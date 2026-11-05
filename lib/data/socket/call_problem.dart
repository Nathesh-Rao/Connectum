import 'socket_service.dart';

enum CallProblemKind {
  offline,
  unknownOutcome,
  rateLimited,
  busy,
  notFound,
  alreadyResolved,
  forbidden,
  stale,
  duplicate,
  invalid,
  other,
}

/// What a failed `sd` call means for the screen: the words to show (the
/// server's own `error.message`, verbatim) and what to do next.
class CallProblem {
  const CallProblem(this.kind, this.text);

  static const offlineText = "You're offline. Connect and try again.";
  static const unknownOutcomeText =
      'No answer from the server. Pull to refresh to see if it went through.';
  static const fallbackText = 'Something went wrong. Try again.';

  final CallProblemKind kind;
  final String text;

  /// A manual Retry is safe: nothing reached the server, or the server said
  /// to slow down. Never offered when the outcome of a write is unknown.
  bool get canRetry =>
      kind == CallProblemKind.offline ||
      kind == CallProblemKind.rateLimited ||
      kind == CallProblemKind.busy;

  /// The card or list on screen may be out of date: read it again.
  bool get shouldRefresh =>
      kind == CallProblemKind.forbidden ||
      kind == CallProblemKind.stale ||
      kind == CallProblemKind.alreadyResolved ||
      kind == CallProblemKind.notFound ||
      kind == CallProblemKind.unknownOutcome;

  /// [isWrite]: a timeout or a drop after sending may still have been done.
  static CallProblem of(SocketCallError e, {bool isWrite = false}) {
    if (e.code == 'not_connected') {
      return const CallProblem(CallProblemKind.offline, offlineText);
    }
    if (e.isConnectionGap) {
      return isWrite
          ? const CallProblem(
              CallProblemKind.unknownOutcome,
              unknownOutcomeText,
            )
          : const CallProblem(CallProblemKind.offline, offlineText);
    }
    final kind = switch (e.code) {
      'rate_limited' => CallProblemKind.rateLimited,
      'busy' => CallProblemKind.busy,
      'not_found' => CallProblemKind.notFound,
      'already_resolved' => CallProblemKind.alreadyResolved,
      'forbidden' => CallProblemKind.forbidden,
      'stale' => CallProblemKind.stale,
      'duplicate' => CallProblemKind.duplicate,
      'invalid' => CallProblemKind.invalid,
      _ => CallProblemKind.other,
    };
    return CallProblem(kind, e.message.isEmpty ? fallbackText : e.message);
  }
}
