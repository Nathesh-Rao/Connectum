# End-to-end encryption (E2E)

> **New to this?** Read `E2E_SIMPLE_GUIDE.md` first (plain words, and why a person sometimes sees "sent before this browser was set up"). **Building another client (the Flutter app)?** See `E2E_MOBILE_KIT.md` and `E2E_MOBILE_REVIEW.md`: a checker that names the failing step, and reference messages.

What it is, how it works step by step, how to switch it on, and what it does **not** do. Every step has a plain-English line ("In plain
English") so the same page can be used to explain it to someone who is not technical.

**Covered:** text messages, voice notes, photos, videos, files, GIFs and stickers in **direct chats and groups**.
**Not covered:** forms, `#` commands, topic messages for outside people, the AI chat, the global room and host chats. The server has to
read those to do its job (route a form, run a command), so they cannot be end-to-end encrypted.

Code: `chat-app/features/connectumChat/e2e/` (browser), `connectum-backend/src/security/sd_e2e.erl` (server), `chat-app/services/connectumSocket.js` (glue).

---

## 1. The idea

> **In plain English:** today the server can read every message (it stores them, encrypted with a key only the server holds).
> With end-to-end encryption the *phones and browsers* lock the message before it leaves and only the people in the chat can unlock it.
> The server becomes a post office that moves sealed envelopes it cannot open.

## 2. The building blocks

| Piece | What it is | In plain English |
|---|---|---|
| **Device keys** | Every browser/phone makes two key pairs the first time it signs in: one to *receive* secrets (ECDH P-256) and one to *sign* (ECDSA P-256). The private halves never leave the device (the browser marks them non-extractable and stores them in IndexedDB). | Each device gets its own padlock (public, anyone may have it) and its own key (private, never leaves the device). It also gets a personal signature stamp. |
| **Device registry** | The server stores each person's *public* keys only (`e2e.register`, `e2e.devices`). To register, the device proves it holds the signing key. | A phone book of padlocks. Anyone may look up Bob's padlocks. Nobody can put a padlock in Bob's name without proving they hold the matching stamp. |
| **Message key** | For every message the sender's device makes a fresh random AES-256-GCM key and encrypts the text with it. | Every message is locked in its own little safe with a brand new combination. |
| **Wrapping** | That combination is then locked once for **every device of everybody in the chat** (and the sender's own other devices): a one-time ECDH with the device's public key, HKDF-SHA-256, AES-256-GCM. | The combination is copied into one small box per device, each box locked with *that device's own padlock*. Only that device's key opens its box. |
| **Signature** | The sender's device signs the whole envelope (ECDSA). Every reader checks it. | The sender stamps the envelope so nobody (not even the server) can forge a message "from Ann" or change a word. |
| **Envelope** | The text sent to the server is `e2e1:` + JSON: `{v, mid, from, dev, conv, ts, ek, iv, ct, sig, keys:{deviceId:{iv,w}}}`. | The sealed envelope: the safe, the boxes with the combination, and the stamp. |
| **Padding** | The plaintext is padded to a multiple of 64 bytes before encryption. | Short and long messages look similar in size, so "ok" can't be told from a paragraph by its length. |

## 3. Step by step: from typing to reading

1. **First sign-in on a device.** The app creates the two key pairs, sends the *public* halves plus a proof of ownership to the server
   (`e2e.register`), and keeps the private halves in the browser. *In plain English: the device makes its padlock and key, hands out the
   padlock, and keeps the key.* (Up to 10 devices per person; each can be removed in the lock dialog.)
2. **Ann types "hello" to Bob.** The app asks the server for the padlocks of Bob and of Ann's other devices (`e2e.devices`, cached for 5
   minutes and refreshed when the server says someone's devices changed). For a group it asks for every member's padlocks (`e2e.group_devices`).
   *In plain English: look up everyone who needs to be able to read it.*
3. **Lock the message.** Fresh key → encrypt "hello" (with the sender, the conversation and the message id bound in as "additional data",
   so the envelope cannot be replayed into another chat). *In plain English: put the message in a new safe.*
4. **Wrap the key for each device.** One tiny locked box per device. *In plain English: copy the combination into one box per reader device.*
5. **Sign.** The sending device signs the envelope. *In plain English: stamp it.*
6. **Send.** The envelope goes over the normal chat connection as the message text. The server checks only what it can check without
   reading: the envelope is well formed, it names the right sender and conversation, the sending device is really that person's, every
   box is for a real device in this conversation, and **every device that exists now has a box**, except the sending device itself (so no device is silently left
   out). Then it stores and delivers it. *In plain English: the post office checks the envelope is addressed properly, not what is inside.*
7. **Deliver only the reader's boxes.** Each reader is sent the envelope with only the boxes for their own devices. *In plain English:
   you only get your own box, not everybody else's.*
8. **Open.** The reader's device finds its box, derives the box key with its private key, opens the box to get the combination, checks the
   signature against the sender's public signing key, then opens the safe. *In plain English: use your own key, check the stamp, read.*
9. **Previews and notifications.** The server's notification cards and feed carry the same envelope (narrowed to that person). The
   *app* decrypts it and builds the preview ("Ann: hello", "🎙️ Voice note"). *In plain English: the notification text is made on your
   own device, so previews still work but the server never sees the words.*
10. **History.** The same envelope is what the server stores, so history is just step 8 repeated. A device that did not exist when a
    message was sent has no box for it and shows "This message can't be read on this device".

### Voice notes, photos, files, GIFs, stickers

- The app encrypts the **file bytes** on the device (AES-256-GCM, random key) and uploads the scrambled blob (type
  `application/x-connectum-e2e`, saved as `.e2e`). The file's key and iv go **inside the encrypted message** (the usual
  `[ATTACHMENT:{...}]` tag with an `e2e` part). The receiver downloads the blob, decrypts it on the device and plays/shows it from a local URL.
  *In plain English: the voice note is locked before it is uploaded; the key to it travels in the sealed message.*
- **GIFs:** the app downloads the GIF, encrypts and uploads it (so the people in the chat do not contact the GIF provider and reveal
  themselves). If the provider blocks the download, the link travels inside the encrypted message instead.
- **Stickers:** small, so they ride inside the encrypted message itself.
- The GIF *search* (typing a search word) is not encrypted: the server runs it.

### Editing and no downgrade

An edit is encrypted like a new message. The server refuses to let an encrypted message be edited into plain text (`e2e_required`).

## 4. Trust: how Ann knows she is really talking to Bob

- **Signature check** on every message (step 8).
- **Key pinning (trust on first use):** the first time a device's keys are seen they are remembered. If the same device later shows
  *different* keys, the app refuses that device and warns (red lock). *In plain English: like a browser warning that a website's
  certificate changed.*
- **Safety number:** the lock dialog shows a number made from both people's keys. If Ann and Bob read it to each other (in person or on
  a call) and it matches, nobody swapped keys on the way. *In plain English: a fingerprint of the two of you that you can compare out loud.*

