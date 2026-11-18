import 'package:connectum/core/crash/crash_reporter.dart';

class FakeCrashReporter implements CrashReporter {
  FakeCrashReporter({this.isEnabled = true});

  @override
  bool isEnabled;
  final fatals = <Object>[];
  final nonFatals = <Object>[];
  final reasons = <String?>[];
  final logs = <String>[];
  final identities = <CrashIdentity>[];
  final keys = <String, Object>{};
  int clears = 0;

  @override
  Future<void> init() async {}
  @override
  void recordFatal(Object error, StackTrace stack) => fatals.add(error);
  @override
  void recordNonFatal(Object error, StackTrace stack, {String? reason}) {
    nonFatals.add(error);
    reasons.add(reason);
  }

  @override
  void log(String message) => logs.add(message);
  @override
  void setIdentity(CrashIdentity identity) => identities.add(identity);
  @override
  void clearIdentity() => clears++;
  @override
  void setKey(String key, Object value) => keys[key] = value;
}
