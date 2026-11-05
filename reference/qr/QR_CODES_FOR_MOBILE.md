# QR codes in the web app (personal and organisation), for the mobile team

Analysis only, no code changed. Paths from `connectum/`. `cc/` = `chat-app/features/connectumChat/`, `be/` = `connectum-backend/src/`. Line numbers as of `main`, 5 Nov 2026.
This complements `docs/MOBILE_QR.md` (what a scanned link opens, landing page, app links, rate limits). Its content is not repeated; section 11 lists where it differs from the code.

## 1. Where the web shows a QR

| # | Place | How it is opened | What the person sees / can do |
|---|---|---|---|
| 1 | **Connect window** `cc/components/modals/ConnectCodeModal.jsx` | Top bar button, icon `qr_code_2`, label **Connect**, tooltip "Show Connectum QR Code or Scan to Connect" (`cc/components/TopBar.jsx`:60; opens `connect_code`, `cc/ConnectumChatScreen.jsx`:1582) | Title "Connectum Codes & QR", subtitle "Instant contact exchange, enterprise connection and QR scanning" (:~295). Three tabs: **My Code & QR**, **Enterprise QR**, **Connect via Code** |
| 2 | **Profile > My QR Code** `cc/components/modals/ProfileModal.jsx` | Profile window, tab `qr` labelled "My QR Code" (:20) | The person's own QR only (no organisation QR) |
| 3 | **Sign-up / set-up screens** `cc/components/ConnectumAuthScreen.jsx`:545–566 | After sign-up | A small card for the **Connectum ID**: label "Your Connectum ID" (:379) or "Enterprise Connectum ID: share it so people can join" (:440); QR of `connectum:<ID>`, buttons **Copy** and **Save QR** (file `connectum-<ID>.png`) |
| 4 | **Landing page** `/connect/<CODE>` (server HTML) | Anyone who opens the link | A QR of the page's own link (`be/http/sd_connectpage.erl`:239, `sd_qr.erl`); see `MOBILE_QR.md` §2 |

**Not found:** no QR on the admin console organisation page, members list, or branches page. The admin console's only QR-related tab is **Mobile app** (`cc/components/modals/AdminConsoleModal.jsx`:88, icon `qr_code_2`), which edits the app-link settings (`admin.applinks.get/save`, see `MOBILE_QR.md` §3); it shows no QR. Branch QR codes exist only inside the Connect window's **Enterprise QR** tab (section 5). There is no print, regenerate-organisation-code, revoke, or expiry control anywhere; **expiry does not exist** (codes never expire).

### Actions available per place
- **My Code & QR tab** (:329–390): copy the code (icon button, tooltip "Copy code"; toast `Copied personal code to clipboard!`); **Download QR** (file `Connectum_QR_<username>.png`, toast "Downloaded QR code image."); **Share Code** (device share sheet with title `Connect with <name>` and text `Connect with me on Connectum using code <XXXX-XXXX>: <url>`; falls back to copying); **Rotate Code** (tooltip "Generate a new personal code. The previous code will become invalid."; asks with a browser confirm: "Are you sure you want to rotate your personal Connectum code? Your previous code will stop working."; toast "Your personal Connectum code has been rotated.").
- **Enterprise QR tab** (:396–470): copy (tooltip "Copy enterprise code", toast `Copied enterprise code to clipboard!`); **Download Enterprise QR** (file `Connectum_Enterprise_QR[_<Branch>].png`); **Share Enterprise Code** (title `Join <org>`, text `Join <org> on Connectum using code <XXXX-XXXX>: <url>`). No rotate: the organisation's code is the organisation's Connectum ID and is fixed (`be/people/sd_connect.erl`:73 `org_code() -> sd_ent:public_id()`).
- **Profile > My QR Code** (`ProfileModal.jsx`:533–610): copy, **Download QR** (`Connectum_QR_<username>.png`), **Rotate Code**. No Share button.
- No "copy link" button exists in any of them. Print: none (only download).

## 2. Who sees which QR

