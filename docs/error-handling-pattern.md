# Error handling pattern

Built on what exists: `ApiException`, `SocketCallError`, `CallProblem`, `AppNotices`, `AppStateView`, `CrashService`. One new type (`AppError`) and one new helper (`runGuarded`) in `lib/core/errors/`. Nothing is rewritten; each batch moves a layer onto the pattern.

## 1. Principles

1. Catch at boundaries (repository call, controller action, platform channel, parse of outside data), not in every method.
2. Catch a specific type (`on SocketCallError`, `on FormatException`). A bare `catch (_)` is allowed only for best-effort cleanup, and needs a one-line reason.
3. Every catch does one of three things: **handle** (set state and tell the person), **translate** (throw an `AppError`), or **rethrow**. Never swallow silently. A deliberate ignore is `on X catch (_) { /* why */ }` and still counts a `Crumb`.
4. `finally` for every loading flag, lock and `_isFlushing`.
5. Log with context through `CrashService.nonFatal(e, s, 'what failed')` and `Crumb`. Never log tokens, keys, message text, record values, file names, URLs or phone numbers (existing rule; `CrashSanitizer` enforces it).
6. Expected errors (offline, refusal, timeout) are never reported; they are in `isExpectedError`.

## 2. Error model

Keep `ApiException` and `SocketCallError` as the transport errors. Add one thing:

```dart
// lib/core/errors/app_error.dart
enum ErrorKind { network, offline, timeout, unauthorized, forbidden, notFound,
  invalid, conflict, server, parse, storage, permission, cancelled, unknown }

class AppError implements Exception {
  const AppError(this.kind, this.message, {this.isRetryable = false, this.code, this.cause, this.stack});
  final ErrorKind kind;
  final String message;      // user-safe, never raw server or exception text
  final bool isRetryable;
  final String? code;        // server code, for logic only
  final Object? cause;       // never shown, never logged raw
  final StackTrace? stack;
}
```

One mapper, `AppError.from(Object e, {bool isWrite = false})`, reusing the existing rules:
- `SocketCallError`: `not_connected` -> offline; `timeout`/`disconnected` -> offline for reads, **timeout (unknown outcome)** for writes (same as `CallProblem.of`); `forbidden`, `not_found`, `invalid`/`invalid_values`, `stale`/`already_resolved` -> conflict, `rate_limited`/`busy` -> retryable.
- `ApiException`: `status` 401 -> unauthorized, 403 -> forbidden, 404 -> notFound, 429 -> retryable, `network` -> network, `bad_response` -> server.
- `FormatException`, `TypeError` on outside data -> parse; `DatabaseException`, `FileSystemException` -> storage; `PlatformException` permission codes -> permission; `TimeoutException` -> timeout.

`CallProblem` becomes a thin adapter over `AppError` (same texts) so the 6 files that use it do not change in the first batches. The server's own `error.message` stays the shown text when present (as `CallProblem` does today).

## 3. Layer rules