## 5. Modes (`CONNECTUM_E2E` on the chat backend)

| Value | What happens |
|---|---|
| `off` (default) | Nothing changes. Envelopes are refused. |
| `optional` | Apps with E2E encrypt automatically. Plain text from old apps is still accepted. If the other person has no device yet, the app sends plain text (nobody is locked out). |
| `required` | Direct and group chat accepts **only** envelopes. Plain text is refused (`e2e_required`). Writing to someone who has no device is refused (`e2e_peer_not_ready`) instead of sending something they could not read. |

Rollout: deploy the new app everywhere → set `CONNECTUM_E2E=optional` and restart → once everyone has signed in on the new app → `required`.

## 6. Limits and what is visible to the server

- **The server still sees metadata:** who talks to whom, when, message sizes, which devices exist, group membership.
- **Recovery is optional, and only covers what comes after you switch it on** (section 6a). Without it, keys live only on devices: if every
  device is lost, older messages cannot be read again, and a device registered later cannot read earlier messages. Multi-device works because
  every message is wrapped for all of a person's devices.
- **Forward secrecy is limited:** every message has its own key and its own one-time ECDH key, but a device's long-term private key can open
  every stored message that was wrapped for it. Signal's Double Ratchet changes keys after every message so that stealing a key today
  does not open yesterday's messages; this design does not.
