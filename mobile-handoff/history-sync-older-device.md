# History sync, older-device side (and the new-device re-fetch)

Read-only study, 3 Nov 2026. Nothing was built, sent to a server or run on a phone. Backend and web were read on `origin/main` of `~/Development/Axi-apps/connectum` (fetched, nothing checked out; paths below are relative to its `connectum/` folder). The app was read at the `master` working tree (uncommitted E2E work included).

Sources read in full: `E2E_HISTORY_SYNC_MOBILE.md`, `E2E_MOBILE_REVIEW.md`, `E2E_ENCRYPTION.md` (6a, "For every client", "History for a new device", "Alerts"), `json/e2e-test-vectors.json` (`lateBox`, `rewrap`), `json/e2e-sync-replies.json`, web `E2ESyncPrompt.jsx`, `e2eClient.js`, `e2eCrypto.js`, `connectumSocket.js`, `sd_e2e.erl`, `tools/e2e-kit/e2e-rewrap.mjs` and `new-device.mjs`. As a local check (nothing in the repo touched) I copied `e2e-rewrap.mjs`, `e2e-check.mjs` and the vectors to the scratchpad and ran `node e2e-rewrap.mjs reference`: **2 positive and 7 negative cases all PASS** on Node 22.

Short word list: **older device** = the phone in this document, signed in, with a box for the past. **New device** = registered later, `late: true`, waiting. **Box** = `keys[<device>] = {iv, w, ek?}`.

---

## (a) The exact sequence

All calls are `/sd <action> <json>` with a `reqId`, answered by `{"type":"sd","action":…,"reqId":…,"ok":true,"data":…}` (`socket_service.dart:339` `sdCall`, 12 s timeout, each frame paced 400 ms by `sendCommand`).

### 0. Preconditions on the older device
Signed in, socket online, own keys loaded, `e2e.status` says mode is not `off`, own device is registered and **not** `late`.

### 1. Learning that a device is waiting
| Trigger | Web | Mobile today | Mobile target |
|---|---|---|---|
| Event `sd_event` `e2e_devices_changed {user}` (own sockets only; sent on add, remove, `done`) | `connectumSocket.js:468` → `refreshSync()` | `E2eRepository._onEvent` → 2 s debounce → `_pollOnce()` → `refreshStatus` + `refreshPending` **only if late** | also `refreshPending` when **not** late |
| Socket `welcome` | `startE2E` → `refreshSync()` (`connectumSocket.js:395`) | `ensureSetup` → `refreshStatus` | add `refreshPending` |
| Timer | 30 s (`SYNC_POLL_MS`, `:25`) **only while this device is late** | 60 s, only while late, foreground | none needed for the older side; optional one slow check while Chats or Security is open |
| Feed item "A new device was added to your encrypted messages" (`category:"security"`, `feed_item`) | not used as a trigger | `FeedRepository` only counts unread | optional extra trigger: on that event call `refreshPending` |
| After the person acts (approve, remove, finish) | `connectumSocket.refreshSync()` (`E2ESyncPrompt.jsx:58,64`) | – | same |

The older web device does not poll. It relies on the event, on `welcome`, and on its own actions. Mobile can do the same.

### 2. `e2e.status`, with the device id
`/sd e2e.status {"id":"1bd6d3cab2c42004583acba1701e9188","reqId":"m-7"}` → `devices[]` with `late`, `ecdh`, `sign`, `label`, `ts`; also `mode`, `maxDevices`, `recovery`. See the full reply in `E2E_HISTORY_SYNC_MOBILE.md` ("The older device").

**Mobile gap:** `refreshStatus` sends `{}` (`e2e_repository.dart:227`). The server only records "last seen" when `id` is passed (`sd_e2e.erl:320` `touch`, once an hour). `waiting` and `helpers` list only devices seen **or added** in the last 30 days (`sd_e2e.erl:42,548`). So this phone drops out of `helpers` for a new device (and a late phone drops out of `waiting`) 30 days after its registration. Pass `{id: <own device id>}`.

### 3. `e2e.sync.pending {}`
```
/sd e2e.sync.pending {"reqId":"m-8"}
{"type":"sd","action":"e2e.sync.pending","reqId":"m-8","ok":true,"data":{
  "waiting":[{"id":"1d16eaa4acaa62ed9be52613c71088e0","label":"Ann phone","ts":1793596324566}],
  "helpers":[{"id":"1bd6d3cab2c42004583acba1701e9188","label":"Ann laptop","ts":1793596324053,"seen":1793596324593}],
  "recovery":null}}
```
`waiting` not empty and own id not in it → show the offer. The recovery key is never in either list. Field set from `sd_e2e.erl:535-542`.

### 4. Fresh lookup of the target (before showing the offer and again before Approve takes effect)
`/sd e2e.devices {"users":["ann"],"reqId":"m-9"}` → `data.users.ann[]` = `{id, ecdh, sign, label, ts, recovery?}`. Take `ecdh` of the device whose id is in `waiting`. (Web: `#handOn` `e2eClient.js:240-241` does `devicesOf([me], {fresh:true})`, finds the target, refuses recovery.) Limit 600 per 10 min.

### 5. Offer card → person taps
- **Approve** → step 6.
- **That is not me** → asks once more ("Remove it now"), then `/sd e2e.remove {"id":"<waiting id>"}` → `{"removed":true}`. Not for the recovery key. Afterwards `put` for that id answers `not_found`.
- **Later** → hidden until the next app start (web keeps it in component state, `E2ESyncPrompt.jsx:18,104`).

