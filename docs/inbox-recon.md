# Inbox recon (web Inbox -> mobile)

Recon only. No app code changed. Nothing was run or built.

**Sources.** Handoff: `docs/Connectum_Inbox_for_the_mobile_team.md` (called "the doc"). Web code: `~/Development/Axi-apps/connectum`, branch `dev`, head `7e685aa8` (PR #975, 24 Nov 2026 15:08), read from the working tree. The Inbox work is merged: `bee7b0a4` took `feat/smartview-next4` into dev. Backend is in the same repo (`connectum-backend/src`), so server claims were checked in Erlang too.
**Notation.** `W:` = web file under `connectum/chat-app/` (`SV/` = `features/smartView/`, `CC/` = `features/connectumChat/`). `B:` = backend under `connectum/connectum-backend/src/`. `M:` = this repo. "Inferred" = read from code, not run.

---

## 0. Doc vs code (trust the code)

| # | Doc says | Code says |
|---|---|---|
| 1 | Branch `feat/smartview-next4`, not released | Merged into `dev` (`bee7b0a4`, PR #975). |
| 2 | Filter line is "Form" | Labelled **"Data"** (`W:SV/InboxFilterFab.jsx:115`). Same multi-select, same counts. |
| 3 | Grid: 3 wide, 2 under 760 px, 1 under 480 px | No such breakpoints. `grid-template-columns: repeat(auto-fill, minmax(min(100%, 260px), 1fr))` (`W:SV/hashInbox.css:134`). Column count follows width, 260 px minimum card. 24 cards per chunk is right (`W:SV/WorkCards.jsx:13`). |
| 4 | Decline-with-reason and Return "open the Approvals dialog for the box" | The Inbox no longer imports the dialog. Both buttons only call `setFolder("approval")` (`W:SV/HashInboxModal.jsx:202,204`), which shows the "Pending my approvals" list: the same cards again. **On dev the Inbox has no reason box; the button is a dead end** (inferred, not run). The box exists only in `ApprovalsPanel.jsx:689-707` + `ApprovalAnswerForm.jsx`. |
| 5 | Live events: `submissions_changed`, `submission_approved`, `submission_rejected`, `ticket_assigned`, `resync` | The listener knows 14 events (`W:CC/utils/useLiveChanges.js:8-13`). The Inbox re-reads on the regex `^(task_\|ticket_\|submissions?_\|resync)` (`W:SV/workItems.js:213`): also `task_assigned`, `task_updated`, `submission_notice`. Coalesced to one call per **150 ms** (`useLiveChanges.js:32-37`). |
| 6 | A re-read = `records.query`, `records.counts`, `records.people`, `req.list`, reminders | `readMail` (`HashInboxModal.jsx:143-153`) also runs `records.mine` x5 (with, raised, involved, team, team done), broadcasts, sent broadcasts; a second effect runs `records.mine` x3 again at open (`:155`). About 12-16 commands per burst. |
| 7 | Web reads more pages while the person types, up to 5,000 records | True only for the old `records.mine` lists (`:347-371`, `searchKey`). For the default `records.query` list `searchKey` is `null` (`:349`) so **search only covers the pages already loaded** (100 per page, more on scroll). |
| 8 | Timeline = same records, one heading per day | Timeline is not a `records.query` view. It switches to the old "task" folder and groups `records.mine` lists by `dayHeading` (`:375,404,319-323`). |
| 9 | View name up to 60 characters | Server: 60 (`B:forms/sd_inboxview.erl:16`). The web UI trims to **40** (`W:SV/svViews.js:32`). |
| 10 | View up to 20,000 bytes | Measured on the Erlang term (`byte_size(term_to_binary(...))`, `sd_inboxview.erl:105`), not JSON length. Not predictable on the phone. |
| 11 | `inbox.views.default {name\|null}` | Exists on server (`B:core/sd_cmds_forms.erl:402`). Web never calls it; it sets the default with `save {default:true}` (`HashInboxModal.jsx:451`). `inboxView.js:1` still says `inbox.view.*` (stale comment). |
| 12 | `req.list {status?, limit?, offset?}` | Web calls `{status:"all"}` with no limit (`W:CC/utils/useApprovals.js:11`). Server returns at most **200**, newest first, `hasMore` (`B:core/sd_cmds.erl` `req.list`). Web ignores `hasMore`. |
| 13 | Priority "dot" | Dot is right (`W:SV/RecordFrame.jsx:53`). The comment in `recordTone.js:9-10` still says "stripe". |
| 14 | "A record that belongs to a report is read only" | No client rule found. The card just asks `record.actions` (`W:SV/WorkCards.jsx:81`); the server answers with what is allowed. |
| 15 | Count on Approvals button vs banner (6 vs 3, "not checked") | **Found, see section A.6.** |
| 16 | 30 per 10 s | Right. See section A.9. |

---

## A. Web Inbox, verified

### A.1 Screen structure

| Part | Where | Notes |
|---|---|---|
| Header | `HashInboxModal.jsx:490-513` | Title "Inbox", search box (`tools`, `:480-488`), Approvals button (`:501-506`), Refresh (`:507`, also `forgetSizes()`), Filter FAB (`:508`), Views (`:509`), Expand (embedded only, `:510`), Close (`:511`, asks "Save your changes?" via `guard`). |
| Opens on | `:69` | `initialFolder` only if it is not all/approval/reminder, else `"data"` (the records list). Then the Default View is applied unless opened on a folder on purpose (`:432-441`). |
| Which list | `:293-298` | `queryView = ["data","escalation","requests","completed"].includes(folder)` (`inboxQuery.js:111`). These four read **`records.query`** through `useRecordQuery`. Other folders (task/timeline, approval stage lists, reminders) are client side. |
| Card grid | `WorkCards.jsx:63-95` | 24 drawn, more when the foot is seen (IntersectionObserver, 400 px margin), then `onMore` reads the next 100 from the server (`:53-62`). |
| Card anatomy | `RecordFrame.jsx:33-67` | Band: person face (+ name under), title (form caption, `cardTitle plain`), byline `#<id> · <date>, <time>`, status chip, priority dot, three-dot menu host. Body: `name value` rows (`recordRows.js`), empty values dropped, scrolls inside the card. |
| Status chip | `RecordFrame.jsx:11-15` | `LiveStatus` = record's own live status (shared `useRecordState`, tone from `toneOf`), fallback `badge` (e.g. "Waiting for approval"). |
| Person on the card | `WorkCards.jsx:25` | `holder` first name, else `raiser`. "You" when it is the user. Picture/name from `people.cards` (`usePeopleFaces.js`). |
| Three-dot menu | `WorkCards.jsx:78-86` | `RecordActionsBar` (Send, Update status; shown only if `record.actions` allows) + `History` (`submission.history`). Opening one panel closes the other. |
| Non-record cards | `MailCards.jsx` | Approval / reminder / broadcast. Tag instead of record status; buttons at the foot (Approve, Decline, Return). |
| State colour | `recordTone.js:58-66`, `WorkCards.jsx:27` | Order: `final`->completed; declined or status word in `rejected\|declined\|blocked\|failed\|overdue\|cancelled\|canceled`->rejected; `waiting` (`sub.status==="pending"`)->waiting; status view (pending/assigned) decides; holder list contains me->pending; `via` contains `"holder"` (team)->pending; else assigned. `final` = `it.final \|\| (sub.status==="approved" && no status text)`. Colours: `hashInbox.css:303-307` (green, blue, yellow, violet, red). |
| Priority dot | `recordTone.js:16-49` | Field **name or caption** matches `/(priorit\|severit\|urgen\|importan\|critical\|risk)/i`; value read as words (label first, then stored value; "priority/severity/urgency/level" stripped). high: highest, very high, high, urgent, critical, blocker, severe, major, p0, p1, sev 1. medium: medium, moderate, normal, average, med, p2, sev 2. low: lowest, very low, low, minor, trivial, p3, p4, sev 3, sev 4. First field that matches a level wins. |
| Record -> row model | `workItems.js:94-122` | Needs from each record: `id, tstruct, values, labels, by, holder, claimants, status, completion, ts, team.via/members/links, actedBy, externalId` and from `structures[tstruct]`: `caption, fields (name->caption), status{field,final[]}`. Subject = field named title/name/subject/summary/what/heading, else first short text, else `<caption> #<id>` (`:79-91`). |
| Empty/error text | `:543` | "No records match the filter." / "No records yet." / "The records could not be read. Use Refresh to try again." |

### A.2 Filter panel (`W:SV/InboxFilterFab.jsx`, request building `W:SV/inboxQuery.js`)

Nothing applies until **Apply** (`:142`); **Clear** resets (`:141`, `clearPanel` `HashInboxModal.jsx:407`). Count badge = lines set (`filterCount`, `:39`). Panel closes on outside tap/Escape.

| Line | UI | Request field (to `records.query`) | Where built |
|---|---|---|---|
| Search in | multi-select, none = All records | `views: [...]`, one object per entry (see A.3). `[{}]` (single empty) is **not sent** | `inboxQuery.js:68-76,135-140` |
| Data (doc: Form) | multi-select, only forms that have a record under the other lines, with count | `forms: [formName]` | `filterArgs` `:95-101` |
| Created by | multi, "Me" first | `createdBy: ["me" \| user,...]` (<= 50, each <= 200 chars) | `names()` `:83` |
| Sent by | multi | `sentBy` | same |
| Sent to | multi | `sentTo` | same |
| Tagged to | multi (fallback list = sentTo + team when no facets) | `taggedTo` | same; `InboxFilterFab.jsx:116` |
| Date | from / to (`type=date`) | `from`, `to` as `YYYY-MM-DD` (regex `inboxQuery.js:78`) | `queryArgs` |
| Sort | Latest, Oldest, A-Z, Z-A, **Open only**, **Closed only** | Open/Closed -> `status:"open"\|"closed"` (and sort back to latest); the four orders are **client side only** (`sortRows`); the server always returns newest first | `InboxFilterFab.jsx:17-18,125` |
| Advanced | up to 10 blocks | `groups: [{form?, createdBy?, sentBy?, sentTo?, conditions?}]` (<= 10 groups after expansion) | `groupsOfBlock` `:55-59` |
| Advanced > Approval | tick Pending / Approved / Rejected, only when a form in a block has an approval flow | **not sent**; client side filter of the approval list (`approvalPick`, `HashInboxModal.jsx:285-287`) | |

Block rules (`inboxQuery.js`): a block that says nothing is dropped (`blockActive`, `:43`). A block naming several forms becomes one group per form, same people (`:58`). **Conditions are sent only when exactly one form is named** (`readyConditions` `:49`), max 20, each `{field, op, join:"and"|"or", value?, value2?}`; value is trimmed; `value` omitted for `empty/notempty`; `value2` only for `between`. Operators per field kind: `OPERATORS` `:10-15` (text: contains eq ne starts ends empty notempty; number: eq ne gt gte lt lte between empty notempty; date: eq lt gt lte gte between empty notempty; bool: eq). Field kind: number/date/bool, else text (`kindOfType` `:18`). Server also accepts `in nin` (`B:forms/sd_recquery.erl:7`).

### A.3 Union of several "Search in" entries

Built in `serverViews(wheres, filters, team)` (`inboxQuery.js:135-140`). Each entry becomes one **view object** merged over the shared fields; the server lists a record when ANY view holds it (`sd_recquery.erl` `parse_views`, `merge_by_id`, max **8** views).

| Entry id (UI) | View object sent | Source |
|---|---|---|
| `all` / none | `[{}]` -> no `views` field at all | `:137,71-73` |
| `me` | `{scope:["me"]}` | `:126` |
| `team` | `{scope:["team"]}` | `:127` |
| `requests` | `{createdBy:["me", ...first 49 report names]}`; **`{}`** if "Created by" is already set | `:128`; team names from `records.people.team` |
| `completed` | `{status:"closed"}` | `:129` |
| `escalations` | `{escalated:{days:3}}` | `:130` |
| `timeline` | `{}` (stands alone; handled client side) | `:131`, `whereChoice` `:117-122` |
| `allapprovals`, `approvals` (Pending my approvals), `approved`, `rejected`, `reminders` | **no view** (not records). If the choice has only these, no records are asked (`recordsOff`, `HashInboxModal.jsx:295`) | `serverViews` filters by `VIEW_OF` |

Mapping of ids to labels: `SEARCH_IN` `InboxFilterFab.jsx:13` (`allapprovals`="Approvals", `approvals`="Pending my approvals"). Several entries are saved as `wheres`; one entry as `folder` (`inboxView.js`). `whereChoice`: Timeline is exclusive; picking it clears others; picking another clears it.

Server view keys allowed: `scope, createdBy, status, escalated` (`sd_recquery.erl:7` `VIEW_KEYS`). A view overrides the shared field of the same name.

### A.4 WebSocket calls the Inbox makes

All through `connectumSocket.sd(action, args, timeout)` (30 s for reads, 15 s for views). Reply `{ok:true,data}` or `{ok:false,error:{code,message}}`.

| Call | Request as web sends | Reply fields used | Web file | In mobile today? |
|---|---|---|---|---|
| `records.query` | `queryArgs` + `offset`, `limit` (100 page; up to 200 when re-reading what is shown) | `submissions[]`, `structures{}`, `total`, `hasMore`, `capped` | `workItems.js:35-40`, `useRecordQuery.js` | **No** |
| `records.query` (facets) | `facetArgs` + `facets:true, offset:0, limit:1` | `formCounts{form:n}`, `people{createdBy,sentBy,sentTo,taggedTo}` | `workItems.js:46-52`, `useFormCounts.js` | **No** |
| `records.counts` | `{}` | `{me, team, all, reports, cap}` (cap default 1000; more than cap = `cap+1`) | `workItems.js:25-29` | **No** |
| `records.people` | `{}` | `{team[], sentBy[], sentTo[]}` (<= 200 each) | `workItems.js:72-77` | **No** |
| `people.cards` | `{usernames:[<=60]}` (web asks only unknown names, batches) | `people{<user>:{name, designation, role, avatar}}` | `usePeopleFaces.js:18` | **No** (mobile has `people_avatars` table only) |
| `records.mine` | `{as:"with"\|"raised"\|"involved"\|"team", offset, limit<=200, done?}` | `submissions, structures, total, hasMore, next` | `workItems.js:17-22` | Yes (`RecordCmd.mine`, workspace, Smart View) |
| `req.list` | `{status:"all"}` | `requests[], total, hasMore` | `useApprovals.js:11` | Yes (`approval_repository.dart:107`) |
| `req.respond` | `{id:Number, action:"accept"\|"reject"\|"return"\|"ignore", reason?, comment?, allowResubmit?}` | `request` | `useApprovals.js:29` | Yes (`approval_repository.dart:143`); mobile sends `reason`, `allowResubmit`, **not `comment`** |
| `record.actions` | `{id}` | what the person may do | `RecordActions.jsx` | Yes (`TicketRepository.loadActions`) |
| `record.send`, `record.status` | per record flow | | | Yes |
| `submission.history` | `{id}` | timeline | `RecordTimeline` | Yes |
| `inbox.views.get` | `{}` | `{views:[{name,view,savedTs}], default}` | `workItems.js:55-59` | **No** |
| `inbox.views.save` | `{name, view, default?:true}` | `{views, default}` | `workItems.js:68` | **No** |
| `inbox.views.delete` | `{name}` | `{views, default}` | `:69` | **No** |
| `inbox.views.default` | `{name\|null}` | `{views, default}` | server only | **No** |
| `admin.users.list` | `{status:"all", pageSize:200}` | only when a pending sign-up exists (admin lookups) | `useApprovals.js:18` | not needed |
| reminders / broadcasts | `loadInbox("reminders")`, `loadBroadcasts`, `loadSentBroadcasts` (`smartViewSources.js`) | | | **No** (out of the four changes; see D) |

Server limits on `records.query` (`B:forms/sd_recquery.erl:5-37`): limit 1-200 (default 100), offset up to 1,000,000, groups <= 10, conditions <= 20, people names <= 50 (<= 200 chars), views <= 8, `escalated.days` 1-365. Each list read is capped at 1,000 records (`?CAP`); `capped:true` says a list was longer. **Every page call recomputes the whole filter** (no cursor; `run/2` builds `Kept` then slices): paging N pages costs N full runs.

### A.5 Approvals: the "Return" call

Not "unchecked": found.

- `req.respond {id: Number, action:"return", reason: <required, trimmed, <= 500>, comment?: <<= 500>}` (`W:CC/utils/useApprovals.js:28-29,47`; rules `W:CC/utils/approvalAnswer.js:22-37`). A return has no `allowResubmit` (it always can be fixed and re-sent). Only for `type === "submission"` (`HashInboxModal.jsx:204`, `ApprovalsPanel.jsx:689`).
- Decline: `action:"reject"`, `reason` required for a form (`declineNeedsReason`, `approvalAnswer.js:12`), `allowResubmit:true|false` always sent for a form decline (`:34`). A sign-up decline: reason optional, no `allowResubmit` (`declineOffersReason`).
- Approve: `action:"accept"`, optional `comment`.
- Ignore: `action:"ignore"` ("Dismiss").
- After every answer: toast, `req.list` again; on accept also sends `#associates` (`useApprovals.js:42`).
- Mobile already has all four actions (`M:lib/features/approvals/models/approval_rules.dart:3-41`, `approval_repository.dart:115-155`). Gap: `comment` (max 500) is not sent.

### A.6 Approvals button, dropdown, count rule, and why it differs from the banner

- **Button**: `HashInboxModal.jsx:501-506`. Toggles `approvalsOn`; shows `ApprovalsPane` in place of the list (`:540`). Not saved in a view. Applying the filter, Clear, or opening a view sets `approvalsOn=false` (`:397,407,426`).
- **Pane**: `ApprovalsPane.jsx`. Rows = `approvalsAll` = every approval row matching the search text (`:288`). Dropdown `All (n)` + `Pending / Approved / Rejected / Closed (n)`; an answer with 0 rows is not offered (`:14-16`). Empty texts: "There are no approvals." / "No approvals are like that." Rows sorted newest first (`mail` sort `newestFirst`, `:218`).
- **Row state**: `approvalState` = `pending` if `status==="pending"`, `rejected`, `approved` if `accepted\|approved`, else `other` (`:195`). Tag "Waiting for you" if pending and `canRespond===true`; "Waiting for approval" if pending and not; "Declined"; "Approved" (`:187-188`). A settled sign-up (`onboarding` not pending) is dropped from the list (`:75`).
- **Button count** = approval rows with `unread` = `pending && canRespond === true` (`:187,195,200,504`).
- **Banner count** (My Workspace) = `approvals.filter(r => r.status === "pending").length` with **no `canRespond` test**, so it also counts requests the person **sent** that wait on someone else; it is hidden when all pending ones are sign-ups/memberships (`W:CC/ConnectumChatScreen.jsx:400-405`). That explains 6 vs 3 (inferred from code; the dev data was not read).
- Mobile has no banner (not found); the Approvals icon in My Workspace has no count (`M:lib/features/workspace/workspace_view.dart:52-55`).

### A.7 Saved views

Server `B:forms/sd_inboxview.erl`:

- `get` -> `{views:[{name, view, savedTs}] sorted by name, default}`. An older single doc becomes view "My view" (default).
- `save {name, view, default?}`: name 1-60 bytes after trim, no control chars; max **20** views (replace of an existing name is always allowed); `view` must be a map; only these keys are kept: `folder, lens, kinds, dataForms, approvalPick, scopePick, wheres, teamMembers, blocks, filters, sort, timing` (`:19`); size <= **20,000** bytes (term); `folder` must be one of `all data approval reminder broadcast escalation task requests approved rejected completed allapprovals` (`:20,123`); string lists <= 100 items of <= 200 bytes; `blocks` <= 10 maps; `filters`, `timing` maps; `sort` <= 40 bytes; `lens` <= 20 bytes. Errors `invalid`/`not_found`. `default:true` sets default to this name.
- `delete {name}`: clears `default` if it was the one.
- `default {name|null}`: `not_found` if the name does not exist.
- No `savedTs` conflict check: last write wins.

Web behaviour (`HashInboxModal.jsx:408-477`):

- Views are read once at open (`:432`). If nothing was started and no `initialFolder`, it opens the view named "Default View", else the one named by `default` (`:437-438`).
- "Default View" is the reserved name (`svViews.js:35`, `nameTaken`). Saving on the Default View sends `default:true` (`:451`).
- `changed` = current setup key differs from the one kept (`setupKey` JSON, `inboxView.js:17`, `:420`). Leaving (close, switching view, new view) while `changed` shows **Save your changes?** (Save / Discard / Cancel) (`guard` `:422`, `UnsavedDialog`).
- Save view (update open one), Save as new view (name; 20 max check client side too), Create view (plain list), Remove view (confirm).
- `restoreOf` (`inboxView.js:23-38`) validates every piece and falls back: unknown folder -> `"data"`; `wheres` kept only if > 1 entry (one entry lives in `folder`); `scopePick` only if exactly one of me/team; unknown entries dropped.
- `setupOf` stores `folder, lens (only in "task"), kinds, dataForms, approvalPick, scopePick, wheres, teamMembers, blocks, filters, sort, timing`. Date range is inside `timing.from/to` (`applyPanel` `:399`).
- **Compatibility rule for mobile**: views are shared with the web per person. Mobile must write `folder` from the allowed list and the same key shapes, and must read views saved by the web without throwing.

### A.8 Live updates, debounce, out-of-order

- Subscription: `useLiveChanges` (`W:CC/utils/useLiveChanges.js`): events in `LIVE` (14) and `status_change connected` -> `{event:"resync"}`; bursts coalesced to **one** callback batch per **150 ms**.
- Inbox re-read: only when `isWorkChange(c)` (`workItems.js:213`) -> `readMail()` (`HashInboxModal.jsx:156`). Broadcast events (`broadcast`, `feed_item`, `feed_changed`) re-read broadcasts only (`:158`).
- After an answer on a card: card slides out, `readMail` after 260 ms (`:161-170`).
- Out-of-order protection exists only for the **records list** and **facets**: sequence counters `seq` in `useRecordQuery.js:13,19,23,34` (120 ms delay before asking, newer ask wins, `more()` checks the same counter) and `useFormCounts.js:10,14-21` (150 ms, plus a `group` key so an answer of another Search in is never shown). `loadCounts`, `loadQueryPeople`, `refreshApprovals`, `records.mine` reads have **no** guard (last answer to arrive wins).
- A failed re-read keeps the list on screen (`failed` flag).
- The list re-read after an event asks for as many records as are shown (`shown.current`, up to 200) (`useRecordQuery.js:22`).

### A.9 Command rate limit: 30 vs 6

- **Server truth: 30 commands per 10 s per connection.** `?RATE_LIMIT_MAX_COMMANDS 30`, `?RATE_LIMIT_WINDOW_MS 10000` (`B:chat.hrl:13-14`), sliding window (`B:http/chat_web_send.erl:385-430`), tunable by env `CHAT_RATE_LIMIT_MAX` (`docs/CONNECTUM.md:69`). `/sd` lines that are refused get a normal reply `ok:false, code:"rate_limited"` with the same `reqId` (`B:core/sd_cmds.erl:65-77`). Other `sd_*` modules have their own per-person limits (e.g. `records.summary` 1500 ids/min, `api.run` 120/min; not touched by the Inbox calls).
- **Mobile's 6 is a self-imposed budget**, not a server number: `SvLimits.budget = 6` per `window = 10 s`, 300 ms gap (`M:lib/data/smart_view/smart_view_commands.dart:46-47`, gate in `M:lib/data/repositories/smart_view_repository.dart:255-257`); `mobile-handoff/smart-view.md:22` says "the task's budget; the document allows 20". It is stale and Smart View only.
- Mobile has three independent counters on one shared server limit: Smart View gate (6/10 s), `RecordActionsQueue` (8/10 s, `record_actions_queue.dart:25-27`), outbox (< 30/10 s). Together they can exceed 30. The Inbox needs one shared gate, or must pick a budget well under 30 for its own reads.
- Burst size matters more than the number: the web Inbox open is about 12-16 commands (see Doc vs code #6). Mobile should not copy that.

### A.10 `#inbox` vs `#view` on web

- They are **two separate full-screen modals**, not one screen with a switch. State is the single `modal` string in `ConnectumChatScreen` (`"inbox"` or `"smart_view"`, `ChatModals.jsx:40,144`; `setModal` calls `ConnectumChatScreen.jsx:1292-1303`). Opening one replaces the other; nothing is carried over (each mounts fresh).
- `#inbox` (`W:CC/chatActions/routeHashCommand.js:163-166`): first opens as an **embedded card** in the My Workspace thread (`renderInlineTool`, `ConnectumChatScreen.jsx:1505-1523`); **Expand** opens the full modal on the same folder and view (`inlineToolState` ref keeps `{folder, workView}` only, `HashInboxModal.jsx:80`).
- `#view [name]` (`routeHashCommand.js:303-308`): `setModalParam(rest ? {name} : null); setModal("smart_view")`.
- Banner, notifications and the phone's Submits tab open the Inbox with `{folder:"approval"|"task"|"submissions"}` (`ConnectumChatScreen.jsx:1288-1303`).
- There is no "Visualize" button or in-screen link between them on dev (the comment at `HashInboxModal.jsx:37` is stale).
- What persists across opening/closing: only server-side saved views; per-card sizes are browser local (web only); filters/search are lost on close (the guard asks to save).
- **Mobile equivalent** (design input, not decided): two bottom tabs already exist (`HomeTab.smartView`, `HomeTab.inbox`, `M:lib/features/home_shell/home_tab.dart:6-10`) and `#view` / `#inbox` hash commands. "Same hash-switching flow" = `#inbox` selects the Inbox tab, `#view [name]` selects the Smart View tab (with its entry kind), and each tab keeps its own state while the other is shown (HomeShell already keeps built tabs, `home_shell_controller.dart:232`). See D for the open choice.

### A.11 Search

Client side over text of cards already loaded (`filterWork`, `workItems.js:202-204`: subject, form, state, holder, raiser, id). Not server side. See Doc vs code #7 for the real reach.

---

## B. Mobile today

### B.1 Inbox tab (exists as a sample)

| Item | File |
|---|---|
| Route `/inbox`, tab | `lib/core/routes/app_routes.dart:18`, `lib/features/home_shell/home_tab.dart:8`, `lib/core/routes/home_reload.dart:143` |
| Screen: static pills (All, Tasks & tickets, Approvals, Reminders, My submissions, Broadcast), no data | `lib/features/inbox/inbox_{controller,view,binding}.dart` (21 / 163 / 10 lines) |
| Test + golden | `test/inbox/inbox_test.dart`, `test/inbox/goldens/inbox_placeholder.png` |
| `#inbox` command | `lib/data/commands/command_handlers.dart:59`; `lib/features/commands/command_runner.dart:221-222` does `Get.until((route) => route.isFirst)` only; it does **not** select the Inbox tab (inferred) |

### B.2 Smart View and its Overview

| Item | File:line |
|---|---|
| Controller: Overview state, `enter()` (tab -> Overview, drawer closed; `#view` -> Overview, drawer open; `#view <name>`), `isOverview`, `showOverview`, `onReselect`, back handling, `title` fallback "Overview", event hook | `lib/features/smart_view/smart_view_controller.dart:50-91,198-304,338,655-661,1059-1073` |
| View: `_Overview` page + crossfade | `lib/features/smart_view/smart_view_view.dart:36,187-228` |
| Drawer: "Overview" row at the top | `lib/features/smart_view/widgets/smart_view_drawer.dart:134-162` |
| Overview UI | `lib/features/smart_view/widgets/sv_overview_body.dart`, `sv_overview_card.dart`, `models/sv_overview_model.dart` |
| Overview data (pure Dart) | `lib/data/smart_view/overview/sv_overview.dart`, `sv_overview_cache.dart` |
| Repository method `readForOverview` (uses `submissions.list`, not `records.overview`) | `lib/data/repositories/smart_view_repository.dart:105,426-440` |
| SQLite table `sv_overview_cache` (migration 15) and its entry in scoped tables | `lib/data/db/app_database.dart:161-190` |
| Binding builds `SvOverviewCache` | `lib/features/smart_view/smart_view_binding.dart:11,29-31` |
| Tokens | `lib/core/theme/app_sv.dart:152` ("Overview" block) |
| Entry kinds | `lib/features/smart_view/models/smart_view_entry.dart`; `home_shell_controller.dart:80,217-236`; `command_runner.dart:179,198` |
| Debug | `lib/features/debug_smart_overview/` (3 files), `/debug/smartoverview` (`app_routes.dart:61`, `app_pages.dart:63-64,379-381`), `gallery_view.dart:89`, `lib/core/debug/seed_smart_view.dart` (overview parts) |
| Tests | `test/smart_view/sv_overview_test.dart`, `sv_overview_model_test.dart`, `sv_overview_screen_test.dart`, `smart_view_tab_test.dart`, `smart_view_navigation_test.dart`; goldens `sv_overview_{empty,loaded,loading}.png`, also touched: `smart_view_screen_test.dart` and `sv_support.dart` (check) |
| Docs | `mobile-handoff/smart-view-ui.md:168` ("Plan: the Overview is the landing page..."), CLAUDE.md "Before release" (`/debug/smartoverview`), `lib/features/smart_view` class doc |

**The previous flow** is commit `18a0090` ("smart view started"), before `a0701c0` ("before firebase") added the Overview. In `18a0090` `enter()` was: `tab` -> load the list, and if no view is open and the list is ready, **open the drawer**; `drawer` (`#view`) -> drawer open; `named` -> that view, drawer closed. Note: it resumed the **last open view** when one existed ("The tab alone: the last opened view, else the list"). Today `_resetTab()` drops the open view on every entry (`smart_view_controller.dart:210-212`). Question D.14.

### B.3 Approvals section

| Item | File |
|---|---|
| Screen, controller, binding, texts, reason controller | `lib/features/approvals/{approvals_view,approvals_controller,approvals_binding,approvals_texts,approval_reason_controller}.dart` (2 tabs: To review / Sent, `approvals_view.dart:74-83`) |
| Widgets | `widgets/approval_detail_sheet.dart`, `approval_reason_sheet.dart`, `approval_tile.dart` |
| Rules and reducer | `models/approval_rules.dart` (accept, reject, return, ignore; reason rule; resubmit only on reject of a submission), `models/approval_reducer.dart` |
| Model | `lib/data/models/approval.dart` (`Approval.tryParse`, `ApprovalPage.parse`, `canRespond`, `isPending`, `isSubmission`) |
| Repository (permanent service) | `lib/data/repositories/approval_repository.dart` (`req.list`, `req.respond`, events `request_created`/`request_resolved`, streams `changes`, `refreshes`; `SeedTasks` branch at `:105`); registered `lib/core/routes/initial_binding.dart:241` |
| Route | `app_routes.dart:28`, `app_pages.dart:6-7,292` |
| Entry points | My Workspace app-bar icon `workspace_view.dart:52-55` -> `workspace_controller.dart:130`; notification router `notification_router.dart:25,157-158,206-207,261-262,346` (`DestinationKind.approvals`); local notifications `local_notification_rules.dart:86-87`; notification texts `notification_texts.dart:32,67`; `/debug/tasks` (`debug_tasks_controller.dart:37`, `debug_tasks_binding.dart`) |
| Tests | `test/approvals/{approval_test,approval_rules_test,approval_reducer_test,approvals_controller_test}.dart`; notification tests that name approvals: `test/notifications/{notification_router,notification_style,local_notification_rules,local_notification_gaps,push_payload,real_replies}_test.dart`; `test/demo/demo_flow_test.dart` (check) |
| Badges / counts | **None found**: nothing reads `ApprovalRepository` except the Approvals controller and the debug screen (`grep` of `lib`). No "waiting for your decision" banner on mobile (not found). |
| My Workspace approval cards | **Not found.** `WorkspaceRepository` builds from `submissions.list` + `records.mine` (`workspace_repository.dart:246-252` skips tickets awaiting approval). |
| Deep links | `deep_link_service.dart:27` mentions "wait for approval" in a comment about joining an enterprise; no deep link opens Approvals. Enterprise `pending_approval` (`enterprise_switcher_controller.dart:76`, `enterprises_controller.dart:163,304,332`) is membership status, **not affected**. |
| Not approvals (do not touch) | Tickets/records "approval" wording in `tickets/*`, `smart_view/*` pills, `struct_records`, `form_card.dart`: these are record statuses. |

### B.4 Records, forms, models that the Inbox can reuse

| Need | Existing | Verdict |
|---|---|---|
| Record commands + names | `lib/data/records/record_commands.dart` (`mine, get, history, actions, status, send, targets, people, thread`) | Reuse; **add** `query`, `counts`, `queryPeople` (`records.people`), `peopleCards`, `inboxViews*` here only. |
| `structures` / record parsing | `lib/data/models/ticket.dart`, `record_state.dart`, `record_live.dart`, `struct_records.dart`; `records.mine` parsing in `TicketRepository`/`WorkspaceRepository` | Reuse the `records.mine` parser if `records.query` rows have the same shape (web uses one parser for both, `workItems.js:20,38`); confirm in D. |
| Card actions + menu | `lib/features/tickets/widgets/record_card_actions.dart`, `record_menu_rows.dart`, `models/card_menu.dart`, `models/record_card_rule.dart`; queue `RecordActionsQueue` (`record_actions_queue.dart`) | Reuse as is for the three-dot menu. Rate limit: see D.5. |
| Record screen | `lib/features/tickets/ticket_detail_*` | Reuse for "tap card opens record". |
| Approval cards, answer sheet | `approvals/widgets/approval_tile.dart`, `approval_reason_sheet.dart`, `approval_rules.dart` | Move into the Inbox feature (reuse logic, new layout). |
| Smart View engine/filters | `lib/data/smart_view/engine/` | Not for the Inbox (server does the filtering). |
| SQLite | no table for inbox records | Per CLAUDE.md "SQLite is the source of truth" would need a cache table; see D.6. |
| Avatars | `people_avatars` table | Extend for `people.cards` name/designation or keep in memory. |

### B.5 New chat and connections

| Item | File | Notes |
|---|---|---|
| Sheet, FAB | `lib/features/chats/widgets/new_chat_sheet.dart`, `new_chat_fab.dart` | |
| Controller | `lib/features/chats/new_chat_controller.dart` | Data sources: my DM conversations (local), `assoc.list` (connections, `:102`), `users.search {q}` after 350 ms debounce (`:141`, up to 20 hits, exact username/email/mobile in strict mode, by name in open mode). `GET /session` for `mode` (`:92`). |
| What it does for an unconnected person | `:171-190` | Shows text "isn't one of your connections yet... Connecting with someone isn't available in the app" (strict) or opens the DM anyway (open mode). **No connect button.** |
| `users.colleagues` | `lib/data/repositories/group_repository.dart:61` (New Group picker, 30 per page with `after`) | Exists; New chat does not use it. |
| `assoc.invite` | **not found** in `lib` | No call, no controller. |
| `req.list` type `associate` | `Approval` model (incoming/outgoing) | A connection request that **someone sent me** can be answered in the Approvals screen today; one I sent is only visible as outgoing there. |

---

## C. New chat with unconnected people (web behaviour)

Web: **Find people** (`W:CC/components/modals/FindPeopleModal.jsx`, via `usePeopleList.js`, also used by `PeoplePicker.jsx`).

- List: `users.colleagues {q, limit:30, after?}` -> `{people:[{username,name,designation,department,branch,avatar,status,connected,online}], hasMore, next}` (`B:core/sd_cmds_people.erl:149-185`). Sorted by name; `next` = opaque cursor `name\0username`; limit 1-50 (default 30). For an **employee or administrator** it returns **every active person the interaction rules allow** (`sd_policy:may_interact`), connected or not; anyone else gets only people they are already connected with (a customer cannot list staff). Hosts show only to the people they cover. `q` matches name, username, designation, department (case-insensitive substring).
- Extra: from **3 characters** and on the first page the web also calls `users.search {q}` and appends people not already listed (`usePeopleList.js:24-30`). `users.search` -> `{users:[<=20]}` with `canInteract` (interaction rules), `connected`, `canMessage` (`sd_cmds_people.erl:125-146`); strict orgs find only an **exact** username/email/mobile; open orgs search by name.
- Debounce 250 ms; sequence counter drops old answers (`usePeopleList.js:17,31`).
- Row: **Connected** badge + **Chat** button when `connected`; else **Connect** button (`FindPeopleModal.jsx:123-145`).
- Send request: `assoc.invite {to: <username|email|mobile>}` -> `{request}` (`B:core/sd_cmds_people.erl:88-99`, `B:people/sd_reqs.erl:56-73`). Errors: `invalid` (self), `not_found`, `already_associated` ("You're already connected."), `forbidden` (interaction rule, message from `sd_policy`), **`duplicate` ("An invitation is already pending.")**, `rate_limited`. Web shows a toast "Connection invitation sent" optimistically (`ChatModals.jsx:221-237`) and a failure toast; **no per-row "request sent" state** (the button stays "Connect").
- The receiver answers it as a request `type:"associate"` (`KIND` label "Connection request", `approvalCards.js:14`) via `req.respond accept`; on accept the web sends `#associates`. Connections change arrives as `associations_changed` (`ConnectumChatScreen.jsx:385` comment).
- **States**: the server gives only `connected` true/false. "Request sent" = an outgoing pending `associate` in `req.list` (`direction:"outgoing"`); "request received" = incoming pending `associate`/`membership` with `canRespond:true`. The web does not draw those two states; mobile can derive them from `req.list` (already loaded by `ApprovalRepository`). `duplicate` is the safety net.

**Mobile gap**: add `users.colleagues` (paged, reuse `GroupRepository.colleagues`) to New chat, show not-connected rows with a **Connect** button, add `assoc.invite`, derive sent/received from `req.list`, handle the six errors above, keep the strict-mode text when `canInteract:false`. Remove the "isn't available in the app" text.

---

## D. Gaps, decisions, questions

### D.1 Doc says "not checked / web only / ask the web owner"

| Item | Found |
|---|---|
| Exact call for **Return** | `req.respond {action:"return", reason (required), comment?}` (A.5). |
| Why button count differs from banner | Banner counts all pending incl. outgoing and ignores `canRespond` (A.6). |
| Card drag-resize, per-card sizes | Web only (`useCardSizes`, `cardSize.js`, localStorage); not needed. |
| "Refresh resets sizes" | web only. |
| Server-side text search | Not built (not found in `sd_recquery.erl`; no `q`/`text` arg). |

### D.2 Questions for BE / web

1. **`records.query` row shape.** Is `submissions[]` / `structures{}` identical to `records.mine`? (Web uses one parser, `workItems.js`.) Which fields are guaranteed: `holder, claimants, team.via, status, completion, actedBy, labels, externalId`? Does `structures[form]` always carry `status{field, final[]}` and `fields`?
2. **Counts vs list.** `records.counts` counts `me` as with + given only (`sd_actions.erl:1371,1386-1391`), but `records.query scope:["me"]` also includes records the person **made** (`candidates`, `:1353` `raised_by`). Header "All (n)" (`counts.all`) will not equal the list. Intended? Should mobile show `records.query.total` instead?
3. **No server text search.** Search on a phone over up to 1,000 per list x views is client side and only over loaded pages (Doc vs code #7). Can BE add `q` (or `text`) to `records.query` (subject/values/id)? If not, what is the supported way to search beyond the first pages?
4. **Page cost.** Each page call recomputes the full filter (A.4). Can `records.query` get a cursor/`after`, or a short server cache keyed by filter, so paging 5-10 pages is not 5-10 full runs?
5. **Rate budget.** Confirm the 30/10 s per connection is the same on the phone's `/ws` (not only `chat_web_send`) and that `/sd` frames from mobile count the same. Can mobile rely on `CHAT_RATE_LIMIT_MAX` being 30 on prod, or is it raised/lowered per deployment?
6. **Return and Decline on the web Inbox** have no reason box (Doc vs code #4). Is that a known web bug? Mobile will use its own sheet (reason required, 500 chars) unless told otherwise. Should mobile send `comment`?
7. **`req.list` paging.** Web reads only the first 200 (`status:"all"`). Is "all" meant to be bounded? Mobile will page with `limit/offset`; any objection to `hasMore` loops?
8. **Saved views contract.** (a) Name limit 40 (web UI) or 60 (server)? (b) May mobile write the same keys, including `folder:"data"`, `wheres`, `blocks`, `filters`, `sort`, `timing`? (c) Is `timing` shape `{from,to,...}` stable (`TIMING_ANY` fields not read here)? (d) Should mobile call `inbox.views.default` rather than `save {default:true}`? (e) Any `savedTs` conflict handling planned (two devices)?
9. **Approvals list on the web Inbox** excludes settled sign-ups (`HashInboxModal.jsx:75`); the Approvals dialog counts? Mobile will follow the Inbox rule. Confirm.
10. **Escalated approvals** (waiting > 3 days) are computed on the client from `ts` (`:281`), not by the server. Mobile will copy it. Confirm `ts` is the request's created time.
11. **Timeline.** Is Timeline meant to be `records.query` grouped by day, or the old `records.mine` lists? Mobile would group `records.query` results by day client side.
12. **Connections.** Does `users.colleagues` ever return `connected:false` rows that `assoc.invite` will refuse (`forbidden`) because of interaction rules? `colleagues` already filters by `may_interact`; `users.search` does not (it returns `canInteract`). Confirm that `canInteract:false` rows must show no Connect button.
13. **Request states for people.** Is there (or can there be) a field such as `requested: "sent"|"received"` on `users.colleagues` rows, to avoid joining with `req.list`?
14. **Smart View tab (owner decision, mobile).** "The tab opens with the drawer open": every time, or only when no view was open (as in `18a0090`, which resumed the last open view)? 
15. **`#inbox` on mobile.** Should it select the Inbox tab (like `#view` selects Smart View)? Today it only pops to the first route.
16. **Reminders, broadcasts, "My submissions"** (web Inbox folders). The doc's single list has approvals and reminders; the four requested changes do not mention broadcasts or reminders. Include reminders in phase 2/3? (Needs `loadInbox("reminders")` source; not read in this recon.)

### D.3 Risks

| Risk | Detail | Mitigation |
|---|---|---|
| Rate limit | 30/10 s shared by chat sends, Smart View, record-actions queue, Inbox. Web open burst is 12-16 commands. Each card asks `record.actions` (queue allows 8/10 s). | One shared command gate; Inbox open = `records.query` + `records.counts` + `people.cards` (+ `req.list`) only; drop `records.mine`; facets only when the panel is open; keep 300 ms gaps. |
| 1,000 cap | Each underlying list is read to 1,000; `capped:true`; `counts.cap` 1000 (`cap+1` = "1000+"). | Show "1000+" and a capped note; do not promise exact totals. |
| Large lists on phones | Up to 200 per page, `structures` per page, many values per row. | Page 50-100; lazy build; memory only or small cache; drop images. |
| Search reach | Client side over loaded pages only. | Say so in UI ("searching loaded records") or get D.2-3. |
| Offline | CLAUDE.md: SQLite is the UI source and cached-first screens never show offline state. Inbox data is not cached today. | Decide: memory only (like Smart View rows) or new cache table. Recommend memory + last-answer snapshot for the offline bar; needs owner decision. |
| Unused SQLite | `sv_overview_cache` (migration 15, `app_database.dart:164`) becomes unused. A table drop needs a new migration; `_scopedTables` list must be updated (wipe on sign out). | New migration that drops it (or leave it unused, wiped by scope). |
| Approvals deletion | `ApprovalRepository` is permanent and also feeds `/debug/tasks` and `SeedTasks`. | Keep the repository; delete only the screen/route/tab UI. |
| Notifications | `approvals` category/destination routes to `/approvals` (`notification_router.dart:157,206,261`) | Re-point to the Inbox with the approvals view before deleting the route. |
| Web-compat for saved views | Mobile and web share `inbox.views.*` | Round-trip tests with web-shaped fixtures. |
| Out-of-order | Web protects only query and facets (A.8). | Sequence counter on every Inbox read on mobile. |

---

## E. Build plan

Order kept as suggested, with two adjustments: (a) a **shared command gate** goes into phase 2, (b) the `#inbox`/`#view` switch is built in phase 2 (it only needs the Inbox tab to exist). Each phase leaves the app shippable. `flutter build apk --debug` after each (CLAUDE.md); no tests run unless asked.

Size key: S < 1 day, M 1-3 days, L > 3 days.

| # | Phase | Size | Needs BE/web answer first? |
|---|---|---|---|
| 1 | Remove Overview, restore Smart View tab flow | S-M | No (D.14 only decides resume vs always-drawer; default: drawer open when no view open) |
| 2 | Inbox list + cards, Me / Team, `#inbox`/`#view` switch, shared gate | L | Soft: D.2-1, D.2-2 (assume `records.mine` shape; show `total`) |
| 3 | Filter panel + facets | M-L | No (D.2-3 is optional) |
| 4 | Approvals button + actions in Inbox, then delete old Approvals section | M | No (D.2-6 `comment` optional) |
| 5 | Saved views | M | **Yes**: D.2-8 (name length, key contract) |
| 6 | Live updates | S-M | No |
| 7 | New chat with unconnected people + connection requests | M | Soft: D.2-12/13; works with `users.colleagues` + `assoc.invite` + `req.list` |

### Phase 1: Remove Overview, restore the drawer-first tab (S-M)

- **Touch**: `smart_view_controller.dart` (drop `overview*`, `isOverview`, `showOverview`, `_refreshOverview`, `onReselect` Overview branch; restore `enter()` per `18a0090`: tab -> list, open drawer when no view open; `title` fallback), `smart_view_view.dart` (remove `_Overview`, keep list/table), `smart_view_drawer.dart` (remove "Overview" row), delete `sv_overview_body.dart`, `sv_overview_card.dart`, `models/sv_overview_model.dart`, `lib/data/smart_view/overview/`, `readForOverview` in `smart_view_repository.dart`, `smart_view_binding.dart` cache wiring, `app_sv.dart` Overview tokens, debug route + `debug_smart_overview/` + `gallery_view.dart:89` + `app_routes/app_pages` entries + seed parts, CLAUDE.md before-release line and `mobile-handoff/smart-view-ui.md:168`. SQLite: new migration dropping `sv_overview_cache`, remove from `_scopedTables`.
- **Tests**: delete the 5 Overview tests and 3 goldens; update `smart_view_tab_test.dart`, `smart_view_navigation_test.dart`, `smart_view_screen_test.dart`/`sv_support.dart` (check) to the drawer-first flow; add a test for `enter()` x3 kinds and for the migration.
- **Risks**: back-button logic (`canLeave`, `:285-292`) was written around Overview; DB downgrade/upgrade path; users with a cached overview.
- **Phone check**: tap Smart View tab -> drawer open with list; pick a view -> table; tap the tab icon again; `#view` -> drawer; `#view <name>` -> that view, drawer closed; back closes drawer first; offline: list from memory or offline state as before; airplane mode mid-open.

### Phase 2: Inbox list and cards, Me / Team (L)

- **Touch**: `record_commands.dart` (+ `query`, `counts`, `queryPeople`, `peopleCards`); new `lib/data/repositories/inbox_repository.dart` (one class; `records.query` paging, `records.counts`, sequence counter, `capped`); a shared command gate (replace `SvLimits` 6 and align `RecordActionsQueue`; budget < 30, e.g. 12-15/10 s, one place); models in `lib/features/inbox/models/` (row from record, `RecordState` colour rule = `recordState()` port, priority from `SIGNAL_FIELD` + level words); rewrite `inbox_controller/view/binding` (Me/Team switch, "My Team" only if `reports > 0`, cards grid 1 column, load more, `AppStateView`, `AppRefresh`); `people.cards` into `people_avatars`; reuse `RecordCardActions`/menu and ticket detail; `command_runner.dart:221` select the Inbox tab; `home_shell` entry for the inbox tab.
- **Rules to copy**: state colours (A.1), priority dot, status chip = live status else "Waiting for approval", "read-only" = no menu items when `record.actions` returns none, 24-card chunking (not needed: use a lazy list).
- **Tests** (when asked): state/priority unit tests with the web vectors in `W:tests/frontend/inboxFilters.test.mjs`/`inboxQuery.test.mjs` (read them first), repository paging + out-of-order, controller states (loading/empty/error/offline), `#inbox` routing, golden for a card in each state.
- **Risks**: rate gate shared; no cache -> offline behaviour (D.3); `records.query` cost per page; `structures` shape (D.2-1); tablet vs phone not in scope.
- **Phone check**: open Inbox: one column, newest first; Me/Team; scroll to load more; pull to refresh; card colours for each of the five states; priority dot; three-dot menu shows only allowed items; a report's record has no actions; capped list shows "1000+"; airplane mode: last list stays with the offline bar; `#inbox` from a chat; `#view` then `#inbox` back and forth keeps each tab's state.

### Phase 3: Filter panel and facets (M-L)

- **Touch**: `inbox_filter_sheet.dart` (bottom sheet, Apply/Clear, count badge), draft model `InboxFilter` with `queryArgs()` and `serverViews()` ports (A.2, A.3), facets call (`facets:true, limit:1`, 150 ms wait, group key, counts "Counting the forms..."), people multi-selects with `peopleChoices`, date range, sort (client side orders + status), advanced blocks (10 / 20 limits, conditions only for one form, operator tables by field kind from the structure).
- **Tests**: port `inboxQuery.test.mjs` cases (union, requests view, 50-name cap, empty block dropped, between needs two values); drop-chosen-when-no-records rule.
- **Risks**: field kinds need `structures[form]` field types (may need `tstruct` definition reads: more commands); big panel on a phone.
- **Phone check**: choose Me + Requests = union; Timeline is exclusive; Data list counts add up; choose a person -> forms narrow; date range with nothing -> "No records match the filter."; Tagged to; advanced block with a condition on one form; Apply/Clear; offline panel shows error line.

### Phase 4: Approvals button and actions, then delete the old section (M)

- **Touch (add)**: Approvals button with count (= pending and `canRespond`), pane with All/Pending/Approved/Rejected/Closed dropdown and search, approval cards (reuse `approval_tile.dart`, `approval_rules.dart`, `approval_reason_sheet.dart`), `ApprovalRepository` unchanged (maybe expose a count stream); reason sheet for Decline/Return of a form (this is where mobile goes beyond web, D.2-6).
- **Touch (delete, after the Inbox path works)**: `lib/features/approvals/` screen/binding/controller/view/widgets that are replaced; route `/approvals` + `app_pages.dart:292`; Workspace app-bar icon (`workspace_view.dart:52-55`, `workspace_controller.dart:130`) -> open Inbox with the approvals pane or remove; notifications (`notification_router.dart`, `local_notification_rules.dart`) -> Inbox approvals; debug tasks screen; tests in `test/approvals/` moved/updated; keep `Approval` model and repository.
- **Tests**: rules (who sees which buttons), count rule vs banner rule, reason required, resubmit flag only on reject, answer then `req.list` again.
- **Risks**: do not count outgoing requests in the badge (the web banner mistake); notification taps while the route is gone; the Inbox answer dead-end seen on web (D.2-6).
- **Phone check**: badge number equals "Waiting for you" cards; Approve -> card leaves, list re-read; Decline of a form asks for a reason; Return; connection request approve; button again returns to the list; notification tap opens the Inbox on approvals; applying a filter closes the pane.

### Phase 5: Saved views (M)

- **Touch**: repository calls `inbox.views.get/save/delete/default`; `InboxView` model with `setupOf`/`restoreOf` ports (A.7); Views menu sheet; "Save your changes?" on leaving a changed view (back, tab switch, view switch); Default View rule.
- **Tests**: restore from web-shaped fixtures (unknown folder -> `data`, one `wheres` entry ignored), 20-view limit, name rule, `invalid` error shown, setup key equality.
- **Risks**: shared with web (D.2-8); 20,000-byte limit not predictable (surface the server message); last-write-wins.
- **Phone check**: save, rename by "Save as new", set default, kill app, reopen -> opens on default; change filter, press back -> "Save your changes?"; remove asks first; a view saved on web opens on the phone.

### Phase 6: Live updates (S-M)

- **Touch**: subscribe to events `submissions_changed, submission_approved, submission_rejected, ticket_assigned, task_*, submission_notice, resync` (and `request_created`/`request_resolved` for approvals); one 150-300 ms debounce; re-read = `records.query` (as many as shown, <= 200) + `records.counts` + `req.list`; sequence counters; failed re-read keeps the list.
- **Tests**: burst -> one read; stale answer dropped; reconnect -> `resync`.
- **Risks**: event storms vs rate gate; re-reading 200 records on every event on mobile data.
- **Phone check**: change a record on web -> card updates quietly; approve on web -> badge changes; network off/on -> everything re-read once.

### Phase 7: New chat with unconnected people (M)

- **Touch**: `new_chat_controller.dart` (+ `users.colleagues` paging reuse from `GroupRepository`, `users.search` for >= 3 chars, 250 ms debounce, sequence counter), `new_chat_sheet.dart` rows (Connected/Chat vs Connect / Request sent / Respond), new `assoc.invite` call (command name in one place), derive sent/received from `ApprovalRepository` list, error mapping (`duplicate`, `already_associated`, `forbidden`, `not_found`, `invalid`, `rate_limited`), refresh on `associations_changed`/`request_resolved`.
- **Tests**: controller states per row, error mapping, strict-mode text only when `canInteract:false`.
- **Risks**: strict orgs list only connected people for non-employees (so the list can be short: show that clearly); duplicate invitations; spam taps (disable button while sending).
- **Phone check**: type 3+ letters: connected and unconnected people listed; tap Connect -> "Request sent", button disabled; tap again after restart -> `duplicate` message handled; other user accepts -> row becomes Chat; employee vs customer account; offline.

**Can start before BE answers**: 1, 2, 3, 4, 6, 7 (with the assumptions above). **Should wait for an answer**: 5 (saved-view contract, D.2-8). **Optional BE work that would improve it**: D.2-3 (server search), D.2-4 (page cost), D.2-13 (request state on people rows).
