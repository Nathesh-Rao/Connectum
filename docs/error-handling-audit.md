# Error handling audit

Read-only audit of `lib/` (579 production Dart files; `lib/demo`, `lib/core/debug` and `lib/features/debug_*` excluded from every count). Counts come from a regex scan plus a `dart analyze` run with extra lints in a scratch copy (the repo's `analysis_options.yaml` was not touched). Regex counts are approximate; file:line references were checked by hand.

## 1. How errors are handled today

There is no single error type. Four families exist, each owned by a layer:

| Type | Where | Used for |
|---|---|---|
| `ApiException(code, message, status, details)` | `lib/data/api/api_client.dart:12` | REST via Dio. `ApiClient` maps Dio failures to codes (`network`, `rate_limited`, `bad_response`, ...). Non-expected ones go to `CrashService.nonFatal` (`:147`, `:229`). |
| `SocketCallError(code, message, details)` | `lib/data/socket/socket_service.dart:29` | WebSocket `sdCall` / `hashCall` (`:428`). `isConnectionGap` = `timeout` / `disconnected` / `not_connected`. The server `{ok:false, error:{code,message}}` envelope becomes this. |
| `CallProblem` (`kind`, `text`, `canRetry`, `shouldRefresh`) | `lib/data/socket/call_problem.dart:19` | Maps a `SocketCallError` to words and next step for a screen. `isWrite:` turns a timeout into "unknown outcome". Used in 6 files (tasks, tickets, approvals). |
| Domain exceptions | `AttachmentException`, `SvFileException`, `SvSaveException`, `ProfilePhotoException`, `PhotoPickException`, `E2eException`, `HandOn*`, `AiError`, `LinkOpenError`, `UnsupportedStep`, `FormLogicAssetsException` | One per feature, no shared base. |
| `FormLogicResult<T>.ok/failed` | `lib/data/form_logic/form_logic_service.dart:15` | "Calls never throw" for the JS engine. The only Result-style type. |

Helpers:
- `AppNotices.show(...)` (`lib/core/widgets/app_notices.dart`): the one snackbar-like notice, no `BuildContext`. 30 call sites.
- `AppStateView` + `AppViewState` (loading/empty/error/offline/content) with retry: 18 views.
- Crash side: `lib/core/crash/` (`CrashService.nonFatal`, `isExpectedError` in `expected_errors.dart`, `CrashSanitizer`, `Crumb` enum). `CrashService.nonFatal` has only 4 call sites (`api_client.dart:147,229`, `socket_service.dart:223`, `workspace_repository.dart:193`).
- No `Result`/`Either`, no `AppError`, no mapper from exception to user text outside `CallProblem` (sockets only) and per-repository `_plainReason` (`submission_repository.dart:844`).

**Best pattern to standardise on: the outbox send path + `CallProblem`.**
`SubmissionRepository._onSendError` (`submission_repository.dart:791`) classifies by cause: connection gap goes back to `pending` (never fails), `in_progress` / `rate_limited` / `busy` go to `pending` with jittered `next_attempt_ts`, a bad chat target fails with a specific reason, `invalid_values` keeps the server details for the form, everything else becomes `failed` with a plain reason and tap-to-retry. `flush()` (`:670`) guards with `_isFlushing` and releases it in `finally` (`:691`). For screens, `TasksController.load` (`tasks_controller.dart:150-170`) is the model: stale-response guard (`seq`), keep cached content on error, `AppViewState.error` vs `offline` by connectivity, `CallProblem.of(e)` for the message, `finally` resets `isLoadingMore` (`:190`).

## 2. Global safety nets

| Net | Status |
|---|---|
| `FlutterError.onError` | Present: `installCrashHooks` (`crash_hooks.dart:14`) chains the old handler, then `recordFatal` unless `silent`. |
| `PlatformDispatcher.instance.onError` | Present (`crash_hooks.dart:27`). Returns `true` only when reporting is enabled; with reporting off the error is passed on. |
| Isolate error listener | Present (`crash_hooks.dart:34`). |
| Crash reporting | Present: Firebase Crashlytics, init guarded by a 5 s timeout with Noop fallback (`crash_bootstrap.dart:12`). Sanitised, deduped (60 s), capped (20 per run). |
| `runZonedGuarded` | **Missing.** `main()` is not zoned; `PlatformDispatcher.onError` covers most uncaught async errors, so this is optional. |
| `ErrorWidget.builder` | **Missing.** A build error shows Flutter's red/grey box in release. Only `form_field_boundary.dart:43` handles `ErrorWidget` locally for form fields. |
| GetX error handling | None configured (no `Get.config`, no `onError` on `GetMaterialApp`). |
| Hooks installed before config check | Yes, good. Hooks start before `AppConfig.validate()`. |
| `main()` itself | `SmartViewPrefs.load()` and the `SystemChrome` calls are un-guarded; a throw there is a blank screen. `AppSettings.version().then(..., onError: (_) {})` (`main.dart:35`) is fine. |

## 3. Risky call sites by layer

Raw totals across production code: `catch` clauses 236 (83 files), with `on` clause 164, `catch (_)` 92 (44 files), `jsonDecode` 41 (26 files), `int.parse` 22 (5 files), `double.parse` 21 (6), `as Map/List/String/int/...` casts 189 (47), `.first/.last/.single` 162 (60), `[0]` 173 (30), `!` 627 (190), `.listen(` 52 (34), `unawaited(` 181 (44), `.then(` 20 (13).

| Layer | Files | Worst offenders |
|---|---|---|
| (a) Network / API / socket | `api_client.dart`, `socket_service.dart`, 20 repositories call `sdCall` | Mostly sound: timeouts, `isConnectionGap`, backoff capped at 15 s (`_maxBackoff` in `socket_service.dart`), frame parse guarded (`:221`, reported). Weak spot: casts on the envelope, e.g. `submission_repository.dart:736,742,777` (`data['submission'] as Map` throws `TypeError`, which `_onSendError` does not catch since it only takes `SocketCallError`). `api_client.dart` `_unwrap` casts `data['data'] as Map?`. |
| (b) Local DB / storage | `lib/data/db/app_database.dart` (1 file) + repositories, `session_store.dart`, `sv_prefs.dart`, `attachment_cache.dart` | `app_database.dart:191-196`: `openDatabase` / `migrate` (version 14) has no try/catch, no recovery: a failed migration is an unrecoverable startup. `sv_prefs.dart:50`, `attachment_cache.dart:104,283`, `app_database.dart:189` are empty catches. `session_store.dart:35,75` `jsonDecode(raw) as Map` throws on a corrupt stored session. |
| (c) JSON / model parsing | `lib/data/models/` (27 files), 41 `jsonDecode` | `outbox_entry.dart:60` casts decoded payload unguarded (a corrupt row poisons the outbox read); `conversation.dart:190,204,215` are inside try. `form_logic_runner.dart:40` unguarded. `sv_values.dart:44-47` `int.parse(m[n]!)` on regex groups (safe by regex shape); `sv_cell_format.dart` 5 and `sv_preview_parsers.dart` 3 `int.parse` on server text. |
| (d) File / IO / image / permission / platform channels | `attachment_cache.dart`, `form_file_repository.dart`, `profile_photo_picker.dart`, `link_launcher.dart`, `install_referrer.dart`, `app_database.dart` (`connectum/device` channel) | `form_file_repository.dart:109` empty catch on `File.delete`; `app_database.dart:189` and `attachment_cache.dart:104,283` empty catches on a platform channel. Photo picker and attachments have typed exceptions (good). |
| (e) Encryption / keys / recovery | `lib/data/e2e/` (8 files), `e2e_repository.dart`, `encryption_policy.dart` | `e2e_crypto.dart` has 6 `catch (_)` (`:47,160,347,471,519,603`) that turn any failure into null/false: a wrong key and a bug look identical. `encryption_policy.dart:360,392` empty `on SocketCallError catch (_)`. `e2e_device_label.dart:17` empty. |
| (f) Push / local notifications | `local_notification_service.dart`, `push_service.dart`, `feed_repository.dart` | `local_notification_service.dart:183` empty catch around `requestPermissions`; `:157` `catch (_)`; `:450` `.catchError((_) {})` on `setRead`. temporary "notifyflow" `debugPrint` logs are listed in CLAUDE.md for removal. |
| (g) Outbox / sync / background | `submission_repository.dart`, `message_repository.dart`, `conversation_repository.dart` | `message_repository.dart:111-115` event queue and `:145-147` decrypt queue end with `.catchError((Object _) {})`: a throwing `_handle(e)` silently drops that socket event with no log and no report. `conversation_repository.dart:307,310` empty catches around syncing. Outbox itself is good (see section 5). |
| (h) Navigation / deep links | `deep_link_service.dart`, `connect_controller.dart` | `deep_link_service.dart:143` empty catch (referrer read; acceptable, flagged inconclusive). `:341,349` `.then(...)` chains with no `onError`. `connect_controller.dart:239,263,569` empty catches on scan/claim paths: a failed claim shows nothing. |
| (i) Controller lifecycle | 76 controllers; 34 `onInit`/`onReady` bodies start async work | `profile_controller.dart:63` `AppSettings.version().then(...)` no error handler. `conversation_controller.dart` has 17 `unawaited`, 5 `catch (_)` (`:1293,1330,1464` swallow). 70 `isClosed`/`mounted` guards exist, so after-dispose updates are partly handled. |
| (j) Forms engine / expressions | `lib/data/form_logic/` (5 files), `lib/features/forms/` | Best isolated: JS runs in an isolate, `FormLogicResult` never throws, timeout restarts the engine. Risk is only the unguarded decode at `form_logic_runner.dart:40`. |

## 4. Bad patterns (production code only)

| Pattern | Count | Notes |
|---|---|---|
| Empty catch blocks `catch (_) {}` / `on X catch (_) {}` | **28** in 17 files | Top 30 list below. `empty_catches` lint does not fire because `_` is exempt. |
| `catch (_)` with a body (silent fallback) | 92 total (64 beyond the 28 empty) | Most return null/false. |
| Catch without `on` clause (lint `avoid_catches_without_on_clauses`) | **68** | Includes `Error`s (OOM, `StateError`, `TypeError`) caught as flow control. |
| `catch Error` (lint `avoid_catching_errors`) | 3 | |
| `unawaited(...)` explicit fire-and-forget | **181** in 44 files | The explicit wrapper silences the lint but adds no error handling; whether the callee catches must be checked per call. Highest: `conversation_controller.dart` 17, `form_controller.dart` 14, `message_repository.dart` 12, `connect_controller.dart` 11, `submission_repository.dart` 9. |
| Un-awaited futures the lint can still see | 16 | `unawaited_futures` violations. |
| `discarded_futures` | 234 | Mostly sync callbacks that start futures (`onTap: () => load()`); noisy, not all bugs. |
| `.then(...)` with no `onError` | most of 20 | `main.dart:35` ok; `profile_controller.dart:63`, `deep_link_service.dart:341,349`, `splash_controller.dart:141`, `smart_view_repository.dart:632`. |
| `.catchError((_) {})` | 5 | `message_repository.dart:115,147` (+1), `firebase_crash_reporter.dart`, `local_notification_service.dart:450`. |
| `onError: (_) {}` | 3 | `session_repository.dart:129,210`, `main.dart:37` (logout best-effort; acceptable). |
| `.listen(` with `onError` | 1 of 52 (`socket_service.dart:196` handles it separately) | Broadcast event streams in repositories have no `onError`; a thrown error inside a listener bubbles to `PlatformDispatcher.onError`. |
| `async void` | 0 | Good. |
| Force-unwrap `!` | 627 in 190 files | Not all server data. |
| `as` casts on server/decoded data | 189 in 47 files | See (a), (c). |
| `.first` / `.last` / `.single` | 162 in 60 files | Most guarded by `isEmpty`; `message_repository.dart:226,441` use `rows.first` after an aggregate query (safe). Not individually verified. |
| `[0]` | 173 in 30 files | Same. |
| `jsonDecode` | 41 in 26 files | Guarded: `conversation.dart`, `e2e_crypto.dart:47`. Unguarded: `outbox_entry.dart:60`, `session_store.dart:35,75`, `form_logic_runner.dart:40`. |
| `int.parse` / `double.parse` | 22 / 21 | `sv_values.dart` (12) regex-shaped; `sv_cell_format.dart` (5) and `sv_preview_parsers.dart` (3) take server text. |
| Missing `finally` on loading flags | Not systematically measurable; 88 `finally` blocks exist and 25 `isLoading = true` sites. Spot checks (tasks, flush, deep links) are right. | |
| `debugPrint` | 26 | Some are the temporary "notifyflow" logs. No `print`. |

Top 30 swallowing sites (all empty catches, then the worst silent ones):

1. `lib/core/routes/initial_binding.dart:297` (version fetch)
2. `lib/core/routes/deep_link_service.dart:143`
3. `lib/features/connect/connect_controller.dart:239`
4. `lib/features/connect/connect_controller.dart:263`
5. `lib/features/connect/connect_controller.dart:569`
6. `lib/features/chats/new_chat_controller.dart:95`
7. `lib/features/chats/new_chat_controller.dart:107`
8. `lib/data/repositories/session_repository.dart:169` (logout; acceptable)
9. `lib/data/repositories/command_repository.dart:243`
10. `lib/data/repositories/command_repository.dart:274`
11. `lib/data/repositories/command_repository.dart:301`
12. `lib/data/repositories/conversation_repository.dart:307`
13. `lib/data/repositories/conversation_repository.dart:310`
14. `lib/data/repositories/encryption_policy.dart:360`
15. `lib/data/repositories/encryption_policy.dart:392`
16. `lib/data/repositories/auth_repository.dart:360`
17. `lib/data/repositories/auth_repository.dart:496`
18. `lib/data/repositories/form_file_repository.dart:109`
19. `lib/data/attachment_cache.dart:104`
20. `lib/data/attachment_cache.dart:283`
21. `lib/data/db/app_database.dart:189`
22. `lib/data/smart_view/sv_prefs.dart:50`
23. `lib/data/e2e/e2e_device_label.dart:17`
24. `lib/data/notifications/local_notification_service.dart:183`
25. `lib/core/utils/app_settings.dart:13`
26. `lib/core/crash/crash_service.dart:60,68,84` (reporter must never throw; acceptable)
27. `lib/data/repositories/message_repository.dart:115` (`catchError` drops socket event)
28. `lib/data/repositories/message_repository.dart:147` (`catchError` drops decrypt pass)
29. `lib/data/e2e/e2e_crypto.dart:160,347,471,519,603` (catch-all to null)
30. `lib/features/conversation/conversation_controller.dart:1293,1330,1464` (silent fallbacks)

Acceptable-by-design among these: crash reporter internals, best-effort logout, iOS backup-exclusion channel, referrer read. Real risks: 3, 4, 5 (connect), 12, 13 (sync), 14, 15 (encryption mode), 17, 27, 28, 29.

## 5. Already handled well (keep as references)

- Outbox classification: `submission_repository.dart:791-842` (`_onSendError`), `:670-692` (`flush` with `_isFlushing` and `finally`), `:844` `_plainReason`.
- Screen list state with stale guard and cached-first behaviour: `tasks_controller.dart:150-192`.
- Message → words mapping: `call_problem.dart:19-70`.
- `sdCall` timeout and drop handling: `socket_service.dart:428-470` (listens to the answer before the send waits, `answer.ignore()` on failed send).
- Frame parse guarded and reported: `socket_service.dart:221-223`.
- Crash hooks chaining: `crash_hooks.dart`, `crash_bootstrap.dart` (timeout plus Noop fallback), `expected_errors.dart` (what is never reported).
- `FormLogicResult` "never throws" contract: `form_logic_service.dart:15`.
- Deep link start: `try { ... } finally { _ready.complete(); }` (`deep_link_service.dart:125-129`).
- `AppConfig.validate()` before `runApp` (`main.dart:41`).

## 6. Lint status

`analysis_options.yaml` is just `include: package:flutter_lints/flutter.yaml` plus `exclude: backup/**`. flutter_lints already enables `empty_catches`, `avoid_print`, `use_build_context_synchronously`, `no_logic_in_create_state`, `use_rethrow_when_possible`. Counts below are for production code (debug and demo excluded), from a scratch copy with the extra rules enabled:

| Lint | In flutter_lints? | Violations |
|---|---|---|
| `avoid_catches_without_on_clauses` | no | **68** |
| `unawaited_futures` | no | **16** |
| `discarded_futures` | no | **234** (noisy; do not enable globally) |
| `avoid_catching_errors` | no | 3 |
| `only_throw_errors` | no | 0 |
| `empty_catches` | yes | 0 (exempts `_`; the 28 empty catches are not flagged) |
| `avoid_print` | yes | 0 |
| `use_build_context_synchronously` | yes | 0 |
| `use_rethrow_when_possible` | yes | 0 |
| `no_logic_in_create_state` | yes | 0 |

## 7. Biggest gaps

1. Silent drop of socket events and decrypt passes (`message_repository.dart:115,147`).
2. No recovery when the DB open or a migration fails (`app_database.dart:191`).
3. Unguarded casts on server and stored data (`submission_repository.dart:736,742,777`, `outbox_entry.dart:60`, `session_store.dart:35,75`) where `_onSendError` only handles `SocketCallError`.
4. Encryption catch-alls that return null for every failure (`e2e_crypto.dart`, 6 sites), so a bug is indistinguishable from a wrong key.
5. Connect/claim paths and sync paths that fail with no user feedback (`connect_controller.dart:239,263,569`, `conversation_repository.dart:307,310`).
Also: no `ErrorWidget.builder`, `CrashService.nonFatal` used in only 4 places, and 181 fire-and-forget calls with no shared guard.
