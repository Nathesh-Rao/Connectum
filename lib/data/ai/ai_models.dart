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
  });

  final String chatId;
  final String title;
  final AiRange range;
  final DateTime? date;
  final AiAgent? agent;

  /// The username of a care thread's person: the summary is built from
  /// `care.summary` and the range is not used.
  final String? carePerson;

  bool get isCare => carePerson != null;
}

/// One event of a summary. The server does not stream, so the repository
/// sends a single final event.
class AiSummaryChunk {
  const AiSummaryChunk(
    this.text, {
    this.isFinal = false,
    this.messageCount,
    this.isTruncated = false,
  });

  final String text;
  final bool isFinal;

  /// How many messages were read into the summary.
  final int? messageCount;

  /// A care thread's older messages were left out (`stats.truncated`).
  final bool isTruncated;
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

  /// `care.summary` said `not_found`: the error's message says which.
  careNotFound;

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
