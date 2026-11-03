# Deep links and routing of the Connectum web app

## Summary
The web app has NO URL router. `App.jsx` renders one screen; navigation is in-memory state (modals, tabs). No code reads `location.pathname`, `location.hash` or `location.search`, and none calls `history.pushState` / `replaceState` / `hashchange` / `popstate` (searched all of `src/`). Every path therefore opens the same app. The embedded structure studio uses `MemoryRouter` explicitly so the browser URL never changes.

## 1. Server rewrites (nginx reference `nginx/axi-chat.conf.reference`)
| Request | Behaviour |
|---|---|
| `/` and `/index.html` | static `index.html`, `Cache-Control: no-cache` |
| `/assets/*`, `/vendor/*` | static, cached 1 year |
| `/ws` | WebSocket proxy to backend :8080 |
| `/upload`, `/uploads/*` | upload (POST) and file serving (GET), proxied |
| `/api/sd/login`, `register`, `setup/start`, `setup/verify`, `password/change` | proxied, rate limited (429) |
| `/api/sd/consumer/*` | 404 (internal only) |
| `/api/sd/*` | proxied REST (see `connectumApi.js`) |
| everything else (e.g. `/connect/ABCD1234`, `/anything`) | `try_files $uri $uri/ /index.html` (SPA fallback) |
Preview environments are included from `/etc/nginx/conf.d/previews/*.conf` (not in the repo; UNCLEAR: their paths).

## 2. Links that exist
| URL | Where produced | Parameters | Parsed by web app? | Likely opened externally? |
|---|---|---|---|---|
| `<APP_URL>` (root) | Every email button: invite ("Open Connectum"), registered ("Open Connectum"), otp mail (no button; code shown in body), onboarding ("Sign in to Connectum"), generic ("Open Connectum") in `sd_mail.erl` | none (no token, no OTP link) | n/a, just opens the app | Yes (emails). Default if `APP_URL` unset: `https://10.0.2.146`; DNS doc says production `https://connectum.app` |
| `<CONNECTUM_PUBLIC_URL>/connect/<CODE>` | Enterprise and personal QR/share links (`sd_connect.erl` `payload/1`; web `qrText()` in `ConnectCodeModal.jsx` builds `window.location.origin/connect/<CODE>` when the payload is `connectum:<CODE>`) | `CODE` = 8 chars, hyphens/spaces removed, upper case (display form `ABCD-1234`) | NO. The web page ignores the path; only the backend parses a scanned/typed text (`connect.scan {code}` and public lookup) | Yes: scanned from a phone camera or shared by message. This is the key one for mobile |
| `<...>/connect/<CODE>?branch=<Name>` | Per-branch enterprise QR (`branch_codes/0`) | `branch` = url-encoded branch name; notes where the person scanned | NO (backend only, via `connect.scan`) | Yes (printed branch QR) |
| `connectum:<CODE>` and `connectum:<CODE>?branch=<Name>` | Same QR payload when no public URL is configured | same | Not a URL scheme anyone handles; the in-app scanner/typed field passes the text to `connect.scan` | Only inside the app scanner. Phone cameras say "no usable data" (comment in `ConnectCodeModal.jsx`) |
| Saved server address | `savedServers.js`: accepts `host`, `https://host/` or `https://host/api/sd`; stores API base `https://host/api/sd` and WS `wss://host/ws`; "the enterprise QR carries the address" | none | Typed/pasted into Saved servers panel, then app reloads | Possibly from enterprise QR link host |
| Links feature (outgoing) | `docs/LINKS.md`: admin-defined addresses with `:username`, `:name`, `:email`, `:mobile`, `:department`, `:designation`, `:designations`, `:branch`, `:category`, `:code`, `:date`, `:time`, `:now` placeholders; server fills via `link.open` | placeholders | Opened by the app outward (window or frame); not inbound | No (outbound) |
| Apps (published pages) | `AppsModal` `initialId` ("straight from a link") | `id` of page | Set by option `type:"page"`, in-app only; no URL | No |
| Legacy `axi-connect.html`, `axi-upload.html`, `axi-ask.html` | `services/chatFlow.js` on typed text `AXI CONNECT/UPLOAD/ASK` | none | `window.location.href` redirect to files not shipped (not in `public/`) | No (dead) |

## 3. What does NOT exist (do not build as deep links without backend change)
| Item | Finding |
|---|---|
| Password reset link | None: sign-in is by emailed 6-digit code; own password set/removed in-app by code (`account/password/*`) |
| OTP magic link | None: code is shown in the email body and typed by the user (see `render(otp...)` in `sd_mail.erl`) |
| Invite link with token | None: invite email only links the app root; the invitee signs in/registers with the same email (and employee code) |
| Shared chat / message / form / approval / notification links | None found (no URL for a chat, message, record, request) |
| Push notification payload routing | No service worker or push code in `src/` (searched `serviceWorker`, `PushManager`, `requestPermission`) |
| Group invite | In-app event only: WS `group_invite`, `group_invite_pending`, `added_to_group` |

## 4. `web/` (forms studio, separate app)
`web/src/main.jsx` uses `BrowserRouter` with routes `/embed/:structRef/:view`, `/structs`, `/structs/new`, `/structs/:id/edit`, `/structs/:id/records`, `/structs/:id/form`, `/structs/:id/record/:recordId`, `*`. The chat nginx file has no location for it and falls back to the chat `index.html`, so it is NOT reachable on the chat host. UNCLEAR: is `web/` deployed on another host (check `deploy/`), and does the mobile app need `/embed/...` links?

## 5. Recommendations for Flutter (derived, not in code)
Register `https://<host>/connect/<CODE>` (+ optional `?branch=`) as an app link / universal link and pass `<CODE>` and `branch` to `connect.scan` (public lookup works without sign-in for enterprise codes); also accept a typed or camera-scanned `connectum:<CODE>`. Email buttons go to the root only, so they need no routing beyond opening the app.

UNCLEAR: Does the backend in production set `CONNECTUM_PUBLIC_URL` and `APP_URL` (both are env, not in repo; docs say `https://connectum.app` in `docs/DNS_CUTOVER.md`)?
UNCLEAR: Should `/connect/<CODE>` open the web app's connect screen? The web app currently ignores that path, so a link opened in a browser just shows the sign-in page.

## Source files used
`src/main.jsx`, `src/app/App.jsx`, `index.html`, `vite.config.js`, `nginx/axi-chat.conf.reference`, `src/features/connectumChat/components/modals/ConnectCodeModal.jsx`, `utils/savedServers.js`, `src/services/chatFlow.js`, `src/services/connectumApi.js`, `axi-chat-backend/src/sd_mail.erl`, `sd_connect.erl`, `web/src/main.jsx`, `docs/LINKS.md`, `docs/DNS_CUTOVER.md`, `docs/EMAIL_SETUP.md`, `docs/CONNECTUM_HANDOFF.md`.
