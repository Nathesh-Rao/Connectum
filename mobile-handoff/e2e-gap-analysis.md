# E2E gap analysis: backend docs of 4 Nov 2026 vs this app

Read-only analysis, 4 Nov 2026. This file **replaces** the 2 Nov version (still in git history, commit 161e5e0); that one predates `E2E_WEB_COMPLETE.md` and `E2E_NEW_DEVICE_AND_HISTORY.md` and is stale in places.

Read: `reference/backend-e2e/` (`E2E_NEW_DEVICE_AND_HISTORY.md`, `E2E_WEB_COMPLETE.md`, `E2E_FRESH_DEVICES_CHANGE.md`, `e2e-test-vectors.json`), `mobile-handoff/history-sync-older-device.md`, and the app's E2E code. To settle two points the docs leave open, I also read `sd_auth.erl`, `sd_ident.erl` and `sd_e2e.erl` on `origin/main` of the backend (commit f813bd5b, nothing checked out). No Dart was changed, nothing was run on a device, nothing was sent to a server. I did **not** run `/debug/e2e`, so "runs there" below means "the code is wired to it", not "I saw it pass".

App state is the `master` working tree, which has uncommitted E2E changes (`e2e_repository.dart`, `encryption_policy.dart`, `message_repository.dart`, `session_repository.dart`, `auth_repository.dart`, `socket_service.dart`). `reference/backend-e2e/` itself is untracked.

Status words: **done** (matches the docs), **partial**, **missing**, **different** (works, but not as the docs/web do; says whether that is safe).

Short names: `crypto` = `lib/data/e2e/e2e_crypto.dart`, `repo` = `lib/data/repositories/e2e_repository.dart`, `policy` = `lib/data/repositories/encryption_policy.dart`, `msgrepo` = `lib/data/repositories/message_repository.dart`, `sess` = `lib/data/repositories/session_repository.dart`.

---

## 0. The short version

1. **Crypto and the send/read path are solid.** Every bound string, the envelope, padding, the box `ek`, the all-devices rule and the `e2e_stale_devices` retry match the docs. Groups can already be sent and read.
2. **The phone never says `"client":"mobile"` at sign-in.** So it sits in the *web* session slot. Signing in on the web today signs the phone out, and the phone then **wipes its cached rows and its unsent outbox**. This is the most urgent finding (section 1) and a one-line-per-endpoint fix.
3. **History sync is only half built.** The new-device (waiting) side works. The older-device side (offer, approve, rewrap, `put`, `done`) does not exist, and neither does any rewrap function in `crypto`.
4. **Recovery code does not exist** (no generate, seal, open, `e2e.recovery.*`, backup or restore). The Security screen says so honestly, but `security_controller.dart:66` still points the person at a recovery code the phone cannot use.
5. **Smaller gaps:** `e2e.status` is sent without the device id; the read path never checks key pins; one generic placeholder instead of nine; `/debug/e2e` runs none of the backend's `rewrap`, `recovery` or `envelope` vectors; a send-heavy phone can hit the 600/10 min limit of `e2e.devices`.

---

## 1. Does sign-in send `"client":"mobile"`?

**No: missing.**

| Where | What the app sends | File:line |
|---|---|---|
| `POST /login/verify` (identity session) | `{email, otp, deviceId}` | `auth_repository.dart:101-105` |
| `POST /enter` (the enterprise session, the one that has a slot) | `{enterprise, deviceId}` | `lib/data/api/api_client.dart:139-147` |
| `POST /setup/verify` | `{email, otp, deviceId}` | `auth_repository.dart:134-137` |
| `grep "client"` over `lib/` | no hit that is a sign-in field | |

The backend reads `client` only where it creates an enterprise session: `sd_ident.erl:361` (`enter_as`) and `:649` (setup), via `client(Body)` at `:273`. `sd_auth.erl:148-154`: `mobile` / `android` / `ios` give the mobile slot, **anything else or nothing gives `web`**. `mobile-handoff/sessions.md` does not mention the field at all.

**What happens today when one person signs in on the web and on the phone** (verified in `sd_auth.erl:117-182`):

1. Both sessions land in the one `web` slot (`slot_key/2`, `sd:usersess:<user>`).
2. The second sign-in deletes the first session. Its live socket gets `sd_event session_replaced` (`replaced_kind` is `web`).
3. If the phone is the one replaced: `socket_service.dart:242` → `SocketState.sessionReplaced` → `sess:58` → `handleSessionReplaced` (`sess:136-149`) → `_db.wipeScope` (`app_database.dart:273`), which deletes every cached row **and the outbox**, then goes to login with "You were signed out because this account signed in on another tab or device." Unsent messages are lost.
4. Signing in on the phone again kicks the web out the same way (the web forces a sign-out, `E2E_WEB_COMPLETE.md` H). Each device keeps ending the other's session.
5. The server also writes a `session_replaced` feed item each time, and never the `session_added` item (that one only fires for two different kinds).
6. It breaks the history-sync design: an older phone cannot stay signed in while the person signs in on the web to be the new device. This is exactly the "signing in there signs you out here" story of `E2E_NEW_DEVICE_AND_HISTORY.md` D3, but it applies to phone + laptop only because of this bug.

