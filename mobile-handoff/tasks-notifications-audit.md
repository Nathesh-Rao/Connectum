# Notifications, To-dos, approvals and tickets: audit

Date: 2026-11-05. Read: `reference/notification/*`, `reference/task-and-action/TASKS_AND_ACTIONS_FOR_MOBILE.md`, `reference/tickets/*` (both documents and the Postman collection), `mobile-handoff/notifications-audit.md`, `push-readiness.md`, and the code of the four features end to end. Nothing was run on a phone or on the real server.

How to read "verified": **code** = I read the line (file:line); **test** = a test in `test/` proves it; **NOT** = nobody has checked it, it is in the manual plan (`tasks-notifications-test-plan.md`).

Summary: 28 call/event rows, **0 wrong, 4 partial** (was 5; `feed.resolve {all}` fixed). 3 small fixes made. 14 gaps for a decision (G-01 to G-14) and 9 questions for the backend (B-01 to B-09). No blockers. Fix round after this audit: G-01, G-02, G-05, G-12 fixed (see "Fix round" below). The two majors (G-01, G-02) are done; B-04 and B-06 could turn major depending on the answer.

---

## A. Contract table

Docs: N = NOTIFICATIONS_FOR_MOBILE, T = TASKS_AND_ACTIONS_FOR_MOBILE, K = TICKETS_AND_TASKS_MOBILE, P = Postman. Line numbers are in `lib/`.