### 6. The job (only after Approve, on this device)
```
cursor = none
loop:
  /sd e2e.sync.page {"reqId":..}                      (first)   /  {"cursor":<next exactly as received>}
  → {"items":[{"id":114,"text":"e2e1:{…keys narrowed to my boxes…}"},…], "next": null | {"b":65,"c":0}}
  for each item:
      if envelope.keys[target.id] exists → count "already", skip
      if envelope.keys[me] missing        → count "skipped", skip
      open my box (box.ek ?? envelope.ek) → raw message key; if it does not open → "skipped"
      make box for target (section b)     → {mid, iv, w, ek}
  every 400 boxes and at the end of each page:
      /sd e2e.sync.put {"device":"<target id>","items":[{"mid","iv","w","ek"},…],"reqId":..}  → {"stored":N}
  yield to the UI
  cursor = data.next; until null
/sd e2e.sync.done {"device":"<target id>","reqId":..}  → {"done":true}
```
Real replies (all in `e2e-sync-replies.json`): `put` ok `{"stored":3}`; bad item `invalid` ("Each item needs a message id (mid) and a wrap (iv, w, ek, base64url)."); empty or over 500 `invalid` ("items must be a list of 1 to 500 wraps."); wrong device `not_found` ("No such device of yours."); `rate_limited` ("Too many history uploads; try again in a moment."). `done` twice is harmless. An empty history still calls `done`.

### 7. After `done`
The server clears `late` on the target, pushes `e2e_devices_changed` to the person's sockets, records `e2e.history_shown`. Older device: `refreshPending` → `waiting` empty → card shows "All set" (web: 6 s, `DONE_MS`, `:11`).

### 8. The one-session hop (read this twice)
One active session per person. In the real story:
1. New phone signs in → **our app** on the older device receives `session_replaced` → today `handleSessionReplaced` wipes that org+user rows and outbox, clears the token, goes to login (`session_repository.dart:136-148`). Keys and the late mark stay.
2. Person signs in on the older device (email code) → new phone is signed out → older device gets `welcome` → step 1-3 → offer.
3. Approve → job runs. **The older device must stay signed in.** If the new phone signs in again meanwhile, the older device is replaced; the job dies (`SocketCallError disconnected`); nothing is lost, the device stays waiting.
4. "All set" → person signs in on the new phone again.

Consequence for the design: the older device has just been wiped, so its SQLite has **no** messages. **The source of envelopes must be `e2e.sync.page`, not local rows.** (The doc allows own envelopes, but ours would be empty or partial in exactly this flow.)

### Rate limits that apply
| Call | Limit (per person) | Note |
|---|---|---|
| `e2e.sync.put` | 400 calls / 10 min, 1-500 items | 400 items → 160,000 boxes per 10 min |
| `e2e.sync.page` | 600 calls / 10 min, ~400 messages per page (50-450) | |
| `e2e.devices` | 600 / 10 min | |
| `e2e.status`, `e2e.sync.pending`, `e2e.sync.done` | none of their own | |
| every command | 30 per 10 s per connection (`/sd` also `busy`) | our `sendCommand` already paces 400 ms (about 25 per 10 s), shared with chat sends |

---

## (b) The crypto of the rewrap step

Same box as any other, two differences: the one-time key is made by the older device, and it travels in the box (`ek`).

```
// 1. open my own box (this is also what reading does)
box     = envelope.keys[myDeviceId]                      // must exist, else skip
ek      = box.ek ?? envelope.ek
shared  = ECDH(myEcdhPrivate, ek)                        // 32-byte X coordinate
wrapKey = HKDF-SHA-256(ikm=shared, salt=b64u_decode(envelope.mid),
                       info="connectum-e2e-wrap|" + myDeviceId + "|" + envelope.dev, L=32)
msgKey  = AES-256-GCM-decrypt(wrapKey, iv=b64u_decode(box.iv),
                              aad="e2e1-wrap|" + envelope.mid + "|" + myDeviceId, data=b64u_decode(box.w))   // 32 bytes

// 2. lock it for the target
eph     = NEW ECDH P-256 key pair, for every message
shared2 = ECDH(eph.private, target.ecdh)
wrapKey2= HKDF-SHA-256(ikm=shared2, salt=b64u_decode(envelope.mid),
                       info="connectum-e2e-wrap|" + target.id + "|" + envelope.dev, L=32)   // envelope.dev = ORIGINAL sender's device
iv      = 12 random bytes
w       = AES-256-GCM-encrypt(wrapKey2, iv, aad="e2e1-wrap|" + envelope.mid + "|" + target.id, data=msgKey)  // 48 bytes with tag
item    = {mid: envelope.mid, iv: b64u(iv), w: b64u(w), ek: b64u(eph.public, 65-byte uncompressed point)}
```
Web source: `e2eCrypto.js:173-179` (`wrapKey`), `189-195` (`wrapFor`), `221-227` (`unwrapKey`), `234-244` (`rewrapEnvelope`). Reference in plain Web Crypto: `tools/e2e-kit/e2e-rewrap.mjs` (`openOwnBox`, `lockFor`, `rewrap`).

Item checks before sending (the whole `put` is refused if any one fails, `sd_e2e.erl` `valid_sync_item`): `mid` 22 chars, `iv` 12 bytes (16 chars), `w` 48 bytes (64 chars), `ek` 65 bytes starting `0x04`, all base64url without padding.

