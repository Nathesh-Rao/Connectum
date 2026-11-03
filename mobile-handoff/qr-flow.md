# QR connect flow: analysis and plan

Status: plan only, nothing built. Written 2026-10-30. Sources: backend `origin/main` (8b66e599), `docs/MOBILE_QR.md`, `sd_connectpage.erl`, `sd_applinks.erl`, `sd_connect.erl`, `sd_ident.erl`, `sd_http.erl`, `sd_cmds.erl`; live GET checks on https://connectum.app; this app's code. Items marked UNVERIFIED were not checked against a running system.

## 1. The contract (MOBILE_QR.md, confirmed against the source)

**QR text**: a plain https link. Organisation `https://connectum.app/connect/{CODE}[?branch={url-encoded name}]`; person `https://connectum.app/connect/{PERSON_CODE}`. Without `CONNECTUM_PUBLIC_URL` the QR is `connectum:{CODE}`; production has the URL set (live `payload`/`url` fields show it).

**Code**: 8 chars, Crockford base32 `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no I, L, O, U), shown `XXXX-XXXX`.
Server `normalize` (`sd_connect.erl:27`): max 300 bytes; trim; uppercase; extract from `connectum:CODE` or `<scheme>://<host>/.../connect/CODE`; then drop every non-alphanumeric character, map O→0, I/L→1, U→V; must be exactly 8 chars all in the alphabet. Anything else is `invalid_code`. The server is lenient (strips any junk characters); the app must be stricter (section 4).

**Enterprise id = the organisation code** (lowercased). `parse_id` = `normalize`. So an organisation code is also the id used by `/enterprise/{id}`, `/join`, `/enter`.

**Branch** (`?branch=`): only a label of where the person scanned. Validated against the organisation's active branches, case-insensitive (`branch_named`); an unknown name is silently ignored (no error, no chip). Used in three places: the landing page chip, the `branch` field added to the card of `connect.lookup`/`connect.scan`/public GET, and `connectBranch` in `POST /join` (stored on the new user as connect branch). Not validated for people who are already members (nothing is stored). The landing page and `with_branch` read it from the text, so the app must pass the branch on (`connectum:CODE?branch=X`) to get it back in the card.