Needed: add `"client":"mobile"` to the body of `/enter` and `/setup/verify` (the two session-creating calls). A phone that is already signed in keeps its web-slot session until its next sign-in.

---

## 2. How `session_replaced` is handled, given per-client slots

| Aspect | Docs | App | Status |
|---|---|---|---|
| Event handled | `sd_event session_replaced`, then close `signed_in_elsewhere` | `socket_service.dart:242-243` → `sess:57-58` | done |
| Device keys survive | "Do not delete device keys when a session ends" (`E2E_NEW_DEVICE_AND_HISTORY.md` §9.1) | `handleSessionReplaced` never touches `E2eKeyStore`; pins and the late mark survive (`app_database.dart:273`, `session_store.dart:61-67`, `e2e_repository.dart:312-315`) | done |
| Rows and outbox | web keeps its local state; the docs say nothing about a phone cache | wiped for that org and user (`sess:141`), per `CLAUDE.md` | different, deliberate. Safe for secrets (the `plaintext` column goes), but unsent messages are lost |
| Offline client | "finds out on its next request" (`sd_auth.erl:156`) | a 401 or handshake failure goes to `handleAuthFailed` (`sess:153-159`): token cleared, rows and outbox **kept** | done |
| Takeover by the same session | `connection_superseded` is a different event | `sess:61` → `supersededNotice` | done |
| Fires only for the same kind | yes, once `client` is sent | today it fires for any other device (section 1) | **broken until `client:"mobile"` is sent** |

After the fix, `session_replaced` happens for a second **phone**, or when the server runs `CONNECTUM_SESSION_SLOTS=1`. The `replacedNotice` text ("another tab or device") then still reads fine.

---

## 3. `e2e.sync.put`: who may write, and does our flow match

Server rule (`sd_e2e.erl:566-590`, `E2E_NEW_DEVICE_AND_HISTORY.md` D1): `put` is accepted only for a target that is `waiting` (late and not yet `done`), or the person's **only** non-recovery device, or a recovery key that is not backed up yet. Anything else is `not_waiting`.

| Flow | What the app does | Match |
|---|---|---|
| New device waiting | Reads `late` from `e2e.status` (`repo:332-354`), keeps a local mark across restarts (`repo:305-317`), polls `e2e.status` + `e2e.sync.pending` every 60 s in the foreground (`repo:45`, `:363-392`), shows who can help (`repo:386`, `security_controller.dart:59-71`). It never calls `put`, which is correct: the *older* device writes. | done (web polls every 30 s; free to differ) |
| After the older device finishes | `late` turns false → `unlockRequests` → `_unlockLocked` refetches the locked conversations once, newest first (`msgrepo:144-215`, `repo:358`) | done |
| Older-device hand-on | No `pending.waiting` read, no offer, no `page`/`put`/`done`, no rewrap in `crypto` (the only caller of `e2e.sync.*` is `refreshPending`, `repo:385`) | **missing** |
| Only device after loss (restore by recovery code) | not built | missing |

What the future hand-on must respect, from the server rules:

- Only put for a device listed in `pending.waiting`, and look the target's key up fresh (`e2e.devices {users:[me]}`) right before the first `put`.
- `not_waiting` on a `put` is not an error: another device finished. Stop quietly.
- Recovery key as a target is allowed only while `backedUp` is false.
- A retry after `done` is refused (`not_waiting`) unless the target is the only device. A restore must therefore call `done` **last** (question B5).
- `waiting` and `helpers` list only devices seen or added in the last 30 days, and "seen" is only recorded when `e2e.status` carries the device id (`sd_e2e.erl:558-563`). See the gap in section 6.

---

## 4. `e2e.sync.approved`

Server (`sd_e2e.erl:374-379`, `:642-656`): writes `approvedTs` on the target and an audit event `e2e.history_approved`; `not_waiting` if the target is not waiting; 60 per 10 min. It is a record, not a lock: any signed-in device could do the job without it. The web never calls it (`E2E_NEW_DEVICE_AND_HISTORY.md` D4, Q6, which recommends both clients call it).

- **Do we call it?** No. We have no approve step yet.
- **Should we?** Yes, when the approve step is built: one call right after the person taps Approve and before the first `put`. Treat any error as non-fatal (log, continue). It costs nothing and gives the owner an audit trail the web does not give. Confirm with the backend that nothing else reads `approvedTs` (question B6).

---

## 5. What the app deletes, and is it safe