- **Groups:** one envelope per message, up to 200 members and 10 devices each (250 boxes). Larger groups need a group-key scheme (MLS / sender keys).
- **A malicious server can add a device** for someone; pinning, the safety number and the new-device notice are the defence. The app
  warns when a known device's key changes, and the "devices on your account" list lets you remove unknown devices.
- **Browser limits:** needs HTTPS (or `localhost`) for Web Crypto and IndexedDB. Clearing site data removes the device keys (the device
  re-registers and old messages are unreadable there). A page script that is compromised (XSS) can use the keys while the page is open,
  so keep the app's Content-Security-Policy strict.
- **Not independently audited.** This composes standard primitives (P-256 ECDH/ECDSA, HKDF, AES-GCM) rather than inventing any, but the
  composition is custom. Have it reviewed by a security professional before describing it to customers as end-to-end encrypted in the
  Signal/WhatsApp sense.
- **Server-side at-rest encryption** (`CHAT_ENCRYPTION_KEYS`) still applies on top. The message queue / target database receives the
  envelope (opaque), so the database copy is unreadable too (decision: with E2E on, the target database stores the sealed envelope).
  See `docs/RABBITMQ_MESSAGE_QUEUE.md`. The queue's size limit defaults to 262,144 so the largest group envelope fits.

## 6a. Recovery and backup: getting the messages back when every device is lost

A browser that loses its saved keys (cleared site data, a browser that tidies up, a new computer) becomes a **new device** and cannot open what was
sent before, because every message is wrapped only for the devices that existed. **Recovery** is the opt-in fix, in the lock dialog at the top of a chat. Since 1 November 2026 it **backs up the earlier messages too** (the way WhatsApp's encrypted backup does), so a person who loses every device gets everything back.

> **In plain English:** you get a code, once. Write it down. The app also locks your earlier messages for it (the **backup**, with a progress bar). If you lose every
> device, sign in on a new one, type the code, and **all** your messages come back, and the new device keeps them without needing the code again. The server holds only
> things the code unscrambles, so only you can: not the server, not the company, and no cloud file is involved (the backup sits next to the messages, locked).

How it works (`e2eCrypto.js`: `newRecoveryCode`, `sealRecovery`, `openRecovery`; `e2eClient.js`: `setupRecovery`, `recoverWithCode`, `turnOffRecovery`; `sd_e2e.erl`: RECOVERY):

1. **Turn on.** The app makes one more pair of keys (ECDH + ECDSA), the **recovery key**, and registers its public halves as one more device of the person,
   flagged `recovery`. From then on every message is also wrapped for it (senders do nothing new: it is in the device list like any other). Messages sent
   **before** are backed up in the next step.
2. **The code.** 26 characters from a 32-letter alphabet without look-alikes (no 0, 1, I, O), in groups of five: 130 bits of randomness, made on the
   device and shown **once**. It is never sent anywhere.
3. **The sealed copy.** The recovery key's private halves are encrypted in the browser with a key derived from the code (HKDF-SHA-256 with a random salt,
   AES-256-GCM, bound to the person and the key id) and the result is stored on the server (`e2e.recovery.set`). The server cannot open it, and 130 random
   bits cannot be guessed at offline even from a copy of the database.
4. **Back up the past.** Right after turning on (and any time later with "Back them up now"), a device opens each earlier message with its own key and locks the
   message key again **for the recovery key's public key**, with a fresh one-time key: the same job as showing the past to a new device ("History for a new device"
   below), the recovery key being the target. `e2e.sync.put` stores the boxes, `e2e.sync.done` marks the backup complete. Messages that already have a box for the
   recovery key (sent after it was switched on) are left alone. The server cannot open any of it: the boxes need the recovery key, which needs the code.
5. **Recover and restore.** On a new device the person types the code. The app fetches the sealed copy (`e2e.recovery.get`, rate limited), opens it, and holds the
   recovery key as **non-extractable** keys: every message backed up for it now opens. The app then runs the same job the other way round (`restoreFromRecovery`):
   it opens each message with the recovery key and locks it again **for this device**, so the device reads the past by itself and no longer needs the code. If
   there are messages but the recovery key opens none (a code made again whose backup never finished) it says so and the device keeps waiting.
