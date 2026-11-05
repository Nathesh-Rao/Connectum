# End-to-end: a new device and reading earlier messages (analysis for the mobile team)

Written 4 November 2026 from the code on `origin/main` (commit `6e1d0009`). It explains what the web app and the Erlang server do today when a person signs in on a **new device** and wants to read earlier messages, so the phone app can behave the same way.

- **This is analysis, not a copy of the code.** Every claim has a `file:line` pointer. Lines are for the commit above and will drift; search for the function name if a line has moved.
- **No real keys, codes, tokens or user data** appear here. Anything that looks like a value (`ABCDE-...`, `<device-id>`, `mid_xxx`) is a placeholder. The real fixed test values are in `docs/e2e-test-vectors.json` (section 5 and 9 say where).
- **Short names for files:** `Client` = `chat-app/features/connectumChat/e2e/e2eClient.js`, `Crypto` = `.../e2e/e2eCrypto.js`, `Store` = `.../e2e/e2eStore.js`, `Socket` = `chat-app/services/connectumSocket.js`, `Prompt` = `chat-app/features/connectumChat/components/E2ESyncPrompt.jsx`, `Badge` = `.../components/E2EBadge.jsx`, `Server` = `connectum-backend/src/security/sd_e2e.erl`.
- The companion file `docs/E2E_WEB_COMPLETE.md` covers everything else about E2E on the web (algorithms, envelope, every message type, attachments, policy, UI texts).

## 0. Read this first: where the existing docs and the code disagree

I compared the existing E2E docs with the code. I read `E2E_ENCRYPTION.md` and `E2E_ATTACHMENTS.md` in full, and `E2E_HISTORY_SYNC_MOBILE.md` except its "Real replies" and test-vector sections. `E2E_SIMPLE_GUIDE.md`, `E2E_MOBILE_KIT.md` and `E2E_MOBILE_REVIEW.md` I only searched for key terms. `E2E_FRESH_DEVICES_CHANGE.md` was **not** read for this document.

| # | What the doc says | What the code does | Where |
|---|---|---|---|
| D1 | `E2E_ENCRYPTION.md` "Targets": "Any device of the person is a valid target" for `e2e.sync.put`. | The server refuses a device that is not **waiting** (`not_waiting`). The only exceptions are a recovery key that is not backed up yet, and the person's **only** device. `E2E_HISTORY_SYNC_MOBILE.md` has this right; `E2E_ENCRYPTION.md` is out of date. | `Server:578-579`, rule text `Server:565-568` |
| D2 | `E2E_ENCRYPTION.md` section 8 (API table) lists `e2e.sync.pending/page/put/done` but **not** `e2e.sync.approved`. | The action exists, is rate limited (60 per 10 minutes) and is allowed for signed-in users. It only writes a record. | `Server:374-379`, `connectum-backend/src/core/sd_cmds.erl:172` |
| D3 | `E2E_HISTORY_SYNC_MOBILE.md` ("The story, for the person") and the web card tell the person: "Signing in there signs you out here, so sign in here again afterwards." | That is only true for two devices of the **same kind** (two laptops, or two phones). A phone and a laptop each have their own session slot, so signing in on one does not sign the other out. The same file's "Sessions" section says this correctly; its story and the web text are from the one-session time. | `connectum-backend/src/security/sd_auth.erl:157-167`, `Prompt:119` |
| D4 | `E2E_HISTORY_SYNC_MOBILE.md`: "The web app does exactly this ... its texts are good to copy." | The web never calls `e2e.sync.approved`, so the server never records that the person pressed Approve. Mobile may call it (optional). | no caller in `chat-app` outside `Client` (search for `sync.approved` finds only the server and docs) |
| D5 | The comment on `removeThisDevice()` says it is for "sign-out on a shared computer, or reset" (`Client:118`); `E2E_ENCRYPTION.md` says only that clearing site data removes the keys. Neither says plainly what sign-out does. | The web **never deletes the device keys on sign-out**. `removeThisDevice()` exists in `Client` but nothing in the app calls it. Keys leave the browser only through the lock dialog's "Remove" on the current device, or clearing site data. | `Client:119-124` (defined), `Badge:73-76` (the only removal), `chat-app/features/connectumChat/components/ConnectumAuthScreen.jsx:234-237` (sign-out does not touch keys) |
| D6 | `E2E_ENCRYPTION.md` section 5 and the error text say the mode is per **organisation** ("not switched on for this organisation"). | The mode is one server setting, read from the environment for the whole backend (`CONNECTUM_E2E`: off, optional, required). I found no per-organisation switch in `sd_e2e.erl`. | `Server:46-51`, `Server:436` |

Everything else I checked in these files matched the code.

---

## 1. Key lifecycle: which keys exist, where they live, what removes them

### 1.1 The keys