| Event | Local rows + outbox | Device keys (`E2eKeyStore`) | Pins | Late mark / status | Server registry | Web does | Verdict |
|---|---|---|---|---|---|---|---|
| Explicit sign out (`sess:161-177`) | wiped for that org+user | **kept** (`e2e_key_store.dart:10-11`) | kept | kept | device stays | keys kept (`ConnectumAuthScreen.jsx:234-237`) | same as web; safe |
| Log out of the account (`sess:190-217`) | wiped, every org (`app_database.dart:252`) | kept | kept | kept | stays | n/a | safe. The logout sheet tells the person (`logout_sheet.dart:22`) |
| `session_replaced` (`sess:136`) | wiped for that org+user | kept | kept | kept | stays | forced sign-out, keys kept | keys safe; unsent messages lost (section 2) |
| Handshake error / expired token (`sess:153`) | **kept** | kept | kept | kept | stays | n/a | per `CLAUDE.md` |
| "Remove this device" (`repo:916-938`, `:821-834`) | unchanged | **deleted** after `e2e.remove` succeeds (a failure other than `not_found` keeps them) | kept | state set to `out` so nothing re-registers | device deleted | same (`Client:131-136`) | same as web; safe. Pins stay, harmless |
| This phone found removed from another device (`repo:672-675`) | unchanged | **kept**, asks the person (`removed` phase) | kept | | already gone | deletes its keys and registers anew (`Client:58-61`) | different. The old keys are inert (the server no longer lists them, so nobody wraps for them); asking first is safe and arguably kinder |
| App uninstall | gone | **Android: gone** with app data (backups excluded). **iOS: Keychain survives** a reinstall (`first_unlock_this_device`) | gone (SQLite) | | stays as a dead device for 30 days | same as "clear site data" | functionally fine; on Android an orphan device occupies one of the 10 slots and senders keep wrapping for it |

Findings:

