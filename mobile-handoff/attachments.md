# Attachments in chats (images, files, video, voice)

Read-only investigation, 2 Nov 2026. Sources: backend and web chat client on `origin/main` of `~/Development/Axi-apps/connectum` (commit `3063d3ed`, fetched, nothing modified). Paths below are repo-relative to that checkout; the web client is `chat-app/`, the backend is `connectum-backend/src/`. Anything the code does not answer is in section 9. Complements `ai-and-misc.md` section 2.1 (which has the same upload facts in short form; this file adds the message shape, permissions, encryption, web UX, plan and questions, and corrects two points, see "Corrections" at the end).

## 1. The mechanism in one paragraph

Sending a file in a DM, group, host or global chat is **two independent steps**: (1) `POST /upload` (plain HTTP, multipart) stores the bytes and returns a relative URL; (2) the client sends an ordinary chat message whose **text** is a tag `[ATTACHMENT:{json}]` that carries that URL. The WebSocket protocol has no attachment command and the server never parses the tag (no `ATTACHMENT` string exists anywhere in `connectum-backend/src`). To the server it is a text message of at most 2000 characters. So attachments reuse the whole send path already built: outbox, `cid`, acks, receipts, history, edits, delete.

`/api/sd/files` (and its `/link`) is a **different** mechanism for files attached to forms and download options. The web chat does not use it for chat attachments (only for reports and form fields, `MessageList.jsx:602`). It is described in section 1.4 because the task asked for `/link`.

## 2. Endpoints and commands

### 2.1 Upload: `POST {origin}/upload`

