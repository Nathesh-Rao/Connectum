# Error handling sweep progress

Rules: CLAUDE.md "Error handling". To-do list: docs/error-handling-audit.md. Baseline `flutter analyze`: 14 infos, 0 errors.

| Layer | Status | Commit | Sites | Notes |
|---|---|---|---|---|
| 0 foundation (app_log, safe, CLAUDE.md rules) | done (earlier run, was uncommitted) | see git log "errors: foundation" | - | message_repository.dart:115,147 converted via runGuarded (reports non-fatal in all modes + debugPrint); kept as is, covered by test/core/errors/message_queue_guard_test.dart |
| 1 socket / decryption / network | not done | | | |
| 2 database and storage | not done | | | |
| 3 parsing and casts | not done | | | |
| 4 crypto | not done | | | |
| 5 connect and sync | not done | | | |
| 6 controllers init, notifications, nav, platform | not done | | | |
| 7 final sweep | not done | | | |

## Unsure list
(none yet)
