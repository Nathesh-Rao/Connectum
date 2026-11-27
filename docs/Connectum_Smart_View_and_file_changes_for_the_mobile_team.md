# Smart View and file changes: complete report for the mobile team

Written 24 Nov 2026. Sources: the web code on `dev` (it now contains `feat/smartview-next4`), the web branch `feat/files-viewing` (pushed, **not merged to dev yet**), and the backend team's docs `FILE_DOWNLOADS.md` and `MOBILE_RECORDS_OVERVIEW.md`. Nothing here is released to PROD. Where something was not checked, it says so.

---

## Part A. Smart View: what changed

### A1. Removed
| Removed | What the mobile app should do |
|---|---|
| The **Overview** pane (a card per structure, the "Needs you" strip) on the web | The web no longer calls it. The server call `records.overview` **stays** on dev **for mobile** (see Part C); use it for the mobile Overview. |
| The **My team** entry in the list of sources (a table of the team's records with columns Team member, Linked as, ...) | Do not build a separate "My team" source. The team is now a **filter of every structure** (A2). |

`#view` now opens on the **first structure** as a table (not the Overview). `#view <name>` is unchanged.

### A2. New: "My team" and "Linked as" in every structure's filter panel
Shown **only when somebody reports to the person** (the list comes from `records.people` -> `team`). Two multi-select lines:

| Line | Choices |
|---|---|
| **My team** | which of the person's direct reports (none chosen = every report) |
| **Linked as** | Tagged to, Assigned to, Assigned by, Sent to, Sent by, Raised by, Raised to, Pending with team, Requests (none chosen = any way) |

A record is kept when **one of those reports is tied to it in one of those ways**. Meaning of each way:
- **Tagged to**: named in a field of people on the record (assigned to, raised to, watcher...).
- **Assigned to**: holds the record now and did not make it.
- **Assigned by / Sent by**: sent it on (the record's assignor). In Connectum assigning is sending, so these two read the same field.
- **Sent to**: it was sent or shared to them (a record they made is not "sent to" them).
- **Raised by / Requests**: made the record (same field).
- **Raised to**: has it now, or is named in it, and did not make it.
- **Pending with team**: has it now and it is still open (a form with a status that is not final).

**How it must be built** (it is **not a column filter**; do not filter rows in the app):
1. Keep the two lines in the same list of conditions as two reserved conditions (so a saved view keeps them, and each shows as a chip):
   `{ col: "__team", op: "in", value: ["ravi","sana"] }` and `{ col: "__linked", op: "in", value: ["tagged","pending"] }`
   (ids: `tagged assignedTo assignedBy sentTo sentBy raisedBy raisedTo pending requests`).
2. When either is set, read the structure from the server with
   `records.query { forms:["<structure>"], team:{ members:[...], linked:[...] }, limit:200, offset:n, withDetails:true }`
   and page with `offset` (page limit **200**). Same reply shape as `submissions.list`: `submissions`, `total`, `hasMore`, `structures`.
3. Every other condition (search, column filters) is applied by the app to those rows as before.
4. With both removed, read the plain list again (`submissions.list`).

Rules the server enforces: a name that is not one of the caller's reports is ignored (if none is a report, nothing matches); `team: {}` is no team filter; wrong shapes are refused with `error.code = "invalid"` (an unknown way, a list that is not a list, more than 20 ways, a non-text name); the records are exactly those the person may read.

Tested live (web against a dev backend): a manager's Task structure, My team = one report + Linked as "Raised by" gave only that report's records; removing the member chip gave all reports' records; a saved view kept both lines and restored them.

### A3. Saved views
Unchanged in shape. The two reserved conditions ride inside `filters`, so no server change was needed for views. An older app that sees `__team` / `__linked` conditions must **ignore** them (they are not columns).

### A4. Other Smart View facts to keep
- Page sizes: first page **100**, then **500**, up to **10,000** rows (`submissions.list`); `records.query` pages are **200**.
- Command limit: **30 per 10 seconds per connection** (`rate_limited`); retry with a growing pause, one read at a time.
- Under 600 px wide the web shows rows as cards (168 px high); the phone should do the same.

---

## Part B. Files in the Smart View (web changes, branch `feat/files-viewing`)

### B1. What a file cell shows now
Every file chip reads **`name  TYPE · size`**, for example `Quarterly report.pdf  PDF · 51 KB`.
- **TYPE** = the file's extension in capitals (`PDF`, `PNG`, `XLSX`). With no extension it falls back to what the file is (`IMAGE`, `DOC`, `TEXT`), else `FILE`. Only plain letters/digits are ever drawn.
- **size** = the real size (`980 B`, `1.5 KB`, `5.0 MB`). A size of **0 or missing is left out** (the server sends `0` when it has no record; do not show "0 B").
- A long name is cut with "..." **before** the type and size are, so those two always stay readable. The web keeps the first 120 characters of a name.
- The first file is a chip; the others are "+n". A taller record lists every file.

The **preview header** reads `PDF · 51 KB · Uploaded Nov 24, 2026 · 1 of 5` (type, size, upload date from `uploadedAt`, position).

### B2. How the web gets the details
`submissions.list { tstruct, limit, offset, fetch:true, withDetails:true, fileMeta:2 }`. With `fileMeta: 2` (exactly the number 2) each file entry also has `ext`, `uploadedAt`, `etag`. An older server ignores the flag; the chip then shows the type from the name and the old `size`.
A chip is built from the record's file field value (a list of 24-hex file ids) and `files[field]` = `[{id, name, mime, size, ext?, uploadedAt?, etag?}]` (rows of a grid section: `files["<section>.<row>.<field>"]`). Treat each new value defensively: `ext` is `""` when the name has none; `uploadedAt` is epoch ms or `null`; `etag` is **bare 64-hex** (the HTTP header quotes it) or `null`. An id with no stored facts is **omitted** from `files`: show a chip named "File" with no size.

### B3. Opening a file: cache and revalidate (new)
- First read: `GET /api/sd/files/<id>` (Bearer). Keep the bytes under the response `ETag` (the quoted SHA-256).
- Next read: send **`If-None-Match: <etag>`**. The server checks the **permission first**, then answers **304** with no body; show the kept bytes. A changed file gives 200 with a new ETag.
- **Never skip the request** because you have a copy: the permission check on every use is what makes a removed permission or deleted file take effect at once. A **403/404 must drop the kept copy**. A network failure keeps it. A 304 you did not ask for is an error.
- Keep only files with a **strong ETag** (quoted 64-hex), non-empty, at most 10 MB; at most the newest 24 files / 30 MB in memory; clear all on sign-out.
- Two overlapping reads of the same file by the same session should share one request.
- Do not trust `Content-Type` to decide what to show: the web reads the first bytes (PNG/JPEG/GIF/WebP/PDF signatures). Never render SVG or HTML.

Measured live: after the first open, every reopen of a file was a 304; a changed ETag re-downloaded; a person with no access got 403 and not the kept copy.

---

## Part C. Server API (built by the backend team, on dev, not in PROD)

### C1. Files
| What | Contract |
|---|---|
| `fileMeta: 2` | on `submissions.list` and `records.mine`: entries gain `ext`, `uploadedAt`, `etag`. Without it replies are exactly as before |
| `GET /api/sd/files/<id>` | Bearer. `ETag` (quoted SHA-256), `If-None-Match` -> **304** (permission checked first). `Range: bytes=a-b`, `a-`, `-n` -> **206** with `Content-Range`; **416** past the end; several ranges / bad syntax / another unit / a stale `If-Range` -> the whole file with 200. `Accept-Ranges: bytes`. Always `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`. **`Content-Type` is the real type only for a safe list** (png, jpg/jpeg, gif, webp, pdf, txt, csv, mp3, m4a, aac, wav, ogg, mp4, mov, webm, doc/docx, xls/xlsx, ppt/pptx); everything else is `application/octet-stream`. `Cache-Control: private, no-cache` (with an ETag; `no-store` when the hash is unknown) |
| `GET /api/sd/files/<id>/link` | `{url, expiresIn, name, size, mime, etag}`. `url` and `expiresIn` are `null` for a file on the server's disk (then use the plain download). The link lasts 60 s by default |
| Errors | 401 no sign-in; 403 "That file isn't available to you."; 404 "No such file." / gone; 413 too large (10 MB default); 400 empty upload |
| Upload | `POST /api/sd/files?name=<name>`, raw body, Bearer; 10 MB default; 60 uploads per hour per person |
| Not built | **Thumbnails** (needs an image service): download the full file and cache it by ETag. **Deleting unused files** is off by default (files are only marked) |

### C2. `records.overview` (counts without records)
`records.overview { tstruct?: string | [string], tzOffsetMinutes?: integer }` -> `{ structures:[{tstruct,total,pending,approved,rejected,recorded,last,days:[7 oldest first]} | {tstruct,error}], totals:{records,thisWeek,waiting}, partial }`. "This week" = the last 7 days including today; days use the caller's timezone (`getTimezoneOffset` convention, UTC if missing); "waiting" = every pending record the caller can see; counts are over **all** visible records (no 500 cap); one failing structure does not fail the call; limit 120 a minute per person. Full contract and real samples: `MOBILE_RECORDS_OVERVIEW.md`. The web no longer uses it; **mobile does**.

### C3. `records.query` additions (used by the Smart View's team filter and the Inbox)
`team {members?, linked?}`, `taggedTo [user|"me"]`, `withDetails: true`, `views [...]`, `facets: true`. See the Inbox document for the full list.

### C4. Mobile logs (separate feature)
`POST /api/sd/mobilelog` with the signed-in person's Bearer token (no API key); at most 5 MiB per file, 200 files per person per day, kept 7 days. Contract and Postman files are in the backend team's `Connectum-Mobile-Logs-API` folder. PROD needs `/var/log/ConnectumMobileLogs` on every node (infrastructure).

---

## Part D. Verification status (be honest about it)
- **Backend suites run against a backend built from dev source** (this week): file meta 56 passed, file download 138, unused-file marking 57, sweep-off 6, records overview 132; all 0 failed.
- **Web file code driven against that real backend:** 39 checks passed (first read, 304 reopen, changed ETag, 403 for another person with the same ETag, bad token 401, unknown id 404, malformed id, view, download, upload errors, sign-out clearing, chips with type and size for every kind of name).
- **Browser:** chips, preview header and 304 reopen confirmed on a signed-in test session.
- **Not done:** a real phone; Postman collection; S3/Oracle storage and multi-node behaviour; the team filter was not tried as a person with no reports (the code path says the lines are hidden).

## Part E. What the mobile team should do
1. Smart View: drop any Overview and My team source; open on the first structure; add the two team lines (A2) using `records.query team`.
2. Files: ask `fileMeta: 2`; draw `name  TYPE · size`; revalidate opens with `If-None-Match`; honour 403/404 by dropping the copy; use `/link` only when `url` is not null; resume/seek large files with `Range`.
3. Overview on mobile: `records.overview`.
4. Merge the latest `dev` into your branch before the next push, and test on dev with a real sign-in.
