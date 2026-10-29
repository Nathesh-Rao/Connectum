# Connectum sessions: sign-in, tokens, sign-out, repeat logins

Based on code; `docs/MULTI_ENTERPRISE.md` describes the same flow. Where docs differ from code, code is given. REST base: `https://<HOST>/api/sd`. All answers are `{"ok":true,"data":{...}}` or `{"ok":false,"error":{"code","message","details"}}`. Placeholders: `<ACCT_TOKEN>`, `<ENT_TOKEN>`, `<TRUST>`.

## 1. Two kinds of session

| | Account session (`kind:"id"`) | Enterprise session (`kind:"ent"`) |
|---|---|---|
| Made by | `login/verify`, `login/start` on a trusted device, `login/password`, `register/verify`, `setup/verify` | `POST enter`, `setup/verify` (returns one too) |
| Identifies | an email (one Connectum ID per email) | a username inside one enterprise |
| Used for | `me`, `enter`, `join`, `join/check`, `logout`, `account/password/*` | WebSocket handshake, every `/sd` action, `GET session`, `feed*`, uploads |
| Lifetime | 15 days, hard limit (not extended by use) | 15 days, hard limit |
| Sent as | `Authorization: Bearer <ACCT_TOKEN>` | `Authorization: Bearer <ENT_TOKEN>` and the WS handshake `token` |

Lifetime: **15 days, a hard limit** (confirmed by the backend developer; the older docs that say 14 are wrong). Each sign-in answer carries `expiresTs` (epoch ms): use it, never a fixed number. `enter` is the right call for the WebSocket token. HTTPS/WSS has no date yet.

## 2. Login with email code (OTP)

1. `POST login/start` `{"email":"a@b.com","trust":"<TRUST>"}` (`trust` only if the device holds one).
   - Unknown email, never invited: error `no_account`. Invalid email: `invalid`. Limits: `rate_limited`.
   - Otherwise a 6-digit code is emailed. Answer: `{"sent":true,"expiresInSec":300}`. If a code was sent less than 30 s ago: `{"sent":false,"retryAfter":<seconds>}` (show a countdown; web UI uses 30 s).
   - On a remembered device (valid `trust`) no code is sent: the answer is already the signed-in object plus `"trusted":true`.
2. `POST login/verify` `{"email":"a@b.com","otp":"123456","deviceId":"<uuid>"}` returns:
```json
{"token":"<ACCT_TOKEN>","expiresTs":1791500000000,"identity":{"connectumId":"XXXX-XXXX","email":"a@b.com","username":"alice"},
 "enterprises":[{"enterprise":"4C4D-3FAH","name":"Acme","city":"Pune","username":"alice","category":"employee","status":"active","landing":false}],
 "trust":"<TRUST>"}
```
   - Code rules: valid 300 s, max 5 wrong tries then `otp_locked` (request a new code), wrong code `otp_invalid`, expired `otp_invalid`. One code per 30 s per address.
   - `enterprises[].status`: `active`, `pending` (waiting for approval, cannot enter), `rejected`, deactivated.
3. `trust` = remembered-device token, valid 15 days (env `CONNECTUM_TRUST_DAYS`). Web stores it per email and keeps it after sign-out. If a later `login/start` with it fails, the web client discards it.
4. `deviceId`: a client-generated stable UUID, created once and persisted; sent on `login/verify`, `register/verify`, `setup/verify`, `login/password`, `enter`. The backend stores it on the session; nothing else in the backend reads it (it is only stored as `deviceKey`).
5. Optional password sign-in: `POST login/password` `{"email","password","deviceId"}` returns the same object as `login/verify` (only for accounts that set a password via `account/password/start|set|remove`, each confirmed by an emailed code). Wrong credentials: `invalid_credentials`; 8 failures in 15 min locks the password (the code still works). `docs/MULTI_ENTERPRISE.md` says "no passwords"; the code and web UI have this optional path.
6. Register / set up (also code-confirmed): `register/start` `{username,email,mobile?,city?,state?,country?}` then `register/verify` `{email,otp,deviceId}` (error `exists` if the email has an account, `no_pending` if the pending sign-up expired after 900 s); `setup/start` `{org,name,email,mobile,...}` then `setup/verify` returns an account token plus an enterprise `session`.

**Entering an enterprise (this is where "the organisation is chosen"):**
`POST enter` with `Authorization: Bearer <ACCT_TOKEN>`, body `{"enterprise":"4C4D-3FAH","deviceId":"<uuid>"}` returns `{"token":"<ENT_TOKEN>","expiresTs":..,"user":{...},"enterprise":"4C4D-3FAH","landing":<optional>}`. Errors: `pending_approval`, `rejected`, `account_inactive`, `not_member`, `unauthenticated` (account session gone: send the user back to email sign-in). Then open the WebSocket with `<ENT_TOKEN>` (see `websocket-protocol.md`).

## 3. Token storage (web client; mirror with secure storage on mobile)

| Web key (localStorage) | Holds | Cleared when |
|---|---|---|
| `connectum_identity` | `{token:<ACCT_TOKEN>, expiresTs, identity, enterprises}` | account sign-out; `me` returns not ok at app start; `enter` returns `unauthenticated` |
| `connectum_session_user` | the enterprise user object including `token` (`<ENT_TOKEN>`), `expiresTs`, `enterprise`, `username`, profile fields | enterprise sign-out/switch; forced sign-out (only if it still holds the ended token) |
| `connectum.trust` | `{ "<email>": "<TRUST>" }` | only when a trusted `login/start` fails; **kept on sign-out** |
| `connectum_device_id` | the UUID | never (a "rotate" helper exists for testing) |

