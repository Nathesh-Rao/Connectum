# Opening Connectum from a QR code (mobile)

What a scanned QR code carries, what it opens, and what the mobile app calls. Code: `connectum-backend/src/http/sd_connectpage.erl` (the page and the two files), `sd_applinks.erl` (the settings),
`sd_connect.erl` (the codes), `sd_pagecache.erl` (the in-memory copy). Admin console > Mobile app edits the settings. Postman: `docs/postman/Connectum_Mobile_QR.postman_collection.json` (every call below, with real example answers). Tests: `test/connectum_connect_landing_test.mjs`.

> **Everything else the mobile app needs** (encryption, history on a new device, message options, forms, Postman, tools): see [MOBILE_HANDOVER.md](MOBILE_HANDOVER.md).

## 1. What the QR carries

A plain https link (read the code after `/connect/`; do not hard-code the host):

| QR | Text | Example |
|---|---|---|
| Organisation | `{PUBLIC_URL}/connect/{ENTERPRISE_CODE}` | `https://connect.example.com/connect/7454YKKJ` |
| Organisation, one branch | the same, then `?branch={name}` (URL-encoded) | `…/connect/7454YKKJ?branch=Chennai%20Main` |
| Person | `{PUBLIC_URL}/connect/{PERSON_CODE}?org={ENTERPRISE_CODE}` (then `&branch={name}` if any) | `…/connect/KVZDHDQD?org=7454YKKJ` |

Codes are 8 characters of Crockford base32 (`0-9 A-Z` without I, L, O, U), shown `XXXX-XXXX`; the dash is not part of the code. Typing is forgiving (any case, spaces and dashes ignored, O is 0, I and L are 1).
A person's code only means something **inside its own organisation**, so a person's link names the organisation (`org` = the organisation's public code, the same one its own QR carries). A fresh install can therefore show
"Join *{organisation}*" first and connect to the person only once the user is in. An organisation's own link needs no `org` (one in it is ignored). A branch is only a label for where the person scanned. A person's code can be rotated: only the current one works. `PUBLIC_URL` is `CONNECTUM_PUBLIC_URL`; without it the QR carries `connectum:{CODE}`.
A phone only opens an app from a **real https domain** (not an IP number, not http): set `CONNECTUM_PUBLIC_URL` to it before the app links can work.

## 2. What the link opens

* **App installed, app links set up (below):** the phone opens the app straight from the camera with the whole link. The page is never shown.
* **Otherwise:** `GET /connect/{CODE}` shows a small page: "Join *Organisation*" (its name, and the branch when it has that branch), the code with a Copy button, **Open in Connectum**, the store button for the phone
  (Google Play on Android, App Store on iPhone, both on a computer), and **Continue in your browser** (`/?connect={CODE}`: the web app opens the Connect window on it and asks before connecting).
* A personal code and a code nobody has give the **same** page (only "Connect on Connectum"): nothing about a person is ever shown to someone who is not signed in, so codes cannot be harvested.
  With `?org=` (a person's link) the page shows **that organisation** ("Join *Name*", its branch when it has it) for any code, real or made up, so it still says nothing about a person.
  An `org` that is not a code, or names no organisation, is ignored: the plain page. A link that is not a code gives a plain 404 page.
* **The picture at the top of the card is a QR code of the page's own link** (near-black ink on a white tile with a quiet zone of three modules, inside four scan corners in the pack's `primaryBright`, above "Join {organisation}"), so a phone can be pointed at a computer's screen; it is on every device. The page is light only, as the whole product is (the mobile team's design pack has no dark theme): white page, the pack's ambient backdrop (a blue glow disc with orbit rings, a violet ring), a white card with a hairline edge, and the filled button wears the pack's bubble surface (its seven round discs are generated into `sd_theme.hrl` from `theme/tokens.json`, so there is one table for the product). Every colour is a token of that file (`scripts/gen-theme.mjs`); never write a hex into `sd_connectpage.erl`. Fonts: Plus Jakarta Sans and JetBrains Mono ExtraBold are our own files in `public/fonts/` (OFL, `font-src 'self'`; the page falls back to the system font while they load), the join button carries the "group add" icon, and the page falls back to the system font while they load. The QR still decodes (checked with the system's QR detector). It is the same link the printed QR codes carry (section 1): `{PUBLIC_URL}/connect/{CODE}` for an organisation, `{PUBLIC_URL}/connect/{CODE}?org={ORG}` for a person (then `&branch=` or, on an organisation's own link, `?branch=`). It is made by the server (`src/http/sd_qr.erl`, an inline SVG with nothing from outside, dark navy on white so every scanner reads it) and checked against an independent generator. The Connectum logo is shown instead on pages that have no code: a code nobody has, a person's code with no organisation, a link that is not a code, an installation with no `CONNECTUM_PUBLIC_URL`, or a link too long for a code (over 213 bytes, a very long branch name). On a computer the first store button ("Join the test (first time)" while the app is in testing) is the filled one and Google Play carries its mark; on a phone "Open in Connectum" is.
* The page is built once and kept in memory for a minute; only a code not seen in that minute reaches the database, and those are limited per address (60 a minute, `CONNECTUM_CONNECT_RATE_PER_IP`; then `429` with `Retry-After`).
  It is about 11 KB with its QR code (the test allows 12 KB), is light only, loads nothing from another site (the logo, `/theme/logo/connectum_logo_blue.svg`, comes from this site), and has a strict content policy (script and style pinned by hash, computed at run time from the page's own text, so a colour change needs no policy change).

### What a branch does when a person joins (3 November 2026)

`POST /api/sd/join` takes `connectBranch` (the branch name from the QR, as the app has it). The server reads it once and: 1) **notes** it on the person (`connectBranch`, as the organisation spells it, only for a branch that is on); 2) **uses it as the person's branch** when they picked none: always for an employee (a branch is required of them anyway), and for an outside person only when their category has `branchFromScan` (or `branchBound`); a branch they picked themselves always wins; 3) shows it to the approver (the sign-up request carries `data.branch` and `data.connectBranch`); 4) with the category's `routeByBranch`, asks the approvers who work in that branch first (everyone named when none of them does). A scanned branch that does not exist or is switched off is simply not used: the person still joins. The app should send `connectBranch` whenever the QR named a branch, and pre-fill the branch field with it (only when `GET /api/sd/enterprise/{id}` lists it in `branches`). A person declined at sign-up: see `APPROVALS_AND_SIGNUP.md`.

