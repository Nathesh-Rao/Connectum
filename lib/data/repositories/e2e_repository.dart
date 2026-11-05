import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../db/app_database.dart';
import '../e2e/e2e_crypto.dart';
import '../e2e/e2e_device_label.dart';
import '../e2e/e2e_key_store.dart';
import '../e2e/e2e_models.dart';
import '../e2e/e2e_texts.dart';
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

/// Where automatic setup stands. `limit`, `removed` and `refused` need the
/// person; `optedOut` is their own earlier removal of this phone.
enum E2eSetupPhase {
  idle,
  working,
  ready,
  off,
  limit,
  removed,
  optedOut,
  refused,
}

class E2eRepository extends GetxService with WidgetsBindingObserver {
  E2eRepository(
    this._keyStore,
    this._socket,
    this._session,
    this._db, {
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? call,
  }) : _call = call ?? _socket.sdCall;

  static const _directoryTtl = Duration(minutes: 5);

  /// How long a person's device list may serve a send. Short on purpose: a
  /// device added since is caught by the `e2e_devices_changed` event or by the
  /// server's `e2e_stale_devices` refusal, which drops the entry.
  static const sendListTtl = Duration(seconds: 10);
  static const _labelMax = 60;
  static const _pollEvery = Duration(seconds: 60);
  static const _eventDebounce = Duration(seconds: 2);
  static const _rateLimitedTicks = 5;

  final E2eKeyStore _keyStore;
  final SocketService _socket;
  final SessionStore _session;
  final AppDatabase _db;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  _call;
  final _crypto = E2eCrypto();

  final mode = ''.obs;
  final maxDevices = 0.obs;

  /// My devices without the recovery key.
  final myDevices = <E2eDevicePublic>[].obs;
  final isRecoveryOn = false.obs;
  final deviceId = ''.obs;
  final hasKeys = false.obs;
  final isStatusKnown = false.obs;
  final lastError = ''.obs;
  final phase = E2eSetupPhase.idle.obs;
  final issueReason = ''.obs;

  /// This device was added after another one existed (`late` from the
  /// server): earlier messages stay locked until an older device hands them on.
  final isLate = false.obs;

  /// Devices that can show this one the past (`e2e.sync.pending`), valid when
  /// [isHelpersKnown].
  final helpers = <E2eDevicePublic>[].obs;
  final isHelpersKnown = false.obs;

  /// The one-time hint for Chats while late, empty once dismissed.
  final lateHint = ''.obs;

  /// Fires when this device stops being late and the locked messages should be
  /// fetched again.
  Stream<void> get unlockRequests => _unlockRequests.stream;

  /// Fires when this phone has just been registered with the server, so
  /// messages that could not be opened for lack of a device are read again.
  Stream<void> get registrations => _registrations.stream;

  /// A key changed on a message being read, or a known contact added a device.
  Stream<E2eNotice> get notices => _notices.stream;

  /// The one-time notice text, empty once dismissed.
  final notice = ''.obs;

  static const noticeText =
      "Secure messaging is on in this organisation. Older messages can't be read on this phone.";
  static const earlierText =
      ' Earlier installs stay listed until you remove them in Security.';
  static const lateHintText =
      "Your earlier messages aren't shown on this phone yet. See Security.";
  static const readableText =
      'Your earlier messages are now readable on this phone.';
  static const _backoffStart = Duration(minutes: 1);
  static const _backoffCap = Duration(minutes: 30);

  final _unlockRequests = StreamController<void>.broadcast();
  final _registrations = StreamController<void>.broadcast();
  final _notices = StreamController<E2eNotice>.broadcast();
  final _toldKeyChanged = <String>{};
  Timer? _retryTimer;
  Timer? _pollTimer;
  Timer? _eventTimer;
  int _skipTicks = 0;
  bool _isForeground = true;
  Duration _backoff = _backoffStart;
  DateTime _retryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isSetupRunning = false;

  final _directory = <String, ({List<E2eDevicePublic> devices, DateTime at})>{};
  final _lookups = <String, Future<Map<String, dynamic>>>{};
  final _groups =
      <String, ({Map<String, List<E2eDevicePublic>> members, DateTime at})>{};
  E2eDeviceKeys? _keys;
  String? _keysScope;
  bool _isKeysLoaded = false;

