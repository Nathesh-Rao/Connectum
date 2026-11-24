# Files in records (Smart View): what the app receives and what it costs

Read-only investigation, mobile app plus the BE source on `origin/dev` of `~/Development/Axi-apps/connectum` (read only). Date 2026-11-24.

## Summary

- **File bytes are NOT inline in any record API.** A file field's value is a list of 24-hex file ids. With `withDetails:true`, `submissions.list` adds `files[field] = [{id,name,mime,size}]`. The tile name, size and type come from that map, never from the bytes.
- **Metadata-only tiles and fetch-on-tap already exist** in the app (`SvFileRepository`, `GET /api/sd/files/<id>`). The new design is mostly a BE contract improvement (etag, thumbnail, mime, signed URL) plus small app changes.
- I could **not** prove the result for the specific record "file upload test #1237": no log file exists in the repo (`docs/logs/` is missing) and there is no live access. Section 6 explains how to capture the proof.
- The only place bytes can legitimately sit in a value is an **API-source** Smart View on the web (`data:image/png;base64,...`, at most 2,000,000 chars). The app does not treat these as files (`SvFile.isFileId` accepts only 24-hex ids), so they would show as text and be large. A form `file` field cannot hold them: the BE accepts only ids.

## (a) How a file field looks today, per API

Sample, from capture `010-submissions-list-every-field-type…json` (`reference/smart-view/examples/`), data replaced where long:

```json
{ "id": 7, "tstruct": "everyfield", "by": "ana", "byName": "Ana", "ts": 1763300000, "canEdit": true,
  "values": { "doc": ["4961748d27125c549678e385"] },
  "labels": {},
  "files":  { "doc": [ { "id": "4961748d27125c549678e385", "name": "Everything.pdf", "mime": "application/pdf", "size": 14 } ] } }
```

A file inside a grid row is keyed `"<section>.<row>.<field>"` in `files` (BE `sd_config.erl` `with_file_names`, `row_files`).

| API | Carries file info? | Shape | Source |
|---|---|---|---|
| `submissions.list` with `withDetails:true` (Smart View, `fetch:true`) | ids in `values` plus metadata in `files` | `files[field] = [{id,name,mime,size}]` | BE `sd_cmds_forms.erl:131-134`, `sd_config.erl:1061-1077`; app `smart_view_repository.dart:371` |
| `submissions.list` without `withDetails` (my submissions, workspace, cache) | ids only in `values`, no `files` | `values.doc = ["<24hex>"]` | capture `009-`; `submission_repository.dart:1250` |
| `records.mine` (`with`, `involved`) | ids only in `values`, no `files`, no `labels` | same as above | capture `027-`; `sv_row.dart:5-8` |
| Single record / `submission.get` | ids in `values` | same | `records-and-tickets.md` |
| `submission.history`, `record.status`, `record.send` | file metadata in `files: {<id>:{id,name,size,mime}}` (history), ids in events | `RecordFile` | `RECORD_ACTIONS.md:47`; `record_state.dart:46-68, 370` |
| `form_message` card | per file field: `value` = names joined, `files:[{id,name,kind}]` | metadata only | BE `sd_formmsg.erl:245-250` |
| `submissions_changed` and similar events | no file data; the app re-reads page 1 (50 rows) | n/a | `smart_view_repository.dart:735-757` |
| Feed, ticket detail, workspace | not read for files; ticket detail uses `RecordFile` from history | n/a | `record_state.dart` |

## (b) Are bytes inline? No, for every API above

Proof from the code path:

1. **BE**: `with_file_names` builds each entry from `sd_files:get(Id)` (a metadata map) and emits only `id, name, mime, size`. File bytes are read only by `sd_files:read` in `download_file` (`sd_http.erl`, `GET /api/sd/files/<id>`). A `file` field accepts only ids (`FORM_FIELD_TYPES.md:23`).
2. **App parsing**: `SvRow.tryParse` copies `values`, `labels`, `files` as maps (`sv_row.dart:122`). `SvFile.listOf` keeps only values that match `^[a-f0-9]{24}$` (`sv_file.dart:39, 111-130`) and takes name, mime and size from the `files` map (`sv_file.dart:96-108`). A base64 string would be dropped as "not a file id".
3. **Where size/type/name on the tile come from**: `SvFile.name/mime/size` from `files[field]`, then `kindOf(name, mime)` (`sv_file.dart` `kindOf`). Nothing is computed from bytes before a tap. A missing detail shows the name `File` and size empty.
4. **Sizes**: the capture `010-` reply is 2,194 chars for a record with one PDF. Metadata per file is about 100 bytes.

