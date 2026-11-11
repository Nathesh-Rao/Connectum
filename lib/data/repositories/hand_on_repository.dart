import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../e2e/e2e_models.dart';
import '../e2e/hand_on.dart';
import '../e2e/hand_on_job.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'e2e_repository.dart';

enum HandOnPhase {
  idle,
  offered,
  checking,
  preparing,
  sending,
  paused,
  done,
  failed,
  cancelled,
  gone,
}

/// A waiting device of this person that this phone could show the past to.
/// [name] is already plain text (control characters out, 60 characters).
class HandOnOffer {
  const HandOnOffer({
    required this.id,
    required this.name,
    required this.ts,
    required this.isContinue,
  });

  final String id;
  final String name;
  final int ts;

  /// An earlier run stopped part way: approving continues it.
  final bool isContinue;
}

/// The older-device side of the history hand-on (`e2e.sync.*`): finds a device
/// of this person that is waiting for its past, offers it, and on Approve
/// makes and uploads the boxes. Nothing starts without a tap on this phone.
class HandOnRepository extends GetxService with WidgetsBindingObserver {
  HandOnRepository(
    this._e2e,
    this._socket,
    this._session, {
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? call,
  }) : _call = call ?? _socket.sdCall;

  static const _discoverDebounce = Duration(seconds: 3);
  static const _noHistoryFor = Duration(minutes: 10);

  static const doneText = 'Your earlier messages are now on';
  static const connectionText =
      'Waiting for a connection. It carries on from where it stopped.';
  static const keyChangedText =
      "This device's security key changed. Check it in Security before showing it your messages.";
  static const unverifiedText =
      "Couldn't check that device with the server. Try again in a moment.";
  static const goneText =
      'That device is no longer waiting. It may have been removed, finished by another device, or not used for 30 days.';

  final E2eRepository _e2e;
  final SocketService _socket;
  final SessionStore _session;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  _call;
  final _pacer = HandOnPacer();

  final phase = HandOnPhase.idle.obs;
  final offer = Rxn<HandOnOffer>();
  final progress = const HandOnProgress().obs;

  /// Why the run stopped or paused, empty otherwise.
  final message = ''.obs;
  final isRetryable = false.obs;

  /// Worker isolate for the cryptography. Off only for the benchmark.
  bool isIsolateOn = true;
  bool _isIsolateBroken = false;

  /// Waiting devices not to offer again in this run of the app (Later, done,
  /// gone).
  final _handled = <String>{};
  final _noHistory = <String, DateTime>{};
  Timer? _debounce;
  HandOnJob? _job;
  Uint8List? _keyBytes;
  bool _isDiscovering = false;
  bool _isAutoResume = false;
  bool _isForeground = true;

  String? get _org => _session.orgId;
  String? get _me => _session.userId?.toLowerCase();

