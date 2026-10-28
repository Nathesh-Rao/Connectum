# Postman collection vs mobile-handoff cross-check

Compared `postman/api_collection_connectum.json` with `websocket-protocol.md`, `sessions.md`, `messages-and-receipts.md`, `forms.md`, `ai-and-misc.md` (plus `screens-and-features.md` and `deep-links.md` where an endpoint is only named there). Nothing here picks a winner; conflicts go to the project owner. All example values are replaced by placeholders (`<email>`, `<enterpriseId>`, `<token>`...). "Session" = enterprise session token (`sessions.md` `<ENT_TOKEN>`); "identity" = account token (`<ACCT_TOKEN>`).

The collection has 25 REST requests. Its WebSocket and `/sd` sections (folders 5 and 6) are reference cards: each is a dummy `GET /api/sd/session`, so they are not endpoints.

## 1. REST endpoints in the collection

Base `<BASE_URL>/api/sd`. Answers are `{"ok":true,"data":{...}}` or `{"ok":false,"error":{"code","message"}}`.

| # | Method, path | Auth | Request body | Example response (trimmed) | Handoff doc |
|---|---|---|---|---|---|
| 1 | GET `/public` | none | | `data{mode, platform}` | none |
| 2 | POST `/login/start` | none | `{email, trust?}` | `data{sent, expiresInSec}`; with valid trust: `data{token, expiresTs, identity, enterprises[], trusted:true}`; 404 `no_account` | sessions.md §2 |
| 3 | POST `/login/verify` | none | `{email, otp, deviceId}` | `data{token, expiresTs, identity{connectumId, email, username, name, mobile, city, state, country, hasPassword}, enterprises[{enterprise, name, city, category, username, status, landing}], trust}`; 401 `otp_invalid` | sessions.md §2 |
| 4 | GET `/me` | Bearer identity | | `data{identity, enterprises[], sessionExpiresTs}` | sessions.md §4 |
| 5 | POST `/enter` | Bearer identity | `{enterprise, deviceId}` | `data{enterprise, token, expiresTs, mustChangePassword, totpDue, user{username, name, email, role, roles[], department, employeeCode, status, isHost, canManageUsers, ...}}` | sessions.md §2 |
| 6 | GET `/session` | Bearer session | | `data{enterprise, mode, user, password{expired, hasPassword, mustChange}, sessionExpiresTs, totpDue}`; 401 `unauthenticated` | sessions.md §4 |
| 7 | POST `/logout` | Bearer session | `{}` | `data{loggedOut:true}` | sessions.md §5 |
| 8 | POST `/register/start` | none | `{username, email, mobile, city, country}` | `data{sent, expiresInSec}` | sessions.md §2.6 |
| 9 | POST `/register/verify` | none | `{email, otp, deviceId}` | `data{token, expiresTs, identity, enterprises:[]}` | sessions.md §2.6 |
| 10 | GET `/enterprises?q=` | none | | `data{enterprises[{enterprise, name, city}]}` | screens-and-features.md (name only) |
| 11 | GET `/enterprise/<enterpriseId>` | none | | `data{enterprise, name, org, branches[], categories[], departments[], designations[], designationRules[], affiliates[], employeeSignup{mode, codeRequired}, onboarding{<category>{requireApproval, requiredFields, branchBound, optionsBefore, welcome}}, location, setupDone}` | screens-and-features.md (name only) |
| 12 | POST `/join/check` | Bearer identity | `{enterprise, isEmployee, category}` | `data{ok, fields{}}` | screens-and-features.md (name only) |
| 13 | POST `/join` | Bearer identity | same as 12 | no example; text says `{joined, status, username, nextStep}` | screens-and-features.md (name only) |
| 14 | GET `/geo/countries` | none | | `data{countries[]}` | screens-and-features.md (name only) |
| 15 | GET `/geo/cities?country=` | none | | no example | screens-and-features.md (name only) |
| 16 | GET `/feed/summary` | Bearer session | | `data{unread, total, resolved, high, medium, low}` | ai-and-misc.md §4 |
| 17 | GET `/feed?priority=&unreadOnly=&limit=` | Bearer session | | `data{counts, hasMore, notifications[{id (string), category, icon, title, message, priority, severity, read, resolved, resolvedTs, ref{cardId}, count, ts}]}` | ai-and-misc.md §4 |
| 18 | POST `/feed/read` | Bearer session | `{all:true}` (or `{ids}`) | `data{counts, updated}` | ai-and-misc.md §4 |
| 19 | POST `/feed/resolve` | Bearer session | `{id}` | no example | ai-and-misc.md §4 |
| 20 | POST `/feed/dismiss` | Bearer session | `{id}` | no example | ai-and-misc.md §4 |
| 21 | POST `/feed/clear` | Bearer session | `{}` | no example | ai-and-misc.md §4 |
| 22 | POST `/files?name=<file>` | Bearer session | raw bytes, real `Content-Type`; max 10 MB | `data{file{id, name, mime, size, by, ts}}` | ai-and-misc.md §2.2 |
| 23 | GET `/files` | Bearer session | | `data{files[{id, name, mime, size, by, ts}]}` | ai-and-misc.md §2.2 |
| 24 | GET `/files/<fileId>` | Bearer session | | raw bytes, no example | ai-and-misc.md §2.2 |
| 25 | GET `/option-file/<optionId>` | Bearer session | | raw bytes, no example | ai-and-misc.md §2.2 |

