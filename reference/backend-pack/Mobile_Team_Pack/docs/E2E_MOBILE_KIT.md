# End-to-end encryption: the kit for another client (the Flutter app)

For the mobile team. The rules are in `E2E_ENCRYPTION.md`; the story in `E2E_SIMPLE_GUIDE.md`. This page is how to **check your client against the app** without guessing.

## What is here

| File | What it is |
|---|---|
| `docs/e2e-test-vectors.json` | Two throwaway test devices (their **private keys are in the file on purpose**), one registration proof and one envelope, all made by the app's own crypto, with every intermediate value (the HKDF key, the additional-data strings, sizes). |
| `tools/e2e-kit/e2e-check.mjs` | A checker. It opens an envelope the way a receiving device does and **stops at the first step that fails, and says what to change**. It is a separate implementation of the spec, using Web Crypto only. |
| `tools/e2e-kit/make-vectors.mjs` | Makes the vectors file again (new keys each time). |
| `tools/e2e-kit/e2e-rewrap.mjs` | The **older device's** job in plain Web Crypto (open its own box, lock the message key for a waiting device): the reference for `docs/E2E_HISTORY_SYNC_MOBILE.md`. `reference` checks the `rewrap` vectors (same bytes out, every bad box refused); `check input.json` checks a box your client made. |
| `tools/e2e-kit/make-rewrap-vectors.mjs` | Adds the `rewrap` section (one-time key and iv fixed, positive and negative cases) to the vectors file without touching the rest. |
| `tools/e2e-kit/new-device.mjs` | A **stand-in for the new device** (`register`, `status`, `read`) to test the older-device side with one phone. See `E2E_HISTORY_SYNC_MOBILE.md`, "Testing the two-device flow". |
| `tools/e2e-kit/capture-sync-replies.mjs` | Captures real replies of the sync actions from a running test server into `docs/e2e-sync-replies.json`. |
| `tests/frontend/e2eKit.test.mjs`, `tests/frontend/e2eRewrapKit.test.mjs`, `connectum-backend/test/connectum_e2e_kit_test.mjs` | Prove the checker opens the app's messages and names ten classic mistakes; that the rewrap reference gives the vector's bytes, agrees with the app's code both ways and refuses the bad boxes; and that the stand-in new device works against a real server. |

Needs Node 22 or newer.

A second reference, `lateBox` in the same file, is the **box made later** for a device added after the message was sent: the same envelope with one more box in `keys` that carries its own one-time key `ek`. Open it with that `ek` (see `E2E_HISTORY_SYNC_MOBILE.md`); the checker does, and names a bad `ek`.

## Use it

**Receive path** (can your client read what the app sends?): open `envelope.text` from the vectors file with the recipient's private key (`recipient.ecdh.pkcs8` or the raw scalar `recipient.ecdh.d`), the device id `recipient.id`, and the sender's signing key `sender.sign.pub`. You must get `{ "v": 1, "t": "e2e1 reference message: ..." }`. If you do not, compare your intermediate values with `intermediates` in the file, in this order: signature input, ECDH secret, HKDF salt, HKDF info, wrap key, wrap additional data, message additional data.

**Send path** (can the app read what your client sends?): make an envelope **for the recipient test device** (public key `recipient.ecdh.pub`, id `recipient.id`), signed by **your own** signing key, conversation `dm:<name a>|<name b>` sorted and lower case. Put it in a file and run:

```
node tools/e2e-kit/e2e-check.mjs envelope input.json
```
```json
{ "text": "e2e1:{...}", "deviceId": "<recipient.id>", "ecdhPrivateKey": "<recipient.ecdh.pkcs8>", "senderSignPub": "<your signing public key, base64url, 65 bytes>", "expectConv": "dm:a|b" }
```

**Registration**: `node tools/e2e-kit/e2e-check.mjs proof input.json` with `{ user, id, ecdh, sign, proof }`, the values you send in `e2e.register`. The server's only answer to a bad proof is "The proof of the signing key is wrong"; this tells you why.

`node tools/e2e-kit/e2e-check.mjs reference` checks the vectors file itself (a self test).

## The older-device side (showing the past on a new device)

The recipe and the steps are in `E2E_HISTORY_SYNC_MOBILE.md`. Here is how to check **a box your client made**:

