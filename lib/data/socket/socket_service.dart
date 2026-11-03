import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:web_socket_channel/io.dart';

import '../../core/config/app_config.dart';
import '../api/api_client.dart';
import '../redact.dart';
import '../session_store.dart';
import 'connectivity_service.dart';

enum SocketState {
  connecting,
  online,
  offline,
  sessionReplaced,
  authFailed,
  expired,
  superseded,
}

class SocketCallError implements Exception {
  const SocketCallError(this.code, [this.message = '', this.details]);

  final String code;
  final String message;
  final Object? details;

  bool get isConnectionGap =>
      code == 'timeout' || code == 'disconnected' || code == 'not_connected';

  @override
  String toString() => 'SocketCallError($code)';
}

class SocketService extends GetxService with WidgetsBindingObserver {
  SocketService(this._session, this._connectivity, this._api);

  static const _pace = Duration(milliseconds: 400);
  static const _handshakeTimeout = Duration(seconds: 15);

  final SessionStore _session;
  final ConnectivityService _connectivity;
  final ApiClient _api;

  final connection = SocketState.offline.obs;
  final eventLog = <String>[].obs;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _onlineSignal = StreamController<void>.broadcast();
  final _calls = <String, Completer<Map<String, dynamic>>>{};
  final _random = Random();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  Timer? _handshakeTimer;
  int _attempt = 0;
  int _callSeq = 0;
  bool _wantConnected = false;
  bool _hasWelcome = false;
  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _pausedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Fires after every successful handshake (`welcome`).
  Stream<void> get onOnline => _onlineSignal.stream;

  bool get isOnline => connection.value == SocketState.online;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    ever(_connectivity.hasNetwork, (hasNetwork) {
      if (!_wantConnected) return;
      if (hasNetwork) {
        connectNow(resetBackoff: true);
      } else {
        _drop(SocketState.offline);
      }
    });
    ever(_connectivity.simulateOffline, (isSimulated) {
      if (!_wantConnected) return;
      if (isSimulated) {
        _drop(SocketState.offline);
      } else {
        connectNow(resetBackoff: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (_session.current.value?.isExpired ?? false)) {
      _drop(SocketState.expired);
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _wantConnected &&
        !isOnline &&
        connection.value != SocketState.connecting) {
      connectNow(resetBackoff: true);
    }
  }

  void start() {
    _wantConnected = true;
    connectNow(resetBackoff: true);
  }

  Future<void> stop() async {
    _wantConnected = false;
    _retryTimer?.cancel();
    if (isOnline) _channel?.sink.add('/quit');
    _drop(SocketState.offline);
  }

  Future<void> connectNow({bool resetBackoff = false}) async {
    if (!_wantConnected) return;
    if (resetBackoff) _attempt = 0;
    final state = connection.value;
    if (state == SocketState.connecting || state == SocketState.online) return;
    if (_session.current.value?.isExpired ?? false) {
      _drop(SocketState.expired);
      return;
    }
    if (!AppConfig.isConfigured ||
        !_session.hasSession ||
        _connectivity.simulateOffline.value ||
        !_connectivity.hasNetwork.value) {
      connection.value = SocketState.offline;
      return;
    }
    _retryTimer?.cancel();
    connection.value = SocketState.connecting;
    _hasWelcome = false;
    try {
      final client = HttpClient();
      if (kDebugMode) {
        client.badCertificateCallback = (_, host, _) =>
            AppConfig.trustedHosts.contains(host);
      }
      final channel = IOWebSocketChannel.connect(
        Uri.parse(AppConfig.wsUrl),
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 15),
        customClient: client,
      );
      await channel.ready;
      _channel = channel;
      _subscription = channel.stream.listen(
        _onData,
        onDone: () => _onClosed(channel),
        onError: (_) => _onClosed(channel),
      );
      // The server stores usernames in lower case and wants exactly that; the
      // stored user id keeps the original for display.
      channel.sink.add(
        jsonEncode({
          'username': _session.userId?.toLowerCase(),
          'token': _session.token,
        }),
      );
      _handshakeTimer = Timer(_handshakeTimeout, () {
        if (!_hasWelcome) _drop(SocketState.offline, retry: true);
      });
    } catch (_) {
      _drop(SocketState.offline, retry: true);
    }
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final event = decoded.cast<String, dynamic>();
    _log('<- ${Redact.event(event)}');
    final type = event['type'];
    if (type == 'welcome') {
      _hasWelcome = true;
      _handshakeTimer?.cancel();
      _attempt = 0;
      connection.value = SocketState.online;
      _onlineSignal.add(null);
      return;
    }
    if (type == 'error' && !_hasWelcome) {
      _onHandshakeError('${event['text'] ?? ''}');
      return;
    }
    if (type == 'error' && '${event['text']}'.contains('Too many commands')) {
      _pausedUntil = DateTime.now().add(
        Duration(milliseconds: 2000 + _random.nextInt(2000)),
      );
    }
    if (type == 'sd') {
      final call = _calls.remove('${event['reqId']}');
      if (call != null) {
        if (event['ok'] == true) {
          call.complete((event['data'] as Map?)?.cast<String, dynamic>() ?? {});
        } else {
          final error = (event['error'] as Map?) ?? {};
          call.completeError(
            SocketCallError(
              '${error['code'] ?? 'error'}',
              '${error['message'] ?? ''}',
              error['details'],
            ),
          );
        }
      }
      return;
    }
    if (type == 'sd_event') {
      switch (event['event']) {
        case 'session_replaced':
          _drop(SocketState.sessionReplaced);
        case 'session_expired':
          _drop(SocketState.expired);
        case 'connection_superseded':
          _drop(SocketState.superseded);
        case 'disconnected':
          if (event['reason'] == 'account_deactivated') {
            _drop(SocketState.authFailed);
          } else {
            _drop(SocketState.offline, retry: true);
          }
      }
    }
    _events.add(event);
  }

  // The docs give no error codes for handshake failures, only texts.
  // "Username taken" only appears when the connection carries no Connectum
  // session, so it is an auth failure, never a retry.
  Future<void> _onHandshakeError(String text) async {
    if (text.contains('Username taken') ||
        text.contains('Sign in to Connectum first') ||
        text.contains('different username')) {
      _drop(SocketState.authFailed);
      return;
    }
    _drop(SocketState.offline);
    try {
      await _api.session();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        connection.value = SocketState.authFailed;
        return;
      }
    }
    if (_wantConnected) _scheduleRetry();
  }

