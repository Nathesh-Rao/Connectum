# Tasks and actions: how they work today (for the mobile team)

Written from the code, nothing changed. Paths are relative to `connectum/connectum-backend/src/` unless they start with `chat-app/` or `docs/`. Line numbers are as of `main` on 5 Nov 2026 and will drift: search by the quoted text if a line moved.

Wire format for every call below (docs/CONNECTUM_API.md:270–289): send the text line `/sd <action> {json,"reqId":n}` on the chat socket; the reply is `{"type":"sd","action","reqId","ok","data"}` or `{"ok":false,"error":{code,message,details}}`. Live pushes arrive as `{"type":"sd_event","event":…,"data":…}` (`core/sd_notify.erl`:142–168).

## 1. What a "task" is (three different things share the word)

| Kind | What it is | Where |
|---|---|---|
| **Task** (To-do) | A small record one employee gives to another (or to themself) | `people/sd_tasks.erl` |
| **Ticket / form task** | A form submission that has a `status` field; it moves through Open, Forwarded, In progress, Completed, Closed, Returned, Dropped | `forms/sd_status.erl`:1–62 |
| **Approval request** | Something waiting for a person to Accept, Reject, Return or Ignore | `people/sd_reqs.erl` |

Mobile must treat them as three lists; they have different actions, errors and events.

### 1.1 Task record
Fields (`people/sd_tasks.erl`:3–4): `id, title, description, creator, assignee, due, priority (low|normal|high), status (open|in_progress|done|cancelled), created, updated, doneTs`. The view adds computed `overdue`, `creatorName`, `assigneeName` (:247–251).
Limits: title ≤120, description ≤2000, `due` not in the past, priority one of the three (:276–321).

## 2. How tasks appear in chat

- **There is no task message in the chat stream.** A task is told to the other person as a **My Workspace feed item** (a notification tile) plus a live event; see `tell/5` (`people/sd_tasks.erl`:333–340): feed key `task:<id>`, severity medium, category `system`, icon `task_alt`, and event `task_assigned` or `task_updated` with `{"task": view}`.
- **`#` commands.** The web composer sends the typed line to the server once and then opens a screen for some commands. `#tasks`, `#task`, `#todo` are **screen-only**: the server has no chat command of that name and would answer "Unknown command", so the web opens its tasks panel and uses the `task.*` actions (`chat-app/features/connectumChat/chatActions/routeHashCommand.js`:25–41, 32). The commands the server does know are listed in `chat/chat_cmds.erl`:59–119 (dm, groupmsg, users, groups, inbox, profile, creategroup, addmember, leavegroup, me, associates, find, transfer, scan, forms, options, lookups …). The web catalogue is `chat-app/features/connectumChat/data/hashCommandsCatalog.js` (461 lines) and a person's own commands come from `cmd.custom/list/save/delete` (`core/sd_cmds.erl`:617–623; kinds option|wizard|tstruct|list|datasource, ≤20 per person, `core/sd_cmdx.erl`:1–40).
- Permission-gated commands are stopped on the client first with the text "You don't have access to #<cmd>. Ask your administrator to give you the permission." (`routeHashCommand.js`:12–16). The list: broadcast/announce → `broadcast`; studio/code/ide → `studio.use`; addemployee/inviteemployee → `invite.employees` (`utils/permissions.js`:15–23). The server still enforces; `availability/2` (`core/sd_cmds.erl`:43–60) only greys things out.
- **Automated tasks and alerts** reach a person as feed items (section 2 of `NOTIFICATIONS_FOR_MOBILE.md`): new submission, ticket assigned, approval needed, reminder, outcome, security notice, and API messages (`forms/sd_feed.erl`:352–592).
- **Cards in the message stream.** Two things appear inside a conversation: (a) a submitted form posted to a DM or group as a message of kind `form` with JSON text `{structure, scope, caption, submissionId, by, fields:[...]}` (`forms/sd_formmsg.erl`:1–15; live event `form_message` {conversation,id,ts,from,form,text}, :223–225; edits `form_message_updated`, :105); (b) a ticket's record conversation gets a card on each status update (`forms/sd_status.erl`:11–12). Not in the general room (`sd_formmsg.erl`:14–15). The web draws MESSAGE-API items as cards in My Workspace (`chat-app/.../utils/apiMessageCards.js`:1–30, newest 30).

## 3. Actions

All `sd` actions need a signed-in session. Who may: `access(Action)` in `core/sd_cmds.erl` gives a level `user | host | manage | admin` (:43–60). Idempotency: only `tstruct.submit`, `tstruct.user.submit`, `submissions.update`, `submission.resubmit`, `group.create` take a `cid` (1–64 chars; answer remembered 1 day; repeat returns `duplicate:true`; concurrent returns error `in_progress`) (`core/sd_cmds.erl`:217–257). Tickets use their own `requestId` (`forms/sd_status.erl`:564, 899–910).

### 3.1 Task actions (`core/sd_cmds_people.erl`:293–300 → `people/sd_tasks.erl`)

