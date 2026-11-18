import 'dart:async';
import 'dart:io';

import 'package:connectum/core/crash/crash_bootstrap.dart';
import 'package:connectum/core/crash/crash_breadcrumbs.dart';
import 'package:connectum/core/crash/crash_config.dart';
import 'package:connectum/core/crash/crash_hooks.dart';
import 'package:connectum/core/crash/crash_identity_binder.dart';
import 'package:connectum/core/crash/crash_reporter.dart';
import 'package:connectum/core/crash/crash_route_observer.dart';
import 'package:connectum/core/crash/crash_sanitizer.dart';
import 'package:connectum/core/crash/crash_service.dart';
import 'package:connectum/core/crash/expected_errors.dart';
import 'package:connectum/data/api/api_client.dart';
import 'package:connectum/data/models/identity_info.dart';
import 'package:connectum/data/models/session_info.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_crash_reporter.dart';

IdentityInfo _identity() => const IdentityInfo(
  token: 't',
  email: 'ann@example.com',
  enterprises: [
    EnterpriseMembership(
      enterprise: 'o1',
      name: 'Acme',
      city: '',
      category: '',
      username: 'ann',
      status: 'active',
    ),
    EnterpriseMembership(
      enterprise: 'o2',
      name: 'Beta',
      city: '',
      category: '',
      username: 'ann',
      status: 'active',
    ),
  ],
);