- **Safe:** nothing deletes a key except an explicit remove, as the docs require ("do not delete device keys when a session ends").
- **Residual risk, shared with the web:** a signed-out phone still holds working device keys (D5, §8 of the new-device doc). The decrypted `plaintext` column is wiped with the rows on sign out; the keys are not.
- **Not handled:** no UI for the Android orphan-device case, and no "remove this device" prompt at sign out. Same gap as the web (L2 #7).

---

## 6. Checklist: "What mobile must implement" (`E2E_NEW_DEVICE_AND_HISTORY.md` §9)

| # | Item | Status | Evidence | What is needed |
|---|---|---|---|---|
| 1 | Keys, 32-hex device id, secure store, keep them when a session ends | **done** | `crypto:67-77`, `:60-61`; `e2e_key_store.dart:15-59` (Keystore/Keychain, PKCS#8) | nothing. Private keys are exportable inside the app process (web: non-extractable); allowed ("where keys live may differ") |
| 2 | Register with proof; handle `limit`, `rate_limited`, `conflict`, `invalid`; send `e2e.status {id}` at every start | **partial** | register: `repo:701-793`; `limit` → `limit` phase `:764`; `rate_limited` → backoff 1→30 min `:756-762`; any other code → `refused` with reason `:769`. **`e2e.status` is sent with `{}`** (`repo:227`, `policy:347`) | send `{id: <own id>}` at every start. Without it the server never records "last seen" (`sd_e2e.erl:89-106`), so this phone leaves `helpers` and `waiting` 30 days after it registered. Show `conflict` and `invalid` in words |
| 3 | Read an envelope, including a box with its own `ek` | **done** | `crypto:394-485`, box `ek` at `:449`; wired to `lateBox` on `/debug/e2e` (`debug_e2e_controller.dart:411`) | see the pin gap below |
| 4 | Send wrapped for every device that exists now; resend on `e2e_stale_devices` by `mid`, at most twice | **done** | forced lookup per send `policy:268`, `:314`; retry `msgrepo:1441-1480` (`_maxStaleRetries = 2` at `:63`), match by `mid`, new envelope, same `cid`, silent | verify on a real second device (`E2E_FRESH_DEVICES_CHANGE.md` "After the mobile release" steps 1-2). Rate-limit risk: `e2e.devices` is 600 per 10 min and the outbox allows 30 sends per 10 s (question B3) |
| 5a | New-device waiting card, helper names, poll, "enter recovery code" if recovery is on | **partial** | `LateNotice` + `security_controller.dart:53-71`; home notice `home_shell_controller.dart:84-96` | the recovery-code action is missing, and the copy at `:66` promises a code the phone cannot use |
| 5b | Approve card on an older device (Approve / That is not me / Later) | **missing** | no read of `pending.waiting` | build |
| 5c | Sync progress, Stop, failed + Try again, empty history still ends with `done` | **missing** | | build with the job |
| 5d | Placeholders for unreadable messages in the phone's own words | **partial** | one text for every failure: "This message can't be read on this device" (`message_bubble.dart:189`); the failure code is kept in the repo (`repo:1010-1013`) but not shown | per-code texts (section 10) |
| 6 | Hand-on job: pending → (approved) → devices → page → rewrap → put ≤400 → done | **missing** | | rewrap in `crypto` + job + UI |
| 7 | After the older device finishes: refetch once, remember "was waiting" across restart | **done** | `repo:305-361`, `msgrepo:144-215` | verify against a real hand-on once item 6 exists |
| 8 | Send `"client":"mobile"` at sign-in | **missing** | section 1 | add |
| 9 | Recovery (generate, seal, `recovery.set`, show once, backup, restore, new code, turn off) | **missing** | section 7 | build |
| 10 | Alerts: "added a new device" notice for contacts; key-changed warning | **partial** | key-changed is shown, but only when a **send** finds a pinned key changed (`policy:132-141`, `key_change_sheet.dart`). No notice for a known contact's new device. `FeedRepository` only counts unread (`feed.summary`); no feed list shows the "A new device was added" item | see "pins" below |

**The pin gap (also item 11 of the "must match" list).** The web checks the sender's keys on **read**: an unknown or changed sender device is refused with a placeholder and an `e2e_key_changed` toast (`Client:362-371`). The app pins and compares only when it **sends** (`checkPins` is called at `policy:290` and `:330`, and by the key-review sheet `repo:529`). On read, `E2eRepository.open` takes the sender's signing key from the directory with no pin check (`repo:971-990`). A server that swapped a sender device's signing key would be accepted on read. The signature stops forgery by anyone *without* that key, not by the server, which holds the directory. Needed: pin on read, refuse a mismatch with a "key changed" placeholder.

---

## 7. Recovery code

| Part | In the app | Missing | Vector |
|---|---|---|---|
| Recovery key shown in lists | `E2eDevicePublic.isRecovery` (`e2e_models.dart:21`); `repo:298` | | |
| Wrapped for on every send | yes: recipients are every device in the list, recovery key included (`policy:143`, `:215`); `readers()` excludes it from "has a reader" (`repo:395`) | | `/debug/e2e` "send: a recovery key in the list is wrapped for" (`debug_e2e_controller.dart:950`) |
| Shown in Security | read-only "Recovery key: On/Off" (`security_view.dart:76`, `repo:232`) and an honest line that the phone cannot use it (`security_view.dart:140`) | | |
| Code: 26 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 130 bits, groups of five, normalise (capitals, strip dashes and spaces), `bad_code` | | all of it | `recovery.normalizedCode`, `normalizing`, `mustRefuse` (too short, letters 0/1/I/O) |
| Seal / open: HKDF-SHA-256 (ikm = 26 chars, random 16-byte salt, info `connectum-e2e-recovery|<user lower>|<id>`), AES-256-GCM 12-byte iv, AAD `e2e1-recovery|<user>|<id>`, blob `{v:1,salt,iv,ct}`, plaintext `{e,s}` = base64url PKCS#8 of the ECDH and ECDSA private keys | | all of it | `recovery.blob`, `info`, `aad`, `plaintext`, `mustRefuse` (wrong code, other user, other id, changed ct, other salt → `wrong_code`) |
| Recovery key pair (extractable ECDH + ECDSA), registration-style proof, random id | | all | none (random). Check the proof with the `registration` vector shape |
| `e2e.recovery.set {id,ecdh,sign,proof,blob,replace?}` (10/h), `.get` (30/h), `.delete` | none; no `e2e.recovery.*` call in `lib/` | all | `/sd` reply shapes in the backend's `e2e-sync-replies.json` (not in `reference/backend-e2e/`) |
| Backup of the past (rewrap with the recovery key as target, `done` marks `backedUp`) | | all, on top of the rewrap | `rewrap` |
| Restore on a new phone: `recovery.get` → open → rewrap with source = recovery key, target = this device → `done`; `nothing_restored` if messages exist but none opens | | all | `rewrap` and `recovery` |
| UI: show once + copy + "I have saved it"; verify step (web has none, Q5); turn off; replace; suggestion after a day | | all | none |
| `pending.recovery {id, backedUp}` | ignored (`repo:385-387` reads only `helpers`) | read it | |

Vectors needed, in order: `recovery` (open direction, deterministic), then `rewrap` (positive and negative). Sealing uses a random salt and iv, so it can only be tested as seal-then-open plus "the backend checker accepts what the phone made". No vector exists for restore with the recovery key as the *source* of a rewrap; the `rewrap` vector has an older device as source only (question B8).

---

## 8. Constants: AAD, HKDF, envelope, sizes, rate limits

| Item | Docs | App | Status |
|---|---|---|---|
| Prefix, `v` | `e2e1:`, `v:1` (`Crypto:18`) | `crypto:14-15` | done |
| Message AAD | `e2e1-msg\|mid\|conv\|from\|dev` | `crypto:209-210` | done |
| Wrap AAD | `e2e1-wrap\|mid\|recipientDev` | `crypto:212-213` | done |
| File AAD | `e2e1-file` | `crypto:215` | done |
| Wrap key | HKDF-SHA-256, salt = decoded `mid`, info `connectum-e2e-wrap\|recipientDev\|senderDev` | `crypto:228-242` (info uses the ORIGINAL sender `e.dev` when reading: `:451`) | done |
| Signature text | `e2e1\|mid\|from\|dev\|conv\|ts\|ek\|iv\|ct`, ECDSA P-256/SHA-256, raw r‖s (64 bytes) | `crypto:217-226`, `:305-321`; verify `:152-163` | done |
| Registration proof | `connectum-e2e-register\|user\|id\|ecdh\|sign` | `crypto:129-149` | done |
| Padding | 4-byte big-endian length + bytes, zero-padded to a multiple of 64; payload `{"v":1,"t":text}` | `crypto:16`, `:186-207`, `:263` | done |
| Reader order | conv check → own box → sender key → verify signature → derive | `crypto:400-436` | done |
| Box `ek` | use the box's own when present | `crypto:449` | done |
| Encodings | base64url, no padding, strict decode; 65-byte uncompressed points; 32-hex device id; 16-byte `mid` (22 chars) | `crypto:23-35`, `:111-125`, `:60-63` | done |
| DM label | `dm:` + both names lower-cased, sorted, `\|` | `crypto:53-56` | done |
| Group label | `group:` + lower-case name | `crypto:58` and `repo:949` also `.trim()` | **different (small).** Web only lower-cases. A group name with leading or trailing space would label differently (question B7) |
| Boxes per envelope | ≤ 250 | `policy:231`, `:218` (blocked, never plain) | done |
| Envelope length | ≤ 120,000 chars, else `too_long` | server code handled `msgrepo:1412`, `:1433`; length checked only in `/debug/e2e` (`debug_e2e_controller.dart:923`) | partial; fine |
| `e2e.devices` | 1-50 names, 600 calls / 10 min | forced per send, no throttle | **risk** (B3) |
| `e2e.register` | 30 / hour | backoff 1 → 30 min on `rate_limited` | done |
| Max devices | 10, server count excludes the recovery key | `repo:714` uses `myDevices` (recovery key excluded) | done (the web counts it by mistake, Q3 of the new-device doc; we do not) |
| Label | cleaned, ≤ 60 chars | `repo:44`, `:884-891` | done |
| Directory cache | 5 min for reading, fresh for sending | `repo:43`, `:404-434`, `policy:268` | done |
| Stale retries | ≤ 2, silent | `msgrepo:63` | done |
| `e2e.sync.put` batch | client 400, server 1-500 | no sync code | missing (constant to add: 400) |
| `e2e.sync.page` | ~400 messages per page, 600 calls / 10 min | | missing |
| `e2e.sync.put` limit | 400 calls / 10 min | | missing |
| `e2e.sync.approved` | 60 / 10 min | | missing |
| Recovery limits | set 10/h, get 30/h, blob salt ≤ 64, iv ≤ 32, ct ≤ 4096 chars | | missing |
| Upload blob type | `application/x-connectum-e2e`, `.e2e`, blob = ciphertext ‖ 16-byte tag, no iv or key inside | `attachment_repository.dart:94-95`, `crypto:489-516` | done (blob file name is `attachment.e2e`, the server picks the stored name anyway) |
| Poll intervals | web 30 s while late | 60 s, 2 s event debounce (`repo:45-46`) | different, allowed |

Not in the docs, and I could not match: the web's `fresh: true` lookup applies to DMs; for groups we ask `e2e.group_devices` at each send (`policy:314`), which is the same idea.

---

## 9. Test vectors

`/debug/e2e` loads **`mobile-handoff/e2e-vectors.json`** (`debug_e2e_controller.dart:35`, our file from 29 Oct, made by us from the web code), not `reference/backend-e2e/e2e-test-vectors.json`. The two files have different sections. I compared the `lateBox` sections with a script: **identical**.

| Section in `reference/backend-e2e/e2e-test-vectors.json` | Runs on `/debug/e2e`? | Detail |
|---|---|---|
| `lateBox` (+ `intermediates`) | **yes** | same envelope and device as our file; checks ek present, opens with the box `ek`, wrap key matches (`:454-470`), 4 tamper cases |
| `recipient` / `sender` (`reference-ann` / `reference-bob`, with private scalars) | no | our file uses its own fixed `alice` / `bob` / `carol` keys |
| `envelope` + `expected` (a real ann → bob envelope with expected plaintext) | **no** | it is the same envelope as in `lateBox`; the ordinary (first-box) path is covered by our own `envelopes` section, not by this one |
| `registration` (proof for `reference-bob`) | no | our own `registration` is checked (`:537-559`) |
| `rewrap` (2 positive, 7 negative) | **no, and nothing to run it against** | needs the missing rewrap function |
| `recovery` (open + 7 `mustRefuse`) | **no, same reason** | needs the missing recovery code |

| Section in our `mobile-handoff/e2e-vectors.json` | Backend file has it? | Runs |
|---|---|---|
| `devices`, `envelopes` (4: two-device DM, unicode, 64-byte padding edge, **group "design"**), `negative` (6) | no | yes (`:217`, `:248`, `:362`) |
| `file`, `base64url` | no | yes (`:578`, `:770`) |
| `safetyNumber`, `deviceFingerprint` | **no** | yes (`:746`, `:761`) |
| padding (`paddingNote` + the 64-byte edge cases) | **no** | yes |
| `assets/debug/e2e-attachment-vectors.json` (4 files + 8 refusals) | the backend's copy is not in `reference/backend-e2e/`, so I cannot compare it | yes (`:686-718`) |

So the three things the web doc lists as "missing on the backend" (group envelope, safety number, padding frame) are **covered by our own file**, produced by running the web code, but the backend has not published them; the same goes for the device fingerprint and base64url cases. Still missing everywhere: edit of an envelope, group label with upper case / spaces / non-ASCII, a group late-box with signature check, restore with the recovery key as source. We should ask the backend to publish ours as theirs, so a future change on either side shows up (question B8).

---

## 10. User-facing E2E texts

Web text from `E2E_WEB_COMPLETE.md` §I and `E2E_NEW_DEVICE_AND_HISTORY.md` §3 and §7.2.

| Web text | App | Status |
|---|---|---|
| Header lock "End-to-end encrypted. Click to verify." | a lock icon with a screen-reader label "End-to-end encrypted" (`conversation_header.dart:66-72`); not tappable; no safety-number screen | partial |
| "Not end-to-end encrypted: the server has to read this chat." (global, host, workspace) | none | missing |
| Dialog "End-to-end encryption / Only you and the people in the chat can read…" and the "Locked on your device before it is sent…" banner | none; Security row "Secure messaging" (`security_view.dart:72`) | missing |
| "Encryption could not start on this device: {reason}" | "Couldn't set up secure messaging" + reason (`security_sheets.dart:26`) | same meaning |
| Key changed: "@x's security key changed… Compare the safety number…" + button "I checked, trust the new key" | "Security key changed" sheet, same advice, button "Trust new key" (`key_change_sheet.dart:34-72`) | same meaning. The "new key is now trusted" follow-up is missing |
| Safety number "Safety number with @x / If you both see the same number, nobody has swapped the keys." | number only inside the key-changed sheet, no explanation line, not reachable on its own | partial |
| Devices: "Your devices n", "This device / Signed in elsewhere", "Remove" | "My devices", `DeviceRow` marks this phone, "Remove this device?" (`security_view.dart:62`, `security_sheets.dart:38`) | same meaning |
| "This device was removed. Sign in again to set it up." | "This phone was removed from your encryption devices" (`security_sheets.dart:25`) | same meaning |
| Limit of 10 devices | "You've reached the limit of N devices… Remove one…" (`security_sheets.dart:59`) | same meaning |
| Recovery: off / code shown / progress / done / failed / turn off / "Enter recovery code" / backup suggestion | none | missing |
| Security line about recovery | "This phone can't use a recovery key yet…" (`security_view.dart:140`) | true today; **must change when recovery ships** |
| Waiting: "Your earlier messages are not shown here yet" + helper names | "Waiting for your other device to show your earlier messages" + "Can show them: …" (`security_controller.dart:53-71`), home notice "Earlier messages aren't shown yet" (`home_shell_controller.dart:86-96`) | same meaning |
| Waiting, no helper active: "…use your recovery code" | "None of your other devices was active recently. If you set up a recovery code, you can use it…" (`security_controller.dart:66`) | **different, misleading**: the phone cannot use a code |
| Approve card, progress, "All set", "Could not finish" | none | missing |
| Placeholder `not_for_this_device` (long, mentions approve / recovery) | "This message can't be read on this device" | differ (generic) |
| Placeholders `key_changed`, `bad_signature`, `no_device`, `unknown_sender_device`, `decrypt_failed`, `wrong_conversation`, `bad_payload`, fallback (8 more) | the same one generic text; pending shows "Decrypting..." (`message_bubble.dart:189`) | differ. The web advice ("Approve this device on another…", "Check the safety number…") is lost. Wording for a phone, never "browser", as the doc asks |
| Toast "@x added a new device ({labels})… check the safety number" | none | missing |
| Toast key changed on read | none (send-time block only: "x's security key changed", `policy:136`) | partial (see pins) |
| Send failures: "{names} has/have not set up encryption yet." | "{peer} hasn't set up encryption yet" / "a, b haven't…" (`msgrepo:1430-1431`, `:1493-1494`; `policy:122`, `:192`) | same meaning |
| `e2e_disabled`, `too_long`, other refusals | own wording (`msgrepo:1432-1435`) | same meaning |
| `e2e_required` ("Messages here are end-to-end encrypted. Update your app…") | falls to "Can't send securely right now: the server didn't accept the encrypted message" | differ (less specific) |
| Group over 200: "Groups of more than 200 people cannot use end-to-end encryption yet." | "groups of more than 200 people can't be encrypted yet" (`policy:320`) | same meaning |
| Stale devices exhausted | "Not sent. Tap to retry" (`staleFailure`, `e2e_models.dart:208`) | acceptable |
| "🔒 Decrypting attachment…" | not checked (attachment bubble not read) | unknown |
| "Encrypted message" in pinned / saved / previews | chat list preview "Encrypted message" (`conversation_tile.dart:203`); pinned and saved lists not built | partial |
| Feed "A new device was added to your encrypted messages" | no feed list screen | missing |
| Org-level notice "Secure messaging is on in this organisation…" | app-only text (`repo:87-90`); the web has none | app-only |

---

## 11. Other differences worth a decision

| Topic | Web / docs | App | Verdict |
|---|---|---|---|
| **Group over 200 members** (check 6) | `e2e.group_devices` returns `limit`; the web refuses to send at all, not even plain, in any mode but `off` (`Client:299`, `Socket:418-423`). Probably unintended (Q2 of both docs) | blocked, never plain: "groups of more than 200 people can't be encrypted yet" (`policy:317-322`); more than 250 boxes also blocked (`:218-223`) | **same as the web**, and safe. If the backend later allows plain here, only `policy:317` changes |
| Group send and read | supported | send and read both built (`policy:159`, `repo:595`, `open` via group list `repo:976`). `CLAUDE.md` still says "encrypted groups stay read-only" | `CLAUDE.md` is out of date; the web group messages wrapped for a registered phone are readable |
| Optional mode, peer has no device | web sends **plain**, regardless of history (`Client:348-352`) | plain only on a thread with no encrypted history; otherwise blocked (`policy:120-125`, `:189-196`) | different, stricter; safe |
| Edit in an encrypted chat | allowed, new envelope with a new `mid`; plain → encrypted edit allowed, the reverse refused (`e2e_required`) | blocked: "Editing isn't supported in encrypted chats yet" (`msgrepo:762-767`) | different (missing feature) |
| `#`, `@`, commands in encrypted threads | | blocked (`msgrepo:757-761`, per `CLAUDE.md`) | different, stricter |
| Reactions, delete, reply link, pin, save | not encrypted (server sees ids) | not touched by this analysis; replies and sends go through the same seal path | not checked in detail |
| Forward prefix `↪ [Forwarded by …]` | needed only if forwarding exists | no forward feature (no hit in `lib/`) | n/a |
| Attachments, upload failure | web falls back to a `data:` link; mobile should show an error | error, blocked pairing of plain file in encrypted send and the reverse (`msgrepo:750-755`) | done |
| Unreadable edited / deleted messages | | not checked | |

---

## 12. Prioritised build plan (one line per future prompt)

Each line names what it needs from the backend or which vector.

**P0, small, no backend answer needed (can run now)**

1. **Send `"client":"mobile"`** on `/enter` and `/setup/verify`; update `mobile-handoff/sessions.md`. Removes the web-kicks-phone-and-wipes-outbox bug. Needs: confirmation B1 that those are the only session-creating calls (I found two in `sd_ident.erl`).
2. **`e2e.status {id}`** at every call (`repo:227`, `policy:347`). Needs: nothing.
3. **Pin on read:** check and pin the sender's device keys when opening, refuse a changed key with a "key changed" placeholder, and add the one-time "contact added a new device" notice (`E2E_WEB_COMPLETE.md` §C). Needs: nothing (rules in `Client:305-371`).
4. **Per-code placeholders and copy fixes:** the nine texts in phone wording; fix `security_controller.dart:66` so it does not promise a recovery code; update `CLAUDE.md` (groups are not read-only). Needs: nothing.
5. **Throttle `e2e.devices` at send:** one list per peer per few seconds, still fresh for the stale retry. Needs: answer B3 first.

**P1, history sync**

6. **Rewrap in `crypto`** (unwrap own box with its `ek`, fresh one-time pair, new box with the waiting device id) plus the `rewrap` vector on `/debug/e2e` (2 positive, 7 negative). Needs: vector `rewrap` (present). No backend answer.
7. **Older-device offer and Approve / That is not me / Later** (reads `pending.waiting`, fresh target lookup, `e2e.remove` after a second confirmation, calls `e2e.sync.approved`). Needs: B6.
8. **Hand-on job:** page → skip boxes the target already has → `put` ≤400 → `done`, progress, Stop, `not_waiting` = stop quietly, back off on `rate_limited`, empty history still ends with `done`. Needs: B4 (own SQLite envelopes or `sync.page`), B5 (batch size).
9. **Two-device test with the stand-in new device** (`tools/e2e-kit/new-device.mjs`, `E2E_HISTORY_SYNC_MOBILE.md`) and the real phone + web run from `E2E_FRESH_DEVICES_CHANGE.md` "After the mobile release". Needs: P0-1 first (otherwise the web sign-in ends the phone's session).

**P2, recovery**

10. **Recovery crypto:** code generate/normalise, seal, open, PKCS#8 import as non-extractable, against the `recovery` vector (open + 7 refusals) on `/debug/e2e`. Needs: vector `recovery` (present); B8.
11. **Recovery on / change / off** (`e2e.recovery.set|delete`, show the code once, copy, "I have saved it", a verify-the-code step the web lacks). Needs: B9.
12. **Backup of the past** (item 8's job with the recovery key as target, `backedUp`, "Back up now"). Needs: nothing beyond 8.
13. **Restore on a new phone** (`recovery.get` → open → rewrap source = recovery, target = this device → `done`, `nothing_restored`, refetch). Needs: B5, a source-is-recovery rewrap vector (B8).

**P3, later**

14. **Safety-number screen and lock sheet** reachable from the header; the "not end-to-end encrypted" tooltip for global / host / workspace.
15. **Edits in encrypted chats** (new envelope, new `mid`); decide `@` / `#` rules. Needs: B10.
16. **Security feed list** with "A new device was added…". Needs: the `feed.list` shape from the mobile Postman collection.

---

## 13. Questions for the backend

B1. **Which endpoints read `client`?** I found `sd_ident.erl:361` (`enter_as`, i.e. `/enter`) and `:649` (setup). Are there others (a password login that creates an enterprise session)? Is `mobile` the value you want (`android` and `ios` also work)?

B2. **Slots:** after the fix, does a phone connection get `session_replaced` only when another phone signs in (`replaced_kind`), and is `session_added` the feed item the phone should show when the laptop signs in?

B3. **`e2e.devices` rate** (600 / 10 min per person) against sends: the outbox can send 30 messages per 10 s, and we force a lookup per send. Is a lookup shared across conversations (so a 10-second reuse is fine, as `E2E_MOBILE_REVIEW.md` once said), or must it be fresh for every message as `E2E_FRESH_DEVICES_CHANGE.md` says? Please give one rule.

B4. **Restore and `done`:** if a restore is interrupted after some `put` calls, a retry is `not_waiting` only after `done`. Confirm that a device stays writable until `done`, and that calling `done` with `nothing_restored` is wrong. What should a phone do if `put` says `not_waiting` mid-restore?

B5. **Batch size:** the client sends 400 per `put`, the server accepts 500. Is 400 a recommendation or a rule? Is the 400 calls / 10 min budget shared between backup, hand-on and restore? Does `sync.page` include conversations the phone never opened? (`E2E_NEW_DEVICE_AND_HISTORY.md` §3.2 says it walks every conversation; please confirm for a phone that holds only some of them.)

B6. **`e2e.sync.approved`:** nothing else reads `approvedTs` or the audit event? Is it safe for the phone to call it and ignore errors?

B7. **Group label normalisation:** `Socket:23` and `Server` should agree on trimming and on case-folding non-ASCII names. Is a trailing space possible in a group name? Please publish a vector with an upper-case, spaced and non-ASCII name.

B8. **Vectors we ask you to publish:** a group envelope, the safety number, the device fingerprint, the padding edge (60 vs 64 bytes), an edit of an envelope, a rewrap with the recovery key as the source and the waiting device as target, and the current `e2e-attachment-vectors.json`. Our `mobile-handoff/e2e-vectors.json` has the first four from running the web code; a backend-owned copy would stop the two drifting.

B9. **Recovery:** is `recovery.set` with `replace:true` atomic (the old key stays until the new one is accepted)? What exactly does `e2e.sync.pending.recovery` return for a key made before #607? Is there any lockout on `recovery.get` other than 30 per hour?

B10. **Edits and commands in encrypted chats:** the web edits as a new envelope. Do you want the phone to do the same, and is `#` / `@` meant to be encrypted or refused in a DM?

B11. **Optional mode, peer without a device:** the web sends plain even on a thread with encrypted history. We block instead. Is blocking acceptable, or should the phone follow the web?

B12. **Envelope near the 120,000-character cap:** still untested over the socket for large envelopes (carried over from the 2 Nov questions). Do you want a result from us?