| Action | Who | Params | Result | State change / events | Errors (code: text) |
|---|---|---|---|---|---|
| `task.create` | employees only | `title`, `description?`, `due?`, `priority?`, `assignee?` (default self) | `{task: view}` | creates `open`; tells assignee `task_assigned`, feed "New task from <name>" (:27–57) | `rate_limited`: "Too many tasks this hour; try later." (120 per 3600 s per person, key `task:<user>`); `invalid` for field rules; "Tasks can only be sent to employees."; "No such employee."; interaction policy `sd_policy:may_interact` (:256–274) |
| `task.list` | caller | `as` assigned\|created\|all, `status` active\|<status>\|all, `limit` ≤100 (default 50), `offset`; admins `all:true` | list sorted soonest due first | none (:69–91) | |
| `task.update` | creator (any field); assignee (status only) | `id` + fields | `{task}` | tells the other party `task_updated`: "<name> set a task to <status>" or "<name> changed a task" (:107–152) | `invalid`: "Nothing to change…"; `forbidden`: "Only the person who created the task can edit it."; "A finished task cannot be edited; reopen it first."; "status must be open, in_progress, done or cancelled."; "Only the person who created the task can cancel it." (:155–165) |
| `task.send` | creator | `id`, `to` | `{task}` | reassigns; new holder gets `task_assigned`, old gets `task_updated` "<name> gave your task to someone else" (:178–216) | "It is already with them."; "Only the person who created the task can send it to someone else." |
| `task.get` | creator or assignee | `id` | `{task}` | none | `not_found`: "No such task." (also for other people's tasks) (:220–230) |

The web panel's calls: `task.list`, `task.create`, `task.update`, `task.send` (`chat-app/.../modals/MyTasksPanel.jsx`:46–106); it re-reads on `task_assigned`, `task_updated` and after reconnect (`resync`) (:69).

### 3.2 Ticket actions (`core/sd_cmds_forms.erl`:325–340, `forms/sd_status.erl`)
- `status.update {id, action, expected:{status, assignee}, sendTo?, reason?, remarks?, percent?, requestId?}`: one all-or-nothing step. `action` is one of the shipped **Send, Status update, Complete, Close, Return, Drop** (:55–62; the table is data per form and may differ). Who: assignee, raiser or admin, per action. Check order: record exists and not waiting approval → person may take the action → allowed from the current status → reason/remarks/send-to/percent rules → person saw the latest state (:1–12).
- `status.mine {as?: with|raised, limit?≤200 (default 100), offset?}`, `status.get {id}`, `status.history {id}` (oldest first).
- Errors seen in the module: `invalid` (many), `not_found`, `forbidden`, `bad_request`, `stale` ("This ticket was updated by someone else. Reload to see the latest.", :611–613), `duplicate`, `busy`. Protected-field text: "Status, Assigned to and Completion change through status updates only." (:~34).
- Event: `ticket_assigned` to the new holder (`sd_status.erl`:340, 888, 1019), payload `{id, tstruct, action, by}`; a record conversation also gets a card.

### 3.3 Approval actions (`core/sd_cmds_people.erl`:185–212, `people/sd_reqs.erl`)
- `req.list {status (default "pending"), limit ≤200, offset}` → `{requests,total,offset,limit,hasMore}`. Each request carries `direction` incoming|outgoing|other and `canRespond` (`sd_reqs.erl`:263–277).
- `req.respond {id (int), action: accept|reject|return|ignore, reason?, comment?, allowResubmit?}` → `{request: view}`. Errors: `invalid` "id (number) and action are required.", "action must be accept, reject, return or ignore.", "Say why: a form that is sent back or declined needs a reason." (:359–364), "Only a submission can be returned to its sender." (:396); `not_found` "No such request."; `already_resolved` "That request has already been answered."; `forbidden` "You sent this request, so it is waiting for <names> to answer." / "This request isn't yours to answer." (:366–379).
- Request types: onboarding, associate, host_transfer, group_invite, membership, submission (a step in a form's approval chain), handover (`sd_reqs.erl`:1–17). Status: pending|accepted|rejected|ignored.
- Events: `request_created` to each approver; `request_resolved` to the sender and approvers; also `membership_added`, `associate_connected` (:189, 542). Resolving also resolves the approvers' cards and feed items and tells the requester.
- Form approval chains: stage 1 the submitter's reporting manager, then each designation; any one approver of a stage answers; a stage nobody can answer is skipped; on approve the submitter gets `submission_approved` "Your <Caption> was approved"; on decline/return `submission_rejected` "Your <Caption> was declined by <name>: <reason> (<comment>)" with ". You can fix it and send it again" when allowed (`forms/sd_subflow.erl`:1–31, 781, 826–842, 1084–1094). Payload of these events: `{submissionId, tstruct, status, reason, allowResubmit}`.

### 3.4 Other actions mobile will meet
`reminder.add {text, dueTs?}` (`core/sd_cmds.erl`:446–451); `cards.list {section,limit}`, `cards.dismiss {id|"all"}` ("id is required (a card id, or \"all\")."), `sections.*`, `forms.forward` (`core/sd_cmds_forms.erl`:15–44); `broadcast.preview|send|list` (needs the `broadcast` permission; targets branch/department/designation/role lists, ≤1000 chars; `people/sd_broadcast.erl`:1–25); `conv.pin/unpin/mute/unmute/read` (`core/sd_cmds.erl`:204; server keeps only a `muted` flag, `forms/sd_conv.erl`:5–22).

## 4. Lists and paging
Tasks: limit/offset. Requests: limit/offset + `hasMore`. Tickets: limit/offset + `total`,`hasMore`. Feed: `before`/`beforeId` cursor + `limit` ≤200 (default 50). Cards: `limit` ≤200, newest 500 kept. Nothing is cursor-less infinite: mobile must page.

## 5. Realtime
Events that change task-like lists (`chat-app/.../utils/useLiveChanges.js`:8–13): `tstructs_changed, options_changed, submissions_changed, task_assigned, task_updated, ticket_assigned, submission_approved, submission_rejected, submission_notice, permissions_changed, membership_added, plugins_changed, pages_changed, links_changed`. The web coalesces bursts to one refresh per ~150 ms and does a full re-read after every reconnect because **events sent while offline are lost** (`sd_notify.erl`:142–168: `push_event` is a no-op for an offline user). Mobile must do the same: on connect, call `task.list`, `req.list`, `status.mine`, `feed.list`.
Sessions: one active session per person per client kind (`web` or `mobile`); signing in again on the same kind ends the previous one and tells it `session_replaced` (`security/sd_auth.erl`:156–170). A phone and a laptop can both be signed in; the other kind is told "session_added".

## 6. Forms as tasks
A form with a status field is a ticket (3.2). Approval-needed forms create a `submission` request per stage (3.3). A submitted form can be posted into a conversation (2). Submissions: `submissions.list/update/delete`, `submission.get/history/resubmit` (`core/sd_cmds_forms.erl`:108–311). A pending or approved submission can no longer be edited or deleted (`sd_subflow.erl`:14).

## 7. Encryption
Direct and group chat text can be end-to-end encrypted (`security/sd_e2e.erl`:1–25); modes via `CONNECTUM_E2E`: off | optional | required. **Not encrypted:** forms, `#` commands, AI chat, the general room, **tasks, tickets, approvals, feed items and API messages** (the server has to act on them; `docs/API_WORKSPACE_MESSAGE.md` says the text is stored readable). Only a DM/group notification carries an envelope that the device must decrypt (see notifications doc §E2E).

## 8. Offline and errors
- Command limiter: documented 30 per 10 s per connection (docs/CONNECTUM_API.md:289); production currently runs 200 per 10 s (`CHAT_RATE_LIMIT_MAX`, docs/LOAD_TEST_VM.md:38). Refusal comes in the normal envelope with code `rate_limited`, "Too many commands -- slow down and retry." (`core/sd_cmds.erl`:62–77).
- Lanes: 200 queued, 4 slow, 8 aux; beyond that error `busy` (`core/sd_lane.erl`:1–26).
- A dropped or replaced session: `session_replaced`, `session_expired`, `connection_superseded`, `disconnected` reason `account_deactivated` (handled `chat-app/.../chatEvents/index.js`:110–119).
- **Nothing queues offline on the server.** The server has no offline outbox for tasks; whether the mobile app queues writes is a mobile decision (open question 3).

## 9. Not verified / does not exist
- No audit log is written by `sd_tasks.erl` or `sd_feed.erl` (grep for `audit` found none); `sd_reqs.erl` has none either (checked: no match).
- Chat-socket reconnect catch-up for **messages** (history after a gap) was not read by me for this document; see `docs/CHAT_PROTOCOL.md` (not read).

## Open questions for the product owner
1. Should mobile show tasks assigned to others (creator view) or only mine?
2. Is the 120 tasks/hour limit per person final?
3. Should writes (create/update/respond) queue while offline and replay with a `cid`? Only five actions accept `cid` today; `task.*` and `req.respond` do not, so a replay could double-create a task.
4. Should tasks get an audit trail?

## What mobile must match exactly versus what may differ
**Must match exactly:** action names and parameter names; the status sets (task: open/in_progress/done/cancelled; request actions accept/reject/return/ignore; ticket actions Send/Status update/Complete/Close/Return/Drop and the `expected` staleness object); who may do what and the server's error codes and texts (the server is the judge; show `error.message`); the `reqId` envelope; handling of `rate_limited`, `busy`, `stale`, `already_resolved`; full re-read of lists after reconnect; the one-session-per-kind rule; treating tasks/tickets/approvals as unencrypted.
**May differ:** layout, grouping, swipe gestures, sorting beyond the server's default, local caching and pull-to-refresh, haptics, how the `#` menu is presented (the web filters commands by `COMMAND_PERMS`; mobile may use `availability`), whether to show the web's 150 ms coalescing, wording of purely client-side hints.