6. **Change or turn off.** A new code replaces the old one (the old code then opens nothing new, and the new recovery key has nothing backed up until the backup is run
   again); turning off deletes the recovery key and the sealed copy from the server and stops new messages being wrapped for it. The boxes made for a removed recovery
   key are never served again (a few hundred bytes each stay in the store, inert). Recovery switched on **before** this feature shows "not backed up yet" and the same
   "Back them up now" button.

**What recovery does not do** (said plainly in the app):
- It covers what was backed up: **the messages the person's devices could open when the backup ran**, plus everything sent after. A message no device of theirs could
  open (sent before their first device existed) is not part of it. What the person **cleared** is not backed up.
- If **every device and the code are lost, nothing can be recovered.** Nobody, including us, can open them.
- Someone who gets **both** the sealed copy (the server's database) **and** the code can read the messages wrapped for the recovery key. Keep the code private.
- The recovery key is a device of the person, so it appears in the safety number and counts as a recipient; it does **not** count towards the 10-device limit and is
  never removed as unused (`e2e.remove` refuses it; use `e2e.recovery.delete`).
- It weakens nothing about the devices' own keys: they stay non-extractable.

## 7. How it is normally done (and how this differs)

- **Signal / WhatsApp (Signal protocol):** every pair of devices does an *X3DH* handshake (uses one-time prekeys uploaded in advance, so
  it works while the other person is offline), then a *Double Ratchet* derives a new key for every message (forward secrecy and
  "self-healing" after a compromise). Groups use *sender keys* (one key per sender, distributed pairwise). Keys can be backed up with a PIN.
- **MLS (RFC 9420):** the modern standard for groups: a tree of keys that makes adding/removing members efficient and gives forward
  secrecy for groups of thousands.
- **This implementation:** the same ingredients without the ratchet: per-message random key, wrapped separately to every recipient
  device (like PGP / Matrix's early Olm-less design / "sealed box"), plus signatures and key pinning. It is much simpler (no prekeys, no
  per-pair state to get out of sync, trivial multi-device) at the price of forward secrecy and efficiency for large groups.
  The envelope has a version (`v:1`, prefix `e2e1:`) so a ratchet or MLS can replace it later.

## 8. API (WebSocket `/sd`, see `docs/CONNECTUM_API.md`)

| Action | Purpose |
|---|---|
| `e2e.status` | `{mode, devices:[mine], maxDevices, recovery}` (`recovery`: true when a recovery key exists; its device carries `recovery: true`; each device has `late`: still waiting to be shown the past; for the recovery key: its backup is not complete) |
| `e2e.register {id, ecdh, sign, label, proof}` | Register this device (proof = ECDSA signature over `connectum-e2e-register|user|id|ecdh|sign`) |
| `e2e.remove {id}` | Remove one of my devices |
| `e2e.devices {users:[...]}` | Public device keys of people I may message (and me) |
| `e2e.group_devices {group}` | Public device keys of every member of a group I am in |
| `e2e.recovery.set {id, ecdh, sign, proof, blob:{v,salt,iv,ct}, replace?}` | Switch recovery on: register the recovery key (same proof as a device) and keep its sealed private half. A second one needs `replace: true` |
| `e2e.recovery.get {}` | `{recovery:false}` or `{recovery:true, id, ecdh, sign, blob}` (the sealed copy), for the signed-in person only |
| `e2e.recovery.delete {}` | Turn recovery off: removes the recovery key and the sealed copy |
| `e2e.sync.pending {}` | `{waiting:[{id,label,ts}], helpers:[{id,label,ts}], recovery: null \| {id, backedUp}}`: my devices still waiting to be shown the past, and the ones that can show it, both only if used in the last 30 days (see "History for a new device"); and where the backup for the recovery key stands |
| `e2e.sync.page {cursor?}` | `{items:[{id,text}], next}`: my own encrypted messages (direct chats and groups I am in, newest first, narrowed to my boxes), to hand on. 600 calls per 10 minutes |
| `e2e.sync.put {device, items:[{mid,iv,w,ek}]}` | Boxes for the past, for one of my own devices, the recovery key included (1 to 500 per call, 400 calls per 10 minutes) |
| `e2e.sync.done {device}` | The device has been shown the past (it stops waiting); for the recovery key: the backup is complete (`backedUp: true`) |

Errors on send: `e2e_disabled`, `e2e_required`, `bad_envelope`, `e2e_peer_not_ready`, `e2e_stale_devices`, `too_long`, `e2e_unsupported` (global room).

`e2e_stale_devices` is a request to look the devices up again and send once more, not a failure: somebody added or removed a device while the message was being written. The event is `{ type: "error", code: "e2e_stale_devices", text, mid, conv, users }`: `mid` is the message id of the envelope that was refused, `conv` its conversation, `users` the people whose lists to look up again. Nothing was stored or delivered. See "For every client" below and `E2E_FRESH_DEVICES_CHANGE.md`.
Event: `e2e_devices_changed {user}` (refresh that person's keys).

## 9. Tests

- `tests/frontend/e2eCrypto.test.mjs`: primitives, tampering of every field, replay into another conversation, wrong device, forged signer, padding, files.
- `connectum-backend/test/connectum_e2e_test.mjs` (optional mode), `..._required_test.mjs`, `..._off_test.mjs`: registry, every envelope rule, history, edits,
  groups and membership changes, several devices, attachments, cards/feed, abuse and rate limits.
- `tests/frontend/e2eClient.test.mjs`: the device layer, including recovery (code format, sealing, wrong code, bound to person and key, a new browser, replace, off, shared computers).
- `connectum-backend/test/connectum_e2e_test.mjs` section "Recovery": the server rules (proof, sizes, one at a time, not removable as a device, not counted in the limit),
  and the whole story with the app's own client against the real backend.
- `tools/ui-audit/e2e-recovery.e2e.mjs`: the same story in a real browser (turn on, code shown once, keys lost, wrong code, right code, reload, turn off).
- `connectum-backend/test/connectum_e2e_socket_test.mjs`: the app's own socket service against the real backend (order, history, edits, placeholders, previews).
- `connectum-backend/test/connectum_e2e_sync_test.mjs`: history for a new device with the app's own client against the real server (68 checks: who is late, the hand-on, what the server serves and to whom, chains, skips, repeats, pages and cursors, cleared chats, limits, every refusal, removed devices).
- `tests/frontend/e2eHistorySync.test.mjs`: the box made later (opens only on its device, every field bound, chains, forged sender still caught) and the client job (batches, skips, stop, server errors, refused targets).
- `connectum-backend/test/connectum_e2e_backup_test.mjs`: the backup and the lost-only-device restore with the app's own client against the real server (41 checks: pending then complete, left-alone boxes, a new device opening everything with the code, restoring for itself and reading without the code, a wrong or guessed code, another person, a code made again, turning it off, stopping and resuming, a removed only device).
- `tools/ui-audit/e2e-backup.e2e.mjs`: the same in a real browser (turn on, code once, progress, done; the browser loses its keys; wrong then right code; "back them up now"; the one-time suggestion; dark theme).
- `tools/ui-audit/e2e-sync.e2e.mjs`: the whole story in a real browser, as the new device and as the older one (cards, Approve with progress, Later, That is not me, reload, light and dark, narrow window).

## 10. How the code works, file by file

Each entry says what the code does, then **in plain English** what that means.

### Browser side (`chat-app/features/connectumChat/e2e/` and `chat-app/services/`)

**`e2eCrypto.js`: the cryptography (no network, no storage).** Plain functions over the browser's built-in Web Crypto, so the same file runs in the app and in the tests.
- `generateDeviceKeys()` makes the two key pairs (ECDH P-256 to receive, ECDSA P-256 to sign). The private keys are created non-extractable, so not even our own page code can read them back out.
- `buildEnvelope()` is the sender's whole job: pad the text to a multiple of 64 bytes, make a random AES-256-GCM key, encrypt, then for every recipient device do a one-time ECDH with that device's public key, run the result through HKDF-SHA-256 to get a wrapping key, and encrypt the message key with it. It then signs the envelope (ECDSA) and returns `e2e1:{json}`.
- `openEnvelope()` is the reader's job: find my box, verify the signature against the sender's public signing key, derive the wrapping key with my private key, unwrap the message key, decrypt. Any failure throws a typed error (`bad_signature`, `not_for_this_device`, `wrong_conversation`, ...), never garbage.
- The message id, conversation, sender and device ids are bound in as AES-GCM "additional data". Change any of them and decryption fails. This is what stops replaying a message into another chat or moving a box to another device.
- `encryptFile()` / `decryptFile()` do the same for attachment bytes. `safetyNumber()` hashes both people's keys into 12 groups of 5 digits.
- *In plain English: this file is the lock-maker. It makes padlocks and keys, seals messages, checks stamps, and refuses anything that has been tampered with.*

**`e2eStore.js`: where the device keeps its secrets.** IndexedDB in the browser (it can store a non-extractable key as it is), or a plain in-memory version for tests. It holds this device's keys and the "pins" (the first keys ever seen for each contact's device). If IndexedDB is unavailable, E2E simply does not start.
- *In plain English: the device's keyring and its notebook of "this is what Bob's padlock looked like the first time".*

**`e2eClient.js`: the organiser.** Owns the device and talks to the server only through the `sd(action, args)` function it is given.
- `init(user)`: asks the server for the mode; if E2E is on, loads this device's keys or creates and registers new ones. If the server no longer lists this device (it was removed elsewhere), it throws the keys away.
- Directory cache: remembers everyone's public device keys for 5 minutes and refreshes when the server says someone's devices changed.
- `encryptText(scope, target, text)`: finds all recipient devices (a person's, or a whole group's), checks the pins, adds the sender's own devices, and calls `buildEnvelope`. In `optional` mode, if someone has no device yet it returns "send plain"; in `required` mode it throws `peer_not_ready`.
- `decryptText(text, conv)`: opens an envelope. If the sender's device is unknown it looks once more; if a pinned key changed it refuses and raises the key-change warning.
- *In plain English: the organiser works out who must be able to read a message, asks the lock-maker to seal it, and when a sealed message arrives, opens it or explains why it can't.*

**`e2eMedia.js`: attachments.** `uploadEncrypted()` encrypts the bytes and uploads the scrambled blob; `protectPicked()` handles GIFs (download, encrypt, upload) and stickers (kept inside the encrypted message); `openEncryptedMedia()` downloads, decrypts and returns a local URL, cached so scrolling does not re-download.
- *In plain English: the voice note is locked before it leaves the phone and unlocked on the other side.*

**`connectumSocket.js`: the glue that makes the rest of the app not need to know.**
- On `welcome` it calls `startE2E()` to set up the device.
- **Sending:** `sendDM`, `sendGroupMsg`, the reply and edit functions now go through `sendProtected()`. If E2E is off it writes the line exactly as before. If on, it encrypts first, in a queue so messages leave in the order they were typed. If encryption fails, the message is **not** sent as plain text; the screen shows it as failed.
- **Receiving:** every incoming event goes through an ordered pipeline. Events that carry an envelope (a new message, an edit, history, the conversation list, notification cards, feed items) are decrypted before any screen code sees them, and a device that cannot read one gets the placeholder "This message can't be read on this device".
- *In plain English: the chat screen keeps working with ordinary text. Encryption and decryption happen in a doorway the messages pass through on the way out and on the way in.*

**UI pieces.** `E2EBadge.jsx` is the lock in the conversation header and its dialog (safety number, your devices with Remove, "trust the new key"). `MessageList.jsx` decrypts attachments as the bubble appears ("Decrypting attachment..." until ready). `Composer.jsx` and `ConnectumChatScreen.jsx` encrypt voice notes, files, GIFs and stickers before sending and mark a failed send.

### Server side (`connectum-backend/src/`)

**`sd_e2e.erl`: the registry and the rules.** It stores public device keys (Redis hash per user, cached), verifies the registration proof (ECDSA over `connectum-e2e-register|user|id|ecdh|sign`), enforces the 10-device cap and rate limits, and serves `e2e.status / register / remove / devices / group_devices`.
- `check_send` applies the mode. `validate` checks the envelope: version, message id format, sender equals the logged-in user, conversation label matches the chat, the sending device is really theirs, sizes, and every box is for a real device in the conversation with at least one box per person who has a device.
- `for_viewer` removes everyone else's boxes before an envelope is handed to a reader. `check_edit` refuses turning an encrypted message into plain text.
- *In plain English: the server is a strict post office clerk. It checks the address, the sender's identity and that nobody is left out, then passes the sealed envelope on. It never has the means to open it.*

**`chat_web.erl`** calls those checks on every send and edit, trims the envelope per reader on live delivery, history and the conversation list, accepts the encrypted-file upload type, and refuses envelopes in the global room.
**`sd_cards.erl`, `sd_feed.erl`** carry the envelope (flagged `e2e:true`) into notification cards and the feed instead of text. **`chat_link_preview.erl`** skips envelopes (the server cannot see the link).

### Follow one message from start to finish
1. Ann types "hello" and presses send. `sendDM` hands it to `sendProtected`.
2. `encryptText` gets Bob's and Ann's device keys, `buildEnvelope` seals and signs it.
3. The envelope goes over the WebSocket as an ordinary `/msg bob e2e1:{...}` line.
4. `chat_web` calls `sd_e2e:check_send`: valid, covers everyone, so it is stored (and queued for the target database) as opaque text.
5. The server pushes Bob the envelope with only Bob's boxes. A notification card with the same envelope is added for him.
6. Bob's socket decrypts it in the doorway; the screen receives "hello" as normal text and shows it with the lock.
7. A third person, or the server's own operators and database admins, see only `e2e1:{...}`.

## For every client (web and mobile): wrap for the devices that exist NOW

**The server now enforces it.** A message must have a box for **every device that exists now** of every person in the conversation, the sender's own other devices included. The one device that may leave itself out is the sending device (the message is in its hands). A message that misses a device, or has a box for a device that no longer exists (removed, or a member who left), is refused with `e2e_stale_devices` and is neither stored nor delivered. Before this the server accepted a message with a box for at least one device of each person, so a sender with an old list silently left a new phone unable to read it ("Sent before this browser was set up for encryption").

What a client does, in order:
1. Right before encrypting **each** message, call `e2e.devices` (and `e2e.group_devices` for groups), do not reuse a list kept for minutes. Wrap for every device in the answer.
2. If the server answers `e2e_stale_devices`: forget what you know of the devices of `users`, look them up again, build a **new** envelope (new `mid`) from the same text, and send it again. Do this by yourself, without telling the person. The web app does it at most twice (`chat-app/services/e2eRetry.js`); after that the refusal is shown like any other error.
3. Match the refusal to your message by `mid` (the refusal carries the `mid` of the envelope you sent). The chat connection has no request ids, so `mid` is the only reliable key.

Switch: `CONNECTUM_E2E_REQUIRE_ALL_DEVICES=0` on the backend puts the old rule back (one box per person). It is the way back if a client is not ready; leave it unset (on) otherwise.

## History for a new device

**The problem:** a message key exists only inside the boxes made when the message was sent, so a device added later has no box for the past and shows the grey line. **The fix** is what WhatsApp does for a linked device: a device the person **already uses** hands the past on. Plain-words version: `E2E_SIMPLE_GUIDE.md`. For the mobile team, everything they must build: **`E2E_HISTORY_SYNC_MOBILE.md`**.

**Waiting.** A device is `late` when it was added to somebody who **already had a device**. The first device, a recovery key and every device that existed before this feature are never late. `e2e.status` gives each device `late`; the device itself uses it to show "waiting".

**Handing on (done by the older device, only after the person pressed Approve in the app; the same job backs up for the recovery key, see 6a).** For each of the person's own encrypted messages (`e2e.sync.page`, or the app's own stored envelopes): open this device's box (`unwrap`), then lock the message key again for the waiting device (`rewrap`): a **fresh one-time ECDH key pair**, ECDH with the waiting device's public ECDH key, HKDF with the **same salt, the same info** `connectum-e2e-wrap|<waiting device>|<ORIGINAL sender device>` and the same additional data `e2e1-wrap|<mid>|<waiting device>` as any box, AES-256-GCM over the 32-byte message key. The result is `{mid, iv, w, ek}` (`ek` is the new one-time public key). They go to the server in batches (`e2e.sync.put`), and when the last batch is stored the device says `e2e.sync.done`.