void main() {
  group('collection rule', () {
    test('matrix', () {
      for (final isDemo in [false, true]) {
        for (final isRelease in [false, true]) {
          for (final isFlagged in [false, true]) {
            expect(
              crashCollectionEnabled(
                isDemo: isDemo,
                isRelease: isRelease,
                isFlagged: isFlagged,
              ),
              !isDemo && (isRelease || isFlagged),
              reason: '$isDemo $isRelease $isFlagged',
            );
          }
        }
      }
    });
  });

  group('bootstrap', () {
    test('failure falls back to Noop', () async {
      final r = await createCrashReporter(
        isCollectionOn: true,
        initFirebase: () async => throw StateError('no firebase'),
        makeReporter: (_) => FakeCrashReporter(),
      );
      expect(r, isA<NoopCrashReporter>());
    });

    test('timeout falls back to Noop', () async {
      final r = await createCrashReporter(
        isCollectionOn: true,
        initFirebase: () => Completer<void>().future,
        makeReporter: (_) => FakeCrashReporter(),
        timeout: const Duration(milliseconds: 20),
      );
      expect(r, isA<NoopCrashReporter>());
    });

    test(
      'enabled uses the real reporter, disabled and demo use Noop',
      () async {
        final fake = FakeCrashReporter();
        final on = await createCrashReporter(
          isCollectionOn: true,
          initFirebase: () async {},
          makeReporter: (_) => fake,
        );
        expect(on, same(fake));
        final off = await createCrashReporter(
          isCollectionOn: false,
          initFirebase: () async {},
          makeReporter: (_) => FakeCrashReporter(isEnabled: false),
        );
        expect(off, isA<NoopCrashReporter>());
        final demo = await createCrashReporter(
          isDemo: true,
          isCollectionOn: true,
          initFirebase: () async => fail('must not start'),
        );
        expect(demo, isA<NoopCrashReporter>());
      },
    );
  });

  group('hooks', () {
    late FlutterExceptionHandler? savedFlutter;
    late bool Function(Object, StackTrace)? savedPlatform;

    setUp(() {
      savedFlutter = FlutterError.onError;
      savedPlatform = PlatformDispatcher.instance.onError;
    });
    tearDown(() {
      FlutterError.onError = savedFlutter;
      PlatformDispatcher.instance.onError = savedPlatform;
    });

    test('Flutter errors keep the old handler and report fatal', () {
      var previous = 0;
      FlutterError.onError = (_) => previous++;
      final reporter = FakeCrashReporter();
      installCrashHooks(reporter, shouldListenToIsolate: false);
      final error = StateError('x');
      FlutterError.onError!(FlutterErrorDetails(exception: error));
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('quiet'), silent: true),
      );
      expect(previous, 2);
      expect(reporter.fatals, [error]);
    });

    test('platform errors report fatal and return true when enabled', () {
      final reporter = FakeCrashReporter();
      installCrashHooks(reporter, shouldListenToIsolate: false);
      final handled = PlatformDispatcher.instance.onError!(
        StateError('y'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(reporter.fatals, hasLength(1));
    });

    test('disabled reporter keeps today\'s behaviour', () {
      var previous = 0;
      PlatformDispatcher.instance.onError = (_, _) {
        previous++;
        return false;
      };
      installCrashHooks(
        const NoopCrashReporter(),
        shouldListenToIsolate: false,
      );
      expect(
        PlatformDispatcher.instance.onError!(StateError('z'), StackTrace.empty),
        isFalse,
      );
      expect(previous, 1);
    });
  });

  group('isExpectedError', () {
    DioException dio(DioExceptionType t, {int? status, Object? error}) =>
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: t,
          error: error,
          response: status == null
              ? null
              : Response(
                  requestOptions: RequestOptions(path: '/x'),
                  statusCode: status,
                ),
        );

    test('expected', () {
      for (final code in [
        'stale',
        'forbidden',
        'not_found',
        'invalid',
        'invalid_values',
        'bad_request',
        'busy',
        'rate_limited',
        'otp_invalid',
        'password_history_unavailable',
      ]) {
        expect(isExpectedError(ApiException(code, '')), isTrue, reason: code);
        expect(isExpectedError(SocketCallError(code)), isTrue, reason: code);
      }
      for (final s in [401, 403, 404, 409, 429]) {
        expect(isExpectedError(ApiException('x', '', status: s)), isTrue);
        expect(
          isExpectedError(dio(DioExceptionType.badResponse, status: s)),
          isTrue,
        );
      }
      expect(isExpectedError(const ApiException('network', 'x')), isTrue);
      expect(isExpectedError(const SocketException('x')), isTrue);
      expect(isExpectedError(TimeoutException('x')), isTrue);
      expect(isExpectedError(const HandshakeException('x')), isTrue);
      expect(isExpectedError(const SocketCallError('timeout')), isTrue);
      expect(isExpectedError(const SocketCallError('session_expired')), isTrue);
      expect(isExpectedError(const SocketCallError('session_ended')), isTrue);
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.cancel,
      ]) {
        expect(isExpectedError(dio(t)), isTrue, reason: '$t');
      }
      expect(
        isExpectedError(
          dio(DioExceptionType.unknown, error: const SocketException('x')),
        ),
        isTrue,
      );
    });

    test('unexpected', () {
      expect(isExpectedError(StateError('boom')), isFalse);
      expect(isExpectedError(const FormatException('bad')), isFalse);
      expect(
        isExpectedError(const ApiException('bad_response', '', status: 200)),
        isFalse,
      );
      expect(
        isExpectedError(const ApiException('network', '', status: 500)),
        isFalse,
      );
      expect(isExpectedError(const SocketCallError('error')), isFalse);
      expect(
        isExpectedError(dio(DioExceptionType.badResponse, status: 500)),
        isFalse,
      );
    });
  });

  group('CrashService', () {
    test('only unexpected errors, deduped for 60 s, capped at 20', () {
      var now = DateTime(2026);
      final r = FakeCrashReporter();
      final s = CrashService(r, now: () => now);
      s.reportNonFatal(const ApiException('stale', ''), null);
      expect(r.nonFatals, isEmpty);
      s.reportNonFatal(StateError('a'), null);
      s.reportNonFatal(StateError('a'), null);
      expect(r.nonFatals, hasLength(1));
      expect(r.nonFatals.single, isA<SanitizedError>());
      now = now.add(const Duration(seconds: 61));
      s.reportNonFatal(StateError('a'), null);
      expect(r.nonFatals, hasLength(2));
      for (var i = 0; i < 40; i++) {
        s.reportNonFatal(StateError('e$i'), null);
      }
      expect(r.nonFatals, hasLength(20));
    });

    test('a disabled reporter is never called', () {
      final r = FakeCrashReporter(isEnabled: false);
      CrashService(r).reportNonFatal(StateError('a'), null);
      expect(r.nonFatals, isEmpty);
    });

    test('keys are debounced', () async {
      final r = FakeCrashReporter();
      final s = CrashService(r, keyDebounce: const Duration(milliseconds: 20));
      s.setKeyLater('screen', '/a');
      s.setKeyLater('screen', '/b');
      expect(r.keys, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(r.keys, {'screen': '/b'});
    });
  });

  group('CrashSanitizer', () {
    String c(String s) => CrashSanitizer.clean(s);

    test('masks sensitive shapes', () {
      expect(c('auth Bearer abc.def-123_x=='), isNot(contains('abc.def')));
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      expect(c('tok $jwt'), isNot(contains('eyJ')));
      expect(c('mail ann@example.com now'), 'mail <email> now');
      expect(
        c('GET https://connectum.app/api?token=abc&x=1 failed'),
        'GET <url> failed',
      );
      expect(c('call 9876543210 now'), 'call <num> now');
      expect(c('id 507f1f77bcf86cd799439011 x'), 'id <id> x');
      expect(c('blob ${'A1b2' * 15} end'), 'blob <blob> end');
      expect(c('password=hunter2 otp: 123456'), 'password=*** otp=***');
      expect(c('ws 1006 ok'), 'ws 1006 ok');
    });

    test('truncates to 300', () {
      expect(c('ab ' * 200).length, 300);
    });

    test('error text that can carry content is left out', () {
      expect(sanitizeError(const FormatException('secret body')).message, '');
      final dio = DioException(
        requestOptions: RequestOptions(path: 'https://x.test/a?token=1'),
        type: DioExceptionType.badResponse,
        message: 'https://x.test/a?token=1',
        response: Response(
          requestOptions: RequestOptions(path: '/a'),
          statusCode: 500,
        ),
      );
      expect(sanitizeError(dio).message, 'badResponse 500');
    });
  });

  group('identity', () {
    late SessionStore store;
    late FakeCrashReporter r;
    setUp(() {
      store = SessionStore();
      r = FakeCrashReporter();
      CrashService.current = CrashService(r);
    });

    void signIn(String org) =>
        store.current.value = SessionInfo(orgId: org, userId: 'ann');

    test('set on sign-in, restore and org switch; cleared on sign-out', () {
      store.identity.value = _identity();
      signIn('o1'); // restore and sign-in look the same: the store changes
      final binder = CrashIdentityBinder(store, r);
      expect(r.identities.last.email, 'ann@example.com');
      expect(r.identities.last.orgName, 'Acme');
      signIn('o2');
      expect(r.identities.last.orgName, 'Beta');
      expect(r.identities.last.orgId, 'o2');
      expect(r.logs, contains('sign_in'));
      expect(r.logs, contains('org_switched'));
      store.current.value = null; // sign-out, expired, password changed
      expect(r.clears, 1);
      expect(r.logs, contains('sign_out'));
      binder.dispose();
    });

    test('sign-in after the binder exists', () {
      final binder = CrashIdentityBinder(store, r);
      expect(r.identities, isEmpty);
      store.identity.value = _identity();
      signIn('o1');
      expect(r.identities.last.userId, 'ann');
      binder.dispose();
    });

    test('email and org name can be switched off', () {
      store.identity.value = _identity();
      signIn('o1');
      final binder = CrashIdentityBinder(
        store,
        r,
        config: const CrashConfig(includeEmail: false, includeOrgName: false),
      );
      expect(r.identities.last.email, '');
      expect(r.identities.last.orgName, '');
      expect(r.identities.last.orgId, 'o1');
      binder.dispose();
    });
  });

  group('breadcrumbs', () {
    test('format limits the code', () {
      expect(
        CrashBreadcrumbs.format(Crumb.command, code: 'tstruct'),
        'cmd:tstruct',
      );
      expect(CrashBreadcrumbs.format(Crumb.wsClosed), 'ws_closed');
      expect(
        CrashBreadcrumbs.format(Crumb.screen, code: '/Debug Me/ø?x'),
        'screen:_debug_me___x',
      );
      final long = CrashBreadcrumbs.format(Crumb.tab, code: 'a' * 60);
      expect(long, 'tab:${'a' * 24}');
      expect(long.length, lessThanOrEqualTo(100));
    });

    test('goes to the reporter and the recent list', () {
      final r = FakeCrashReporter();
      CrashService.current = CrashService(r);
      for (var i = 0; i < 7; i++) {
        CrashBreadcrumbs.add(Crumb.tab, code: 'n$i');
      }
      expect(r.logs, hasLength(7));
      expect(CrashService.current.recentCrumbs, hasLength(5));
      expect(CrashService.current.recentCrumbs.last, 'tab:n6');
    });

    test('screen names carry no arguments', () {
      expect(crashScreenName('/conversation/abc123'), '/conversation');
      expect(crashScreenName('/chats?x=1'), '/chats');
      expect(crashScreenName('/debug/crashtest'), '/debug/crashtest');
      expect(crashScreenName(null), '/');
    });
  });
}