| Name | Params in the docs | What the code sends | Response fields we read | Error codes handled | Match | Action |
|---|---|---|---|---|---|---|
| `feed.list` | `priority all/high/medium/low/resolved, category?, unreadOnly?, before?, beforeId?, limit ≤200 (50)` (N) | `priority, limit, unreadOnly (only if true), before=ts, beforeId=id` `data/repositories/feed_repository.dart:173` ; first read 200, pages 50 (`:38-39`) | `counts, hasMore, notifications[]` (P) `:179-185`; item fields `features/notifications/models/feed_item.dart:136` | any `SocketCallError`: first read -> error/offline state; later -> rows kept (`feed_repository.dart:160`); paging/filter -> AppNotices with server text (`notifications_controller.dart:115,127`) | yes | none. Doc gap: does `priority:all` include resolved? The app does not depend on it (merge by id). |
| `feed.summary` | none | `{}` `:145` | `high, medium, low, resolved, unread, total` `:146` | as above | yes | none |
| `feed.read` | `ids:[…] \| all:true, read?:false` | `ids` (+`read:false`) `:315`; `all:true` `:337` | `counts` `:319` | rollback on any error + rethrow (`:401-415`); server text shown | yes | none. Never sent with empty `ids` (P: "ids must be a non-empty list"). |
| `feed.resolve` | `{id} \| {all:true}` | `{id}`, and `{all:true}` since the fix round | `notification, counts` `:356-358` | rollback + text | yes | "Mark all resolved" added (G-02 fixed) |
| `feed.dismiss` | `{id}` | `{id}` `:366` | `counts` | rollback + text; `not_found` now also schedules a re-read (fixed F2) | yes | none |
| `feed.clear` | none (removes resolved) | `{}` `:380` | `counts` | rollback + text | yes | none |
| `task.create` | `title, description?, due?, priority?, assignee?` (T) | same; `assignee` left out for "me"; `due` = 23:59:59 of the chosen day; no `cid`/`requestId` `data/repositories/task_repository.dart:140`, `features/tasks/models/task_form_rules.dart:53` | `{task}` (or bare view) `:196` | `rate_limited, invalid, forbidden, timeout/disconnected, not_connected` via `CallProblem` (`data/socket/call_problem.dart`); no automatic retry (`tasks_controller.dart:285`) | yes | none |
| `task.get` | `id` (T lists `task.fetch` by mistake: the real action is `task.get`) | `task.get {id}` `:192` | `{task}` | `not_found` -> "no longer available" (`tasks_controller.dart:107`) | yes (doc wrong, code right) | tell the doc owner |
| `task.list` | `as assigned/created/all, status active/<s>/all, limit ≤100 (50), offset` | `as, status, limit:50, offset (if >0)` `:110` | `tasks, total, hasMore` `models/task.dart:115` | quiet on refresh, notice+Retry on paging (`tasks_controller.dart:164,191`) | yes | The app never sends `as:all` (two tabs) |
| `task.update` | `id` + fields (creator any; assignee status only) | `{id, status}` for status moves; `{id, only the changed fields}` for edit `task_form_rules.dart:68` | `{task}` | `forbidden/not_found/invalid/rate_limited/…` -> verbatim; `forbidden`/`stale` re-read the task with `task.get`; `not_found` removes the row (`:307-321`) | yes | A due date cannot be cleared (null is ignored): G-13 |
| `task.send` | `id, to` | `{id, to: username}` `:183` | `{task}` | same | yes | none |
| `req.list` | `status (pending), limit ≤200, offset` | `status, limit:50, offset` `approval_repository.dart:103` | `requests, total, hasMore`; per request `direction, canRespond, type, data.*, status, resolvedBy*` (P) `models/approval.dart` | quiet on refresh | yes | none |
| `req.respond` | `id (int), action accept/reject/return/ignore, reason?, comment?, allowResubmit?` | same names; `reason`/`comment` only when non-empty; reason required client-side for reject/return `approval_rules.dart:32`; no `cid` `approval_repository.dart:139` | `{request}` | `already_resolved, forbidden, not_found, invalid, rate_limited, busy` -> verbatim; not replayed on timeout (`approvals_controller.dart:195-216`) | yes | none |
| `status.mine` | `as with/raised, limit 1-200 (100), offset` | `as, limit:100, offset (if >0)` `ticket_repository.dart:127` | `submissions, structures, total, hasMore`; `total` -> badge `:137` | quiet on refresh, notice+Retry on "Show more" | yes | `raised` has no paging; the app only pages if `hasMore` |
| `status.get` | `id` | `{id}` `:149` | `submission, structures, isAdmin, inPool` | `not_found` -> gone; other -> error with retry | yes | none |
| `status.history` | `id` | `{id}` `:164` | `history[]` `{by, ts, values{Action,FromStatus,ToStatus,Percent,Remarks,Reason,Files}}` | history error shown separately | yes | none |
| `status.update` | `id, action, expected{status,assignee}, sendTo?, reason?, remarks?, percent?, files?, requestId?` | exactly these, only the inputs the action asks for (`features/tickets/models/ticket_input.dart:62`); `requestId` = UUID kept for retries (`ticket_detail_controller.dart:177`) | `status, assignee, completion, record, ticket, repeated` `models/ticket.dart:504` | `stale, forbidden, not_found, invalid, duplicate, busy, rate_limited` -> `TicketOutcome` (`ticket_input.dart:117`); verbatim text | yes | the docs say a repeat can also come as error `duplicate`; both treated as success |
| event `feed_item` | `{notification, counts}` | `feed_repository.dart:224` | item, counts | no counts or no id -> re-read | yes | none |
| event `feed_removed` | `{ids, counts}` | `:234` | ids, counts | – | yes | none |
| event `feed_changed` | `{ids, read, counts}` | `:239` (`read != false` = read) | ids, read, counts | – | yes | none |
| event `request_created` | "request view" (N §4; P folder 6) | `approval_repository.dart:77`: reads `data.request` or `data` itself; direction/canRespond worked out for the viewer when missing (`models/approval.dart:130`) | request | – | **partial** | payload shape not shown in the docs: BE question B-03 |
| event `request_resolved` | same | same; the card stays and loses its buttons (`approval_reducer.dart:36`) | request | – | **partial** | B-03 |
| event `task_assigned` / `task_updated` | `{task}` | `task_repository.dart:86`; row updated in place, lists re-read after 150 ms; in-app line "You have a new task." / "A task was updated." (`feed_repository.dart:282`) | `task` | – | yes | none |
| event `ticket_assigned` | `{id, tstruct, action, by}` | `ticket_repository.dart:107`, `models/ticket.dart:535`; lists re-read, open ticket re-read | all four | – | yes | none |
| event `submissions_changed` | (K) | only `TicketRepository` re-reads (`:110`) | – | – | yes | none |
| event `submission_approved/rejected/notice` | `{submissionId, tstruct, status, reason, allowResubmit}` | `feed_repository.dart:45-49`: only a feed re-read, no in-app line, no routing | – | – | **partial** | The feed item that goes with it carries the words and `ref.submissionId`; tap opens a detail sheet (G-09). Does anything refresh the Submissions list from these events? Not checked here. |
| event `broadcast` | `{text,…}` | `feed_repository.dart:294`: in-app line "Announcement: …" (≤120) when foreground | text | – | **partial** | Background: nothing. N §2 row 12 says "not a chat message; event `broadcast`" and does not say a feed item exists. B-06 |
| event `session_replaced` / `session_expired` (+ `connection_superseded`, `disconnected`) | sign-out flows | `data/socket/socket_service.dart:242-251`: pending calls fail with `disconnected`; state moves to the matching sign-out state | – | – | yes | Sign-out rules are in `sessions.md`, not re-audited here |

