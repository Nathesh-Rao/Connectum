# Diagnostic log file

Opt-in, mobile only. Profile > Logs switch (default OFF). While OFF no file exists and nothing is written.

## Files
- `lib/core/log/app_log.dart`: the only entry point (`AppLog.e/w/i`); delegates to the sink.
- `log_file_sink.dart`: state, writer (buffered, flush every 2 s or 50 lines, on pause/detach and before Save/Share), 10 MB cap, enable/disable/start-new/append.
- `log_formatter.dart`: header, entry lines, caller extraction. `log_settings_store.dart`: switch + current file (`log_settings.json` next to the logs). `log_bootstrap.dart`: set-up, lifecycle observer, user/org context.
- UI: `lib/features/settings/` (`LogsController`, `LogsSettingsTile`, `LogsOptionsSheet`, `OldLogDialog`, `LogExporter`), shown on the Profile screen.

## Where it lives
`<app support dir>/logs/ConnectumMobileLog_YYYYMMDD_HHMMSS.txt` (device local time at creation). UTF-8, `\n`.

## Format
```
2026-11-23 17:34:12.345 | E | tag @ Class.method (file.dart:791) | message
    detail line (4 spaces: first 8 stack frames, E only)
    ... repeated 3 times
```
Levels I, W, E. The caller comes from the stack and is worked out only while logging is on. Identical consecutive entries collapse. Header (80 `=` rule) is written at creation and when the switch re-starts on an existing file; a plain restart writes `SESSION START <time> | app <version>`. `CONTEXT user=... org=...` is written when the signed-in user or organisation changes.

## What is logged
Every `AppLog.e` (type and context only, never the error text), unhandled errors (Flutter, platform, isolate) with stack, `sdCall` results (action, ok/failed, code, ms), socket state and reconnects, session events, outbox events (queued, send, sent, failed, retry), form submit results (name, status, cid, posted to chat), E2E setup phase, push token and permission, notification received/opened, lifecycle, connectivity, DB open and schema version, app version change.

## Add a log line
- `AppLog.i(tag, 'what happened')` for a high-priority event, `AppLog.w` for a recoverable problem, `AppLog.e(tag, e, st, 'context')` in every catch.
- Put it at a central point, never in a hot path (per message render, per frame, per keystroke).

## API requests and responses
Every socket call (`SocketService._call`, behind `sdCall` and `hashCall`) and every REST call (`ApiLogInterceptor` on the `ApiClient` and attachment Dio) is logged as two lines sharing a counter id, only while logging is ON (`ApiLog.begin` returns null otherwise, nothing is built or redacted):
```
... | I | API #42 tstruct.submit (SubmissionRepository.flush) | -> {"name":"Ticket","values":{...}}
... | I | API #42 tstruct.submit | <- ok 312ms {"submission":{...}}
... | E | API #42 tstruct.submit | <- FAILED 312ms code=not_found message=No such conversation. {details}
... | W | API #42 tstruct.submit | <- NO RESPONSE 12000ms SocketCallError timeout
```
The file header says `API bodies: logged, secrets masked`.

### Redaction (`lib/core/log/log_redaction.dart`, applied before anything is formatted)
- Secret keys (any depth, any case, `_`/`-` ignored, also inside JSON strings): `secretKeys`, `secretKeyPrefixes` (`wrapped*`), `code` and any key containing `otp` / `verification`. The value becomes `***`.
- Sensitive actions (`sensitiveActions`, `sensitivePrefixes`: login, OTP, passwords, registration/setup, enter, session, devices, `e2e.*`): request and response are `<redacted: auth/crypto action>`; only the action, duration and ok/failed remain (failed also drops the server message).
- Message text keys (`textKeys`, flag `MASK_MESSAGE_TEXT`) become `<text N chars>`: chat text and form comments are the user's private content and add nothing to a bug report. A non-JSON request (a `#command` line) is masked the same way. Attachment file names become `<name masked>`.
- Strings over 200 chars become `<N chars>`; binary and multipart bodies become `<file upload N bytes, name masked>`.
- Lists over 20 items show the first 3 and `(+N more items)`. A body is cut at 2048 chars (8192 for failures) with `...(+N chars)`.
- Headers: only `content-type`, `content-length`, `status`, `x-request-id`.
- If redaction throws, the line says `<body not logged: redaction error>`; the raw body is never written.

### Add a sensitive key or action
Add the normalised key (lower-case, no `_`/`-`) to `secretKeys`, or the action or path prefix to `sensitiveActions` / `sensitivePrefixes`, and add the case to `test/core/log/log_redaction_test.dart`.

## Never log
Tokens, keys, recovery codes, passwords, message text or plaintext, attachment names, form field values, device ids. Request and response bodies only through `ApiLog` + `LogRedaction`, never a raw `debugPrint` or `AppLog` line of a body.

## Save and share
- Save to device: Android 10+ copies into public Downloads through MediaStore (`saveToDownloads` in `MainActivity.kt`, no permission); older Android and iOS open the system save screen (`file_picker`). Share: `share_plus`, `text/plain`.
- Upload is "Coming soon".