If the real log shows huge `"<N chars>"` values in `values.<fileField>`, the field is not a `file` type (for example a text field filled with base64 by an API or import) and that is a data problem, not a file-field problem.

## (c) Existing upload and download actions (all REST, none on the WebSocket)

| Action | Params | Answer | Notes / source |
|---|---|---|---|
| Upload `POST /api/sd/files?name=<enc>` | raw bytes as body, `Content-Type` = file mime, `Content-Length`, `Authorization: Bearer` | `{ok,data:{file:{id,name,mime,size,by,ts}}}` | 10 MB default (`CONNECTUM_MAX_FILE_MB`), 60 uploads/hour/person, org quota. BE `sd_http.erl:446-475`; app `form_file_repository.dart:59-72` |
| List `GET /api/sd/files` | Bearer | `{data:{files:[...]}}` (own uploads) | `ai-and-misc.md:122` |
| Download `GET /api/sd/files/<id>` | Bearer | raw bytes, always `application/octet-stream`, `Content-Disposition: attachment; filename*=UTF-8''<enc>`, `X-File-Name`, `Content-Length`, `Cache-Control: private, no-store`, `nosniff` | BE `send_attachment`; app `sv_file_repository.dart:178-197`. No Range, no ETag, no thumbnail. |
| Link `GET /api/sd/files/<id>/link` | Bearer | `{url|null, name, size}`; `url` is a SigV4 presigned GET, about 60 s (5..900), `null` when the file is on the server disk | BE `sd_http.erl:492-497`. **The app does not use it** (`records-and-tickets.md:228` "not built"). |
| Permission | uploader, an admin, a download option that targets the file, or a visible submission that contains it | | `forms/sd_files.erl:132-144` |
| Chat `POST /upload`, `GET /uploads/<name>` | different mechanism (chat attachments: `[ATTACHMENT:{...}]` tag in message text, public URL) | | `attachments.md`; **not** used for records |
| `record.status` / `record.send` | `files:[fileId]`, at most 10, own uploads only | `files` | `RECORD_ACTIONS.md:42-43` |
| WebSocket file actions | none exist | | grep of `SD_ACTIONS_REFERENCE.md` and `mobile-handoff/` finds none |

## (d) App-side cost and risks

| Area | Today | Risk / cost |
|---|---|---|
| Smart View read | `submissions.list` 500 rows/page, up to 20 pages, then `records.mine` 3 pages of 200 (`smart_view_repository.dart:358-410`, `smart_view_commands.dart:33-37`). `withDetails` also makes the **server** read file metadata for every record on every page ("opt in because it reads the files of every record on the page", `sd_cmds_forms.erl:132`). | Server-side cost grows with rows times files. App-side metadata is small. |
| Parsing | `jsonDecode` of every WebSocket frame on the UI isolate (`socket_service.dart:229`), then `SvRow.tryParse` and `_cut` (copies `values`, `labels`, `files` maps per row, `smart_view_repository.dart:477-506`), then re-sort and `assignAll` of **all rows after every page** (`_show`, line 509). | With 500-row pages this is CPU on the UI thread (jank risk). Not caused by bytes, but it would be catastrophic if bytes were inline: a 5 MB base64 string is decoded, copied into the row map and kept alive. |
| `SvFile.listOf` per cell | Runs on each cell build (`sv_columns.dart:255`), max 20 files per cell. | Cheap, but re-parses `files` maps every build. Could be cached per row. |
| Persistence | Smart View rows are **memory only**, never SQLite (CLAUDE.md, `SvRow` doc). `submissions.list` without `withDetails` (my submissions) is written to `form_submissions.values_json` (`submission_repository.dart:1019-1050`): ids only. `sv_overview_cache` holds counts only. Outbox holds form values with file ids, not bytes. | Low. If a non-file field held base64 it would be stored raw in `values_json`. |
| Logging | `LogRedaction` turns any string over 200 chars into `<N chars>` (`log_redaction.dart:253`); bodies are capped to 2 KB. | Good for the evidence step, and it keeps logs small. |
| File fetch | `dio.download` straight to a `.part` file, then rename (`sv_file_repository.dart:133-197`). Stream to disk, no bytes in memory. | Good. |
| Preview memory | Sheet, docx, pptx, zip: `file.readAsBytes()` then `compute` for files over 256 KB, parse cap 15 MB (`sv_file_preview_controller.dart:82-83, 180-206`). Save as: `readAsBytes` of the whole file into memory (`sv_file_repository.dart:257`). Preview cap 25 MB. | Up to about 15-25 MB held in memory per preview plus a copy into the isolate. |
| Cache | Temp dir `sv_files`, key `<id>_<size>` (no etag), 100 MB LRU, cleared on sign out or org change (`sv_file_repository.dart:86, 103-130, 283-290, 300-321`). The server sends `no-store`. | The OS may purge temp at any time. A file edited in place with the same size would be stale. No etag means no revalidation. |
| Cell UI | One chip plus a "+N" badge (`SvFileTableCell`, `sv_file_chips.dart:367-400`). Tap opens the viewer with all files of the cell. | Fine; no bytes needed to draw it. |

