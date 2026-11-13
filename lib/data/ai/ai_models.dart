/// One AI agent this person may use (`ai.agents`): `id`, `name`, `alias` (the
/// command word), `provider`, `model`, `modelChoice`.
class AiAgent {
  const AiAgent({
    required this.id,
    required this.name,
    this.alias = '',
    this.provider = '',
    this.model = '',
    this.hasModelChoice = false,
  });

  final String id;
  final String name;
  final String alias;
  final String provider;
  final String model;

  /// May the person pick another model of the provider's (`modelChoice`).
  final bool hasModelChoice;

  static AiAgent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    if (id.isEmpty) return null;
    final name = '${raw['name'] ?? ''}';
    return AiAgent(
      id: id,
      name: name.isEmpty ? id : name,
      alias: '${raw['alias'] ?? ''}',
      provider: '${raw['provider'] ?? ''}',
      model: '${raw['model'] ?? ''}',
      hasModelChoice: raw['modelChoice'] == true,
    );
  }
}

/// `ai.agents` has no status flag and no reason: AI is ready when at least one
/// agent is listed, else it is not set up (the server does not say why).
enum AiSetupState { ready, notSetUp }

class AiSetup {
  const AiSetup(this.state, {this.agents = const []});

  final AiSetupState state;
  final List<AiAgent> agents;

  bool get isReady => state == AiSetupState.ready;
}

/// The "From" options of the web (`ChatSummaryModal.jsx`); the server has no
/// others.
enum AiRange {
  everything('Everything'),
  today('Today'),
  week('Last 7 days'),
  month('Last 30 days'),
  date('A date');

  const AiRange(this.label);

  final String label;

  /// The first moment of the range in device time, or null for everything.
  /// [date] is the picked day.
  DateTime? since(DateTime now, {DateTime? date}) {
    return switch (this) {
      AiRange.everything => null,
      AiRange.today => DateTime(now.year, now.month, now.day),
      AiRange.week => DateTime(now.year, now.month, now.day - 7),
      AiRange.month => DateTime(now.year, now.month, now.day - 30),
      AiRange.date =>
        date == null ? null : DateTime(date.year, date.month, date.day),
    };
  }
}

/// What one summary asks for.
class AiSummaryRequest {
  const AiSummaryRequest({
    required this.chatId,
    required this.title,
    required this.range,
    this.date,
    this.agent,
    this.carePerson,
    this.question,
  });

  final String chatId;
  final String title;
  final AiRange range;
  final DateTime? date;
  final AiAgent? agent;

  /// The username of a care thread's person: the summary is built from
  /// `care.summary` and the range is not used.
  final String? carePerson;

  /// A typed question about a care thread: it is answered from the whole
  /// thread (`care.thread`), not the one-tap `care.summary`. Null for the
  /// one-tap summary and in any other chat.
  final String? question;

  bool get isCare => carePerson != null;

  bool get isCareQuestion => isCare && (question?.trim().isNotEmpty ?? false);
}

/// One person on a care thread's team (`care.summary` `team`).
class CareMember {
  const CareMember({
    required this.username,
    required this.name,
    this.roles = const [],
  });

  final String username;
  final String name;
  final List<String> roles;

  String get label => name.isEmpty ? username : name;

  static CareMember? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final username = '${raw['username'] ?? ''}';
    if (username.isEmpty) return null;
    final list = raw['roles'];
    final role = raw['role'];
    final roles = <String>[
      if (list is List)
        for (final r in list) '$r',
    ].where((r) => r.isNotEmpty).toList();
    if (roles.isEmpty && role is String && role.isNotEmpty) roles.add(role);
    return CareMember(
      username: username,
      name: '${raw['name'] ?? ''}',
      roles: roles,
    );
  }
}

/// A care thread read for a typed question (`care.thread`, then its history):
/// the conversation, the team and the chat as the model reads it.
class CareThread {
  const CareThread({
    required this.conversation,
    required this.person,
    required this.name,
    required this.transcript,
    required this.count,
    this.team = const [],
    this.isPatient = false,
  });

  /// `care.thread`'s `conversation` (`group:care-<username>`).
  final String conversation;

  /// `care.thread`'s `person`.
  final String person;

  /// The person's display name.
  final String name;

  /// The `THE GROUP CHAT, IN ORDER` block, within the limits
  /// ([AiTranscript.careMaxMessages] and [AiTranscript.careMaxChars]).
  final String transcript;

  /// Messages in [transcript]; 0 when the thread holds nothing.
  final int count;
  final List<CareMember> team;

  /// The person asking is the person the thread is about.
  final bool isPatient;
}

/// One event of a summary. The server does not stream, so the repository
/// sends a single final event.
class AiSummaryChunk {
  const AiSummaryChunk(
    this.text, {
    this.isFinal = false,
    this.messageCount,
    this.isTruncated = false,
    this.isPatientView = false,
  });

  final String text;
  final bool isFinal;

  /// How many messages were read into the summary.
  final int? messageCount;

  /// A care thread's older messages were left out (`stats.truncated`).
  final bool isTruncated;

  /// The answer is for the person the thread is about, who sees only the
  /// parts of the thread they have access to.
  final bool isPatientView;
}

enum AiErrorKind {
  /// No connection (`disconnected`, `not_connected`).
  offline,

  /// Connectum did not answer in time (`timeout`, `test_timeout`).
  serverTimeout,

  /// The provider took too long (`upstream_timeout`).
  timeout,
  failed,
  noMessages,
  tooLarge,

  /// 30 questions per minute per person (`rate_limited`).
  rateLimited,

  /// 600 per minute across everybody on one agent (`rate_limited`, "The AI is
  /// busy right now").
  agentBusy,
  providerRateLimited,
  noPermission(isSetupProblem: true),
  notSetUp(isSetupProblem: true),
  agentGone(isSetupProblem: true),
  badKey(isSetupProblem: true),
  keyUnreadable(isSetupProblem: true),
  noKey(isSetupProblem: true),
  forbiddenAddress(isSetupProblem: true),
  noCredit(isSetupProblem: true),
  providerBusy,
  providerUnreachable,
  modelUnavailable(isSetupProblem: true),
  badRequest,
  emptyAnswer,

  /// `care.summary` / `care.thread` said `not_found` (matched by code only,
  /// never by the server's text) to someone who is not the person.
  careNotFound,

  /// The same `not_found` to the person the thread is about: the thread
  /// starts once the care team is connected.
  careNotStarted,

  /// The thread exists (an employee has joined) but nothing is recorded yet:
  /// `care.summary` came back empty. A friendly state, not an error.
  careEmpty,

  /// The same for the person the thread is about.
  careEmptyPatient,

  /// An end-to-end encrypted chat: AI is blocked on mobile (the BE decision
  /// is unchanged). Nothing was read, built or sent.
  encrypted;

  const AiErrorKind({this.isSetupProblem = false});

  /// The person cannot fix these here: they go to the administrator.
  final bool isSetupProblem;
}

class AiError implements Exception {
  const AiError(this.kind, [this.message]);

  final AiErrorKind kind;

  /// The words when they vary (the provider's refusal, the server's own
  /// message, `care.summary`'s `not_found`); never chat text.
  final String? message;

  @override
  String toString() => 'AiError($kind${message == null ? '' : ': $message'})';
}
