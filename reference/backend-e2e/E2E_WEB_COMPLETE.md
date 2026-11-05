# End-to-end encryption on the web: the complete picture (analysis for the mobile team)

Written 4 November 2026 from the code on `origin/main` (commit `6e1d0009`). It describes what the web app and the Erlang server actually do, so the mobile app can interoperate with the web and reproduce the behaviour.

- **Analysis, not a code dump.** Every claim has a `file:line` pointer (lines drift; search the function name if one has moved). No real keys, codes, tokens or user data appear: values like `<device-id>` or `mid_xxx` are placeholders. Real fixed test values live in `docs/*.json` (section K).
- **Short names for files:** `Crypto` = `chat-app/features/connectumChat/e2e/e2eCrypto.js`, `Client` = `.../e2e/e2eClient.js`, `Store` = `.../e2e/e2eStore.js`, `Media` = `.../e2e/e2eMedia.js`, `Socket` = `chat-app/services/connectumSocket.js`, `Retry` = `chat-app/services/e2eRetry.js`, `Server` = `connectum-backend/src/security/sd_e2e.erl`, `Prompt` = `.../components/E2ESyncPrompt.jsx`, `Badge` = `.../components/E2EBadge.jsx`, `Send` = `connectum-backend/src/http/chat_web_send.erl`, `Web` = `connectum-backend/src/http/chat_web.erl`, `Upload` = `connectum-backend/src/http/chat_web_upload.erl`.
- The new-device story (second device, history, recovery, errors) has its own file: `docs/E2E_NEW_DEVICE_AND_HISTORY.md`. This file avoids repeating it and points there.
- **Existing docs compared:** `E2E_ENCRYPTION.md` and `E2E_ATTACHMENTS.md` (read in full); `E2E_HISTORY_SYNC_MOBILE.md` (all except the "Real replies" and test-vector sections); `E2E_SIMPLE_GUIDE.md`, `E2E_MOBILE_KIT.md` and `E2E_MOBILE_REVIEW.md` (only by searching for key terms). `E2E_FRESH_DEVICES_CHANGE.md` was not read. The differences found are listed in section L1.

---

## A. Map of the code

### Browser (`chat-app/`)

| File | What it does | Imported by |
|---|---|---|
| `features/connectumChat/e2e/e2eCrypto.js` | All cryptography: device keys, envelope build/open, rewrap, recovery code and seal, safety number, file encryption. No network, no storage. | `e2eClient.js`, `e2eMedia.js` (via client), `connectumSocket.js` (`E2E.convLabel`, `E2E.PREFIX`, `Socket:19`), tests |
| `features/connectumChat/e2e/e2eClient.js` | The organiser: owns this device, directory of public keys, pinning, plan (who to wrap for), encrypt/decrypt text, recovery, hand-on job. Talks only through the `sd(action,args)` function it is given. | `connectumSocket.js` (`Socket:15`, constructed `Socket:75`) |
| `features/connectumChat/e2e/e2eStore.js` | Where keys live: IndexedDB `connectum-e2e` (stores `device`, `pins`, `recovery`), or an in-memory copy for tests. | `connectumSocket.js` (`lazyIndexedDbStore`, `Socket:16`) |
| `features/connectumChat/e2e/e2eMedia.js` | Encrypt and upload a file; protect a GIF/sticker; download and decrypt on receive. | `Composer.jsx`, `chatActions/attachFile.js`, `MessageList.jsx` |
| `services/connectumSocket.js` | The glue: starts E2E on `welcome`, encrypts outgoing text (`sendProtected`), decrypts incoming events in order, refreshes sync state, placeholder texts. | the chat screen and event handlers |
| `services/e2eRetry.js` | Resend by itself when the server answers `e2e_stale_devices`. | `connectumSocket.js` (`Socket:20`, `Socket:88`, `Socket:310`) |
| `features/connectumChat/components/E2EBadge.jsx` | The lock in the conversation header, the dialog (safety number, devices, Remove, recovery). Exports `E2EDialog` and `deviceKind`. | `ConversationHeader.jsx:47`, `E2ESyncPrompt.jsx` |
| `features/connectumChat/components/E2ESyncPrompt.jsx` | The cards: approve a new device, "waiting", "back up your messages" suggestion. | the chat screen |
| `features/connectumChat/chatEvents/connection.js` | Handlers for `e2e_send_failed`, `e2e_key_changed`, `e2e_new_device`, error events, session events. | event dispatcher (`chatEvents/index.js`) |
| `features/connectumChat/chatActions/attachFile.js`, `Composer.jsx` (`:650`, `:683`, `:785`), `chatEvents/messages.js`, `chatEvents/history.js`, `utils/chatMessages.js:53` | Choosing encrypted upload vs plain for attachments, building and reading the `e2e` part of the attachment tag. | chat screen |
| `features/connectumChat/components/MessageList.jsx:345` | Shows "Decrypting attachment…" and decrypts attachments as the bubble appears. | chat screen |
| `features/connectumChat/components/PinnedBar.jsx:10`, `modals/SavedMessagesModal.jsx:11` | Show "Encrypted message" instead of previews for pinned and saved items. | chat screen |

### Server (`connectum-backend/src/`)