### What the app already has (`lib/data/e2e/e2e_crypto.dart`)
| Building block | Present | Where |
|---|---|---|
| strict base64url encode/decode | yes | `encode`, `decode` (:23-33) |
| `_wrapKey` (HKDF salt = decoded mid, info `…|recipientDev|senderDev`) | yes, private | :228-242 |
| `_wrapAad` | yes, private | :212 |
| ECDH with fresh `EcdhPrivateKey.generateKey`, raw public export, 65-byte point check | yes | :278-284, :111-117 |
| open a box with `box.ek ?? e.ek` | yes, but **inside `openEnvelope` after the signature check**, and it never hands out the 32 raw bytes | :443-476 |
| fixed random for vectors (`E2eRandom.fixed`, `takeEphemeral`) | yes | `e2e_random.dart` |
| device private keys from secure storage as PKCS8 | yes | `e2e_key_store.dart:24-45` |
| **a function that opens a box and returns the message key** | **missing** | |
| **a function that locks a message key for a target** | **missing** (the loop in `buildEnvelope` :286-300 does it, but with the sender's ephemeral key and no per-box `ek`) | |
| **`rewrapEnvelope`** | **missing** | |
Parsing already keeps a box's `ek` (`parseEnvelope` :366-376). So the crypto is two small pure functions on `E2eCrypto`: `unwrapOwnBox(text, keys) → Uint8List` and `lockFor(rawKey, mid, senderDev, target) → {mid, iv, w, ek}`, with a `rewrap` that calls both. Order of fixed randoms for the vector test: `takeEphemeral()` then `bytes(12)` (so `E2eRandom.fixed([ephemeral, iv])`). No new package.

Decision to keep: rewrap must **not verify the sender signature** (the web does not either): it only re-locks a key this device could already open, so it reveals nothing new. Signature stays a reading rule. It must verify the GCM tag of its own box (it does by decrypting).

### Vectors to match (`e2e-test-vectors.json` → `rewrap`; throwaway keys; all values below copied from the file)
Case 1, a waiting device:
```
mid              4m1BDDbS54nDe_439URewQ
older device     e4a7c80875a31d2aac65f69c55501225
waiting device   5a7c237d891db44ee3cfd0c656f7a872   (ecdh public in input.target.ecdh)
envelope.dev     7282251cafd6326cf79fadc1e6ea6eff
fixed eph d      VtD7sTPPlhBgtoZBKNHfVw7wDIvS0P0Ds1OGFfII_80   x Kfc-z9w3koacbvzxOlf4OFXtwqOQkZTofNxJuubbjpM   y 0GJ_eGbD09Y3CyjZifAk7T4DvhKmN9yhLXZ-TTrn3dE
fixed iv         atBD30TBT3dTBh7U
ownBoxEk         BHm9bbuLuLV6Td-pjgiiXyouTXXjuwh96yTAYygJheTtY2gLy2ycP-b_w0FE10qtuyCojssfHIaJabRhNtmMeIM   (the envelope's ek: the older device's own box has none)
ownSharedSecret  c17d8cef9687292eb4a317767a7ea2559ce10cca089b617fed3cf18b080c3697
ownWrapKey       e1f4f3ea4163ec152f184ad2981d60b41452ef016abb1ab6b36754705432a4a6
ownHkdfInfo      connectum-e2e-wrap|e4a7c80875a31d2aac65f69c55501225|7282251cafd6326cf79fadc1e6ea6eff
msgKey           024baa35469e6dbffbb9c35efb5a823e433711821ac7e4194b843a4c65c6db90
sharedSecret     8a33079a9984af3a81762d6061fb84bd0a8ffda136c5a6dfdb6626af5a8f7f42
hkdfSalt         e26d410c36d2e789c37bfe37f5445ec1
hkdfInfo         connectum-e2e-wrap|5a7c237d891db44ee3cfd0c656f7a872|7282251cafd6326cf79fadc1e6ea6eff
wrapKey          3b6414a250ae5805c122c84d9ff6e32cec05d843e15f4b963ce764076f69c021
wrapAad          e2e1-wrap|4m1BDDbS54nDe_439URewQ|5a7c237d891db44ee3cfd0c656f7a872
EXPECTED item    {"mid":"4m1BDDbS54nDe_439URewQ","iv":"atBD30TBT3dTBh7U","w":"6RZGtxtIMPuV3WRYakcEBJC_gTt3jo6g_oo_bhxkdYyOJEmpXMmJax904Li46tn5","ek":"BCn3Ps_cN5KGnG788TpX-DhV7cKjkJGU6HzcSbrm246T0GJ_eGbD09Y3CyjZifAk7T4DvhKmN9yhLXZ-TTrn3dE"}
```
Case 2, the recovery key as target (same steps; used by stage D): target `d429f6b748dbc62019a27801ec386b58`, fixed iv `y39i8cPpY-xqtOnd`, msgKey (same) `024baa35…c6db90`, shared `9887c59c305f639511b106440c1a458f5831c4f002921b2dd4235a5b559c9af1`, wrapKey `2b570d4c5c0fc0ea85bd89546f166a1c030be4c9fdbe2864066895420c86160d`, expected `w` `EGlslQ4VXsfwSEN-SGZNpwtEsbCtRhvel_IPddL0JsZKklQZbFfeOgDLhpUGEU08`, `ek` `BBcN2dlQABMLTtv7GAnV4ZSMlqj3OLLQsQca82xp6iYPfzutzU6-aO6CHPkqCVd9wHyNv7XN35ELuvpnLG098Ns`.

The full inputs (envelope, `ecdhPkcs8` of the older device, `targetEcdhPkcs8`, `ephPrivateJwk`) are in the JSON and are throwaway; the app's `mobile-handoff/e2e-vectors.json` does **not** yet contain the `rewrap` section (it has `lateBox` only) and must get it before stage B.

Reading side, the same file's `lateBox` (device `ac30d8a7b01774a27052b3a1aab2c62f`, box `ek` `BF1nEst1…`, shared `bd62ab82…18b8`, wrapKey `6a7179ed…9a09`, hkdfInfo `connectum-e2e-wrap|ac30d8a7b01774a27052b3a1aab2c62f|7282251cafd6326cf79fadc1e6ea6eff`) already passes in `/debug/e2e`.

**Negative vectors the reading code must refuse (all 7 pass in the node tool; check each on the phone):**
| Case | Stops at |
|---|---|
| box made for another message (wrong mid) | 5 open the box |
| older device's id in the HKDF info (must be the ORIGINAL sender's) | 5 |
| older device's id in the aad (must be the waiting device's) | 5 |
| box without its own `ek` | 5 |
| one bit of `w` changed | 5 |
| good box delivered in another conversation | 2 conversation |
| envelope with no box for this device | 3 box for this device |

---

## (c) How the web decides what to hand on, and in what order