  String? get _org => _session.orgId;
  String? get _me => _session.userId?.toLowerCase();

  /// False once setup needs the person (limit, removed, refused, opted out).
  bool get isSettingUp => switch (phase.value) {
    E2eSetupPhase.limit ||
    E2eSetupPhase.removed ||
    E2eSetupPhase.optedOut ||
    E2eSetupPhase.refused => false,
    _ => true,
  };

  bool get isRegistered =>
      deviceId.value.isNotEmpty && myDevices.any((d) => d.id == deviceId.value);

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    _socket.onOnline.listen((_) => unawaited(ensureSetup()));
    ever(_session.current, (_) => _reset());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _pollTimer?.cancel();
    _eventTimer?.cancel();
    _unlockRequests.close();
    _registrations.close();
    _notices.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground && isLate.value) unawaited(_pollOnce());
  }

  void _reset() {
    _keys = null;
    _keysScope = null;
    _isKeysLoaded = false;
    clearDirectory();
    mode.value = '';
    maxDevices.value = 0;
    myDevices.clear();
    isRecoveryOn.value = false;
    deviceId.value = '';
    hasKeys.value = false;
    isStatusKnown.value = false;
    phase.value = E2eSetupPhase.idle;
    issueReason.value = '';
    notice.value = '';
    isLate.value = false;
    helpers.clear();
    isHelpersKnown.value = false;
    lateHint.value = '';
    _pollTimer?.cancel();
    _eventTimer?.cancel();
    _retryTimer?.cancel();
    _backoff = _backoffStart;
    _retryAfter = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event' || e['event'] != 'e2e_devices_changed') return;
    final data = e['data'];
    final user = data is Map ? idText(data['user']).toLowerCase() : '';
    if (user.isEmpty) {
      _directory.clear();
      _lookups.clear();
      return;
    }
    invalidate([user]);
    if (user != _me) return;
    if (phase.value != E2eSetupPhase.ready) {
      unawaited(ensureSetup());
      return;
    }
    // A burst of events (a device finishing, then a removal) is read once.
    _eventTimer?.cancel();
    _eventTimer = Timer(_eventDebounce, () => unawaited(_pollOnce()));
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
    if (_keys != null && await _readLate() == _lateWaiting) {
      isLate.value = true;
      await _loadLateHint();
    }
    return _keys;
  }

  // ---- server, read only -------------------------------------------------

  /// The `e2e.status` arguments: this device's id when there is one, so the
  /// server records "last seen" for it.
  static Map<String, dynamic> statusArgs(String? deviceId) => {
    if (deviceId != null && deviceId.isNotEmpty) 'id': deviceId,
  };

  /// The `e2e.status` arguments for this phone.
  Future<Map<String, dynamic>> currentStatusArgs() async =>
      statusArgs((await keys())?.id);

  /// Drops every cached and in-flight device list (sign-out, organisation
  /// switch, `session_replaced`).
  void clearDirectory() {
    _directory.clear();
    _groups.clear();
    _lookups.clear();
  }

  /// `e2e.status`: the organisation mode, the limit and my registered devices.
  Future<bool> refreshStatus() async {
    await keys();
    if (!_socket.isOnline) return false;
    try {
      final data = await _call('e2e.status', statusArgs(_keys?.id));
      mode.value = idText(data['mode']);
      maxDevices.value = intOf(data['maxDevices']);
      final all = _devices(data['devices']);
      myDevices.assignAll(all.where((d) => !d.isRecovery));
      isRecoveryOn.value =
          data['recovery'] == true || all.any((d) => d.isRecovery);
      isStatusKnown.value = true;
      lastError.value = '';
      unawaited(_saveStatus());
      await _applyLate(all);
      return true;
    } on SocketCallError catch (e) {
      lastError.value = 'e2e.status: ${e.code}';
      return false;
    }
  }

  String get _statusKey => 'e2e.status.$_org.$_me';

  /// Public facts only (labels, ids, dates), kept so the Security screen has
  /// something to show offline.
  Future<void> _saveStatus() => _session.writeValue(
    _statusKey,
    jsonEncode({
      'mode': mode.value,
      'max': maxDevices.value,
      'recovery': isRecoveryOn.value,
      'devices': [
        for (final d in myDevices)
          {'id': d.id, 'label': d.label, 'ts': d.ts, 'seen': d.seen},
      ],
    }),
  );

  /// The last status read, or null. Never touches the network.
  Future<
    ({String mode, int max, bool isRecovery, List<E2eDevicePublic> devices})?
  >
  readSavedStatus() async {
    try {
      final raw = await _session.readValue(_statusKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        mode: idText(json['mode']),
        max: intOf(json['max']),
        isRecovery: json['recovery'] == true,
        devices: [
          for (final d in (json['devices'] as List? ?? []).whereType<Map>())
            E2eDevicePublic(
              id: idText(d['id']),
              ecdh: '',
              sign: '',
              label: idText(d['label']),
              ts: intOf(d['ts']),
              seen: intOf(d['seen']),
            ),
        ],
      );
    } catch (_) {
      return null;
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
        seen: intOf(d['seen']),
        isRecovery: d['recovery'] == true,
        isLate: d['late'] == true,
      ),
  ];

  // ---- late device: the past is not shown here yet -------------------------

  static const _lateWaiting = '1';
  static const _lateUnlock = '2';
  static const _hintDone = 'done';

  String get _lateKey => 'e2e.late.$_org.$_me';
  String get _hintKey => 'e2e.latehint.$_org.$_me';

  /// Local mark per organisation and user, kept across restarts and sessions:
  /// `1` while waiting, `2` once the locked messages still have to be fetched
  /// again, empty otherwise. Never removed with the keys or the session.
  Future<String> _readLate() async => await _session.readValue(_lateKey) ?? '';

  Future<void> _writeLate(String value) => _session.writeValue(_lateKey, value);

  Future<void> _loadLateHint() async {
    final isDone = await _session.readValue(_hintKey) == _hintDone;
    lateHint.value = isDone ? '' : lateHintText;
  }

  Future<void> dismissLateHint() async {
    lateHint.value = '';
    await _session.writeValue(_hintKey, _hintDone);
  }

  /// Reads `late` for this device from a status list. Becoming late starts
  /// the slow poll; stopping asks for the locked messages to be fetched again
  /// (once, remembered across restarts until that finished).
  Future<void> _applyLate(List<E2eDevicePublic> all) async {
    final own = all.where((d) => d.id == deviceId.value).firstOrNull;
    if (own == null) return;
    final mark = await _readLate();
    if (own.isLate && mode.value != 'off') {
      isLate.value = true;
      if (mark != _lateWaiting) await _writeLate(_lateWaiting);
      await _loadLateHint();
      _startPolling();
      return;
    }
    isLate.value = false;
    helpers.clear();
    isHelpersKnown.value = false;
    lateHint.value = '';
    _pollTimer?.cancel();
    if (mark.isEmpty) return;
    if (mark == _lateWaiting) {
      await _writeLate(_lateUnlock);
      await _session.writeValue(_hintKey, '');
    }
    if (!_unlockRequests.isClosed) _unlockRequests.add(null);
  }

  /// The locked messages were fetched again (completely or as far as the
  /// server allows): the mark goes. [readable] is how many opened.
  Future<void> finishUnlock({required int readable}) async {
    await _writeLate('');
    if (readable > 0) notice.value = readableText;
  }

  void _startPolling() {
    if (_pollTimer?.isActive ?? false) return;
    unawaited(refreshPending());
    _pollTimer = Timer.periodic(_pollEvery, (_) => unawaited(_pollOnce()));
  }

  /// One slow-poll step: the status (late may have ended) and the helpers. Only
  /// in the foreground, only while late; a rate limit skips the next ticks.
  Future<void> _pollOnce() async {
    if (!_isForeground || !_socket.isOnline) return;
    if (_skipTicks > 0) {
      _skipTicks--;
      return;
    }
    if (!await refreshStatus() || !isLate.value) return;
    await refreshPending();
  }

  /// `e2e.sync.pending` on a late device: which devices can show it the past.
  Future<void> refreshPending() async {
    if (!_socket.isOnline || !isLate.value) return;
    try {
      final data = await _socket.sdCall('e2e.sync.pending', {});
      helpers.assignAll(_devices(data['helpers']));
      isHelpersKnown.value = true;
    } on SocketCallError catch (e) {
      lastError.value = 'e2e.sync.pending: ${e.code}';
      if (e.code == 'rate_limited') _skipTicks = _rateLimitedTicks;
    }
  }

  /// The devices that can read now: the list without the recovery key.
  static List<E2eDevicePublic> readers(List<E2eDevicePublic> all) => [
    for (final d in all)
      if (!d.isRecovery) d,
  ];

  /// `e2e.devices` for people, through the cache: an entry younger than
  /// [maxAge] (default 5 minutes) is reused, [isForced] always asks. Lookups
  /// for the same person that overlap share one request. A user missing from
  /// the result is absent from the map. Throws [SocketCallError] when the
  /// lookup fails.
  Future<Map<String, List<E2eDevicePublic>>> devicesOf(
    List<String> users, {
    bool isForced = false,
    Duration maxAge = _directoryTtl,
  }) async {
    final names = {for (final u in users) u.trim().toLowerCase()};
    final out = <String, List<E2eDevicePublic>>{};
    final waits = <Future<Map<String, dynamic>>>[];
    final missing = <String>[];
    for (final name in names) {
      final hit = _directory[name];
      if (!isForced &&
          hit != null &&
          DateTime.now().difference(hit.at) < maxAge) {
        out[name] = hit.devices;
      } else if (!isForced && _lookups[name] != null) {
        waits.add(_lookups[name]!);
      } else {
        missing.add(name);
      }
    }
    if (missing.isNotEmpty) {
      final done = Completer<Map<String, dynamic>>();
      done.future.ignore();
      for (final name in missing) {
        _lookups[name] = done.future;
      }
      waits.add(done.future);
      unawaited(_fetchDevices(missing, done));
    }
    for (final wait in waits) {
      await wait;
    }
    final dropped = <String>[];
    for (final name in names) {
      if (out.containsKey(name)) continue;
      final hit = _directory[name];
      if (hit == null) {
        dropped.add(name);
      } else {
        out[name] = hit.devices;
      }
    }
    // A list dropped while its request was in flight is asked for again.
    if (dropped.isNotEmpty) {
      out.addAll(await devicesOf(dropped, isForced: true));
    }
    return out;
  }

  Future<void> _fetchDevices(
    List<String> names,
    Completer<Map<String, dynamic>> done,
  ) async {
    try {
      final data = await _call('e2e.devices', {'users': names});
      final listed = (data['users'] as Map?) ?? {};
      for (final name in names) {
        if (!identical(_lookups[name], done.future)) continue;
        Object? raw;
        for (final e in listed.entries) {
          if (e.key.toString().toLowerCase() == name) raw = e.value;
        }
        _directory[name] = (devices: _devices(raw), at: DateTime.now());
      }
      done.complete(data);
    } catch (e, st) {
      done.completeError(e, st);
    } finally {
      for (final name in names) {
        if (identical(_lookups[name], done.future)) _lookups.remove(name);
      }
    }
  }

  /// The directory entries when every one of [users] is still fresh, else
  /// null. Never touches the network.
  Map<String, List<E2eDevicePublic>>? cachedDevices(List<String> users) {
    final out = <String, List<E2eDevicePublic>>{};
    for (final name in {for (final u in users) u.trim().toLowerCase()}) {
      final hit = _directory[name];
      if (hit == null || DateTime.now().difference(hit.at) >= _directoryTtl) {
        return null;
      }
      out[name] = hit.devices;
    }
    return out;
  }

  void invalidate(Iterable<String> users) {
    for (final u in users) {
      final name = u.trim().toLowerCase();
      _directory.remove(name);
      _lookups.remove(name);
    }
  }

  // ---- pins (trust on first use) -------------------------------------------

  /// Devices of [current] whose id is pinned with other keys. Pure.
  static List<E2eDevicePublic> pinMismatches(
    Map<String, ({String ecdh, String sign})> pinned,
    List<E2eDevicePublic> current,
  ) => [
    for (final d in current)
      if (pinned[d.id] != null &&
          (pinned[d.id]!.ecdh != d.ecdh || pinned[d.id]!.sign != d.sign))
        d,
  ];

  /// Compares each listed device with its pin. With [isRecord] a device seen
  /// for the first time is pinned. A changed key is returned, never replaced:
  /// only [trust] replaces a pin.
  Future<List<E2ePinChange>> checkPins(
    Map<String, List<E2eDevicePublic>> byUser, {
    required bool isRecord,
  }) async {
    final org = _org;
    final scopeUser = _session.userId;
    if (org == null || scopeUser == null) return const [];
    final rows = await _db.query(
      'SELECT device_user, device_id, ecdh, sign FROM e2e_pins WHERE org_id = ? AND user_id = ?',
      [org, scopeUser],
    );
    final pinned = <String, Map<String, ({String ecdh, String sign})>>{};
    for (final r in rows) {
      pinned.putIfAbsent(idText(r['device_user']), () => {})[idText(
        r['device_id'],
      )] = (
        ecdh: idText(r['ecdh']),
        sign: idText(r['sign']),
      );
    }
    final changes = <E2ePinChange>[];
    for (final entry in byUser.entries) {
      final known = pinned[entry.key] ?? const {};
      for (final d in pinMismatches(known, entry.value)) {
        changes.add(E2ePinChange(user: entry.key, device: d));
      }
      if (!isRecord) continue;
      final fresh = entry.value.where((d) => !known.containsKey(d.id)).toList();
      // Told once: a person this phone already knew gets a device it has not
      // seen. Never the first time somebody is seen, never my own devices,
      // never a recovery key.
      final added = fresh.where((d) => !d.isRecovery).toList();
      if (known.isNotEmpty && added.isNotEmpty && entry.key != _me) {
        _notices.add(
          E2eNotice.newDevice(entry.key, [
            for (final d in added)
              if (d.label.isNotEmpty) d.label,
          ]),
        );
      }
      for (final d in fresh) {
        await _db.insert(
          'INSERT OR IGNORE INTO e2e_pins(org_id, user_id, device_user, device_id, ecdh, sign, first_ts) '
          'VALUES(?,?,?,?,?,?,?)',
          [
            org,
            scopeUser,
            entry.key,
            d.id,
            d.ecdh,
            d.sign,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
      }
    }
    return changes;
  }

  /// What the key-changed sheet shows: a fresh directory read, the devices
  /// whose key differs from the pin, and the safety number for the pair.
  Future<E2eKeyReview> reviewKeys(String peer, {String? group}) async {
    final me = _me ?? '';
    final name = peer.trim().toLowerCase();
    final devices = group == null
        ? await devicesOf([name, me], isForced: true)
        : {
            for (final e in (await groupDevices(group)).entries)
              if (e.key == name || e.key == me) e.key: e.value,
          };
    final changed = await checkPins(devices, isRecord: false);
    return E2eKeyReview(
      user: name,
      safetyNumber: await _crypto.safetyNumber(
        devices[me] ?? const [],
        devices[name] ?? const [],
      ),
      devices: devices,
      changed: changed,
    );
  }

  /// "Trust new key": pins the keys the person was shown and records when.
  Future<void> trust(E2eKeyReview review) async {
    final org = _org;
    final scopeUser = _session.userId;
    if (org == null || scopeUser == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in review.changed) {
      await _db.update(
        'UPDATE e2e_pins SET ecdh = ?, sign = ?, trusted_ts = ? '
        'WHERE org_id = ? AND user_id = ? AND device_user = ? AND device_id = ?',
        [
          c.device.ecdh,
          c.device.sign,
          now,
          org,
          scopeUser,
          c.user,
          c.device.id,
        ],
      );
      if (kDebugMode) {
        debugPrint('e2e: trusted new key for ${c.user} device ${c.device.id}');
      }
    }
  }

  // ---- sending -----------------------------------------------------------

  /// The envelope for [text], wrapped for every device in [decision] (the
  /// peer's and all of mine). Called only for an encrypt verdict.
  Future<String> seal(
    E2eSendDecision decision,
    String convId,
    String text,
  ) async {
    final keys = decision.keys;
    final user = _me;
    final conv = expectedConv(convId);
    if (!decision.isEncrypt || keys == null || user == null || conv == null) {
      throw const E2eException('not_sealable', 'nothing to encrypt for');
    }
    final byId = {for (final d in decision.recipients) d.id: d};
    return _crypto.buildEnvelope(
      user: user,
      keys: keys,
      conv: conv,
      recipients: byId.values.toList(),
      text: text,
    );
  }

  /// `e2e.group_devices`: every member (me included) and their devices, from
  /// the server every time. It also refreshes the per-person directory, so a
  /// sender's signing key is found for reading. Throws [SocketCallError].
  Future<Map<String, List<E2eDevicePublic>>> groupDevices(String group) async {
    final data = await _socket.sdCall('e2e.group_devices', {'group': group});
    final members = (data['members'] as Map?) ?? {};
    final out = {
      for (final e in members.entries)
        e.key.toString().toLowerCase(): _devices(e.value),
    };
    final now = DateTime.now();
    for (final e in out.entries) {
      _directory[e.key] = (devices: e.value, at: now);
    }
    _groups[group.trim().toLowerCase()] = (members: out, at: now);
    return out;
  }

  /// The last group list when it is still fresh, else null. For the composer
  /// only: a send always asks the server. Never touches the network.
  Map<String, List<E2eDevicePublic>>? cachedGroupDevices(String group) {
    final hit = _groups[group.trim().toLowerCase()];
    if (hit == null || DateTime.now().difference(hit.at) >= _directoryTtl) {
      return null;
    }
    return hit.members;
  }

  void invalidateGroup(String group) =>
      _groups.remove(group.trim().toLowerCase());

  // ---- automatic setup -----------------------------------------------------

  String get _stateKey => 'e2e.state.$_org.$_me';
  String get _noticeKey => noticeKeyFor(_org, _me);

  static String noticeKeyFor(String? org, String? user) =>
      'e2e.notice.$org.${user?.toLowerCase()}';

  /// Local mark per organisation and user: `on` (set up), `pending` (a
  /// registration was started with the stored keys), `out` (the person removed
  /// this phone, so nothing registers it again by itself) or empty.
  Future<String> _readState() async =>
      await _session.readValue(_stateKey) ?? '';

  Future<void> _writeState(String value) =>
      _session.writeValue(_stateKey, value);

  /// Brings this phone to a registered state without the person's help
  /// whenever the organisation uses secure messaging. Runs in the background
  /// on every socket-online event; reads `e2e.status` first and changes
  /// nothing when the mode is off or this phone is already listed. Keys that
  /// exist are never regenerated here.
  Future<void> ensureSetup() async {
    if (_isSetupRunning || _org == null || _me == null) return;
    if (!_socket.isOnline || DateTime.now().isBefore(_retryAfter)) return;
    _isSetupRunning = true;
    final scope = _keysScope;
    try {
      if (phase.value != E2eSetupPhase.ready) {
        phase.value = E2eSetupPhase.working;
      }
      if (!await refreshStatus()) {
        if (phase.value == E2eSetupPhase.working) {
          phase.value = E2eSetupPhase.idle;
        }
        return;
      }
      await _loadNotice();
      if (mode.value == 'off' || mode.value.isEmpty) {
        phase.value = E2eSetupPhase.off;
        return;
      }
      final stored = await keys();
      final state = await _readState();
      if (stored != null && isRegistered) {
        if (state != 'on') await _writeState('on');
        _settle();
        return;
      }
      if (stored != null && state != 'pending') {
        _raise(E2eSetupPhase.removed);
        return;
      }
      if (stored == null && state == 'out') {
        phase.value = E2eSetupPhase.optedOut;
        return;
      }
      await _registerThisPhone(isReplacing: false);
    } finally {
      _isSetupRunning = false;
      if (scope != _keysScope) phase.value = E2eSetupPhase.idle;
    }
  }

  /// "Set up again" and "Retry": registers with new keys. The old keys are
  /// replaced only once the server has accepted the new device.
  Future<void> setUpAgain() async {
    if (_isSetupRunning || _org == null || _me == null) return;
    _isSetupRunning = true;
    try {
      phase.value = E2eSetupPhase.working;
      _retryAfter = DateTime.fromMillisecondsSinceEpoch(0);
      await _registerThisPhone(isReplacing: _keys != null);
    } finally {
      _isSetupRunning = false;
    }
  }

  Future<void> _registerThisPhone({required bool isReplacing}) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    // Look at the server list again right before registering.
    if (!await refreshStatus()) {
      phase.value = E2eSetupPhase.idle;
      return;
    }
    if (isReplacing && isRegistered) {
      _settle();
      return;
    }
    if (maxDevices.value > 0 && myDevices.length >= maxDevices.value) {
      _raise(E2eSetupPhase.limit);
      return;
    }
    final label = await E2eDeviceLabel.current();
    final hasEarlier = myDevices.any(
      (d) => d.label.trim().toLowerCase() == label.toLowerCase(),
    );
    final fresh = isReplacing || _keys == null
        ? await _crypto.generateDeviceKeys()
        : _keys!;
    if (!isReplacing && _keys == null) {
      await _keyStore.save(org, user, fresh);
      _keys = fresh;
      _keysScope = '$org|$user';
      _isKeysLoaded = true;
      hasKeys.value = true;
      deviceId.value = fresh.id;
    }
    await _writeState('pending');
    try {
      await _socket.sdCall('e2e.register', {
        'id': fresh.id,
        'ecdh': fresh.ecdhPub,
        'sign': fresh.signPub,
        'label': label,
        'proof': await _crypto.registrationProof(user: user, keys: fresh),
      });
    } on SocketCallError catch (e) {
      lastError.value = 'e2e.register: ${e.code} ${e.message}';
      if (e.isConnectionGap) {
        phase.value = E2eSetupPhase.idle;
        return;
      }
      // A definitive refusal leaves no registration.
      if (!isReplacing && _keys != null && _keys!.id == fresh.id) {
        await _keyStore.remove(org, user);
        _keys = null;
        hasKeys.value = false;
        deviceId.value = '';
      }
      await _writeState(isReplacing ? 'on' : '');
      if (e.code == 'rate_limited') {
        _retryAfter = DateTime.now().add(_backoff);
        _retryTimer?.cancel();
        _retryTimer = Timer(_backoff, () => unawaited(ensureSetup()));
        _backoff = _backoff * 2 > _backoffCap ? _backoffCap : _backoff * 2;
        phase.value = E2eSetupPhase.idle;
        return;
      }
      if (e.code == 'limit') {
        await refreshStatus();
        _raise(E2eSetupPhase.limit);
        return;
      }
      _raise(
        E2eSetupPhase.refused,
        reason: E2eTexts.registrationFailure(
          e.code,
          e.message,
          maxDevices.value,
        ),
      );
      return;
    }
    if (isReplacing) {
      await _keyStore.save(org, user, fresh);
      _keys = fresh;
      _keysScope = '$org|$user';
      _isKeysLoaded = true;
      hasKeys.value = true;
      deviceId.value = fresh.id;
    }
    await _writeState('on');
    _backoff = _backoffStart;
    _directory.remove(user);
    await refreshStatus();
    if (!isReplacing) {
      final text = hasEarlier ? 'earlier' : 'plain';
      await _session.writeValue(_noticeKey, text);
      await _loadNotice();
    }
    if (!_registrations.isClosed) _registrations.add(null);
    _settle();
  }

  void _settle() {
    issueReason.value = '';
    phase.value = E2eSetupPhase.ready;
  }

  void _raise(E2eSetupPhase next, {String reason = ''}) {
    issueReason.value = reason;
    phase.value = next;
  }

  Future<void> _loadNotice() async {
    final raw = await _session.readValue(_noticeKey) ?? '';
    notice.value = raw.isEmpty
        ? ''
        : raw == 'earlier'
        ? '$noticeText$earlierText'
        : noticeText;
  }

  Future<void> dismissNotice() async {
    notice.value = '';
    await _session.writeValue(_noticeKey, '');
  }

  /// `e2e.remove` for [id]. When it is this phone, the keys go too and the
  /// phone stays off until the person sets it up again.
  Future<bool> removeDevice(String id) async {
    final own = _keys?.id ?? deviceId.value;
    if (id == own) {
      // Marked first: the server's "devices changed" push must not set the
      // phone up again.
      final before = await _readState();
      await _writeState('out');
      final isOk = await removeThisDevice();
      if (isOk) {
        phase.value = E2eSetupPhase.optedOut;
      } else {
        await _writeState(before);
      }
      return isOk;
    }
    try {
      await _socket.sdCall('e2e.remove', {'id': id});
    } on SocketCallError catch (e) {
      if (e.code != 'not_found') {
        lastError.value = 'e2e.remove: ${e.code}';
        return false;
      }
    }
    await refreshStatus();
    return true;
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
    _directory.remove(user);
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
    _directory.remove(user);
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
    Future<E2eDevicePublic?> Function(String user, String deviceId)? deviceFor,
    Map<String, ({String ecdh, String sign})>? testPins,
  }) async {
    final own = keys ?? await this.keys();
    if (own == null) return _logged(const E2eReading.cannot('no_device'));
    var isOffline = false;
    final group = convId.startsWith('group:') ? convId.substring(6) : null;
    Future<String?> lookup(String user, String dev) async {
      if (signKeyFor != null) return signKeyFor(user, dev);
      if (deviceFor != null) {
        final d = await deviceFor(user, dev);
        if (d == null) return null;
        await _requireUnchangedKey(user, d, testPins: testPins);
        return d.sign;
      }
      try {
        for (final isForced in [false, true]) {
          // A group sender is looked up through the group list.
          final all = group != null
              ? (isForced
                    ? await groupDevices(group)
                    : cachedDevices([user]) ?? const {})
              : await devicesOf([user], isForced: isForced);
          for (final d in all[user.toLowerCase()] ?? <E2eDevicePublic>[]) {
            if (d.id == dev) {
              await _requireUnchangedKey(user, d);
              return d.sign;
            }
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

  /// The web's rule on reading (`#signKeyFor`): the sender device's keys must
  /// equal its pin. A device seen for the first time is pinned; a changed key
  /// refuses the message (`key_changed`) and leaves the pin as it is. With
  /// [testPins] the pins are that map and nothing is stored.
  Future<void> _requireUnchangedKey(
    String user,
    E2eDevicePublic d, {
    Map<String, ({String ecdh, String sign})>? testPins,
  }) async {
    final name = user.trim().toLowerCase();
    final List<E2ePinChange> changed;
    if (testPins != null) {
      final bad = pinMismatches(testPins, [d]);
      testPins.putIfAbsent(d.id, () => (ecdh: d.ecdh, sign: d.sign));
      changed = [for (final x in bad) E2ePinChange(user: name, device: x)];
    } else {
      changed = await checkPins({
        name: [d],
      }, isRecord: true);
    }
    if (changed.isEmpty) return;
    if (_toldKeyChanged.add('$name|${d.id}')) {
      _notices.add(E2eNotice.keyChanged(name));
    }
    throw const E2eException('key_changed', "the sender's key changed");
  }

  E2eReading _logged(E2eReading reading) {
    if (kDebugMode) debugPrint('e2e: cannot read (${reading.code})');
    return reading;
  }

  // ---- attachments ------------------------------------------------------

  /// A fresh key and iv for each file; the blob is `ciphertext || tag`.
  Future<E2eEncryptedFile> encryptFile(List<int> bytes) =>
      _crypto.encryptFile(bytes);

  /// Throws [E2eException] `file_decrypt_failed` for a wrong key, a damaged
  /// or a short blob.
  Future<Uint8List> decryptFile(List<int> blob, String key, String iv) =>
      _crypto.decryptFile(blob, key, iv);
}
