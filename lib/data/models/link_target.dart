/// What a link option resolved to: the address with the person's own details
/// and the one-time ticket in it. Never logged and never stored.
class LinkTarget {
  const LinkTarget({required this.url, required this.name});

  final String url;
  final String name;
}

/// Why a link could not be opened, in words fit for the person.
class LinkOpenError implements Exception {
  const LinkOpenError(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;

  @override
  String toString() => 'LinkOpenError';
}