**Contract mismatches: 0 wrong, 4 partial** (`request_created`, `request_resolved`, `submission_*`, `broadcast`). Plus one error in the docs (`task.fetch`).

Page limits checked against the docs: feed 200/50 (≤200 ok), tasks 50 (≤100 ok), requests 50 (≤200 ok), tickets 100 (≤200 ok), local cap 300 feed items (`feed_item.dart:4`).

---

## B. Behaviour checks

### 1. Reconnect and resume re-read
- Feed: summary + `feed.list {priority:all, limit:200}` replace the list (`feed_repository.dart:139-165`). **test** `feed_repository_test` ("summary, then the latest 200 items…", "replace the list").
- Triggers: socket online `:87`, app resume `:105`, events `:246`, all through `scheduleRefresh` (150 ms). **test**: burst of 5 triggers = 1 read; resume = 1 read; pause = none; offline = no call.
- task.list (both tabs) / req.list / status.mine: each repository fires `refreshes` on online + resume + its events (`task_repository.dart:58,75,95`; `approval_repository.dart:49,65,90`; `ticket_repository.dart:79,94,116`) and the open screen re-reads. **test** `tasks_controller_test` ("a task event reads both lists once, after 150 ms"). The "socket online" source itself is **code** only (the stream is private to the socket).
- Only screens that are open re-read; closed screens read on open. Badge `withTotal` (tickets) is updated only when the Tickets pane has read once: **NOT** verified that the badge is right right after a cold start without opening the pane (it is 0 until then). G-14.
- No double loops: `refresh()` sends no events; `request_*` schedules the feed refresh and its own refresh, both coalesced (`approval_repository.dart:89-90`). **code**. In-flight refresh is shared (`_refreshing ??=`, `feed_repository.dart:136`), **test** "two refreshes at once make one pair of calls". Side effect: an event that arrives while a read is in flight is merged into that read and may not be reflected (G-10).
- Reconnect while a write is in flight: the socket fails all pending calls with `disconnected` (`socket_service.dart:301`). Task/ticket/approval writes -> "unknown outcome": no retry offered for tasks/approvals, ticket Retry reuses the request id, lists re-read (`call_problem.dart:46`, **test** `call_problem_table_test`, `tasks_controller_test` "a lost answer is not sent again", `ticket_detail_controller_test` "a lost answer"). Feed writes -> rolled back to the snapshot (`feed_repository.dart:401`); the reconnect read then shows the real state. If a re-read finishes first, the rollback puts the older snapshot back until the next read (G-10). **code**.

### 2. Optimistic updates and rollbacks
- Feed read/unread/resolve/dismiss/clear/mark-all: instant change, rollback + rethrow on error. **test** `feed_repository_test` (6 cases, including `rate_limited` text kept and `not_connected`).
- No stuck spinner: `isBusy`/`isSubmitting` reset in `finally` in tasks (`tasks_controller.dart:302`), approvals (`:214`), ticket detail (`:211`). **test** for all three controllers.
- Double tap: task create **test**; approval **test**; ticket **test**; feed `setRead` has no guard but the calls are idempotent. Tasks: second `_write` returns `false` silently while busy (`:291`), no message. OK.
- Back-and-forth (read, unread, read quickly): each call rolls back to its own snapshot (`_optimistic`), so two fast calls with one failing can restore a state the other already changed (G-10). **NOT** verified on a phone.
- Task status: row changes only after the server answers (not optimistic); on error the server text. Approval action: card changes after the answer. **code**.

