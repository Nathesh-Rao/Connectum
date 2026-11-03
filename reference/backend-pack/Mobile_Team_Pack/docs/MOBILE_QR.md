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
* The page is built once and kept in memory for a minute; only a code not seen in that minute reaches the database, and those are limited per address (60 a minute, `CONNECTUM_CONNECT_RATE_PER_IP`; then `429` with `Retry-After`).
  It is under 8 KB, follows the phone's light or dark setting, loads nothing from another site (one logo from this site), and has a strict content policy (script and style pinned by hash).

### The same three values in every handoff: `code`, `org`, `branch`

`org` is present only on a person's link, and only when the organisation exists; `branch` only when that organisation has it. Names and order are fixed; the app ignores parameters it does not know.

| Handoff | Form |
|---|---|
| Link / QR text | `https://{host}/connect/{CODE}[?org={ORG}][&branch={name}]` |
| Open in Connectum (iPhone, and the page's own link) | `{scheme}://connect/{CODE}[?org={ORG}][&branch={name}]` (`connectum` unless the provider set another word) |
| Open in Connectum (Android, package known) | `intent://connect/{CODE}[?org={ORG}][&branch={name}]#Intent;scheme={scheme};package={androidPackage};S.browser_fallback_url={encoded Play address};end` |
| Google Play button | `{Play address}&referrer={encoded: connect_code={CODE}[&connect_org={ORG}][&connect_branch={name}]}` (the Play Install Referrer) |
| iPhone App Store button | copies `connectum:{CODE}[?org={ORG}][&branch={name}]` to the clipboard when tapped, then opens the App Store address |
| Continue in your browser | `/?connect={CODE}[&org={ORG}][&branch={name}]` (the web app asks before connecting) |

On its first start the app reads the referrer (Android) or, when the person taps Paste, the clipboard (iPhone), keeps the code, and after sign-in or sign-up calls `connect.scan`.
The Google Play address is a **setting** (Admin console > Mobile app): for a test it can be the internal-test listing address; empty, it is built from the package. Other devices see both store buttons.

## 3. The two files a phone reads (served for the whole installation)

`GET /.well-known/assetlinks.json` (Android App Links) and `GET /.well-known/apple-app-site-association` (also at `/apple-app-site-association`; iOS Universal Links, paths `/connect/*`). Both are JSON, answered at once, never
redirected. Until the identifiers are set they are an empty list / no apps (valid files). The provider sets them in **Admin console > Mobile app**: Android package + up to 6 SHA-256 fingerprints, iOS Team ID + bundle ID,
the two store addresses (Google Play defaults to the package), and the app's link word. Saving needs the provider key (`CONNECTUM_PROVIDER_KEY`), changes at once, is audited, and clears the kept pages.
Actions: `admin.applinks.get {}`, `admin.applinks.save {providerKey, androidPackage?, androidFingerprints?, iosTeamId?, iosBundleId?, playStoreUrl?, appStoreUrl?, scheme?}` (only what is sent changes; empty clears).
nginx must send these paths to the backend: `nginx/axi-connect.conf` (install steps inside it).

### While the app is in closed testing on Google Play (1 Nov 2026)

* **Fingerprints:** all three (upload key, debug key, Play app signing key) go into **one** `assetlinks.json` entry, in the order given. Paste each as written, with colons; the server upper-cases and checks them (32 pairs of hex).
* **Play address:** the page's "Get it on Google Play" button and the Android fallback use `playStoreUrl`. In closed testing set it to the **opt-in link** (`https://play.google.com/apps/internaltest/...`); it is opened **as it is**. Only the public listing (`.../store/apps/details?id=...`) gets the `referrer=connect_code=CODE[&connect_org=..][&connect_branch=..]` added, because only the public listing can pass an install referrer. When the app is public, change this one setting; no release is needed (it is read from settings, kept for 30 s).
* **Clipboard:** a tap on **any** store button (Google Play or App Store) copies `connectum:CODE[?org=..][&branch=..]` first, so the app can read it on its first start (the Play referrer, when present, is read first).
* **Branches:** a `?branch=` that the organisation does not have is ignored on purpose (the page and the links then carry no branch). To test branches, add one in the organisation's Admin console (branches). Other behaviour: sections 1, 2 and 4.
* **Rotating a person's code:** `connect.rotate {}` (signed in as that person; the web app's Connect code window has the button). The old code stops working at once.

## 4. What the app calls (all need a signed-in session; about 60 codes per 10 minutes per person)

The `code` may be the whole link, `connectum:CODE`, `{scheme}://connect/CODE` (with or without `?org=` and `?branch=`), `CODE?org=…`, or the bare code.
If the link names **another organisation** than the one the person is in, `connect.lookup` and `connect.scan` answer `wrong_org` ("That code is for a different organisation…") and connect nobody; an `org` that is not a code is ignored.

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
