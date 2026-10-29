# End-to-end encryption: what the web does and what Flutter must do

Sources (all read from backend `origin/main`, nothing executed against a server): `src/features/connectumChat/e2e/{e2eCrypto,e2eClient,e2eStore,e2eMedia}.js`, `src/services/connectumSocket.js`, `ConnectumChatScreen.jsx`, `axi-chat-backend/src/{sd_e2e,chat_web,chat_cmds}.erl`, `docs/E2E_ENCRYPTION.md`, `tests/frontend/e2eCrypto.test.mjs`. Vectors: `mobile-handoff/e2e-vectors.json` (section 8).
Where this file says "inferred", it is my reading of the code, not something observed live.

## 1. Summary

Every device (a browser, later a phone) owns two P-256 key pairs: one to receive (ECDH), one to sign (ECDSA). It registers the **public** halves with the server, proving it holds the signing key. To send, the sender makes a fresh random AES-256-GCM key per message, encrypts the text with it, and then wraps that key separately for **every registered device of every person in the chat plus the sender's own devices** (one ephemeral ECDH per message, HKDF, AES-GCM). It signs the result. The server stores and relays this "envelope" (`e2e1:` + JSON) as the message text and only checks its shape and that nobody with a device was left out. A reader finds the wrap for its own device id, verifies the sender's signature, unwraps, decrypts. There is no ratchet, no recovery, no backup: lose the device keys and old messages are gone for that device.

## 2. Exact algorithms and encodings

| Item | Value |
|---|---|
| Curve | P-256 (secp256r1 / prime256v1), both ECDH and ECDSA |
| Signature | ECDSA P-256 with SHA-256 |
| KDF | HKDF-SHA-256, 32-byte output |
| Cipher | AES-256-GCM, 12-byte IV, 16-byte tag appended to the ciphertext (WebCrypto layout `ct‖tag`) |
| Random | 16 bytes message id, 12-byte IVs, 32-byte AES key, 16-byte device id |
| Padding | plaintext framed and zero-padded to a multiple of 64 bytes |
| base64 variant | **base64url, no padding** everywhere. The web decoder rejects `=` and any non `[A-Za-z0-9_-]`, and length%4==1 |
| Public key | base64url of 65 bytes `04‖X‖Y` (uncompressed point). Not SPKI, not JWK, not compressed |
| Signature / registration proof | base64url of 64 bytes `r‖s`, each 32 bytes big-endian (IEEE P1363). **Not DER.** The server converts to DER itself (`der_sig`) |
| Device id | 32 lowercase hex chars (16 random bytes). Server regex `^[a-f0-9]{32}$` |
| Message id `mid` | base64url of 16 random bytes = 22 chars. Server regex `^[A-Za-z0-9_-]{22}$`. This is **not** the server's numeric message id |
| Usernames | lower case, trimmed (web also strips `user-` and `@`) |
| Conversation label | DM: `dm:` + both lower-cased names sorted ascending (UTF-16 order), joined by `|` → `dm:alice|bob`. Group: `group:` + lower-cased, trimmed name → `group:design` |
| Plaintext payload | UTF-8 of `JSON.stringify({"v":1,"t":"<text>"})`. `t` is the exact chat text (attachments are the `[ATTACHMENT:{...}]` text, section 6) |

### Framing (padding)
`frame(bytes) = uint32_BE(len) ‖ bytes ‖ zeros`, total length `ceil((4+len)/64)*64`. Reader: length must be ≥4 and a multiple of 64, `len ≤ total-4`; take bytes `[4, 4+len)`; UTF-8 decode must be strict (invalid UTF-8 is an error).