| File | What it does |
|---|---|
| `security/sd_e2e.erl` | The registry of public device keys, every envelope rule, recovery, history sync storage, `for_viewer` narrowing. (`sd_e2e.erl:1-25` is the design summary.) |
| `core/sd_cmds.erl:170-172, 540-541` | Routes `e2e.*` actions for signed-in users to `sd_e2e:call`. |
| `http/chat_web_send.erl` | Calls `sd_e2e:check_send` / `check_edit` on every send and edit (`:27-52`), adds the `e2e:true` field to messages (`:246-262`), narrows envelopes per viewer in lists and history (`:293-301`). |
| `http/chat_web.erl` | Live delivery narrows each envelope per viewer (`:420`, `:444`, `:496`, `:503`); ends a replaced session (`:409-410`). |
| `http/chat_web_upload.erl` | Accepts the blob type `application/x-connectum-e2e`, size limit, `.e2e` extension (`:12-13`, `:232`, `:285`, `:298`, `:332`, `:360`). |
| `forms/sd_cards.erl:158-162`, `forms/sd_feed.erl:376-399` | Notification cards and feed items carry the envelope (narrowed to the person) flagged `e2e:true`, not text. |
| `forms/sd_mentions.erl:13, 30` | Does not read mentions out of an envelope. |
| `integrations/sd_msgq.erl:49`, `tools/msgq-consumer/bridge.mjs:82` | The message queue and the target database store the sealed envelope as opaque text. |
| `security/sd_auth.erl:150-182` | Session slots (phone and laptop), `session_replaced`. |

I did **not** open `chat_link_preview.erl` (the old doc says it skips envelopes) or `chat_store.erl`; claims about them below are marked "from the existing doc".

### Shared
There is no shared E2E code between web and server. The only shared knowledge is the envelope format, the conversation label rule and the strings that are signed or bound as additional data (sections B and F). Test vectors live in `docs/` and `tools/e2e-kit/`.

---

## B. Cryptography

### B.1 Primitives

| Item | Value | Where |
|---|---|---|
| Library | the browser's built-in **Web Crypto** (`crypto.subtle`), no third-party crypto library | `Crypto:13-15` |
| Key agreement | **ECDH, curve P-256** | `Crypto:50` |
| Signature | **ECDSA P-256 with SHA-256**; WebCrypto gives the signature as `r\|\|s` (64 bytes); the server converts it to DER to verify registration proofs | `Crypto:51`, `Crypto:216`, `Server:304-315` |
| Key derivation | **HKDF-SHA-256** (wrap key and recovery key) | `Crypto:173-179`, `Crypto:97-101` |
| Symmetric cipher | **AES-256-GCM** (message, boxes, files, recovery blob), 12-byte iv, 16-byte tag appended to the ciphertext | `Crypto:205-208` |
| Public key format | 65-byte uncompressed P-256 point (`0x04` + X + Y), base64url | `Crypto:59-68`, `Server:285-290` |
| Private key storage | non-extractable CryptoKey (device keys); the recovery pair is extractable **once** so it can be sealed | `Crypto:48-53`, `Crypto:105-109` |
| Encoding | **base64url without padding** for every binary value; hex (32 chars) for device ids; message id = 16 random bytes in base64url (22 chars) | `Crypto:23-37`, `Crypto:44-45`, `Server:43-44` |
| Text encoding | UTF-8, strict decoding on read | `Crypto:15-16` |

### B.2 The envelope

The message text sent to the server is the prefix `e2e1:` followed by JSON (`Crypto:18`, `Crypto:218`):

```
e2e1:{ "v":1, "mid":<22 chars>, "from":<user lower case>, "dev":<sender device id>,
       "conv":"dm:a|b" | "group:name", "ts":<ms>, "ek":<one-time public key>,
       "iv":<12 bytes>, "ct":<ciphertext+tag>, "sig":<ECDSA r||s>,
       "keys": { "<device id>": {"iv":<12 bytes>, "w":<wrapped message key>} , ... } }
```

- **Versioning:** `v:1` and the prefix `e2e1:`. The reader rejects any other version as `bad_envelope` (`Crypto:247-255`). The server rejects `v` other than 1 (`Server:456`). A text that starts with `e2e1:` must be a valid envelope; it is never treated as plain text (`Server:21`).
- **Conversation label:** `dm:` + the two usernames, lower case, sorted, joined by `|`; or `group:` + lower-case group name (`Crypto:182-186`; the server computes the same, `Server:528`, `Server:468`).
- **Padding:** the JSON payload is framed as a 4-byte big-endian length plus the bytes, then zero-padded to a multiple of **64** bytes before encryption (`Crypto:155-167`). The payload is `{ "v":1, "t":"<the text>" }` (`Client:332`).

### B.3 What is encrypted, authenticated or signed

