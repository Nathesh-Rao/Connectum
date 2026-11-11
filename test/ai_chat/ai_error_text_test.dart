import 'package:connectum/data/ai/ai_error_text.dart';
import 'package:connectum/data/ai/ai_models.dart';
import 'package:connectum/data/ai/ai_relay.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/ai_chat/ai_texts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyRelayError: the web texts for every server code', () {
    for (final (code, kind, text, needsKey) in [
      (
        'no_key',
        'no_key',
        'Connect your AI first: add your API key once.',
        true,
      ),
      (
        'key_unreadable',
        'bad_key',
        'The stored key could not be read. Add it again.',
        true,
      ),
      (
        'rate_limited',
        'rate',
        'Too many questions in a minute. Wait a little and try again.',
        false,
      ),
      (
        'too_large',
        'too_large',
        'That question came with too much data. Ask something narrower.',
        false,
      ),
      (
        'upstream_timeout',
        'timeout',
        'The AI provider took too long to answer. Try again.',
        false,
      ),
      (
        'upstream_unavailable',
        'network',
        "Can't reach the AI provider right now. Check the connection and try again.",
        false,
      ),
      (
        'forbidden_address',
        'bad',
        'The provider address is not allowed. Check the address in the key settings.',
        false,
      ),
      for (final c in [
        'test_timeout',
        'disconnected',
        'not_connected',
        'timeout',
      ])
        (
          c,
          'network',
          "Can't reach Connectum right now. Check the connection and try again.",
          false,
        ),
    ]) {
      test(code, () {
        final i = AiErrorText.classifyRelayError(code, 'ignored');
        expect(i.code, kind);
        expect(i.message, text);
        expect(i.needsKey, needsKey);
        expect(i.needsTopUp, isFalse);
      });
    }

    test('an unknown code gives the error message, else the fallback', () {
      expect(
        AiErrorText.classifyRelayError('weird', 'Odd thing').message,
        'Odd thing',
      );
      expect(
        AiErrorText.classifyRelayError('weird', '').message,
        'Something went wrong. Please try again.',
      );
      expect(
        AiErrorText.classifyRelayError(null).message,
        'Something went wrong. Please try again.',
      );
      expect(AiErrorText.classifyRelayError('weird').code, 'other');
    });
  });

  group('classifyProviderError', () {
    const noCredit =
        "Your AI provider account has no credit left. Add credit on the provider's billing page, then ask again. Your key is fine.";
    const badKey =
        'The AI provider no longer accepts this key (it may have been rotated, revoked or expired). Add the new key to continue.';
    const refused =
        'The AI provider refused this key (it may not be allowed to use this model, or it was revoked). Add a key that has access.';
    const rate =
        'The provider is limiting how fast you can ask. Wait a minute and try again.';
    const model =
        'That model is not available to this key. Open the key settings and choose a model your account can use (or clear it to use the default).';
    const busyDown =
        'The AI provider is busy or down right now. Try again in a moment.';
    const busySide =
        'The AI provider had a problem on its side. Try again in a moment.';
    Map<String, Object> err(String m) => {
      'error': {'message': m},
    };

    for (final (status, body, code, text) in <(int, Object?, String, String)>[
      (402, null, 'no_credit', noCredit),
      (
        400,
        err('Your credit balance is too low to access the API'),
        'no_credit',
        noCredit,
      ),
      (
        429,
        err('You exceeded your current quota, check your plan and billing'),
        'no_credit',
        noCredit,
      ),
      (401, null, 'bad_key', badKey),
      (401, err('insufficient credit'), 'bad_key', badKey),
      (
        400,
        err('API key not valid. Please pass a valid API key.'),
        'bad_key',
        badKey,
      ),
      (403, err('permission_denied'), 'bad_key', badKey),
      (403, null, 'bad_key', refused),
      (429, null, 'rate', rate),
      (404, null, 'model', model),
      (400, err('The model `gpt-9` does not exist'), 'model', model),
      (
        413,
        null,
        'too_large',
        'That question came with too much data. Ask something narrower.',
      ),
      (503, null, 'busy', busyDown),
      (502, null, 'busy', busyDown),
      (504, null, 'busy', busyDown),
      (529, null, 'busy', busyDown),
      (500, null, 'busy', busySide),
      (599, null, 'busy', busySide),
      (418, err('Rate limit reached, try again in 20s'), 'rate', rate),
      (400, null, 'bad', 'The AI provider could not use that request.'),
      (
        400,
        err('messages: must not be empty'),
        'bad',
        'The AI provider could not use that request: messages: must not be empty',
      ),
      (418, null, 'other', 'The AI provider returned an error (HTTP 418).'),
      (0, null, 'other', 'The AI provider returned an error (HTTP ?).'),
    ]) {
      test('$status ${body ?? ''} is $code', () {
        final i = AiErrorText.classifyProviderError(status, body);
        expect(i.code, code);
        expect(i.message, text);
        expect(i.needsTopUp, code == 'no_credit');
        expect(i.needsKey, code == 'bad_key');
      });
    }

    test('the provider message is cut to 160 characters', () {
      final i = AiErrorText.classifyProviderError(400, err('y' * 300));
      expect(
        i.message,
        'The AI provider could not use that request: ${'y' * 160}',
      );
    });

    test('a top-level message and string errors are read too', () {
      expect(
        AiErrorText.classifyProviderError(400, {'message': 'oops'}).message,
        'The AI provider could not use that request: oops',
      );
      expect(
        AiErrorText.classifyProviderError(400, {
          'error': 'invalid_api_key',
        }).code,
        'bad_key',
      );
    });
  });

  group('the app kinds use these texts', () {
    test('every socket code maps to a kind with the web text', () {
      for (final (code, kind) in [
        ('no_key', AiErrorKind.noKey),
        ('key_unreadable', AiErrorKind.keyUnreadable),
        ('too_large', AiErrorKind.tooLarge),
        ('upstream_timeout', AiErrorKind.timeout),
        ('upstream_unavailable', AiErrorKind.providerUnreachable),
        ('forbidden_address', AiErrorKind.forbiddenAddress),
        ('timeout', AiErrorKind.serverTimeout),
        ('test_timeout', AiErrorKind.serverTimeout),
        ('disconnected', AiErrorKind.offline),
        ('not_connected', AiErrorKind.offline),
      ]) {
        final e = AiRelay.fromSocket(SocketCallError(code));
        expect(e.kind, kind, reason: code);
        expect(
          AiTexts.errorText(kind),
          AiErrorText.classifyRelayError(code).message,
          reason: code,
        );
      }
    });

    test('an unknown server code keeps the server message', () {
      final e = AiRelay.fromSocket(
        const SocketCallError('whatever', 'Odd thing'),
      );
      expect(e.kind, AiErrorKind.failed);
      expect(AiTexts.errorText(e.kind, detail: e.message), 'Odd thing');
      final bare = AiRelay.fromSocket(const SocketCallError('whatever'));
      expect(
        AiTexts.errorText(bare.kind, detail: bare.message),
        'Something went wrong. Please try again.',
      );
    });

    test('provider statuses carry the status-specific text', () {
      final busy = AiRelay.fromProvider(500, null);
      expect(busy.kind, AiErrorKind.providerBusy);
      expect(
        AiTexts.errorText(busy.kind, detail: busy.message),
        contains('problem on its side'),
      );
      final down = AiRelay.fromProvider(503, null);
      expect(
        AiTexts.errorText(down.kind, detail: down.message),
        contains('busy or down'),
      );
      expect(
        AiTexts.errorText(AiErrorKind.noCredit),
        contains('no credit left'),
      );
      expect(
        AiTexts.errorText(AiErrorKind.badKey),
        contains('no longer accepts this key'),
      );
    });

    test('the two own rate-limit texts stay', () {
      expect(
        AiTexts.errorText(AiErrorKind.rateLimited),
        'Too many questions in a minute. Try again shortly.',
      );
      expect(
        AiTexts.errorText(AiErrorKind.agentBusy),
        'The AI is busy right now. Try again in a moment.',
      );
    });

    test(
      'key, credit, model and address problems are the administrator\'s',
      () {
        for (final k in [
          AiErrorKind.noKey,
          AiErrorKind.badKey,
          AiErrorKind.keyUnreadable,
          AiErrorKind.noCredit,
          AiErrorKind.modelUnavailable,
          AiErrorKind.forbiddenAddress,
        ]) {
          expect(k.isSetupProblem, isTrue, reason: '$k');
          expect(AiTexts.hint(k), 'Ask your administrator.');
          expect(
            AiTexts.hint(k, isAdmin: true),
            'Set it up in the web app (Admin console > AI agents).',
          );
          expect(AiTexts.errorBody(k), endsWith('\n\nAsk your administrator.'));
        }
        for (final k in [
          AiErrorKind.offline,
          AiErrorKind.timeout,
          AiErrorKind.failed,
          AiErrorKind.notSetUp,
        ]) {
          expect(AiTexts.hint(k), isNull, reason: '$k');
        }
      },
    );
  });
}