### 3. Idempotency
- `status.update`: `requestId` per form; same id on retry after `timeout`/`disconnected`/`busy`/`rate_limited`/`not_connected`; new id after `stale`/`forbidden`/`invalid`/success; a new sheet = a new id (`ticket_detail_controller.dart:177-199`, `ticket_input.dart:117-140`). **test** `ticket_detail_controller_test` (6 cases) and `ticket_input_test`.
- Retry after a lost answer where the first one did go through: the payload's `expected` is rebuilt from the screen state; if the reload already showed the new status the same `requestId` with a new `expected` is sent. The docs list the checks in order: requestId repeat is answered "first result" but they do not say whether it is tested before `stale`. **NOT** verified: B-04, manual case K-12.
- `task.create`, `task.update`, `task.send`, `req.respond`: no id, never replayed. **test** (`tasks_controller_test`, `approvals_controller_test`: exactly one call after a timeout). Retry button offered only for `not_connected`, `rate_limited`, `busy` (`call_problem.dart:32`). Exposure: `busy`/`rate_limited` could in theory be returned after the server applied the action. Not seen in the docs.

### 4. Error mapping
All 11 codes of the brief plus `bad_request` go through `CallProblem` (text verbatim, kind, retry, refresh): `rate_limited, busy, stale, forbidden, invalid, not_found, already_resolved, duplicate, in_progress, session_replaced, session_expired`. **test** `call_problem_table_test` (every code, read and write). Follow-ups:
- `rate_limited`/`busy`: text + Retry (tasks, approvals, tickets). Typed text is kept (task form stays open on `false`; ticket form kept).
- `stale`: text, ticket re-read, form kept, new id. `forbidden`: text, re-read. `not_found`: row removed (tasks, approvals, ticket "gone"). `already_resolved`: text, list re-read. `invalid`: text, form kept.
- `duplicate`: success (tickets). `in_progress`: only the `cid` actions (not used by these features) -> shown as `other` with the text.
- `session_replaced/expired` never reach screens as call errors: the socket drops and the app signs out (`socket_service.dart:242`).
- Feed errors do not use `CallProblem`: `NotificationsController._say` shows `e.message` verbatim or "Couldn't do that. Try again." for gaps (`notifications_controller.dart:175`). No Retry button (the tile stays as it was). **code**.
- Shown via `AppNotices` everywhere. **code** (grep: no `Get.snackbar` in these features).

### 5. Encryption and logging
- E2E feed items: envelope kept whole (`feed_item.dart:151`), opened on the device by `FeedRepository.readableText` (`:422`), cached in memory per session; fallback "Encrypted message" in tile and detail, "New message" in local notifications. **test** (opened once, cannot/pending -> null, no chat -> null, cache cleared on session change).
- Tasks, tickets, approvals, API messages are plain: no `e2e` handling there. **code**.
- Logging: no `print`/`debugPrint` in these features prints text, envelopes or tokens; the only prints are `Local notifications unavailable: <type>` and `Local notification failed: <type>` (`local_notification_service.dart:87,331`). The in-memory `SocketService.eventLog` (20 lines, shown only in `/debug/socket`) keeps `Redact.event` of each event: `text` is hidden, other strings cut to 40 chars, so a feed `title`/`message` or the start of an `e2e1:` envelope can appear there (`socket_service.dart:203`, `redact.dart:34`). Not written to disk. G-12. `/debug/notifications` prints nothing (grep).
- Push token: never logged; stored in secure storage and cleared on session change (`push_token_registry.dart`). **code**.

### 6. Local notifications
Rules (`data/notifications/local_notification_rules.dart:17-45`), **test** `local_notification_rules_test` + `local_notification_gaps_test`:
| Rule | Result | Verified |
|---|---|---|
| read or resolved item | none | test |
| from me (any case) | none | test |
| muted conversation / open conversation | none | test |
| foreground and background | the same: the `feed_item` event is the only trigger and posts a system notification (heads-up); the in-app notices of `task_assigned`, `task_updated`, `request_created`, `ticket_assigned` and `broadcast` are gone (those events only re-read the lists). One item id never shows twice for the same `ts` and `count` | test |
| low severity | system notification only for a group message for a group message (`open_chat`, chat id `room-…`) while the setting "Notify for group messages" is on (default) | test |
| e2e item | same rules, text opened on the device; if unreadable "New message" without body | test (rules), code (text) |
| coalescing | notification id = hash of the item id, so a coalesced item replaces its banner | test (stable id) |
| clear on read/resolve/dismiss/remove | `onGone` -> cancel + group summary update (`:377`); a re-read sweeps the rest (`:388`) | test (events emit `onGone`), NOT (system tray) |
| sign-out / org switch | `cancelAll` when the session changes (`:96`) | code |
| killed app | cannot be woken (no push). Documented in the service header | n/a |
| tap warm start | `onDidReceiveNotificationResponse` -> `NotificationRouter.handlePayload` (`:82,412`) | code, NOT on phone |
| tap cold start | `getNotificationAppLaunchDetails` (`:98`); target kept until the home is up and signed in (`notification_router.dart:223-239`) | code, NOT on phone |
| signed-out target | kept in `_pending` (single slot) | code. Survives a change of person: G-05 |
| permission | explainer once after sign-in (`home_shell_controller.dart:100`), system prompt only on "Allow"; state re-read on resume (`:117`); "denied/permanently denied" -> row with "Open settings" once `wasAsked` (`notifications_controller.dart:75-80`); Android 13+ declared `POST_NOTIFICATIONS` in the manifest | code, NOT on phone |
Notes: `inactive` counts as background (G-11). A cold-start tap cannot mark the item read because the socket is not online yet (G-06). Group messages are `low`: they notify in the background only while the setting is on (G-01, fixed). Security notices go to the `security` channel only when `category == 'security'`, which the docs do not state (G-08/B-05).

