# Connectum Mobile

## Stack
- Flutter, Android + iOS. State, DI and routing: GetX. Local DB: sqflite with hand-written SQL (no drift, no ORM). Realtime: WebSocket to the Erlang backend.

## Backend reference
- The backend contract is in `mobile-handoff/`. Before writing or changing code for the socket, session, messages, forms, deep links or AI, read the matching doc: `websocket-protocol.md`, `messages-and-receipts.md`, `sessions.md`, `forms.md`, `deep-links.md`, `ai-and-misc.md`.
- Never guess the protocol. If a doc says UNCLEAR, ask the user.
- `postman/api_collection_connectum.json` holds the REST endpoints with example responses. If it disagrees with `mobile-handoff/`, ask the user instead of picking one.
- The approved UI design is in `reference/prototype`.

## Architecture (keep it simple)
- Feature-first: `lib/features/<feature>/{<feature>_controller.dart, <feature>_view.dart, <feature>_binding.dart, models/}`. Shared code in `lib/core/` (theme, widgets, utils, routes) and `lib/data/` (db, socket, repositories).
- Every screen = one GetxController + one `GetView<Controller>` + one Binding. Views are UI only. Controllers hold logic and state.
- `Get.find` / `Get.put` / `Get.lazyPut` are allowed ONLY in Binding files (and one app-level InitialBinding for permanent services). Never in views, widgets or controllers. Dependencies reach controllers through constructors.
- Concrete classes only. No abstract classes, interfaces, use-case classes, mappers or generic base classes unless asked. One repository class per domain.
- `Obx` with the smallest possible scope. No `setState` in screens.

## Routing
- Route names are constants in `lib/core/routes/app_routes.dart`. GetPage list with bindings in `app_pages.dart`. Auth and organisation guards are `GetMiddleware`.
- Any screen that can be opened from an external link takes its parameters from the route. A link received before login or organisation selection is kept as a pending link and opened afterwards.

## UI consistency
- Design source: `reference/prototype` (code) and `reference/screenshots`. Match spacing, radii, colors, type and motion timings.
- Tokens are plain static const classes: AppColors, AppSpacing, AppRadius, AppText, AppShadows, AppDurations/AppCurves. One light theme, no dark mode, no ThemeExtension, no theme generators. Never hardcode colors, sizes or durations inside widgets.
- Shared widgets in `lib/core/widgets`, prefixed App: AppTextField, AppButton, AppScaffold, AppStateView, AppBottomSheet, AppAvatar, AppStatusPill. Screens never use raw TextField or ElevatedButton.
- AppTextField is the only text field: min height via constraints (never SizedBox height), isDense, explicit symmetric contentPadding, textAlignVertical center, fixed line height, so text is always vertically centered.
- AppScaffold keeps designed screens packed to the viewport (LayoutBuilder + scroll view with a minHeight constraint, spacing via Spacer/Expanded) so a page scrolls only when the keyboard covers content. Never replace a designed screen with a plain ListView.
- Every list and screen handles loading, empty and error with retry through AppStateView. Cached-first screens (Chats, conversation, Submissions, workspace) never show an offline state: they show the cached data with the dark offline bar only, and an empty cache shows the normal empty state. Only connection-only screens (login, OTP, create account, set up) show the offline state. State pictures are PNGs in `assets/images/states/`, shown by AppStateImage (one enum maps state to file and display scale). AppAnimationPlaceholder (visible label like "[animation: empty-chats]") is only the fallback when a file is missing or fails. Lottie (`lottie` package) is used only for the onboarding slides (OnboardingLottie) and the success check (AppSuccessAnimation).
- Min font sizes: 11 for labels/captions, 12 for readable text.