- **Everyone who has the Connect button sees both tabs** "My Code & QR" and "Enterprise QR": the tab buttons are unconditional (`ConnectCodeModal.jsx`:~272–290) and `connect.my` returns the organisation card to every caller (`be/people/sd_connect.erl`:262–267, `be/core/sd_cmds_people.erl`:406–409). **So a normal member sees the organisation QR too**; this differs from the assumption in the request. The only admin-only part is the **branch picker** (below).
- **Who gets the Connect button** (`cc/components/TopBar.jsx`:50–64): employees, affiliate people and admins always; an outside person (customer, supplier) only if the administrator switched `connect` on in their allowed navigation (`currentUser.nav`).
- **Admin = `role == "admin"`** (`be/people/sd_users.erl`:162). A manager, owner, guest or a person holding custom permissions is **not** an admin here and gets no `branches` list. I found no permission that grants it. The check is **server side**: `connect.my` adds `branches` only `case sd_users:is_admin(User)` (`sd_cmds_people.erl`:408–409). The client simply shows the picker when `branches.length > 0` (`ConnectCodeModal.jsx`:~398). A non-admin who asks gets the same answer without `branches`: no error code.
- Access level of the four actions: all are plain signed-in user actions (`be/core/sd_cmds.erl`:188–189). Unauthenticated: `signin` level.

## 3. The personal QR

