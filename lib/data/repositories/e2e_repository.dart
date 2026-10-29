import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../e2e/e2e_crypto.dart';
import '../e2e/e2e_key_store.dart';
import '../e2e/e2e_models.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

enum E2eRegisterResult {
  registered,
  alreadyRegistered,
  modeOff,
  limitReached,
  needsConfirmation,
  needsConnection,
  refused,
}

class E2eRepository extends GetxService {
  E2eRepository(this._keyStore, this._socket, this._session);

  static const _directoryTtl = Duration(minutes: 5);
  static const _labelMax = 60;

  final E2eKeyStore _keyStore;
  final SocketService _socket;
  final SessionStore _session;
  final _crypto = E2eCrypto();

  final mode = ''.obs;
  final maxDevices = 0.obs;
  final myDevices = <E2eDevicePublic>[].obs;
  final deviceId = ''.obs;
  final hasKeys = false.obs;
  final isStatusKnown = false.obs;
  final lastError = ''.obs;

  final _directory = <String, ({List<E2eDevicePublic> devices, DateTime at})>{};
  E2eDeviceKeys? _keys;
  String? _keysScope;
  bool _isKeysLoaded = false;

  String? get _org => _session.orgId;
  String? get _me => _session.userId?.toLowerCase();

  bool get isRegistered =>
      deviceId.value.isNotEmpty && myDevices.any((d) => d.id == deviceId.value);

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    ever(_session.current, (_) => _reset());
  }

  void _reset() {
    _keys = null;
    _keysScope = null;
    _isKeysLoaded = false;
    _directory.clear();
    mode.value = '';
    maxDevices.value = 0;
    myDevices.clear();
    deviceId.value = '';
    hasKeys.value = false;
    isStatusKnown.value = false;
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event' || e['event'] != 'e2e_devices_changed') return;
    final data = e['data'];
    final user = data is Map ? idText(data['user']).toLowerCase() : '';
    if (user.isEmpty) {
      _directory.clear();
      return;
    }
    _directory.remove(user);
    if (user == _me) unawaited(refreshStatus());
  }

  /// This device's keys, read from the key store (never generated here).
  Future<E2eDeviceKeys?> keys() async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return null;
    final scope = '$org|$user';
    if (_isKeysLoaded && _keysScope == scope) return _keys;
    _keys = await _keyStore.load(org, user);
    _keysScope = scope;
    _isKeysLoaded = true;
    hasKeys.value = _keys != null;
    deviceId.value = _keys?.id ?? '';
    return _keys;
  }

  // ---- server, read only -------------------------------------------------

  /// `e2e.status`: the organisation mode, the limit and my registered devices.
  Future<bool> refreshStatus() async {
    await keys();
    if (!_socket.isOnline) return false;
    try {
      final data = await _socket.sdCall('e2e.status', {});
      mode.value = idText(data['mode']);
      maxDevices.value = intOf(data['maxDevices']);
      myDevices.assignAll(_devices(data['devices']));
      isStatusKnown.value = true;
      lastError.value = '';
      return true;
    } on SocketCallError catch (e) {
      lastError.value = 'e2e.status: ${e.code}';
      return false;
    }
  }

  List<E2eDevicePublic> _devices(Object? raw) => [
    for (final d in (raw as List? ?? []).whereType<Map>())
      E2eDevicePublic(
        id: idText(d['id']),
        ecdh: idText(d['ecdh']),
        sign: idText(d['sign']),
        label: idText(d['label']),
        ts: intOf(d['ts']),
      ),
  ];

  /// `e2e.devices` for people, through the 5-minute cache. A user missing from
  /// the result is absent from the map. Throws [SocketCallError] when the
  /// lookup fails.
  Future<Map<String, List<E2eDevicePublic>>> devicesOf(
    List<String> users, {
    bool isForced = false,
  }) async {
    final names = {for (final u in users) u.trim().toLowerCase()};
    final out = <String, List<E2eDevicePublic>>{};
    final missing = <String>[];
    for (final name in names) {
      final hit = _directory[name];
      final isFresh =
          hit != null && DateTime.now().difference(hit.at) < _directoryTtl;
      if (isFresh && !isForced) {
        out[name] = hit.devices;
      } else {
        missing.add(name);
      }
    }
    if (missing.isEmpty) return out;
    final data = await _socket.sdCall('e2e.devices', {'users': missing});
    final listed = (data['users'] as Map?) ?? {};
    for (final name in missing) {
      Object? raw;
      for (final e in listed.entries) {
        if (e.key.toString().toLowerCase() == name) raw = e.value;
      }
      final devices = _devices(raw);
      _directory[name] = (devices: devices, at: DateTime.now());
      out[name] = devices;
    }
    return out;
  }

  /// `e2e.group_devices`: members and their devices. Not cached.
  Future<Map<String, List<E2eDevicePublic>>> groupDevices(String group) async {
    final data = await _socket.sdCall('e2e.group_devices', {'group': group});
    final members = (data['members'] as Map?) ?? {};
    return {
      for (final e in members.entries)
        e.key.toString().toLowerCase(): _devices(e.value),
    };
  }

  // ---- registration, only on an explicit call ----------------------------

  /// Registers this phone. Idempotent: with keys that are already registered
  /// it does nothing. With keys that are not registered it returns
  /// [E2eRegisterResult.needsConfirmation] unless [isConfirmed]. It never
  /// regenerates keys that exist and never removes another device.
  Future<E2eRegisterResult> register(
    String label, {
    bool isConfirmed = false,
  }) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return E2eRegisterResult.refused;
    if (!await refreshStatus()) return E2eRegisterResult.needsConnection;
    if (mode.value == 'off') return E2eRegisterResult.modeOff;
    var keys = await this.keys();
    if (keys != null && isRegistered) {
      return E2eRegisterResult.alreadyRegistered;
    }
    if (keys != null && !isConfirmed) {
      return E2eRegisterResult.needsConfirmation;
    }
    if (myDevices.length >= maxDevices.value && maxDevices.value > 0) {
      return E2eRegisterResult.limitReached;
    }
    final isNew = keys == null;
    if (keys == null) {
      keys = await _crypto.generateDeviceKeys();
      await _keyStore.save(org, user, keys);
      _keys = keys;
      _keysScope = '$org|$user';
      _isKeysLoaded = true;
      hasKeys.value = true;
      deviceId.value = keys.id;
    }
    try {
      final clean = label.replaceAll(RegExp(r'[\u0000-\u001f]'), '').trim();
      await _socket.sdCall('e2e.register', {
        'id': keys.id,
        'ecdh': keys.ecdhPub,
        'sign': keys.signPub,
        'label': clean.length > _labelMax
            ? clean.substring(0, _labelMax)
            : clean,
        'proof': await _crypto.registrationProof(user: user, keys: keys),
      });
    } on SocketCallError catch (e) {
      lastError.value = 'e2e.register: ${e.code} ${e.message}';
      // A definitive refusal leaves no registration, so keys created by this
      // very call are dropped. After a timeout the outcome is unknown: keep
      // them and let the next status say whether the server has the device.
      if (isNew && !e.isConnectionGap) {
        await _keyStore.remove(org, user);
        _keys = null;
        hasKeys.value = false;
        deviceId.value = '';
      }
      await refreshStatus();
      return e.code == 'limit'
          ? E2eRegisterResult.limitReached
          : E2eRegisterResult.refused;
    }
    await refreshStatus();
    return E2eRegisterResult.registered;
  }

  /// "Remove this device": `e2e.remove` for this phone's id only, then its keys.
  Future<bool> removeThisDevice() async {
    final org = _org;
    final user = _me;
    final keys = await this.keys();
    if (org == null || user == null || keys == null) return false;
    try {
      if (isRegistered || !isStatusKnown.value) {
        await _socket.sdCall('e2e.remove', {'id': keys.id});
      }
    } on SocketCallError catch (e) {
      if (e.code != 'not_found') {
        lastError.value = 'e2e.remove: ${e.code}';
        return false;
      }
    }
    await _keyStore.remove(org, user);
    _keys = null;
    hasKeys.value = false;
    deviceId.value = '';
    await refreshStatus();
    return true;
  }

  // ---- reading -----------------------------------------------------------

  /// The label of the conversation [convId] for the envelope check.
  String? expectedConv(String convId) {
    final me = _me;
    if (convId.startsWith('dm:') && me != null) {
      return E2eCrypto.dmLabel(me, convId.substring(3));
    }
    if (convId.startsWith('group:')) {
      return E2eCrypto.groupLabel(convId.substring(6));
    }
    return null;
  }

  /// Opens an envelope that arrived in [convId]. Needs this device's keys and
  /// the sender's signing key from the directory; one directory refresh is
  /// tried before an unknown sender device counts as a failure. A lookup that
  /// cannot reach the server leaves the message pending. [keys] and
  /// [signKeyFor] and [expectConv] replace the stored keys, the directory and
  /// the conversation label (self-test).
  Future<E2eReading> open({
    required String text,
    required String convId,
    String? expectConv,
    E2eDeviceKeys? keys,
    Future<String?> Function(String user, String deviceId)? signKeyFor,
  }) async {
    final own = keys ?? await this.keys();
    if (own == null) return _logged(const E2eReading.cannot('no_device'));
    var isOffline = false;
    Future<String?> lookup(String user, String dev) async {
      if (signKeyFor != null) return signKeyFor(user, dev);
      try {
        for (final isForced in [false, true]) {
          final all = await devicesOf([user], isForced: isForced);
          for (final d in all[user.toLowerCase()] ?? <E2eDevicePublic>[]) {
            if (d.id == dev) return d.sign;
          }
        }
      } on SocketCallError catch (e) {
        if (e.isConnectionGap) isOffline = true;
        rethrow;
      }
      return null;
    }

    try {
      final opened = await _crypto.openEnvelope(
        text: text,
        keys: own,
        signKeyFor: lookup,
        expectConv: expectConv ?? expectedConv(convId),
      );
      return E2eReading.ok(opened.text);
    } on E2eException catch (e) {
      return _logged(E2eReading.cannot(e.code));
    } on SocketCallError catch (e) {
      if (isOffline) return const E2eReading.pending();
      return _logged(E2eReading.cannot('directory_${e.code}'));
    } catch (_) {
      return _logged(const E2eReading.cannot('decrypt_failed'));
    }
  }

  E2eReading _logged(E2eReading reading) {
    if (kDebugMode) debugPrint('e2e: cannot read (${reading.code})');
    return reading;
  }
}
