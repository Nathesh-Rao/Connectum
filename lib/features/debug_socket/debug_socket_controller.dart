import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/api/api_client.dart';
import '../../data/db/app_database.dart';
import '../../data/models/ids.dart';
import '../../data/redact.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';

class DebugSocketController extends GetxController {
  DebugSocketController({
    required this.socket,
    required this.connectivity,
    required this.session,
    required this.messages,
    required this.conversationRepository,
    required this.submissions,
    required AppDatabase db,
  }) : _db = db;

  final SocketService socket;
  final ConnectivityService connectivity;
  final SessionRepository session;
  final MessageRepository messages;
  final ConversationRepository conversationRepository;
  final SubmissionRepository submissions;
  final AppDatabase _db;

  final orgId = TextEditingController();
  final username = TextEditingController();
  final token = TextEditingController();
  final identityToken = TextEditingController();
  final enterpriseId = TextEditingController();
  final convId = TextEditingController(text: 'dm:');
  final messageText = TextEditingController(text: 'test message');
  final sdAction = TextEditingController(text: 'users.search');
  final sdArgs = TextEditingController(text: '{"q":""}');
  final formName = TextEditingController();
  final formValues = TextEditingController(text: '{}');

  final notes = <String>[].obs;
  final outbox = ''.obs;
  final lastCid = '-'.obs;
  final recent = ''.obs;
  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _acks;
  String? _cidConv;
  String? _cidText;

  @override
  void onInit() {
    super.onInit();
    _refreshOutbox();
    _acks = socket.events.listen(_noteAck);
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshOutbox(),
    );
  }

  Future<void> _refreshOutbox() async {
    final rows = await _db.query(
      'SELECT kind, status, COUNT(*) AS n FROM outbox GROUP BY kind, status',
    );
    outbox.value = rows.isEmpty
        ? 'empty'
        : rows.map((r) => '${r['kind']}/${r['status']}: ${r['n']}').join('  ');
  }

  void _note(String line) {
    notes.insert(0, line);
    if (notes.length > 10) notes.removeRange(10, notes.length);
  }

  void connect() => socket.start();

  void disconnect() => socket.stop();

  Future<void> loginDirect() async {
    await session.signIn(
      orgId: orgId.text.trim(),
      userId: username.text.trim(),
      token: token.text.trim(),
    );
    token.clear();
    _note('signed in (token stored, not shown)');
  }

  Future<void> enterFlow() async {
    try {
      final shape = await session.enter(
        identityToken.text.trim(),
        enterpriseId.text.trim(),
      );
      identityToken.clear();
      _note('enter ok, shape: $shape');
    } on ApiException catch (e) {
      _note('enter failed: ${e.code} (${e.status})');
    }
  }

  Future<void> sendTest() async {
    final result = await messages.sendText(
      convId.text.trim(),
      messageText.text,
    );
    _note('send ${convId.text.trim()}: ${result.name}');
    await _refreshOutbox();
  }

  void _noteAck(Map<String, dynamic> e) {
    final type = idText(e['type']);
    if (e['cid'] != null && type.endsWith('ack')) {
      _note(
        '$type cid=${e['cid']} id=${e['id']} duplicate=${e['duplicate'] == true}',
      );
    } else if (type == 'error' && e['code'] != null) {
      _note('error code=${e['code']}');
    }
  }

  Future<void> sendWithCid() async {
    _cidConv = convId.text.trim();
    _cidText = messageText.text;
    lastCid.value = newCid();
    await _sendCid();
  }

  Future<void> sendSameCidAgain() async {
    if (_cidConv == null) {
      _note('send with a cid first');
      return;
    }
    await _sendCid();
  }

  Future<void> _sendCid() async {
    final command = MessageRepository.cidCommand(
      _cidConv!,
      _cidText!,
      lastCid.value,
    );
    if (command == null) {
      _note('a client id works for dm:, group: and host: only');
      return;
    }
    final sent = await socket.sendCommand(command);
    _note('sent $_cidConv cid=${lastCid.value}${sent ? '' : ' (offline)'}');
  }

  Future<void> loadOlder(String conv) async {
    final page = await messages.loadOlder(conv);
    if (page == null) {
      _note('older $conv: no answer (offline or nothing stored)');
      return;
    }
    _note(
      'older $conv: ${page.count} messages, hasMore=${page.hasMore}, next=${page.next}',
    );
  }

  Future<void> showMessages() async {
    final rows = await _db.query(
      'SELECT msg_id, cid, status, is_encrypted_unsupported AS e2e, text FROM messages '
      'WHERE org_id = ? AND user_id = ? AND conv_id = ? ORDER BY ts DESC, local_seq DESC LIMIT 8',
      [session.store.orgId, session.store.userId, convId.text.trim()],
    );
    recent.value = rows.isEmpty
        ? 'no stored messages'
        : rows
              .map(
                (r) =>
                    '${r['msg_id']}  ${r['status']}  cid=${r['cid'] ?? '-'}  e2e=${intOf(r['e2e']) == 1}  ${idText(r['text']).length}ch',
              )
              .join('\n');
  }

  /// Runs one `/sd` action and notes the answer as redacted JSON (long text
  /// is cut). For checking a response shape against the real server.
  Future<void> runSd() async {
    try {
      final args = (jsonDecode(sdArgs.text) as Map).cast<String, dynamic>();
      final data = await socket.sdCall(sdAction.text.trim(), args);
      _note('${sdAction.text.trim()}: ${jsonEncode(Redact.value(data))}');
    } on SocketCallError catch (e) {
      _note('${sdAction.text.trim()} failed: ${e.code} ${e.message}');
    } on FormatException catch (_) {
      _note('args must be a JSON object');
    }
  }

  Future<void> syncNow() async {
    _note('sync started');
    await messages.syncNow();
    await submissions.syncFromServer();
    _note('sync finished');
  }

  Future<void> metaTest() async {
    try {
      final values = (jsonDecode(formValues.text) as Map)
          .cast<String, dynamic>();
      _note(await submissions.debugMetaRoundTrip(formName.text.trim(), values));
    } on SocketCallError catch (e) {
      _note('meta test failed: ${e.code} ${e.message}');
    } on FormatException catch (_) {
      _note('form values must be a JSON object');
    }
  }

  Future<void> signOut() => session.signOut();

  @override
  void onClose() {
    _timer?.cancel();
    _acks?.cancel();
    for (final c in [
      orgId,
      username,
      token,
      identityToken,
      enterpriseId,
      convId,
      messageText,
      formName,
      formValues,
      sdAction,
      sdArgs,
    ]) {
      c.dispose();
    }
    super.onClose();
  }
}
