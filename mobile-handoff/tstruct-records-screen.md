# `#tstruct <name>`: the Studio records screen (Task O)

Read from `origin/dev` of ~/Development/Axi-apps, commit 4184e548589a2d4ac586ead28bcad69d26db6bc7 (still the tip after `git fetch`). Paths under `connectum/`. Follows `tstruct-commands-web.md`.

## What the server answers to the `#tstruct <name>` line
- Mobile never sends the line. `CommandRepository.run` returns `HashKind.records` with the typed name; `CommandRunner._openStructure` calls `SubmissionRepository.openStructure` = `tstruct.user.open {name, mode:"add"}` (`submission_repository.dart` `openStructure`; the web sends no `mode` for `#tstruct`, the server ignores it, `sd_cmds_forms.erl:190-222`).
- Answer: `{tstruct: <definition>, scope: "user"|"admin", rev, submissions: [my own records]}`. The app keeps `tstruct` + `rev` + `scope` as the form definition and **ignores `submissions`**. Before Task O it then opened My Submissions filtered to the name; now it opens `/struct-records` with `StructRecordsLaunch(name, scope, caption, chat)`. Unknown name: `not_found` "No such structure, or it is not available to you." as before (warning notice, text kept).

## How the web page gets its records (`form-studio/src/studio/pages/RecordPages.jsx`)
- `Records` (17-130 in the file; `Promise.all([getStruct(id), listRecords(id,{withMine:true})])`, lines 35-41). `getStruct` = `tstruct.user.get {name}`, then `tstruct.get` if `not_found` (`core/api.js:714-730`).
- `listRecords` (`api.js:765-785`): `submissions.list {tstruct, recordsOnly:true}` (no limit/offset: server default 500, window = newest 1000 the caller may see, `sd_config.erl:1117-1140`), then with `withMine` a second `submissions.list {tstruct}` and adds only MY OWN `pending`/`rejected` ones (`by` = me), sorted newest first. The web does not page.
- Visibility is the server's: `can_see_submission` (`sd_config.erl:1322-1333`: admin, author, host, manager of the author, participant, team, `seeAll`, data access). Answer: `{submissions, total, offset, limit, hasMore, structures}`.
- Row (`connectumSubToWeb`, `api.js:536-553`): `id, tstruct, values, labels, by, ts, editedTs, status (pending|rejected|approved|null), rejection, result.message, axpertRecordId`. `withDetails:true` would add `canEdit` per row (`sd_cmds_forms.erl:119-135`); the page does not ask for it.
- Count = rows that are real records (`isRealRecord`, `format.js:19`); header says "N records".
- Hidden fields (`RecordsBrowser.jsx:20-22`, `api.js:566-569`, `gridModel.js:126-136`): the server still sends their values; for anyone who is not the structure's creator (`struct.owner`) or an administrator the field is removed from the struct and from every record. Read-only structures: `system` set and not `access`, or `recordHistory` (`RecordPages.jsx:80`).
- Card/table fields (`RecordTable.jsx:84-150`): "Record #n" (n = position, newest = highest), status badge only for pending ("Waiting for approval") / rejected ("Declined"), time ago, first 3 filled fields as label/value (`formatValue`, `format.js:3-16`). Table: Autogenerate first, then the fields that fit.

## Actions
- **New record** (`RecordPages.jsx:67,110`): hidden when read-only; opens the form page = `#tstruct-add`. Submit = `tstruct.submit` / `tstruct.user.submit` (`api.js:111-120`).
- **Edit** (`:128-129`): shown when `isMine(rec.createdBy) && rec.status !== 'pending'` (`isMine` = username equal, case-insensitive); opens the edit page; save = `submissions.update {id, values}` (`api.js:127-138`). The edit page warns "Only the person who created this record can change or delete it" for others (`:203`).
- **Delete** (`:130-134`, `RecordsBrowser.jsx:66-77`): same gate; ConfirmSheet "Delete this record?" / "Record #n will be permanently deleted. This can't be undone."; `submissions.delete {id}` (`api.js:122-125`); toast "Record deleted", list read again.
- Server rules (the only real gate): delete = author or creator of the structure, not locked, not a history/system record, `forbidden` / `submission_locked` / `not_found` (`sd_config_orgrecords.erl:137-170`); edit = author or data-access `can_edit`, not locked (`:198-206`).
- **Creator-only** (`:89-109`): Edit definition (creator or editor), Clone (not system), Delete definition (creator, not system; confirm "Delete X?"). Live: re-read quietly on `tstructs_changed`/record events; leave if the structure was deleted (`:53-65`).
- States: skeleton rows; empty "No records yet" + "New record"; error "Couldn't load this struct" + "Try again".

## What the mobile screen does (`lib/features/struct_records/`)
- Pushed over the chat. Header: Back, structure caption, count pill ("N records", total from the server), primary New record. New record = `FormLaunch(name, scope, caption, convId, postChoiceTitle, isPostedByDefault)` exactly as `#tstruct-add` (no second open: the definition is kept).
- Rows: `StructRecordsRepository.page` = `submissions.list {tstruct, recordsOnly:true, limit:50, offset}` through the Smart View gate (one at a time, paced, rate-limited, retried); first page also the second list (limit 100) for my waiting/declined ones. Load more at the end of the list. Pull to refresh (`AppRefresh`). Rows in memory only.
- Card: key field (else first filled) as title, "No. <id>" (the record id; the web shows a position), up to 4 filled fields, pill for pending/declined, files as "N files". Hidden fields cut as on the web (`StructRecordsSchema.of`); unknown types are plain text (`SvCell`).
- Edit/Delete: shown on `isMine(by) && status != pending` of a structure that is not read-only (web client rule, per row; the server's `canEdit` flag is not used). Edit = existing `/form` in edit mode (`submissions.update` through the outbox, `cid`), list read again 1.5 s after. Delete = confirm sheet (web words), then `SubmissionRepository.deleteSubmission` (refusals in plain words); row removed only on success or `not_found`.
- Tap on a row does nothing (the record/submission screens read local storage or need `record.actions`).
- Offline / not connected: the app's offline state with Retry. Demo: `lib/core/debug/seed_struct_records.dart` (remove before release with the other seeds).

## UNCLEAR
- Which records the server returns to a non-creator beyond `can_see_submission` was not traced further.
- Whether `submissions.list` `limit`/`offset` combined with `recordsOnly` pages the same window on every server release (code says yes).
- The web's "No." is a position; mobile shows the record id.
