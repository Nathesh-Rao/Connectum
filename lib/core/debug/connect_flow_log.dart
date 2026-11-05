/// TEMPORARY: step names and booleans of the connect flow, never a code, a
/// link or a name. Remove with every `ConnectFlowLog.` call.
class ConnectFlowLog {
  ConnectFlowLog._();

  static void log(String step, [Map<String, Object?> flags = const {}]) {
    final detail = flags.entries.map((e) => '${e.key}=${e.value}').join(' ');
    // ignore: avoid_print
    print('connectflow: $step${detail.isEmpty ? '' : ' $detail'}');
  }

  /// The file:line that called the function that called this.
  static String caller() {
    final frames = StackTrace.current.toString().split('\n');
    if (frames.length < 4) return '?';
    return frames[3].replaceFirst(RegExp(r'^#\d+\s+'), '');
  }
}