- **Repository / service**: translate, no UI. Catch transport errors, throw `AppError` (or return the existing result types). Write to SQLite first, then the network (existing rule). No `AppNotices` here.
- **Controller**: state plus retry. Pattern is `TasksController.load`:
```dart
Future<void> load() async {
  final seq = ++_seq;
  viewState.value = items.isEmpty ? AppViewState.loading : viewState.value;
  try {
    final page = await repo.list();
    if (seq != _seq) return;
    items.assignAll(page);
    viewState.value = items.isEmpty ? AppViewState.empty : AppViewState.content;
  } on AppError catch (e) {
    if (seq != _seq) return;
    if (items.isNotEmpty) { AppNotices.show(e.message, variant: AppNoticeVariant.error); }
    else { viewState.value = e.kind == ErrorKind.offline ? AppViewState.offline : AppViewState.error; }
  } finally {
    isBusy.value = false;
  }
}
```
Cached-first screens never show the offline state, only the offline bar (CLAUDE.md). A write whose outcome is unknown says so and offers refresh, never blind retry.
- **Widgets**: no try/catch for business logic; they render `AppStateView` and call controller methods. `use_build_context_synchronously` stays on.
- **Outbox / background**: never throws out of `flush()`. Connection gap -> `pending`; busy/rate-limited -> `pending` with jittered `next_attempt_ts`; refusal -> `failed` with a plain reason; first attempt older than 23 h -> "couldn't confirm delivery". Add to `_onSendError`'s caller a `catch` for non-socket errors (cast, storage): mark `failed` with a generic reason and report once, never leave the row `sending`.
- **Parsing**: tolerant. Use the existing `idText`/`intOf` style helpers; `jsonDecode` of stored or server data goes through `tryDecodeMap(String?)` (returns null, not throws); `int.tryParse`; no `as Map` on decoded data, use `is Map`. A bad row is skipped and counted, not fatal.
- **Platform channels / permissions**: catch `PlatformException` and `MissingPluginException` at the service; return a result with `denied` / `permanentlyDenied` / `unavailable`. Permanently denied offers "Open settings" (`AppSettings`). Never block app start on a channel.
- **Encrypted chat flows**: a message is never lost. Decrypt failure keeps the envelope and shows a placeholder; send failure keeps the outbox row. Separate "wrong key / locked" (user guidance: unlock, trust new key) from "bug" (report once). `e2e_crypto.dart` catch-alls become `on FormatException` / `on E2eException` so unexpected errors are reported, not turned into null. Never downgrade to plain.

## 4. Fire-and-forget

```dart
// lib/core/errors/run_guarded.dart
void runGuarded(Future<void> Function() job, {String? reason, void Function(AppError)? onError}) {
  unawaited(() async {
    try { await job(); }
    on AppError catch (e) { onError?.call(e); }
    catch (e, s) {
      CrashService.nonFatal(e, s, reason);   // expected errors are filtered inside
      onError?.call(AppError.from(e));
    }
  }());
}
```
Rule: bare `unawaited(x())` is allowed only if `x` documents "never throws" (e.g. `flush`). Otherwise `runGuarded(() => x(), reason: 'flush outbox')`. Stream listeners that call async code use `onError:` or `runGuarded` inside. The event queue in `message_repository.dart:115` logs with `CrashService.nonFatal` instead of `catchError((_) {})`.

## 5. Global setup

Crash hooks already exist. Add only the missing pieces, in `main()` after `installCrashHooks`:

```dart
ErrorWidget.builder = (d) => const AppFriendlyError();   // release only; debug keeps the red box
// SmartViewPrefs.load(), SystemChrome calls: wrap in try/catch, fall back to defaults.
runApp(...)   // PlatformDispatcher.onError already covers uncaught async errors; runZonedGuarded not needed
```
`ErrorWidget.builder` returns a small widget in the app's style (no stack, no text from the error). Logger plug-in point stays `CrashService` (non-fatal, sanitised, deduped, capped); no second logger. `DatabaseException` on open: show `AppConfigError`-style screen with "Reset local data" (wipes scope, keeps token) instead of a blank start.

## 6. Review checklist (any new code)

- [ ] Every `await` on network/DB/IO/platform is inside a boundary that handles or translates.
- [ ] No `catch (_) {}`; every `catch` names a type unless reasoned.
- [ ] Loading flags and locks reset in `finally`.
- [ ] No `unawaited(x())` without `runGuarded` unless `x` never throws.
- [ ] Outside data: `tryDecode`, `is` checks, `tryParse`, `firstOrNull`; no `!`/`as` on it.
- [ ] Screen has loading, empty, error+retry (`AppStateView`); cached-first shows no offline state.
- [ ] User text is user-safe; no raw exception text, no secrets in logs.
- [ ] Write with unknown outcome says so and refreshes; never silent retry of a non-idempotent write (cid makes sends safe).
- [ ] Listeners cancelled in `onClose`; updates after dispose guarded (`isClosed`).

**Lints** (violations from the audit): enable now `avoid_catches_without_on_clauses` (68), `unawaited_futures` (16), `avoid_catching_errors` (3), `only_throw_errors` (0). Fix the 28 empty catches by hand (the `empty_catches` lint does not see `_`). Do **not** enable `discarded_futures` (234, mostly sync callbacks); revisit after the clean-up. Turn on at the end of each batch for the directories already fixed, via `// ignore_for_file` removal, not all at once, so CI stays green.

