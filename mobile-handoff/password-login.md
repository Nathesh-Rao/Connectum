# Password sign-in

Read from the web repo (read-only): `connectum-backend/src/security/sd_ident.erl` (`login_password`, `password_start|set|remove`), `src/http/sd_http.erl`, `test/connectum_password_signin_test.mjs`, `chat-app/features/connectumChat/components/ConnectumAuthScreen.jsx`, `chat-app/services/connectumApi.js`.

## Sign in

`POST /api/sd/login/password` (no auth) `{email, password, deviceId}`. Plain password over TLS (the server hashes with salted PBKDF2-SHA256; nothing is derived on the client). `client:"mobile"` stays off.

Answer: the same object as `login/verify` (`token`, `expiresTs`, `identity`, `enterprises`, `trust`). `identity.hasPassword` tells whether the account has a password. No 2FA or password-change step follows (`totpDue` / `mustChangePassword` are not part of this path), so the app reuses `AuthRepository._finishLogin`: the trust token is saved, the identity stored, and the enterprise list opens, exactly as after the code.

The password is 1 to 128 bytes. The email is not case sensitive; the password is.

## Errors

| Code | HTTP | When | Shown |
|---|---|---|---|
| `invalid_credentials` | 401 | wrong password, unknown email, account with no password, empty password, malformed email: all the same answer | "That email and password do not match. You can sign in with an emailed code instead." plus a "Use email code instead" link |
| `rate_limited` | 429 | 8 wrong tries per email in 15 minutes (the correct password is refused too), or the per-IP limit | "Too many wrong passwords. Use an emailed code, or try again in a few minutes." plus the link |
| `network` / `bad_response` | – | no connection | "Can't reach the server..."; the form (email and password) is kept |

A refusal clears the password field and keeps the email. The answer carries no retry time (no `retryAfter`, no `Retry-After` header was found); the app shows a countdown only if `ApiException.retryAfterSeconds` is present, which today it is not. The email code is never locked by the password lock.

Not applicable to this endpoint: password expired, disabled account, locked account (separate code), 2FA after the password. `account_inactive` and `pending_approval` surface later at `enter`/enterprise list, as after a code sign-in.

## Which screen

The web sign-in tab has one form with a link, "Use my password instead" / "Email me a code instead". The default is the code. Mobile: a two-pill switch (Password | Email code) on the Sign in tab, default Email code. There is no "forgot password" flow in the web: the emailed code is the way back in, so the app shows only the hint "Forgot it? Sign in with an emailed code."

## Set, change, remove (web: the enterprise list, "Set a password" / "Change password")

All with the account (identity) token as Bearer:

1. `POST /api/sd/account/password/start` `{}` -> `{sent, expiresInSec, devOtp?}`, or `{sent:false, retryAfter}` within the 30 s cooldown. The code goes to the account's own email.
2. `POST /api/sd/account/password/set` `{otp, newPassword}` -> `{hasPassword:true}`. 8 to 128 characters (counted as characters), no other rule. Wrong code: `401 otp_invalid`; a code works once.
3. `POST /api/sd/account/password/remove` `{otp}` -> `{hasPassword:false}`.

No current password and no confirm field are asked (the emailed code is the proof). Setting or removing does not end other sessions (the server only starts a new identity session at sign-in and replaces enterprise sessions at `enter`) and does not touch end-to-end encryption: E2E keys and devices are separate (`mobile-handoff/e2e.md`), registered per device, with no link to the password. Mobile: Profile -> Password opens a sheet (`lib/features/password/`) with those steps; the account token can be missing or expired (then "Your session has ended. Please sign in again.").

`/me` returns `identity.hasPassword`; the app stores it in `IdentityInfo.hasPassword` (updated by `refreshMe`, sign-in and the set/remove calls).

## Demo and debug

`DEMO_MODE`: `DemoAuthRepository.loginWithPassword` accepts `demo1234` for any email; anything else gives `invalid_credentials`. The Password sheet works there too (any code).
`/debug/auth` (debug builds): the real sign-in screen on a scripted repository; pick Wrong password, Locked, Locked with 20 s, or Network error.

## Open questions for the backend

1. Do the dev seed users have passwords? Nothing in `deploy/demo` or the tests seeds one; a password is only set through the emailed-code flow, so a seed user has none until it sets one (`CONNECTUM_DEV_OTP=1` returns the code).
2. Could the 429 for a locked password carry `retryAfter` (the lock is a fixed 15 minute window per email)? The countdown is built but has nothing to show.
3. `docs/LOGIN_INTEGRATION.md` still describes the older username/admin password and `mustChangePassword`; confirm it does not apply to `login/password`.
