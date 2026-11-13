# Test rules (integration tests against the BE dev machine)

Details: `mobile-handoff/dev-environment.md`.

- First line of every integration test: `await DevGuard.assertDevOnly(baseUrl)` (`test/support/dev_guard.dart`). It needs `DEV_HOST` (the allowed dev host, e.g. `10.0.2.113`) and refuses anything whose `/api/sd/version` is not `environment: dev`.
- Dev can send REAL emails: use only `@test.co` addresses (or your own).
- One unique name prefix per run (the seed tool's `--prefix`); every name starts with it.
- One seed run per run, not per test (set-ups from one address get slowed).
- No load tests. At most a few dozen simulated people.
- One active session per client kind per person: use a distinct account for every parallel test.
- Expect restarts: the dev backend restarts on every merge (a few seconds of 503, up to ~30 s warm-up). Retry 503 and connection resets a couple of times before failing.
- Sign-in is limited to 30 requests a minute per address.
- Tell Arjun when a batch can be wiped. Never delete anything without your prefix. Never point a test at `connectum.app`.