## 6. Evidence from the log

No log file is available in the repo (`docs/logs/` does not exist; only `docs/logging.md`, which documents the format). To capture it:

1. Profile > Logs: turn Logs on.
2. Open the Smart View of the structure that has "file upload test #1237" and wait for it to finish loading.
3. Export the log (Logs > Share) and send it.
4. Look for the line `API #n submissions.list <- OK`. Check, for the rows with files:
   - `values.<fileField>` should be `["<24hex>", ...]`, short strings.
   - `files.<fileField>` should be `[{id,name,mime,size}]`.
   - Any `<N chars>` with N in the thousands or millions inside `values` means inline content (and then the field is not a `file` type).
   - Also note the `(+N chars)` suffix at the end of the line (bodies are capped at 2,048 chars, `LogRedaction.maxBody`), `total`, `hasMore` and the number of rows. Compare reply size across `offset` pages.

## (e) Changes for the new design (metadata-only tiles, fetch on tap)

The app already has: metadata-only tiles, tap to fetch with progress, cancel, error mapping (401, 403, 404, 413, network), temp cache with LRU, preview by type (PDF `pdfrx`, `video_player` for video and audio, image via `InteractiveViewer` with a magic-bytes check, text, csv/tsv, docx/pptx/zip via `archive`), save via `file_picker`, share via `share_plus`, open via `open_filex`. Offline: a cache hit opens; otherwise the file shows "No connection. Check your internet and try again." with Retry.

What is still needed once the BE adds the new fields and action:

| Need | Change | Files |
|---|---|---|
| Richer file entry (`ext`, `uploadedAt`, `etag`, reliable `mime`) | extend `SvFile` and its parsing; use mime from the server instead of sniffing and the extension | `lib/data/smart_view/sv_file.dart`, `lib/data/models/record_state.dart` (`RecordFile`) |
| New fetch action (signed URL or chunked) | replace or extend `_download`; if signed URL, call it first, then GET the URL **without** Authorization | `lib/data/repositories/sv_file_repository.dart` |
| Cache keyed by id + etag | change `cacheKey` to `<id>_<etag>`; drop a copy when the etag differs; consider moving to the app cache dir | `sv_file.dart:89`, `sv_file_repository.dart` |
| Thumbnails for images | new small-image fetch used by the chip and the viewer placeholder; memory-bounded cache | `sv_file_chips.dart`, `sv_image_viewer.dart` |
| Progress, cancel, error, offline | exist; add a "kept on this phone" hint and an offline-with-cache state | `sv_file_preview_controller.dart`, `sv_file_preview_dialog.dart` |
| Size limits | align `maxPreviewBytes` (25 MB), `maxParseBytes` (15 MB), `cacheLimit` (100 MB) with the BE; stream `saveAs` instead of `readAsBytes` | `sv_file_repository.dart:86-90, 257`, `sv_file_preview_controller.dart:82` |
| Opt-in flag | send the new flag with `submissions.list` and `records.mine` and fall back if absent | `smart_view_commands.dart`, `smart_view_repository.dart:371, 745`, `submission_repository.dart:1250` |
| Metadata parity for other screens | `records.mine` and cards carry ids only; use the same metadata so the tile is the same everywhere | `sv_row.dart`, `smart_view_repository.dart` (`_readMine`) |
| Performance (independent of files) | decode large frames off the UI isolate, add rows once per page batch, cache `SvFile.listOf` per row | `socket_service.dart:229`, `smart_view_repository.dart:509` |
| Tests | file parsing and cache tests | `test/` (not run per working rules) |

## 5. Uploads, as they work today

