import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/api/api_client.dart';
import '../../data/db/app_database.dart';
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
    required this.submissions,
    required AppDatabase db,
  }) : _db = db;

  final SocketService socket;
  final ConnectivityService connectivity;
  final SessionRepository session;
  final MessageRepository messages;
  final SubmissionRepository submissions;
  final AppDatabase _db;

  final orgId = TextEditingController();
  final username = TextEditingController();
  final token = TextEditingController();
  final identityToken = TextEditingController();
  final enterpriseId = TextEditingController();
  final convId = TextEditingController(text: 'dm:');
  final messageText = TextEditingController(text: 'test message');
  final formName = TextEditingController();
  final formValues = TextEditingController(text: '{}');

  final notes = <String>[].obs;
  final outbox = ''.obs;
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _refreshOutbox();
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
    ]) {
      c.dispose();
    }
    super.onClose();
  }
}