  bool get isRunning => switch (phase.value) {
    HandOnPhase.checking ||
    HandOnPhase.preparing ||
    HandOnPhase.sending => true,
    _ => false,
  };

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    _socket.listenOnline('hand on', () {
      _schedule();
      if (phase.value == HandOnPhase.paused && _isAutoResume) {
        return _begin(isFirst: false);
      }
    });
    ever(_session.current, (_) => _reset());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _job?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) _schedule();
  }

  void _reset() {
    _debounce?.cancel();
    _job?.cancel();
    _job = null;
    _wipeKey();
    _handled.clear();
    _noHistory.clear();
    _isAutoResume = false;
    offer.value = null;
    progress.value = const HandOnProgress();
    message.value = '';
    isRetryable.value = false;
    phase.value = HandOnPhase.idle;
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event' || e['event'] != 'e2e_devices_changed') return;
    final data = e['data'];
    final user = data is Map ? idText(data['user']).toLowerCase() : '';
    if (user.isEmpty || user == _me) _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_discoverDebounce, () => unawaited(discover()));
  }

  // ---- finding a waiting device ----------------------------------------

  /// Looks for a waiting device and, when this phone has history to give it,
  /// raises the offer. Read only: the one `e2e.sync.page` probe below reads the
  /// person's own history the way the hand-on later does.
  Future<void> discover() async {
    if (_isDiscovering || !_isForeground || !_socket.isOnline) return;
    if (isRunning || phase.value == HandOnPhase.paused) return;
    _isDiscovering = true;
    try {
      if (!await _e2e.refreshStatus()) return;
      final keys = await _e2e.keys();
      if (keys == null ||
          _e2e.mode.value == 'off' ||
          !_e2e.isRegistered ||
          _e2e.isLate.value) {
        _dropOffer();
        return;
      }
      final waiting = await _waiting();
      if (waiting == null) return;
      final shown = offer.value;
      if (shown != null && !waiting.any((d) => d.id == shown.id)) {
        _handled.add(shown.id);
        offer.value = null;
        phase.value = HandOnPhase.gone;
        message.value = goneText;
        return;
      }
      if (shown != null) return;
      final next = waiting
          .where(
            (d) =>
                d.id != keys.id && isDeviceId(d.id) && !_handled.contains(d.id),
          )
          .firstOrNull;
      if (next == null) return;
      final skipUntil = _noHistory[next.id];
      if (skipUntil != null && DateTime.now().isBefore(skipUntil)) return;
      final target = await _verify(next.id);
      if (target == null) return;
      final checkpoint = await _loadCheckpoint(next.id);
      if (checkpoint == null && !await _hasHistoryToGive(next.id, keys.id)) {
        _noHistory[next.id] = DateTime.now().add(_noHistoryFor);
        return;
      }
      offer.value = HandOnOffer(
        id: next.id,
        name: handOnDeviceName(next.label),
        ts: next.ts,
        isContinue: checkpoint != null,
      );
      phase.value = HandOnPhase.offered;
    } on HandOnFailure {
      // Not verified or key changed: no offer. The reason is shown only when
      // the person presses Approve.
    } on SocketCallError {
      // Offline or limited: the next event or resume asks again.
    } finally {
      _isDiscovering = false;
    }
  }

  void _dropOffer() {
    if (offer.value == null || isRunning) return;
    offer.value = null;
    phase.value = HandOnPhase.idle;
  }

  /// `waiting` from `e2e.sync.pending`, or null when it cannot be read.
  Future<List<E2eDevicePublic>?> _waiting() async {
    try {
      final data = await _call('e2e.sync.pending', {});
      return [
        for (final d in (data['waiting'] as List? ?? []).whereType<Map>())
          E2eDevicePublic(
            id: idText(d['id']),
            ecdh: '',
            sign: '',
            label: idText(d['label']),
            ts: intOf(d['ts']),
          ),
      ];
    } on SocketCallError {
      return null;
    }
  }

  /// Reads up to [HandOnLimits.probePages] pages for one envelope this phone
  /// can give a box for. Reaching the end with none: nothing to give. Not
  /// reaching the end: assume there is.
  Future<bool> _hasHistoryToGive(String targetId, String deviceId) async {
    Object? cursor;
    for (var i = 0; i < HandOnLimits.probePages; i++) {
      await _pace('e2e.sync.page');
      final Map<String, dynamic> page;
      try {
        page = await _call('e2e.sync.page', {'cursor': ?cursor});
      } on SocketCallError {
        return false;
      }
      final texts = [
        for (final item in (page['items'] as List? ?? []).whereType<Map>())
          if (item['text'] is String) item['text'] as String,
      ];
      final scan = HandOnScan.of(texts, deviceId: deviceId, targetId: targetId);
      if (scan.candidates > 0) return true;
      cursor = page['next'];
      if (cursor == null) return false;
    }
    return true;
  }

  Future<void> _pace(String action) async {
    for (var d = _pacer.waitFor(action); d > Duration.zero;) {
      await Future<void>.delayed(d);
      d = _pacer.waitFor(action);
    }
    _pacer.record(action);
  }

  // ---- the gate ------------------------------------------------------------

  /// Everything that must hold before anything is sent for [id]: it is in a
  /// fresh `e2e.sync.pending.waiting`, late in a fresh `e2e.status`, listed
  /// with the same public key in a fresh `e2e.devices` for this person, is not
  /// the recovery key and not this phone, and its key still matches the pin
  /// when one exists (read only, nothing is pinned here). Returns the device
  /// as the server lists it now, or null when the server cannot be asked.
  Future<E2eDevicePublic?> _verify(String id) async {
    final me = _me;
    final own = await _e2e.keys();
    if (me == null || own == null || id == own.id || !isDeviceId(id)) {
      return null;
    }
    final waiting = await _waiting();
    if (waiting == null) return null;
    if (!waiting.any((d) => d.id == id)) {
      throw HandOnFailure.fromCode('not_waiting');
    }
    if (!await _e2e.refreshStatus()) return null;
    final status = _e2e.myDevices.where((d) => d.id == id).firstOrNull;
    if (status == null) throw HandOnFailure.fromCode('not_found');
    if (!status.isLate) throw HandOnFailure.fromCode('not_waiting');
    await _pace('e2e.devices');
    final Map<String, List<E2eDevicePublic>> lookup;
    try {
      lookup = await _e2e.devicesOf([me], isForced: true);
    } on SocketCallError {
      return null;
    }
    final target = (lookup[me] ?? const <E2eDevicePublic>[])
        .where((d) => d.id == id)
        .firstOrNull;
    if (target == null) throw HandOnFailure.fromCode('not_found');
    if (target.isRecovery ||
        target.ecdh.isEmpty ||
        target.ecdh != status.ecdh) {
      throw HandOnFailure.fromCode('not_found');
    }
    final changed = await _e2e.checkPins({
      me: [target],
    }, isRecord: false);
    if (changed.isNotEmpty) {
      throw const HandOnFailure(HandOnFailureKind.keyChanged, keyChangedText);
    }
    return target;
  }

  // ---- the person's choices -------------------------------------------------

  /// "Later": no offer for this device until the app is opened again.
  void later() {
    final id = offer.value?.id;
    if (id != null) _handled.add(id);
    offer.value = null;
    phase.value = HandOnPhase.idle;
  }

  /// Back to idle once the person has seen the end of a run. A device left
  /// unfinished (failed, stopped) is offered again by the next check.
  void close() {
    offer.value = null;
    message.value = '';
    isRetryable.value = false;
    progress.value = const HandOnProgress();
    phase.value = HandOnPhase.idle;
  }

  /// The tap on Approve (or Continue, or Try again): the only way a run
  /// starts.
  Future<void> approve() async {
    if (offer.value == null || isRunning) return;
    await _begin(isFirst: true);
  }

  Future<void> retry() => approve();

  /// Stop. Boxes already sent stay; the device stays waiting; no `done`.
  void cancel() {
    final job = _job;
    if (job != null) {
      job.cancel();
      return;
    }
    if (phase.value != HandOnPhase.paused) return;
    _isAutoResume = false;
    _wipeKey();
    phase.value = HandOnPhase.cancelled;
  }

  Future<void> _begin({required bool isFirst}) async {
    final o = offer.value;
    if (o == null || isRunning) return;
    message.value = '';
    isRetryable.value = false;
    phase.value = HandOnPhase.checking;
    try {
      final target = await _verify(o.id);
      if (target == null) {
        _fail(
          const HandOnFailure(
            HandOnFailureKind.unknown,
            unverifiedText,
            isRetryable: true,
          ),
        );
        return;
      }
      if (isFirst) await _approved(o.id);
      await _run(target);
    } on HandOnFailure catch (f) {
      _fail(f);
    } on SocketCallError catch (e) {
      if (e.isConnectionGap) {
        _pause();
      } else {
        _fail(HandOnFailure.fromCode(e.code));
      }
    }
  }

  /// `e2e.sync.approved`: an optional record that the person pressed Approve.
  /// Its errors are ignored.
  Future<void> _approved(String id) async {
    try {
      await _pace('e2e.sync.approved');
      await _call('e2e.sync.approved', {'device': id});
    } on SocketCallError {
      // optional
    }
  }

  Future<void> _run(E2eDevicePublic target) async {
    final keys = await _e2e.keys();
    if (keys == null) {
      _fail(
        const HandOnFailure(
          HandOnFailureKind.unknown,
          'Encryption is not ready on this phone.',
        ),
      );
      return;
    }
    _keyBytes ??= await keys.ecdhPrivate.exportPkcs8Key();
    final job = HandOnJob(
      targetId: target.id,
      deviceId: keys.id,
      start: await _loadCheckpoint(target.id),
      pacer: _pacer,
      call: _call,
      rewrap: (texts) => _rewrap(
        HandOnWork(
          ecdhPkcs8: _keyBytes!,
          deviceId: keys.id,
          targetId: target.id,
          targetEcdh: target.ecdh,
          texts: texts,
        ),
      ),
      save: (checkpoint) => _saveCheckpoint(target.id, checkpoint),
      verifyTarget: () async {
        if (await _verify(target.id) == null) throw const HandOnPaused();
      },
      onProgress: (p) {
        progress.value = p;
        if (phase.value == HandOnPhase.preparing ||
            phase.value == HandOnPhase.checking ||
            phase.value == HandOnPhase.sending) {
          phase.value = p.isPreparing
              ? HandOnPhase.preparing
              : HandOnPhase.sending;
        }
      },
    );
    _job = job;
    _isAutoResume = true;
    phase.value = HandOnPhase.preparing;
    try {
      await job.run();
      _isAutoResume = false;
      _handled.add(target.id);
      message.value = '';
      phase.value = HandOnPhase.done;
      unawaited(_e2e.refreshStatus());
    } on HandOnCancelled {
      _isAutoResume = false;
      phase.value = HandOnPhase.cancelled;
    } on HandOnPaused {
      _pause();
    } on HandOnFailure catch (f) {
      _fail(f);
    } finally {
      _job = null;
      if (!isRunning && phase.value != HandOnPhase.paused) _wipeKey();
    }
  }

  void _pause() {
    final ended = switch (_socket.connection.value) {
      SocketState.sessionReplaced => HandOnFailure.replacedText,
      SocketState.expired ||
      SocketState.authFailed ||
      SocketState.superseded => HandOnFailure.expiredText,
      _ => '',
    };
    if (ended.isNotEmpty) {
      _isAutoResume = false;
      _wipeKey();
    }
    message.value = ended.isEmpty ? connectionText : ended;
    phase.value = HandOnPhase.paused;
  }

  void _fail(HandOnFailure f) {
    _isAutoResume = false;
    switch (f.kind) {
      case HandOnFailureKind.anotherFinished || HandOnFailureKind.deviceGone:
        final id = offer.value?.id;
        if (id != null) {
          _handled.add(id);
          unawaited(_saveCheckpoint(id, null));
        }
        message.value = f.message;
        phase.value = HandOnPhase.gone;
      case HandOnFailureKind.sessionEnded:
        message.value = f.message;
        phase.value = HandOnPhase.paused;
        _wipeKey();
      default:
        message.value = f.message;
        isRetryable.value = f.isRetryable;
        phase.value = HandOnPhase.failed;
    }
    if (kDebugMode) debugPrint('hand-on: stopped (${f.kind.name})');
  }

  void _wipeKey() {
    _keyBytes?.fillRange(0, _keyBytes!.length, 0);
    _keyBytes = null;
  }

  Future<HandOnPageResult> _rewrap(HandOnWork work) async {
    if (isIsolateOn && !_isIsolateBroken) {
      try {
        return await handOnRewrapInIsolate(work);
      } catch (_) {
        _isIsolateBroken = true;
      }
    }
    return handOnRewrapPage(work);
  }

  // ---- the saved place -----------------------------------------------------

  String _checkpointKey(String id) => 'e2e.handon.$_org.$_me.$id';

  Future<HandOnCheckpoint?> _loadCheckpoint(String id) async =>
      HandOnCheckpoint.parse(await _session.readValue(_checkpointKey(id)));

  Future<void> _saveCheckpoint(String id, HandOnCheckpoint? checkpoint) =>
      _session.writeValue(_checkpointKey(id), checkpoint?.toJson() ?? '');
}