## 2. Coverage gaps

**In the collection, missing from the docs**
- `GET /public` (#1): no handoff doc mentions it.
- Detail for #10 to #15: the docs only list the endpoint names in `screens-and-features.md`; no request or response shapes. Shapes for #11 (public page) and #12 are only in the collection.
- Fields not in the docs: `mustChangePassword` and `totpDue` on `enter` and `session`; the nine-field `identity`; the `onboarding` block of #11; error codes `invalid_values`, `admin_locked`, `forbidden`.
- Setup facts only in the collection: server is a private IP reachable by VPN or office network only, http/ws today, self-signed https, needs iOS ATS and Android cleartext exceptions; 30 s HTTP timeout advice; test accounts must be invited by an admin first.

**In the docs, missing from the collection**
- `POST /login/password`, `POST /account/password/start|set|remove`, `POST /setup/start`, `POST /setup/verify`, `2fa/*` (sessions.md, screens-and-features.md).
- `POST /upload` and `GET /uploads/<name>`: the chat attachment mechanism (ai-and-misc.md §2.1, messages-and-receipts.md §2). The collection covers only `/files`.
- `login/start` throttle answer `{"sent":false,"retryAfter":N}`, error codes `otp_locked`, `invalid_credentials`, `exists`, `no_pending` (sessions.md).
- WebSocket events the collection never mentions: `session_replaced`, `connection_superseded`, `disconnected`, `error` `code` list beyond four values, `host_message`/`/hostmsg`, `/read` receipts, `/edit`, delta history (`/history ... delta`), `e2e_*` events.
- Left out by the collection on purpose: admin console, Axpert, consumer program, queue, Shopify.

## 3. Conflicts (not resolved)

| # | Topic | Handoff docs | Collection |
|---|---|---|---|
| C1 | Where the WebSocket token comes from | websocket-protocol.md §1: the token from `POST /api/sd/enter`. messages-and-receipts.md §1: "session token from `POST /api/sd/login`". The handshake error text also names `/api/sd/login`. | Session token from `enter` (folder 2 step 4, WS card "How to connect"). |
| C2 | Session lifetime | sessions.md: 15 days (code); says `CHAT_PROTOCOL.md` and `CONNECTUM_API.md` say 14. messages-and-receipts.md §1: "14 days". | "about 15 days", not extended by activity. |
| C3 | Server address and scheme | websocket-protocol.md and sessions.md: `https://<HOST>/api/sd`, `wss://<HOST>/ws`. deep-links.md: `APP_URL` default `https://<private-IP>`, production `https://connectum.app`. | `http://<private-IP>` and `ws://<private-IP>/ws`; server is not on the internet; https is self-signed; a production address comes later. |
| C4 | `enter` response | sessions.md: `{token, expiresTs, user, enterprise, landing?}` | Adds `mustChangePassword` and `totpDue`; example has no `landing`. |
| C5 | `identity` object | sessions.md `login/verify` example: `{connectumId, email, username}` | Also `name, mobile, city, state, country, hasPassword`. |
| C6 | Feed item id type | ai-and-misc.md: `/resolve {id}`, `/dismiss {id}` (type not stated) | Collection is inconsistent with itself: the list returns `id` as a string, but the resolve and dismiss example bodies send the number `1`. |
| C7 | Error for an unknown command | messages-and-receipts.md: `error` events carry a `code` for `not_associated` / `not_allowed` | The card text lists `unknown_command` among the codes, but its sample `/nope` reply has only `type` and `text`. |

## 4. UNCLEAR items the examples answer

The "earlier summary" is taken to be the UNCLEAR markers in the handoff docs. Few are answered.

| UNCLEAR (doc) | What the collection shows |
|---|---|
| Submission `status` / `approval` shape (forms.md) | Partial. For a form that needs no approval, `tstruct.submit` returns `recordStatus: "saved"` and a `submission` with only `{id, tstruct, values, by, ts, branch, host, scope}`; `submissions.list` and `submission.get` items have the same keys and no `status` or `approval`; `submissions.update` adds `editedTs`. Evidence: the `tstruct.submit`, `submissions.list` and `submissions.update` samples. The `pending` / `stages` shape is not shown. |
| History page size, no older pages (messages-and-receipts.md) | Confirms the cap. The `/history dm` card says "up to the last 50 messages, oldest first" and the sample uses only `scope`, `with`, `now`, `list`. No `before` argument exists for `/history`. Whether the backend will add one is still open. (`feed.list` does take `before`.) |
| Session lifetime 14 vs 15 days (sessions.md) | The collection says about 15 days, matching sessions.md, but it is a conflict (C2), not an UNCLEAR, so it is left for the owner. |
| 2FA (screens-and-features.md) | Minimal: `totpDue: false` appears in the `enter` and `session` samples. No `2fa/*` endpoint is in the collection. |

## 5. UNCLEAR items that remain

- **websocket-protocol.md:** what the client should do on a handshake `error`; `conversation_changed` has no web handler; full list of `edit_denied` reasons; whether `/pubkey` and `/getpubkey` are still used.
- **messages-and-receipts.md:** the `[ATTACHMENT:...]` JSON schema; whether mobile stays limited to 50 messages or gets a `before` parameter.
- **forms.md:** how to model a Yes/No field (the collection's only `tstruct.get` example is a `list` field with `options`, nothing yes/no); whether grid-section rows appear on the chat card; the `pending` approval shape.
- **sessions.md:** exact text and category of the `session_replaced` feed item; whether the Flutter app may hold two organisations at once.
- **ai-and-misc.md:** whether `#<alias>` calls the relay server-side; local thumbnails; native crypto interop with the web E2E envelope; size limits (`CHAT_PROTOCOL.md` vs `chat_web.erl`, code used); unauthenticated `GET /uploads/<name>`; push notifications (no device-token endpoint exists in either source); who owns the AI tool loop.
- **deep-links.md:** preview-environment paths; whether `web/` `/embed/...` links are needed; production values of `CONNECTUM_PUBLIC_URL` and `APP_URL`; what `/connect/<CODE>` should open.
- **screens-and-features.md:** which UI calls 2FA; E2E badge scope; notifications modal key; inbox contents; meeting-notes endpoints; visibility of the Allowance, Applications and Affiliates tabs.
- **New, from this check:** the conflicts C1 to C7 above need an owner decision.
