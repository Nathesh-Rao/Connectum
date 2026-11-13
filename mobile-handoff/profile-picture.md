# Profile picture

Audited against `origin/main` of the web repo (`~/Development/Axi-apps/connectum`, read only).

## Contract (all confirmed in code)

| Item | Value | Source |
|---|---|---|
| Upload | `POST {origin}/upload`, `multipart/form-data`, one part `file`; `Authorization: Bearer <token>` (required in a strict org) | `ai-and-misc.md` section 2.1, `chat_web_upload.erl` |
| Then | `/setavatar <url>` on the socket. `url` must start with `/uploads/` or `https://`, no spaces or backslash, max 300 chars. No ack: the reply is the `profile` broadcast, a wrong url gets `{"type":"error"}` | `chat_web.erl:800-813`, `valid_avatar_url` `:217` |
| Remove | `/removeavatar`, answered by the `profile` broadcast with `avatar:null` | `chat_web.erl:811` |
| Formats / size | png, jpeg, gif, webp, max 8 MB, magic bytes checked. No HEIC, BMP, SVG | `chat_web_upload.erl:8-22` |
| Errors | `400` empty/not multipart, `401`, `413` too large, `415` type or content mismatch, `429` 20 uploads / 60 s **per IP** (body `{"error":text}`) | `attachments.md` |
| Server resizes? | **No.** Stored as uploaded, no thumbnail endpoint | `attachments.md` section 2.2 |
| Web crop | square window with a round mask, zoom 1x to 4x (`MAX_ZOOM`), drag; **no rotation**. Output 512 x 512 JPEG q0.92 on white. Client check: types png/jpeg/gif/webp, 8 MB | `AvatarCropper.jsx:6,136-150`, `avatarCrop.js`, `ProfileModal.jsx:262-300` |
| Field | `avatar`: `/uploads/<48 hex>.<ext>` (relative, prefix with the origin) or `https://...`, or `null` | `websocket-protocol.md` |
| Delivery | `GET {origin}/uploads/<name>`, **no auth header**. `Cache-Control: no-cache`, no ETag, so cache by url | `attachments.md` section 2.2 |
| Cache busting | The name is random per upload, so a new picture is a new url. No version or hash exists or is needed | |
| Live event | `{"type":"profile","user":"alice","avatar":"/uploads/x.png"|null,"status":..}` pushed to every online client on change, and one per known person after `welcome` | `chat_room.erl:164`, `websocket-protocol.md` |
| In lists | `avatar` on `/conversations` items, `conv.list {full:true}` **direct rows only**, `assoc.list`, `users.search`, `users.colleagues` rows | `postman-crosscheck.md` |
| Groups | No group avatar field (`group-create.md`) | |
| E2E chats | Pictures are public profile data, unaffected by encryption | |
| Feed / notification payloads | No avatar field known | not verified |

## In the app

- Picker: `ProfilePhotoPicker` (`lib/data/profile_photo/`), `image_picker` (already in pubspec). Camera or library; re-encoded by the plugin (also HEIC to JPEG), then checked (type, 8 MB).
- Crop: `lib/features/profile_photo/` (`/profile/photo-crop`), no package. Pure maths in `crop_math.dart`; drawing and PNG output in `photo_renderer.dart`. Pinch/drag, quarter turns, straighten -45..45, zoom 1x..4x, reset, cancel.
- Output: 512 x 512 on white (as the web). **PNG, not JPEG**: Flutter cannot encode JPEG without a package and the server accepts PNG. A PNG is larger than the web's JPEG (typically 200 KB to 1 MB, far below 8 MB). Re-drawing strips EXIF/GPS (tested: no `eXIf`/`GPS`/text chunk).
- Upload: `ProfilePhotoRepository` (`ProfilePhotoRepositoryImpl`, `FakeProfilePhotoRepository` for DEMO_MODE and tests): multipart with progress, then `/setavatar`. A failure after the upload (socket down) is "offline".
- Own picture shows at once from memory (`memory:<n>`), the real url replaces it after upload, a failure restores the previous one.
- Storage: table `people_avatars` (migration 14, per organisation and person) via `PeopleAvatars`; direct chat rows keep `conversations.avatar`. `profile` events update both.
- Display: `AppAvatar(picture: ...)` over the initials; loading, failure and none show the initials and the colour from the name (unchanged). Files cached by `AttachmentCache`, memory by Flutter's image cache. Only `/uploads/` on this server is fetched.
- Shown in: chat list tiles (direct), conversation header, chat info (direct), group members, mention list, profile card.

## Not done

- Sender avatars beside messages (the thread has none by design).
- Workspace row (the web uses the own picture; ours is "My Work Space"), task people, forward sheet, group picker, connect target: they do not read `PeopleAvatars` yet.
- People lists (`users.colleagues`, `assoc.list`, `users.search`) carry `avatar`; the app does not read it, it relies on `profile` events (one per known person after `welcome`).
- `https://` pictures from another host are not fetched (initials show).

## Open questions for the backend

1. Does `welcome` send a `profile` event for every member of every group I am in, or only DM partners, connections and online people (max 300)? Group members who are none of these will show initials until a list carries their `avatar`.
2. `/setavatar` and `/removeavatar` have no ack, only the broadcast. Is the broadcast also sent to the sender on every device? (`broadcast_profile` says "every online client".)
3. Should the 20 uploads / 60 s limit stay per IP (a shared office network can hit it)?
4. Do feed or push payloads carry the sender's `avatar`?