- **List:** only `e2e.sync.page` (`e2eClient.js:254`). Server walks conversations sorted by key (`sd_e2e.erl:581`, DMs then groups, sorted), inside each newest first, a page ends after the store page that reaches 400 messages (`sd_e2e.erl:40,577`). `next` is `{b,c}`, opaque, sent back unchanged.
- **In it:** every end-to-end envelope the person can see (sent, received, replies, groups), edited messages in their current form, keys already narrowed to the person's **own** boxes including late boxes already stored. **Not in it:** deleted, plain, forms, a cleared conversation before the clear point, a group the person left (`sd_e2e.erl:581-598`).
- **Per item** (`e2eClient.js:256-265`): `parseEnvelope`; if `keys[target.id]` exists → `already += 1`, skip; else `rewrapEnvelope`; an `E2EError` (no box for me, box does not open) → `skipped += 1`; any other error aborts the job.
- **Batching:** collect to `SYNC_BATCH = 400` (`:9`, `:261`) and one more flush at the end of each page (`:266`); progress callback after every flush (`:250`).
- **Pacing:** no timer; one `setTimeout(0)` between pages "to let the screen breathe" (`:269`). No back-off for `rate_limited`: the web throws and shows "Try again". (The doc asks the app to wait and retry the same batch; mobile should.)
- **Stop:** `AbortSignal` checked **between pages** only (`:253`), not inside a page. A stop leaves the device waiting and does not call `done`.
- **Finish:** `e2e.sync.done {device}` after the last page (`:273`) even when 0 sent. Restore variant skips `done` if sent=0, already=0, skipped>0 (`:230,272`) and throws "Your recovery code does not open any earlier message…".
- **Messages the older device cannot open:** skipped silently, counted, **no number shown** (doc: "the web app shows no number for skipped ones"). They also stay grey on the new device.
- **Who may be the target:** `devicesOf([me], fresh)` must contain it and it must not be the recovery key (for hand-on) (`:240-242`). The web does **not** check that the target is in `waiting` or `late`, does **not** pin its keys, and the server does not check either (it stores boxes for any device of the person). Mobile will be stricter (section e).
- **Resume:** run again; boxes already on the server show in the narrowed `keys`, so only what is left is rewritten.

---

## (d) UX

### What the web shows (`E2ESyncPrompt.jsx`, texts are good to copy)
| State | Lines | Text |
|---|---|---|
| Offer | 92-109 | **"Show your earlier messages on {device}?"** / "This device was just added to your account. If it is yours, approve it and your earlier messages will appear there. If you do not recognise it, remove it." Buttons **Approve**, **That is not me** (second tap: label becomes **Remove it now**, `confirmRemove` `:20,61`), **Later** |
| Working | 73-78 | "Showing your earlier messages on {device}" / "{N} messages done. Keep this window open until it finishes." (before the first batch: "Starting.") / progress bar / **Stop** |
| Done | 79 | "All set" / "Your earlier messages are now on {device}." (disappears after 6 s) |
| Error | 80-86 | "Could not finish" + message (abort: "Stopped.") / **Try again**, **Close** |
| New device waiting | 111-127 | "Your earlier messages are not shown here yet" / "Sign in on {1-2 helper names} and approve this device. Signing in there signs you out here, so sign in here again afterwards and your earlier messages will be waiting." / none: "None of your other devices was active recently. If you set up a recovery code, enter it…" / **Got it** |
| Mode `off` | 48 | nothing is shown |
| Backup nudge | 129-144 | after a day of use, once: "Back up your messages…" (stage D) |
The card is bottom-left, 380 px, fixed. Unmounting aborts the job (`:41`).

### Proposed mobile UX (tokens only; no new shared widget unless needed)
- **Where:** a card above the Chats list (same slot style as the late hint) and the same block at the top of the Security screen (`SecurityView`, next to `LateNotice`). A floating `AppNoticeCard` is wrong for this: it auto-dismisses; use it with `holdFor: null` only if a floating card is preferred. The offer survives until answered (doc: no time limit).
- **Offer card** (`AppColors.accentSoft`, `AppRadius.mdAll`, `AppSpacing.sm` padding like `LateNotice`): icon `Icons.phonelink_lock`; title `AppText.readableStrong` "Show your earlier messages on {name}?"; body `AppText.readable` "This device was just added to your account. If it is yours, approve it. If you don't recognise it, remove it."; caption `AppText.caption` "Added {relative time}. ID {first 8 of the device id}". Buttons `AppButton.primary("Approve")`, `AppButton.secondary("That's not me")`, `AppButton.text("Later")`. "That's not me" opens an `AppBottomSheet` confirm ("Remove {name}? It will stop receiving your messages.") then `e2e.remove`.
- **Approve confirmation:** the Approve tap itself is the explicit consent, but because the label is server-supplied, the card must show the sanitised name (below) and age before the tap. No second dialog needed.
- **Running:** the same card turns into a progress card: title "Showing your earlier messages on {name}", `AppText.readable` "{N} messages done. Keep the app open until it finishes.", `AppProgressBar` (the total is unknown: indeterminate, or a determinate estimate from a count the app can get only after the walk; web is count-only), `AppButton.text("Stop")`. Motion from `AppDurations.base`/`AppCurves`.
- **Done:** "All set" + `AppSuccessAnimation` once (it exists), body "Your earlier messages are now on {name}. Sign in on that device again to see them." (mobile-specific because of the session hop).
- **Paused (app backgrounded, connection lost, `session_replaced`):** "Paused. Open the app to continue." Never an error for a network drop; the job is resumable. Offline: show the card disabled with the dark offline bar only (cached-first rule); Approve is disabled offline because it needs a connection (like the other E2E actions).
- **Error:** "Couldn't finish" + short reason + `AppButton.primary("Try again")`, `AppButton.text("Close")`. Messages: `rate_limited` → "Slowing down, will continue" (automatic back-off, not an error), `not_found` → "That device was removed." (close card), `invalid` → "Something went wrong with our copy of your messages. Try again." (a bug of ours: log the code, not the data).
- **Device name (sanitised exactly as the doc says):** "The device's name is shown as plain text: control characters are removed and it is cut to 60 characters" (`E2E_ENCRYPTION.md` "Alerts when a device is added"; `e2e.md` for registration). So `label.replaceAll(RegExp(r'[\u0000-\u001f]'), '').trim()`, cut to 60, shown in a plain `Text` (no links, no markup, no `Text.rich`). Empty after sanitising → "A new device". Stricter hardening (bidi and zero-width characters, `\u007f`) is **not** in the doc; listed as a question to the backend (Q9), not done silently.
- **Strings:** all in one place with the other E2E texts in `E2eRepository` (existing pattern), not scattered in widgets.