| Key | Made by | Made when | Stored where, in what form | Leaves the device? |
|---|---|---|---|---|
| **Device ECDH key pair** (P-256) | the device | first sign-in on this browser/phone | IndexedDB database `connectum-e2e`, object store `device`, one record per signed-in user; the private key is a **non-extractable** CryptoKey; the public half is also kept as base64url | public half goes to the server (`e2e.register`); private never |
| **Device signing key pair** (ECDSA P-256) | the device | same moment | same record, also non-extractable | public half to the server; private never |
| **Device id** | the device | same moment | in the same record; 32 hex characters | public (it is in every envelope) |
| **Pins** (first-seen public keys of other people's devices) | the device | when it first sees a device | IndexedDB object store `pins`, key `user\|deviceId` | never |
| **Recovery key pair** (ECDH + ECDSA, extractable once) | the device, only if the person turns recovery on | at "Turn on recovery" | public halves registered on the server as one more device flagged `recovery`; private halves exist as a **sealed blob** on the server (see section 5); when a code opens it on a browser, the private ECDH half is stored non-extractable in IndexedDB store `recovery` | the sealed blob goes to the server; the opened key stays on the device |
| **Recovery code** (26 characters) | the device | at "Turn on recovery" | **not stored anywhere**; shown once | never sent |
| **Message key** (AES-256-GCM, one per message) | the sender's device | at send | exists only inside the boxes of the envelope (and in memory while sending/reading) | only as wrapped boxes |
| **Box / wrap** (message key locked for one device) | the sender (normal), or an older device / the recovery key (later, for history) | at send, or at hand-on | inside the envelope's `keys` on the server; later boxes in a separate server store | yes, but only openable by the device they are for |
| **Attachment key** (AES-256-GCM, one per file) | the sender's device | at upload | inside the **encrypted message text** (the attachment tag), not in the file | only inside an encrypted message |

Pointers: key generation `Crypto:49-53`; store layout and database name `Store:8-9` and `Store:30-40`; what a device record holds `Store:4-6`; recovery pair `Crypto:105-109`; code `Crypto:80-88`; message key `Crypto:205`; attachment key `Crypto:286-292`.

There is **no per-conversation or per-group key**. A group message is one envelope with one box per device of every member (up to 250 boxes). `Server:30-33`, `Crypto:197-219`.

### 1.2 What the server keeps

- The **device registry**: for each person, a hash of their devices (id, public ECDH key, public signing key, label, creation time, `seen` time, flags `late`, `recovery`, `backedUp`, `xw`, `approvedTs`). `Server:62-66`, `Server:108-118`.
- The **recovery blob** (sealed private half of the recovery key) per person. `Server:37`, `Server:237`.
- **Later boxes** for history, one entry per message id and device. `Server:38`, `Server:581`.
- It never holds a private key, a message key or a recovery code. `Server:4-8`.

### 1.3 What is lost when

| Event | Device keys on the device | Server registry | What the person loses |
|---|---|---|---|
| **Sign out** (web) | **kept** (nothing deletes them) | device stays registered | nothing; signing in again on the same browser re-uses the same device (case e) |
| **Session replaced** by another sign-in of the same kind | kept | kept | nothing; the connection is closed and the person must sign in again (`Socket` receives `session_replaced`, web calls `forceSignOut`, `chat-app/features/connectumChat/chatEvents/connection.js:96-99`) |
| **"Remove" on this device** in the lock dialog | deleted (`Client:131-136` calls `e2e.remove`, then deletes the local record) | device deleted | this browser becomes a brand-new device the next time the person signs in (it will wait for history) |
| **"Remove" on another device** in the lock dialog | untouched on that device; on its next `init` it sees the server no longer lists it and **deletes its own keys** (`Client:58-61`) | device deleted | that other device loses its keys on next start |
| **Clear site data / private window / browser tidy-up** | gone | stays registered as a dead device until unused for 30 days (replaced when the person is at the 10-device limit) | the browser is a new device; old messages show as unreadable there; the dead device lingers (`Server:81-86`, `Server:149-156`) |
| **Uninstall a phone app** | depends on the mobile implementation; the web equivalent is "clear site data" | the same dead-device behaviour | same as above |
| **Turn off recovery** | the recovery private key is deleted from this browser (`Client:175-179`) | recovery key and blob deleted | the code opens nothing; boxes made for the recovery key are never served again (`Server:254-264`) |

The browser asks for "persistent storage" so it is less likely to tidy the keys away (`Client:80-88`). The result only appears in the status (`persisted`); no screen shows it.

---

## 2. A new device, step by step

### 2.0 What happens at sign-in, in every case

```
Device -> Server: (WebSocket opens, `welcome` arrives)                          Socket:299
Device -> Server: e2e.status {id?}   (id only if this device already has keys)  Client:51
Server -> Device: {mode, devices:[...with `late`], maxDevices, recovery}        Server:327-330
```

Then `Client.init` decides (`Client:45-78`):

1. `mode` is `off`: stop. Nothing else happens.
2. This device has local keys, but the server no longer lists its id: delete the local keys and treat the device as new (`Client:58-61`).
3. No local keys: refuse if the person already has 10 non-recovery devices (`Client:65`; the server would also try to replace a device unused for 30 days, `Server:149-156`, but the web checks the count first, see Open questions Q3), else make keys and register.
4. `late` is true if this device was just registered and the person already had a non-recovery device (`Client:70`), otherwise the server's `late` flag for it.

Registration:

```
Device -> Server: e2e.register {id, ecdh, sign, label, proof}                  Client:112
   proof = ECDSA signature by the new signing key over
           "connectum-e2e-register|<user>|<id>|<ecdh>|<sign>"                  Crypto:71-74
Server: checks id (32 hex), both keys are 65-byte uncompressed P-256 points,
        the proof verifies, and < 10 devices (or one unused for 30 days)       Server:129-159
Server -> Device: {device}                                                      Server:351
Server: stores it (late=true if the person already had a device), tells the
        person's other devices `e2e_devices_changed`, writes audit
        `e2e.device_added`, and (only if there was an older device) puts
        "A new device was added to your encrypted messages" in the person's
        notification panel                                                      Server:160-168, 120-125, 177
```

Rate limit: 30 registrations per hour per person (`Server:347`).

### 2.a First device ever

```
New device -> Server: e2e.status                 -> {mode:"optional"|"required", devices:[]}
New device -> Server: e2e.register {...}         -> {device}      (no `late`: the person had none)
```

- The device is **not late**. There is no past to hand on: no earlier device could have been a recipient (`Server:163`, `Client:70`).
- Messages sent to the person **before** this moment have no box for it. They show "sent before this browser was set up" (text in section 7). In `optional` mode, people who wrote to the person before they had a device sent plain text, which the person can read normally (plain text is accepted in `optional`, `Server:439`).
- No alert is sent for a first device (`Server:177-178`).

### 2.b Second device while the first is online

```
New device -> Server: e2e.register {...}                  -> {device}; stored with late=true
Server -> Older device(s): event sd_event e2e_devices_changed {user}
Server -> Person's feed:   security item "A new device was added ..." (all devices)
Older device -> Server: e2e.sync.pending                  -> {waiting:[{id,label,ts}], helpers:[...], recovery}
Older device: shows the Approve card (section 3)
New device: shows "Your earlier messages are not shown here yet" and asks e2e.sync.pending
            every 30 seconds while it is late                                   Socket:26, 389
```

What the new device can read **at once**: every message sent after its registration, because every sender must wrap for all devices that exist when they send (the server refuses otherwise, `e2e_stale_devices`, `Server:497-520`). What it cannot read: everything earlier; each such message shows the placeholder (section 7).

### 2.c Second device while the first is offline

Same as 2.b, but nobody can approve. The new device keeps asking `e2e.sync.pending`:

- `helpers` lists the person's other devices **seen in the last 30 days** (`Server:558-563`). If any exists, the new device tells the person to sign in on it (web text `Prompt:112-119`).
- If none was seen in 30 days, the new device says so and points to the recovery code (`Prompt:120`).
- As soon as the older device comes online, signs in and the person approves, the job runs (section 3). There is **no expiry** for the offer: it stays until the person answers or removes the device (`E2E_HISTORY_SYNC_MOBILE.md`, "Sessions: exactly what happens"; no timer exists in `Server` or `Prompt`). A waiting device nobody has used for 30 days simply stops being listed (`Server:558-563`).

### 2.d The person has only one device and lost it

```
New device -> Server: e2e.register {...}   -> the person had NO non-recovery device left,
                                               so this one is not late             Server:163
```

- Nobody can hand the past on. The only way back is the **recovery code** (section 5), and it brings back earlier messages **only if the backup was finished** before the loss.
- Without recovery, earlier messages cannot be read again (`E2E_ENCRYPTION.md` section 6, consistent with the code: no other key exists).
- The lost device stays in the registry as a dead device. Every sender must keep wrapping for it (the server demands a box for every device that exists), until the person removes it or it is replaced after 30 days of no use at the 10-device limit.

### 2.e Signing in again on the same device

```
Device -> Server: e2e.status {id: <my id>}  -> devices includes my id
Device: loads its stored keys (IndexedDB), no new registration                   Client:50-68
```

- The same device id and keys are used. No new alert, not late, nothing to sync.
- `e2e.status` with the id updates the device's "last seen" at most once an hour (`Server:89-106`, `Server:328`). This is what stops an active device being treated as dead.
- If the server no longer lists this id (removed from elsewhere) the device deletes its keys and registers anew (case 2.b).
- A key that cannot be loaded (private window, cleared data) means case 2.b or 2.d.

---

## 3. History sync from an older device

### 3.1 Who does what, in order

Roles: **N** = the new (waiting) device, **O** = an older device of the same person that is signed in and has keys.

```
N -> Server: e2e.register                               (N becomes late)
Server -> O: sd_event e2e_devices_changed
O -> Server: e2e.sync.pending            <- {waiting:[N], helpers:[...], recovery}   Client:189-197
O: shows card "Show your earlier messages on <N label>?"   Approve | That is not me | Later   Prompt:96-107
  -- person presses Approve --
O -> Server: e2e.sync.approved {device:N}          OPTIONAL, web does not call it   Server:374
O -> Server: e2e.devices {users:[me]} (fresh)     <- my devices incl. N's public ECDH key   Client:240
loop until `next` is null:
  O -> Server: e2e.sync.page {cursor?}            <- {items:[{id,text}], next}      Client:256
  for each item:
      if the envelope already has a box for N: count `already`, skip              Client:260
      else open O's own box; make a new box for N with a one-time key; add to batch   Crypto:234-243
      if batch has 400: O -> Server: e2e.sync.put {device:N, items:[{mid,iv,w,ek}]}   Client:263, 248
  flush the rest with e2e.sync.put                                                 Client:269
O -> Server: e2e.sync.done {device:N}             <- {done:true}                    Client:277
Server -> N: sd_event e2e_devices_changed
N -> Server: e2e.sync.pending / e2e.status       <- N no longer late               Socket:371-391
N: drops its saved copy of the conversations once and reads them again            Socket:383-386
```

### 3.2 What is exchanged and the limits

- **Batch size:** the client sends 400 boxes per `e2e.sync.put` (`Client:9`); the server accepts 1 to 500 (`Server:39`, `Server:574`).
- **Page size:** `e2e.sync.page` returns up to 400 messages per answer (default), ending after the store page that reaches the limit, so a page can hold somewhat more (`Server:40`, `Server:623-636`). The setting `CONNECTUM_E2E_SYNC_PAGE` changes it (`Server:604`).
- **Rate limits per person:** `e2e.sync.put` 400 calls per 10 minutes (`Server:363`); `e2e.sync.page` 600 calls per 10 minutes (`Server:369`); `e2e.sync.approved` 60 per 10 minutes (`Server:376`). `e2e.status`, `e2e.sync.pending`, `e2e.sync.done` have no limit of their own (`Server:327`, `Server:360`, `Server:373`).
- **What O re-wraps:** only **message keys**. For each end-to-end message it can open, O makes one new box for N: ECDH between a fresh one-time key and N's public ECDH key, HKDF-SHA-256 with `salt = mid`, `info = "connectum-e2e-wrap|<N id>|<ORIGINAL sender device id>"`, then AES-256-GCM with additional data `e2e1-wrap|<mid>|<N id>`. The box is `{mid, iv, w, ek}` where `ek` is the new one-time public key. `Crypto:173-195`, `Crypto:234-243`.
- **Conversation keys:** do not exist (section 1.1), so there is nothing to re-wrap besides message keys.
- **Attachment keys:** are **inside** the message text, so they come along when the message key is re-wrapped. O does not touch attachments or their files. `Crypto:286-292`, `E2E_ATTACHMENTS.md` "The attachment tag".
- **Rewrap vectors:** `docs/e2e-test-vectors.json` sections `rewrap` (positive and negative) and `lateBox`, checked by `tools/e2e-kit/e2e-rewrap.mjs` and `tools/e2e-kit/e2e-check.mjs`.
- **How N stores the result:** the server stores each box under the message id and N's device id (`sd:e2e:xw:<mid>`) and marks N with `xw`; N stores nothing itself. When the server serves any envelope to the person it adds N's later box to `keys[N]` for N only (`Server:581-582`, `Server:680-705`). N opens a box that has its own `ek` using that `ek` (`Crypto:223-227`). The sender's signature does not cover `keys`, so it still verifies.
- **Which messages O hands on:** the person's own direct chats and groups in a fixed order, newest first, **without** deleted messages, plain text, forms, groups the person left, and what the person cleared (`Server:595-636`, `Server:608-611`).

### 3.3 The Approve prompt (older device)

- **Text** (web, `Prompt:99-100`): title "Show your earlier messages on {device name}?"; body "This device was just added to your account. If it is yours, approve it and your earlier messages will appear there. If you do not recognise it, remove it." Buttons: **Approve**, **That is not me**, **Later** (`Prompt:102-104`).
- **When it appears:** whenever `e2e.sync.pending` has a waiting device other than this one that the person has not dismissed with Later in this page session (`Prompt:92-93`). It is re-checked on start, on the `e2e_devices_changed` event, and after each action (`Socket:371-391`, `Socket:473`).
- **Who can approve:** any device of the same person that is signed in with keys. The server cannot tell an approval from the device's own call, so it is the app's rule, not a lock (`Server:542-548`, `Server:642-643`).
- **Expiry:** none. "Later" only hides the card until the page is reloaded (`Prompt:18`, `Prompt:104`).
- **"That is not me":** asks once more ("Remove it now"), then `e2e.remove` of that device (`Prompt:60-65`).
- **While running:** "Showing your earlier messages on {device}", "N messages done. Keep this window open until it finishes.", a **Stop** button (`Prompt:74-77`). At the end "All set / Your earlier messages are now on {device}." for 6 seconds (`Prompt:79`, `Prompt:11`). On failure "Could not finish" with the message, **Try again**, **Close** (`Prompt:80-86`).

### 3.4 What the new device's person sees while waiting

- Card "Your earlier messages are not shown here yet" with the names of up to two helper devices (`Prompt:111-120`), a **Got it** button that hides it for this page session (`Prompt:123`), and, if recovery is on, "Enter recovery code" (`Prompt:122`).
- New messages open normally; older ones show the placeholder text (section 7).
- Polling every 30 seconds while late (`Socket:26`, `Socket:389`).

### 3.5 Cases

| Case | What the code does | Evidence |
|---|---|---|
| **Cancel** (Stop) | `AbortSignal` is checked between pages; the job throws `aborted`; the card shows "Stopped." with Try again. Boxes already stored stay; N stays late. | `Client:255`, `Prompt:56` |
| **Timeout** | There is no timeout in the job. A network call that never answers would hang until the socket's own request timer fails it (see `Socket` `pendingSd`). I did not find a job-level timer. | `Client:205-280` (none) |
| **Resume after interruption** | Run Approve again: it reads from the start, **skips** messages whose envelope already shows a box for N (`already`), rewrites nothing else needed, and finishes with `done`. A repeated `put` for the same message replaces the earlier box. | `Client:260`, `Server:581` |
| **Two new devices at once** | Each is late. The card offers the first one that is not dismissed; after it finishes `pending` is checked again and the next card appears. While a job runs the card shows only that run (one at a time per device). | `Prompt:67-90`, `Prompt:92` |
| **Two older devices both approve** | Both write boxes. The first to call `done` ends the waiting. The second device's next `put` gets `not_waiting`, which the client treats as "another device finished" and stops quietly. | `Client:249-250`, `Client:275` |
| **Older device is a phone app** | Nothing in the server depends on the kind of device. The phone must implement the same job (section 9). The server only cares that it is a registered device of the person. | `Server:549-563` |
| **Older device goes offline mid-sync** | A failing `sd` call throws; the web shows "Could not finish" with the message and Try again. Stored boxes stay, N stays late. Because of the one-session-per-kind rule, a new sign-in of the same kind as O ends O's session mid-job and the job stops. | `Client:244-253`, `Prompt:80-86`, `sd_auth.erl:157-167` |
| **How large a history** | The server walks every conversation the person has. The only hard numbers are the batch and rate limits above: at 400 boxes per call and 400 calls per 10 minutes that is up to about 160,000 boxes per 10 minutes per person; reading is capped at 600 page calls per 10 minutes. A box is about 200 bytes of server storage per message per device shown the past (`E2E_ENCRYPTION.md`). I did **not** find a documented or tested maximum history size, or a measurement of how long the cryptography takes per message. | `Server:363`, `Server:369` |

---

## 4. Messages sent from another device

**Question:** is a message sent from device A encrypted to the sender's other devices at send time, or readable on device B only through history sync?

**Answer:** it is wrapped for the sender's **other devices that exist at send time**. `Client.#plan` fetches the person's own devices fresh, removes this device from the list and adds it back, so the sender's other devices get a box (and the sending device gets its own box) (`Client:343-347`). The server **requires** a box for every device that exists now, except the sending device, and refuses the message otherwise with `e2e_stale_devices` (`Server:497-520`).

```
A (sending device) -> Server: e2e.devices {users:[bob, me]} (fresh)
A: wraps for Bob's devices, A itself, and my device B (if B is registered now)
A -> Server: /msg bob e2e1:{...keys:{bob-dev, A, B}}
Server: refuses if any existing device has no box (e2e_stale_devices), else stores
B: reads it immediately (it has its own box)
```

- If device B **did not exist yet** when A sent, there is no box for B. B can read that message only after a history sync from A (or another device that has a box), or after recovery (section 5).
- The web gives the sender a box for itself too, although the server would allow leaving it out (`Client:347`, `Server:492-495`).

---

## 5. Recovery code and key backup

**Does it exist?** Yes, it is built and live on the web. `E2E_ENCRYPTION.md` section 6a and `E2E_HISTORY_SYNC_MOBILE.md` ("Backup and restore") describe it and the code agrees. It is opt-in.

### 5.1 What it protects

- Everything sent **after** recovery is switched on (each message also has a box for the recovery key).
- Earlier messages that a device **backed up** by wrapping them for the recovery key (`Client:212-220`).
- It does **not** cover a message that no device of the person could open when the backup ran, and does not cover what the person cleared (`Server:595`).
- If every device and the code are lost, nothing can be recovered.

### 5.2 Creating it

```
Device: makes a recovery key pair (ECDH + ECDSA, extractable), a 26-char code,
        a random id                                                       Client:144-148, Crypto:84-88
Device: seals the private halves with a key derived from the code:
        HKDF-SHA-256(ikm = the 26 chars, salt = 16 random bytes,
        info = "connectum-e2e-recovery|<user lower case>|<id>")
        -> AES-256-GCM, aad = "e2e1-recovery|<user>|<id>", 12-byte iv      Crypto:97-117
Device -> Server: e2e.recovery.set {id, ecdh, sign, proof, blob:{v:1,salt,iv,ct}, replace?}
        proof = same registration proof as a device                        Client:150
Server: stores the public halves as one more device flagged `recovery`
        and keeps the blob; limits: salt <= 64, iv <= 32, ct <= 4096 chars;
        10 calls/hour; a second one needs replace:true                      Server:210-244, 331-336
Device: shows the code ONCE; starts the backup of earlier messages          Badge:99-101
```

The code alphabet is `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 26 characters in groups of five (130 bits). Input is accepted in any case, with or without dashes and spaces (`Crypto:80-95`).

### 5.3 Verification

There is **no separate verification step** (no "type the code again to confirm"). The person sees "I have saved it" after the code is shown (`Badge:179`). The first proof the code works is a restore. This is a gap worth knowing (open question Q5).

### 5.4 Backup of the past

Same job as history sync with the recovery key as the **target** (`Client:212-220`), `e2e.sync.done` marks it complete (`backedUp: true`, `Server:661-662`). `e2e.sync.pending` reports `recovery: {id, backedUp}` (`Server:552-556`). A new code (replace) starts again with nothing backed up (`Client:152`).

### 5.5 Using the code on a new device

```
New device -> Server: e2e.recovery.get   (30/hour)   <- {recovery:true, id, ecdh, sign, blob}   Client:164, Server:337-342
New device: normalise the code (26 chars, else bad_code), derive the key,
            open the blob (wrong code -> wrong_code), import the private halves
            as NON-extractable keys, keep the ECDH one in IndexedDB             Client:163-170
New device: restore: for each message open with the recovery key, make a box for
            THIS device, e2e.sync.put {device: me}, e2e.sync.done {device: me}  Client:227-235
```

- `e2e.sync.put` accepts this because the **only** device of a person is a valid target even when not late (`Server:565-568`, `Server:578`), and because a recovery key target is allowed while not backed up.
- If there are messages but the recovery key opens none, the device is **not** finished: error `nothing_restored`, text "Your recovery code does not open any earlier message: they were not backed up for it." (`Client:225`, `Client:232`).
- After a restore the device no longer needs the code.

### 5.6 Does the server ever see the code?

No. The code is never sent. The server holds the sealed blob and the public keys. Someone with **both** the server's database and the code could open it (`E2E_ENCRYPTION.md` 6a, consistent with `Server:197-204`).

### 5.7 Test vector for the mobile team

It exists: `docs/e2e-test-vectors.json`, section `recovery`. It has a fixed (fake) code, the user and id, the sealed copy in the exact shape `e2e.recovery.get` returns (`blob.salt`, `blob.iv`, `blob.ct`), the HKDF `info` and `aad` strings, the expected plaintext JSON `{e, s}`, and a `mustRefuse` list; `steps` writes the four steps in order. It was made by `tools/e2e-kit/make-recovery-vectors.mjs`. I read its field names but did not re-run the generator.

**What is still missing** (nothing in the repository covers it): a vector for **generating** a recovery code (it is random, so only the alphabet and length can be tested), a vector for `safetyNumber`, and a vector for the "backup then restore through the server" round trip other than the server test suite (`connectum-backend/test/connectum_e2e_backup_test.mjs`).

---

## 6. Groups and attachments in this scenario

### Groups

- **200-member limit:** `e2e.group_devices` refuses a group of more than 200 members with `limit` and the text "Groups of more than 200 people cannot use end-to-end encryption yet." (`Server:33`, `Server:406-407`). An envelope may carry at most 250 boxes (`Server:31`, `Server:478`).
- **What the web does with a group over 200:** `Client.#groupDevices` turns the server error into an `E2EError`, which `sendProtected` reports as a failed send and does **not** fall back to plain text (`Client:299`, `Socket:418-423`). So such a group cannot send from the web at all while the mode is not `off`. See Q2.
- **Members added later:** a new member's devices are looked up fresh at the next send, so new messages open for them. Earlier group messages have no box for them; the server's history for the person is narrowed to boxes they have, and the placeholder shows. Handing on only covers the **same person's own** devices, never a new member (`Server:565-568`).
- **Members removed:** the removed member's devices no longer appear in `e2e.group_devices` (`Server:408-409`), so later messages are not wrapped for them. A message that still carries a box for a device that is no longer in the conversation is refused with `e2e_stale_devices` (`Server:502-503`). Messages they already received stay readable on their devices; nothing in the code deletes keys or messages they hold.

### Attachments on a new device

- The file is stored on the server encrypted with a key that lives **in the message text** (`E2E_ATTACHMENTS.md`, "The attachment tag"). When a history sync re-wraps the message key, the new device can open the message, read the tag, download the blob and decrypt it. So **yes, a new device can open old attachments** once it can open the message.
- The web caches decrypted files in memory by URL and key (`chat-app/features/connectumChat/e2e/e2eMedia.js:85-99`); the cache is lost on reload, so the file is downloaded and decrypted again.
- Files are not re-uploaded or re-encrypted by a hand-on.
- Server retention of uploaded files (are old blobs deleted?) is outside what I traced; see Q7.

---

## 7. Edge cases and errors

### 7.1 Events and codes

| Situation | Code / event | Who raises it | What the web does |
|---|---|---|---|
| Device not in server list | (none; `e2e.status` simply lacks the id) | server | deletes local keys, registers anew (`Client:58-61`) |
| More than 10 devices | client message "This account already has 10 devices; remove one in Settings first."; server `limit` "At most 10 devices per person: remove one first." | client first, then server | init fails; E2E is unavailable on this device until a device is removed (`Client:65`, `Server:158`) |
| Too many registrations | `rate_limited` "Too many device registrations; try again later." | server | init fails (`Server:348`) |
| Registration proof wrong / bad ids or keys | `invalid` with a specific message | server | init fails (`Server:134-139`) |
| Device id already registered with other keys | `conflict` | server | init fails (`Server:147`) |
| **No key for this message** | decrypt failure `not_for_this_device` | client | placeholder text below (`Crypto:268`, `Socket:33`) |
| Sender's device unknown | `unknown_sender_device` | client | placeholder (`Crypto:270`, `Socket:38`) |
| Sender's key changed | `key_changed` + event `e2e_key_changed` | client | placeholder + toast (`Client:368-371`, `Socket:34`, `connection.js:42-45`) |
| Bad signature | `bad_signature` | client | placeholder (`Crypto:271-272`) |
| Message for another conversation | `wrong_conversation` | client | placeholder (`Crypto:266`) |
| Damaged | `decrypt_failed` / `bad_payload` | client | placeholder (`Crypto:280`, `Client:398`) |
| Encryption not ready | `no_device` | client | placeholder (`Client:387`, `Socket:36`) |
| **Session replaced** | event `sd_event session_replaced`, then the connection closes with reason `signed_in_elsewhere` | server | forced sign-out; keys stay (`chat_web.erl:409-410`, `connection.js:96-99`) |
| **Device removed** | `e2e.remove` -> `{removed:true}`; other sessions get `e2e_devices_changed`; the removed device deletes its keys on its next `init` | server / client | (`Server:191-195`, `Client:58-61`) |
| **Sync rejected** | `not_waiting` ("That device is not waiting for its earlier messages."), `not_found` ("No such device of yours."), `invalid` (bad items, 1 to 500) | server | `not_waiting` on `put`: the client stops quietly (`Client:249-250`); others show "Could not finish" (`Prompt:80-86`) |
| **Rate limited** | `rate_limited` with texts such as "Too many history uploads; try again in a moment." | server | shown as the job error; the person can press Try again (`Server:364`, `Server:370`) |
| Recovery code typed wrongly | `bad_code`: "A recovery code has 26 letters and numbers, for example ABCDE-FGHJK-LMNPQ-RSTUV-WXYZ2-3." | client | note in the lock dialog (`Crypto:93`, `Badge:117`) |
| Recovery code does not open the key | `wrong_code`: "That code does not open the recovery key. Check it and try again." | client | note (`Crypto:128`) |
| Recovery not on | `no_recovery` | client/server | note (`Client:166`, `Server:257`) |
| Too many recovery lookups | `rate_limited` "Too many attempts; try again later." | server | note (`Server:339-340`) |
| Send refused: stale device list | event `{type:"error", code:"e2e_stale_devices", text, mid, conv, users}` | server | resends by itself up to twice, silently (`chat-app/services/e2eRetry.js:4-33`, `Socket:310`) |
| Send refused: no key for the other person | `e2e_peer_not_ready` "These people have not set up secure messaging yet: ..." (in `required`; in `optional` the web sends plain) | server/client | send marked failed + toast (`Server:507-508`, `Client:349-351`, `connection.js:53-57`) |
| Other send refusals | `e2e_disabled`, `e2e_required`, `bad_envelope`, `too_long`, `e2e_unsupported` | server | send marked failed + toast with the server's text (`Server:431-438`, `connection.js:53-57`) |

### 7.2 The exact texts shown for a message this device cannot open

From `Socket:29-40`:

- `not_for_this_device`: "🔒 Sent before this browser was set up for encryption, so it can't be opened here. Approve this device on another device you already use and it will show here, or open it on the device you used then, or enter your recovery code under the lock at the top of a chat (if you switched recovery on before it was sent)."
- `key_changed`: "🔒 This sender's security key changed. Check the safety number before trusting new messages."
- `bad_signature`: "🔒 This message could not be verified and was hidden."
- `no_device`: "🔒 Encryption is not ready on this device yet. Reload the page or sign in again."
- `unknown_sender_device`: "🔒 The sender's device is not known yet. Reload the page to try again."
- `decrypt_failed`: "🔒 This message is damaged and could not be opened."
- `wrong_conversation`: "🔒 This message does not belong to this conversation and was hidden."
- `bad_payload`: "🔒 This message could not be read."
- anything else: "🔒 This message can't be read on this device."

The "sent before this browser" text says "browser" even on a phone, and it still says "Approve this device on another device you already use"; the mobile app should word it for a phone.

---

## 8. Security properties

- **What the server can see:** who talks to whom and when, sizes, which devices exist (ids, labels, public keys, last seen), group membership, the later boxes' existence, audit events (`e2e.device_added`, `e2e.device_removed`, `e2e.history_shown`, `e2e.history_approved`, `e2e.recovery_on`, `e2e.recovery_off`), and the sealed recovery blob. It cannot read message text, attachments' contents or their names/types (`Server:13-15`, `E2E_ATTACHMENTS.md`).
- **What it cannot do alone:** open a message or a box (it holds no private key), forge a message "from" someone (signatures are checked by readers), or move a box to another device (the device id is bound in the key derivation and the additional data, `Crypto:169-176`).
- **What a malicious server could do:** add a device to a person. The defences are the new-device alert to the owner (`Server:177`), the app's "added a new device" notice for contacts (`Client:38-42`, `connection.js:47-51`), key pinning (`Client:305-317`) and the safety number. The history approval is also an app rule, not a server lock (`Server:642-643`).
- **A stolen session without the device:** it can register a **new** device (new keys), which becomes `late`. It cannot read earlier messages unless an older device of the person is tricked into approving, or the person's recovery blob and code are both known. The owner sees "A new device was added" in their notifications and in the lock dialog and can press "That is not me". It can fetch the sealed recovery blob (rate-limited, 30/hour) but cannot open it without the code (`Server:337-342`).
- **The device without the session (a stolen, unlocked browser profile):** the keys are non-extractable but usable by page code while the page is open; a signed-out browser still holds the device keys (D5), so anyone who can sign in as the person (or already has a session) on that browser reads new messages and, with the keys, history that has boxes for that device. The server requires a valid session for every call, so without a session the keys cannot fetch anything. I did not test this scenario.
- **"One active session per person":** it is really one session per **kind** of client (a phone and a laptop). A new sign-in of the same kind ends the old one. It does not remove keys or devices; its security value is that a second sign-in is noticed (feed item `session_replaced`, and `session_added` for the other kind) (`sd_auth.erl:157-182`). It also means the older device doing the hand-on must stay signed in throughout (section 3.5).
- **Forward secrecy** is limited, as `E2E_ENCRYPTION.md` says: a device's long-term private key opens every message wrapped for it. The code has no ratchet (`Crypto:197-219`).

---

## 9. What mobile must implement (checklist, in build order)

Everything uses the existing `/sd` WebSocket calls. Each step has its test.

1. **Keys and storage.** Make an ECDH P-256 pair and an ECDSA P-256 pair, a 32-hex device id; store the private keys in the platform's secure, non-exportable store; remember the device id. Do **not** delete the keys when a session ends. *Test:* `registration` vector in `docs/e2e-test-vectors.json` (`Crypto:71-74`).
2. **Register** with `e2e.register` and the proof. Handle `limit`, `rate_limited`, `conflict`, `invalid`. Send the device id in `e2e.status {id}` at every start so "last seen" stays fresh. *Test:* `tools/e2e-kit/e2e-check.mjs proof input.json`.
3. **Read an envelope**, including a box with its own `ek` (use it instead of the envelope's). *Tests:* vectors `envelope` and `lateBox` with `tools/e2e-kit/e2e-check.mjs envelope input.json`.
4. **Send an envelope** wrapped for every device that exists **now** (call `e2e.devices` fresh for each message), resend on `e2e_stale_devices` by `mid` at most twice. *Tests:* the web's `tests/frontend/e2eCrypto.test.mjs`, the kit checker, `e2e-message-marks-replies.json`.
5. **States and screens needed:**
   - **New device waiting:** `e2e.status` says this device `late` -> card "Your earlier messages are not shown here yet", helper names from `e2e.sync.pending`, poll about every 30 seconds and on `e2e_devices_changed`, "Enter recovery code" if recovery is on.
   - **Approve on an older device:** a card per waiting device with Approve, "That is not me" (ask twice, then `e2e.remove`), Later.
   - **Sync progress:** "N messages done", Stop.
   - **Sync failed:** message, Try again, Close.
   - **Nothing to sync:** an empty history still ends with `e2e.sync.done`.
   - **Placeholders** for unreadable messages, in the phone's own words (section 7.2).
6. **Hand-on job (older device):** `e2e.sync.pending` -> optional `e2e.sync.approved` -> `e2e.devices {users:[me]}` -> loop `e2e.sync.page` -> rewrap each message (skip those that already have a box for the target) -> `e2e.sync.put` batches of up to 400 -> `e2e.sync.done`. Treat `not_waiting` on `put` as "somebody else finished". Keep the session alive; on a rate limit wait and retry the same batch. *Tests:* vectors `rewrap` (positive and negative) with `tools/e2e-kit/e2e-rewrap.mjs`; the stand-in new device `tools/e2e-kit/new-device.mjs` (see `E2E_HISTORY_SYNC_MOBILE.md`, "Testing the two-device flow with one phone").
7. **After the older device finishes (new device):** drop any saved copy of the conversations once and read them again; remember "was waiting" across a restart (web: a flag per device, `Socket:379`, `Socket:383`). Without this the grey lines stay.
8. **Sessions:** send `"client": "mobile"` at sign-in so a phone does not end the laptop's session (`sd_auth.erl:150-153`, the doc `E2E_HISTORY_SYNC_MOBILE.md` "Sessions").
9. **Recovery (if mobile offers it):** generate the code and keys, seal, `e2e.recovery.set`, show the code once, run the backup, restore flow, "Make a new code", "Turn off". *Test:* the `recovery` vector, section 5.7.
10. **Alerts:** show the "added a new device" notice for contacts and the key-changed warning (`connection.js:42-51`).

---

## 10. Open questions

| # | Question / ambiguity | Recommendation |
|---|---|---|
| Q1 | The Approve card text and the doc story still say "signing in there signs you out here" (D3). | Update `Prompt:119` and the story in `E2E_HISTORY_SYNC_MOBILE.md` for the phone-plus-laptop case; mobile should not copy the old sentence. |
| Q2 | A group over 200 members cannot send at all from the web while the mode is not `off`, even in `optional` mode, because the lookup error is not turned into "send plain" (`Client:299`, `Socket:418-423`). Is that intended? | Decide: refuse with a clear message (what the doc implies), or allow plain in `optional`. State it in the doc. |
| Q3 | The web refuses to register at 10 devices **before** asking the server, although the server would replace a device unused for 30 days (`Client:65` vs `Server:149-156`). | The web's count also includes the recovery key (`mine` is the whole device list), while the server does not count it (`Server:142`, `Server:149`), so a person with 9 devices plus the recovery key is refused by the web (10 entries) but would be accepted by the server. Let the server decide: try to register and show the server's error. |
| Q4 | No expiry and no re-confirmation for Approve; the offer stays for 30 days of device use. | Fine for now; consider a time-limited offer. |
| Q5 | Recovery has no "type the code again" check before the person leaves the dialog. | Add a verify step (mobile can do it first). |
| Q6 | The web never records approval (`e2e.sync.approved`). | Call it from both clients so the audit shows it. |
| Q7 | I did not trace how long encrypted attachment blobs are kept on the server, or whether old ones are deleted. | Ask the backend owner; it decides whether old attachments can still be opened on a new device. |
| Q8 | I found no measured maximum history size or timing for the hand-on. | Run the stand-in device against a large test account and record minutes per 10,000 messages. |
| Q9 | `E2E_FRESH_DEVICES_CHANGE.md` was not read for this document. | Check it against `Server:497-526` before the mobile team relies on it. |
| Q10 | D6: the mode is global to the server; texts say "this organisation". | Decide whether a per-organisation mode is wanted; fix the texts either way. |