### The same three values in every handoff: `code`, `org`, `branch`

`org` is present only on a person's link, and only when the organisation exists; `branch` only when that organisation has it. Names and order are fixed; the app ignores parameters it does not know.

| Handoff | Form |
|---|---|
| Link / QR text | `https://{host}/connect/{CODE}[?org={ORG}][&branch={name}]` |
| Open in Connectum (iPhone, and the page's own link) | `{scheme}://connect/{CODE}[?org={ORG}][&branch={name}]` (`connectum` unless the provider set another word) |
| Open in Connectum (Android, package known) | `intent://connect/{CODE}[?org={ORG}][&branch={name}]#Intent;scheme={scheme};package={androidPackage};S.browser_fallback_url={encoded Play address};end` |
| Google Play button | `https://play.google.com/store/apps/details?id={androidPackage}&referrer={encoded: connect_code={CODE}[&connect_org={ORG}][&connect_branch={name}]}` (the Play Install Referrer). While the app is in testing there is a second Android button before it, **Join the test (first time)**, that opens the opt-in link as it is (see below) |
| Google Play button, **claim mode** (the provider's choice) | `{PUBLIC_URL}/connect/{CODE}/play[?org={ORG}][&branch={name}]` on this site; pressing it answers `302` to `{listing address}&referrer=connect_claim%3D{token}` (see "The one-time claim token") |
| iPhone App Store button | copies `connectum:{CODE}[?org={ORG}][&branch={name}]` to the clipboard when tapped, then opens the App Store address (the only button that copies) |
| Continue in your browser | `/?connect={CODE}[&org={ORG}][&branch={name}]` (the web app asks before connecting) |

On its first start the app reads the referrer (Android; nothing is copied there) or, when the person taps Paste, the clipboard (iPhone), keeps the code, and after sign-in or sign-up calls `connect.scan`.
The Google Play address is a **setting** (Admin console > Mobile app): in closed testing it is the opt-in link; once public it is the listing address; empty, the listing address is built from the package. The referrer is `connect_code=..[&connect_org=..][&connect_branch=..]`: each value percent-encoded once (UTF-8: a branch with spaces or non-ASCII letters such as `Zürich Süd & Co` comes back exactly), then the whole string percent-encoded once more as the value of `&referrer=`; always far under Play's 1000 characters. Other devices see both store buttons.

## 3. The two files a phone reads (served for the whole installation)

`GET /.well-known/assetlinks.json` (Android App Links) and `GET /.well-known/apple-app-site-association` (also at `/apple-app-site-association`; iOS Universal Links, paths `/connect/*`). Both are JSON, answered at once, never
redirected. Until the identifiers are set they are an empty list / no apps (valid files). The provider sets them in **Admin console > Mobile app**: Android package + up to 6 SHA-256 fingerprints, iOS Team ID + bundle ID,
the two store addresses (Google Play defaults to the package), and the app's link word. Saving needs the provider key (`CONNECTUM_PROVIDER_KEY`), changes at once, is audited, and clears the kept pages.
Actions: `admin.applinks.get {}`, `admin.applinks.save {providerKey, androidPackage?, androidFingerprints?, iosTeamId?, iosBundleId?, playStoreUrl?, appStoreUrl?, scheme?, referrerMode?}` (only what is sent changes; empty clears).
nginx must send these paths to the backend: `nginx/axi-connect.conf` (install steps inside it).

### While the app is in closed testing on Google Play (1 Nov 2026)

* **Fingerprints:** all three (upload key, debug key, Play app signing key) go into **one** `assetlinks.json` entry, in the order given. Paste each as written, with colons; the server upper-cases and checks them (32 pairs of hex).
* **Play address and the two Android buttons:** an opt-in link (`https://play.google.com/apps/internaltest/...`) cannot carry a referrer, but the normal listing address (`https://play.google.com/store/apps/details?id=PACKAGE`) opens the testing version in Play for a tester who has already opted in, and it can. So while `playStoreUrl` holds the opt-in link the page shows, on Android, **Join the test (first time)** = the opt-in link as it is, and **Get it on Google Play** = the listing address (made from the package) + `&referrer=`. The Android intent's app-missing fallback is the listing address with the referrer. No release is needed to change any of this: it is the Play address setting. When the app is public, put the listing address in the setting (or clear it): there is then one button, **Get it on Google Play**, with exactly the same address form.
* **On Android the page routes by itself** (script in the page, nothing on the server): it goes to the `intent://` link at once, so the app opens if it is installed and otherwise the browser goes to the Google Play listing **with the referrer** (the intent's `S.browser_fallback_url`, URL-encoded):
  `intent://connect/{CODE}[?org=..][&branch=..]#Intent;scheme=connectum;package={androidPackage};S.browser_fallback_url={encoded listing address with referrer};end`.
  It does this **once per tab** (coming back with the back button, or a reload, shows the page and does not send the person away again), only on Android (not iPhone, not desktop; a link-preview robot or search engine runs no script and is never redirected: the server sends every device the same page, status 200), and **`?stay=1`** (also among other parameters, exactly `stay=1`) keeps the page, for testing. The visible buttons (Open in Connectum, Join the test, Get it on Google Play, Continue in your browser) stay as the fallback if the redirect is blocked (some in-app browsers refuse `intent:` links). A page without an Android package set has nothing to open, so it does not route.
* **Clipboard (iPhone only):** a tap on the **App Store** button copies `connectum:CODE[?org=..][&branch=..]` first, because an iPhone has no install referrer. **Nothing is copied on Android**: the code travels in the Play address (the referrer), so the Google Play buttons only open Play.
* **Branches:** a `?branch=` that the organisation does not have, or has switched off, is left out of the page's links on purpose (the QR still opens the organisation), but it is **no longer silent**: the card of `connect.lookup`, `connect.scan` and `GET /api/sd/connect/{code}` carries `enterprise.branchUnavailable: true` (one answer for "no such branch" and "switched off", so a lookup without a sign-in cannot tell them apart), and the page shows a quiet note, "That branch is not available. You can still join." Show the same words in the app and go on with the join. A link that names no branch, or an empty one, has no such flag. To test branches, add one in the organisation's Admin console (branches), switch it off, and scan its QR.
* **Rotating a person's code:** `connect.rotate {}` (signed in as that person; the web app's Connect code window has the button). The old code stops working at once.

### The one-time claim token (optional, the provider's choice)

By default the Play address carries the raw code in its referrer (`connect_code=...`), so the code can sit in Play's logs or in a copied referrer. **Admin console > Mobile app > "What the Google Play button hands to the app"** can be set to **A one-time token** (`referrerMode: "claim"`; the default is `"code"`; either can be changed at any time, no release needed).

1. In claim mode the page's Android **Get it on Google Play** button is `{PUBLIC_URL}/connect/{CODE}/play[?org={ORG}][&branch={name}]` (also the Android intent's app-missing fallback). It needs `CONNECTUM_PUBLIC_URL`; without it the button keeps carrying the code.
2. Pressing it asks the server for the same checks as the page: a real organisation code, or a person's code that names a real organisation (else a plain `404` and nothing stored). It stores `{code, org?, branch?}` for **24 hours** under a random 22-character URL-safe token and answers `302` to `{listing address}&referrer=connect_claim%3D{token}`. Only the token travels.
3. On its first start the app reads the referrer. If it holds `connect_claim=<token>`, it calls `GET /api/sd/connect/claim/{token}` (no sign-in) and gets `{"ok":true,"data":{"code":"KVZDHDQD","org":"Y2NHGHP6","branch":"Zürich Süd & Co"}}`: the same three values the raw referrer would have held (`org` and `branch` only when there are any). Then everything is as with the raw code.
4. The token works **once** (the server deletes it as it answers; four phones asking at the same moment: one gets it). A second try, an expired token, a token that was never made, or text that is not a token all answer `404 not_found` ("That link was already used or has expired."). The app then falls back to the clipboard or to asking for the code.
5. Both the button and the claim call are limited to 20 a minute per address (`429`, `Retry-After` on the button). An app that sees `connect_code=` keeps working in either mode, so support both.

Code: `sd_applinks.erl` (`play_redirect/3`, `claim/1`), `sd_connectpage.erl` (`play/4`), `sd_http.erl` (the claim route). Tests: `connectum_connect_landing_test.mjs`, section "The one-time claim token". Postman: Mobile QR collection, folder 7.

## 4. What the app calls (all need a signed-in session; about 60 codes per 10 minutes per person)

The `code` may be the whole link, `connectum:CODE`, `{scheme}://connect/CODE` (with or without `?org=` and `?branch=`), `CODE?org=…`, or the bare code.
If the link names **another organisation** than the one the person is in, `connect.lookup` and `connect.scan` answer `wrong_org` ("That code is for a different organisation…") and connect nobody; an `org` that is not a code is ignored.

* `GET /api/sd/connect/claim/{token}` (no sign-in, 20 a minute per address) → `{code, org?, branch?}` for a token from the Play referrer in claim mode, **once** (see below).
* `connect.lookup {code}` → who it is, **connecting nothing**: `{type:"person", connected, user:{name, username, designation, department, branch, …}}` or `{enterprise:{name, code, branch?, …}}`.
* `connect.scan {code}` → connects: a person's code makes the two associates at once (the owner is told); an organisation's code returns its card (`alreadyMember:true`).
* `connect.my {}` → the signed-in person's code and the organisation's, with their `payload` strings (what to draw as a QR).
* `GET /api/sd/connect/{code}[?org={ORG}][&branch={name}]` (no sign-in, 60 a minute per address) → the **organisation's** card only. For an organisation's code it is that organisation. For a person's code **with `org`** it is the
  card of the organisation `org` names, `fromPersonLink: true` (the person's code is not even looked at, so a real code and a made-up one answer alike). A person's code without `org`, or with an unknown `org`, answers 404 like an unknown code.
  `org` and `branch` may also be written inside the code (the whole link). Use it to say whose code a scan was before sign-in ("Join {organisation}").

**Limits** (each can be changed by the provider with an environment setting; the defaults are the numbers here):

| What | Default | Setting |
|---|---|---|
| `connect.lookup` + `connect.scan`, together, per signed-in person | 60 per 10 minutes | `CONNECTUM_CONNECT_USER_RATE`, `CONNECTUM_CONNECT_USER_RATE_SECS` |
| `GET /api/sd/connect/…`, `GET /api/sd/enterprise/…`, the landing page `GET /connect/…` (one count) | 60 per minute per address | `CONNECTUM_CONNECT_RATE_PER_IP` |
| the Google Play button `/connect/{CODE}/play` (claim mode), and `GET /api/sd/connect/claim/{token}` | 20 per minute per address each | `CONNECTUM_CONNECT_CLAIM_RATE_PER_IP` |
| `login/start`, per address and per email | 60 per 15 minutes, 20 per 15 minutes | `CONNECTUM_LOGIN_RATE_PER_IP`, `CONNECTUM_LOGIN_RATE_PER_EMAIL` |
| password sign-in | wrong password refused after 8 failures in 15 minutes per email | fixed |
| `register` | 30 per hour per address | `CONNECTUM_REGISTER_RATE_PER_IP` |
| `join` | 20 per hour per account | `CONNECTUM_JOIN_RATE_PER_ACCOUNT` |
| enterprise search | 60 per minute per address | fixed |

`join` answers `{joined, status:"pending"|"active", username, requestId, awaitingApprovalFrom, welcome, nextStep:"approval"|"enter"}`. Someone waiting for approval learns they were approved by `enter` (error `pending_approval`
until then, `rejected` if refused), by `GET /api/sd/me` (each organisation has a `status`), and by the organisation's delivery channel (email or other) which tells them they can sign in.

**Confirm before connecting a person (recommended, and what the web app does):** call `connect.lookup`, show "Connect with {name}?", then `connect.scan` on Yes. Nothing connects by itself from a poster, link or screenshot.

## 5. The three flows

1. **App not installed, new user.** Scan → the page → store (Android carries the code in the referrer; iPhone copies it) → install → first start keeps the code → email check (`login/start` answers 404 for an unknown email) →
   register (`register` → `register/verify`) → **join** with the code: `POST /api/sd/join` (identity token) `{enterprise:{ORG CODE or the link}, …, connectBranch?}`, then `enter` → in the organisation. For a **person** QR the link carries
   `org`, so: show "Join {organisation}" (`GET /api/sd/connect/{CODE}?org={ORG}`), join/enter that organisation first, then `connect.scan` the code.
2. **App not installed, existing user.** Same up to the first start → sign in (`login/start` → `login/verify`) → `enter` → `connect.scan` (after the confirm).
3. **App installed, signed in.** The app opens from the camera with the link → `connect.lookup` → confirm → `connect.scan`. With the app links set up and the app open on the right organisation this is one tap (or none, if the app is set to connect silently).
   If the code is another organisation's, `connect.lookup` answers "not found" in this session: use `GET /api/sd/connect/{code}` for its name and offer to switch or join.

## 6. Setting it up (provider checklist)

1. Set `CONNECTUM_PUBLIC_URL` to the real https domain (the QR codes change with it: people re-print or re-show them) and point DNS and the certificate at the VM.
2. Install `nginx/axi-connect.conf` (see the file) and reload nginx.
3. Admin console > Mobile app: package + fingerprints, Team ID + bundle ID, store addresses; Save with the provider key.
4. Check `https://{domain}/.well-known/assetlinks.json` and `…/apple-app-site-association` show the app, then test a QR on a phone with the app installed and without it.