### 7. NotificationRouter (`notification_router.dart:127-176`)
**test** `notification_router_test` (existing, 18 cases) covers: `open_chat` (dm, group, no chat -> detail), `open_message` (with/without message id, no chat), `approvals`, `tickets` (+ref -> ticket, no ref -> list), `submissions` (+ref -> submission), `tasks`/`task`, `none`, missing, `admin_console`, `about_me`, `axpert`, `smart_prompt`, unknown -> detail, push payload. To-do items (no ref, no actionType, category `system`, icon `task_alt`) resolve to `none` and are NOT detected by category or icon (`:169`). They show a detail sheet from the tile; the in-app line from `task_assigned` opens the task by id. Gaps: `tickets` when the Tasks screen is already open does nothing (G-07); `submissions` with a ref opens the detail sheet only (G-09).

### 8. Permissions and roles
- To-do: edit/cancel/send/reopen only for the creator, status moves for creator or assignee, finished task not editable (`features/tasks/models/task_actions.dart:36-47`). **test** `task_actions_test` (7). Whether an assignee may reopen a finished task is not in the docs; the app allows creator only (B-07).
- Approvals: buttons only when `canRespond && pending`; Return only for a submission (`approval_rules.dart:21-29`). **test**. Admin sees requests not sent to them via `canRespond` (`inReview`).
- Tickets: per `who`/`from`/final (`ticket_actions.dart:10-47`); waiting for approval and final -> no actions; admin actions hidden until `status.get` says `isAdmin`; pool ("Take it") uses `inPool` when known, else a guess from the pool field (ASSUMPTION documented in the code). **test** `ticket_actions_test` (incl. pool group). The server decides again.

### 9. Lists
- Paging with offset/`hasMore` (tasks, approvals, tickets) and `before/beforeId` (feed) **test** (feed, tasks); sorting as the server returns (tasks re-sorted locally with the same rule, `task_reducer.dart:9`; feed newest first by `ts`; tickets/approvals in server order, approvals re-sorted newest first). Caps: feed 300 **test**.
- Filters: feed chips + unread only (client filter, server read once per filter), tasks status filter, approvals status filter, tickets by form (client).
- Empty/error/offline states through `AppStateView` in all four screens (**code**; images **NOT** verified).
- Badges: bell = `feed.summary.unread` (`chats_view.dart:155`), updated by the three events and by actions **test**; tickets "With me" total = `status.mine.total` (updated on every read); **approvals pending: no badge exists** (G-03).

### 10. Two-device sync
`feed_changed` / `feed_removed` from another device update the tiles and counts and cancel the local notification (`feed_repository.dart:234-244`, `local_notification_service.dart:94`). **test** (repository), NOT on a phone. Read on the web clears the banner on the phone only while the socket is alive; otherwise the next re-read sweeps (`_sweepRead`).

### 11. Session rules
- One session per kind and `session_replaced`: `socket_service.dart:242`, rows/outbox wipe is in `sessions.md` (not re-audited).
- Sign-out / org switch (a kept notification target now belongs to the person who was signed in when it was kept: G-05 fixed): feed list, counts, e2e text cache reset (`feed_repository.dart:109`) **test**; pending local notifications cancelled (`local_notification_service.dart:96`); push token cleared (`push_token_registry.dart:71`); **fixed F1**: `TicketRepository` kept `_known`, `_names`, `withTotal` across persons. **test**.
- Tasks, approvals: nothing is stored on the phone (no drafts, no outbox); screen controllers are disposed by `Get.offAllNamed`. Router `_pending` is not cleared (G-05).