---

## (e) Edge cases and what we must refuse

Security rules (from the task) are applied as hard gates in one function, `E2eRepository.canHandOnTo(deviceId)`, checked at offer time and **again right before the first `put`** (a lookup made minutes ago is not trusted).

| Case | Rule |
|---|---|
| Approve | Only from a tap on this device. No code path starts the job from a push, an event, a deep link, a timer, the feed, or app start. A persisted "approved" flag is not allowed; after a kill the person approves again. |
| Device not listed by the server as late for this account | Refuse. Target must be in the fresh `e2e.sync.pending.waiting` **and** `late: true` in a fresh `e2e.status` **and** in a fresh `e2e.devices {users:[me]}`, with the same `ecdh`, **and** not `recovery`, **and** not this device. (The web checks only the `e2e.devices` part; the server checks nothing but ownership.) |
| A device that is not really late | Not in `waiting` → no offer. If it leaves `waiting` during a run (someone else finished, removed) → stop, close the card. |
| Changed key | Run `checkPins({me: [target]}, isRecord: false)` first. Known device id with a different `ecdh`/`sign` than the pin → refuse, show the existing key-changed review, never replace the pin. Unknown device id → pin it at Approve (`isRecord: true`) so a later swap of its keys is caught; this does not weaken pinning, it adds a pin. If `ecdh` changes **during** the run (fresh lookup before each page, cheap and within the 600 per 10 min) → stop. |
| Offer for a device we do not know | Fine to **offer** (that is the point: the person decides), but only with the details above (name, age, short id). Never auto-approve, never hide the "That's not me" action. Label is untrusted text (sanitised, plain `Text`). |
| Recovery key as target | Never offered, never a target of the hand-on; only the stage-D backup job may target it, and only with its own explicit button. |
| Tampered / forged box seen by us as the **new** device | Reading refuses all 7 negative vectors (section b); a box without own `ek` is never opened with the envelope's key (already so, `parseEnvelope` :372-374). |
| Tampered envelope seen by us as the **older** device | `sync.page` is server data. A forged envelope can only get us to re-lock a key the server already knows; harmless. We skip anything that does not parse or whose box does not open. We do not need a signature check here. |
| Replays | `put` is idempotent: one box per (mid, device), later replaces earlier. Replaying a page, a `put`, or `done` changes nothing. A replayed `waiting` event just re-reads state. |
| Wrong mid / a mid that is not the person's | The server stores it and never serves it (`E2E_HISTORY_SYNC_MOBILE.md` "Put and done"). Not a leak. We still only send `mid`s taken from the envelopes we opened. |
| Rate limits | `rate_limited` on `put`/`page`: wait (start 5 s, ×2, cap 60 s, up to 10 min total), retry the **same** batch, show "Slowing down". Never skip a batch. Budget: stay far below 400 puts per 10 min. |
| Server says `not_found` on `put` | Target removed: stop, close, no retry. |
| Another device finishes first / two older devices | Safe; last write wins, either valid. The card disappears when `waiting` empties. |
| `session_replaced` during the job | The socket stops; the job ends as "paused". The rows are wiped (existing rule) but the job needs none. Next sign-in re-offers. |
| Handshake error / expired token | Same: pause; keys stay; offer again after login. |
| App backgrounded / killed | Job pauses (no background execution; section f). No data loss. |
| Mode `off` | No card, no calls. |
| Empty history / nothing openable | Still call `done` (web does). For hand-on only. |
| Device label with 60+ chars, control chars, RTL marks | Section (d). |
| Memory | Never collect all boxes: flush every ≤400. Keep only counters. The private key is loaded from secure storage as today, held in memory for the job, dropped at the end; it is **not** written anywhere new, not logged, and not part of any request. Envelopes and message keys are never logged (existing `REACT`-style prints must not be copied). |
| 100k-message history | 250 pages + 250 puts ≈ 500 calls ≈ 3.5 to 6 min at the 400 ms pace; fine. Measure on a phone before promising. |

---

## (f) Staged build plan

Sizes are working days for one developer, including self-tests, excluding two-device testing time.

### Stage A: the offer, Approve and "not me" (no hand-on) , **S-M, 2-3 days**
- `E2eRepository`: `waiting` (`RxList<E2eDevicePublic>`), `refreshPending` also when not late, called on `welcome`, on `e2e_devices_changed`, on app resume, on opening Chats/Security; pass `{id}` to `e2e.status`.
- `canHandOnTo` gate (fresh `pending` + `status` + `devices` + pin check) as one method; `rejectDevice(id)` (= `removeDevice`, asked twice).
- Offer card widget + strings + sanitiser, in Chats and Security; "Later" in memory.
- Approve in A calls the gate and stops: it must **not** pretend to hand on. Ship A only behind a debug flag (or show Approve disabled with "Available in the next update") until B is finished; do not release A alone, because a person would see an offer that cannot be completed.
- Done when: `dart analyze` clean; the offer shows for a stand-in new device (section g); "not me" removes it; no network call except the five listed.

