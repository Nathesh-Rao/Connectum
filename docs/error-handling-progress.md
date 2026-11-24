# Error handling sweep progress

Rules: CLAUDE.md "Error handling". To-do list: docs/error-handling-audit.md. Baseline `flutter analyze`: 14 infos, 0 errors.

| Layer | Status | Commit | Sites | Notes |
|---|---|---|---|---|
| 0 foundation (app_log, safe, CLAUDE.md rules) | done (earlier run, was uncommitted) | see git log "errors: foundation" | - | message_repository.dart:115,147 converted via runGuarded (reports non-fatal in all modes + debugPrint); kept as is, covered by test/core/errors/message_queue_guard_test.dart |
| 1 socket / decryption / network | done | see git log "errors: socket" | 11 unawaited->fireAndLog sites (+ all), 21 listen onError, ~14 empty/`_` catches logged, ~14 general catches after SocketCallError/ApiException, 8 other catches logged | analyze 14 = baseline; golden/scan test failures in tickets, smart_view are pre-existing UI WIP, not from this layer |
| 2 database and storage | done | see git log "errors: storage" | app_database open+migrate (log, rethrow, no data touched), session_store load x2 (corrupt session -> signed out, data kept), 8 empty/`_` catches logged, 1 unawaited, 3 onError | DB open failure still propagates to callers: needs your decision |
| 3 parsing and casts | done | see git log "errors: parsing" | OutboxEntry tolerant payload (+isUnreadable -> failed 'unreadable' in both outbox sends), submission _send general catch, 10 socket-event listeners wrapped (fireAndLog), push_payload catch, session_store (layer 2) | most jsonDecode sites were already guarded by FormatException |
| 4 crypto | done | see git log "errors: crypto" | e2e_crypto 6 catches log op + exception type (same null/false/E2eException results), hand_on 3, device label, encryption_policy 3, e2e_repository 2 + 8 unawaited + event listener | AppLog.e prints only type + short op, never keys/plaintext |
| 5 connect and sync | not done | | | |
| 6 controllers init, notifications, nav, platform | done | see git log "errors: controllers" | ~124 unawaited->fireAndLog, 19 listen onError, 16 unawaited_futures statements wrapped, ~23 `catch (_)` logged, 9 catch(e) without log, deep_link/connectivity onInit guarded, LinkLauncher general catch, image precache onError | main.dart skipped (your uncommitted edits) |
| 7 final sweep | done | (with layer 6) | listen without onError: 0; empty catches: 0 | remaining accepted: lib/core/crash internals (reporter must never throw), core/errors/run_guarded unawaited, main.dart:80 |

## Unsure list
- Added helper `streamOnError(tag)` to lib/core/log/safe.dart (for `.listen(onError:)`).
- message_repository `_logDropped` still uses runGuarded (kept: tested, logs and reports in all modes).
- CLAUDE.md first 3 Error-handling bullets (AppError/runGuarded/pattern doc) contradict the new rules; not edited.
- feed_repository.dart:425 catch (_) rethrows (kept).
- `.then()` chains in message_repository/smart_view_repository/command_repository pass errors to the caller (left).
- form_logic_runner.dart:40 (`jsonDecode(json) as Map` after Isolate.run, dev conformance runner) left unguarded: return type non-null.
- int.parse on regex digit groups (sv_cell_format 176-180, sv_preview_parsers 189-193,290) could throw on huge digit runs; left.
- Inline listen closures (non-identifier handlers) only got onError, not a wrapped body.
- main.dart not touched (uncommitted user edits): unawaited(_start()) at :80, SmartViewPrefs.load/SystemChrome unguarded.
- Disk hit 99% during test runs ("no space left on device"); some directory test runs (authentication, forms, profile_photo, link_browser, home_shell, splash, support) were therefore not verified cleanly; analyze is clean.
- Pre-existing failures not from this work: golden tests (smart_view, tickets, inbox), typed Get.toNamed scan (forms_picker_controller:172, workspace_controller:393, conversation_controller:652).
- Not wrapped: qr_share_service.shareImage, sv_file_repository saveFile, Clipboard.setData calls.
