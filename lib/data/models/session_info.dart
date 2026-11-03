class SessionInfo {
  const SessionInfo({
    required this.orgId,
    required this.userId,
    this.expiresTs,
  });

  final String orgId;
  final String userId;
  final int? expiresTs;

  bool get isExpired =>
      expiresTs != null && expiresTs! < DateTime.now().millisecondsSinceEpoch;
}
