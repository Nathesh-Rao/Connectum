# Crashlytics (Android only, production only)

Plan/log: precondition ok (`google-services.json`: project `connectum-5cb41`, package `com.agile.connectum`). No handlers existed before (`FlutterError.onError`, `PlatformDispatcher` untouched), so the hooks chain after the defaults. Session signal = `SessionStore.current` / `identity` (Rx), so one binder covers sign-in, restore, org switch and every sign-out path. Gradle: plugins in `settings.gradle.kts` (`google-services` 4.4.4, `firebase.crashlytics` 3.0.6), applied in `app/build.gradle.kts`; no AGP/Gradle/Kotlin/minSdk change was needed (minSdk 24 from Flutter). Debug build verified.

## Installed
- `firebase_core`, `firebase_crashlytics` (pubspec). Code: `lib/core/crash/`. Manifest: `firebase_crashlytics_collection_enabled=false`; code turns it on.
- Collection: `crashCollectionEnabled` = `!DEMO_MODE && (release || --dart-define=CRASH_REPORTING=true)`. Otherwise `NoopCrashReporter`; a Firebase failure/timeout (5 s) also falls back to it. Swap a fake with `CrashService.current = CrashService(fake)`.
- Fatal: `FlutterError.onError`, `PlatformDispatcher.onError`, isolate error listener (previous handlers still run first; with reporting off nothing changes).
- Non-fatal: only unexpected errors (`isExpectedError`), through `CrashService.nonFatal`: `ApiClient` (Dio failures, bad response), WS frame parse, workspace sync catch-all. Same type+message once per 60 s, 20 per run. Reported as `SanitizedError(type, cleaned message)`.
- Identity (owner decision): user id, and keys `user_email`, `org_name`, `org_id`. Switch off in `crash_config.dart`: `kCrashIncludeEmail`, `kCrashIncludeOrgName` (key set to empty). Cleared on sign-out, expired session, password-changed sign-out.
- Keys: `app_version`, `tab`, `screen` (route name without arguments; debounced 500 ms).
- Breadcrumbs: only `CrashBreadcrumbs.add(Crumb.x, code:)`; code a-z0-9_- up to 24 chars. Sites: route observer, home tab, `#` command name, lifecycle + WS state (`SocketService`), Smart View open/mode/filter, file preview kind, sign-in/out/org switch.

## Never sent
Tokens, passwords, OTPs, message text, file names/URLs/contents, record/form/submission values, hidden fields, Smart View data, phone numbers, bodies, full URLs. `CrashSanitizer` masks tokens, JWTs, URLs, emails, secret key=values, 8+ digit runs, 24-hex ids, 40+ char blobs, and cuts to 300 chars. Parse errors and Dio errors report their type only.
Limit: fatal reports and stack traces are Crashlytics' own and cannot be cleaned by the app; we only keep sensitive data out of keys and logs.

## Verify (owner)
1. `flutter run --dart-define=BASE_URL=https://connectum.app --dart-define=WS_URL=wss://connectum.app/ws --dart-define=CRASH_REPORTING=true --dart-define=START_ROUTE=/debug/crashtest`
2. On the screen: status says Collection enabled: yes. Tap "Send breadcrumb", "Record non-fatal error", then "Fatal native crash" (confirm).
3. Relaunch from the phone launcher (not from flutter run); fatals upload on the next launch.
4. Firebase console > Crashlytics > connectum-5cb41; the report appears within a few minutes. The first ever crash may need "Enable Crashlytics" in the console.

## Release
- Play Console Data safety: crash logs, device identifiers, and email (while `kCrashIncludeEmail` is on).
- Release is built without `--obfuscate`: no Dart symbol upload needed. R8 mapping upload is the Crashlytics Gradle plugin's default. If obfuscation is ever turned on, add `--split-debug-info=<dir>` and upload the symbols with the Firebase CLI.
- Remove `/debug/crashtest` and `lib/features/debug_crashtest/` before release (CLAUDE.md).
