# Error handling sweep progress

Rules: CLAUDE.md "Error handling". To-do list: docs/error-handling-audit.md. Baseline `flutter analyze`: 14 infos, 0 errors.

| Layer | Status | Commit | Sites | Notes |
|---|---|---|---|---|
| 0 foundation (app_log, safe, CLAUDE.md rules) | done (earlier run, was uncommitted) | see git log "errors: foundation" | - | message_repository.dart:115,147 converted via runGuarded (reports non-fatal in all modes + debugPrint); kept as is, covered by test/core/errors/message_queue_guard_test.dart |
| 1 socket / decryption / network | done | see git log "errors: socket" | 11 unawaited->fireAndLog sites (+ all), 21 listen onError, ~14 empty/`_` catches logged, ~14 general catches after SocketCallError/ApiException, 8 other catches logged | analyze 14 = baseline; golden/scan test failures in tickets, smart_view are pre-existing UI WIP, not from this layer |
| 2 database and storage | not done | | | |
| 3 parsing and casts | not done | | | |
| 4 crypto | not done | | | |
| 5 connect and sync | not done | | | |
| 6 controllers init, notifications, nav, platform | not done | | | |
| 7 final sweep | not done | | | |

## Unsure list
- Added helper `streamOnError(tag)` to lib/core/log/safe.dart (for `.listen(onError:)`).
- message_repository `_logDropped` still uses runGuarded (kept: tested, logs and reports in all modes).
- CLAUDE.md first 3 Error-handling bullets (AppError/runGuarded/pattern doc) contradict the new rules; not edited.
- feed_repository.dart:425 catch (_) rethrows (kept).
- `.then()` chains in message_repository/smart_view_repository/command_repository pass errors to the caller (left).