```
node tools/e2e-kit/e2e-rewrap.mjs reference         # the vectors: same bytes out for fixed inputs, every bad box refused
node tools/e2e-kit/e2e-rewrap.mjs check input.json
```
```json
{ "text": "<the stored envelope, e2e1:{...}>", "targetId": "<the waiting device's id>", "targetEcdhPrivateKey": "<its private key, PKCS8 base64url>",
  "senderSignPub": "<the sender's signing public key>", "item": { "mid": "...", "iv": "...", "w": "...", "ek": "..." }, "expectConv": "dm:a|b" }
```

It puts your `item` into the envelope as the waiting device's box and opens it with the same steps as `e2e-check.mjs`: a wrong box stops at step 5 and says which part of the recipe to compare. To get fixed bytes to compare with, use the `rewrap` section of `docs/e2e-test-vectors.json` (the one-time key and the iv are fixed there).

## The recipe, in one place

```
base64url        A-Z a-z 0-9 - _   with NO "=" padding (Dart's base64Url.encode adds it: strip it)
public keys      65 bytes, uncompressed P-256 point (first byte 0x04), base64url. Not DER, not compressed.
signature        ECDSA P-256, SHA-256, RAW 64 bytes r||s (32 + 32, big-endian). NOT ASN.1 DER (70 to 72 bytes, starts 0x30).
user names       lower case everywhere (from, conv, signed text)
conv             direct: "dm:" + the two names, lower case, sorted, joined by "|"      group: "group:" + name, lower case
mid              16 random bytes, base64url (22 characters)

frame            4-byte BIG-endian length of the JSON + the UTF-8 JSON {"v":1,"t":"text"}, then zero bytes up to a multiple of 64
message          AES-256-GCM, fresh 32-byte key, 12-byte iv, additional data  "e2e1-msg|<mid>|<conv>|<from>|<dev>"
one-time key     a fresh ECDH P-256 pair per message; "ek" is its public half (65 bytes)
for each device  secret = ECDH(ek private, device ecdh public)  (the 32-byte X coordinate)
                 wrap key = HKDF-SHA-256(ikm = secret, salt = base64url-DECODED mid (16 bytes), info = "connectum-e2e-wrap|<recipient dev>|<sender dev>") -> 32 bytes
                 w = AES-256-GCM(wrap key, 12-byte iv, additional data "e2e1-wrap|<mid>|<recipient dev>", the 32-byte message key)  -> 48 bytes
signature input  UTF-8 text  "e2e1|<mid>|<from>|<dev>|<conv>|<ts>|<ek>|<iv>|<ct>"    (ts = milliseconds, as a number)
envelope         "e2e1:" + JSON { v:1, mid, from, dev, conv, ts, ek, iv, ct, sig, keys: { "<device id>": { iv, w } } }
```

## The mistakes the checker names

| Step that fails | Usual cause |
|---|---|
| 1 envelope text | base64 with padding or `+ /`; DER signature (wrong size); compressed or DER public key; upper-case user name; `ts` sent as text |
| 2 conversation | names not lower case or not sorted |
| 3 box for this device | the device list was not fresh: **wrap for the devices that exist now** (ask `e2e.devices` or `e2e.group_devices` just before sending, the sender's own other devices too). This was the cause of the grey "sent before this browser was set up" message on a device that already existed. **The server now refuses such a message with `e2e_stale_devices`** (see below) |
| 4 signature | DER instead of raw; wrong order of the signed fields; wrong signing key |
| 5 open the box | salt is the *text* of `mid` instead of its decoded bytes; info has recipient and sender the wrong way round; missing or wrong additional data on the wrap |
| 6 open the message | additional data does not name the sender device |
| 7 padding | not padded to 64; length prefix little-endian |

## The server refuses a message that misses a device (`e2e_stale_devices`)

A message must have a box for every device that exists now, the sender's own other devices included (the sending device itself may leave its own out). Otherwise the server answers

```json
{ "type": "error", "code": "e2e_stale_devices", "text": "Somebody's devices changed while this message was being written. Send it again.", "mid": "<the mid of the envelope you sent>", "conv": "dm:a|b", "users": ["bob"] }
```

and stores nothing. Your client should look up the devices of `users` again, build a **new** envelope from the same text, and send it again, by itself, without telling the person. Match the refusal to your message by `mid`. The web app tries twice and then shows the error (`chat-app/services/e2eRetry.js`). Details and the rollout switch: `E2E_FRESH_DEVICES_CHANGE.md`.

## For the web team

The same module the browser runs, `chat-app/features/connectumChat/e2e/e2eCrypto.js`, made the vectors, and the checker (a separate implementation) opens them: two implementations agree. Any change to the format must keep `node --test tests/frontend/e2eKit.test.mjs` green and regenerate `docs/e2e-test-vectors.json`.