### 12. Time
Overdue uses the device clock against the server's `due` (`models/task.dart:49`); labels use the local calendar day (`task_due_label.dart`); the due value sent is 23:59:59 of the local day, so a clock a few minutes off cannot make "today" past (`task_form_rules.dart:37`); the picker's first day is today (`task_form_controller.dart:62`, `task_form_sheet.dart:53`). **test** `time_handling_test` (clock 5 minutes fast/slow, midnight crossing, other year, picker). A different device time zone than the server: only the calendar day can differ; **NOT** verified on a phone (X-04).

### 13. UI states
Loading: `AppStateView` default / `AppSpinner` for paging (`notifications_view.dart:251`). Sheets: `AppBottomSheet` enableDrag + isDismissible, text scale clamped to 1.3 (`app_bottom_sheet.dart:67-82`). Tasks screen uses `NeverScrollableScrollPhysics` on a tab view (`tasks_view.dart:87`). Scroll-in-scroll, long names/titles, 1.3 text scale on the tiles: **NOT** verified (cases X-05, X-06).

### 14. Debug leftovers (this feature set)
| Item | In CLAUDE.md "Before release"? |
|---|---|
| `/debug/tasks`, `lib/features/debug_tasks/`, `lib/core/debug/seed_tasks.dart`, `SeedTasks` branches in task/approval repos and `task_people_controller` | yes |
| `/debug/tickets`, `lib/features/debug_tickets/`, `seed_tickets.dart`, `SeedTickets` branches, `assets/debug/tickets/` | yes |
| `/debug/notifications`, `lib/features/debug_notifications/`, `/debug/notifications` | **no -> added now (F3)** |
| `TaskRepository.me`/`ApprovalRepository.me`/`TicketRepository.me` fall back to the seed user when no one is signed in | covered by "the `SeedTasks`/`SeedTickets` branches" |
| `/debug/forms`, `/debug/formlogic` (other feature) | **no**, outside this audit: `app_routes.dart:30-31` |
| `test/support/` and the tests read `assets/debug/tickets/` and the Postman file: they are test-only; the asset folder goes with the release cleanup, the tests that use it then need the fixtures moved to `test/` |

---

## C. Defects and gaps

### Fixed now (3, each a few lines, tests pass)
| # | Sev | Where | Problem | Fix |
|---|---|---|---|---|
| F1 | minor | `data/repositories/ticket_repository.dart:75-90` | `_known` (last tickets read), `_names` and the badge `withTotal` stayed when another person or organisation signed in. Ticket detail pre-fills from `_known[id]`, so ticket 38 of the previous account could flash in the next one; the badge showed the old number. | `ever(_store.current, …)` clears them. **test** `ticket_detail_controller_test` "does not leak". |
| F2 | minor | `features/notifications/notifications_controller.dart:167` | read/resolve/dismiss on a tile that was already removed on another device: rollback brought the dead tile back and it stayed until the next re-read; every tap gave "No such notification." | on `not_found` also `feed.scheduleRefresh()`. |
| F3 | minor | `CLAUDE.md` Before release | `/debug/notifications` and `lib/features/debug_notifications/` were not in the list. | added. |