**Call:** `connect.my` (no parameters), `be/core/sd_cmds_people.erl`:406–409. Response (`sd_connect.erl`:262–267, 153–156):
```
{ "person": {"code":"KVZDHDQD","display":"KVZD-HDQD","payload":"https://x.example/connect/KVZDHDQD?org=7454YKKJ",
             "url":"<same, or null>","name":"Ana Fake","username":"ana"},
  "enterprise": {…card, section 4…}, "branches": [ … ]  /* admins only */ }
```
- `payload` = the text to draw. With `CONNECTUM_PUBLIC_URL` set it is `<PUBLIC_URL>/connect/<CODE>?org=<ORG CODE>` and `url` is the same string; **without** it, `payload` is `connectum:<CODE>?org=<ORG CODE>` and `url` is `null` (`sd_connect.erl`:136–143, 150–156). The share text then ends with `: ` and an empty link (`ConnectCodeModal.jsx`:~365).
- The code: 8 characters, Crockford base32 `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, 5 random bytes (`sd_connect.erl`:22, 60); stored once per person (`sd:connect:user`), created on first `connect.my`.
- **Validity:** no expiry. **Rotate:** `connect.rotate` (no parameters) → `{ "person": { …same shape…, "code": "<new>" } }` (`sd_cmds_people.erl`:410–412). The old code is deleted at once and a stale mapping resolves to `not_found` ("No one has that code.", `sd_connect.erl`:95–101). Audit entry `connect.rotate` (actor = target = the person, `sd_connect.erl`:98). No rate limit on `connect.my`/`connect.rotate`. No event is sent to other devices on rotate (section 9): another device keeps showing the old QR until it calls `connect.my` again.
- **Revoke without replacing:** does not exist (only rotate).
- **What a scanner sees:** the scanner must be signed in. `connect.lookup {code}` returns `{type:"person", connected, user:{name, username, designation, department, branch, …}}` and connects nothing; `connect.scan {code}` connects (they become associates at once; the owner gets the feed item "New connection" / "<name> connected with you by scanning your code." and the event `associate_connected {user, via:"code"}`, `sd_connect.erl`:300–312). Errors: `rate_limited` "Too many codes tried; wait a few minutes and try again.", `invalid_code` "That isn't a valid Connectum code.", `not_found` "No one has that code.", `invalid` "That's your own code.", `forbidden` (policy text from `sd_policy:may_interact`), `wrong_org` "That code is for a different organisation. Open the organisation it belongs to first." (`sd_connect.erl`:273–306, `sd_cmds_people.erl`:415+). Limit: 60 lookups+scans per 10 minutes per signed-in person (`sd_connect.erl`:126–130).
- **Not signed in:** nothing about a person is ever shown; a person's code answers like an unknown one (`sd_connect.erl`:11–12, 188–193). Details: `MOBILE_QR.md` §2.

## 4. The organisation QR and branches

**Card** (`sd_connect.erl`:196–206), also the `enterprise` part of `connect.my`:
`{code, display, payload, url, name, location (object or null), categories, setupDone}`. The code is the organisation's public Connectum ID and cannot be changed or rotated. `payload` = `<PUBLIC_URL>/connect/<ORGCODE>` (or `connectum:<ORGCODE>`).

**Branch list** (admins only): `connect.my` → `branches: [{name, city (or null), payload, url}]`, only branches whose `active` is not `false`, in the organisation's order (`sd_connect.erl`:209–219). `payload` = org payload + `?branch=<URL-encoded name>`. **Choosing a branch changes only a parameter in the link; the code is the same organisation code** (`sd_connect.erl`:205–208). There is no separate call "branch QR": the list already carries each branch's payload.

**Web branch switch** (`ConnectCodeModal.jsx`:~398–410): shown only when `branches.length > 0`. A select titled "Which QR code to show" with options **Whole organisation** (default, empty value) and `<name> · <city>` per branch. Hint under it: `People who scan it are noted as coming through <branch>.` or, with nothing chosen, `Pick a branch to show its own QR for that place.` With no branches (or a non-admin) there is no picker and the QR is the whole organisation's. There is no "default branch" beyond "Whole organisation".

**What a scanner sees on a branch QR:** `connect.lookup`/`connect.scan`/`GET /api/sd/connect/<code>?branch=..` add `branch` (the name spelled as the organisation has it) to the card; a branch that does not exist or is switched off still works as the organisation's code but adds `branchUnavailable: true` (`sd_connect.erl`:233–250). Their words in the app: "You are in <org> (<branch>)" when already a member (`ConnectCodeModal.jsx`:~629).

**What a person joining through a branch QR gets** (`be/security/sd_ident.erl`:570–670): the app sends `connectBranch` with `POST /api/sd/join`. The server (1) checks the branch is on (`branch_named`), (2) notes it on the person's record as `connectBranch` (`sd_users_memberships.erl`:363), (3) uses it as the person's `branch` only if they did not pick one **and** they are an employee, or their category keeps a branch (`sd_onboarding:scan_fills_branch`, `sd_onboarding.erl`:230–234), (4) shows it to the approver in the onboarding request data (`sd_reqs.erl`:31–34).
**Approval:** a joining person is created `pending` and `sd_onboarding:approvers/1` decides: `none` → active at once (`nextStep:"enter"`); otherwise an onboarding request goes to the approvers named by the category's rules (if the category has `routeByBranch`, to those who work in that branch; otherwise the administrators) → `status:"pending"`, `nextStep:"approval"` (`sd_ident.erl`:650–664, `sd_onboarding.erl`:253–272). An employee who enters their employee code is claimed with no approval (`sd_ident.erl`:613–630). So **whether the org QR needs approval is set in the user category's onboarding policy** (`requireApproval`, default true, `sd_onboarding.erl`:38–40), not by the QR.

## 5. Information around the QR (exact texts)

My Code & QR tab: name (heading, `connect.my` `person.name`); line "Share your personal code with colleagues or citizens. When they scan it, you instantly connect as associates."; the QR; the code as `XXXX-XXXX` (`display`). Image alt: `Connectum QR for <name>`.
Enterprise QR tab: heading = organisation name (fallback "Connectum Enterprise"); under it `<city>, <country>` from `location`, else "Official enterprise registration and onboarding QR"; the QR; the code `XXXX-XXXX`. Alt: `Enterprise QR for <name>`.
Profile > My QR Code: line "Colleagues and partners can scan this QR or enter your Connectum code to connect with you instantly."; while loading "Generating your Connectum QR…". Alt "Connectum QR".
Connect via Code tab (scan/type): heading "Connect to a Person or Enterprise"; hint "Enter any 8-character Connectum code (e.g. ABCD-1234) or scan using your camera."; bad text → "That isn't a Connectum code. It has 8 letters and digits."; confirm card `Connect with <name>?` / `@<username> • <designation> • <department>` with buttons **Not now** and **Connect** (busy: "Connecting…"); results `Connected with <name>!`, `Already connected with <name>.`, "Message Now" button; another organisation: `This is the code of <org>` / "You are signed in to a different organisation. Switch or join from the account menu at the top of the chats list, then scan it again." (`ConnectCodeModal.jsx`:~160–290, 560–680).
Not shown anywhere beside the QR: person's role, branch, designation, link text, expiry. The link itself is not displayed; it is only in the share text.

## 6. Payload, encoding and quality

- **Full pattern:** person `{PUBLIC_URL}/connect/{CODE}?org={ORGCODE}`; organisation `{PUBLIC_URL}/connect/{ORGCODE}`; organisation branch `{PUBLIC_URL}/connect/{ORGCODE}?branch={URL-encoded name}`. Without `CONNECTUM_PUBLIC_URL`: `connectum:{CODE}[?org=..]`/`[?branch=..]` (`sd_connect.erl`:136–143, 214–216).
- **Connect window (`makeQr`, `ConnectCodeModal.jsx`:25–31):** library `qrcode` (npm), **error correction M**, **quiet zone 4 modules**, each module a whole number of pixels (≥3 px, image drawn at 3x), dark `#111827` on white, shown at 200 px. Version picked automatically by the library (byte mode).
- **Important difference:** before drawing, the Connect window runs `qrText()` (:17–21): if the payload starts with `connectum:` it replaces it with `<this page's origin>/connect/<CODE upper-cased, dashes/spaces removed, URL-encoded>`. Applied to a payload that still has `?org=…` this would encode the `?`/`=` and upper-case them (not run; reading of the code), so **with PUBLIC_URL unset the personal QR drawn by the web is not the server's `payload`**. With PUBLIC_URL set the server payload is already an `https` link and is drawn unchanged.
- **Profile tab** draws `payload` as is: width 240, margin 2, library-default correction level, dark `#1e293b` (`ProfileModal.jsx`:111–115). So the same person can show two slightly different images on web (same text when PUBLIC_URL is set).
- **Sign-up screen** draws `connectum:<ID>`, margin 1, width 240, level M (`ConnectumAuthScreen.jsx`:551).
- **Landing page** (server-made SVG, no library): own implementation, byte mode, level M, versions 1–10 (≤213 bytes), lowest-penalty mask, quiet zone 3 (`sd_qr.erl`:1–6; `sd_connectpage.erl`:239).
- **Same on every device/session?** The text is a function of (public URL, org code, person code): identical on every device and session until the code is rotated. The image differs only by drawing options above.
- Mobile may draw its own image; recommended: level M, quiet zone 4, ≥200 px, dark on white.