### Strings that get signed or bound (copy exactly, `|` is a literal)
- Registration proof message: `connectum-e2e-register|<user>|<deviceId>|<ecdhB64u>|<signB64u>` (the base64url **strings**, not the raw bytes; `<user>` = lower-case username as the server knows it).
- Message AAD: `e2e1-msg|<mid>|<conv>|<from>|<senderDev>`
- Wrap AAD (per recipient device): `e2e1-wrap|<mid>|<recipientDev>`
- HKDF: IKM = ECDH shared secret (32 bytes, X coordinate), salt = **decoded** `mid` (16 bytes), info = UTF-8 `connectum-e2e-wrap|<recipientDev>|<senderDev>`, output 32 bytes → AES-256-GCM wrap key.
- Signature input: UTF-8 of `e2e1|<mid>|<from>|<dev>|<conv>|<ts>|<ek>|<iv>|<ct>` (the base64url strings of `ek`, `iv`, `ct`; `ts` as a plain integer). **`keys` is not signed.**
- File AAD: `e2e1-file`.

### Envelope JSON (text sent to the server = `"e2e1:" + JSON`)
```
{"v":1,"mid":"<22 chars>","from":"alice","dev":"<32 hex>","conv":"dm:alice|bob","ts":<ms integer>,
 "ek":"<65-byte ephemeral ECDH pub, b64u>","iv":"<12 bytes b64u>","ct":"<AES-GCM ct‖tag, b64u>","sig":"<64 bytes b64u>",
 "keys":{"<recipient dev id>":{"iv":"<12 bytes b64u>","w":"<48 bytes b64u>"}, ...}}
```
Field order does not matter (the signature is over a rebuilt string, and the server re-encodes JSON when it trims `keys`). `v` must be the number 1. `ts` is the sender's clock (Date.now), must be an integer in JSON (not `1.7e12`). `w` = wrapped 32-byte message key + 16-byte tag = 48 bytes (64 chars). Server size caps: `ek`, `sig`, `w` ≤100 chars, `iv` ≤16 chars, `ct` ≤120000 chars, whole envelope ≤120000 chars, 1 to 250 wraps.

### A. Register a device
1. Generate ECDH P-256 and ECDSA P-256 key pairs. Keep the private keys in secure storage.
2. `id` = 16 random bytes as 32 hex chars. `ecdh`, `sign` = public keys as base64url of the 65-byte raw point. `label` = free text ≤60 chars (control chars are stripped).
3. `proof` = ECDSA-SHA256 (r‖s, base64url) over the registration message above, signed with the **signing** private key.
4. `/sd e2e.register {"id","ecdh","sign","label","proof","reqId"}` → `{device}`. Re-registering the same id with the same keys is a no-op; the same id with other keys is `conflict`. Server verifies the proof against `sign`.
5. First call `e2e.status` → `{mode, devices:[mine], maxDevices}`. If `mode` is `off`, do nothing. If the stored device id is not in `devices`, the server dropped it (removed elsewhere): throw the local keys away and register again.

### B. Encrypt a DM (alice → bob)
1. Recipients = all devices of bob (`e2e.devices {"users":["bob","alice"]}` → `{users:{bob:[{id,ecdh,sign,label,ts}], alice:[...]}}`) plus **every** device of alice including this one.
2. `conv = dm:alice|bob`. `mid` = 16 random bytes b64u. `msgKey` = 32 random bytes. `iv` = 12 random bytes.
3. `plain = frame(utf8({"v":1,"t":text}))`. `ct = AES-256-GCM(msgKey, iv, aad=msgAad, plain)` → `ct‖tag`.
4. One ephemeral ECDH P-256 key pair `eph`; `ek` = its public key (65 bytes b64u).
5. For each recipient device `r`: `shared = ECDH(eph.private, r.ecdh)` (32 bytes); `wk = HKDF-SHA256(shared, salt=decode(mid), info="connectum-e2e-wrap|r.id|myDevId", 32)`; `wiv` = 12 random bytes; `w = AES-256-GCM(wk, wiv, aad="e2e1-wrap|mid|r.id", msgKey)`; `keys[r.id] = {iv: b64u(wiv), w: b64u(w)}`.
6. `sig` = ECDSA-SHA256(my sign private key, signatureInput) as r‖s b64u.
7. Wire: `/msg bob e2e1:{...}` (or `/c <cid> /msg bob e2e1:{...}`; `cid_supported` includes `/msg`, `/replydm`, `/groupmsg`, `/replygroup`; edits are `/edit dm bob <id> e2e1:{...}`). The envelope must be a single line (JSON has no raw newlines). Server limit 120000 chars instead of the usual 2000.