**Install handoff**
- Android: Play button href = `{playStoreUrl}&referrer=connect_code%3D{CODE}` (URL-encoded `connect_code=CODE`). The Install Referrer API returns `connect_code=CODE` (possibly with Play's own `utm_*` parts).
- iOS: tapping the App Store button copies the string `connectum:{CODE}` (no branch) to the clipboard (script: `copy(clip)` on click of `#ios`).
- Open link: `connectum://connect/{CODE}[?branch=...]` (scheme setting, default `connectum`). On Android with the package known: `intent://connect/{CODE}[?branch]#Intent;scheme=connectum;package={PKG};S.browser_fallback_url={play url};end`, set as the href by script only on Android.

**Calls** (JSON wrapper `{ok, data}`; chat-protocol commands go over the WebSocket `/sd` action path the app already uses)

| Call | Auth | Request | Response | Errors / limits |
|---|---|---|---|---|
| `GET /api/sd/connect/{code}` | none | code (full text accepted, URL-decoded) | `{type:"enterprise", enterprise:{name, code, display, payload, url, location{address,city,country,pin}\|null, categories[], setupDone, branch?}}`. A person's code answers `not_found` | 60/min per IP (`429 rate_limited`); `not_found`, `invalid` |
| `GET /api/sd/enterprise/{id}` | none | id | name, location, branches[], departments[], designations[], categories[], `onboarding{<category>:{requireApproval, requiredFields[], branchBound, optionsBefore[], welcome}}`, `employeeSignup{mode,codeRequired}`, affiliates | `not_found` |
| `connect.lookup {code}` | enterprise session | code or whole link | `{type:"enterprise", enterprise{...,branch?}}` or `{type:"person", connected:bool, user:{name, username, designation, department, branch, ...}}` | `invalid_code`, `not_found`, `rate_limited` (60 tries / 10 min per user, **shared with scan**) |
| `connect.scan {code}` | enterprise session | same | enterprise: card + `alreadyMember:true`. Person: `{type:"person", user, alreadyConnected:bool}`; connects at once and notifies the owner | `invalid` ("own code"), `forbidden` (`sd_policy:may_interact`), `not_found`, `rate_limited` |
| `connect.my {}` | enterprise session | none | `{person:{code, display, payload, url, name, username}, enterprise:{...}, branches[] (admins only)}` | |
| `connect.rotate {}` | enterprise session | none | new person code; the old one stops | |
| `POST /api/sd/login/start` | none | email | 404 `no_account`-style for an unknown email (the app maps it to code `no_account`) | rate limited |
| `POST /api/sd/join/check`, `/join` | identity token | `{enterprise, category, isEmployee, employeeCode?, ...requiredFields, connectBranch?}` | check: `{ok, fields{}}`. join: `{joined, status:"active"\|"pending", username, requestId, awaitingApprovalFrom, welcome, nextStep:"enter"\|"approval"}` | `already` ("already connected"), `code_required`, `invalid`, `not_found`, `rate_limited` (join 20/hour per email), field errors |
| `POST /api/sd/enter` | identity token | `{enterprise,...}` | enterprise session | `not_member`, `pending_approval`, `rejected`, `account_inactive` |

Important behaviours:
- `connect.lookup`/`scan` run inside the signed-in enterprise. A code of another organisation answers `not_found` there. Doc section 5 says the same: use the public GET for the other organisation's name, then offer to switch or join.
- A person's code is only resolvable inside its own organisation's session, and **the URL carries no organisation** (see questions 1, 2).
- `join` of someone the organisation already holds under that email (invited, or listed employee) returns `joined:true` with no approval (`link_existing`). With an employee code it goes through the claim.

## 2. What the GET checks showed (2026-10-30)

| URL | Result |
|---|---|
| `/.well-known/assetlinks.json` | 200, body `[]` |
| `/.well-known/apple-app-site-association` | 200 `application/json`, `{"applinks":{"apps":[],"details":[]}}` |
| `/connect/Y2NHGHP6` default, Android UA, iPhone UA | 200, **byte-identical** HTML (md5 equal) for all three |
| `/api/sd/public` | `{mode:"strict", platform:true}` |
| `/api/sd/connect/Y2NHGHP6` | the enterprise card (above); categories: 15 |
| `/api/sd/enterprise/Y2NH-GHP6` | branches `["Head office"]`, 15 categories, all `requireApproval:true`, `requiredFields:[]`, `welcome:""` |

**Why there are no store buttons or intent link.** The server does not vary by User-Agent. It always sends the same page; a script sets `data-os` and CSS hides the other platform's button. The buttons are simply not rendered because the provider settings are empty (`sd_connectpage.page`):
- Google Play button: rendered only when `playStoreUrl` is set, or derived from `androidPackage` (`https://play.google.com/store/apps/details?id=PKG`). Its href gets `&referrer=connect_code%3D{CODE}`.
- App Store button (`id="ios"`): only when `appStoreUrl` is set (https, host `apps.apple.com` or `itunes.apple.com`).
- Intent link (`data-intent` on "Open in Connectum"): only when `androidPackage` is set (fallback to Play is added only if a Play URL exists).
- assetlinks needs `androidPackage` **and** at least one fingerprint; AASA needs `iosTeamId` **and** `iosBundleId`.

All are set in Admin console > Mobile app, or `admin.applinks.save {providerKey, androidPackage, androidFingerprints[≤6], iosTeamId, iosBundleId, playStoreUrl, appStoreUrl, scheme}` (needs the provider key `CONNECTUM_PROVIDER_KEY`, which only the backend side holds). Saving clears the page cache; assetlinks/AASA are cached 5 minutes (`max-age=300`).
The branch chip was missing for `?branch=Chennai` because the organisation has no active branch called Chennai; this is the designed behaviour (`?branch=Head%20office` should show it; not fetched, outside the allowed GET list).
Other observations: the page for a person's code, an unknown code and an inactive organisation is the same generic "Connect on Connectum" page; the "Continue in your browser" link goes to `/?connect=CODE` (web app).

**What the server needs from me** (send to the backend developer to enter):
1. Android package `com.agile.connectum` (currently the applicationId; confirm it is final, see 8).
2. SHA-256 fingerprints: debug key, upload key, Play app signing key (up to 6 allowed).
3. iOS Team ID (pbxproj has `ZDYX426H32`, confirm it is the account that will publish) and bundle id `com.agile.connectum`.
4. Play listing URL (or leave blank: derived from the package) and App Store URL (only exists after the App Store Connect record exists).
5. Scheme: keep `connectum`.

## 3. Flows mapped onto the code

### What exists today
- `DeepLinkService` (`lib/core/routes/deep_link_service.dart`): listens to `app_links`, `map()` builds `AppLink{code, branch, host}`, keeps `pendingLink` **in memory only**, and `openPending()` just opens `/enterprises`. Nothing consumes the code.
- Bugs/gaps found in `map()`: (a) the app's own open link `connectum://connect/CODE` yields host `connect`, path `/CODE`, so the code becomes `/CODE` (slash kept); (b) no alphabet/length validation; no O/I/L/U mapping; (c) any host is accepted for https; (d) `connectum:CODE?branch=X` is fine. (e) `EnterprisesController.asConnectumId` is a second, different copy of the code rules.
- Splash routes to chats / enterprises / authentication / onboarding and calls `deepLinks.openPending()` only when it did not route to authentication/onboarding. After login and OTP the app goes to `/enterprises` (`Get.offAllNamed`) but nothing calls `openPending()` there. So a signed-out link is not resumed.
- Enterprises screen: membership list with `Pending`/`Rejected` handling in `enter()`, `refresh()` calls `auth.refreshMe()`; a join by search sheet (`join_sheet.dart`) using `/enterprise/{id}`, `/join/check`, `/join`. It does not send `connectBranch`, refuses categories with `requiredFields`, and shows only text for pending.
- `AuthRepository.byId/publicPage/join/joinCheck/enter` exist. `startLogin` maps the 404 to `no_account`, which the form shows under the email field; it does not offer register. Register is the "Self register" tab and needs name, mobile, etc.; `register` → `register/verify` → identity; then Enterprises.
- No middleware exists (CLAUDE.md names `GetMiddleware` guards; none are in `lib`). The pending-link flow below is done in the service, not a guard.
- Native: no intent filters, no URL types, no entitlements file, no camera permission, no referrer or clipboard code, no scanner, no QR renderer, no Connect screen. `launchMode=singleTop` is already set. Flutter's own deep-link handling is not disabled (see 6).
- The Postman collection has no `connect` endpoints and still documents a private `http://10.0.2.146` server; `deep-links.md` still lists the production URL as UNCLEAR. Both are now superseded by MOBILE_QR.md and the live checks above; treat the code as the truth.

### One handler (new, small)
- `ConnectCode.parse(String text)` (pure Dart, in `lib/features/connect/models/`): returns `code` + `branch?` or null. Replaces `map()`'s parsing and `asConnectumId`.
- `ConnectService` (a `GetxService` registered in `InitialBinding`, replaces `DeepLinkService`'s link parts): `receive(source, text)` with `source` in `link | scanner | referrer | clipboard | manual`. It parses, stores one `PendingConnect{code, branch, source, receivedAt}` in secure storage (survives kill during OTP), then `resume()`.
- `resume()` is called: on receive, after login/verification/register success, after `enter`, after Enterprises/Chats first build, on app resume and on network regain. It routes to `/connect/:code?branch=` (the confirm screen) or does nothing if the app is not at a stage that can handle it.

### Screens and states
`/connect` = the Connect hub (scanner, manual entry, my code). `/connect/:code` = confirm screen (route params only, so it can be opened from any link). Each has one controller, view and binding. The confirm screen is one `AppStateView`-based screen with these states:

| State | Behaviour |
|---|---|
| Not signed in | Link arrives: store pending, continue the normal splash → onboarding/authentication. Show a small `AppNoticeBanner` on the auth screen: only what the public GET returned ("You're joining Test organisation Mobile team"). Person code: "A connection code is waiting" (nothing else). After sign-in/OTP/register the app lands on Enterprises and `resume()` opens the confirm screen. |
| Signed in as identity, no enterprise active | Org code: public card → confirm "Join {name}?" with category picker → join. If already a member: show the membership state instead (see below). Person code: cannot be resolved (question 1); keep the code, ask the user to enter the organisation they know the person from, then lookup. |
| Enterprise active, same organisation | Org code: `connect.lookup` → `alreadyMember` message "You are already in {name}". Nothing to confirm. Person: `connect.lookup` → "Connect with {name}?" (name, designation, department) → `connect.scan`. Distinguish `connected:true` ("You're already connected"), own code ("That's your own code"), `forbidden` (server message), `not_found` ("Not found in {org}. It may belong to another organisation or the code was renewed"). |
| Enterprise active, different organisation | Never switch silently. Public GET card → "Join {name}?" (not a member) or "Switch to {name}?" (member, active). Both are explicit buttons; the code stays pending until done or cancelled. Switching uses the existing `enter` path. |
| Needs category | `/enterprise/{id}` categories. One category: preselect. Several: picker. Show "approval needed" from `onboarding[cat].requireApproval` before the user taps (the flag drives the notice; UNVERIFIED that it always equals "approvers exist", `sd_onboarding:approvers` is the real decider; the join answer is authoritative). |
| Needs extra fields | `requiredFields` non-empty: show "This needs more details than the mobile app supports yet" with the code kept (same as today's join sheet). Stage 6 can add fields. `join/check` `fields` errors shown inline. |
| Joined, active | Success animation, "Enter {name}" button → `enter`. If the pending code was a person code, `resume()` runs `connect.lookup` after entering. |
| Joined, **pending approval** | Screen "Request sent to {name}", the `welcome` text, "You can enter once an administrator approves". The membership appears on Enterprises with the Pending pill. Entering gives `pending_approval` (message already handled in `enter()`). Pending code is cleared once the join returned (the join is done); person codes are kept. How the user learns: there is no push, and no socket before entering an organisation (CONNECTUM docs: no service worker/push). So: Enterprises refreshes `refreshMe()` on screen open, pull-to-refresh, app resume, and every 60 s while a pending membership is visible; when status flips to active show a toast "Approved: Enter {name}". Question 5 asks the backend for an email or push on approval. |
| Rejected | `enter` returns `rejected`; membership shows Rejected pill and message "Your request to join was not approved". Join can't be re-sent (`already`). |
| Invalid / rotated / unknown | Invalid text: message at the scanner, nothing stored. `not_found` from the public GET or lookup: "This code isn't valid any more. Ask for a new one." Clear pending. |
| Different email than expected | The code is not bound to an email, so there is no mismatch to detect. If the signed-in account is already a member, `already`/`alreadyMember` is shown as success. Registering a new email that the organisation already knows is linked without approval (server behaviour). |
| Offline | Confirm needs a connection: connection-only screen (`AppStateView` offline), pending kept; `resume()` on network regain. The scanner itself works offline (it only stores the code). |
| Link while form or chat open | Never navigate away from an open form or a conversation with a draft. Keep pending and show a dismissible banner on the next Chats build ("Connection request waiting: Open"). |
| Same link twice | Pending is keyed by code; if the same code is already open in the confirm screen or was received less than 10 s ago, ignore. A code already resolved earlier gives a harmless alreadyMember/alreadyConnected. The cold-start initial link is stored with a "handled" marker so a hot restart does not replay it. |
| Cancel | Clears the pending code and goes back. Back from the confirm screen = cancel. |

### Flow A (installed, signed in)
link → `ConnectService.receive` → `/connect/:code` → lookup (current org) or public GET (other org) → confirm → `connect.scan` / `join`. Missing today: everything after the parse.
### Flow B (not installed, existing user)
landing page → store → install → first launch reads referrer (Android) / clipboard (iOS) → pending → onboarding → login → OTP → Enterprises → confirm → join or connect. The pending code must survive onboarding, OTP and an app kill: store it in secure storage and clear on success/cancel/24 h.
### Flow C (not installed, new user)
Same, but `login/start` 404: the sign-in form shows `no_account`. Add a single action there: "Create an account" switching to the Self register tab with the email prefilled, while the pending notice stays visible. After `register/verify` the app joins with the code through the same confirm screen (the identity token is enough for `/join`). Needs one user decision (question 9): the register tab asks for several fields; is a shorter path wanted?
### Person QR
- Flow A: handled (same organisation) or `not_found` (different org).
- Fresh install: impossible to know the organisation from the URL (section 1). The doc's flow says "join that organisation first" but does not say how the app learns which. Until the backend answers, the app keeps the code, lets the user pick an organisation they belong to, runs `connect.lookup` there, and says "Not found" otherwise.

## 4. In-app scanner and Connect screen

**One handler**: scanner, manual entry, clipboard, referrer and links all call `ConnectService.receive(source, text)`.

**Accepted formats** (strict; the scanner is the untrusted-input boundary):
1. `https://<trusted host>/connect/<CODE>[?branch=..]` where trusted host = host of `AppConfig.baseUrl` (connectum.app). Other hosts: rejected, even with a valid code.
2. `connectum:<CODE>[?branch=..]` and `connectum://connect/<CODE>[?branch=..]`.
3. Bare code `XXXX-XXXX` or `XXXXXXXX` (case, spaces, dashes forgiven; O→0, I/L→1, U→V).
After removing separators the code must be exactly 8 chars of the alphabet. Anything else: "This isn't a Connectum QR code." shown for 2 s, scanning continues, same payload ignored for 3 s. Branch: at most 60 chars, trimmed; control characters rejected.
**Important server quirk**: the server cannot parse `connectum://connect/CODE` (its regex wants `/connect/` after the host; the text falls through, stripping gives the wrong length). The app must send `connect.lookup/scan` the bare code or `connectum:CODE[?branch=X]`, never the raw link. Reported as question 3.

**Connect screen** (no prototype design; propose, from tokens and `App*` widgets): `AppScaffold` titled "Connect". Top: camera preview in an `AppRadius` rounded card (fixed 4:3, overlay corners in `AppColors` accent), torch icon button top-right of the card, hint line "Scan a Connectum QR code". Below: divider "or", `AppTextField` "Enter a code" (auto-format `XXXX-XXXX`, uppercase) with an `AppButton` "Continue". Footer row: "My QR code" (stage 7, hidden until built). States through `AppStateView`: camera starting, permission denied (explanation + "Try again" + "Open settings"), no camera, unsupported. Works signed out (it only stores the code). Entry points: a QR icon in the Chats header next to existing actions (verify space in the header at build time), a "Connect" row in Profile, and "Have a connection code?" under the sign-in form and on Enterprises (opens the same screen).

**Camera permission**: the scanner package reports a denied error; Android's package cannot tell denied from permanently denied, so after one denial show "Open settings" always. Settings shortcut: add a `openSettings` method to the existing `connectum/device` MethodChannel (Kotlin: `ACTION_APPLICATION_DETAILS_SETTINGS`; Swift: `UIApplication.openSettingsURLString`). This avoids adding a settings package. iOS: after the first denial the system never asks again, so the screen goes straight to settings.
**Torch**: scanner controller toggle; hidden when the device reports none.
**Manual entry** also covers a damaged QR.

**Scanner package (pub.dev, checked today)**:
| Package | Version | Notes |
|---|---|---|
| `mobile_scanner` | 7.4.2 | CameraX + ML Kit (Android), AVFoundation/Vision (iOS), BSD-3, 160/160 points, ~2.1 M downloads, 2308 likes. Controller with torch, permission errors, `onDetect`. |
| `ai_barcode_scanner` | 8.2.0 | a UI wrapper built on mobile_scanner; extra layer. |
| others (`qrscan`, `lightweight_barcode_scanner`, ...) | | small, few users. |
Recommendation: `mobile_scanner`. Mainstream, maintained, supports both platforms, gives a widget (needed for the embedded preview and overlay) plus torch. Before adding, check (UNVERIFIED, I did not read its pubspec): its minimum iOS/Android versions against this app's iOS 13.0 deployment target and Flutter's default minSdk, its Android manifest (does it declare `CAMERA`?) and the ML Kit model delivery (bundled vs downloaded; the bundled one adds a few MB to the app). Not added now.

**Optional "My QR"** (not in scope): `connect.my` already returns `payload` strings. Drawing needs one package: `pretty_qr_code` 3.6.0 (widget, MIT, ~212 k downloads) or the pure Dart `qr` 4.0.1 with a small `CustomPainter`. Cost: one package, one section on the Connect screen (person code, enterprise code, branch picker for admins, rotate button with a confirm), about 1 day. Rotation invalidates old QR images; show that.

## 5. Security review

- **Strict parse from every source** (scanner, link, referrer, clipboard, manual). Code = 8 alphabet chars or rejected. https host must be the configured host. Branch is display text only: length-limit, never used in a route path or SQL, never as an identifier.
- **Referrer and clipboard are untrusted hints.** They only create a pending code, which always goes to the confirm screen. They never trigger `join` or `connect.scan` by themselves. A malicious app or a copied text can at worst show a "Join X?" prompt.
- **Always confirm**, including organisations (decided). Person connect shows who it is first (`connect.lookup`).
- **Before sign-in show only what the public endpoint returns** (organisation name, city). Never a person's details; the server also refuses to resolve person codes without sign-in.
- **No logging** of codes, branches, referrer strings, clipboard text, emails. `redact.dart` exists: add the code pattern if codes might appear in error messages; the debug `REACT` prints are unrelated. No analytics. The code never goes into a URL path that is logged by the app.
- **Pending lifecycle**: stored only in secure storage (`first_unlock_this_device`); cleared on success, cancel, any `not_found`/`invalid`, explicit sign out, and 24 h (the proposal; question 8). Kept across auth errors and `session_replaced`-style logouts (the user did not choose to drop it) but not across explicit sign out.
- **Switching organisation**: a link never calls `enter` on its own; the switch is an explicit button naming the target. The chat socket of the current organisation is not touched until then.
- **Rotation and replay**: person codes rotate (only the current works); an old poster gives `not_found`. A valid person code connects instantly on `connect.scan`, so the confirm step is the only protection against a hostile poster; keep it. The server limits (60 tries / 10 min per user, join 20/hour, 60/min per IP) are the brute-force defence; the app must show `rate_limited` politely and not auto-retry in a loop.
- **Shared limit**: lookup and scan share one counter, so lookup+scan costs 2 tries; avoid a second lookup per code.
- **Referrer handling**: read once, then mark consumed in a marker file (see 6), accept only the exact key `connect_code`.
- Landing page itself: CSP pinned by hash, nothing external, no personal data; fine.

## 6. Native work

### Android
- Manifest, on `MainActivity` (singleTop already):
  - `<intent-filter android:autoVerify="true">` VIEW, DEFAULT, BROWSABLE; `<data android:scheme="https" android:host="connectum.app" android:pathPrefix="/connect/"/>`.
  - `<intent-filter>` VIEW, DEFAULT, BROWSABLE; `<data android:scheme="connectum" android:host="connect"/>`, and a second `<data android:scheme="connectum"/>` for `connectum:CODE` (opaque URI; UNVERIFIED that Android matches a bare scheme without host; test with adb, section 9).
  - `<meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>` (check app_links' README for the current key). Without it Flutter's own deep-link handler also pushes `/connect/CODE` as a route into GetX, which now would match `/connect/:code` and bypass `ConnectService`. The iOS equivalent is `FlutterDeepLinkingEnabled=false` in Info.plist.
  - `<uses-permission android:name="android.permission.CAMERA"/>` and `<uses-feature android:name="android.hardware.camera" android:required="false"/>` (so Play does not filter out devices).
  - Release uses https only, so no new network config.
- Install Referrer options:
  1. `play_install_referrer` 0.6.0 (BSD-2, 88 k downloads, 160 points): one new Dart package.
  2. Own code in the existing `connectum/device` channel with Gradle `implementation("com.android.installreferrer:installreferrer:2.2")` (version to confirm); about 40 lines of Kotlin, no new pub package, and it fits the channel already used for `model`.
  3. Attribution SDK packages (`launchtrack`, `linklab_flutter_sdk`, ...): not wanted, they add servers and trackers.
  Pick option 2 (smallest surface, no third-party Dart code); option 1 is the fallback if the Kotlin side proves fiddly. Parse with `Uri.splitQueryString`, accept only `connect_code`. Read once per install: marker file in the app support directory (`path_provider`), **not** secure storage.
- Needs from me: nothing for the manifest. Fingerprints and package go to the backend (section 2).

### iOS
- New `ios/Runner/Runner.entitlements` with `com.apple.developer.associated-domains` = `applinks:connectum.app`, and the capability enabled in Xcode (Signing & Capabilities) and on the App ID in the developer portal. For development-signed builds add `?mode=developer` while testing, and remove before release. Needs: Apple developer account access, the App ID `com.agile.connectum` with Associated Domains.
- Info.plist: `CFBundleURLTypes` with scheme `connectum`; `NSCameraUsageDescription` (for example "Connectum uses the camera to scan Connectum QR codes."); `FlutterDeepLinkingEnabled` = false. `NSAllowsLocalNetworking` removal is already in the release list.
- Clipboard on first launch: reading `UIPasteboard.general.string` (and Flutter's `Clipboard.getData`) triggers the system paste prompt on iOS 16+. `hasStrings` does not prompt but is true for anything. `detectPatterns(for:)` only knows built-in patterns such as `probableWebURL`; whether `connectum:CODE` is matched as a probable web URL is UNVERIFIED (test on a device). A cleaner option is to ask the backend to copy the https link instead (question 4), then `detectPatterns([.probableWebURL])` can gate the read without a prompt. Plan: on the first launch only, behind the marker file, if `hasStrings`, read once and accept only the exact pattern `connectum:CODE`; ignore everything else without telling the user. Add the "Have a connection code? Paste it" fallback (section 7) so a denied prompt is not a dead end.
- Needs from me: Team ID confirmation, App Store Connect record, the Associated Domains capability on the App ID, and a physical iPhone to test (universal links do not work reliably in the simulator).

## 7. Fallbacks and test hooks

- **No code arrived on first launch** (referrer failed, paste denied, user installed first): "Have a connection code?" link on the authentication screen, Enterprises, and the Connect screen: manual entry, scan, or "Paste copied code" (explicit tap, so the iOS prompt is expected by the user). Same `receive(source: manual)`.
- **Optional automatic clipboard check** beyond first launch: not recommended (prompts on every foreground, privacy cost). Only first launch plus the explicit button.
- **Debug-only simulation**: a hidden field on `/debug/e2e`-style debug screen (new `/debug/connect` is simpler; registered under `!kReleaseMode` like the others) with: a text field + buttons "Simulate Android referrer" (feeds `connect_code=CODE` through the same parser the native read uses), "Simulate iOS clipboard" (feeds `connectum:CODE`), and "Reset first-launch marker". Add the route, view and any `lib/features/debug_connect/` to the CLAUDE.md "Before release" list. In release the real native readers are the only source.

## 8. Release readiness (Play INTERNAL testing, TestFlight)

- **Signing today**: `android/app/build.gradle.kts` signs release with the **debug** key (TODO comment). `android/.gitignore` already ignores `key.properties`, `*.jks`, `*.keystore`. Plan: read `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) in the gradle file with a `signingConfigs.release`; if the file is missing, fail the release build with a clear message instead of falling back to debug. I never create, print or store a keystore or password. You create it yourself (for example `keytool -genkeypair -v -keystore <path>/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`) and fill `key.properties` locally.
- **Play app signing**: with an AAB on Play, Google re-signs with its own key. Links verify against the **Play app signing** key, so that key's SHA-256 is the one that matters for installed-from-Play builds.
- **Commands for the fingerprints** (you run them; they print only fingerprints):
  - Debug key: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA256` (or `cd android && ./gradlew signingReport`).
  - Upload key: `keytool -list -v -keystore /path/to/upload-keystore.jks -alias upload | grep SHA256` (it asks for the password; type it yourself).
  - Play app signing key: Play Console > select the app > Test and release > App integrity > App signing > "App signing key certificate" > SHA-256 (older consoles: Setup > App signing). Only appears after the app exists and a first bundle is uploaded.
  - Send all three, colon-separated, to the backend developer (`androidFingerprints`, max 6).
- **Missing today**: release signing config; AppConfig release behaviour (below); `versionCode`/`versionName` from `pubspec.yaml` `version: 0.1.0` (set `0.1.0+1`; Play needs an increasing build number); app icons and launch images are unverified; `android:label`/`CFBundleDisplayName` "Connectum" set; the privacy policy URL and data-safety form (Play asks for camera use, data collected: email, name, mobile, messages); App Store privacy answers; iOS Distribution certificate and App Store provisioning profile (Xcode automatic signing with team `ZDYX426H32` if it is the right account); export-compliance answer (the app uses encryption: `ITSAppUsesNonExemptEncryption`, E2E; decide the answer).
- **AppConfig**: `validate()` runs in `main.dart` and in release throws a `StateError` unless both URLs are https/wss; an empty value also fails (good), but a throw before `runApp` gives a white screen, not a clear message. Plan: replace the throw with a small configuration error screen (plain text, no network) shown in release when `BASE_URL`/`WS_URL` are missing or insecure. Also assert the ws host equals the base host, and derive the allowed link host from `baseUrl`. No default to the private server exists in `lib` (grep for `10.0.2` found nothing). Release build flags: `--dart-define=BASE_URL=https://connectum.app --dart-define=WS_URL=wss://connectum.app/ws`.
- **Debug tools unreachable in release**: `/gallery`, `/debug/socket`, `/debug/assets`, `/debug/e2e` are registered only under `!kReleaseMode` / `kDebugMode` (`app_pages.dart:154,180`), and `SEED_UI` is `!kReleaseMode`. Still do the "Before release" removals in CLAUDE.md before the first store upload (files, the `mobile-handoff/e2e-vectors.json` asset, REACT prints, `NSAllowsLocalNetworking`, debug network security config), plus the new `/debug/connect`.
- **First release build risks (R8/shrinking)**: `minifyEnabled` is not configured, so Flutter's default for release applies (R8 minify on in recent Flutter templates; confirm in the merged config). Risks: `webcrypto` (native BoringSSL via FFI, loads `.so`; it also needs the build toolchain to fetch/compile native assets, test a release build early), `sqflite` (reflection-free, low risk), `flutter_secure_storage` (uses AndroidX security; check for R8 warnings about Tink), `app_links` (low), ML Kit via `mobile_scanner` (ships consumer rules), and the new Installreferrer library (AIDL, needs keep rules only if reflection; normally none). Mitigation: run one `flutter build appbundle --release` (you run it) and install the resulting apk via `bundletool` or `flutter build apk --release` on a real device, exercising login, E2E decrypt and an attachment, before uploading. Add `-dontwarn` only for warnings that actually show up.
- **applicationId / bundle id**: both `com.agile.connectum` (RunnerTests `com.agile.connectum.RunnerTests`). The "agile" prefix looks like a company namespace, not a final product id; these can never change after the first upload, and assetlinks/AASA are keyed on them. Confirm before the backend is given the values (question 10).
- **Unverified for Play internal testing**: that the Install Referrer carries `connect_code` on an internal test track. Internal testers install through an opt-in link or the Play listing, and the Play page opened from the landing page is visible only to people who are testers (others see "not found"). So: the landing page's Play button can only be tested by an invited tester account; the referrer on a test track install is documented to work like production but I could not verify it here; assetlinks verification works on internal testing only after the Play signing fingerprint is added and Play has finished processing (can take hours). TestFlight has no clipboard/referrer issue but the App Store button on the landing page points to the public App Store page, which does not exist until release, so on TestFlight the iOS flow is tested by copying `connectum:CODE` by hand (or via the debug hook) and opening the TestFlight build.

## 9. Test plan

### Before any store (adb, Android)
Debug build installed. Replace `CODE` with `Y2NHGHP6`.
- Custom scheme: `adb shell am start -W -a android.intent.action.VIEW -d "connectum://connect/Y2NHGHP6" com.agile.connectum`; also `"connectum:Y2NHGHP6"` and with `?branch=Head%20office`.
- https link (works as an intent match even without verification; opens the chooser if unverified): `adb shell am start -W -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "https://connectum.app/connect/Y2NHGHP6"`.
- Verification state: `adb shell pm get-app-links com.agile.connectum`; force a recheck: `adb shell pm verify-app-links --re-verify com.agile.connectum`; for local testing before assetlinks exists: `adb shell pm set-app-links --package com.agile.connectum 2 connectum.app` (Android 12+; undo with `pm set-app-links --package com.agile.connectum 0 all`). A real verification needs the backend's assetlinks filled (section 2).
- Cold start vs running vs backgrounded for each of those; the same link twice; a link while a form is open.
- Referrer: not testable with adb for a debug install except through the debug hook; the real thing needs a Play install. (`adb shell am broadcast -a com.android.vending.INSTALL_REFERRER` only reaches the legacy receiver, not the API; do not rely on it.)
### iOS
- Custom scheme in the simulator: `xcrun simctl openurl booted "connectum://connect/Y2NHGHP6"`.
- Universal links need a device, the entitlement, and a filled AASA; test from Notes/Messages (tap, not typing in Safari).
- Clipboard: simulator pasteboard `echo -n "connectum:Y2NHGHP6" | xcrun simctl pbcopy booted`, then first launch (delete the app and the marker, reinstall). The paste prompt appears on iOS 16+ simulators; confirm its wording and the denied path.
### Needs a real store install
Install Referrer; the Play listing visibility for testers; App Store button copy and the later clipboard read on a clean device; the AASA/assetlinks verification with the real signing key; R8 behaviour.
### Checklist
- Flow A: link opens app (cold/warm), lookup → confirm → scan; person connect; already member; own code; other-org code.
- Flow B: install, first launch, sign in, OTP, confirm, join (pending), approval appears, enter.
- Flow C: unknown email → create account → OTP → join; code survives kill during OTP.
- Failure: invalid code, unknown (`not_found`), rotated person code, rate limited, offline at each stage, 429 from the landing/public GET, session expiry mid-flow, server answers `already`.
- Camera: first-time allow, deny once (retry), deny permanently (Settings shortcut then return and rescan), restricted (iOS parental), no camera (emulator), torch toggle, rotation lock (the app is portrait only).
- QR quality: QR shown on a screen (moiré, brightness), poor light with torch, QR printed small, damaged/partly covered QR (should fail cleanly and offer manual entry), a non-Connectum QR (Wi-Fi, url of another host), a QR with a valid code on another host (rejected).
- Pending approval refresh; rejected; Enterprises screen after resume.

## 10. Staged build plan (effort in working days)

| Stage | Content | Days | Needs |
|---|---|---|---|
| 1 | `ConnectCode.parse`, `ConnectService` with persisted pending code, 24 h lifecycle, replace `DeepLinkService.map`; tests are not run per project rules, analyze only | 1 | nothing |
| 2 | Confirm screen `/connect/:code` + controller/binding, all states, public GET card, `connect.lookup/scan`, join with category, `connectBranch`, pending-approval screen and Enterprises polling/toast; resume hooks after login/OTP/register/enter; person code basic flow | 4 | nothing |
| 3 | Debug hook screen (referrer/clipboard simulation) so flows B/C run end to end on a debug build | 0.5 | nothing |
| 4 | Android native: intent filters, scheme, disable Flutter deep linking, referrer via channel, CAMERA, settings shortcut; iOS native: entitlements, URL types, clipboard read, camera string, flag | 2 | package id and Team ID decisions (questions 10, 11); fingerprints and backend settings only for end-to-end App Links |
| 5 | Connect hub screen: scanner, manual entry, permission flow, torch, entry points, "Have a connection code?" | 2 | approval to add `mobile_scanner` |
| 6 | Flow C polish (unknown email → register), `requiredFields` support in join (reuse form widgets), employee code | 2 to 3 | question 9 |
| 7 | Optional "My QR" | 1 | approval for `pretty_qr_code` (or `qr`) |
| 8 | Release readiness: signing config, AppConfig error screen, versioning, R8 check, Before-release cleanup, store metadata | 2 | keystore (mine), accounts, Play/App Store records |
Total about 14 to 15 days. Stages 1 to 3 can start now without identifiers, accounts or the scanner package. Stage 4's Dart parts can too; its verification needs the backend settings. Stage 5 waits only for the package approval.

## 11. Open questions

For the backend developer:
1. Person QR carries no organisation, and `connect.lookup` only resolves it inside the right organisation's session. How is a fresh install supposed to know the organisation? Suggest adding `?e={ORG_CODE}` to person QR URLs (and the landing page). Without it, flow C for a person QR cannot be built.
2. Can the public GET resolve a person code's organisation (name only, no person data)? Matters for the "Join the organisation first" step in MOBILE_QR.md section 5.
3. `connect.lookup/scan` cannot parse `connectum://connect/CODE` (the `Open in Connectum` form) because the regex needs a slash before `connect`. Fix it or confirm the app should always send a bare code / `connectum:CODE`. Matters for sending the branch.
4. Can the iOS clipboard string be the https link instead of `connectum:CODE`? That lets the app detect it with `detectPatterns(probableWebURL)` and avoid the paste prompt on unrelated clipboard text. Also the clipboard is written only when the iOS button is tapped, and the button only exists once `appStoreUrl` is set.
5. Is there an email or push when a pending join is approved? Without it the user has to open the app and refresh.
6. Please fill Mobile app settings (package, three fingerprints, Team ID, bundle id, store URLs) once I send them; also confirm whether the landing page may get a visible fallback when no store URL is set (today it silently shows no store button).
7. Does `onboarding[category].requireApproval` always match whether `join` returns pending (`sd_onboarding:approvers`)? Matters for the "approval needed" notice before joining.
8. Is 24 hours acceptable for the pending code, and do branch QR codes expire?

For me:
9. Flow C: is the full "Self register" form acceptable after an unknown email, or do you want a shorter path (name only) when the backend allows it?
10. Is `com.agile.connectum` the final Android applicationId and iOS bundle id? It cannot change after upload and the backend files depend on it.
11. Is team `ZDYX426H32` (in the Xcode project) the account that will publish to TestFlight and the App Store, and does the Play developer account exist?
12. Which clipboard behaviour do you want: automatic first-launch read (system paste prompt) or only the explicit "Paste copied code" button?
13. Scanner package: approve `mobile_scanner`? And is "My QR" wanted now or later?