| Item | Value | Code |
|---|---|---|
| Route | `POST /upload` (and `GET /uploads/<name>`), proxied by nginx to the Erlang HTTP listener | `http/chat_web_http.erl:114-121`; nginx `nginx/setup-tls.sh:93-106`, `nginx/connectum.conf.reference:75-85` |
| Origin | Same host as the WebSocket: `https://<HOST>/upload` (web tries `connectumApi.getServerOrigin()` = REST base minus `/api/sd`, then the page origin) | `chat-app/services/connectumApi.js:168-216` |
| Request | `multipart/form-data`, **one file part**. The field name is ignored: the first part with a `filename` is taken. Part `Content-Type` is the declared mime (parameters like `;codecs=opus` are stripped, compared lower-case). `Content-Length` is **required** (no chunked bodies: `{error,no_length}` becomes `400 Bad request`; Dio's `FormData` with `MultipartFile.fromFile` sets it) | `chat_web_upload.erl:58-77`, `96-118`, `154-174`, `226-232` |
| Auth | `Authorization: Bearer <token>` (the same token as REST and the WebSocket handshake). No header: allowed only in a non-strict (open) org; in a strict Connectum org `401 "Sign in to upload."`. Expired token: `401 "Session expired. Sign in again."`. The token only identifies the uploader for the quota; it does not tie the file to a conversation | `chat_web_upload.erl:35-44`; header built by `uploadAuth()` `connectumApi.js:12-18` |
| Success `200` | `{"url":"/uploads/<48 hex>.<ext>","type":"<normalised mime>","size":<bytes, number>,"name":"<cleaned original name>"}`. `url` is **relative**: prefix with the origin. `name` has no path, no control chars, no `"` or `\`, max 100 chars | `chat_web_upload.erl:270-289`, `333-339` |
| Stored name | `random_hex(24)` = 48 hex chars (192 bits) + extension from the mime. The client's file name is never used on disk | `chat_web_upload.erl:271-272`, `341-356` |
| Errors (body `{"error":"<text>"}`) | `400` empty file / "No file found in upload" / "Expected multipart/form-data" / "Bad request"; `401`; `413` too large ("File too large (max N MB)", N = the type's limit) or quota ("Chat files" allowance, message from `sd_allowance`); `415` type not allowed ("Only images, voice notes, video, PDF, Office documents or text files are allowed") or "File content doesn't match its declared type"; `429` "Too many uploads -- slow down"; `502` "The file could not be saved: ..." (storage place down or misconfigured) | `chat_web_upload.erl:33`, `36`, `40`, `68`, `71`, `234`, `241`, `250`, `264`, `288`, `463-473` |
| Rate limit | **20 uploads per 60 s per client IP** (checked before the body is read; `X-Real-IP` from nginx). Per IP, not per user: many phones behind one NAT/office Wi-Fi share it | `chat.hrl:27-28`, `chat_upload_limiter.erl:43-66` |
| Quota | Signed-in uploads are counted per user in the "media" ("Chat files") allowance and refused with `413` when full | `chat_web_upload.erl:257-268`, `core/sd_allowance.erl:33` |

Allowed types, limits and stored extension (the whole table is code, `chat_web_upload.erl:8-22`, `328-331`, `341-356`):

| Class | Declared mime accepted | Limit | Ext | Magic-byte check (`:294-326`) |
|---|---|---|---|---|
| Images | `image/png`, `image/jpeg`, `image/gif`, `image/webp` | **8 MB** | png jpg gif webp | PNG, JPEG `FFD8FF`, `GIF87a/89a`, `RIFF....WEBP` |
| Voice / audio | `audio/webm`, `audio/ogg`, `audio/mp4` | **8 MB** | webm ogg m4a | EBML, `OggS`, `....ftyp` |
| Video | `video/mp4`, `video/webm`, `video/quicktime` | **25 MB** | mp4 vwebm mov | `....ftyp`, EBML |
| Documents | `application/pdf`, docx, xlsx, pptx (OOXML mimes), `text/plain` | **20 MB** | pdf docx xlsx pptx txt | `%PDF-`, `PK\3\4` for OOXML, text must be UTF-8 without NUL |
| Encrypted blob | `application/x-connectum-e2e` | video + 0.5 MB (**25.5 MB**) | e2e | only `size >= 28` (no signature) |

Not accepted (so a picker must filter or convert): **HEIC/HEIF** (iPhone photos), `image/bmp`, `image/svg+xml`, `.doc`, `.xls`, `.ppt` (old Office), `text/csv`, `application/zip`, `audio/mpeg` (mp3), `audio/aac`, `audio/wav`, `video/x-matroska`, `video/3gpp`. The web composer's file input is `accept="*/*"` (`Composer.jsx:915-921`) and its comment mentions ZIP, but the server answers `415`.

Hard request cap: body at most 26 MB (`MAX_BODY_SIZE` = video 25 MB + 1 MB, `chat_web_upload.erl:11`), larger gets `413 "File too large (max 25 MB)"` (`:71`, with the body drained first so the client sees the JSON, not a reset).

**Deployment trap (not a code fact, a config fact).** nginx in front of `/upload` has `client_max_body_size 9m` (`nginx/setup-tls.sh:97`) or `10m` for the whole server (`nginx/connectum.conf.reference:31`, no override in its `/upload` block). Documents up to 20 MB and video up to 25 MB are accepted by Erlang but **nginx answers `413` first** (an nginx HTML error page, not the JSON `{"error"}`). Practical limit today is about 9 MB for everything unless production differs. See question 1.

Response timing/streaming: the server reads the whole body into memory, validates, then writes. There is no resumable or chunked upload. Progress can only be measured on the client (bytes sent).

### 2.2 Download / display: `GET {origin}/uploads/<name>`

| Item | Value | Code |
|---|---|---|
| Auth | **None.** No header, no cookie, no check of who asks, which conversation or which organisation. The 192-bit random name is the only secret | `chat_web_http.erl:114-118`, `chat_web_upload.erl:362-379` |
| Name check | rejects empty, `/`, `\`, `..` (404) | `chat_web_upload.erl:431-435` |
| Response | `200` with `Content-Type` from the extension (`chat_web_upload.erl:437-458`), `X-Content-Type-Options: nosniff`, `Cache-Control: no-cache`, `Accept-Ranges: bytes`, `Connection: close`. Documents (pdf, OOXML, txt) also get `Content-Disposition: attachment` (no `filename`: the saved name is the random one, so the app must supply the real name from the tag) | `chat_web_http.erl:151-170` |
| Range | `Range: bytes=N-M` and `bytes=N-` give `206` with `Content-Range` (for audio/video seeking); other forms get the full `200` | `chat_web_upload.erl:388-429` |
| Missing | `404 "Not found"`; also when a cloud-stored file is not found in any configured storage place | `:372-377` |
| Cache | `no-cache` means "revalidate", but there is no `ETag`/`Last-Modified`, so every revalidation re-downloads. A mobile client **must cache by URL itself** (the URL is immutable: random name, content never changes) | `chat_web_http.erl:167` |
| Whole file in memory | the server reads the full file (also from the cloud store) before sending | `:368-377` |

There is **no thumbnail, no resize, no preview endpoint** for chat files (grep for `thumb` in backend and web: nothing). Images are served as uploaded. Video has no poster. A "preview" in the web is the browser scaling the original `<img>`/`<video>`.

The `Content-Type` is derived from the extension in the URL, so the app can tell image/video/audio/document from the URL even without the tag.

### 2.3 WebSocket commands involved

None for the file itself. The message that carries the URL uses the usual commands, all with `cid` support (`chat_web.erl:1068-1069`: `/msg`, `/replydm`, `/groupmsg`, `/replygroup`, `/hostmsg`):

| Target | Command | Notes |
|---|---|---|
| DM | `/c <cid> /msg <user> [ATTACHMENT:{...}]` | `chat-app/.../chatActions/attachFile.js:63-64` uses `sendDM` (plain `/msg`); the app should use `cid` as for text |
| Group | `/c <cid> /groupmsg <group> [ATTACHMENT:{...}]` | `attachFile.js:57-59` |
| Host | `/c <cid> /hostmsg <hostKey> [ATTACHMENT:{...}]` | `attachFile.js:60-62` |
| Global | `/<text>` (plain broadcast, no `cid`) | `attachFile.js:54-56` |

Length rule: the tag is part of the text, so it is bound by `MAX_MESSAGE_LEN` = **2000 characters** (`chat.hrl:6`, enforced `chat_web_send.erl:28-33`, `56-60`; the over-limit reply is `{"type":"error","text":"Message too long (max 2000 chars)"}`). An encrypted envelope has its own 120 000 limit (`security/sd_e2e.erl:30`). The web drops `url` when it is 1800 chars or longer (`attachFile.js:28-30`); a normal `/uploads/<48hex>.ext` URL is about 62 characters.

### 2.4 `/api/sd/files` and `/link` (forms and options, not chat)

Used for form `file` fields and download options. Listed for completeness; mobile does not need it for chat attachments.

| Call | Detail | Code |
|---|---|---|
| Upload | `POST /api/sd/files?name=<enc>`, raw bytes body, `Content-Type: <mime>`, Bearer. `200 {ok,data:{file:{id,name,mime,size,by,ts}}}`. 10 MB default (`CONNECTUM_MAX_FILE_MB`) | `chat-app/services/connectumFiles.js:33-43`, `forms/sd_files.erl:34-40` |
| Download | `GET /api/sd/files/<id>` Bearer: bytes, always `application/octet-stream` + `Content-Disposition: attachment; filename*=UTF-8''<enc>` + `X-File-Name`, `Cache-Control: private, no-store` | `http/sd_http.erl:184-190`, `send_attachment` (`~:436`) |
| Link | `GET /api/sd/files/<id>/link` Bearer: `{ok,data:{url,name,size}}`. `url` is an AWS-SigV4 presigned GET valid **60 s** (`CONNECTUM_STORAGE_LINK_SECONDS`, clamped 5..900), or `null` if the file is on the server's disk (then use the plain download). The web asks `/link` first and falls back | `sd_http.erl:422-428`, `forms/sd_files.erl:160-173`, `connectumFiles.js:48-64`, `docs/FILE_STORAGE.md` ("Short-lived download links") |
| Permission | uploader, an admin, a download option that targets the file, or a visible submission that contains it | `forms/sd_files.erl:132-144` |

Chat uploads (`/upload`) never get a `/link`: they are served by the Erlang process through `GET /uploads/<name>` from disk or from the cloud store (`chat_web_upload.erl:372-377`), so large chat files do pass through the server.

## 3. The message with an attachment

The server stores and relays `text` only. Nothing else (no mime, size, dimensions or file id field) exists on a message row. Everything is inside the tag, built in `attachFile.js:42-50`:

```
[ATTACHMENT:{"kind":"image","name":"IMG_0042.jpg","size":"1.2 MB","url":"/uploads/9f3a...e1.jpg","type":"image/jpeg"}]
```

| Field | Type / value | Notes |
|---|---|---|
| `kind` | `"image"` \| `"video"` \| `"audio"` \| `"file"` | chosen by the web from the file's mime prefix (`Composer.jsx:622-625`): `image/*` image, `video/*` video, `audio/*` audio, else file. Voice notes are `kind:"audio"` |
| `name` | string | original file name as the picker gave it, **not** the server's cleaned `name` (voice notes: `"Voice note (0:07)"`) |
| `size` | **string**, human readable (`"1.2 MB"`, `"340 KB"`), or `""` | the web formats it itself (`Composer.jsx:615-617`); the server's numeric byte `size` is not forwarded. The parser accepts a number too (`chatMessages.js:41`) |
| `url` | string | the relative `/uploads/<name>` from the upload response, or (encrypted chats) the `.e2e` blob URL. Resolve against the server origin (`MessageList.jsx:30-39`: `http(s):`, `data:`, `blob:` kept; `/x` gets the origin prefix). Empty string if it was a long data URL (web fallback bug, see section 6) |
| `type` | string | the file's mime as the browser reports it (`file.type`, may be `""`); the web does not use the server-normalised `type` for the tag |
| `e2e` | `{"key":"<b64url>","iv":"<b64url>"}` | present only for encrypted attachments (section 5) |

What the tag does **not** carry: image width/height or aspect ratio, video duration/poster, thumbnail, pixel count, checksum, caption. Voice-note duration is only inside the display name `Voice note (m:ss)`; the web composer also passes a `duration` field to its UI but `wireMeta` (`attachFile.js:42-49`) does not include it. So a receiver cannot lay out an image bubble before it loads. Adding optional `w`, `h` (and `dur`) keys to the tag is backward compatible: the web parser only reads the named keys (`chatMessages.js:36-58`). That needs the web team's agreement (Q5).

Parsing (`chatMessages.js:31-102`), in priority order:
1. `[ATTACHMENT:{...}]` anywhere in the text, regex `\[ATTACHMENT:(\{.*?\})\]` (non-greedy up to the first `}]`; a file name that itself contains `}]` breaks it; `.` does not cross newlines). Text outside the tag is a caption (`text`); the web composer never writes one.
2. A message that is only `/uploads/<name>` or `https://host/uploads/<name>`: kind from the extension (png jpg jpeg gif webp svg image; mp4 webm mov mkv video; mp3 wav ogg m4a aac audio; else file). This is legacy (early web, GIF/sticker picks sent as bare links); the server's link-preview code skips such bare media links (`chat/chat_link_preview.erl` `is_bare_media_url`).
3. Legacy `📎 Document: x.pdf` style text with no URL (no file to open).
4. GIF/sticker picks: `{kind:"image", fileName:"<title>.gif", imageUrl:<provider https URL>}` is wrapped in the same tag with `url` = the provider's `https://` URL (`Composer.jsx:1056-1062`); a sticker is a short inline `data:image/svg+xml...` URL put in `url` as is (`Composer.jsx:1066`). Mobile can skip GIF/stickers for now.

Where the raw tag shows up and must be parsed or labelled by the app: message bubble, conversation list preview (`/conversations` `text` is the raw text, `live-shapes.md:12`), reply quote, notification/feed preview. The web turns the tag into labels `📷 Photo`, `🎥 Video`, `🎙️ Voice note`, `📎 <name>` (`chatMessages.js:105-111`, `connectumSocket.js:48-53`).

Reply, edit, delete, react, forward act on the message like any text. Editing a tag message is possible at the protocol level (it is text); nothing in the web stops it. This app already blocks edits in encrypted threads.

## 4. Who may download a chat attachment

**Anyone who has the URL, with no check.** There is no membership test, no recipient test, no organisation test and no token on `GET /uploads/<name>` (`chat_web_upload.erl:362-379`; `ai-and-misc.md` already flagged this as UNCLEAR, the code is unambiguous: it is public by design, "security relies on random names"). Consequences:
- A user removed from a group, or any forwarded/leaked URL, can still fetch the file for ever. There is **no expiry** and **no deletion**: neither message delete, conversation purge (`chat_store:purge_upto`) nor any TTL removes the file (grep: no `delete`/cleanup path for `uploads/`).
- The only per-user control is the uploader's quota (`sd_allowance`, "Chat files").
- The URL is stored in the message text, so whoever can read the message (DM peers, group members via `/history`: members may read the whole history, `chat_web_send.erl:166-175`) can read the URL. The server cannot distinguish "recipient" from "everyone".
- The only real confidentiality is end-to-end encryption (section 5): then the blob is useless without the key inside the encrypted message.

Contrast: `/api/sd/files/<id>` (forms) *does* check the user (`forms/sd_files.erl:132-144`).

For the app this means: no auth header is needed to display, which keeps image widgets simple; but the URL must never be logged (this app already has `lib/data/redact.dart`; add `/uploads/` URLs to it).

## 5. Encryption of attachments

The web **does encrypt attachments in end-to-end threads** (DM and group, when `canEncrypt` is true), it does not send them in the clear. Flow (`Composer.jsx:626-637`, `attachFile.js:24-41`, `chat-app/features/connectumChat/e2e/e2eMedia.js:1-43`):

1. Bytes are encrypted on the device: AES-256-GCM, random 32-byte key, random 12-byte IV, AAD = `e2e1-file`, output `ciphertext||tag` (+16 bytes). (`mobile-handoff/e2e.md` section 6; this app already has `E2eCrypto.encryptFile/decryptFile`, `lib/data/e2e/e2e_crypto.dart:487-517`.)
2. Uploaded with `POST /upload`, multipart part named `<name>.e2e`, content type `application/x-connectum-e2e` (`e2eMedia.js:8-18`). The server stores it as `<48hex>.e2e` without inspecting it (`chat_web_upload.erl:293-294`, `328`). Same auth, same 20/min IP limit, same media quota.
3. The tag `[ATTACHMENT:{kind,name,size,url:"/uploads/<48hex>.e2e",type,e2e:{key,iv}}]` is put **inside the end-to-end envelope** as the message text (`{"v":1,"t":"[ATTACHMENT:...]"}`, `e2e.md`), so `name`, `type`, `kind` and the key are never visible to the server. The server sees: that an upload happened (uploader, time, size), and the opaque `.e2e` URL in nobody's cleartext.
4. The receiver decrypts the envelope, parses the tag, downloads `GET /uploads/<x>.e2e`, decrypts with `{key,iv}`, shows from a local object URL (`e2eMedia.js:49-60`, `MessageList.jsx:331-346`). While loading the bubble reads "🔒 Decrypting attachment…", on failure "🔒 This attachment can't be decrypted on this device."
5. Envelope cap is 120 000 characters (`sd_e2e.erl:30`, `438`), which holds the tag easily; the file itself is not in the envelope. Small stickers/data URLs (<= 50 000 chars) travel inline in the envelope (`e2eMedia.js:6`, `32-34`). A GIF picked from a provider is downloaded, encrypted and uploaded so members do not contact the provider (`e2eMedia.js:26-43`).
6. Size: an encrypted blob may be up to 25.5 MB regardless of kind (so an encrypted image is not held to 8 MB; the web does not check, only the 25.5 MB cap applies). Because the type is hidden, the server cannot apply the 8 MB image limit or any magic-byte check.

Details that matter for the app:
- **No downgrade.** If the thread is encrypted and the encrypted upload fails, the web's catch block reads the file as a data URL and calls `onAttachFile` without `remoteUrl`; `attachFile` then re-encrypts through `protectPicked` and either inlines it (data URL <= 50 000 chars) or sends an empty `url` (`Composer.jsx:654-669`, `attachFile.js:36-39`). It never sends a plain `/uploads/` file into an encrypted thread. Mobile should simply fail the send with retry.
- In `required` mode the server refuses a plain `[ATTACHMENT]` text (`e2e_required`, `sd_e2e.erl:424`); in `optional` mode a plain attachment is accepted anywhere, so the **client** is the only thing keeping files encrypted in an encrypted thread. This app's `EncryptionPolicy.decide` already is that rule for text; the attachment send must use the same verdict.
- Not covered: global room (`e2e_unsupported`), hosts, forms, AI.
- Voice-note transcription is disabled for encrypted notes (`MessageList.jsx:360`).
- This app's current CLAUDE.md rule: "`#`, `@`, edits and attachments stay blocked in encrypted threads" and "Encrypted groups stay read-only". Lifting it is stage 4 below.

## 6. Limits, storage, expiry

| Topic | Fact | Code |
|---|---|---|
| Size | image/audio 8 MB, docs 20 MB, video 25 MB, e2e blob 25.5 MB, body cap 26 MB; **real ceiling ~9-10 MB behind the checked-in nginx configs** | section 2.1 |
| Client-side checks (web) | attachments 25 MB (`connectumApi.js:168-176`), avatar 8 MB and image types; no per-type check, no count limit | |
| Count / rate | 20 uploads per 60 s per IP; no per-conversation limit; WebSocket commands 30 per 10 s per connection apply to the message send | `chat.hrl:13-14,27-28` |
| Where stored | **Either** the server's disk (`CONNECTUM_UPLOADS_DIR`, default `<backend>/uploads`) **or** an S3-compatible bucket (Oracle `axpertfiles`, `ap-hyderabad-1`, in use as of 1 Nov 2026 via a Customer Secret Key profile `oci-s3`), decided by a server config file, per organisation. Chat uploads go to key `<prefix>uploads/<name>`; form files to `<prefix><enterprise>/files/<id>`. The app never needs to know which: the URL is the same | `chat_web_upload.erl:270-280`, `integrations/sd_storage.erl:336-361`, `docs/FILE_STORAGE.md` |
| Config failure | a configured but unusable bucket makes the upload fail (`502`), never silently falling back to disk | `docs/FILE_STORAGE.md` |
| Expiry | **none** for `/uploads/<name>`. No cleanup job. (The 60 s expiry belongs only to `/api/sd/files/<id>/link` presigned URLs.) | |
| Orphans | an upload whose message is never sent stays forever; mobile should upload only at send time (or accept orphans) | |
| Metadata the server keeps | none besides the file and the quota counter: no DB row ties a file to a message, user or conversation | |

## 7. Web UX (what to match)

| Part | Web behaviour | Code |
|---|---|---|
| Picker | One paperclip button in the composer opens the browser file dialog, any type (`accept="*/*"`), **one file at a time**. No camera/gallery split on web | `Composer.jsx:914-931` |
| After choosing | A toast `Sharing "<name>"...` appears, the upload runs, a toast `Sent "<name>"` follows. **No preview before sending, no caption, no progress bar, no cancel.** The message is added to the thread optimistically as a sent bubble (local blob URL) at the same moment | `Composer.jsx:608-669`, `attachFile.js:13-22` |
| Failure | on any upload error (including 413/415/429/401) the web silently falls back to reading the file as a data URL and "sends" a tag whose `url` is empty (data URLs exceed 1800 chars): the recipient gets a card with nothing to open. **Do not copy this.** Voice notes instead show "Couldn't send the voice note" | `Composer.jsx:651-669`, `attachFile.js:28-30`, `Composer.jsx:743-748` |
| Voice note | Mic button records (MediaRecorder: webm/ogg/mp4), on stop uploads with `kind:"audio"`, name `Voice note (m:ss)` | `Composer.jsx:695-760` |
| Image bubble | `<img>` of the original, scaled by CSS, a download overlay button; broken image becomes a "Image preview unavailable" card remembered per URL. **No lightbox / full-screen viewer, no pinch zoom, no swipe between images** (clicking does nothing; only avatars are `viewable`) | `MessageList.jsx:41-85`, `700-717` |
| Video bubble | native `<video controls>` inline + a download button | `MessageList.jsx:719-740` |
| Voice bubble | custom play/pause with progress bar, optional "Show text" transcript (not for encrypted) | `MessageList.jsx:240-330`, `350-` |
| File card | icon badge by extension + name + size string + "Tap to download"; whole card clickable | `MessageList.jsx:659-704`, `getFileBadgeConfig` |
| Download/open | `fetch(url)` → blob → `<a download>` click (saves to the browser's downloads); on failure opens the URL in a new tab. Documents are never rendered in-page (server sends `Content-Disposition: attachment`). **No in-app document preview, no "open with"** | `MessageList.jsx:87-125` |
| Encrypted | "🔒 Decrypting attachment…" then the media from a local blob | `MessageList.jsx:331-346` |
| Previews | conversation row shows `📷 Photo`, `🎥 Video`, `🎙️ Voice note`, `📎 name` | `chatMessages.js:105-111`, `attachFile.js:68-76` |

The web is minimal. The approved mobile design in `reference/prototype` should drive the UI; the web only fixes the behaviour.

## 8. This app today and what it needs

### 8.1 Current state (`lib/`)

- **No attachment code at all.** The composer has a placeholder `+ Attach` button wired to `c.tapPlaceholder` (`lib/features/conversation/widgets/conversation_composer.dart:98-102`); no uploader, no `[ATTACHMENT]` parser, no media widget, no download cache, no picker package.
- Existing pieces to reuse: `Message` model with `text` only (`lib/data/models/message.dart`), the outbox + `cid` + ack path in `message_repository.dart`, `ApiClient` (Dio, `lib/data/api/api_client.dart`), `E2eCrypto.encryptFile/decryptFile` with the exact web parameters (AES-256-GCM, AAD `e2e1-file`; `lib/data/e2e/e2e_crypto.dart:215,487-517`), `EncryptionPolicy` (the single plain/encrypt/blocked rule), `AppStateImage`, `redact.dart`.
- `pubspec.yaml` already has: `dio` (multipart, `onSendProgress`, `ResponseType.bytes`/download with progress), `path_provider` (cache directory), `path`, `webcrypto`. Missing: picker, file opener, mime detection, image cache/compress.
- Debug seed data (`lib/core/debug/seed_*.dart`) contains the word "attach"/"file" in sample text only; not an implementation.

### 8.2 Minimal package proposal (nothing installed; each one-line reason as CLAUDE.md asks)

| Package | Why | Stage |
|---|---|---|
| `image_picker` | gallery and camera photo/video in one API, normally converts iOS HEIC to JPEG on pick and uses the Android photo picker (no storage permission); both to be verified on install; needs `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` on iOS and the `CAMERA` permission only if camera is offered | 1 |
| `file_picker` | documents (pdf, docx, xlsx, pptx, txt) from the system picker; no permission on modern Android (SAF) and iOS (document picker) | 2 |
| `open_filex` (or `open_file`) | hand a downloaded document to the OS viewer; `share_plus` is the alternative if "Save/Share" is wanted instead | 2 |
| `mime` | derive mime from extension + magic bytes to set the part `Content-Type` correctly and filter unsupported types before upload | 1 |
| `flutter_image_compress` (optional) | downscale and re-encode large camera photos under 8 MB; without it a 12 MP JPEG is 3-6 MB and usually passes | 1 (only if needed) |
| `cached_network_image` or own cache | image caching keyed by the immutable URL; own file cache with `path_provider` + Dio is enough and adds no package | 3 |
| `record` (voice) / `video_player` (video) | stage 5 only | 5 |

Everything else (upload, progress, retry) is Dio. Camera: `image_picker` with `ImageSource.camera`; the `CAMERA` permission and `uses-feature camera required=false` are already planned for the QR scanner (`mobile_scanner` is installed), so no new manifest risk. CLAUDE.md: the release manifest lists only INTERNET and ACCESS_NETWORK_STATE today; `image_picker` on Android needs none for gallery.

## 9. Staged plan with sizes

Sizes are working days for one developer including the empty/error/offline states, `dart analyze`, and device check; no tests unless asked (CLAUDE.md).

| Stage | Scope | Size | Depends on |
|---|---|---|---|
| **1. Images in plain chats** | `AttachmentTag` model + parser/builder (all four forms in section 3); `UploadService` in `lib/data/` (Dio multipart, progress, 401/413/415/429 mapping); Attach sheet (Photo library, Camera); preview-before-send screen with remove; outbox entry type `attachment` (upload step, then the text send with the same `cid`; an upload failure must not lose the picked file: copy to app cache first); bubble with placeholder size and tap-to-retry; conversation-list/reply/notification labels; full-screen image viewer (pinch zoom, which the web lacks); offline: attachments need a connection (CLAUDE.md), the Attach button shows the offline state, no queueing | **4-5 d** | answers to Q1, Q2, Q5 |
| **2. Documents** | `file_picker`, type/size pre-check against section 2.1, file card (icon by extension, name, size), per-type limits, clear messages for rejected types | **1.5-2 d** | stage 1 |
| **3. Download, open, cache** | download with progress into an app cache dir keyed by the URL hash (URL is immutable), open with OS viewer / share, cache eviction (size cap), "Clear media cache" in Profile, `redact.dart` for `/uploads/` URLs; image thumbnails by decoding with `cacheWidth` | **2 d** | stage 2 |
| **4. Encrypted threads** | encrypt (`encryptFile`) then upload as `application/x-connectum-e2e`; tag with `e2e` inside the envelope (`EncryptionPolicy.decide` unchanged); decrypt on view with "Decrypting…"/"can't decrypt" states; cache the **decrypted** copy only in app-private storage (decide cache policy: Q9); lift the app's attachments block; groups stay read-only until encrypted group send exists (separate work) | **3-4 d** | stages 1, 3; e2e group send for groups |
| **5. Video and voice** | video pick/record, size pre-check, `video_player` bubble with Range seek; voice note recorder (`record`, m4a/aac in `audio/mp4`; web uses webm which iOS cannot record), play/pause bubble with duration, waveform optional | **4-5 d** | stage 3 |

Order is by risk: stage 1 proves upload + tag + bubble; stages 2-3 are mostly UI; stage 4 is the security-sensitive one and should follow the e2e group-send work; stage 5 depends on Q8.

## 10. Questions for the backend team

1. **nginx body limit.** `client_max_body_size` is 9 MB (`setup-tls.sh:97`) / 10 MB (`connectum.conf.reference:31`) but Erlang accepts docs up to 20 MB and video up to 25 MB (and e2e blobs 25.5 MB). What does production nginx actually allow on `/upload`, and will it be raised to 26 MB to match? What does the client see on an nginx `413` (HTML, no JSON)?
2. **Public downloads.** `GET /uploads/<name>` has no auth, no membership check and files never expire or get deleted (also not on message delete, conversation purge, leaving a group). Is that the intended permanent design for mobile? Will chat files get an authenticated or signed download (like `/api/sd/files/<id>/link`) or a retention/cleanup job?
3. **Upload rate limit.** 20 uploads/60 s is per IP behind `X-Real-IP`. Offices and mobile carrier NAT share IPs, so legitimate users can hit `429`. Is a per-user limit planned? What retry hint should the app use (there is no `Retry-After`)?
4. **Allowed types.** Please confirm the list is final: HEIC/HEIF, `audio/mpeg`, `audio/aac`, `.csv`, `.zip`, `.doc/.xls/.ppt`, `video/3gpp` are rejected (`415`). The web UI says "any file" and its comments mention ZIP and CSV. Should mobile convert (HEIC to JPEG is trivial) or will the list grow?
5. **Tag contract.** The tag is a client convention (no server parsing, no schema). Can we freeze it as: `kind`, `name`, `size` (string today; may mobile send **bytes as a number**?), `url`, `type`, optional `e2e`, plus **new optional `w`, `h`** (pixels) and **`dur`** (seconds) so bubbles do not jump when the image loads and voice notes show a length? Does the web team accept the extra keys (their parser ignores unknown keys)? Who owns this contract?
6. **Captions.** The parser supports text outside the tag (`chatMessages.js:34`) but the web composer never sends one. May mobile send `caption text [ATTACHMENT:{...}]` (and in what order)? Does the web render it as a caption for images, videos and files?
7. **Tag parsing edge.** Regex `\[ATTACHMENT:(\{.*?\})\]` breaks on a file name containing `}]`. Should the sender strip or escape it, or will the web parser be fixed?
8. **Voice format.** The web records webm/ogg/mp4 (`audio/webm`; a phone recorder normally produces AAC in an m4a container, `audio/mp4`, which the server accepts). Does the web player (an `<audio>` element) play `audio/mp4` voice notes in the browsers you support? Should mobile send `audio/mp4` (accepted) with `kind:"audio"` and a name like `Voice note (0:07)`, as the web does?
9. **Cache of decrypted media.** For encrypted attachments the web keeps decrypted blobs only in memory (`e2eMedia.js` cache). May mobile store the decrypted file on disk in app-private storage (the app already stores decrypted message text), or must it re-download and decrypt each time?
10. **Encrypted blob size.** The server cannot see the type of an `.e2e` blob, so an encrypted 20 MB image passes the 8 MB image limit. Is that accepted? Should mobile still enforce 8 MB images client-side in encrypted chats?
11. **Quota message.** What does the "Chat files" allowance (`sd_allowance`, `413`) default to, and is its text safe to show as is? Is there an API to read the remaining quota (`allowance.mine` exists in `sd_cmds.erl:180`) that the Attach sheet could use?
12. **Global room.** The web sends attachments to the global room as plain broadcast (no `cid`). Does mobile need global-room attachments at all (the app has no global room today)? If yes, the offline duplicate risk in CLAUDE.md applies.
13. **Mixed content.** `url` may be an absolute `https://` URL (GIF providers) as well as `/uploads/...`. Is it safe/expected for mobile to refuse to load any host other than the server origin and known GIF providers?
14. **Cloud store path.** Chat files in the Oracle bucket are served *through* the Erlang process (whole file in memory). Is a presigned redirect for `/uploads/` planned (the `/link` machinery exists), and would `GET /uploads/<name>` then answer `302`? The app should follow redirects either way; please confirm no `Authorization` header must be withheld on the redirect.
15. **Environments.** The `/upload` URL on the dev backend the app uses: same host as the WebSocket? (`websocket-protocol.md` assumes `https://<HOST>/upload`.)

## 11. Corrections to earlier handoff notes

- `messages-and-receipts.md:26` says `/upload` is "max 8 MB"; `ai-and-misc.md` 2.1 has it right: tiered 8 / 20 / 25 MB (`chat_web_upload.erl:8-10`). The real ceiling is lower because of nginx (Q1).
- `ai-and-misc.md` 2.1 says "documents get `Content-Disposition: attachment`" (true, no file name in it) and `Cache-Control: no-cache` (true, no validators either). Its UNCLEAR about whether downloads gain auth is answered by the code: they do not, and nothing in the repo plans it (Q2).
- `ai-and-misc.md` "Client-side checks (web) attachment max 25 MB" applies to `uploadAttachment`; the server limit per type is smaller for images and audio.