## 7. Landing page and app links
Not repeated; see `MOBILE_QR.md` §2–3 (page, `intent://`, Play referrer, claim token, iOS clipboard). What mobile's profile card needs is only the **link text**, i.e. `payload`/`url` above.

## 8. Security and privacy
- A scan of a **person** QR by a signed-in person connects them immediately, without asking the owner; "showing your code is consent" (`sd_connect.erl`:268–271). The web asks the scanner first (lookup → confirm → scan); mobile should too.
- Before sign-in a scan reveals only the organisation card (name, location, categories, setupDone), never anything about the person (`sd_connect.erl`:189–193).
- Abuse limits: 60 `connect.lookup`+`connect.scan` per 10 min per signed-in person; landing/`GET /api/sd/connect/*` 60/min per address; claim/play 20/min per address (`MOBILE_QR.md` §4).
- Leaked or old QR: a person rotates (the old code stops at once). The **organisation** QR cannot be changed; anyone with it can reach the join form, but joining still goes through the category's approval (section 4). Branch names are not secrets.
- Audit: only `connect.rotate` is audited. A scan/connect is **not** audited (no `sd_audit` call in `scan`); it creates the feed item to the owner.

## 9. Events
No event exists for "regenerated", "revoked" or "branch changed". The only QR-related event is `associate_connected {user, via:"code"}` sent to the owner when someone scans their code (`sd_connect.erl`:307–311). After a rotate, other devices must re-call `connect.my`.

