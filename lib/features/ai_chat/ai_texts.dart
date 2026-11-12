import '../../data/ai/ai_error_text.dart';
import '../../data/ai/ai_models.dart';

/// One place for the words of the in-chat AI. Where the web has wording
/// (`AssistantView.jsx`, `assistantErrors.js`) it is reused.
class AiTexts {
  AiTexts._();

  static const title = 'AI assistant';
  static const summarize = 'Summarize this chat';
  static const summarizeHint = 'Key points, decisions and who does what';
  static const careSummarize = 'Summarize this thread';
  static const careSummarizeHint =
      "Key points from the person's forms and messages";
  static const careNote =
      "Up to the latest 500 messages and the person's forms";
  static const careTruncated = 'Older messages were left out.';
  static const patientScope =
      'You see the parts of the conversation you have access to';
  static const askHint = 'Ask about this thread';
  static const askHeading = 'Ask a question';
  static const askSend = 'Send question';
  static const questionLabel = 'Your question';
  static const summarizing = 'Summarizing…';
  static const caption = 'AI-generated, may contain mistakes';
  static const copied = 'Summary copied';
  static const privacy =
      "The messages in the selected range are sent to your organisation's AI "
      'provider.';

  static const shareTitle = 'Post summary to this chat?';
  static const shareText =
      'Everyone in this chat will see exactly this, posted under your name:';
  static const posted = 'Summary posted';
  static const postFailed = "Couldn't post the summary";

  static const setupTitle = "AI isn't set up yet";

  /// The web's words (`workspaceAgent.js`, `no_agent`); an administrator is
  /// told where to set one up.
  static String setupText({bool isAdmin = false}) => isAdmin
      ? 'No AI agent is set up for you yet. Set it up in the web app '
            '(Admin console > AI agents).'
      : 'No AI agent is set up for you yet. Ask your administrator.';

  static String errorTitle(AiErrorKind kind) => switch (kind) {
    AiErrorKind.offline => "You're offline",
    AiErrorKind.serverTimeout => "Can't reach Connectum",
    AiErrorKind.timeout => 'Taking too long',
    AiErrorKind.failed => "Couldn't summarize",
    AiErrorKind.noMessages => 'Nothing to summarize',
    AiErrorKind.tooLarge => 'Too much to read',
    AiErrorKind.rateLimited ||
    AiErrorKind.providerRateLimited => 'Too many requests',
    AiErrorKind.agentBusy => 'AI is busy',
    AiErrorKind.noPermission => 'Not allowed',
    AiErrorKind.notSetUp => setupTitle,
    AiErrorKind.agentGone => 'AI agent removed',
    AiErrorKind.badKey ||
    AiErrorKind.keyUnreadable ||
    AiErrorKind.noKey => "AI isn't working",
    AiErrorKind.forbiddenAddress => "AI isn't working",
    AiErrorKind.noCredit => 'AI has no credit left',
    AiErrorKind.providerBusy => 'AI is busy',
    AiErrorKind.providerUnreachable => "Can't reach the AI",
    AiErrorKind.modelUnavailable => 'AI model not available',
    AiErrorKind.badRequest => "The AI couldn't use that",
    AiErrorKind.emptyAnswer => 'No answer',
    AiErrorKind.careNotFound => 'No care conversation',
    AiErrorKind.careNotStarted => 'No care conversation yet',
  };

  /// The classified web error behind a kind (`AiErrorText`), or null for
  /// the kinds that have words of their own.
  static AiErrorInfo? info(AiErrorKind kind) => switch (kind) {
    AiErrorKind.offline => AiErrorText.classifyRelayError('disconnected'),
    AiErrorKind.serverTimeout => AiErrorText.classifyRelayError('timeout'),
    AiErrorKind.timeout => AiErrorText.classifyRelayError('upstream_timeout'),
    AiErrorKind.providerUnreachable => AiErrorText.classifyRelayError(
      'upstream_unavailable',
    ),
    AiErrorKind.tooLarge => AiErrorText.classifyRelayError('too_large'),
    AiErrorKind.keyUnreadable => AiErrorText.classifyRelayError(
      'key_unreadable',
    ),
    AiErrorKind.noKey => AiErrorText.classifyRelayError('no_key'),
    AiErrorKind.forbiddenAddress => AiErrorText.classifyRelayError(
      'forbidden_address',
    ),
    AiErrorKind.failed => AiErrorText.classifyRelayError(null),
    AiErrorKind.providerRateLimited => AiErrorText.classifyProviderError(
      429,
      null,
    ),
    AiErrorKind.badKey => AiErrorText.classifyProviderError(401, null),
    AiErrorKind.noCredit => AiErrorText.classifyProviderError(402, null),
    AiErrorKind.modelUnavailable => AiErrorText.classifyProviderError(
      404,
      null,
    ),
    AiErrorKind.providerBusy => AiErrorText.classifyProviderError(503, null),
    AiErrorKind.badRequest => AiErrorText.classifyProviderError(400, null),
    _ => null,
  };

  /// The words of an error: the web's (`AiErrorText`), except the two
  /// rate limits, whose texts are the server's more specific ones. [detail]
  /// replaces the default where the words vary (the provider's refusal, the
  /// server's own message, a care thread's `not_found`).
  static String errorText(
    AiErrorKind kind, {
    String? detail,
    bool isAdmin = false,
  }) {
    final hasDetail = detail != null && detail.isNotEmpty;
    return switch (kind) {
      AiErrorKind.noMessages =>
        hasDetail ? detail : 'There are no messages in this range.',
      AiErrorKind.rateLimited =>
        'Too many questions in a minute. Try again shortly.',
      AiErrorKind.agentBusy =>
        'The AI is busy right now. Try again in a moment.',
      AiErrorKind.noPermission =>
        'You do not have access to this AI agent. Ask your administrator.',
      AiErrorKind.notSetUp => setupText(isAdmin: isAdmin),
      AiErrorKind.agentGone =>
        'That AI agent no longer exists. Ask your administrator.',
      AiErrorKind.emptyAnswer => 'The assistant could not answer that.',
      AiErrorKind.careNotFound => AiErrorText.classifyCareError(
        'not_found',
        isPatient: false,
      )!.message,
      AiErrorKind.careNotStarted => AiErrorText.classifyCareError(
        'not_found',
        isPatient: true,
      )!.message,
      AiErrorKind.failed ||
      AiErrorKind.providerBusy ||
      AiErrorKind.badRequest when hasDetail => detail,
      _ => info(kind)!.message,
    };
  }

  /// The one line after the words of a problem only an administrator can
  /// fix on the web (a key, credit, a model or an address); null otherwise.
  static String? hint(AiErrorKind kind, {bool isAdmin = false}) {
    final isFixedOnWeb =
        kind.isSetupProblem &&
        kind != AiErrorKind.notSetUp &&
        kind != AiErrorKind.noPermission &&
        kind != AiErrorKind.agentGone;
    if (!isFixedOnWeb) return null;
    return isAdmin
        ? 'Set it up in the web app (Admin console > AI agents).'
        : 'Ask your administrator.';
  }

  /// The words and, after a blank line, the hint.
  static String errorBody(
    AiErrorKind kind, {
    String? detail,
    bool isAdmin = false,
  }) {
    final text = errorText(kind, detail: detail, isAdmin: isAdmin);
    final line = hint(kind, isAdmin: isAdmin);
    return line == null ? text : '$text\n\n$line';
  }

  static const cancelledTitle = 'Summary cancelled';
  static const cancelledText = 'Nothing was shared. You can start again.';
}