### Stage B: the hand-on , **L, 6-8 days**
1. `E2eCrypto.unwrapOwnBox`, `lockFor`, `rewrap`; add the `rewrap` section to `mobile-handoff/e2e-vectors.json`; `/debug/e2e` self-test runs both positive cases byte for byte and refuses the 7 negatives (**gate: do not send anything real before this passes on a device**).
2. `HandOnJob` (one concrete class in the repository, no base class): state `idle/working/paused/done/error`, counters `sent/skipped/already`, `stop()`.
3. Background isolate for the CPU part: `Isolate.run` per page with `{pkcs8 of my ECDH key, my device id, target {id, ecdh}, envelopes[]}` → `{items[], skipped, already}`. The main isolate does all socket calls, pacing and UI. The worker never touches sqflite, GetX or the socket. **Open item:** confirm `package:webcrypto` works inside a spawned isolate on both platforms and measure; at about 0.25 ms per message on a laptop it may be cheap enough to run on the main isolate in chunks of 50 with `await Future.delayed(Duration.zero)` (then no isolate, and the PKCS8 bytes never leave the main isolate). Decide after measuring on a phone; the isolate is the default because the task asks for it.
4. Pacing: use `sdCall` as is (400 ms pace); between pages yield; `put` at ≤400 (configurable constant, see Q6 on frame size); `rate_limited` back-off as in (e).
5. Stop button: checked between pages **and** between chunks inside a page (better than web). Stop does not call `done`.
6. Foreground rule: pause on `AppLifecycleState.paused/inactive`, resume on `resumed` (re-run is cheap because of `already`). **No new package and no new permission.** A wake lock needs `wakelock_plus` plus `WAKE_LOCK`, which would also change the "Permissions" line in CLAUDE.md (release manifest is INTERNET + ACCESS_NETWORK_STATE only). Not recommended for B; text says "Keep the app open". Decision for you (see end).
7. Progress UI per (d); `done` call; refresh pending.
8. Keep the `unlockRequests`/late logic untouched on the older side.
- Done when: vectors pass on both OSes; a run against the stand-in new device (g) ends with `read --expect N` OK; Stop then re-run finishes with no duplicates; a kill mid-run followed by a re-run finishes.

### Stage C: the new-device side re-fetch fix , **S-M, 2-3 days** (can run in parallel with B; it is independent of the hand-on)
Items from section 5: re-request `/conversations` (and `/groups`) after an unlock; make `_decryptPreviews` re-open previews whose message row is `cant_decrypt`; do not lose the unlock trigger when `_isUnlocking` is busy; keep polling status for a short time after `late` ends only if the unlock did not finish; show "Your earlier messages are now readable" even when rows were wiped; e2e.status with `id`.

### Stage D: recovery code backup and restore , **L, 7-10 days, after A-C**
Creating the recovery key (two extra extractable P-256 pairs), the 26-character code, the sealed blob (`e2e.recovery.set`, `.get`, `.delete`), the backup job (= stage B with the recovery key as target; skip envelopes that already have `keys[recoveryId]`), restore on a new phone (source = recovery key id and private ECDH, target = this device, "opens none → do not call `done`"), UI, and the optional once-a-day suggestion. **Blocked on a recovery vector** (code, salt, iv, blob) from the backend (Q2 of `e2e-gap-analysis.md`, restated Q10 below). No new package is needed for what the docs specify (HKDF-SHA-256 + AES-GCM, no memory-hard KDF). The recovery private key may leave secure storage only inside the sealed blob; the plain 26-character code is shown once and never stored or sent.

---

## (g) What can be tested without a second real device

