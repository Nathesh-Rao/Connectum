import '../socket/socket_service.dart';
import 'ai_error_text.dart';
import 'ai_models.dart';

/// The pure parts of the `assistant.relay` call: the provider body, the text
/// in the answer and the mapping of every error in the BE doc.
class AiRelay {
  AiRelay._();

  static const maxTokens = 1800;
  static const timeoutMs = 30000;
  static const wait = Duration(seconds: 40);

  /// The provider's own request body (section 3.4 of the doc): the transcript
  /// is inside [system] as `CHAT IN FOCUS`, the question is the one user turn;
  /// no tools, one round.
  static Map<String, dynamic> payload(
    AiAgent agent, {
    required String system,
    required String question,
  }) {
    final model = agent.model;
    switch (agent.provider) {
      case 'anthropic':
        return {
          if (model.isNotEmpty) 'model': model,
          'max_tokens': maxTokens,
          'temperature': 0,
          'system': system,
          'messages': [
            {'role': 'user', 'content': question},
          ],
        };
      case 'gemini':
        return {
          'systemInstruction': {
            'parts': [
              {'text': system},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': question},
              ],
            },
          ],
          'generationConfig': {'temperature': 0},
        };
      default:
        return {
          if (model.isNotEmpty) 'model': model,
          'temperature': 0,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': question},
          ],
        };
    }
  }

  /// The answer text of a 2xx provider body, or '' when there is none.
  static String text(String provider, Object? body) {
    if (body is! Map) return '';
    switch (provider) {
      case 'anthropic':
        final content = body['content'];
        if (content is! List) return '';
        return content
            .whereType<Map>()
            .where((p) => p['type'] == 'text')
            .map((p) => '${p['text'] ?? ''}')
            .join();
      case 'gemini':
        final candidates = body['candidates'];
        if (candidates is! List || candidates.isEmpty) return '';
        final first = candidates.first;
        final parts = first is Map && first['content'] is Map
            ? (first['content'] as Map)['parts']
            : null;
        if (parts is! List) return '';
        return parts.whereType<Map>().map((p) => '${p['text'] ?? ''}').join();
      default:
        final choices = body['choices'];
        if (choices is! List || choices.isEmpty) return '';
        final first = choices.first;
        final message = first is Map ? first['message'] : null;
        return message is Map ? '${message['content'] ?? ''}' : '';
    }
  }

  /// A failed `sd` envelope or a lost connection.
  static AiError fromSocket(SocketCallError e) {
    switch (e.code) {
      case 'timeout':
      case 'test_timeout':
        return const AiError(AiErrorKind.serverTimeout);
      case 'disconnected':
      case 'not_connected':
        return const AiError(AiErrorKind.offline);
      case 'no_agent':
        return const AiError(AiErrorKind.notSetUp);
      case 'no_access':
        return const AiError(AiErrorKind.noPermission);
      case 'not_found':
        return const AiError(AiErrorKind.agentGone);
      case 'no_key':
        return const AiError(AiErrorKind.noKey);
      case 'key_unreadable':
        return const AiError(AiErrorKind.keyUnreadable);
      case 'forbidden_address':
        return const AiError(AiErrorKind.forbiddenAddress);
      case 'rate_limited':
        return AiError(
          _isAgentBusy(e.message)
              ? AiErrorKind.agentBusy
              : AiErrorKind.rateLimited,
        );
      case 'too_large':
        return const AiError(AiErrorKind.tooLarge);
      case 'upstream_timeout':
        return const AiError(AiErrorKind.timeout);
      case 'upstream_unavailable':
        return const AiError(AiErrorKind.providerUnreachable);
      default:
        final info = AiErrorText.classifyRelayError(e.code, e.message);
        return AiError(
          AiErrorKind.failed,
          e.message.isEmpty ? null : info.message,
        );
    }
  }

  /// The two limits share the code `rate_limited`; only the server's text
  /// differs: "The AI is busy right now. Try again in a moment." is the
  /// per-agent one, "Too many questions in a minute. Try again shortly." the
  /// per-person one (also the answer when the text is missing).
  static bool _isAgentBusy(String message) =>
      message.toLowerCase().contains('busy');

  /// A relay answer whose `data.status` is not 2xx, classified as the web
  /// does (`AiErrorText`). The words that vary by status travel in the
  /// error's message.
  static AiError fromProvider(int status, Object? body) {
    final info = AiErrorText.classifyProviderError(status, body);
    return switch (info.code) {
      'no_credit' => const AiError(AiErrorKind.noCredit),
      'bad_key' => const AiError(AiErrorKind.badKey),
      'rate' => const AiError(AiErrorKind.providerRateLimited),
      'model' => const AiError(AiErrorKind.modelUnavailable),
      'too_large' => const AiError(AiErrorKind.tooLarge),
      'busy' => AiError(AiErrorKind.providerBusy, info.message),
      'bad' => AiError(AiErrorKind.badRequest, info.message),
      _ => AiError(AiErrorKind.failed, info.message),
    };
  }
}
