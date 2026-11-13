import 'dart:async';

import '../repositories/conversation_repository.dart';
import '../models/message.dart';
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
    await _refuseEncrypted(request.chatId);
    final now = _now();
    final String system;
    final String question;
    final int count;
    var isTruncated = false;
    var isPatientView = false;
    if (request.isCare) {
      final person = request.carePerson!;
      final isPatient = AiPrompt.isPatient(user, person);
      isPatientView = isPatient;
      if (request.isCareQuestion) {
        final thread = await careThread(person);
        if (thread.count == 0) throw _careEmpty(isPatient);
        count = thread.count;
        system = AiPrompt.careThreadSystem(
          name: _nameOf(user),
          now: now,
          isPatient: isPatient,
          team: thread.team,
          transcript: thread.transcript,
        );
        question = request.question!.trim();
      } else {
        final summary = await _careSummary(person, isPatient);
        final stats = summary['stats'];
        final forms = stats is Map && stats['forms'] is num
            ? stats['forms'] as num
            : 0;
        final messages = stats is Map && stats['messages'] is num
            ? stats['messages'] as num
            : 0;
        if (forms == 0 && messages == 0) throw _careEmpty(isPatient);
        isTruncated = stats is Map && stats['truncated'] == true;
        count = messages.toInt();
        final card = summary['person'];
        final name = card is Map && '${card['name'] ?? ''}'.isNotEmpty
            ? '${card['name']}'
            : person;
        system = AiPrompt.careSystem(
          name: _nameOf(user),
          now: now,
          isPatient: isPatient,
          thread: CareSummaryText.toPlainText(summary, now: now),
        );
        question = AiPrompt.careQuestion(name);
      }
    } else {
      final since = request.range.since(now, date: request.date);
      final kind = ConversationRepository.kindOf(request.chatId);
      final rows = await _messages.readFor(org, user, request.chatId);
      _refuseEncryptedRows(rows);
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
      isPatientView: isPatientView,
    );
  }

  /// AI is blocked in end-to-end chats: nothing is read, built or sent.
  Future<void> _refuseEncrypted(String chatId) async {
    if (await _messages.hasEncryptedHistory(chatId)) {
      throw const AiError(AiErrorKind.encrypted);
    }
  }

  void _refuseEncryptedRows(List<Message> rows) {
    if (rows.any((m) => m.isEncrypted)) {
      throw const AiError(AiErrorKind.encrypted);
    }
  }

  /// The thread exists but holds nothing yet (an empty `care.summary`).
  AiError _careEmpty(bool isPatient) =>
      AiError(isPatient ? AiErrorKind.careEmptyPatient : AiErrorKind.careEmpty);

  /// `care.summary {person}`: the clipped summary, for the one-tap summary.
  Future<Map<String, dynamic>> _careSummary(
    String person,
    bool isPatient,
  ) async {
    try {
      return await _socket.sdCall('care.summary', {'person': person});
    } on SocketCallError catch (e) {
      throw _careError(e, isPatient);
    }
  }

  /// `not_found` is told by its code only: the server's text is its own and
  /// may be reworded (and one code carries two texts), so ours is used.
  AiError _careError(SocketCallError e, bool isPatient) {
    if (e.code == 'not_found') {
      return AiError(
        isPatient ? AiErrorKind.careNotStarted : AiErrorKind.careNotFound,
      );
    }
    return AiRelay.fromSocket(e);
  }

  @override
  Future<CareThread> careThread(String person) async {
    final org = _store.orgId;
    final me = _store.userId;
    if (org == null || me == null) throw const AiError(AiErrorKind.notSetUp);
    final isPatient = AiPrompt.isPatient(me, person);
    final Map<String, dynamic> ref;
    try {
      ref = await _socket.sdCall('care.thread', {'person': person});
    } on SocketCallError catch (e) {
      throw _careError(e, isPatient);
    }
    final conversation = '${ref['conversation'] ?? ''}';
    if (conversation.isEmpty) throw const AiError(AiErrorKind.failed);
    await _refuseEncrypted(conversation);
    final who = '${ref['person'] ?? person}';
    // The team and the person's name come from care.summary (it is the only
    // call that lists them); a failure there only leaves the roster out.
    final card = _careCard(who);
    final hasMore = await _messages.fetchRecent(
      conversation,
      atLeast: AiTranscript.careMaxMessages,
    );
    if (hasMore == null) throw const AiError(AiErrorKind.serverTimeout);
    await _refuseEncrypted(conversation);
    final cardData = await card;
    final team = [
      if (cardData['team'] is List)
        for (final m in cardData['team'] as List) ?CareMember.tryParse(m),
    ];
    final p = cardData['person'];
    final name = p is Map && '${p['name'] ?? ''}'.isNotEmpty
        ? '${p['name']}'
        : _nameOf(who);
    final names = {
      for (final m in team) m.username.toLowerCase(): m.label,
      who.toLowerCase(): name,
    };
    final rows = await _messages.readFor(org, me, conversation);
    _refuseEncryptedRows(rows);
    final transcript = AiTranscript.build(
      rows,
      kind: 'group',
      title: name.length > AiTranscript.careTitleChars
          ? name.substring(0, AiTranscript.careTitleChars)
          : name,
      since: null,
      nameOf: (u) => names[u.toLowerCase()] ?? _nameOf(u),
      statusOf: statusOf,
      limitMessages: AiTranscript.careMaxMessages,
      limitChars: AiTranscript.careMaxChars - AiTranscript.headerReserve,
      keepLines: 1,
      isCut: hasMore,
    );
    return CareThread(
      conversation: conversation,
      person: who,
      name: name,
      transcript: transcript.text,
      count: transcript.count,
      team: team,
      isPatient: isPatient,
    );
  }

  Future<Map<String, dynamic>> _careCard(String person) async {
    try {
      return await _socket.sdCall('care.summary', {'person': person});
    } on SocketCallError {
      return const {};
    }
  }
}