### C. Decrypt a DM
1. Text starts with `e2e1:` → it MUST be an envelope (the server also sets `e2e:true` on `history` and `/conversations` items; live events `private`, `group_message` have no flag, so test the prefix).
2. Parse JSON; require `v===1`, strings `mid from dev conv ek iv ct sig`, number `ts`, object `keys`.
3. If an expected conversation is known (DM: `dm:`+sorted(me, peer); history: the thread being read) and `conv` differs → `wrong_conversation`.
4. The server hands you only the wraps for your own currently registered devices. `mine = keys[myDeviceId]`; missing → `not_for_this_device`.
5. Sender signing key = the `sign` of device `(from, dev)` from the directory (`e2e.devices` / `e2e.group_devices`; look up once more if unknown, else `unknown_sender_device`). Verify `sig` over the signature input; fail → `bad_signature`. (Note: verifying needs the sender's device to be **currently registered**.)
6. `shared = ECDH(myEcdhPrivate, ek)`; `wk` as in B.5 with `r.id = myDevId`, `senderDev = envelope.dev`; `msgKey = AES-GCM-decrypt(wk, mine.iv, aad="e2e1-wrap|mid|myDevId", mine.w)`; `plain = AES-GCM-decrypt(msgKey, iv, aad="e2e1-msg|mid|conv|from|dev", ct)`; unframe; parse JSON; `t` must be a string.
7. Any other failure → `decrypt_failed`.

### D. Groups
Same as DM except: `conv = group:<lowercase name>`; recipients come from `e2e.group_devices {"group":"design"}` → `{group, members:{user:[devices]}}` (you must be a member; error `limit` above 200 members); one envelope, up to 250 wraps, 10 devices each. Server rule: every member who has at least one device must have at least one wrap; wraps for non-members' devices are refused. Wire `/groupmsg <group> e2e1:{...}`, reply `/replygroup`. Decrypt identical, expected conv `group:<name>`.

### E. Bindings (what ties what together)
- Sender and conversation: `from`, `dev`, `conv` are in the message AAD and in the signature. A message cannot be replayed into another chat or attributed to another user without failing.
- Recipient device: in wrap AAD and the HKDF info.
- `mid`: HKDF salt, both AADs, signature. It is a client random value; there is **no binding to the server's numeric `id`** and no uniqueness check (inferred: nothing in `sd_e2e.erl` stores seen `mid`s). A server could re-deliver one envelope under a second id or re-serve it later; the reader cannot tell. Store `mid` next to the server id if you want to de-duplicate locally.
- `ts` is signed but not in any AAD, and unverified (clock skew is tolerated). `keys` is not signed: anyone relaying may drop wraps (the server does this on purpose per viewer).

## 3. When the web encrypts

Automatic, never a per-chat switch. In `sendProtected` (connectumSocket.js): if the server `mode` is `off` or the device is not ready, the line goes plain exactly as before. Otherwise DM and group text (new message, reply, edit, attachment tag) is encrypted when **every other person in the chat has at least one registered device** (own devices are always added).
- `mode=optional`: someone without a device → the message is sent **plain** (nobody locked out). `mode=required`: plain text is refused by the server (`e2e_required`); the client throws `peer_not_ready`, nothing is sent.
- If encryption itself fails (directory error, etc.) the message is **never** downgraded to plain; the bubble is marked failed.
- Pinning interaction (risk, inferred from `#plan`/`#checkPins`): a peer device whose keys changed is *dropped from the recipients*; if that was all of a person's devices, the person counts as "has no devices" and in `optional` mode the message silently goes **plain**. Do not copy this; fail instead.
- Never encrypted: forms, `#` commands, topic messages, AI chat/relay, global room (server refuses envelopes with `e2e_unsupported`), host chats (`/hostmsg`, the web passes `e2eTarget=null`), the local workspace. Reactions are plain metadata outside the envelope.
- Mode is organisation-wide, read from `e2e.status`. The mobile "encrypted thread" test is: the thread has history items with `e2e:true`, or `mode != off` and the peer has devices (`required` mode makes everything encrypted).

## 4. Keys on the web, lifecycle, "can't be read"

- **Storage:** IndexedDB database `connectum-e2e`, one `device` record per username with the **non-extractable** `CryptoKey` objects, plus `pins` (`user|deviceId` → first-seen `{ecdh, sign}`, trust on first use). No export, no backup, no recovery, no passphrase.
- **Sign-out:** the web does not delete the keys. `removeThisDevice()` exists but nothing in `src/` calls it (grep), so signing out of the web leaves the device registered and the keys in IndexedDB; signing in again on the same browser reuses them. Keys are lost only when site data is cleared, or when the device is removed.
- **Removal:** `/sd e2e.remove {"id"}` (lock dialog → "Remove"). The server deletes the record and pushes `e2e_devices_changed {user}`; every client drops that user's cached directory. A removed device that is still running notices on the next `e2e.status` (id missing) and discards its keys.
- **Limits:** 10 devices per person (`limit` error; web `init` also refuses to register an 11th), registration rate limit 30 per hour per user (`rate_limited`), `e2e.devices` 600 per 600 s, 1 to 50 users per call. The directory is cached 5 minutes client-side.
- **Newly registered device can read:** only messages whose envelope contains a wrap for it, i.e. messages sent **after** it registered *and* whose sender had it in their directory. Not readable: all earlier messages (history is the same stored envelope, there is no re-wrap), and messages sent in the up-to-5-minute window when the sender's cache was stale (web invalidates on `e2e_devices_changed` if its socket is open). The server only demands one wrap per person, so a partial wrap is accepted.
- **Why the web shows "This message can't be read on this device" even for its own sends** (inferred from code, not reproduced): `E2E_REASON` maps only `not_for_this_device`, `key_changed`, `bad_signature`; every other failure (`unknown_sender_device`, `no_device`, `decrypt_failed`, `wrong_conversation`, `bad_payload`) falls back to the same text. Real causes: (1) browser data was cleared or the device was removed and re-registered, so a new device id; messages sent under the old id have no wrap for it; (2) the old sending device no longer exists in the directory, so the signature key lookup returns nothing (`unknown_sender_device`): history from a removed device is unreadable by everyone, including the other party; (3) `init` failed (IndexedDB unavailable, registration error, 10-device cap) so there is no device (`no_device`) while history still has envelopes; (4) the message came from another device of the same user that registered before this one. Mobile should show distinct reasons.

## 5. `#` and `@` lines in an encrypted thread (web behaviour)

- **`#command`:** `handleSend` checks `trimmed.startsWith('#')` and a client-side catalog match; a match goes to `handleRouteHashCommand`, which does `connectumSocket.send(rawLine)`: the **raw line, unencrypted**. The server (`chat_web:handle_line` → `chat_cmds:run`) rewrites `#dm alice hi` to `/msg alice hi` and runs it. Consequence (inferred): in `optional` mode `#dm`/`#msg`/`#pm`/`#reply*`/`#groupmsg`/`#gm` deliver **plaintext** into the encrypted DM/group, mixing plain and encrypted messages, with the web showing an optimistic local bubble; in `required` mode the server refuses (`e2e_required`), the web toasts it and marks the send failed. `##text` is the escape for a literal `#` but it goes to `broadcast_text`, i.e. the **global room**, not the thread. A `#` not followed by a letter (`#1 priority`), or a line that matches no known command, is ordinary text and is encrypted normally.
- **`@user`:** the web only treats a leading `@name body` specially in **My Workspace** (it calls the normal `sendDM`/group send, so it is encrypted when the target allows). In any real DM/group thread `@bob hi` is ordinary text, encrypted verbatim. There is no server-side `@` rewriting.
- **Recommendation for Flutter:** in an encrypted thread, never forward a messaging `#` command raw. Either send the line as ordinary encrypted text, or block it with a notice. Non-messaging `#` commands (`#notifications`, `#help`) do not carry the thread's text and can still run.

## 6. Media

Yes, encrypted client-side. Bytes: AES-256-GCM, fresh random 32-byte key and 12-byte IV, AAD `e2e1-file`, output `ct‖tag` (length = plaintext+16). Upload with `POST /upload` multipart field `file`, filename `<name>.e2e`, part content type `application/x-connectum-e2e`, same auth as other uploads (server: min 28 bytes, no magic-byte check, size cap video+512 KB). The message text is the usual `[ATTACHMENT:{"kind","name","size","url","type","e2e":{"key":"<b64u>","iv":"<b64u>"}}]` **inside the envelope payload**, so the key never reaches the server. Receivers download the blob, decrypt, show from a local file. GIFs picked from a provider are downloaded, re-encrypted and uploaded (so members do not hit the provider); stickers/small images travel as `data:` URLs inside the payload (≤50000 chars); on download failure the plain link goes inside the encrypted message. `name`/`type` stay inside the envelope; the server sees only the opaque blob and its size.

## 7. Flutter feasibility (pub.dev checked 2026-10-29)

Needs: P-256 ECDH, ECDSA-SHA256 with **raw r‖s**, HKDF-SHA256, AES-256-GCM with AAD, SHA-256, a CSPRNG, and secure key storage on Android and iOS.

| Package | Version / date | Verdict |
|---|---|---|
| `webcrypto` (google) | 0.6.1, 2026-05-22, Dart ^3.10 | **Recommended.** Mirrors the WebCrypto API the web code uses: `EcdhPrivateKey/EcdhPublicKey.importRawKey` (raw 65-byte points), `deriveBits`, `EcdsaPrivateKey.signBytes(data, Hash.sha256)` returns the WebCrypto **r‖s** format, `EcdsaPublicKey.verifyBytes`, `HkdfSecretKey.deriveBits(length, hash, salt, info)`, `AesGcmSecretKey.encryptBytes(data, iv, additionalData:)`, `fillRandomBytes`. Keys export as PKCS8/JWK for storage. Native BoringSSL via FFI on Android/iOS. Cost: the build hook compiles BoringSSL, needs `cmake` and a C compiler (cmake exists at `/opt/homebrew/bin/cmake` on this Mac; Android NDK/CI not checked). No `deriveKey` (not needed, use `deriveBits`). |
| `pointycastle` | 4.0.0, 2025-02-19 | Fallback. Pure Dart, no native build: `ECDHBasicAgreement`, `ECDSASigner` (gives `r`,`s` as BigInt, you must left-pad each to 32 bytes and build r‖s yourself), `HKDFKeyDerivator`, `GCMBlockCipher` with `AEADParameters` (appends tag). More hand assembly, slower for 250 wraps, I did not verify these APIs against the vectors. |
| `cryptography` | 2.9.0, 2025-11-21 | **Not usable alone.** Its pure-Dart `DartEcdsa` (and ECDH) methods throw `UnimplementedError` on the VM (source read); it only works with `cryptography_flutter` or in a browser. |
| `cryptography_flutter` | 2.3.4, 2025-11-21 | Not recommended. README says NIST ECDH/ECDSA are for **Apple** platforms; an Android path exists in the Kotlin source but its signature encoding (Java gives DER, WebCrypto is r‖s) is unverified. |
| `flutter_secure_storage` | 11.2.0, 2026-09-16 | **Recommended for the private keys:** store the two PKCS8 blobs (base64) in Keychain/Keystore. Unlike the web, native keys are exportable bytes, so storage protection is the only barrier. Use `first_unlock_this_device`-style accessibility so keys do not sync to iCloud backup (confirm option names when integrating). |
| `sqflite` (already used) | | Pins, directory cache, `mid`, device id. Public data only. |

Pitfalls (all verified in the web code or the server): signatures are r‖s not DER (server rejects anything but exactly 64 bytes); public keys are raw 65-byte points, never SPKI; base64url without padding both ways (reject `=`); the HKDF salt is the **decoded** `mid`, the info is text; the registration proof signs the **base64url strings**; AES-GCM output must be `ct‖tag(16)`; use integer `ts`; lower-case names; strict UTF-8; Dart `jsonEncode` of a map keeps insertion order but order does not matter here; generate the ephemeral key per message, never reuse it; ECDH output must be the 32-byte X coordinate (what both WebCrypto `deriveBits(256)` and BoringSSL return).

## 8. Test vectors

`mobile-handoff/e2e-vectors.json`, produced by running the web's own `e2eCrypto.js` (unchanged, copied to a scratch dir, Node v22.23.4) with fixed device keys and injected randomness (a queue that replaces `getRandomValues` and `subtle.generateKey` for the AES key and the ephemeral ECDH key). Contents: five fixed test devices (alice1, alice2, bob1, carol1, carol2, with private scalars and public keys; **test keys, never use them for anything real**), a registration proof, four envelopes (DM with two sender devices, unicode DM, padding-edge DM, group with a two-device member) each with the random inputs, AAD strings, HKDF info, signature input, the full envelope, the shared secret / wrap key / message key / padded plaintext per recipient, and the plaintext each device must obtain; six negative cases with the error code the web returns; a file-encryption vector; safety number and fingerprint; base64url edge cases.
- Every envelope was also decrypted by an **independent** `node:crypto` implementation written from this spec: web code and spec agree.
- Two runs give identical `mid/ek/iv/ct/keys`. **ECDSA signatures are not reproducible** (random nonce in WebCrypto): `sig` and the registration `proof` differ per run. The Dart code must (1) *verify* the vector `sig`/`proof` against the listed public keys and (2) produce signatures that the web (or the Node reference) verifies. For byte-exact checks of the encrypt path in Dart, inject the listed random values and compare everything except `sig`, then verify `sig`.
- To inject randomness in Dart: give the encrypt function an optional `RandomSource` (default CSPRNG) used in tests only; call order is `mid(16)`, `msgKey(32)`, `iv(12)`, `ephemeral private scalar(32)`, then one `wrapIv(12)` per recipient in the listed order.

## 9. Staged build plan (one developer who knows this codebase; days include debugging against the vectors)

| Stage | Scope | Effort |
|---|---|---|
| a. Device keys + registration | add `webcrypto` and `flutter_secure_storage`, make Android/iOS build with it, key generation, PKCS8 storage, `e2e.status`/`e2e.register`, device id, tables for pins/directory, pass vectors for proof/verify | 3 to 4 d (+1 d if the native build fights back) |
| b. Decrypt incoming DMs | `openEnvelope` port, directory lookup, history, `/conversations` previews, live `private`, edits, chat-list text, per-reason placeholders, decide plaintext-at-rest vs envelope-at-rest, lift the read-only block for reading | 3 to 4 d |
| c. Send DMs | plan (recipients), pins, `buildEnvelope`, outbox integration (encrypt once and store the envelope so a retry reuses bytes and `cid`), replies, edits, error mapping (`e2e_required`, `e2e_peer_not_ready`, `bad_envelope`, `too_long`) | 3 to 4 d |
| d. Groups | `e2e.group_devices`, group conv label, membership changes, large envelopes | 2 to 3 d |
| e. `#` / `@` | encrypted-thread composer rules from section 5 | 1 d |
| f. Edge cases + UI | device list/removal screen, key-changed warning and safety number, `e2e_devices_changed`, unknown sender device refetch, new group members, local re-registration when removed, cap of 10 devices, retry on `bad_envelope` after a stale directory | 4 to 5 d |
| g. Media | encrypt/upload/download/decrypt, thumbnails, GIF/sticker cases | 3 to 4 d |

Total about 4 to 5 weeks for everything; a–c is about 2 weeks.

Risks: native build of `webcrypto` on CI and both OSes; plaintext at rest in SQLite for decrypted messages (decision below); stale directory (5 min) → `bad_envelope`/missed new device; offline send requires directory data, which conflicts with "write row and outbox at once" (encrypt at flush time, or fail visibly when no directory is cached; never send plain in `required`/after a key change); key loss on reinstall (new device, history unreadable); no forward secrecy; unaudited custom composition.

Security review points: key storage accessibility and backup exclusion; plaintext in SQLite and in notifications/previews/logs/screenshots; no silent downgrade to plain (including the web's pin-drop quirk); TOFU pinning and what the user sees on a key change; signature verification must fail closed; constant-time not needed but never log keys/plaintext; the `REACT`-style debug prints must not print envelopes; random source quality; unique IVs (random 96-bit is fine here since every key is used once); device id and label leak metadata; server is trusted for the directory (a malicious server can add a device), so safety number UI matters; replay of identical envelopes (no `mid` dedupe).

## 10. Smallest demo, and what is unclear

Smallest demo: read and send text in **one** encrypted DM, mode `optional` or `required`, peer (web user) already has a device.
1. Register this phone (stage a, store keys in secure storage).
2. Decrypt `e2e1:` text in that thread on live events and `history` (stage b without edits, previews or other thread types).
3. Send: fetch `e2e.devices` for `[peer, me]` every time (no cache), TOFU-pin, build the envelope, `/msg peer e2e1:{...}`. Fail visibly on any error, never send plain.
Left out: groups, attachments, edits/replies, `#`/`@`, device management UI, safety number, key-change UI, offline queueing, notifications previews, reactions logic. About 5 to 7 days.
What can go wrong in the demo: the existing e2e messages in that thread (ids 1 and 2 in `live-shapes.md`) were sent before the phone registered, so they will show "can't be read"; the web user's browser may not know the new phone for up to 5 minutes (unless its socket is open), so the first phone → web message is fine but the first web → phone message may carry no wrap for the phone; the 10-device cap and the 30/hour registration limit during repeated reinstall testing; a mismatch in any of the encodings in section 7 shows only as `bad_signature`/`decrypt_failed`, so work through the vectors first.

Unclear or risky in the scheme itself:
- No recovery or backup; the web even keeps keys after sign-out while mobile will want clearer rules.
- Optional-mode silent plain fallback, plus the pin-drop quirk, plus raw `#dm` into an encrypted thread: three ways plaintext can enter an "encrypted" conversation. The doc itself says it is not independently audited.
- Messages from a removed device become unverifiable for everyone (signature key lookup needs the live directory).
- No `mid`-vs-server-id binding and no replay protection.
- `keys` is unsigned (harmless for confidentiality, but a recipient cannot tell which wraps were stripped).
- Open question for the user: should the mobile composer allow forms and `#` messaging commands in an encrypted thread (see `forms-live.md`)? Section 5 recommends encrypting the line as text.

## Not verified
- Nothing was run against the real server (as instructed), so server-side behaviour is read from Erlang source only; the deployed commit and each organisation's mode are unknown.
- No browser run: the web UI texts and flows come from source.
- The `webcrypto` Android/iOS build, runtime behaviour, and performance were not tried; `pointycastle` and `cryptography_flutter` Android encoding were not tested.
- Maximum WebSocket frame size for a 50 to 120 KB `/groupmsg` or `/c ... /msg` line was not checked.
- `/c <cid>` with an envelope is read from `with_cid`/`cid_supported`, not exercised.
- Attachment upload headers (`uploadAuth()`) are as in `ai-and-misc.md`, not re-read here.