  void _onClosed(IOWebSocketChannel channel) {
    if (!identical(channel, _channel)) return;
    final state = connection.value;
    final keep =
        state == SocketState.sessionReplaced ||
        state == SocketState.authFailed ||
        state == SocketState.expired ||
        state == SocketState.superseded;
    _drop(keep ? state : SocketState.offline, retry: !keep);
  }

  void _drop(SocketState next, {bool retry = false}) {
    _handshakeTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _hasWelcome = false;
    for (final call in _calls.values) {
      call.completeError(const SocketCallError('disconnected'));
    }
    _calls.clear();
    if (connection.value != next) connection.value = next;
    if (retry && _wantConnected) _scheduleRetry();
  }

  // Capped exponential backoff with jitter; reset on the next `welcome`.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    final base = min(30000, 1000 * pow(2, _attempt).toInt());
    final delay = (base * (0.7 + _random.nextDouble() * 0.6)).round();
    _attempt = min(_attempt + 1, 10);
    _retryTimer = Timer(Duration(milliseconds: delay), connectNow);
  }

  Future<bool> sendCommand(String line) async {
    if (!isOnline) return false;
    final pause = _pausedUntil.difference(DateTime.now());
    if (!pause.isNegative) await Future<void>.delayed(pause);
    final now = DateTime.now();
    final wait = _nextSlot.difference(now);
    _nextSlot = (wait.isNegative ? now : _nextSlot).add(_pace);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    final channel = _channel;
    if (!isOnline || channel == null) return false;
    final words = line.split(' ');
    _log('-> ${words.take(line.startsWith('/c ') ? 3 : 1).join(' ')}');
    if (kDebugMode && line.startsWith('/react ')) {
      final emoji = line.split(' ').last;
      debugPrint(
        'REACT frame: $line  codepoints=${emoji.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase()}').join(' ')}',
      );
    }
    channel.sink.add(line);
    return true;
  }

  Future<Map<String, dynamic>> sdCall(
    String action,
    Map<String, dynamic> args, {
    Duration timeout = const Duration(seconds: 12),
  }) {
    final id = 'm-${++_callSeq}';
    return _call(
      id,
      '/sd $action ${jsonEncode({...args, 'reqId': id})}',
      timeout,
    );
  }

  /// Sends a raw `#command` line whose answer is an `sd` envelope. The server
  /// sets its `reqId` to `#<canonical command name>`.
  Future<Map<String, dynamic>> hashCall(
    String line,
    String name, {
    Duration timeout = const Duration(seconds: 12),
  }) => _call('#$name', line, timeout);

  Future<Map<String, dynamic>> _call(
    String id,
    String line,
    Duration timeout,
  ) async {
    if (!isOnline) throw const SocketCallError('not_connected');
    final completer = Completer<Map<String, dynamic>>();
    _calls[id] = completer;
    final sent = await sendCommand(line);
    if (!sent) {
      _calls.remove(id);
      throw const SocketCallError('not_connected');
    }
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _calls.remove(id);
        throw const SocketCallError('timeout');
      },
    );
  }

  void _log(String line) {
    eventLog.insert(0, line);
    if (eventLog.length > 20) eventLog.removeRange(20, eventLog.length);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _drop(SocketState.offline);
    _events.close();
    _onlineSignal.close();
    super.onClose();
  }
}