**Serving.** The server stores each box under the message id and the waiting device's id (`sd:e2e:xw:<mid>`), and when it serves the envelope to that person (history, live, cards, feed, `e2e.sync.page`) it adds the box to `keys` **for that device only**, as `keys[<device>] = {iv, w, ek}`. Everybody else gets what they got before. A viewer with no device that was shown the past costs no extra lookup.

**Reading.** A box with its own `ek` is opened with **that** `ek` for the key agreement; a box without one uses the envelope's `ek`, as always. Nothing else changes, and the signature still verifies (it never covered `keys`, see `sigInput`).

**Why this is safe.**
- A box is useless to anyone but the device it was made for (the device id is in the key derivation and the additional data; a box moved to another device id does not open: tested).
- The server never holds a message key or a private key. What a device uploads is only ever used for the **same person's own devices**; boxes for messages the person cannot see are never served.
- The older device does it only after the person approved **on that device**: a device added with a stolen session does not get the past. The owner is told about every added device (alerts above) and can remove it ("That is not me").
- What the person **cleared** is not handed on (`sync.page` respects it), deleted messages are left out, and a message the older device has no box for is skipped.

**Targets.** Any device of the person is a valid target (it is the person's own, and a box is useless to anyone else), the recovery key included; the server refuses a device that is not theirs (`not_found`). The app skips a message the target already has a box for (the served envelope shows it), so running a job again does only what is left.

**Limits.** `e2e.sync.put`: 1 to 500 boxes per call, 400 calls per 10 minutes per person; `e2e.sync.page`: 600 per 10 minutes, a page ends after the store page that reaches `CONNECTUM_E2E_SYNC_PAGE` (default 400) messages. A box is about 200 bytes of storage per message per device that was shown the past. Removing a device leaves its boxes unused (they are never served).

**One active session per person.** Signing in on the new device signs the older one out. So the sequence is: sign in on the new device (waiting); sign in on the older device and approve (the new one is signed out meanwhile); sign in on the new device again. Both keep their keys. The offer and the "waiting" card say so. A setting for more than one session at a time would shorten this; it is a company decision and is not built.

**Resuming.** Stopping half way leaves the device waiting and everything stored so far in place; running it again writes the same boxes again (no duplicates) and finishes. A device that was already shown the past may be topped up the same way.

## Alerts when a device is added

A device that is added to an account can read every message sent to that account from then on. If it is not the person's own (a stolen session, a compromised server), nobody would otherwise know. So:

* **The account owner is told**, in the notification panel, on every device they have: "A new device was added to your encrypted messages" (priority medium, category `security`, the device's name in the text and what to do: remove it in the lock dialog and change the password). It is the same feed item kind as "signed in on another device" (`sd_feed:security/3`, `security_text(e2e_device_added, ...)`). It is **not** sent for the person's very first device (that is getting started), not when the same device registers again, and not for the recovery key (that is switched on by the person, not added as a device). The device's name is shown as plain text: control characters are removed and it is cut to 60 characters.
* **A contact is told by their app**, not by the server (device-change events go only to the account that changed, never to the people who write to it). When the app looks up the devices of somebody it already knew (it has pinned at least one of their devices) and finds a device id it has not seen, it shows once: "@bob added a new device (Chrome on Windows). Messages you send them now are encrypted for it too. If that surprises you, check the safety number in the lock at the top of the chat." Not for the first time somebody is seen, not for the person's own devices, not for a recovery key. In the web app: `E2EClient.onNewDevice` (`chat-app/features/connectumChat/e2e/e2eClient.js`) and the `e2e_new_device` socket event.
* Every device addition and removal is also in the audit log (`e2e.device_added`, `e2e.device_removed`), as before.

A refusal because a sender used an old device list (`e2e_stale_devices`) is logged once per refusal: `e2e stale devices refused: from=… conv=… whose devices to look up again: …` (usernames and the conversation label, no message content), so how often it happens can be counted.

Also: pass your device id in `e2e.status` (`{id}`) when you start. The server records when a device was last used. A person at the 10-device limit can still register: a device unused for 30 days is replaced. A browser that loses its stored keys (private window, cleared site data) makes a new device each time, which used to fill the list for good.
