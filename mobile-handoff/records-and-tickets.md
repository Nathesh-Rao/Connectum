# Records and tickets (the record flow)

Source of truth: `incoming/be-answers/irecords-and-tickets-2026-11-13.txt` (BE answers by number, dev release `061ed545`; the file name has a stray leading "i" on disk). Where `reference/` or the BE docs disagree with it, the answers win. Also used: `RECORD_ACTIONS.md`, `RECORD_THREAD.md` and `tools/postman/examples.json` on `origin/dev` of the web repo (read with `git show`, never changed). Captured replies live in `test/fixtures/records/`.

## Corrections from the BE's Smart View document, revision 2 (16 Nov 2026, `origin/dev` `a5f28fca`)

Verified by the BE on a backend built from dev (107 captures, copied to `test/fixtures/smart_view/real/`). They win over everything older in this file. Details and the capture numbers are in `reference/MOBILE_SMART_VIEW.md` (2.4, 2.4.1, 2.4.2, 2.11, 2.13, 4.7).

| # | Fact | Status for us |
|---|---|---|
| 1 | `records.mine` `next`: **always `null`** for `with`, `involved` and `all` (and `team` with no reports): continue with `offset += rows received` while `hasMore`. Only `raised` and `team` can answer a real `next`; use it, never offset + received. | Already how `TicketPage.nextOffset` and `PagedRead` work. Unchanged. |
| 2 | **Server defect:** `records.mine {as:"raised"}` with a small `limit` drops records and answers `hasMore:false` (limit 2 returned 2 of 4). With `limit` 200 nothing is dropped. `raised` `total` is the size of that answer, not of the list. | **Fixed in the app (16 Nov 2026):** `RecordLimits.mineLimit(as, requested)` is the one rule; `TicketRepository.mine` is the only caller of `records.mine` and always sends 200 for `raised`. `with`/`involved`/`all` keep the asked limit (default 100). The DEMO fake (`SeedTickets._mine`) now copies the defect (a 200-entry chunk). Tests: `test/tickets/records_mine_limit_test.dart`. Remove the rule when the BE confirms a fix (it is harmless to keep). |
| 3 | `all` is for administrators; anyone else silently gets `with`. An unknown `as` is treated as `with`. `limit` over 200 is clamped. An empty answer is `{hasMore:false, next:null, structures:{}, submissions:[], total:0}`, never an error. | Not offered (we do not know `isAdmin` early). Unchanged. |
| 4 | `team` (a manager's open records with direct reports) exists: adds `reports` (count) and `team:{members, via}` on rows; real `next`; read-only for the manager. Not captured with data. | Answers open item 4 below. Not built; `nextOffset` already follows `next` for `team`. |
| 5 | A `records.mine` row has `actedBy, actionSeq, assignor, branch, by, editedTs, holder, host, id, participants, scope, ts, tstruct, values` (+ `completion`, `hours`); **no `byName`, `canEdit`, `files` or `labels`**. | `Ticket.parse` already reads these; names come from what we hold. Unchanged. |
| 6 | A person who **received** a record may not edit or delete it (`submissions.update` / `submissions.delete` answer `forbidden`); what they may do is the workflow: `record.actions` -> `send` / `status`. The author may still edit a record that is with someone else. `canEdit` exists only on `submissions.list` rows (`withDetails`); `canDelete` exists nowhere. | Matches our rules (Edit/Delete only for my own records; received records get the workflow only). Unchanged. |
| 7 | An **administrator cannot delete someone else's record** (`forbidden`). | Matches: our delete button is "mine" only. Unchanged. |
| 8 | No access is always `not_found` ("No such submission." / "No such record.") for `submission.get`, `submission.history` and `record.actions`; never `forbidden`. | Matches the error table. The `forbidden` branch for these three is dead code only. |
| 9 | Record commands are WebSocket only. `POST /api/sd/<command>` does not exist (`not_found` "No such endpoint."). Fixed at the source in `RECORD_ACTIONS.md` and `MOBILE_RECORDS_FULL.md`. | No change; doc error 1 below is now closed. |
| 10 | **`data.record` on events exists on dev since 16 Nov 2026 (#822)**, in no release (`main` and tag `v0.1.0` lack it): `submissions_changed` and `ticket_assigned` carry `record = {by, claimants, completion, final, holder, status, ts}` for a person who may read the record. No `record` means "unknown, ask", never "no status". `deleted` carries none. `records.summary {ids <= 50}` returns `{id, tstruct, record}` (1,500 ids a minute). | **Not used.** The "Live card" section below ("No event carries status") is true for every server that has no #822 and stays our rule; a server with it would let a card patch with no read. Decision pending which release carries it. |
| 11 | Hidden fields are **not removed** by the server from record payloads (`values`, `structures.<form>.fields` captions, `tstruct.user.get` with its `default`); only the Smart View source list leaves them out. | A security question for the BE owner, see `mobile-handoff/smart-view.md` "Security: hidden fields". |

**What these change in our code and docs (list only, nothing else was changed):**
- `lib/data/repositories/ticket_repository.dart` `mine`: the raised limit (changed). Doc comment on `mine` updated.
- `lib/data/records/record_commands.dart`: `RecordLimits.mineLimit` (new).
- `lib/core/debug/seed_tickets.dart` `_mine`: copies the raised defect; page cap now applies to with/involved only (changed).
- `test/tickets/record_commands_test.dart`: the raised request now expects `limit: 200` (changed).
- Unchanged but now confirmed: `TicketPage.nextOffset`, `PagedRead`, the workspace sync (`_list`, involved + with only), the delete rule, the `not_found` handling.
- To decide later (not changed): reading `data.record` on events (`TicketRepository` event handlers, "Live card" below) once a release carries it; whether the record screens draw hidden fields; `team` support; `isAdmin` for `all`.

## Visibility, sharing and workspaces (BE doc of 16 Nov 2026)

Source: `reference/MOBILE_RECORDS_FULL.md` (from `connectum/docs/MOBILE_RECORDS_FULL.md` on `origin/dev` `374648ec`, 33 scenario checks on a scratch backend; web side read from `useWorkspaceSubmissions.js`, `formMessages.js`, `RecordActions.jsx`). It adds to the answers above and wins where they differ. What the app does with it:

### Where the document differed from our docs or code (all changed)

| # | The document | We had | Now |
|---|---|---|---|
| 1 | A record card is a form message whose form has a numeric `submissionId`, is not `readonly` and has no data-source `result`. Whether it shows a status is `record.actions`' answer. | Record only inside a `rec-` conversation, for a form listed by `records.mine`, a record already read, or the removed `ticket` flag; "an ordinary form card never asks the server". | `RecordCardRule.of` (`features/tickets/models/record_card_rule.dart`), the web's rule. `FormCardData.isReadOnly` replaces `isTicket`. |
| 2 | `record.actions` is read for the menu and the status line (web: when the card is shown; ours: lazily, see below). | `ensureTicket` ran `submission.get` + `record.actions` for every card drawn (post-frame, per card). | Nothing is read while drawing. The long-press menu (chat and workspace) and the record screen read `record.actions` once per record (60 s cache, cleared by any record event). |
| 3 | My Workspace = own `submissions.list` + `records.mine as=involved` and `as=with` (not mine, not waiting, once per id), inside ONE organisation. | Only own records from `submissions.list` (5-page cap, errors swallowed). Records sent to the person never appeared. | `WorkspaceRepository` (`data/repositories/workspace_repository.dart`) + `WorkspaceController`; see "My Work Space" below. |
| 4 | `with` and `involved` answer `next: null` even when `hasMore` is true: continue at `offset += rows received`. `raised` and `team` answer a real `next`: use it. | `next` ignored everywhere; offset counted only the rows we could parse; `raised` paged by rows held. | `TicketPage.received` (raw rows) and `TicketPage.nextOffset(as, offset)`; `raised` follows `next`. |
| 5 | Old records (never sent or acted on since 11 Nov, #752) are in `submissions.list` but in none of `with`, `raised`, `involved`. | Not known. | The workspace uses `submissions.list` for own records, so they show. Lists that read `records.mine` alone (Tickets tabs) do not show them: by design of the server, not an app fault. |
| 6 | A person without access gets `not_found`, never `forbidden`. | Same (error table). | Unchanged. |
| 7 | Every record command is scoped by the session's organisation; switching is a new `enter` and a new connection; ids are per organisation. | Same in code (`AuthRepository.enter` -> `leaveCurrent` -> new socket; `TicketRepository._reset`). | Re-checked; `WorkspaceRepository` clears too and drops a read that was running (below). |
| 8 | `RECORD_ACTIONS.md` HTTP route sentence is wrong. | Already in "Doc errors". | Unchanged. |
| 9 | Open question 5 (a flag on the form message): the answer is the rule in row 1; no flag is coming. | Listed as open for the BE. | Closed. |

### Two BE gaps, handled (Findings 1 and 2 of the document; the BE has not fixed them)

1. **An approver of an open stage and a notified person** open the record (`submission.get`, `submission.history` ok) but `record.actions` is `not_found`, and the record is in no list. The record screen opens **read-only**: details and history, no Send / Update status, no error screen, no retry. Code: `TicketRepository.get` returns `TicketDetail.isReadOnly`; the case is logged `[records] id=N submission.get ok but record.actions not_found: BE gap, opened read-only`.
2. **A person with form-wide visibility** (`seeAllUsers`, a designation, the form's creator, branch access) lists the record (`submissions.list {tstruct}`, `records.list`) and `record.actions` works, but `submission.get` and `submission.history` are `not_found`. When a list row for the record is known (`records.mine`), the screen shows that row's values with a calm notice ("You can see this record in the list but not open it yet."), no history, and no retry loop (the refused `submission.get` is not asked again for 60 s). Code: `TicketDetail.isUnopenable`; logged `[records] id=N listed but submission.get not_found: BE gap, showing the list row`. An id never seen in a list is simply "no longer available".

The app does not call `submissions.list {tstruct}`, so (2) can only be reached through a `records.mine` row or a notification. If the BE fixes either gap nothing changes in the app: the gap branches are never taken.

### My Work Space (web parity: `useWorkspaceSubmissions.js`)

- Built on the device inside the CURRENT organisation: own records (`submissions.list`, up to 10 pages of 100, cached in SQLite; the latest 100 shown as cards, plus any still waiting to be sent), received records (`records.mine as=involved` then `as=with`, up to 10 pages of 100 each; dropped when `by` is me or the record waits for approval; once per id, involved first), oldest at the top, newest at the bottom. A received record is ordered by `editedTs`, else `ts`; an own one by `ts` (as the web). Received cards are keyed `rec-<id>`, own `c-<id>`.
- Received records are kept in memory only (like the other record lists): offline after a restart the workspace shows the cached own records, and the received ones come back with the first read.
- A tap on a received card opens the record screen; a long press (any numeric, non-pending card) opens the record menu (`record.actions` read at that moment).
- Reads: one at a time, pages one after the other with 350 ms between pages, a read at most every 6 s (the web's gap), a burst of events is one read after 1 s. Triggers: opening the screen, `submissions_changed`, `ticket_assigned`, `feed_item`, socket online, app resume, pull of the error screen's Retry. A read is at most 10 + 10 + 10 commands (30 only with three full lists; a normal one is 3) against the 30 per 10 s limit.
- The page limit is explicit and logged (`[records] <list> stopped at the 10-page cap with N rows read; the server has more`), and so is every failure (`[records] <list> failed at offset=N after P page(s): <code>`).
- Errors: a failed read keeps what was shown. With nothing to show it is the error state with Retry (never the empty state; offline is not an error). With cards on screen a short notice says the refresh failed.

### Organisations (checked in code)

- Every record command goes through the one socket of the current session (`SocketService.sdCall`); there is no `enterprise` argument anywhere. `AuthRepository.enter` -> `SessionRepository.leaveCurrent` (closes that socket, clears the token) -> `signIn` -> `socket.start()`: a new `enter` and a new connection.
- Per-organisation record state is cleared when `SessionStore.current` changes: `TicketRepository._reset` (known records, forms, states, menu caches, names, badge), `WorkspaceRepository._reset` (received list), `SubmissionRepository` (rows reload for the new org and user). The home is rebuilt on a switch (`HomeReload`), so the Tickets and workspace screens' own lists are gone with it. A read that was running while the organisation changed is dropped, not shown (`WorkspaceRepository._read` and `PagedRead` compare the scope).
- The `[records] session` line (once per person and organisation: org, user, connection, token, the person's workspaces) is kept.

### Probe (`tools/records-probe.mjs` on the web repo, for the owner only)

- What it prints for each organisation: the organisation the session resolves to (`GET /api/sd/session`), the person's organisations (`GET /api/sd/me`, email sign-in only), counts for `records.mine` `with`, `raised`, `involved`, `team` (records over pages, total, hasMore, first ids, whether offset paging works), `submissions.list` (how many on the first page, how many made by the person), `feed.list` (items by category, how many name a record, their ids), and `submission.get` + `record.actions` for the first id of each list (ok or the error code). It prints counts, ids and yes/no only, no record text and no token (`--shape` adds the JSON shape with texts replaced).
- **An email sign-in REPLACES the phone's session** (it enters the organisation and ends the earlier session of the same kind; the probe's WebSocket is also the person's live connection while it runs). The owner must agree first and sign in on the phone again afterwards. With `--token` (the app's own organisation token) no new session is made, but the token is secret: never paste it anywhere.
- **Only the owner runs it. Claude Code never does** (it needs the owner's email code or token, and it would sign the phone out). Run: `node tools/records-probe.mjs --base https://dev.connectum.app --email <email> --start`, then `--email <email> --otp <code> --all-orgs --shape` (Node 22+, no packages). Send the whole output to the BE team, with what the web's My Workspace shows for the same person and organisation. How to read it is in the document, question 8.

## Doc errors (BE confirmed)

1. `RECORD_ACTIONS.md` says record commands are also `POST /api/sd/<command>`. Wrong: they are **WebSocket only**, `/sd <action> {json}` answered by `{type:"sd", reqId, ok, data | error:{code,message,details?}}`. Plain HTTP answers 404 `not_found` "No such endpoint." (Fixed at the source by the BE on 16 Nov 2026, verified.)
2. `TASKS_AND_ACTIONS_FOR_MOBILE.md` says `task.fetch`. Wrong: it is `task.get`. It is also outdated about `records.mine` options.

## Removed on the server, no alias

`status.mine`, `status.get`, `status.update`, `status.history` answer `unknown_action` since 11 Nov (PR #752). `structures[form].status.actions[]` is gone.

## Migration map (old -> new)

Line numbers of the old code are from `HEAD` before this change.

| Old | New |
|---|---|
| `status.mine` (`ticket_repository.dart:179`) | `records.mine {as?, limit?, offset?}` (`RecordCmd.mine`, `TicketRepository.mine`) |
| `status.get` (`:202`) | `submission.get {id}` + `record.actions {id}` read together (`TicketRepository.get`) |
| `status.history` (`:219`) | `submission.history {id}` (`TicketRepository.history`, `RecordHistory`) |
| `status.update` (`:231`) | `record.status` (`setStatus`) and `record.send` (`send`); helpers `record.targets`, `record.people`, `record.thread` |
| `structures[].status.actions[]`, `TicketAction`, `TicketTable.actions/editableIn/assignee/completion/subject/pool` (`models/ticket.dart:19,99-157`) | `TicketTable` is `{field, statuses, final}`; the menu is `RecordState.items` from `record.actions` (`models/record_state.dart`) |
| `TicketActions.of/canEdit` (`features/tickets/models/ticket_actions.dart`) | deleted. The server says who may act (`items[].enabled`, `why`); no client-side guessing |
| `TicketPayload.build`, `TicketValidation`, `TicketActionInput` (`ticket_input.dart`) | `RecordPayload.status/send`, `RecordValidation`, `StatusInput`, `SendInput` |
| `TicketActionForm` and `ticket_action_sheet.dart` (one sheet from a per-form action) | one status sheet and one send sheet from `items` `status` and `send` |
| `TicketHistoryEntry` (values-based: `Action`, `FromStatus`, `Percent`...) | `RecordEvent` (`op`, `to[]`, `fromStatus`, `toStatus`, `completion`, `hours`, `changes[]`...) |
| `TicketUpdateResult` (`status`, `assignee`, `record`, `ticket`) | `RecordPatch` (`holder`, `assignor`, `status`, `completion`, `hours`, `final`, `files`, `repeated`) |
| `Ticket.isTicket`, `form['ticket']` (`form_card.dart:148`) | gone. `TicketRepository.isRecordForm`, `ConversationController.recordIdOf` |
| `Ticket.withWhom` from the assignee field | `holder` from the row (`records.mine`) and `record.actions` |
| `TicketRepository` 60 s cache `cardTtl` (`:55`), `ensure`, `nameOf` (`:93`) | kept; `ensure` now reads `submission.get` + `record.actions`; `nameOf` also learns names from histories |
| Burst `150 ms` (`ticket_repository.dart`, `task_repository.dart`) | 300 ms debounce |
| Tabs With me / Raised by me | With me / Raised by me / Involved; pages read while `hasMore` |
| Chat info ticket section (`chat_info_controller.dart:105-107`) | reads the known record (`known(id)`); same page |
| Notification `tickets` mapper, `_openTicket` (`notification_router.dart:291-327`) | opens the record by `ref.submissionId`; no "not a ticket" fallback |
| `SeedTickets` + `assets/debug/tickets/*.json` (old captures) | in-memory server for the new commands (`core/debug/seed_tickets.dart`); fixtures moved to `test/fixtures/records/` |
| `'task.get'` etc. strings (`task_repository.dart:111-193`) | `TaskCmd` constants (`data/records/record_commands.dart`) |
| Tests `ticket_test`, `ticket_input_test`, `ticket_actions_test`, `ticket_detail_controller_test` | rewritten for the new flow (`test/tickets/`) |

There is no SQLite table for tickets or tasks (the repositories keep only the badge and the last records read in memory), so no migration and no cache to clear on upgrade.

## Commands

All through `SocketService.sdCall`. Names in one place: `lib/data/records/record_commands.dart` (`RecordCmd`, `TaskCmd`, `RecordEvents`, `RecordLimits`).

| Command | Request | Answer |
|---|---|---|
| `records.mine` | `{as?: with\|raised\|involved\|all, limit?, offset?}` | `{submissions, structures, total, hasMore, next}` |
| `submission.get` | `{id}` | `{submission}` |
| `record.actions` | `{id}` | `{items:[{id:send\|status, label, enabled, why?}], holder, claimants, initiator, assignor, status, statuses, final, completion, hours, commentsRequired, completionRequired, hoursRequired, filesRequired, isAdmin, hasRules, lastUpdate, files}` |
| `submission.history` | `{id}` | `{events (oldest first), names, files, status, caption, fields, sections}` |
| `record.status` | `{id, status, comments?, percent?, hours?, files?, expected?, requestId?}` | patch `{id, holder, status, completion, hours, final, files}` |
| `record.send` | `{id, via, person?, value?, reason?, remarks?, files?, expected?, requestId?}` | patch `{id, holder, assignor, status, completion, files}` |
| `record.targets` | `{id}` | `{unrestricted, designations, categories, initiator, assignor, blocked}` |
| `record.people` | `{id, q?, designation?, category?}` | `{people:[{username, name, designation}], total}` (at most 50) |
| `record.thread` | `{id}` | `{conversation: "group:rec-<slug>-<id>", id, title}`; `not_found` when the form has no thread |
| `tstruct.submit` | `{name, values, ref?, meta?, chat?, cid?}` | `{submission, recordStatus: saved\|pending}`; no recipient argument |
| `submissions.update` | `{id, values, meta?, cid?}` | `{submission}`; replaces ALL values |
| `submission.resubmit` | `{id, values?, meta?, cid?}` | `{submission}` |
| `submissions.delete` | `{id}` | `{deleted:true}` (not built in the app) |
| `task.create/get/list/update/send` | see `tasks-notifications-audit.md` | `task.get` -> `{task}`; tasks are unrelated to records |

### `records.mine` rules

- `with` (default): open records I hold. `raised`: records I created that are now with someone else or waiting for approval (looks at my newest 1,000 only). **`raised` is always asked with `limit` 200** (`RecordLimits.mineLimit`): a smaller limit makes the server drop records and answer `hasMore:false`. `involved`: given to me, shared with me or acted on by me, never my own. `all` is administrator-only (others get `with`): **not offered**, the app does not know `isAdmin` before a record is read.
- Newest first, offset paging, default limit 100, max 200, out-of-range values clamped. **A page can be shorter than `limit` while `hasMore` is true: always continue until `hasMore` is false** (`TicketsController.load`, guard of 50 pages). `with` and `involved` answer `next: null`: continue at `offset + rows received`. `raised` and `team` answer a real `next` (the scan position, not a row count): continue there (`TicketPage.nextOffset`).
- `total` is real for `with` and `involved`. For `raised` it is only the rows of the page: **never shown**. The badge uses `with` only.
- No filter by status or form on the server; the form filter on the screen works on what is read.
- `structures[form].status = {field, statuses, final}` (absent when the form has no status). The first status is where a record starts; any status can move to any other; the same status is refused ("It is already X.") unless completion or hours change. Up to 20 statuses.
- A row has `holder`, `assignor`, `completion`, `participants`, `editedTs`, `actionSeq`.

### Status (`record.status`)

Who can act is the server's call (holder, administrator, any claimant of a shared record, first to act takes it; nobody while waiting for approval; a final status is administrator-only). The sheet opens from the `status` item. A disabled item opens with its `why` and a disabled button.

Fields: status (from `statuses`), comments (<= 1,000), percent 0-100 (cannot go down unless `isAdmin`, checked on the phone), hours 0-24 with at most two decimals (`2,5` is sent as `2.5`), files (<= 10, own uploads). Fields marked by `commentsRequired`, `completionRequired`, `hoursRequired`, `filesRequired` are mandatory with the BE wording ("Add your comments.", "Enter the completion.", "Enter the hours worked.", "Attach a file."; a completion of 0 and hours of 0 count). Nothing else is blocked on the phone.

Status sheet completion rules (phone-side conveniences; the server stays the judge and its messages are shown; `TicketActionForm` in `features/tickets/ticket_action_form.dart`, view in `widgets/ticket_action_sheet.dart`):
- A. Data: `record.actions` `completion`, `status`, `statuses`, `final` (list of status names), `completionRequired`, `isAdmin`. No extra call.
- B. The slider starts at the record's `completion`; "Not set" only when it is null. Non-admin minimum = that value (the part below is drawn locked, "Was 40%", the thumb is clamped, light haptic). An administrator is free from 0 to 100, no lock.
- C. A final status picked -> completion 100 (150 ms), slider locked while it stays picked.
- D. The slider at 100 on a non-final status -> the first final status (list order) is picked, with the hint "Set to <status> because completion is 100%". 100 always means closed. (This is how "max 99 for a non-final status" holds: the thumb may reach 100, but then the status is final.)
- E. Final -> non-final: completion goes back to the record's previous value if below 100, else 99 (only an administrator reopening a closed record).
- F. A final status picked shows the inline warning above the button: "Closing this ticket sets completion to 100%. After it is closed, only an administrator can change it." No dialog.
- G. A form with no final status in `final`: C-F do not apply (B does). `record.actions` does not say whether the form has a completion field; the slider is always shown.
- H. Status and percent are sent as the sheet shows them; percent is never below the minimum for a non-admin.
- I. Slider semantics "Completion 40 percent, minimum 40"; the locked part and the warning have labels.
- J. Comments, hours and files rules are unchanged.

### Send (`record.send`)

`via`: `user` needs `person`; `designation` and `category` need `value`; `initiator` and `assignor` need nothing. The `send` item exists only when Send is enabled on the form. People come from `record.people` (debounced search). Not to yourself, not to the current holder, not to someone blocked by the rules: the BE message is shown.

### `expected`, `requestId`, `cid`

- `expected = {status, holder}` (both optional): the values the screen shows (`RecordState.expected`). No version or timestamp exists.
- `requestId` (`record.send`, `record.status`): a UUID, <= 100 bytes, **made once per intent** (`TicketActionForm.requestId`) and reused on every retry of that intent; a new press or a new sheet makes a new one. The server remembers it 24 h per record and person, stored only after success; `repeated:true` is a success.
- `cid` (`tstruct.submit`, `submissions.update`, `submission.resubmit`): 1-64 characters `[A-Za-z0-9-_.:]`, one per save through the outbox (`m-` + UUID). A repeat returns the first answer with `duplicate:true` (an ordinary success). No retry without the same cid.
- After ANY action `record.actions` and `submission.history` are read again: only a patch comes back.

### Errors (by `code`, never by message)

| Code | Meaning | App |
|---|---|---|
| `stale` | updated by someone else | read `record.actions` + history again, keep the sheet and what was typed, show the message, a retry is a new intent (new `requestId`, new `expected`) |
| `forbidden` | not the holder etc. | show the message, read again |
| `not_found` | no such record **or no access** | close the record screen, refresh the lists |
| `invalid` | validation / final / waiting for approval | show the message |
| `bad_request` | missing id | show the message |
| `busy` | being updated | one automatic retry after 2 s with the same `requestId`, then the notice with Retry |
| `rate_limited` | too many commands (30 / 10 s; dev 200); no `retryAfter` | notice, the buttons wait 3 s, retry keeps the `requestId` |
| `invalid_values` | form validation on create/edit, `details.fields:{field:message}` | shown per field by the form flow (existing) |
| `submission_locked` | edit while pending/approved | message shown by the form flow |

### History events

`created, edited {changes[{field,from,to}]}, deleted, sent_for_approval, waiting, approved, declined, returned, resubmitted, approved_final, sent {to[], reason, remarks, via, value, fromHolder, asAdmin, claimed, status, files}, status {fromStatus, toStatus, completion, hours, remarks, asAdmin, claimed, final, files}, reassigned`. `via:"auto"` is auto-send. Names come from `names`, files from `files`.

### Record detail layout and the History panel (16 Nov 2026)

Layout (`ticket_detail_view.dart`, `widgets/fixed_top_layout.dart`): the page does not scroll. The top block (title, record and status pills, holder line, completion bar, Send / Update status, Edit, the form values) is fixed; the History panel (`TicketHistoryPanel`) takes all the height left, is anchored to the bottom, and its list scrolls inside it (`AppRefresh`, so pull to refresh works from the list). **Fallback:** when the top block leaves the panel less than 160 dp (`TicketHistoryPanel.minHeight`: many fields, 150-200 % text, a small phone), the page becomes one scroll view (top block, then the panel at its own height, at least 160 dp). The decision is measured, never guessed (`FixedTopLayout`: a height probe on the top block; it flips after one extra frame, so tests pump twice). A record the person cannot open (BE gap 2) keeps the old single scroll with its notice and no panel.

Order: newest first (the server's list reversed; event ids unchanged). A live event fades in over 150 ms (`AppDurations.reduced`). While the user is scrolled down the list, a new event waits and appears when the list is back at the top, so the list never jumps.

Item (`TicketHistoryItem`): a 28 dp dot on a thin rail (tinted circle, icon in the tone colour; the newest has a stronger tint and a ring), the existing title (`TicketsTexts.opTitle`; several recipients read "Sent to Ben +2"), one muted meta line (name, "by an administrator", "took it", then the relative time; a tap on the time shows the exact date and time). One semantics node per event ("Status updated by Ben Iyer, 2 hours ago, Open to In progress, completion 81 percent, remark ...").

| Kind | Dot icon / tone | Extra |
|---|---|---|
| created, edited, resubmitted, sent, reassigned | primary | edited: "field: old -> new" rows, three then "+N more" |
| status | violet | from pill (grey) -> to pill (header status tone, a check when final), completion "40% -> 81%" with a small arc, hours "2.5 h" |
| sent_for_approval, waiting, returned | violet | |
| approved, approved_final | green | |
| declined, deleted | red | |
| unknown op | neutral dot | the op words as title |

Sent: "from -> to" chips; more than one recipient collapses to the first name and "+N", a tap opens them all. Remarks and reasons: a soft block with a thin accent line, three lines then "Show more", selectable. Files: chips with a paperclip (three, then "+N"); nothing opens on a tap (no download is built). History carries names only, so no avatars are drawn. Empty: "No history yet"; error: the existing notice with "Try again"; loading: a small spinner, all inside the panel.

Tests: `test/tickets/ticket_history_timeline_test.dart` (every kind, pills, chips, completion, remark, files, edits, exact time, semantics, live event, states, fixed and fallback layouts, demo data) and goldens `test/tickets/goldens/ticket_detail_{short,long,fallback}.png`, `history_timeline.png`. Demo records 71 (every event kind, long remark, several recipients), 72 (40 events) and 73 (2 events) in `SeedTickets`.

### Autosend

`tstruct.submit` has no recipient. Recipients come from the form's auto-send rules, applied after saving (never the author, at most 50, several people can share a record: `claimants`) and from a later manual `record.send`. After the save is accepted the app tells "Saved" or "Waiting for approval" (`recordStatus: pending`); when the record is not pending it reads `record.actions` once and tells who holds it ("Sent to Ben." / "Shared with ..."). `SavedRecordNotice`, fed by `SubmissionRepository.saved`. There are **no drafts**: states are normal, pending, approved, rejected.

### Record conversation

Only when the form has `recordThread`: `record.thread {id}`. The card the conversation gets per event is a read-only form message (`structure:"record_history"`, fields Structure, Record, Event, By, To, From status, To status, Completion, Hours worked, Reason, Remarks). **Its `submissionId` is the history row, not the record**: it is never used to open anything (`RecordHistoryCard`); a tap opens the record named in the card's own "Record" field.

The form message no longer carries a `ticket` flag (RECORD_ACTIONS.md). A chat card is a record card by the web's rule (`RecordCardRule`): its form has a numeric `submissionId`, is not `readonly` and has no data-source `result`. That is all the card knows; the status line and the Send / Update status menu come from `record.actions`, read when the person opens the menu or the record (cached per record for 60 s, cleared by record events), never while cards are drawn or history loads. A record without a status simply has an empty menu. `record_history` cards stay read-only and open the record in their own "Record" field. The decision is logged once per card: `[records] card conv=... -> RECORD (rule: ...)` or `plain (rule: ...)`.

## Files (records only)

- Upload: `POST /api/sd/files?name=<name>`, the **raw bytes** as the body, `Content-Type` = the file's real mime, `Content-Length`, Bearer token (existing `FormFileRepository`, dio with progress). Answer `{ok, data:{file:{id,name,mime,size,by,ts}}}`.
- Limits: 10 MB per file (dev), any type, 60 uploads/hour per person, organisation quota. The size is checked before the upload with "That file is over 10 MB. Choose a smaller one." (`RecordLimits.maxFileBytes`). The picker (`AttachmentRepository`) still applies the chat's ~9.5 MB ceiling to what it picks, so a file between 9.5 and 10 MB is refused at the picker.
- Attach by id only, your own uploads, at most 10 per action. Errors shown as the server words them: "You can attach only files you uploaded yourself." / "That file is no longer there. Attach it again."
- Download: `GET /api/sd/files/<id>` and `/link` (not built; history shows file names).
- NOT the chat `/upload` (media and avatars, other limits).
- The picked temp copy is deleted after a good upload (`deleteAfter`); nothing else of a record file stays on the phone.

## Events and refresh

There is no "changed since" read. Events: `submissions_changed {id, tstruct, action: Send|Status update|Taken}` (to the new and old holder, the initiator and the actor), `ticket_assigned {id, tstruct, action, by}` (only the new holder, not the actor, never for `record.status`), `feed_item {notification, counts}` (the feed repository), `form_message`, `form_message_updated`, `task_assigned`, `task_updated`. Offline events are lost; `feed.list` keeps the notifications.

The repositories debounce 300 ms (`TicketRepository.scheduleRefresh`); the screens run one refresh at a time (an event during a refresh asks for one more round). After a reconnect and on app resume the lists and the open record are read again.

Feed item for a record: `{id, ts, category:"submissions", title:"<Form> #<id> is with you", message, actionType:"tickets", actionLabel:"Open ticket", ref:{submissionId, tstruct}, from}`, updated in place per record. No `chatId`, no deep link: a tap opens the record by `ref.submissionId` (this one IS the record id).

## Card menu (long press = the web's right click)

Source: web `MessageList.jsx` `menuItems` (about line 950) and `MessageMenu.jsx`; the Edit and History buttons are the card's action bar (`MessageList.jsx` about line 556); `utils/recordActions.js`. One list for the chat and the Work Space: `CardMenu.build` (`lib/features/tickets/models/card_menu.dart`, pure, truth-tabled in `test/tickets/card_menu_and_live_test.dart`) drawn by `RecordMenuRows` (`lib/features/tickets/widgets/record_menu_rows.dart`). The menu reads `record.actions` once when it opens (cached 60 s) and says "Loading…" in the record's place meanwhile.

| Web item (order) | Shown when (web) | Here |
|---|---|---|
| Reply with quote | always | Reply: direct chat or group, settled message |
| Forward | always | Forward: `Forward.canForward` |
| Copy text | the message has text | Copy: the card's one-line summary |
| Copy link | not for a card (`isCardMessage`) | not offered, as on the web |
| Edit (message text) | own text message | not for a card, as on the web |
| Save this message | `marks.canMark`: direct chat, group, general room; not a team chat | coming soon (notice "Coming soon") |
| Pin for everyone | as Save, not in the general room | coming soon |
| Mark as unread | as Save, not my own message | coming soon |
| Send, Update status (divider before) | the items of `record.actions`; a form without Send or status offers none; each with `enabled` and `why` | the same items; off rows show the server's `why` and do nothing |
| Edit / Fix and send again | card bar: mine, not received, not pending/approved, a declined one only when the approver allows it | here: the submission detail's gate (`FormCardData.canEdit` / `canFix`) |
| History | card bar: mine | opens the record screen (`/tickets/<id>`, its history) |
| Delete | any message of mine | here: the submission detail's gate (`FormCardData.canDelete`: mine, sent, not waiting for approval, not approved), confirm first, online only, deletes the submission |

Different from the web, on purpose: Edit, History and Delete are menu rows (the web has them as buttons or as a message delete); Delete removes the submission, as on the submission detail screen. A record_history card is read-only: no record rows, no Edit or Delete; Reply, Forward and Copy only; a tap opens the record named in its `Record` field.

## Card actions without a tap (chat and Work Space)

`RecordCardActions` (`lib/features/tickets/widgets/record_card_actions.dart`) is the one component under a record card, in a chat (`conversation_view.dart`) and in My Work Space (`workspace_view.dart`, own and received `rec-<id>` cards): the status block and the `AppActionBar` (one button per enabled item). Drawing reads nothing. While a card is built and its screen is in front (`TickerMode`) it tells the repository `loadActions([id])`; when it is disposed or covered, `releaseActions([id])`. The bar fades in over 150 ms with `AnimatedSize`; nothing shows while loading.

**Filtering (what the server returned, nothing else).** `RecordState.parse` keeps only `send` and `status` (unknown ids and malformed entries are dropped); `offered` is the enabled ones. Send is never assumed, status is never assumed. A disabled item is no button; the long-press menu keeps listing it with the server's `why`. Empty or missing `items`, a `not_found` reply (known BE gap) or an unreadable reply: no bar, no error on the card, a `[records]` log line, the answer is kept 60 s so it is not repeated.

**Queue** (`RecordActionsQueue`, owned by `TicketRepository`): one `record.actions` at a time, at least 300 ms after the last one ended, at most 8 starts in any 10 s (server limit 30 per 10 s per connection), newest record id first, only records on screen, none while the last read is under 60 s old, de-duplicated (a count per record for a record shown twice), paused in the background or when the socket is offline, resumed on resume/online. `rate_limited`, `busy` and `timeout` retry with 1, 2, 4, 8, 16 s backoff (5 tries), no UI. A record event, a reconnect or a resume marks the record stale (bar hidden); a stale record on screen is read again through the same queue, one off screen only loses its cache. Menu opens (`ensureMenu`) and the record screen read directly (a person's tap) and refresh the same cache. `form_message_updated` still marks nothing stale. Replacing the internals with a batch command touches `TicketRepository._fetchForCard` only.

## Live card

What the web does: `useRecordState` reads `record.actions` for a card (at once in a record's own conversation or when the card shows activity, else when the menu opens), reads it again on every record event (`isRecordChange`: `task_*`, `ticket_*`, `record_*`, `submission(s)_*`, `resync`) and shows `RecordStatus`: the status chip, "With @holder" or "Shared with @a, @b", the completion bar, the last update (who, when, the remarks) and the files. No hours on the card. It is a read per mounted card per event; the phone does not do that (30 commands per 10 s).

Here: `TicketRepository.liveOf(id)` is one observable per record (`RecordLive`); `RecordStatusBlock` draws it under the fields (`RecordCardActions`), so only the card of the changed record rebuilds. It is filled, with no read of its own, by:

| Source | Fields it sets |
|---|---|
| `record.actions` (menu or record opened, after my action) | status, holder, initiator, claimants, completion, last update (by, ts, remarks), final; clears the stale mark |
| `records.mine` pages (the workspace and lists already read them) | status, holder, initiator, completion |
| my own `record.status` / `record.send` answer | status, holder, completion, final, "last by me"; clears shared |
| `ticket_assigned {id, tstruct, action, by}` | holder = me (only the new holder gets it), the action; stale |
| `submissions_changed {id, tstruct, action}` | the action ("Send", "Status update", "Taken"); stale |
| `form_message`, `form_message_updated {conversation, id, from, form, text}` | nothing of the record: the message repository rewrites the card's fields in place; the lists read again (debounced 300 ms) |
| reconnect, app resume | every known card marked stale |

**On a server without #822 no event carries status, holder (except `ticket_assigned` to me), completion or the last update** (dev has `data.record` since 16 Nov 2026, in no release; we do not read it yet), so a change made by someone else shows on the card only as "stale": the action bar goes (its buttons may be wrong) and what was known stays; the next menu or record open reads `record.actions` (0 to 1 command, cached 60 s). A message in history carries no status either, so a card read from `/history` shows nothing until a read, a list page or an action fills it in this session (nothing is stored on the phone). Open question for the BE: add `status`, `holder` and `completion` to `submissions_changed` (one sentence: it would let a card update with no read at all).

Cost: an event touches one map entry and one observable; a burst of 20 events is 0 commands and one list refresh (300 ms debounce). Drawing, scrolling and history replay make no command (`cardReads` stays 0).

Demo (`DEMO_MODE`): the fake record server (`SeedTickets`) emits `submissions_changed` for my own Send and Update status; 12 s after start `sam` moves record 31 to the next status (`submissions_changed`), 24 s after start `rhea` sends me a new record (`ticket_assigned`, then `submissions_changed`).

## Edit, resubmit, delete

- Edit (`submissions.update`): existing form edit screen through the outbox, one `cid` per save. It replaces ALL values (the full set is sent), cannot change the status field ("The status changes through Update status only."), is refused while pending/approved (`submission_locked`), allowed when rejected. The author can edit; so can a person with an edit rule (holder and administrators cannot unless they have it). **No optimistic locking: two editors can overwrite each other.** The "may overwrite newer changes" guard is not built.
- Resubmit (`submission.resubmit`): existing, through the outbox; author only and only if the approver allows.
- Delete (`submissions.delete`): built on the submission detail screen (16 Nov 2026): shown by the web's rule (mine, sent, not pending, not approved), confirm first, online only (never queued), `submission_locked` / `forbidden` / `not_found` shown in plain words, list and workspace read again; history rows stay. The form owner who is not the author does not get the button (the web gives it to the author only). The unverified "updated records cannot be deleted" hint is ignored.

## Creating a record from `#` (`#create` / `#tstruct-add <name>`)
One `tstruct.user.open {name, mode:"add"}` names the form (caption or name), then the form screen saves it with `tstruct.user.submit` / `tstruct.submit` (name, values, one fresh `cid` per attempt; no `ref`, no `meta`). It is an ordinary new submission: the record flow takes over (`SavedRecordNotice`: "Saved", then who holds it from `record.actions`). `chat` is sent **only** in a shared thread (`care-*` / `rec-*` group: `chat:"group:<name>"`, no box, the server posts the card); in a DM, host, global, workspace and team group (team row: pending BE doc) no `chat` is sent, nothing is written into the chat and the record shows in My Work Space, which the app opens after the save from a DM or team group (`FormChatRule`). Never `dm:`. See `commands.md`.

## Not available

Drafts (no save-without-send), a delta/"since" read, edit locking, a record-task link (tasks and records are unrelated), cancel, priority and due date as record properties (they can be form fields), `records.history` (administrators, organisation-wide), print, post, push. Planned by the BE, not built.

## Testing

`test/tickets/`: models from the captured replies, every command's request shape, error mapping by code, `requestId` reuse, `repeated`/`duplicate`, paging with short pages, no Raised total, debounced events, the history card, the notification mapper, upload request shape, the status and send sheets, a real `GetMaterialApp` navigation test, goldens, and a source scan (no removed names, no typed `Get.toNamed<T>`).

DEMO_MODE and `/debug/tickets` run on `SeedTickets` (in-memory server, `answer(cmd, args)`): with me (open, in progress, one that needs a comment, 70 sample rows paged 60 at a time), raised (with someone else, final, waiting for approval), involved; `record.actions` with enabled/disabled + `why`; history of the ops the demo produces (created, sent, status); stale (`nextError`), busy, lost answer (`isLosingNextAnswer`, a retry with the same `requestId` returns `repeated:true`); `record.send` via every `via`; `record.people` search. File upload progress and the task list are served by the existing demo (`SeedTasks`) and the real `FormFileRepository` (no demo file server).

## Open items for the BE

1. Seed records on dev (it has none): at least one record per status of a form with a status, one with `commentsRequired`/`hoursRequired`/`filesRequired`, one waiting for approval, one final, one shared by auto-send (`claimants`), one with a record thread; users for creator, holder, no-access and administrator.
2. JSON examples for `tstruct.submit` and `submissions.update` (none in `tools/postman/examples.json`).
3. Docs corrections: `RECORD_ACTIONS.md` HTTP route; `TASKS_AND_ACTIONS_FOR_MOBILE.md` `task.fetch` and `records.mine` options.
4. ~~`records.mine as`: `team`?~~ Answered by the Smart View document revision 2: `team` exists (see the corrections table). Not captured with data yet.
5. ~~The form message has no `ticket` flag now.~~ Answered by `MOBILE_RECORDS_FULL.md` (question 5): the rule is `submissionId` + not read-only + no result; the status comes from `record.actions`.
6. The shape of `record.actions.lastUpdate` and `files` (kept raw).
7. How can the app know `isAdmin` before opening a record (to offer `as:"all"`)?
8. The `ticket_assigned` `action` values (the old sample said `Raised`).
9. PR #782 changed `/setavatar`, `/removeavatar`, `/setstatus` (now ack/error with `cmd` and `code`), the upload rate limit (per person) and added `retryAfter` to the password-login 429: the avatar and login code was not touched here.
