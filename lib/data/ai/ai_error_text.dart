/// What went wrong with an assistant call, in words a person can act on.
/// A pure port of the web's `assistantErrors.js` (`chat-app/features/
/// connectumChat/services/`): the texts are the web's, do not tidy them.
class AiErrorInfo {
  const AiErrorInfo(
    this.code,
    this.message, {
    this.needsKey = false,
    this.needsTopUp = false,
  });

  /// no_key, bad_key, no_credit, rate, model, busy, timeout, network,
  /// too_large, bad or other.
  final String code;
  final String message;

  /// The key must be added again (not possible on the phone).
  final bool needsKey;

  /// The provider account needs credit (not possible on the phone).
  final bool needsTopUp;
}

class AiErrorText {
  AiErrorText._();

  static final _credit = RegExp(
    r'insufficient[_ ]?(quota|funds|balance|credit)|exceeded your current quota|credit balance is too low|out of credit|no credits?|any credits|some credits|billing|payment required|add (a )?payment|purchase (more )?credits|plan and billing|balance is (too )?low|quota (has been )?exceeded for (this )?(billing|account)|resource has been exhausted.*billing|top up',
  );
  static final _keyBad = RegExp(
    r'invalid[_ ]api[_ ]?key|incorrect api key|api key (not valid|is invalid|expired|revoked)|authentication[_ ]error|invalid x-api-key|unauthorized|permission[_ ]denied|api_key_invalid|key (has )?expired|expired|revoked|not authorized',
  );
  static final _rate = RegExp(
    r'rate[_ ]?limit|too many requests|requests per|tokens per|try again in',
  );
  static final _model = RegExp(r'model');
  static final _modelGone = RegExp(
    r'(not found|does not exist|not supported|unknown|invalid)',
  );

  static const _noCredit =
      "Your AI provider account has no credit left. Add credit on the provider's billing page, then ask again. Your key is fine.";
  static const _badKey =
      'The AI provider no longer accepts this key (it may have been rotated, revoked or expired). Add the new key to continue.';
  static const _refusedKey =
      'The AI provider refused this key (it may not be allowed to use this model, or it was revoked). Add a key that has access.';
  static const _rate429 =
      'The provider is limiting how fast you can ask. Wait a minute and try again.';
  static const _modelText =
      'That model is not available to this key. Open the key settings and choose a model your account can use (or clear it to use the default).';
  static const _tooLarge =
      'That question came with too much data. Ask something narrower.';
  static const _busyDown =
      'The AI provider is busy or down right now. Try again in a moment.';
  static const _busySide =
      'The AI provider had a problem on its side. Try again in a moment.';
  static const _connectum =
      "Can't reach Connectum right now. Check the connection and try again.";

  static String _lower(Object? body) {
    if (body is! Map) return '';
    final e = body['error'];
    final eMap = e is Map ? e : null;
    final parts = <Object?>[
      e is String ? e : eMap?['message'],
      eMap?['code'],
      eMap?['type'],
      eMap?['status'],
      body['message'],
      body['detail'],
      body['error_description'],
    ];
    return parts.whereType<String>().join(' | ').toLowerCase();
  }

  /// The provider's answer that was not a success: its HTTP [status] and
  /// [body].
  static AiErrorInfo classifyProviderError(int status, Object? body) {
    final t = _lower(body);
    if (status == 402 || (status != 401 && _credit.hasMatch(t))) {
      return const AiErrorInfo('no_credit', _noCredit, needsTopUp: true);
    }
    if (status == 401 ||
        (_keyBad.hasMatch(t) && (status == 400 || status == 403))) {
      return const AiErrorInfo('bad_key', _badKey, needsKey: true);
    }
    if (status == 403) {
      return const AiErrorInfo('bad_key', _refusedKey, needsKey: true);
    }
    if (status == 429) return const AiErrorInfo('rate', _rate429);
    if (status == 404 ||
        (status == 400 && _model.hasMatch(t) && _modelGone.hasMatch(t))) {
      return const AiErrorInfo('model', _modelText);
    }
    if (status == 413) return const AiErrorInfo('too_large', _tooLarge);
    if (status == 529 || status == 503 || status == 502 || status == 504) {
      return const AiErrorInfo('busy', _busyDown);
    }
    if (status >= 500) return const AiErrorInfo('busy', _busySide);
    if (_rate.hasMatch(t)) return const AiErrorInfo('rate', _rate429);
    if (status == 400) {
      final raw = _raw(body);
      return AiErrorInfo(
        'bad',
        'The AI provider could not use that request'
            '${raw.isEmpty ? '.' : ': ${raw.length > 160 ? raw.substring(0, 160) : raw}'}',
      );
    }
    return AiErrorInfo(
      'other',
      'The AI provider returned an error (HTTP ${status == 0 ? '?' : status}).',
    );
  }

  static String _raw(Object? body) {
    if (body is! Map) return '';
    final e = body['error'];
    final fromError = e is Map ? e['message'] : null;
    if (fromError is String && fromError.isNotEmpty) return fromError;
    final m = body['message'];
    return m is String ? m : '';
  }

  /// An error of the server's own relay (the `sd` envelope's `code`), with the
  /// error's own [message] for a code that is not listed.
  static AiErrorInfo classifyRelayError(String? code, [String? message]) {
    switch (code) {
      case 'no_key':
        return const AiErrorInfo(
          'no_key',
          'Connect your AI first: add your API key once.',
          needsKey: true,
        );
      case 'key_unreadable':
        return const AiErrorInfo(
          'bad_key',
          'The stored key could not be read. Add it again.',
          needsKey: true,
        );
      case 'rate_limited':
        return const AiErrorInfo(
          'rate',
          'Too many questions in a minute. Wait a little and try again.',
        );
      case 'too_large':
        return const AiErrorInfo('too_large', _tooLarge);
      case 'upstream_timeout':
        return const AiErrorInfo(
          'timeout',
          'The AI provider took too long to answer. Try again.',
        );
      case 'upstream_unavailable':
        return const AiErrorInfo(
          'network',
          "Can't reach the AI provider right now. Check the connection and try again.",
        );
      case 'forbidden_address':
        return const AiErrorInfo(
          'bad',
          'The provider address is not allowed. Check the address in the key settings.',
        );
      case 'test_timeout':
      case 'disconnected':
      case 'not_connected':
      case 'timeout':
        return const AiErrorInfo('network', _connectum);
      default:
        return AiErrorInfo(
          'other',
          message == null || message.isEmpty
              ? 'Something went wrong. Please try again.'
              : message,
        );
    }
  }
}