## 7. Proposed CLAUDE.md rule

```
## Error handling
- Follow `docs/error-handling-pattern.md`. Catch at boundaries with a specific `on` type; every catch handles (state + notice), translates (`AppError.from`) or rethrows. No `catch (_) {}`.
- Repositories translate and never touch UI; controllers hold `AppViewState` + retry and use `AppNotices` for messages; widgets never try/catch business logic.
- Reset loading flags and locks in `finally`. Fire-and-forget uses `runGuarded`, never a bare `unawaited(x())`.
- Outside data (server, SQLite, prefs, platform) is parsed tolerantly: no `!` or `as` on it; `tryParse`, `is` checks, `firstOrNull`.
- Never put tokens, keys, message text or record values in logs; report only via `CrashService.nonFatal`.
```

## C. Implementation plan

Order is smallest and safest first. "UI" = changes what the person sees (needs your approval).

| # | Batch | Files | Risk | Verify | UI |
|---|---|---|---|---|---|
| 1 | Foundation: `AppError` + mapper + `runGuarded` + `ErrorWidget.builder` + guard `main()` prefs/SystemChrome | new `lib/core/errors/*` (3), `main.dart` | Low (additive) | analyze, unit tests for mapper, `flutter build apk --debug` | **Yes**: friendly error widget replaces the red/grey box in release |
| 2 | API / sdCall layer: `ApiClient._unwrap` and envelope casts return `AppError`/`parse`; `CallProblem` adapts to `AppError` | `api_client.dart`, `socket_service.dart`, `call_problem.dart`, ~20 repositories (casts only) | Medium (touches every call) | analyze; targeted `api_client` and `call_problem` tests | No (same texts) |
| 3 | Parsing: `tryDecodeMap`, tolerant `outbox_entry.dart:60`, `session_store.dart:35,75`, `form_logic_runner.dart:40`, `sv_cell_format`, `sv_preview_parsers` | ~8 files in `data/models`, `data/` | Low | model tests with bad JSON, analyze | No |
| 4 | Storage / DB: guard `openDatabase`/migrate, "Reset local data" fallback, `sv_prefs`, `attachment_cache`, `form_file_repository` empty catches | `app_database.dart` + 4 | Medium (startup path) | migration test (existing `migrate`), analyze, build | **Yes**: new recovery screen on DB failure |
| 5 | Outbox / sync: log-and-continue in `message_repository.dart:115,147`; catch non-socket errors in submission flush; `conversation_repository.dart:307,310` | 3 repositories | Medium (message delivery) | existing outbox tests (run on request), analyze | No |
| 6 | Controllers: replace 28 empty catches and `catch (_)` in `connect_controller`, `new_chat_controller`, `conversation_controller`, add notices; `runGuarded` for the 181 `unawaited` in rolling sub-batches by feature | ~30 controllers | Medium, many files | analyze per sub-batch, targeted controller tests, build | **Yes**: new error notices where failures were silent (connect, new chat, sync) |
| 7 | Platform / permissions: channel results `denied`/`permanentlyDenied`; photo picker, link launcher, attachment cache, iOS backup channel | 5 files | Low | analyze, device check | **Yes**: "Open settings" prompts |
| 8 | Encryption: narrow `e2e_crypto.dart` catch-alls, `encryption_policy.dart:360,392`, `e2e_device_label.dart`; user guidance text for key problems | 4 files | **High** (key handling; never downgrade) | e2e vector tests (on request), analyze, build, owner review | **Yes**: new guidance messages |
| 9 | Notifications: `local_notification_service.dart:157,183,450`, remove temporary `notifyflow` logs | 3 files | Low | analyze, device check | No |
| 10 | Navigation / deep links: `deep_link_service.dart:143,341,349`, splash and profile `.then` | 3 files | Low | analyze, deep-link tests | **Yes**: notice for a bad link (today silent) |
| 11 | Lints on: add the four lints (section 6), keep `discarded_futures` off; CLAUDE.md rule from section 7 | `analysis_options.yaml`, `CLAUDE.md` | Low | `dart analyze` clean | No |

Each batch ends with `dart analyze` on changed files and `flutter build apk --debug` (build only). Tests run only when you ask.
