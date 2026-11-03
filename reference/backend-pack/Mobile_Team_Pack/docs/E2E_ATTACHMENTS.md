# Encrypted attachments (for the mobile app)

*In plain English: a file sent in an encrypted chat is locked on the sender's device before it is uploaded. The server stores only scrambled bytes. The key to unlock the file travels inside the encrypted message, so only the people in the chat can open it.*

The web app does this today for **files, photos, videos and voice notes** in encrypted direct chats and groups. The code is `chat-app/features/connectumChat/e2e/e2eMedia.js` (`uploadEncrypted`, `openEncryptedMedia`) and `e2eCrypto.js` (`encryptFile`, `decryptFile`). The overall design is in `E2E_ENCRYPTION.md`.

## When a file is encrypted

- The chat is encrypted when **every person in it has a registered device** (the lock in the chat header). Then every file is encrypted. There is no setting to choose.
- If someone in the chat has no keys yet (mode `optional`), the web app sends the file **plain**: the normal upload, a tag with no `e2e` part. The receiver sees no lock.
- If the encrypted upload fails (no network, too big), the web app currently falls back to putting the file inside the message as a `data:` link. That stays inside the encrypted message, but it is large; the mobile app should show an error and let the person retry instead.

## The recipe

| Step | What |
|---|---|
| Key | 32 random bytes, new for every file |
| iv | 12 random bytes, new for every file |
| Cipher | AES-256-GCM |
| Additional data | the UTF-8 text `e2e1-file` (not the file name, not the message id) |
| Blob | the ciphertext **followed by the 16-byte tag**, nothing else. The key and iv are **not** in the blob. |
| Text form of key, iv | base64url, no padding |

So the blob is always **the file's size + 16 bytes**. The smallest blob the server takes is 17 bytes (a file of one byte).

## Upload

`POST /upload`, header `Authorization: Bearer <session token>`, `multipart/form-data` with one part named `file`:

- the part's **content type** must be exactly `application/x-connectum-e2e` (parameters are ignored, upper or lower case is fine);
- the part must have **a file name**. The web app sends `<original name>.e2e`. The server does **not** check what it is: it never uses it, and it stores the file as `<48 random hex>.e2e` whatever you send. A part with no file name is refused (400);
- the reply is `{ "url": "/uploads/<48 hex>.e2e", "type": "application/x-connectum-e2e", "size": <bytes> }`.

Refusals: wrong content type 415 (also when the blob is shorter than 17 bytes), empty 400, over the size 413, no sign-in 401, too many uploads 429.

## The attachment tag

After the upload, the message text is

```
[ATTACHMENT:{"kind":"file","name":"hello.txt","size":"1 KB","url":"/uploads/<48 hex>.e2e","type":"text/plain","e2e":{"key":"<base64url>","iv":"<base64url>"}}]
```

and this whole text is encrypted like any other message (`E2E_ENCRYPTION.md`). `kind` is `file`, `image`, `video` or `audio`. `name` and `type` are the **original** file's, for showing it; the server never sees them. The ready-made examples are in `e2e-attachment-vectors.json` (`positive[].tag`).

To open it: read the tag, download `url`, decrypt with `key` and `iv`, show the result with `name` and `type`. If decryption fails (wrong key, damaged, cut short) show "could not open this file"; do not show the bytes.

## Limits

| What | Limit |
|---|---|
| The app's own limit on an encrypted blob | 25.5 MB (a 25 MB video plus the tag) |
| **What actually gets through today** | **10 MB**: nginx in front of the server has `client_max_body_size 10m` for `/upload`. A bigger body gets 413 from nginx before the app sees it. This is below the app's own 20 MB for documents and 25 MB for video. |
| Uploads per minute | 20 per network address (shared by everyone behind one office address) |
| Media allowance per person | the same allowance as plain uploads |

Plan for 10 MB until the nginx value is raised.

## Check your work

- `e2e-attachment-vectors.json`: four real encrypted files with the key and iv fixed (a text file, **one byte**, all 256 byte values, a 100,000-byte picture) so the blob is the same bytes every time, the matching tag for each, and eight blobs that **must be refused** (one bit changed in the data or the tag, tag cut off, iv put in front of the blob, wrong key, wrong iv, shorter than the tag, a 16-byte key).
- `node tools/e2e-kit/e2e-attachment.mjs reference` checks the vectors with plain Web Crypto, written apart from the app.
- `node tools/e2e-kit/e2e-attachment.mjs check input.json` opens a blob **your** app made: `{ "blob": "<base64>", "key": "...", "iv": "...", "plaintext": "<base64, optional>" }`. If it fails it says what to look at (key and iv sizes, the additional data, the blob layout).
- The common mistakes: the iv put in front of the blob; a 16-byte key; no additional data (or the file name as additional data); standard base64 where base64url is expected; padding on the base64url text.

## How it is tested

- `tests/frontend/e2eAttachmentKit.test.mjs`: a file the web app encrypted opens with the independent kit and the other way round, for sizes from 1 byte to 70,000; every vector; every refusal; the tag is read by the app's own parser.
- `connectum-backend/test/connectum_e2e_attach_test.mjs`: the server side (type, size, file-name handling, 17-byte minimum, sign-in, rate limit, the bytes come back exactly).
- `tools/ui-audit/e2e-attachment.e2e.mjs`: a real browser. It attaches a file in an encrypted chat and checks what was posted (the locked type, nothing readable), what the server holds, that the other person decrypts the exact file, and that a chat with someone who has no keys sends the file plain.