- Picked via `AttachmentRepository` (`image_picker`, `file_picker`), checked against 10 MB (`RecordLimits.maxFileBytes`, `record_commands.dart:66`; the picker applies about 9.5 MB).
- Uploaded **as soon as chosen**, streamed as raw bytes (`File.openRead()`, no base64, no chunking), with `onSendProgress` and a cancel token (`form_file_repository.dart:59-82`).
- The form value is the list of ids of finished uploads (`form_controller.dart:922-927`), sent in `tstruct.submit` / `submissions.update` values.
- Errors: 401/403 session ended, 413 too large, other 4xx the server's message, else "Couldn't upload that file. Try again." with retry per file; the temp copy is deleted after a good upload.
- Limits: 10 per field, 60 uploads/hour, org quota.

## 7. Web comparison

The web reads `files` from `submissions.list` with `withDetails` and shows chips (`SvFiles.jsx`). On click a Connectum file is fetched **with the person's sign-in** through `fetchFileBlob` in `chat-app/services/connectumFiles.js`, kept in memory, and its type comes from the first bytes (`sniffKind`: PNG, JPEG, GIF, WebP, PDF) because the server sends `application/octet-stream`. The web asks `GET /api/sd/files/<id>/link` first and falls back to the plain download (`attachments.md:82`). So the server already has the metadata, a download route and a presigned link route; it lacks mime, etag, thumbnail and Range.

## (f) Questions for the BE team

1. For the record "file upload test #1237", please send the raw `submissions.list` reply (with `withDetails:true`). Is the field type `file`? Does any value hold anything other than 24-hex ids?
2. Can any API return file content inline (base64, `data:` URL, bytes) for a `file` field or any other field type? Which ones? (Web API sources allow `data:image/...;base64` up to 2,000,000 chars.)
3. Is `GET /api/sd/files/<id>` the intended mobile download route? Please confirm Bearer auth, the max size, and whether a `Range` header is supported (we assume no).
4. Can `GET /api/sd/files/<id>/link` be relied on for mobile? How long does the link last for a 25 MB file? What happens when it expires mid-download? When is `url` null (disk-stored files)?
5. Can the file entry carry a real `mime` and `ext`, `uploadedAt` and an `etag` (or content hash), so the app can cache by id + etag? Today the download is always `application/octet-stream`.
6. Is there, or will there be, a thumbnail or resized image option (for example `?w=256`)? Which formats (webp or jpeg)?
7. Does an edited or replaced file get a new id, or the same id with new content? (This decides the cache key.)
8. Does `withDetails:true` limit the number of files per record or per field? What do `size` and `mime` hold when the stored metadata is missing (the BE falls back to `0` and `<<>>`)?
9. Could `records.mine` also return `files` metadata (with an opt-in flag)? Today it returns ids only.
10. What are the rate limits for downloads (not only the 60 uploads/hour)? Is there a per-user bandwidth quota?
11. Is the 10 MB upload limit final? Is chunked or resumable upload planned?
12. Which opt-in flag name and version will old clients see? Will the old shape stay unchanged when the flag is absent?
13. Is a file deleted when its record is deleted, and what does the download answer then (`404` or `403`)? Is the answer the same for a file the person may no longer see?
14. Is the `files` map ordered like the ids in `values`? Can the same id appear twice?

## (g) Contract sketch (proposal only, not agreed with the BE)

```jsonc
// submissions.list { tstruct, limit, offset, fetch:true, withDetails:true, fileMeta:2 }   // opt-in flag; absent = today's shape
"files": { "doc": [ {
  "id": "4961748d27125c549678e385",
  "name": "Everything.pdf",
  "size": 120394,
  "mime": "application/pdf",
  "ext": "pdf",
  "uploadedAt": 1763300000,
  "etag": "9f2c1a…",          // content hash; changes when the content changes
  "thumb": true               // an image thumbnail exists
} ] }

// New action (REST, same auth), either:
// A) signed URL:    GET /api/sd/files/<id>/link?etag=<etag>  ->  { url, expiresIn, name, size, mime, etag }
//                   (the app GETs url with no Authorization, sends If-None-Match, supports Range)
// B) streamed bytes: GET /api/sd/files/<id>  with  Range  and  ETag / If-None-Match,
//                   and a correct Content-Type (no octet-stream)
// Thumbnail:        GET /api/sd/files/<id>/thumb?w=256   ->  image/webp
```

Rules proposed: metadata only in record APIs when the flag is present; the file's content is never inside a record; old clients without the flag get today's shape; `404` for a removed file, `403` for no access, `413` for a file over the limit.