### Needs a decision (product/app)
| # | Sev | Where | What goes wrong | Proposal |
|---|---|---|---|---|
| G-01 | **major** | `local_notification_rules.dart:39-43` | Group messages are `low` (N §2 row 2). Low is never shown, in the foreground or the background (`allowLow` is never true). With the app in the background and the socket alive, a group message gives no notification at all. Also API messages with severity low. (N open question 3.) | Decide: group messages notify (maybe quieter channel), or stay silent by design. If notify: pass `allowLow` per category. |
| G-02 | **major** | `notifications_view.dart:128` | No "Mark all resolved" (`feed.resolve {all:true}`); N §3 lists it as a tile-list button. With 50+ items the only bulk action is "Mark all read". | Add menu entry (3 lines + the repository call), or accept the difference. |
| G-03 | minor | `chats_view.dart:155`, `approvals_controller.dart:72` | No badge for pending approvals anywhere (`reviewCount` is unused); the bell counts only the feed. A request is reachable by its feed tile (`approvals`) and from Workspace. | Decide where the number lives. |
| G-04 | minor | `feed_repository.dart` / `feed_reducer.dart:70` | Everything of a muted chat is hidden and silent, including a mention (`mention:<g>:<id>`) of me in a muted group. The web does the same (N §6), but the product may want mentions through. | Decide. |
| G-05 | minor | `notification_router.dart:121-127` | `_pending` is one slot, never cleared on sign-out or when another person signs in: a tap left by person A opens A's chat id in B's session. "Signed-out target kept" is required, but for the same person only. | Clear `_pending` when `userId`/`orgId` differ from the one stored with it (about 6 lines). |
| G-06 | minor | `local_notification_service.dart:412-420` | A tap from a killed app calls `feed.setRead` before the socket is online: `not_connected` is swallowed and the item stays unread (badge stays). | Remember the id and mark read on the first `onOnline`. |
| G-07 | minor | `notification_router.dart:263` | `tickets` destination while the Tasks screen is already open does nothing; the person stays on To-dos. | Switch the section when already on `/tasks`. |
| G-09 | minor | `notification_router.dart:269-278` | `submissions` item with `ref.submissionId` opens a detail sheet only (known TODO). | Open the submission when its screen takes a link. |
| G-10 | minor | `feed_repository.dart:136,401` | (a) an event arriving during an in-flight read is folded into it and may be missing; (b) a rollback restores a snapshot that may be older than a read that finished meanwhile. | Mark "dirty" and re-run once; rollback only the touched ids. Small but touches the core of the feed: not done in an audit. |
| G-11 | minor | `local_notification_service.dart:67,116` | `inactive` (shade pulled down, permission dialog, incoming call) counts as background: a system notification can appear while the app is visible. | Treat `inactive` as foreground. |
| G-12 | minor | `socket_service.dart:203,383` | `eventLog` keeps 40 characters of feed titles/messages and the start of an envelope in memory; not guarded by `kDebugMode`. Only shown in `/debug/socket`. | Guard with `kDebugMode` or hide `title`/`message` in `Redact`. |
| G-08 | minor | `local_notification_rules.dart:50` | Security notices (#13-15) go to the high-importance `security` channel only when `category == 'security'`; the docs do not say what category they carry. Otherwise they land in `system` (low importance, easy to miss). | Needs B-05. |
| G-13 | minor | `models/task.dart` + `task_form_rules.dart:82` | A due date cannot be removed on edit (null ignored). | Needs B-07 (does `due: null` clear?). |
| G-14 | minor | `ticket_repository.dart:137` | Tickets badge is 0 until the Tickets pane has read once. | Read `status.mine` (limit 1) on connect, or accept. |

### Fix round (2026-11-05)
| # | Status | What was done / why not |
|---|---|---|
| G-01 | **fixed** (client setting) | Switch "Notify for group messages" on the Notifications screen, default ON, stored in `SessionStore` per org + person (`notif.groups.<org>.<user>`). `LocalNotificationRules.decide` takes `shouldNotifyGroups` (replaces the unused `allowLow`): a low group message (`open_chat`, chat id starting `room-`) notifies in the background unless muted, mine or open. OFF: only mentions, replies and other medium/high items. DMs and the foreground are unchanged. Tests: `local_notification_rules_test`, `local_notification_gaps_test`. Plan: N-03, L-12, L-12a to L-12d. |
| G-02 | **fixed** | Menu entry "Mark all resolved" -> `FeedRepository.resolveAll` (`feed.resolve {all:true}`), optimistic with rollback like the other bulk actions; no confirmation sheet, because "Mark all read" and "Clear resolved" have none. Tests: 2 in `feed_repository_test`. Plan: N-23. |
| G-03 | not fixed | Product decision: where the number of pending approvals lives. |
| G-04 | not fixed | Product decision (mentions in muted groups). |
| G-05 | **fixed** | A kept target remembers the org/person signed in when it was kept and is dropped if another person is signed in when the home comes up. A target kept while nobody was signed in still opens for whoever signs in. `notification_router.dart`. No unit test: opening goes through `Get` navigation, which the router tests do not set up; manual case L-18. |
| G-06 | not fixed | Needs the socket's online signal in `LocalNotificationService` (new dependency and binding change), more than a few lines in one file. |
| G-07 | not fixed | Needs the Tasks screen to switch section from outside; UI change, not in a BE doc. |
| G-08 | not fixed | Needs B-05. |
| G-09 | not fixed | Needs the Submissions screen to take a link (feature work). |
| G-10 | not fixed | Touches the core of the feed refresh; the audit already decided not to do it as a small fix. |
| G-11 | not fixed | Platform behaviour choice (iOS `inactive` also happens while the app goes to the background); needs a phone to judge. |
| G-12 | **fixed** | `SocketService._log` does nothing outside debug builds, so no titles or envelope starts are kept in memory in release. |
| G-13 | not fixed | Needs B-07. |
| G-14 | not fixed | Would add a new read on connect (new behaviour); decision first. |

### BE questions
| # | Question |
|---|---|
| B-01 | Task feed items (#10) have no `actionType`/`ref`: a tap cannot open the task (N §5, open question 4). Can they carry `actionType:"tasks"` and `ref.taskId`? Until then To-do tiles open a detail sheet. |
| B-02 | Does `feed.list {priority:"all"}` include resolved items? |
| B-03 | Payload of `request_created` / `request_resolved`: the request view directly, or `{request}`? Does it carry `direction`/`canRespond` for the receiver? (The app handles both and works out the rest.) |
| B-04 | `status.update` with the same `requestId`: is it answered before the `stale` check? (Needed for a retry after the first one went through and the screen already reloaded.) |
| B-05 | Which `category`/`priority` do security notices (#13-15) carry? The app routes only `category == "security"` to the high-importance channel. |
| B-06 | Does an announcement (broadcast) also create a feed item? If not, a phone in the background never learns of it. |
| B-07 | May an assignee reopen a finished task? Does `task.update {due:null}` clear a due date? |
| B-08 | `task.create` has no `cid`: is a server-side duplicate check planned (T open question 3)? |
| B-09 | Muted chats: will the server stop creating feed items (N open question 1)? |

### Not blockers
There are no blockers. The two majors are decisions (G-01, G-02); B-04 and B-06 are risks I could not check without the server.

---

## D. Tests added

Before: 259 tests. After: **392** (+133), `flutter test` all pass, `dart analyze test` clean.

| File | Tests | Covers |
|---|---|---|
| `test/notifications/feed_repository_test.dart` | 33 | re-read on connect/resume, coalescing 150 ms, shared in-flight read, three events, counts, onGone, rollback of all 6 feed writes, paging cursors, in-app lines, e2e text and cache, reset on session change |
| `test/tickets/ticket_detail_controller_test.dart` | 10 | payload, request id kept/new, stale, forbidden, double tap, offline, not_found, reason required, no cross-account leak |
| `test/tasks/tasks_controller_test.dart` | 16 | list params, paging, filter, error state, create (no cid, once, offline, rate limit, double tap), status move, forbidden/not_found recovery, send, events |
| `test/approvals/approvals_controller_test.dart` | 8 | real `req.list`, accept, reject needs reason, already_resolved, lost answer not replayed, forbidden/not_found, double tap, events |
| `test/tasks/call_problem_table_test.dart` | 26 | every error code, read and write, text verbatim |
| `test/tasks/time_handling_test.dart` | 14 | overdue with a wrong clock, labels, midnight, picker, limits at the edge |
| `test/notifications/local_notification_gaps_test.dart` | 14 | the catalogue types against the rules, own action, chat sources, channels |
| `test/notifications/real_replies_test.dart` | 12 | Postman samples (feed, approvals, status.update, events) through the parsers |
| `test/support/` | – | `FakeSocket`, `FakeStore`, `Postman` fixture reader |

Not testable without a phone/server: the system tray (collapse, clearing, permission prompts), cold/warm tap routing, the socket's own `onOnline`/`session_replaced` handling, rendering at text scale 1.3.

## Update: one rule for foreground and background, new channels

- Rules: `LocalNotificationRules.explain` returns the decision with its reason; `decide` wraps it. There is no foreground input and no in-app notice for feed items. `AppNotices` stays for errors and results of the person's own actions.
- Android channels are `messages_v2`, `approvals_v2`, `security_v2` (importance high) and `tasks_v2`, `system_v2` (default), all with sound and vibration. The earlier ids (`messages`, `approvals`, `tasks`, `system`, `security`) are deleted at startup, because a channel's settings cannot change after creation.
- The small icon is `@drawable/ic_stat_notification` (white on transparent), kept from shrinking by `res/raw/keep.xml`.
- Temporary `notifyflow:` logs trace lifecycle, socket state, each `feed_item`, the decision, the permission, channel creation and `show()`; they are on the "Before release" removal list.
