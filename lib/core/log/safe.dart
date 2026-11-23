import 'app_log.dart';

Future<T?> safeCall<T>(
  String tag,
  Future<T> Function() body, {
  T? fallback,
}) async {
  try {
    return await body();
  } catch (e, st) {
    AppLog.e(tag, e, st);
    return fallback;
  }
}

T? safeSync<T>(String tag, T Function() body, {T? fallback}) {
  try {
    return body();
  } catch (e, st) {
    AppLog.e(tag, e, st);
    return fallback;
  }
}

void fireAndLog(String tag, Future<void> Function() body) {
  Future<void> run() async {
    try {
      await body();
    } catch (e, st) {
      AppLog.e(tag, e, st);
    }
  }

  run();
}