| Test | How | Needs |
|---|---|---|
| Rewrap bytes (B1) | `/debug/e2e` self-test with the `rewrap` vectors: same `{mid,iv,w,ek}` and intermediates, both cases | phone only |
| Negative boxes | the 7 negative vectors, plus the 4 tamper cases already in `/debug/e2e` | phone only |
| Reference run of the web side | `node tools/e2e-kit/e2e-rewrap.mjs reference` (done in the scratchpad: 9 of 9 PASS) | Node 22 |
| Check a box our code made | `node tools/e2e-kit/e2e-rewrap.mjs check input.json` with `{text, targetId, targetEcdhPrivateKey, senderSignPub, item, expectConv}`; export from `/debug/e2e` (test keys only) | Node 22 |
| **Stand-in new device** | `tools/e2e-kit/new-device.mjs register | status | read` registers a late device for a **test** account over WebSocket, and later opens every message with the checker's steps (`read --expect N`). The real phone is the older device. This exercises steps 1-7 of (a) end to end with one phone. | one phone, a test account with messages, a session token per command (one-session rule: each command needs a fresh sign-in, which logs the phone out, so follow the table in `E2E_HISTORY_SYNC_MOBILE.md` "Testing the two-device flow with one phone") |
| Offer card, progress, error states | `SEED_UI` fixtures (add a `late-device offer` chip beside the existing `SeedUi.e2eStates`); gallery | none |
| Throttling, `rate_limited`, `not_found` | a fake `sdCall` in a debug screen that replays `e2e-sync-replies.json` shapes | none |
| Stage C (new-device re-fetch) | partly: a unit-style debug run that marks rows `cant_decrypt`, serves the `lateBox` envelope, and runs `_unlockLocked`; the live path needs an older device (or the stand-in's counterpart) | phone + stand-in or web |

**Needs two real devices:** the one-session hop on a real phone pair (new phone signs in → older gets `session_replaced` → older signs in → new phone is out → approve → new signs in again), foreground/background behaviour of a long run, the real Android/iOS suspension, and a web account as the new device against a phone as the older (the likeliest demo). The stand-in covers the crypto and protocol, not the OS behaviour.

---

## (h) Questions for the backend team

1. `e2e.status` records "last seen" only when `id` is passed (`sd_e2e.erl:320`). Confirm that passing it on every status call is what you expect from mobile, and that `waiting`/`helpers` exclude a device not seen for 30 days (`:42,548`) even right after its registration `ts` ages out.
2. Does the **server** ever need to know approval happened? Today it cannot tell (`E2E_HISTORY_SYNC_MOBILE.md` "Security and consent"). Would you add an optional `e2e.sync.approved {device}` audit record before the first `put`?
3. May `e2e.sync.put` / `e2e.sync.done` be refused for a device that is not `late` (and not the recovery key)? That would enforce "only for a waiting device" on the server instead of only in the app.
4. Is `e2e.sync.page` complete for conversations the phone never opened, and does it include group messages for groups the person belongs to even when no one has written for months (`conversation_keys`, `sd_e2e.erl:581`)? Does it include messages from a group before the person joined? (A device would have no box for them: confirm they are simply skipped.)
5. Pagination stability: if a message is edited or a new one arrives while we walk, can an item appear twice or be missed? The cursor is `{b: message id, c: conversation index}`; the conversation list is re-sorted per call. What if a DM is created mid-walk (index shift)?
6. Maximum WebSocket text frame. A `put` of 400 boxes is about 90-100 KB in one frame. You found no explicit limit; has any proxy limit been seen? Should mobile use 200 per `put`?
7. `put`/`page` budgets (400 and 600 per 10 min) are per person, not per device: do a backup (stage D) and a hand-on running at once share the budget? Same for `e2e.devices` used by the send path.
8. `done` and `e2e_devices_changed`: when the new device has no socket (it was signed out by the older one's sign-in), is there any push or notification that tells it? We assume it learns only on its next sign-in. Is a "history ready" push planned?
9. Label sanitising: the doc says control characters removed and 60 chars. Would you accept additionally removing bidi controls (`U+202A-202E`, `U+2066-2069`), zero-width characters and `U+007F` in the display? Is the label also trimmed server-side at registration, so we can trust length?
10. Recovery vector (needed for stage D): please add to `e2e-test-vectors.json` a fixed code, salt, iv, and the resulting blob, plus the PKCS8 `{e,s}` JSON plaintext and the recovery key's `id` used in HKDF info/aad.
11. Concurrent sessions: still "not built, a company decision"? It would remove the sign-in hop and change the texts and the work (mobile could then offer while the new device stays signed in).
12. Does the feed item "A new device was added…" carry the device id, so a tap can open the offer directly? (Today it has the name only.)
13. For the stand-in tool: can a test account be given a long-lived token so the one-session rule stops forcing a phone sign-out between commands in test?

Questions for you (decisions, not backend): keep the app awake with `wakelock_plus` (new package + `WAKE_LOCK`) or foreground-only with a clear text; isolate or chunked main-isolate crypto after measuring; whether stage A may ship alone behind a flag.

---

## 5. Diagnosis: the spare phone shows "Encrypted message" and "Your earlier messages aren't shown on this phone yet. See Security."

Observed on your side (not reproduced by me, no device was touched). Everything below is read from code.

### What the notice and the placeholder mean in the code
- The notice is `E2eRepository.lateHintText` (`e2e_repository.dart:91`), shown while `isLate` is true. `isLate` is set from the server (`e2e.status` → this device's `late`, `_applyLate` :332-354) or, before the first status, from the persisted mark `e2e.late.<org>.<user>` = `1` (`keys()` :213-216).
- "Encrypted message" in the Chats tile is `Conversation.lastIsEncrypted` (`conversation_tile.dart:203`), which is true when the last message's `decrypt_state` is not `ok` (`conversation.dart:136-139`), or the list row says `[encrypted message]` and no message row holds it.
- Both symptoms together say: **the server still lists this phone as `late`** (or did when the app last asked), and the boxes are not (all) there. The server clears `late` only when an older device calls `e2e.sync.done {device}` (`sd_e2e.erl:604-614`). Nothing else clears it.

### The most likely reason, said plainly
**Nobody has handed the past on.** The app has no older-device code (section (a)-(f)): it cannot be the helper. If the other device is another phone with this app, it cannot do it. If it is the web, the person must (1) sign in on the web (this signs the spare phone out), (2) see the card "Show your earlier messages on …?", (3) press Approve, (4) wait for "All set", (5) sign in on the spare phone again. Skipping or interrupting any step leaves it late. This cannot be told from code alone; check in this order:
1. Security screen on the spare phone: is "Waiting for your other device to show your earlier messages" there after a fresh sign-in? Yes → the server says late → nobody finished. Go to the web and do 1-5 above. No → go to the next list.
2. If the web shows no offer at all: the spare phone must be in `waiting`, which needs its `ts`/`seen` within 30 days and `late: true`. Also check the web's `e2e.sync.pending`.
3. If the Security screen shows no waiting line but the Chats list still says "Encrypted message": this is the re-fetch problem below.

### What must happen on the new device after the older device approved and handed on
1. Older device stores all boxes and calls `done`. Server: `late` removed on the new device's record, `e2e_devices_changed` pushed to the person's sockets (the spare phone has none: it was replaced).
2. Spare phone: person signs in again → login → `welcome` → `E2eRepository.ensureSetup` (`onOnline`) → `refreshStatus` → `_applyLate`: own device not late, mark `1` → writes `2`, clears the hint, `_unlockRequests.add` (:332-354).
3. If the session had been replaced, `handleSessionReplaced` already wiped that org+user's rows (`session_repository.dart:136-148`), so there is nothing to repair: history is fetched fresh, now with the new boxes, and each envelope opens with `box.ek ?? e.ek` (`e2e_crypto.dart:447-450`). `/conversations` previews are opened by `_decryptPreviews` (`conversation_repository.dart:477-501`, a row with no message row yet, so `known.isEmpty`, opens). **In that path the symptom should disappear by itself after the next sign-in.**
4. If the rows were kept (handshake/expired token, or the person did not hit `session_replaced`; also any time the status turns not-late while the app is running): `MessageRepository._unlockLocked` (:152-182) re-fetches history for every conversation that has `cant_decrypt` rows, newest first, 1 page per second, stopping at the oldest locked message or `_maxUnlockPages`; a changed envelope text becomes `pending` (`_upsert` :1948-1958) and `_decryptPending` opens it and reloads lists and conversations (:217-256). Then `finishUnlock` clears the mark.
5. The web equivalent (the doc's "real bug found in the browser test"): `refreshSync` on "was waiting and now not" → `clearMessageCache()`, `e2e_history_ready`, `sendConversations()` (`connectumSocket.js:366-386`; `clearMessageCache` at :379, `sendConversations` at :381), and "was waiting" survives a restart (`browserFlag`). Mobile's persisted mark does the same job.

### Missing or doubtful on the new device (read from code, each with where)
1. **Chat-list previews are not refreshed after an unlock.** `_unlockLocked` only visits conversations that already have `cant_decrypt` message rows (`message_repository.dart:160-171`). A conversation known only from the `/conversations` list (never opened) has no row. Its preview text `[encrypted message]` is re-opened only by `_decryptPreviews`, which runs only when a **`conversations` event arrives** and skips every row that already has a message row (`conversation_repository.dart:486-490`, the `known.isNotEmpty → continue`). The web re-sends `/conversations` after clearing (`sendConversations()`). Mobile does not. **This alone can leave "Encrypted message" in the chat list after the device stopped being late**, until something else triggers `/conversations` (reconnect/restart). Fix: after `finishUnlock` (and after the wipe path's login), request `/conversations` and `/groups` again; make `_decryptPreviews` also re-open when the matching message row is `cant_decrypt`.
2. **The unlock trigger can be lost.** `unlockRequests` is a broadcast stream; `_unlockLocked` returns immediately if `_isUnlocking` or the socket is offline (`:155-157`) and the mark stays `2`. But once `late` ended, `_applyLate` cancelled the poll timer (:347), so nothing asks again until the next `refreshStatus` (reconnect, event, or 60 s only while late). On a flaky connection the unlock may never run until the next restart. Fix: retry while the mark is `2` (a few attempts with back-off) or on resume.
3. **`finishUnlock(readable: before − after)`** only sets the "now readable" notice when rows existed. After the wipe path it is 0, so the person gets no confirmation. Cosmetic, but it makes "did it work?" invisible.
4. **`e2e.status` is sent without `id`** (`:227`): "last seen" is never updated for this phone; after 30 days it falls out of `waiting`/`helpers` and the web would stop offering it, and the server may replace it as "unused" at the 10-device limit. Fix in stage A.
5. **Poll cadence** is 60 s and only in the foreground while late (`_pollEvery`, :45; `didChangeAppLifecycleState` :152); the doc says about 30 s. Harmless, since the phone is usually signed out in the middle of the story anyway.
6. **"Keys survive `session_replaced`"** is true by code: `handleSessionReplaced` does not call `E2eKeyStore.remove`, `wipeScope` clears only `_scopedTables` (conversations, messages, forms, outbox, cursor; **not** `e2e_pins`), and the late mark is not deleted. It is the right behaviour; confirm once with the debug screen after a real replace. The Security text ("Your keys stay on this phone when you sign out") matches.
7. **Groups:** `_unlockLocked` iterates all `conv_id`s including groups; opening a group envelope needs the sender's signing key via `groupDevices` (`e2e_repository.dart:960-990`). Fine, but CLAUDE.md says encrypted groups are read-only/blocked on sending; the doc's `sync.page` includes groups, so a hand-on from this phone would include them. No code conflict, only a reminder.
8. **Boxes that never arrive:** a message sent before the older device had a box (older than that device) is skipped on purpose and stays "Encrypted message" forever on the new device. That is by design (`Edge cases`), but the UI today gives the person no way to tell "waiting" from "never readable". Consider a different line once `late` is false: "Sent before your other device was set up; it can't be opened."
9. **Not checked / unverifiable here:** the actual server state of the spare phone, whether the web's Approve was pressed and finished, and any message in the spare phone's database. Section "most likely reason" lists the three checks that settle it.

---

## 12-line summary

1. The older-device job is: `pending` (waiting) → fresh `e2e.devices` → explicit Approve → loop `e2e.sync.page` → open own box (`box.ek ?? e.ek`) → fresh ephemeral key → box for target → `e2e.sync.put` (≤400) → `e2e.sync.done`.
2. The crypto is the normal wrap with the **target's** id in HKDF info/aad and the **original sender's** `dev` in info; two vectors (waiting device, recovery key) and 7 refusals exist, and all 9 pass in the reference node tool (run on a copy in the scratchpad).
3. The app already has HKDF/AES-GCM/ECDH, strict base64url, ephemeral keys, box `ek` parsing and fixed-random for vectors; it lacks `unwrapOwnBox`, `lockFor`, `rewrap`, and the `rewrap` vectors in `mobile-handoff/e2e-vectors.json`. No new package needed.
4. The web hands on whatever `e2e.sync.page` returns, skips boxes the target already has, skips anything it cannot open, batches 400, yields once per page, aborts only between pages, then calls `done`; it never checks that the target is late or pinned (we will).
5. Our rules are stricter: target must be in fresh `waiting` **and** `late` **and** in `e2e.devices` with the same key, not recovery, not me, pin-checked; re-checked before the first `put`; Approve only from a tap.
6. The session hop changes the design: the new phone's sign-in wipes the older app (`session_replaced`), so the source must be `e2e.sync.page`, not local rows.
7. UX: offer card in Chats/Security with `AppButton.primary/secondary/text`, `AppProgressBar`, plain-text device name (control chars removed, 60 chars), Stop, paused and "All set, sign in on the other device again".
8. Plan: A offer/not-me (2-3 d, behind a flag), B hand-on (6-8 d, vectors first, isolate only if measurement says so), C new-device re-fetch fixes (2-3 d), D recovery backup/restore (7-10 d, needs a recovery vector).
9. Testable on one phone: vectors, negatives, the node reference, and the stand-in new device (`new-device.mjs register/status/read`); two devices are needed for the real session hop and OS suspension.
10. One real bug found: `e2e.status` is sent without `id` (`e2e_repository.dart:227`), so the phone is never "seen" and drops out of `waiting`/`helpers` after 30 days.
11. Spare-phone symptom: the server still has it `late` because nobody finished `done` (the app cannot be the helper); if it is not late, chat-list previews stay "Encrypted message" because nothing re-requests `/conversations` after an unlock and `_decryptPreviews` skips rows that exist.
12. 13 questions for the backend team and 3 decisions for you (wake lock, isolate vs chunks, whether stage A ships alone) are at the end of (h).
