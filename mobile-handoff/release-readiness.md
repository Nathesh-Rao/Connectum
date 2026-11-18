# Release readiness (Task S)

## Audit: item -> finding -> action
| Item | Finding | Action |
|---|---|---|
| `/gallery`, `/gallery/auth` and every `/debug/*` route | Were `kDebugMode`-only; no menu/link outside the gallery itself | `AppPages.build(isRelease:)` adds `_debug()` only when `!isRelease`; `pages` is `kReleaseMode ? _core() : build(...)` so release tree-shakes them |
| `START_ROUTE` | Debug-only already | `AppPages.initialFor(isRelease:, startRoute:)`; ignored in release |
| `DEMO_MODE` | Already `!kReleaseMode && flag` | One reader: `DemoMode.resolve(isRelease:, requested:)`. `SeedUi`, crash config, initial binding go through `DemoMode.isActive` or `!kReleaseMode` |
| Diagnostic logs | `notifyflow:` (socket, local notifications, feed) and `people avatars`, `enter ... failed`, form-field logs printed in release | All wrapped in `kDebugMode`. `[records]`, `[cmd]`, `REACT`, `e2e:`, `connectflow:` were already guarded |
| Sensitive logs | Nothing logs tokens, passwords, OTPs, message text, record values; `e2e: trusted new key` (user, device id) and `enter <org> failed: $e` were the closest, both now debug-only | none further |
| Test credentials / dev URLs | `10.0.2.113` only in debug/profile network configs and the unused `AppConfig.devHost` constant; OTP hint `123456` only under DemoMode | none (devHost is dead code, can be deleted) |
| TODO/FIXME | 3 `TODO(push)` in push_token_registry (server has no push.register yet), 1 in notification_router (open a submission by link) | none affect release; push is not shipped |
| Bad-certificate callbacks | All `badCertificateCallback` are under `kDebugMode` | none |

## Android
- applicationId / namespace: `com.agile.connectum`. Label `Connectum`. Launcher icon `ic_launcher` + round (adaptive).
- Version: `pubspec.yaml` `version: 1.5.0+6` -> versionName 1.5.0, versionCode 6 (via `flutter.versionName/Code`).
- SDK (Flutter 3.38.4 defaults): compileSdk 36, targetSdk 36, minSdk 24. Play requires new apps and updates to target API 35+ from 31 Aug 2025 and API 36 from Aug 2026; 36 satisfies it. No change needed (confirm in Play Console on upload).
- Permissions (main manifest): INTERNET (socket, API); CAMERA (mobile_scanner QR scan, `uses-feature camera required=false`); POST_NOTIFICATIONS (flutter_local_notifications, Android 13+). Merged: ACCESS_NETWORK_STATE (connectivity_plus). READ_EXTERNAL_STORAGE and READ_MEDIA_* are removed with `tools:node="remove"`. None unused.
- Cleartext: main manifest sets no `usesCleartextTraffic` and no network config (targetSdk 36 default: cleartext blocked). The dev-host config lives only in `src/debug` and `src/profile`. `AppConfig.validate` also refuses non-https/wss release builds.
- `android:debuggable`: not set (release = false).
- Backup: `allowBackup="false"`, `fullBackupContent` and `dataExtractionRules` exclude root/file/database/sharedpref/external for cloud backup and device transfer, so session tokens and the DB are not backed up. No change.
- R8/shrink: nothing set in `build.gradle.kts`, no `proguard-rules.pro`; Flutter's Gradle plugin applies its defaults to release. No package needs a keep rule that we know of; check the release build's R8 output and a smoke test of QR, notifications and Crashlytics on the Internal-testing build.
- Plugins: `com.google.gms.google-services` and `com.google.firebase.crashlytics` applied. `android/app/google-services.json` is committed (not git-ignored). It holds Firebase client config, not a secret; restrict the API key in Google Cloud if desired. `key.properties` is git-ignored (contents never read).
- Crashlytics collection is off in the manifest and switched on at runtime: release = on, debug/profile only with `CRASH_REPORTING=true`, demo never.

## Dependencies (direct, from pub cache)
MIT: get, dio, lottie, file_picker, quickjs_engine, pdfrx, archive. BSD-3: web_socket_channel, sqflite, path, path_provider, flutter_secure_storage, connectivity_plus, mobile_scanner, image_picker, mime, open_filex, qr_flutter, share_plus, flutter_local_notifications, video_player, firebase_core, firebase_crashlytics. Apache-2.0: app_links, webcrypto. No GPL/LGPL/MPL found. Transitive and native (Firebase SDK, pdfium, quickjs) licences not checked.

## Owner decisions
- Plain-text storage of decrypted messages in SQLite (see CLAUDE.md before-release) still needs an accept/change decision.
- Whether to keep the profile-build cleartext config.

## Build notes (run locally)
```
flutter clean && flutter pub get
flutter build appbundle --release --dart-define=BASE_URL=https://connectum.app --dart-define=WS_URL=wss://connectum.app/ws
```
No `DEMO_MODE`, `START_ROUTE` or `CRASH_REPORTING` (the first two are ignored in release anyway). Needs `android/key.properties`. Output: `build/app/outputs/bundle/release/app-release.aab`. versionCode comes from `+N` in pubspec `version: x.y.z+N`; raise N for every upload. Upload in Play Console > Testing > Internal testing first.
Warning: a release/Play install over the DEBUG-signed app needs an uninstall (signatures differ), which wipes app data and encryption keys. Test on another device or accept a fresh login. Never `flutter install` / `flutter run --release` onto the dev phone.