## 10. Calls mobile needs
1. **My personal QR:** `/sd connect.my {}` → draw `data.person.payload` (show `data.person.display`, `name`).
2. **Rotate:** `connect.rotate {}` → draw `data.person.payload` (new code).
3. **Org QR:** the same `connect.my` → `data.enterprise.payload` (works for any member; show `data.enterprise.name`, `display`).
4. **Branch list (admin only):** the same `connect.my` → `data.branches[]` (`name`, `city`, `payload`, `url`); absent for non-admins.
5. **Branch-specific org QR:** draw `data.branches[i].payload`; no other call.
6. Scanner side: `connect.lookup {code}` then `connect.scan {code}`; pass the whole link or code (accepted forms in `MOBILE_QR.md` §4).

## 11. Corrections to `docs/MOBILE_QR.md` (differences from the code)
1. §4 says `connect.my` returns "the signed-in person's code and the organisation's, with their `payload` strings". True, but it **omits `branches`** (admin only, `sd_cmds_people.erl`:408), the `url` field (null without PUBLIC_URL), and that the **person payload always carries `?org=`** (`sd_connect.erl`:262–264). Add them.
2. §1 table: the person example matches the code; "then `&branch={name}` if any" is **not produced by `connect.my`** for a person (only the organisation's branch payloads carry `branch`).
3. §1 and §4 should say a payload is `connectum:<CODE>…` (not https) when `CONNECTUM_PUBLIC_URL` is unset.
4. Nothing in MOBILE_QR.md says the web draws different images on the Connect window and the Profile tab, or that `qrText()` rewrites `connectum:` payloads (section 6).
5. §4 "Limits" says 60 codes per 10 minutes: correct for lookup+scan only; `connect.my`/`connect.rotate` are unlimited.
6. §3: "Saving needs the provider key…": not re-checked here.
Everything else I read in it matched the code (`org`/`branch` handling, `wrong_org`, `branchUnavailable`, rotation).

## Open questions
1. Should a normal member see the **organisation QR** in mobile? The web shows it to every member (§2). Hiding it would be a product decision.
2. Should non-admin roles with a permission (e.g. a branch manager) get the branch list? Today only `role == "admin"`.
3. Rotate has no event for other devices; add one (`connect_rotated`)?
4. Should the web's `qrText()` behaviour (rewrites `connectum:` payloads, and breaks `?org=`) be fixed? Only matters when `CONNECTUM_PUBLIC_URL` is not set.
5. Should scans be audited (privacy vs. traceability)?
6. Does mobile need print/PDF of the org QR? None exists on web.
7. Expiry or one-time personal QR (not built)?

## 12. What mobile must match versus what may differ
**Must match**
1. The QR text is exactly the server's `payload` (never rebuild it); person QR carries `?org=`; branch QR is the org code plus `?branch=<encoded name>`.
2. Codes: 8 chars Crockford base32, shown `XXXX-XXXX`; accept forgiving input.
3. Rotation semantics: old code dead at once; re-fetch `connect.my` after rotating or after any `not_found` on your own code.
4. Branch picker only when the server sent `branches`; default "Whole organisation"; exact hint texts in §1/§4 if mobile reuses them.
5. Scanner flow: lookup → confirm "Connect with <name>?" → scan; same error texts (server wording).
6. No expiry, no revoke, no org-code rotation exist: do not invent them.
7. Quality: level M, quiet zone ≥4 modules, dark on white.
8. Approval for joiners is decided server-side by the user category, never by the app.

**May differ**
9. Layout, whether the personal and organisation QR share one screen or the profile card, icons, haptics.
10. Share sheet wording (keep the link), file names of saved images, whether to offer print/download.
11. Image size and colours (any scannable dark-on-light), and drawing library.
12. Whether to show the organisation QR to non-admins (open question 1).