## Workspace and forms
- "My Work Space" is local to the app: a pinned row above the chat list (never archived, always first, shown in every list state) and a `/workspace` screen of my submissions with a welcome message. The server has a `workspace` host kind but `/hostmsg` refuses it; never send workspace text to the server. Details in `mobile-handoff/workspace.md`.
- The forms button is in every composer (encrypted chats and the workspace too). A form posted from a DM or group carries `chat` (`dm:<user>` or `group:<name>`); from the workspace, global or a team, it carries none. Forms are never end-to-end encrypted: the form screen says so in an encrypted chat.
- A form save (`tstruct.user.submit` / `tstruct.submit` by the option's `targetScope`, `submissions.update`, `submission.resubmit`) goes through the outbox with one stable `cid` per save; a pending form message is written into the chat at once.

## Naming
- snake_case files. `<Feature>Controller` / `<Feature>View` / `<Feature>Binding`. `App*` for core tokens and widgets. Token classes have a private constructor (`AppColors._()`). Booleans start with is/has/should. Models are plain names: Message, Conversation, FormSubmission.

## Data
- Message ids are generated by the server. The client shows a local temp id (`temp-<timestamp>`) until the server ack arrives, then swaps to the server id.
- Delivered/read ticks only where the backend provides them (direct messages). A local pending state shows until the server ack.
- SQLite is the source of truth for the UI. The WebSocket and API only write into it. Controllers read from it.
- Every row is scoped by organisation id and user id.

## Sessions
- On a `session_replaced` event or a handshake error, clear that organisation's token and local session and send the user to login with a notice.
- Reconnect delay uses backoff with a cap, not a fixed delay.

## Offline
- SQLite is the UI's only source. The app opens offline with everything cached. Login, OTP, attachments and the AI tab need a connection and show the offline state instead of queuing.
- Sending writes the row and an outbox entry at once. States: pending -> sending -> sent -> delivered/read (DMs only). `failed` only for non-retryable server refusals (permission, encrypted chat, validation) or an unconfirmed delivery; a network drop never fails a message.
- The outbox is persistent and flushes on socket online, network regain, app resume and after login: one chat command in flight per conversation, in order, paced under 30 commands per 10 s. Every DM, group and host send and reply carries a client id (`cid`, `m-` plus a UUID) and goes out as `/c <cid> <command>`; acks are matched by cid, `duplicate:true` is a normal ack, and a retry reuses the cid. An entry first sent more than 23 hours ago fails with "couldn't confirm delivery" and tap-to-retry (the server remembers an id for one day). Only global-room messages, which cannot take an id, are still reconciled against fetched history before a re-send. Forms use `meta.clientId` the same way. Older history pages with `before <id>`; after a reconnect the latest page must contain my last known id (no numeric id comparison) or the sync pages back, at most 10 pages per conversation.
- Encrypted DMs: text and replies are sent encrypted (`EncryptionPolicy.decide` is the only rule for plain/encrypt/blocked; the envelope is built at flush time; never downgraded to plain). Encrypted groups send and read like DMs, and `#`, edits and attachments stay blocked in encrypted threads.
- `session_replaced`: wipe that org+user rows and outbox, go to login. Handshake error or expired token: clear the token, keep rows and outbox, go to login, flush after login. Explicit sign out: wipe. Only a real auth error clears the token; "Username taken" retries with backoff.

## Release signing
- `android/key.properties` (git-ignored, created by the user, never read or printed by Claude) holds: `storePassword`, `keyPassword`, `keyAlias`, `storeFile` (path to the `.jks`, relative to `android/app/`). A release build without it fails; debug builds use the debug key.
- Release: `flutter build appbundle --release --dart-define=BASE_URL=https://connectum.app --dart-define=WS_URL=wss://connectum.app/ws`. Never `flutter install` / `flutter run --release` onto the dev phone (a release-signed install over the debug one forces an uninstall and deletes its encryption keys).

## Before release
- Remove `NSAllowsLocalNetworking` from `ios/Runner/Info.plist` and the debug-only `android/app/src/debug/res/xml/network_security_config.xml`; confirm release is https/wss only (`AppConfig.validate`); remove the `/debug/socket`, `/debug/assets` and `/gallery` routes (with `lib/features/gallery/widgets/avatar_samples.dart`, the avatar palette sample, and the AppSpinner and pull-header samples in `gallery_view.dart`) and `lib/core/debug/seed_ui.dart` (`SEED_UI=1` fixture: debug builds only, in-memory sample enterprises and about 13 sample chats, `SEED_ROWS=300` adds generated rows; turn it on with `--dart-define=SEED_UI=1`, best without `BASE_URL`); remove the `/debug/connect` route and `lib/features/debug_connect/`; remove the `/debug/e2e` route, `lib/features/debug_e2e/` (including `hand_on_vectors.dart`), `assets/debug/e2e-rewrap-vectors.json` and its `pubspec.yaml` asset entry and the `mobile-handoff/e2e-vectors.json` entry under `assets:` in `pubspec.yaml` (Flutter cannot bundle an asset for debug only; `lib/data/e2e/` stays); remove the "Remove this device" and "Register this phone" buttons on the `/debug/e2e` screen (they go with the route); remove the "Show device limit sheet (sample devices)" button on the same screen (it goes with the route; the sheet itself, `lib/features/security/widgets/device_limit_sheet.dart`, stays); document and accept, or change, "decrypted text stored unencrypted on the device" (the `plaintext` column of `messages` and the decrypted `last_text` of `conversations`; the envelope is kept as received); check backups: `android:allowBackup="false"` with `fullBackupContent` (`res/xml/backup_rules.xml`) and `dataExtractionRules` (`res/xml/data_extraction_rules.xml`) excluding database, sharedpref, file, root and external; iOS: the databases folder is flagged `isExcludedFromBackup` (`AppDatabase._open` via the `connectum/device` channel) and every `FlutterSecureStorage` uses `first_unlock_this_device` (the Keychain is not restored onto another device), and inspect a release build's merged manifest to confirm; remove `lib/core/debug/seed_connect.dart` and the debug-only "Simulate scan" chips/button in `lib/features/connect/widgets/scanner_pane.dart` (`_SimulateScan`); remove the `/debug/qr` route, `lib/features/debug_qr/` and `lib/core/debug/seed_qr.dart` (sample QR data and `QrSampleRepository`; the real `QrRepository` implementation replaces it); remove the `/debug/tasks` route, `lib/features/debug_tasks/` and `lib/core/debug/seed_tasks.dart` (sample tasks and requests answered in place of the server, injected events; also the `SeedTasks` branches in `task_repository.dart`, `approval_repository.dart` and `task_people_controller.dart`); remove the `/debug/tickets` route, `lib/features/debug_tickets/`, `lib/core/debug/seed_tickets.dart` (the captured `status.*` replies answer in place of the server; also the `SeedTickets` branches in `ticket_repository.dart` and `task_people_controller.dart`), `assets/debug/tickets/` and its `pubspec.yaml` asset entry; remove the `/debug/chat` route and `lib/features/debug_chat/` (sample messages for mentions, forwards, edits, quotes, day separators); remove the `/debug/notifications` route and `lib/features/debug_notifications/` (sample feed items, local notification test); remove the `/debug/commands` route, `lib/features/debug_commands/` and `lib/core/debug/seed_commands.dart` (the `#` commands doc catalogue as a fixture, fake suggestions with latency, stale-reply, `unknown_command` and `usage` simulators; no server calls); remove the temporary `notifyflow:` logs (`debugPrint` lines in `local_notification_service.dart`, `feed_repository.dart` `onEvent`, and `socket_service.dart` `onInit` / `didChangeAppLifecycleState`); remove the debug-only `REACT frame` / `REACT event` prints in `socket_service.dart` (`sendCommand`) and `message_repository.dart` (`_onReaction`).
- App Store export compliance: Info.plist deliberately has no `ITSAppUsesNonExemptEncryption` (own end-to-end encryption); the team answers the App Store Connect export-compliance questions.
- Icon: made from the 1206x1305 web logo (`connectum.app/connectum-logo.png`, speckle cleaned, white background); sources in `branding/icon/`, regenerate with `dart run flutter_launcher_icons`, then `git checkout ios/Runner.xcodeproj/project.pbxproj` (the tool edits it). `ic_launcher_round.png` and `branding/play_store_icon_512.png` came from a Pillow script outside the repo. Follow-ups: themed (monochrome) icon layer, a branded native splash (Android 12 splash icon, iOS LaunchImage is a 1x1 placeholder), a vector or higher-res logo source.
- Permissions: the release manifest has only INTERNET and ACCESS_NETWORK_STATE (connectivity_plus) plus androidx's own `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. Future features: QR scanner needs CAMERA and `uses-feature camera required=false` (and `NSCameraUsageDescription` on iOS); push needs POST_NOTIFICATIONS (Android 13+); typed location stays manual (no location permission).

## Working rules
- After a task, run `dart analyze` on changed files and run on the device when relevant. Do NOT run flutter test, integration, viewport or VM tests, or full builds unless asked.
- Small changes. Before adding a package, tell the user why in one sentence.
- No extra docs and no comments beyond what the code needs.
