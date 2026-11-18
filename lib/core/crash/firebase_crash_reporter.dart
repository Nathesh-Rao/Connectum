import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'crash_reporter.dart';

class FirebaseCrashReporter implements CrashReporter {
  FirebaseCrashReporter({required bool isCollectionOn})
    : _wantsCollection = isCollectionOn;

  final bool _wantsCollection;
  bool _isEnabled = false;

  FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  @override
  bool get isEnabled => _isEnabled;

  @override
  Future<void> init() async {
    await _c.setCrashlyticsCollectionEnabled(_wantsCollection);
    _isEnabled = _wantsCollection;
  }

  void _run(Future<void> Function() call) {
    if (!_isEnabled) return;
    unawaited(call().catchError((_) {}));
  }

  @override
  void recordFatal(Object error, StackTrace stack) =>
      _run(() => _c.recordError(error, stack, fatal: true));

  @override
  void recordNonFatal(Object error, StackTrace stack, {String? reason}) =>
      _run(() => _c.recordError(error, stack, reason: reason));

  @override
  void log(String message) => _run(() => _c.log(message));

  @override
  void setIdentity(CrashIdentity identity) {
    _run(() => _c.setUserIdentifier(identity.userId));
    setKey('user_email', identity.email);
    setKey('org_name', identity.orgName);
    setKey('org_id', identity.orgId);
  }

  @override
  void clearIdentity() {
    _run(() => _c.setUserIdentifier(''));
    for (final key in const ['user_email', 'org_name', 'org_id']) {
      setKey(key, '');
    }
  }

  @override
  void setKey(String key, Object value) =>
      _run(() => _c.setCustomKey(key, value));
}
