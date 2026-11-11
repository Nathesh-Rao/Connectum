import 'dart:async';

import '../repositories/conversation_repository.dart';
import '../repositories/message_repository.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'ai_answer.dart';
import 'ai_models.dart';
import 'ai_prompt.dart';
import 'ai_relay.dart';
import 'ai_repository.dart';
import 'ai_transcript.dart';
import 'care_summary_text.dart';

/// The real calls: `ai.agents` for the setup and `assistant.relay` for the
/// answer. The server never sees "which chat": the transcript is built here
/// from the messages this device already holds for the chat, and nothing is
/// logged or kept.
class AiRepositoryImpl implements AiRepository {
  AiRepositoryImpl(
    this._socket,
    this._store,
    this._messages, {
    this.statusOf,
    this.displayNameOf,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _events = _socket.events.listen(onEvent);
    _online = _socket.onOnline.listen((_) => _changed.add(null));
  }

  final SocketService _socket;
  final SessionStore _store;
  final MessageRepository _messages;

  /// The status of a submission by its number, for a form line of the
  /// transcript.
  final String? Function(String submissionId)? statusOf;

  /// The display name shown in chat titles for a username (the same source as
  /// `TicketRepository.nameOf`); the username when absent or empty.
  final String Function(String user)? displayNameOf;
  final DateTime Function() _now;

  final _changed = StreamController<void>.broadcast();
  late final StreamSubscription<Map<String, dynamic>> _events;
  late final StreamSubscription<void> _online;
  int _run = 0;

  @override
  Stream<void> get agentsChanged => _changed.stream;

  /// Public so tests can feed it events.
  void onEvent(Map<String, dynamic> e) {
    if (e['type'] == 'sd_event' && e['event'] == 'ai_agents_changed') {
      _changed.add(null);
    }
  }

  Future<void> dispose() async {
    await _events.cancel();
    await _online.cancel();
    await _changed.close();
  }

  @override
  Future<AiSetup> getSetupState() async {
    final Map<String, dynamic> data;
    try {
      data = await _socket.sdCall('ai.agents', const {});
    } on SocketCallError catch (e) {
      throw AiRelay.fromSocket(e);
    }
    final raw = data['agents'];
    final agents = [
      if (raw is List)
        for (final a in raw) ?AiAgent.tryParse(a),
    ];
    return AiSetup(
      agents.isEmpty ? AiSetupState.notSetUp : AiSetupState.ready,
      agents: agents,
    );
  }

  @override
  Stream<AiSummaryChunk> summarize(AiSummaryRequest request) {
    final id = ++_run;
    final out = StreamController<AiSummaryChunk>();
    unawaited(_summarize(id, request, out));
    return out.stream;
  }

  @override
  void cancel() => _run++;

  Future<void> _summarize(
    int id,
    AiSummaryRequest request,
    StreamController<AiSummaryChunk> out,
  ) async {
    try {
      final chunk = await _ask(request);
      if (id == _run && !out.isClosed) out.add(chunk);
    } on AiError catch (e) {
      if (id == _run && !out.isClosed) out.addError(e);
    } on Object {
      if (id == _run && !out.isClosed) {
        out.addError(const AiError(AiErrorKind.failed));
      }
    }
    if (!out.isClosed) await out.close();
  }

  String _nameOf(String user) {
    final name = displayNameOf?.call(user).trim() ?? '';
    return name.isEmpty ? user : name;
  }

  Future<AiSummaryChunk> _ask(AiSummaryRequest request) async {
    final org = _store.orgId;
    final user = _store.userId;
    final agent = request.agent;
    if (org == null || user == null || agent == null) {
      throw const AiError(AiErrorKind.notSetUp);
    }
    final now = _now();
    final String system;
    final String question;
    final int count;
    var isTruncated = false;
    if (request.isCare) {
      final person = request.carePerson!;
      final summary = await _careSummary(person);
      final stats = summary['stats'];
      final forms = stats is Map && stats['forms'] is num
          ? stats['forms'] as num
          : 0;
      final messages = stats is Map && stats['messages'] is num
          ? stats['messages'] as num
          : 0;
      if (forms == 0 && messages == 0) {
        throw const AiError(
          AiErrorKind.noMessages,
          'Nothing has been recorded in this thread yet.',
        );
      }
      isTruncated = stats is Map && stats['truncated'] == true;
      count = messages.toInt();
      final card = summary['person'];
      final name = card is Map && '${card['name'] ?? ''}'.isNotEmpty
          ? '${card['name']}'
          : person;
      system = AiPrompt.careSystem(
        name: _nameOf(user),
        now: now,
        isPatient: user.toLowerCase() == person.toLowerCase(),
        thread: CareSummaryText.toPlainText(summary, now: now),
      );
      question = AiPrompt.careQuestion(name);
    } else {
      final since = request.range.since(now, date: request.date);
      final kind = ConversationRepository.kindOf(request.chatId);
      final rows = await _messages.readFor(org, user, request.chatId);
      final transcript = AiTranscript.build(
        rows,
        kind: kind,
        title: request.title,
        since: since,
        nameOf: (u) => u,
        statusOf: statusOf,
      );
      if (transcript.isEmpty) throw const AiError(AiErrorKind.noMessages);
      count = transcript.count;
      system = AiPrompt.system(
        name: _nameOf(user),
        now: now,
        label: request.title,
        transcript: transcript.text,
      );
      question = AiPrompt.question(
        request.title,
        isGroup: kind == 'group',
        since: since,
      );
    }
    final Map<String, dynamic> data;
    try {
      data = await _socket.sdCall('assistant.relay', {
        'agent': agent.id,
        'payload': AiRelay.payload(agent, system: system, question: question),
        'timeoutMs': AiRelay.timeoutMs,
      }, timeout: AiRelay.wait);
    } on SocketCallError catch (e) {
      throw AiRelay.fromSocket(e);
    }
    final status = data['status'];
    final body = data['body'];
    if (status is! int || status < 200 || status >= 300) {
      throw AiRelay.fromProvider(status is int ? status : 0, body);
    }
    final text = AiRelay.text(agent.provider, body);
    if (AiAnswer.plain(text).isEmpty) {
      throw const AiError(AiErrorKind.emptyAnswer);
    }
    return AiSummaryChunk(
      text,
      isFinal: true,
      messageCount: count,
      isTruncated: isTruncated,
    );
  }

  /// `care.summary {person}`; `not_found` says which of its two texts.
  Future<Map<String, dynamic>> _careSummary(String person) async {
    try {
      return await _socket.sdCall('care.summary', {'person': person});
    } on SocketCallError catch (e) {
      if (e.code == 'not_found') {
        throw AiError(AiErrorKind.careNotFound, e.message);
      }
      throw AiRelay.fromSocket(e);
    }
  }
}
