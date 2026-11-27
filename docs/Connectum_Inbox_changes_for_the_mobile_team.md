# Inbox changes for the mobile team

**What this is:** every change made to the Inbox on web, what the server now does, and what mobile needs to do.
**Where the code is:** branch `feat/inbox-files-search` (PR #1003 into `dev`, not merged). Part of it is already on `dev`: release **v0.2.67** (see section 9).
**Docs in the repo:** `docs/CONNECTUM_API.md` (`req.team`, `record.card`, `inbox.views.*`), `docs/FILE_DOWNLOADS.md`, `docs/SMART_VIEW.md`, `docs/MOBILE_RECORDS_OVERVIEW.md` section 8.

---

## 1. Summary

| # | Change | Server change? | Mobile action |
|---|---|---|---|
| 1 | `#inbox` opens the full Inbox directly | no | none (web only) |
| 2 | Record cards show file names and open a preview | optional request args | show name, type, size; preview |
| 3 | Inbox search also matches file names, field names, answers | no | optional |
| 4 | Approvals list: chips + Me / My Team toggle | **new `req.team`**, `returned` flag | build chips and toggle |
| 5 | Approvals filter panel (Search in, Data, Raised by, Approver, Date, Sort, Advanced) | no | optional |
| 6 | Saved views: main Inbox only; Approvals is never saved | no | none |
| 7 | Notification "View submission" opens that one record | **new `record.card`** | open the same record |
| 8 | Smart View opens the view saved last | no | only if mobile has Smart View views |

---

## 2. `#inbox` and the cards (web)

- `#inbox` opens the full Inbox section directly. The old pop-up card inside My Workspace is gone.
- Cards have a fixed default size (height 300 px), can be resized, and the grid shows 1 to 5 columns depending on width.
- A file row inside an update ("files that came with an update") is one tidy row: clip, file name on one line (full name on hover), size, and who attached it under the name.

## 3. File preview and file names

**What the user sees:** a file answer shows the **file name, type and size** (not the file id) and a click opens the preview.

**Server (all optional, an older server ignores them):**

| Call | New argument | Result |
|---|---|---|
| `submissions.list` | `withDetails: true, fileMeta: 2` | per record `files` (name, type, size per file field) and `labels` |
| `records.mine` | `fileMeta: 2` | the same file facts for the Inbox lists |
| `records.query` | `withDetails: true, fileMeta: 2` | the same for the Inbox filter |

With `fileMeta: 2` each file entry also has `ext` (lower case), `uploadedAt` (ms) and `etag` (64 hex). `""` or `null` means unknown: leave it out. A file with no stored facts is shown as "File".

**Download `GET /api/sd/files/<id>`** (Bearer token, permissions unchanged):
- Always `Content-Disposition: attachment` and `X-Content-Type-Options: nosniff`.
- Real `Content-Type` only for png, jpg, jpeg, gif, webp, pdf, txt, csv, mp3, m4a, aac, wav, ogg, mp4, mov, webm, doc, docx, xls, xlsx, ppt, pptx. Anything else (html, svg, xml, js, json, unknown) is `application/octet-stream`. **Never render those; read the first bytes to decide.**
- `ETag` = stored SHA-256. Send `If-None-Match` for a cheap `304`. The permission check runs first: a person who lost access gets 403/404, never 304.
- `Accept-Ranges: bytes`: one `Range` (`a-b`, `a-`, `-n`) gives `206`; out of range gives `416`.
- Files never change for an id, so cache by id + ETag. `Cache-Control` is `private, no-cache`.

**Mobile to do:** show name, type and size on the card; open the preview from the chip; cache by id + ETag; never render html/svg/xml.

**Search (web):** the search box matches file names, field names and answers as well as form, people and status.

---

## 4. Approvals list: chips and Me / My Team

**Where:** the Approvals button in the Inbox header. It is only a **filter on the requests**; the main Inbox keeps the saved views (section 6).

**Chips:** All, Pending, Approved, Requests, Rejected (each with a count).
**Toggle:** **Me / My Team** on every chip. My Team appears only for a person who has direct reports.

| Chip | Me | My Team |
|---|---|---|
| All | all entries below | all team entries |
| Pending | Pending by me, Pending with me | Pending to team |
| Approved | Approved by me, Approved for me | Approved to team |
| Requests | Sent to me, Sent by me | Sent by team |
| Rejected | Rejected by me, Rejected for me | Rejected to team |

**What each entry means** (read from `req.list` and `req.team`):

| Entry | Rule |
|---|---|
| Sent to me | I am an approver, or I may answer it (for example an administrator) |
| Sent by me | I raised it (`direction: outgoing`) |
| Sent by team | a direct report raised it, any answer |
| Pending by me | I raised it and it still waits |
| Pending with me | it waits for my answer (`canRespond: true`) |
| Pending to team | a direct report raised it and it waits for my answer |
| Approved by me / Rejected by me | I answered it (`resolvedBy` is me) |
| Approved for me / Rejected for me | I raised it and it was approved / declined |
| Approved to team / Rejected to team | a direct report raised it and I approved / declined it |

Rules to keep identical on mobile:
- A **returned** request counts as a rejection and its card says **Returned**.
- A dismissed or withdrawn request is in none of the entries and is not listed.
- There is **no** "Sent to team" and **no** "Approved by team".
- Show Approve / Decline / Return only when `canRespond` is true.
- Hide the toggle when the person has no direct reports.

**Server, new: `req.team {status?, limit?, offset?}`** (level `user`)
- Returns `{requests, total, offset, limit, hasMore}`: the approval requests (type `submission`) that the caller's **direct reports** raised. Read only.
- Only where the manager may read the record as a manager (the form's own permission; `hideFromManagers` turns off the team-involvement rule only). The author's manager always reads.
- Each request is decorated like `req.list` and carries `team: true`. No reports gives an empty list.
- `status` defaults to `all`; `limit` at most 200; page with `offset` until `hasMore` is false. Web reads up to 5 pages (1,000 requests).
- An older server answers with an error: treat it as an empty team list.

**Server, changed: `req.list`** items carry `returned: true` for a returned request (still stored as a rejection). Fields the screen uses: `status`, `direction`, `canRespond`, `fromUser`, `approvers`, `resolvedBy`, `returned`, `type`, `submissionId`, `tstruct`.

## 5. Approvals filter panel (the behaviour to copy)

The panel changes with the chip that is on.
- **Search in** offers that chip's entries (for example Pending: Pending by me, Pending with me, Pending to team).
- **Nothing is ticked until the person ticks it.** Pressing a chip or the toggle sets no filter. The field shows, in grey, what the toggle is showing (for example "Pending by me, Pending with me").
- The **badge** on the filter button counts only what the person changed. Ticking an entry shows 1; taking the tick away again shows nothing.
- If the person ticks entries of one side only, the toggle follows it; a mixed choice lights neither side.
- Other lines: **Data** (the forms, with counts), **Raised by**, **Approver**, **Date** from / to, **Sort** (Latest, Oldest, A to Z, Z to A) and an **Advanced filter** (blocks of forms with and / or conditions on answers; text, number and date operators).
- The Advanced filter reads only the answers a request card carries (up to 8 summary fields, found by the field caption). "Tagged to" is not applied to requests.
- The filtering of requests happens **in the app** on what the server returned. The server decides who may see a request.

---

## 6. Saved views of the Inbox

- Save view, Save as new view, Create view, Remove view: unchanged calls `inbox.views.get`, `inbox.views.save {name, view, default?}`, `inbox.views.delete`.
- The view saved last is the one that opens first (the server's `default`); `#inbox` opens it.
- **The Approvals list is never part of a saved view.** The saved view is the main Inbox's filters only. (Release v0.2.67 briefly saved an `approvals` part in a view; this was removed again. Ignore any `approvals` key you may see in a view.)
- When the Inbox is opened from a "Review approval" notification, the Approvals list opens first, with no filter, and the saved view sits under it.

---

## 7. Notification "View submission" opens that record

A "New submission: <form>" notification carries `ref: {submissionId, tstruct}`. **On web, View submission now opens the Inbox on that one record** (its card, headed "Submission #N", with a **Show all records** button that returns to the usual Inbox). It no longer opens the list of all records.

**Server, new: `record.card {id, fileMeta?}`** (level `user`)
- Returns ONE record as the Inbox cards read it: `{submissions: [record with files, labels, canEdit], structures}` (the same shapes as `records.query` with `withDetails`).
- Access is the same check as `submission.get`: linked to the record, a manager of someone on it, or an administrator.
- A record the caller may not read: "I cannot view it." A record that does not exist: "No such submission." A bad id: an error, never a crash.

**Mobile to do:** open the record by `ref.submissionId` through `record.card`; on a refusal show the server's message and stay on the usual screen. If the notification has no record number, open the list.

## 8. Smart View saved views (only if mobile has them)

In the Smart View of a form or source, the view saved last (the Default View or a named one) now opens first; before, the Default View always opened. The server keeps the list in order (`smartview.views`, `smartview.views.save`), so the first view in the list is the one to open. No server change. Also fixed on web: the Options menu that opens upward was cut off at the top.

---

## 9. Status and release

| Part | State |
|---|---|
| Approvals chips, Me / My Team, `req.team`, `returned`, file names and previews, `#inbox` direct | on `dev`, released as **v0.2.67** |
| Approvals not ticked by default / badge counts changes / not saved in views, `record.card` and View submission, Smart View opens last saved view, polished file rows, Options menu fix | branch `feat/inbox-files-search` (PR #1003 into `dev`), **not merged and not released** |

The server parts (`req.team`, `record.card`) need the backend release before mobile can use them against a real server.

## 10. Verified and not verified

**Verified:**
- Frontend tests for the approvals model and panel, the saved-view round trip, file names and search, and Smart View views.
- Backend suite `connectum_record_access_test` (272 checks, 0 failed, includes `record.card`) and the `req.team` checks in `connectum_approvals_test`.
- Real browser on a local test organisation: every chip on both sides, the panel following chip and toggle, the badge, Save view then reload, View submission opening the record, Show all records.

**Not verified:**
- The full backend regression (only the affected suites ran).
- The team side on a real server before the backend release.
- Saving and restoring the Approvals panel's own lines in the browser (unit tests only).
- The refused case of View submission in the browser (backend tests cover the refusal).
- The contrast script (it needs puppeteer); contrast was checked by calculation.

**Questions:** to the web owner.