| What | How | String / data |
|---|---|---|
| The message | AES-256-GCM with a fresh random key and iv | additional data (AAD): `e2e1-msg\|<mid>\|<conv>\|<from>\|<dev>` (`Crypto:169`, `Crypto:208`) |
| Each box (message key for one device) | one-time ECDH (envelope's `ek`, private half discarded) with the device's public ECDH key; HKDF-SHA-256 with `salt = base64url-decode(mid)` and `info = "connectum-e2e-wrap\|<recipient device>\|<sender device>"`; AES-256-GCM over the 32-byte key | AAD: `e2e1-wrap\|<mid>\|<recipient device>` (`Crypto:170`, `Crypto:173-195`) |
| A later box (history) | same, but with its **own** one-time key `ek` stored beside the box; `info` still uses the **original** sender device | `Crypto:229-243`, `Crypto:223-227` |
| The signature | ECDSA by the sender device over the text `e2e1\|<mid>\|<from>\|<dev>\|<conv>\|<ts>\|<ek>\|<iv>\|<ct>` (the values exactly as they appear in the JSON). It does **not** cover `keys`. | `Crypto:171` |
| Device registration proof | ECDSA by the new signing key over `connectum-e2e-register\|<user>\|<id>\|<ecdh>\|<sign>` | `Crypto:71-74`, `Server:296-302` |
| Recovery blob | AES-256-GCM, key = HKDF-SHA-256(ikm = 26-char code, salt = 16 random bytes, info = `connectum-e2e-recovery\|<user lower case>\|<id>`), AAD `e2e1-recovery\|<user>\|<id>` | `Crypto:97-117` |
| A file | AES-256-GCM, random 32-byte key and 12-byte iv | AAD is the fixed text `e2e1-file` (`Crypto:290`) |
| Safety number | SHA-256 over `connectum-safety\|<sorted device lists of both people>`, shown as 12 groups of 5 digits | `Crypto:139-146` |
| Key pin fingerprint (helper) | first 16 bytes of SHA-256 over `<id>\|<ecdh>\|<sign>`, base64url | `Crypto:149-152` (the pins themselves store the keys, `Client:311`) |

**Nonce/iv rule:** a fresh random 12 bytes for every encryption; there is no counter. **Reader order:** parse, check conversation, find own box, look up the sender's signing key (pinned), **verify the signature first**, then derive and decrypt (`Crypto:264-282`).

Differences from a "typical" design worth knowing: no ratchet (no forward secrecy), the signature does not cover the boxes, and the server cannot verify signatures (it checks structure only).

---

## C. Keys and storage

| Key | Where it lives | Format | Lifetime |
|---|---|---|---|
| Device ECDH pair | browser IndexedDB `connectum-e2e`, store `device`, key = username | CryptoKey objects (private non-extractable) + public base64url | until the device is removed or site data cleared (`Store:30-40`, `Store:54-57`) |
| Device signing pair | same record | same | same |
| Pins | store `pins`, key `<user>\|<deviceId>` | `{ecdh, sign}` as first seen | until "trust the new key" for that person (`Client:320`) |
| Recovery private ECDH key | store `recovery`, key = username | `{id, ecdh: CryptoKey (non-extractable)}` | until recovery is turned off, or found off on init (`Client:71-72`) |
| Directory cache (everyone's public devices) | memory only | map user -> `{at, devices}` | **5 minutes** (`Client:7`, `Client:291-295`) |
| Message and attachment keys | memory during use | raw bytes | seconds |
| The server's copy | device list per person; recovery blob; later boxes | JSON | until removed (`Server:62-66`, `Server:37-38`) |

If IndexedDB is unavailable (some private windows) E2E simply does not start on that device (`Store:50-52`, `Client:74-76`).

### Fetching another person's keys (peer lookup)

```
Client -> Server: e2e.devices {users:[bob, me]}        (1 to 50 names, 600 calls / 10 min)   Server:380-397
Server -> Client: {users:{bob:[{id,ecdh,sign,label,ts,recovery?}], me:[...]}}
   (only people the caller may message, and themselves)                                        Server:389
Client -> Server: e2e.group_devices {group}            (caller must be a member, <= 200)     Server:398-414
```

- **Direct messages:** `Client.#plan` asks for **fresh** lists at every send (`fresh: true`, `Client:343`). The 5-minute cache is used when **reading** (to find a sender's signing key, `Client:358-366`) and in `devicesOf` generally.
- **Cache dropped** when: the server pushes `e2e_devices_changed {user}` for that user (`Socket:473`); a send is refused with `e2e_stale_devices` (the named users, `Retry:29`); "trust the new key" (`Client:320`); after the person changes their own recovery (`Client:152`, `Client:177`); and always when a sender device is unknown (looked up once more, `Client:362-364`).
- **Pinning (trust on first use):** the first keys seen for a device are stored; a later different key for the same id is refused and raises `e2e_key_changed` (`Client:305-317`, `Client:367-371`). The web tells the person once when a person it already knew gets a **new** device (`Client:36-42`, `Client:315`, `chat-app/features/connectumChat/chatEvents/connection.js:47-51`).

---

## D. Sending and receiving, message type by message type

### D.1 A 1:1 message (and the general path)

```
UI -> Socket.sendDM(target,text)                                     Socket:505
Socket.sendProtected: queue, await E2E ready                         Socket:407-415
  Client.encryptText('dm', target, text):
    e2e.devices {users:[target, me]} (fresh)                          Client:343
    pin check for each person's devices; drop changed keys            Client:346
    add my own other devices and this device                          Client:347
    if somebody (not me) has NO device:
        mode required -> throw peer_not_ready
        mode optional -> return null => send PLAIN                    Client:348-352
    buildEnvelope(...)  -> "e2e1:{...}"                                Client:353, Crypto:201-219
  mid = envelope's mid; Retry.remember(mid, resend)                    Socket:424-425
  Socket.send("/msg <target> e2e1:{...}")                              Socket:426, 505
Server (Send:27-52): sd_e2e:check_send -> validate -> store as opaque text -> deliver
Server -> each reader: the envelope with ONLY that reader's boxes       sd_e2e.erl:694-707, Web:420
Reader Socket: decrypts in the doorway; screens receive plain text      Socket:451-495
```

If encryption **fails** (not "peer not ready"), the message is **not** sent as plain text: the screen shows it as failed (`Socket:418-423`).

### D.2 A group message

Same, with `e2e.group_devices {group}` instead of `e2e.devices`, `/groupmsg <group> e2e1:{...}`, conversation label `group:<name>`, and the 200-member and 250-box limits (`Client:340-341`, `Server:406-407`, `Server:478`). Needs boxes for every device of every member (`Server:497-520`).

### D.3 Edit

`Socket:597-600`: an edit is `sendProtected` too (`/edit dm|group <target> <id> <text>`), so it is a new envelope with a new `mid`. The server calls `check_edit`: an encrypted message cannot be edited into plain text (`e2e_required`, "This message is end-to-end encrypted: its edit must be too.", `Server:444-448`); a plain message edited into an envelope is allowed. The web does not allow editing a message that failed or could not be opened (`MessageList.jsx:448`). Edit of the **global** room is never encrypted (`Socket:602`).

### D.4 Delete

`/delete dm|group|global <target> <id>` (`Socket:585-590`): a command about a message id. **Not encrypted**, the server sees which message was deleted and by whom. (The old doc says history does not return deleted messages; confirmed for sync, `Server:629`.)

### D.5 Reply

Direct and group replies use `sendProtected` (`/replydm <user> <id> <text>`, `/replygroup <group> <id> <text>`, `Socket:528`, `Socket:533`). The **text** is in the envelope; the **id of the message replied to** travels outside it, so the server sees the reply link. The global-room reply is plain (`Socket:523`). A real-server reference of these replies: `docs/e2e-message-marks-replies.json` (note at the top).

### D.6 Forward

`chatActions/forward.js:12-13, 46-62`: the forwarded text is built as `↪ [Forwarded by <me> • from <author>]: <original text>` and sent with `sendDM` or `sendGroupMsg`, so it is an ordinary encrypted message with that prefix inside the text. Forwarding to the global room or a host chat goes plain (`forward.js:49-51`, `:54-55`), and a form message is forwarded by form logic, not encrypted (`forward.js:6`).

### D.7 Reaction

`/react dm|group|global <target> <id> <emoji>` (`Socket:574-579`): **not encrypted**; the server sees the message id and the emoji.

### D.8 Pin and save

Pinning and saving are server actions on a message id (`msg.pin`, `msg.save`; real replies in `docs/e2e-message-marks-replies.json`). The server stores which message is pinned. The web shows "Encrypted message" in the pinned bar and the saved list instead of a preview (`PinnedBar.jsx:10`, `SavedMessagesModal.jsx:11`): it does not decrypt for these. I did not trace what the pinned and saved records hold; the "Encrypted message" label suggests they carry the envelope.

### D.9 Mentions, formatting

- **Formatting** (bold, links, etc.) is just characters in the text, so it is inside the encrypted payload and rendered after decrypting (no separate field).
- **Mentions:** the server does not read an envelope for `@name`, so no mention is detected server-side for an encrypted message (`sd_mentions.erl:13`, `:30`). Any mention highlight the web shows must be computed on the device after decrypting; I did not trace that code.

### D.10 An attachment (`[ATTACHMENT:...]` tag)

The tag is part of the message text and is encrypted with it; the file is encrypted separately (section G). The tag shape and `e2e: {key, iv}` part: `E2E_ATTACHMENTS.md` "The attachment tag", read by the web in `utils/chatMessages.js:53`.

### D.11 What stays unencrypted

| Item | Visible to the server? | Notes |
|---|---|---|
| Who, to whom, when, size, group membership, which devices exist | yes | metadata (`Server:13-15`) |
| `mid`, `from`, `dev`, `conv`, `ts` | yes | inside the envelope JSON, in the clear |
| Message ids, reply links, reactions (emoji), pins, saves, deletes, reads, mutes | yes | commands and conversation state |
| Unread counts, last id, read/delivered ids | yes | in the conversation record (`docs/e2e-message-marks-replies.json`, `conv_unread`) |
| Attachment names and types | **no** (inside the tag); the blob's size and upload time are visible | `E2E_ATTACHMENTS.md` |
| **Notifications and feed items** | carry the **envelope** (narrowed to the person) flagged `e2e:true`; the **app decrypts** it to make a preview ("Ann: hello", "🎙️ Voice note") | `sd_cards.erl:158-162`, `sd_feed.erl:376-399`, `Socket:437-438`, `Socket:483-495`; preview text: `Socket:50-56` |
| **Search** | **not traced.** The GIF search is plain (existing doc). I did not read the message-search code; whether message search works on encrypted text is unknown to me (open question L2.1). |
| Link previews | skipped for envelopes (from the existing doc; I did not open `chat_link_preview.erl`) |
| The database copy via the queue | the opaque envelope | `bridge.mjs:82`, `sd_msgq.erl:49` |

---

## E. Policy: when a thread is encrypted

### E.1 The mode (server)

`CONNECTUM_E2E` = `off` (default), `optional`, `required` (`Server:46-51`), one setting for the whole backend (see L1, D6).

| Mode | Envelope sent | Plain text sent |
|---|---|---|
| `off` | refused `e2e_disabled` | accepted |
| `optional` | accepted if valid | accepted |
| `required` | accepted if valid | refused `e2e_required` ("Messages here are end-to-end encrypted. Update your app, or sign in again, so your device can encrypt.") |

`Server:434-441`. The **global room** never accepts an envelope (`e2e_unsupported`, "The global room is not end-to-end encrypted.", `Server:429-433`). Forms, `#` commands, host chats, the AI chat and topic messages for outside people are not encrypted (existing doc; the client sends them without envelopes: `attachFile.js:10-11` picks no E2E target for workspace, host and the general room).

### E.2 The client's decision

`Client.#plan` (`Client:338-355`):

1. E2E not enabled (mode off or not ready): send as before (plain).
2. Look up devices (fresh); drop devices with changed keys.
3. Somebody other than me has **no device**: in `required` throw `peer_not_ready` ("<names> has/have not set up encryption yet."); in `optional` send **plain** so nobody is locked out.
4. Otherwise encrypt for every device of every person plus my devices.

- **Group over 200 members:** the lookup fails with `limit`; the web does not send (neither encrypted nor plain), in any mode except `off`. This is probably unintended (L2.2). `Server:406-407`, `Client:299`, `Socket:418-423`.
- **Plain text into an encrypted thread:** in `optional` the server accepts it (`Server:439`), so a modified client can. The web never does it when everyone has a device. In `required` it is refused.
- **Per-organisation settings:** none found (L1 D6).
- **Lock state in the UI:** header icon `lock` (green) when E2E is on and the chat is eligible, `lock_open` when not ready or not an encrypted scope, `gpp_maybe` (red) when a contact's key changed; title text and dialog banners in section I (`Badge:24-29`, `Badge:128-135`). The conversation scope rule: not the workspace, host chats or the general room (`Badge:10-14`).

---

## F. Server side

### F.1 Actions (WebSocket `/sd`, signed-in users only: `sd_cmds.erl:170-172`)

| Action | Params | Result | Limits and rules | Code |
|---|---|---|---|---|
| `e2e.status` | `{id?}` | `{mode, devices:[{id,ecdh,sign,label,ts,recovery?,late}], maxDevices:10, recovery:bool}` | passing `id` records "last seen" at most hourly | `Server:327-330`, `Server:89-106` |
| `e2e.register` | `{id, ecdh, sign, label, proof}` | `{device}` | 30/hour; max 10 non-recovery devices (replaces one unused 30 days); label cleaned to 60 chars | `Server:345-354`, `Server:129-172` |
| `e2e.remove` | `{id}` | `{removed:true}` | not for the recovery key | `Server:355-359`, `Server:180-195` |
| `e2e.devices` | `{users:[1..50]}` | `{users:{name:[devices]}}` | 600/10 min; only people the caller may message | `Server:380-397` |
| `e2e.group_devices` | `{group}` | `{group, members:{name:[devices]}}` | caller must be a member; `limit` over 200; `forbidden`, `not_found` | `Server:398-414` |
| `e2e.recovery.set` | `{id, ecdh, sign, proof, blob:{v:1,salt,iv,ct}, replace?}` | `{device}` | 10/hour; blob sizes; second one needs `replace:true` | `Server:331-336`, `Server:213-244` |
| `e2e.recovery.get` | none | `{recovery:false}` or `{recovery:true, id, ecdh, sign, blob}` | 30/hour | `Server:337-342`, `Server:246-252` |
| `e2e.recovery.delete` | none | `{removed:true}` | `not_found` if off | `Server:343-344`, `Server:254-264` |
| `e2e.sync.pending` | none | `{waiting, helpers, recovery}` | no own limit | `Server:360`, `Server:549-563` |
| `e2e.sync.page` | `{cursor?}` | `{items:[{id,text}], next}` | 600/10 min | `Server:367-372`, `Server:595-636` |
| `e2e.sync.put` | `{device, items:[{mid,iv,w,ek}]}` | `{stored:n}` | 400/10 min; 1 to 500 items; `not_waiting`, `not_found`, `invalid` | `Server:361-366`, `Server:569-587` |
| `e2e.sync.done` | `{device}` | `{done:true}` | none | `Server:373`, `Server:658-668` |
| `e2e.sync.approved` | `{device}` | `{approved, device, ts}` | 60/10 min; optional record | `Server:374-379`, `Server:644-656` |
| event `e2e_devices_changed` | `{user}` | sent to the person's own devices on any change | | `Server:120-125` |

Error shape: `{ok:false, error:{code, message}}` for `/sd` calls; send refusals arrive as `{type:"error", code, text}` events (`Send:48-56`). Codes seen: `invalid`, `conflict`, `limit`, `not_found`, `forbidden`, `rate_limited`, `not_waiting`, `bad_request`, plus the send codes in F.3.

### F.2 Storage

Redis-style hashes through `sd_db`: `sd:e2e:dev:<user>` (devices), `sd:e2e:recovery` (blob per user), `sd:e2e:xw:<mid>` (later boxes) (`Server:62`, `Server:37-38`). Device lists are cached with a generation counter (`Server:66-76`). The device record fields: `id, ecdh, sign, label, ts, seen, late, recovery, backedUp, xw, approvedTs` (see `Server:108-118`, `:582`, `:651`, `:662`). Audit events written: `e2e.device_added`, `e2e.device_removed`, `e2e.recovery_on`, `e2e.recovery_off`, `e2e.history_shown`, `e2e.history_approved`.

### F.3 What the server validates and refuses on a send

`Server:450-520` in order:

1. Envelope length more than 120,000 characters: `too_long`.
2. Not valid JSON with `v:1` and all fields: `bad_envelope` "it is not a valid envelope".
3. `mid` not 22 base64url chars; `from` is not the signed-in user; `conv` does not match the real conversation; `dev` not 32 hex; `ek` over 100, `iv` over 16, `sig` over 100 characters; `ct` over the length limit; 0 or more than 250 boxes; a malformed box (iv over 16, w over 100): `bad_envelope` with the reason.
4. The sending device is not registered for the sender: `bad_envelope` "the sending device is not registered for you".
5. A box for a device that is not in the conversation: `e2e_stale_devices` (default) or `bad_envelope` (old rule).
6. Someone (not the sender) has no device: `e2e_peer_not_ready`.
7. Some existing device (other than the sender's) has no box: `e2e_stale_devices`.

`e2e_stale_devices` is returned with `{mid, conv, users}` and logged without content (`Server:524-526`). `CONNECTUM_E2E_REQUIRE_ALL_DEVICES=0` restores the old "one box per person" rule (`Server:522`). The server does **not** verify the signature, decrypt, or look at the ciphertext.

### F.4 What the server hands to readers

`for_viewer`: the envelope with `keys` reduced to the viewer's own device ids **plus** their later boxes (`Server:694-707`). Applies to live delivery, history, conversation lists, cards and feed (`Web:420`, `:444`, `:496`, `:503`; `Send:293-301`).

---

## G. Attachments and forms

### G.1 Files

- **Encrypt:** random 32-byte key and 12-byte iv, AES-256-GCM, AAD `e2e1-file`; the blob is ciphertext plus the 16-byte tag, **no** iv or key inside (`Crypto:286-292`, `E2E_ATTACHMENTS.md` "The recipe").
- **Upload:** `POST /upload` as multipart with one `file` part, content type `application/x-connectum-e2e`, name `<original>.e2e`; header `Authorization: Bearer <session token>` (`Media:47-57`). The server accepts that type, requires at least 17 bytes, allows up to the video limit plus 512 KB, stores it as `<48 hex>.e2e`, does not track it for the media allowance (`Upload:12-13`, `:232`, `:285`, `:298`, `:332`, `:360`). The web tries the API origin, then a relative path (`Media:50`).
- **Key and iv travel inside the encrypted message**, in the tag's `e2e` part, never to the server (`Media:59-63`).
- **Download:** fetch the blob (from the server origin when the url is relative), decrypt, give a local `blob:` URL; cached per url and key in memory (`Media:85-99`). A failure raises `file_decrypt_failed` (`Crypto:300`).
- **Preview:** there is none server-side; the web shows "🔒 Decrypting attachment…" until the file is decrypted (`MessageList.jsx:345`). Notification previews use `e2ePreview` ("🎙️ Voice note", "📷 Photo", "🎥 Video", "📎 Attachment", `Socket:50-56`).
- **GIFs:** the app downloads the GIF, encrypts and uploads it so no recipient contacts the GIF provider; if the download is blocked, the link travels inside the encrypted message. **Stickers** (small `data:` URL up to 50,000 characters) travel inside the message (`Media:65-82`). A GIF search word is not encrypted.
- **When an upload fails**, the web falls back to a `data:` link inside the message (existing doc); the mobile app should show an error instead (`E2E_ATTACHMENTS.md` "When a file is encrypted").
- **Limits:** the app's own limit and nginx limits are in `E2E_ATTACHMENTS.md` "Limits"; I did not re-check them against deployed config.

### G.2 Forms

Forms, form data and form files are **not** end-to-end encrypted; the server has to read them to route and store them (the existing doc, section 1; the web sends forms by form logic, e.g. `forward.js:6`). I did not find any E2E code in `form-studio/` or `shared/` (searched for "e2e"; only colour constants matched).

---

## H. Sessions and devices

- **Sessions:** two per person, one phone and one laptop (a phone sends `"client":"mobile"`); a new sign-in of the same kind ends the earlier one; the live connection gets `sd_event session_replaced` and closes with reason `signed_in_elsewhere` (`sd_auth.erl:150-182`, `Web:409-410`). `CONNECTUM_SESSION_SLOTS=1` makes it one session in all. The web then forces a sign-out with "You were signed out because this account signed in on another tab or device." (`chatEvents/connection.js:96-99`).
- **Device list:** `e2e.status` (the lock dialog shows "This device" and "Signed in elsewhere" with Remove, `Badge:157-166`).
- **Removing a device:** `e2e.remove` (not the recovery key); the server notifies the person's devices; the removed device deletes its keys on its next `init` (`Client:58-61`); "Remove" on this device deletes local keys at once (`Client:131-136`).
- **Sign-out on the web:** clears the account identity only. The device keys are **not** deleted (`ConnectumAuthScreen.jsx:234-237`; nothing calls `removeThisDevice`, `Client:119-124`).
- **What is deleted where:** local keys by "Remove on this device", by finding itself removed, or by clearing site data; the server's device record by `e2e.remove` or by replacement after 30 days unused at the limit; the recovery key and blob by `e2e.recovery.delete`; later boxes of a removed device are never served (`Server:191-195`, `Server:149-156`, `Server:254-264`).
- **Details of the second device, history and recovery flows:** `docs/E2E_NEW_DEVICE_AND_HISTORY.md`.

---

## I. UI states and texts

| Where | When | Exact text |
|---|---|---|
| Header lock tooltip | contact key changed | "This person's security key changed" (`Badge:29`) |
| | E2E on, eligible chat | "End-to-end encrypted. Click to verify." |
| | not ready | "Not encrypted on this device. Click for details." |
| | global/host/workspace | "Not end-to-end encrypted: the server has to read this chat." |
| Dialog title and subtitle | always | "End-to-end encryption"; "Only you and the people in the chat can read these messages" or "Not active on this device" (`Badge:125`) |
| Banner, cannot start | E2E unavailable | "Encryption could not start on this device: {reason}" (`Badge:127`) |
| Banner, unencrypted chat | no scope | "This chat is not end-to-end encrypted. The global room and host chats are handled by the server. Direct chats and groups are encrypted." (`Badge:130`) |
| Banner, encrypted | scope and enabled | "Locked on your device before it is sent. Text, voice notes, photos, GIFs and stickers in this conversation|group are scrambled; the server only carries data it cannot read." (`Badge:134`) |
| Banner, key changed | `changed` | "@{name}'s security key changed. This can happen when they reinstall or use a new browser, but it could also mean someone is interfering. Compare the safety number with them first." Button: "I checked, trust the new key" (`Badge:140-141`); after: "The new key is now trusted. Compare the safety number below with the other person first if you have not." (`Badge:81`) |
| Safety number | DM | "Safety number with @{name}" / "If you both see the same number, nobody has swapped the keys." (`Badge:147-148`) |
| Devices | ready | "Your devices {n}" / "Each browser or phone you sign in on has its own keys. Remove any you no longer use."; rows "This device" / "Signed in elsewhere"; button "Remove"; after: "This device was removed. Sign in again to set it up." or `Removed "{label}".` (`Badge:154-163`, `Badge:75`) |
| Recovery | off | "Recovery keeps a backup of your messages that only your code can open. If you lose every device, sign in on a new one, enter the code, and your messages come back. Only you have the code: not us, and not the company." Button "Turn on recovery and back up" (`Badge:200-201`) |
| Recovery code shown | after turn on | "Your recovery code. Write it down or keep it somewhere safe. It is shown only now and is not stored anywhere we can read. It is the only way to bring your messages back if you lose every device." Buttons "Copy", "I have saved it" (`Badge:175-179`) |
| Backup/restore progress | job | "Backing up your earlier messages" or "Bringing your earlier messages back"; "{n} messages done. Keep this window open until it finishes."; done: "Your earlier messages are backed up" / "If you ever lose every device, sign in on a new one and enter your recovery code." or "Your earlier messages are back" / "They open on this device now, without the code."; error: "The backup did not finish" or "Nothing could be brought back" (+ message, "Try again") (`Badge:187-194`) |
| Recovery on, here | on | "Recovery is on for your account. To bring your messages back on this device, enter your recovery code." Button "Bring my messages back" (`Badge:211-213`) |
| Turn off | | "Turn recovery off? The backup is deleted and your code opens nothing any more." "Yes, turn it off" / "Keep it"; after: "Recovery is off. The backup is deleted and your code opens nothing any more." (`Badge:217`, `Badge:108`) |
| Footer | always | "Only you and the people in the chat can open these messages, not even the server." plus a recovery-dependent sentence (`Badge:226`; the end of the line is cut in my output, not read in full) |
| Sync cards | see `docs/E2E_NEW_DEVICE_AND_HISTORY.md` sections 3.3 and 3.4 | `Prompt:74-143` |
| Backup suggestion | after a day on this device, recovery off, not late | "Back up your messages" / "If you lose your phone, a recovery code brings your messages back on a new one. Only you have the code: not us, and not the company." "Set it up" / "Not now" (`Prompt:129-141`) |
| Unreadable message placeholders | decrypt failures | nine texts in `docs/E2E_NEW_DEVICE_AND_HISTORY.md` section 7.2 (`Socket:29-40`) |
| Toast, key changed | `e2e_key_changed` | "@{user}'s security key changed. Open the lock in the chat header and check the safety number." (`connection.js:42-45`) |
| Toast, contact's new device | `e2e_new_device` | "@{user} added a new device ({labels}). Messages you send them now are encrypted for it too. If that surprises you, check the safety number in the lock at the top of the chat." (`connection.js:47-51`) |
| Failed send | `e2e_send_failed` or an `e2e_*` error | the message is marked failed; a toast shows the server's text, or `e2e_<code>` with the client's message such as "<names> has/have not set up encryption yet." (`connection.js:37-57`, `Socket:419-422`) |
| Attachment | while decrypting | "🔒 Decrypting attachment…" (`MessageList.jsx:345`) |
| Pinned/saved | encrypted item | "Encrypted message" (`PinnedBar.jsx:10`, `SavedMessagesModal.jsx:11`) |
| Feed, new device (server text) | someone's device added to my account | "A new device was added to your encrypted messages" (exact text is built in `sd_feed.erl:567`; I read only the pointer) |

---

## J. Errors and recovery

| Failure | Recovery on the web |
|---|---|
| Server refused: stale device list | Look the named people up again, new envelope with a new `mid`, resend, at most twice; then show the refusal (`Retry:4-33`) |
| Encryption fails on the device | The message is not sent; failed state; no plain fallback (`Socket:418-423`) |
| Socket closed when sending | `e2e_send_failed` with code `disconnected` (`Socket:426`) |
| Peer has no device | `required`: failed send with the names; `optional`: plain (`Client:348-352`) |
| Cannot start (no Web Crypto, no IndexedDB, status failed, 10 devices) | `unavailable` is set; retried at most every 15 seconds on the next send (`Client:90-95`, `Client:98`, `Client:74-76`) |
| Sender key changed | refuse the device, warn, placeholder; the person can trust the new key after checking the safety number (`Client:367-371`, `Client:320`) |
| Unknown sender device | one more lookup, then placeholder (`Client:362-366`) |
| Message from before this device | placeholder; sync or recovery (see the new-device doc) |
| Session replaced | forced sign-out; keys stay (`connection.js:96-99`) |
| Recovery code wrong or not backed up | notes in the dialog; device stays waiting (`Client:225-233`) |

All decrypt failures return a typed code and never garbage (`Crypto:216-217`, `Client:400-402`).

---

## K. Test material

| File | What it covers |
|---|---|
| `docs/e2e-test-vectors.json` | sections `recipient`, `sender`, `registration` (proof), `envelope` (a real envelope + expected plaintext), `expected`, `lateBox` (a box made later), `intermediates`, `rewrap` (positive and negative), `recovery` (code, sealed blob, expected plaintext, refusals) |
| `docs/e2e-attachment-vectors.json` | four encrypted files with fixed key and iv (including 1 byte and all 256 byte values) and eight blobs that must be refused |
| `docs/e2e-message-marks-replies.json` | real server replies for save, pin, unread, edit refused, permissions |
| `docs/e2e-sync-replies.json` | real replies of every sync action for both roles |
| `tools/e2e-kit/e2e-check.mjs` (`envelope`, `proof`, `reference`), `e2e-rewrap.mjs`, `e2e-attachment.mjs`, `new-device.mjs`, `capture-sync-replies.mjs`, and the `make-*-vectors.mjs` generators | checkers and a stand-in new device |
| Web tests: `tests/frontend/e2eCrypto.test.mjs`, `e2eClient.test.mjs`, `e2eHistorySync.test.mjs`, `e2eAttachmentKit.test.mjs`, `e2eRewrapKit.test.mjs` | as named by the existing doc (I did not open them) |
| Backend tests: `connectum-backend/test/connectum_e2e_*_test.mjs` | server rules, required/off modes, sync, backup, kit |

**Missing** (none among the sections of the JSON files above; I did not search the web or backend test files for these):

- a **group** envelope vector (the main `envelope` vector is one conversation; no reference with many boxes or a group label);
- vectors for **`safetyNumber`** and **`deviceFingerprint`**;
- a separate vector for the **padding** frame (4-byte length + bytes, to a multiple of 64); it may be covered inside the `envelope` vector, which I did not check;
- a vector for a **forwarded** message prefix and for **edits** of an envelope;
- a **conversation label** vector for unusual names (upper case, spaces, non-ASCII). `convLabel` only lower-cases and sorts (`Crypto:182-186`); `Socket:23` and `Server` must agree on normalising names, which I did not compare for non-ASCII;
- a reference for the **late-box + signature still verifies** case with a *group* envelope.

---

## L. Known limitations and open questions

### L1. Where the existing docs and the code differ (full list for both files)

Same table as `docs/E2E_NEW_DEVICE_AND_HISTORY.md` section 0 (D1 to D6): out-of-date "any device is a valid target"; missing `e2e.sync.approved` in the API table; the "signing in there signs you out here" sentence; the web never calls `sync.approved`; sign-out does not delete keys; the mode is global, not per organisation. I found no other difference in the parts I compared. On the box rule, `E2E_ENCRYPTION.md` ("For every client") and the code agree: a box for every existing device except the sender's (`Server:497-520`).

### L2. Open questions

| # | Question | Recommendation |
|---|---|---|
| 1 | Does message **search** work on encrypted messages, and where does it run? I did not read the search code. | Check `chat-app` search and the server's search; document the answer. |
| 2 | A group over 200 members cannot send from the web at all (not even plain) while the mode is not `off`. | Decide and document: refuse clearly, or allow plain in `optional`. |
| 3 | Mentions and link previews for encrypted messages: no server-side mention or preview; client-side mention highlighting not traced. | Confirm the intended behaviour. |
| 4 | The signature does not cover the boxes or the conversation recipients, so a server can add or drop boxes (it cannot read). | Decide whether that is acceptable; it is also what allows later boxes. |
| 5 | No forward secrecy; a long-term device key opens every message wrapped for it. | Known and documented; plan a ratchet or MLS later. |
| 6 | Padding is to 64 bytes only; ciphertext length still leaks length roughly. | Accept, or pad further. |
| 7 | The web keeps device keys after sign-out on a shared computer. | Offer "remove this device" at sign-out, or on a shared-computer option. |
| 8 | The group member limit (200) and 250-box limit mean large groups cannot be encrypted. | Document for customers; plan sender keys or MLS. |
| 9 | Attachment blob retention and the nginx upload size on deployed servers were not verified. | Check the deployed configuration. |
| 10 | The mode is global; the texts say "organisation". | Decide on a per-organisation mode, or fix the texts. |
| 11 | `E2E_FRESH_DEVICES_CHANGE.md` and the web's own test files were not opened for this analysis. | Review before relying on them. |

---

## M. What mobile must match exactly, and what it may do differently

### Must match exactly (otherwise messages do not open on the other side)

1. **Envelope:** prefix `e2e1:`, JSON fields and `v:1` (B.2); base64url **without padding** everywhere; the 65-byte uncompressed point format.
2. **Primitives:** ECDH P-256, ECDSA P-256 with SHA-256 (`r||s`, 64 bytes), HKDF-SHA-256, AES-256-GCM with 12-byte iv and the tag appended.
3. **Every bound string**, byte for byte: AAD `e2e1-msg|mid|conv|from|dev`; AAD `e2e1-wrap|mid|recipientDev`; HKDF `salt = base64url-decode(mid)`, `info = connectum-e2e-wrap|recipientDev|senderDev`; signature input `e2e1|mid|from|dev|conv|ts|ek|iv|ct`; registration proof `connectum-e2e-register|user|id|ecdh|sign`; file AAD `e2e1-file`; recovery `info`/AAD strings.
4. **Padding frame:** 4-byte big-endian length + bytes, zero-padded to a multiple of 64; payload JSON `{"v":1,"t":"<text>"}`.
5. **Conversation label** rule (lower case, sorted, `dm:a|b` or `group:name`) and **lower-case** usernames in `from`.
6. **A box for every device that exists now** (fresh `e2e.devices` at every send); the `e2e_stale_devices` retry by `mid`.
7. **Reading a later box:** use the box's own `ek` when present.
8. **The attachment tag** (`kind`, `name`, `size`, `url`, `type`, `e2e:{key,iv}`), the blob layout (ciphertext + tag, no iv or key inside), upload type `application/x-connectum-e2e`.
9. **Recovery** (if offered): alphabet, length, HKDF info and AAD, blob shape, so a code made on one platform opens on the other.
10. **Forward** prefix `↪ [Forwarded by <me> • from <author>]: <text>` if mobile forwards, so both apps render it the same.
11. **Pinning rule** (trust on first use) is behaviour, but if mobile pins differently it will disagree with the web about "key changed".

### May differ

- **Where the keys live** (platform secure storage instead of IndexedDB) and the local database layout.
- **All screens and wording**, as long as the facts are true for a phone (the placeholder for older messages should not say "browser").
- **Caching** of devices (the web uses 5 minutes for reading; mobile may differ as long as sends use fresh lists).
- **Message previews and notifications:** build them on the device after decrypting (the server cannot).
- **Retry counts and polling intervals** (the web uses 2 resends and a 30-second poll).
- **Attachment fallbacks:** the web falls back to a `data:` link on upload failure; mobile should show an error instead.
- **Sync UX** (progress, stop, retry), provided the protocol steps and the rules in `docs/E2E_NEW_DEVICE_AND_HISTORY.md` section 9 are kept.
