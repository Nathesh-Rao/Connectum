# The BE dev environment

Facts from the backend's dev doc (13 Nov 2026) and `reference/test-env/MOBILE_TEST_ENVIRONMENT.md`. Where a fact is not known it says so.

## Addresses

| What | Value |
|---|---|
| API through nginx | `http://10.0.2.113/api/sd` (or `:8080` direct) |
| WebSocket | `ws://10.0.2.113/ws` (or `ws://10.0.2.113:8080` direct) |
| Reach | private network or VPN only. **Plain http/ws, no TLS.** `dev.connectum.app` does not exist yet |
| Restarts | the dev backend restarts on every merge: a few seconds of 503, up to ~30 s warm-up |
| Email | dev can send **real** emails |
| Sign-in limit | 30 requests/min per address (nginx), then 429 |
| Sessions | one active session per client kind per person (a second sign-in ends the first) |
| Docs source | the `dev` branch of the web repo, `connectum/docs/` |

## Run the app against dev

`BASE_URL` has no `/api/sd`: the app appends it (`AppConfig.apiBase`). `WS_URL` is used exactly as given, so it includes `/ws`.

```
flutter run -d ZD222DPPP2 \
  --dart-define=BASE_URL=http://10.0.2.113 \
  --dart-define=WS_URL=ws://10.0.2.113/ws
```

Cleartext is allowed only in debug and profile builds, only to `10.0.2.113`, `10.0.2.2`, `localhost`, `127.0.0.1` (`android/app/src/{debug,profile}/res/xml/network_security_config.xml`). On iOS `NSAllowsLocalNetworking` already covers private addresses (it is on the before-release removal list). A release build refuses a non-https `BASE_URL` / non-wss `WS_URL` at startup (`AppConfig.validate`); `DEMO_MODE` and `SEED_UI` are off in release.

## Verify the environment

`GET /api/sd/version` returns `{ ok, data: { release, node, environment } }`. `environment` is `"dev"` on dev; `release` is the short commit id (a `vX.Y.Z` tag on production). There is no schema or migration version.

In debug and profile builds the app calls it once at startup (4 s timeout, failure ignored) and prints one `debugPrint` line (`server: <environment> <release>`). There is no UI for it: no banner, no label.

## HTTP behaviour

- GET calls and the sign-in start calls (`/login/start`, `/setup/start`, `/register/start`) retry a 503 or a dropped connection twice (0.5 s, 1.5 s). Other POSTs are never retried. After that the message reads "The server is restarting or busy. Wait a few seconds and try again."
- 429 is never retried: "Too many attempts. Wait a minute and try again." (`rate_limited`).

## Sign-in on dev

`CONNECTUM_DEV_OTP=1` is on: `POST /login/start` answers `{sent, devOtp}`, then `/login/verify` with that code, then `/enter`. A fixed OTP is not supported. Seeded emails are `<username>@test.co`; the exact accounts are not known until a seed run prints them.

## Not available yet

Push (the backend has none), event injection, a reset endpoint, seeded direct-chat messages, ticket/record forms with actions, approvals, attachments (file storage profile not verified), E2E test chats (server mode not verified), and the mock AI at a private address (needs `CONNECTUM_API_ALLOW_PRIVATE=1`, not verified).

## Rules for automated tests

`test/README.md`. Every integration test starts with `DevGuard.assertDevOnly(baseUrl)` (`test/support/dev_guard.dart`; set `DEV_HOST`): it fetches `/version` and throws unless `environment == "dev"` and the host equals `DEV_HOST`. Only `@test.co` (or own) emails, one prefix and one seed run per run, no load tests, distinct accounts for parallel tests, tolerate 503 and warm-up, tell Arjun when a batch can be wiped.

## Keeping the docs in sync

`tool/be_sync/sync_be_docs.sh [--dry-run]` (read-only on the web repo, details in `tool/be_sync/README.md`). With `DEV_BASE_URL=http://10.0.2.113` it also says whether the docs are ahead of or behind the deployed dev release.

## Open BE questions

1. Exact seeded addresses and whether a fixed OTP will exist (today: random `devOtp`).
2. When `dev.connectum.app` (DNS, TLS) will exist.
3. Dev values of `CHAT_RATE_LIMIT_MAX`, `CONNECTUM_E2E` and `CONNECTUM_API_ALLOW_PRIVATE`.
4. Whether the dev instance has a file storage profile (attachments).
5. `origin/dev` docs have moved tickets to `RECORD_ACTIONS.md` (`records.mine` replaces `status.mine`, `task.fetch` replaces `task.get`, `INBOX_TASKS_AND_TICKETS.md`): is this live on the deployed dev, and when must the app move? Our `reference/` copies and code still use the old names until the sync is applied and reviewed.
