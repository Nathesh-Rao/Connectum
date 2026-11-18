class CrashIdentity {
  const CrashIdentity({
    required this.userId,
    this.email = '',
    this.orgName = '',
    this.orgId = '',
  });

  final String userId;
  final String email;
  final String orgName;
  final String orgId;

  @override
  bool operator ==(Object other) =>
      other is CrashIdentity &&
      other.userId == userId &&
      other.email == email &&
      other.orgName == orgName &&
      other.orgId == orgId;

  @override
  int get hashCode => Object.hash(userId, email, orgName, orgId);
}

abstract class CrashReporter {
  bool get isEnabled;
  Future<void> init();
  void recordFatal(Object error, StackTrace stack);
  void recordNonFatal(Object error, StackTrace stack, {String? reason});
  void log(String message);
  void setIdentity(CrashIdentity identity);
  void clearIdentity();
  void setKey(String key, Object value);
}

/// Used when collection is off, when Firebase fails to start, in the demo and
/// in tests.
class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  bool get isEnabled => false;
  @override
  Future<void> init() async {}
  @override
  void recordFatal(Object error, StackTrace stack) {}
  @override
  void recordNonFatal(Object error, StackTrace stack, {String? reason}) {}
  @override
  void log(String message) {}
  @override
  void setIdentity(CrashIdentity identity) {}
  @override
  void clearIdentity() {}
  @override
  void setKey(String key, Object value) {}
}