On start the web client reads `connectum_session_user` and resumes without any call. If `connectum_identity` exists it calls `GET me` (Bearer account token) to refresh the enterprise list and goes to the list screen.

## 4. Refresh and validity checks

- **There is no refresh endpoint and no token renewal.** A session is a hard 15 days; after that the user repeats section 2 (a remembered device skips the code).
- While signed in, the web client calls `GET session` (Bearer enterprise token) immediately and every **60 s**, and also when a `permissions_changed` push arrives. `401` or error code `unauthenticated` leads to forced sign-out. Answer: `{user, password, sessionExpiresTs, totpDue, enterprise, mode, ...}`.
- Over the socket: expiry is detected when the server receives a client line (checked at most every 30 s), then `sd_event session_expired` and close. `/sd` calls after expiry return `error.code:"session_expired"`.
- Other 401 sources: token revoked by a repeat login (section 6), `POST logout`, user deactivated (`account_inactive` / `disconnected` event).
- `GET me` answer: `{identity, enterprises, sessionExpiresTs}`.

## 5. Logout

Three web actions:

| Action | Calls | Local effect |
|---|---|---|
| Switch enterprise (`leaveEnterprise("Choose an enterprise")`) | `POST logout` with `<ENT_TOKEN>` | socket `/quit` + close, message cache (IndexedDB) cleared, `connectum_session_user` removed, UI state reset; account session and `connectum_identity` stay, so the enterprise list shows |
| Sign out fully (`handleSignOutAll`) | `POST logout` with `<ACCT_TOKEN>`, then the same as above | also removes `connectum_identity`; shows the email sign-in tab; `connectum.trust` stays |
| Sign out of account on the list screen | `POST logout` with `<ACCT_TOKEN>` | removes `connectum_identity` |

`POST logout` `{}` answers `{"loggedOut":true}` and works for either token kind; it deletes the session record. It does **not** forget the remembered device. It does not revoke the other kind of session (signing out of the enterprise leaves the account session valid, and the reverse).

## 6. Same user logs in again

### Same organisation (second tab, second phone, or re-entering after sign-out)
Server rule (`sd_auth:revoke_previous_session`): **one active enterprise session per username per enterprise.** `POST enter` for that enterprise deletes the previous enterprise token and pushes a notice:

1. The old token stops working at once (REST `401 unauthenticated`; `/sd` calls fail).
2. If the old device still has an open socket, it receives, then the server closes it:
```json
{"type":"sd_event","event":"session_replaced","reason":"signed_in_elsewhere"}
```
3. A security item `session_replaced` is added to that person's notification feed (via `sd_feed:security`). UNCLEAR: exact text and category shown for it; only the kind name was found.
4. If the old device is offline, it learns on its next request (REST 401, failed socket handshake, or the 60 s `GET session` poll).

UI on the old device (`ConnectumChatScreen.jsx`, `forceSignOut`): disconnect socket (no reconnect), clear message cache, remove `connectum_session_user` if it still holds the ended token (another tab may already have stored a new one), reset all per-user state, set the sign-in notice **"You were signed out because this account signed in on another tab or device."**, render the auth screen. Because `connectum_identity` is still valid, the auth screen shows the enterprise list with that notice as the error line.

Related but different: a connection with a **valid session** (reload, second window, the same app reconnecting) takes the old socket over at once: the older gets `sd_event connection_superseded` (`reason:"opened_elsewhere"`) and is closed. A new **sign-in** on another device sends the old socket `session_replaced` instead. `Username taken` only appears when there is no Connectum session. Mobile: `connection_superseded` and `session_expired` sign this device out (token cleared, cached rows and outbox kept) with a notice; `session_replaced` wipes this organisation's rows and outbox; any handshake error is an auth failure (token cleared, rows kept).

### Different organisation
Sessions, usernames, sockets and chat rooms are per enterprise (Redis keys prefixed `e:<id>:`, `chat_room@<id>`). `POST enter` for enterprise B creates a new, independent enterprise session. Enterprise A's session and socket are untouched: no `session_replaced` is sent, and the account session is unchanged. The web client can hold only one enterprise at a time per browser profile: it must first "switch" (section 5), which calls `logout` for A. If another tab/device enters B while tab 1 stays in A, tab 1 keeps working with its A token (UNCLEAR: whether the Flutter app should allow two enterprises at once; the backend allows it). In the browser, `connectum_session_user` is a single slot, so tab 2 overwrites it, and a reload of tab 1 would resume B.

### Forced sign-out summary (web UI)

| Trigger | Message shown |
|---|---|
| `session_replaced` | You were signed out because this account signed in on another tab or device. |
| `session_expired` | Your session has ended. Please sign in again. |
| `disconnected` + `account_deactivated` | This account has been deactivated. Please contact your administrator. |
| `GET session` 401 | You were signed out because this session ended. Please sign in again. |

## 7. Source files used
`src/services/connectumApi.js`, `src/services/connectumSocket.js`, `src/services/sessionToken.js`, `src/features/connectumChat/components/ConnectumAuthScreen.jsx` (lines 22 to 235), `src/features/connectumChat/ConnectumChatScreen.jsx` (handleLoginSuccess ~3595, leaveEnterprise ~3685, forceSignOut ~3713, session poll ~3727, event handlers ~1988), `axi-chat-backend/src/sd_ident.erl`, `sd_auth.erl`, `sd_http.erl`, `sd_policy.erl`, `sd_notify.erl`, `chat_room.erl`, `chat_web.erl`, `docs/MULTI_ENTERPRISE.md`, `docs/CONNECTUM_API.md`, `docs/CHAT_PROTOCOL.md`.
