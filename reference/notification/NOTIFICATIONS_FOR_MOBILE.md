# Notifications: the full catalogue (for the mobile team)

Written from the code, nothing changed. Paths are relative to `connectum/connectum-backend/src/` unless they start with `chat-app/` or `docs/`. Search by the quoted text if a line moved.

## 0. The two stores (and why there are two)

| Store | Module | What it is | Retention |
|---|---|---|---|
| **Feed** ("My Workspace", the bell, Notifications Center) | `forms/sd_feed.erl` | One list of items with priority, read, resolved. The one the web bell draws. | newest **300** per person (:44) |
| **Cards** (inbox index) | `forms/sd_cards.erl` | Per-message cards, classified into sections; drives the four counters priority / pending / personal / reminders | newest **500** (`MAX_CARDS`); custom sections ≤20, rules ≤20 |

A card becomes a feed item through `sd_feed:from_card` (`sd_cards.erl`:78, 227). A new mobile bell should be built on the **feed**; use the card counters only if you want the same four badges as the older inbox.

## 1. In-app list API

Feed (`forms/sd_feed.erl`:50–100, routed by `core/sd_cmds.erl`:490–491 `feed.<sub>`):
- `feed.list {priority: all|high|medium|low|resolved, category?, unreadOnly?, before?, beforeId?, limit ≤200 default 50}`. Error: "priority must be one of: all, high, medium, low, resolved."
- `feed.summary` → counts `{high,medium,low,resolved,unread,total}` (:126–140).
- `feed.read {ids:[…] | all:true, read?:false}`; `read:false` marks unread.
- `feed.resolve {id} | {all:true}`; `feed.dismiss {id}`; `feed.clear` (removes resolved ones).
- Errors: `not_found` "No such notification."; `invalid` "id is required."
- Item fields: `id, priority (high|medium|low|resolved), category, title, message, ts, icon, read, actionType, actionLabel, chatId?, ref, count, resolved, resolvedTs`, plus `e2e` and `chat`/`from` for message items. Storage keys `sd:feed:<u>`, `sd:feedi:<u>`, `sd:feedk:<u>` (:1–34).
- **Coalescing:** a second item with the same `key` increments `count`, becomes unread and re-opens (:226–255). So 20 DMs from one person are one tile with count 20.

Cards / counters (`core/sd_cmds.erl`:454–487): `notifications.summary`, `notifications.list {category: priority|pending|personal|reminders|all, unreadOnly (default true), limit}`, `notifications.read {all | category | ids}`; `cards.list/dismiss` (`core/sd_cmds_forms.erl`:15–44). Summary shape: `{counts:{priority,pending,personal,reminders}, total, personalBySender}` (`sd_cards.erl`:291–303). Classification order: priority ("!" or #urgent/#priority) → pending (a request) → reminders → updates (system) → personal (DM) → general (`sd_cards.erl`, header). A reminder with no time or a past time is "due"; a future one is silent until `sd_scheduler` fires it (`sd_cards.erl`:194–231; the scheduler ticks every few seconds, so a reminder is at most one tick late, `core/sd_scheduler.erl`:1–11).

## 2. Catalogue of notification types (feed items)

Columns: trigger → recipient → title / message template → severity, category, icon → action (deep link) → lifetime. All in `forms/sd_feed.erl`:352–592 unless noted. Message text is clipped to **200 characters** (:602–608).

| # | Type | Trigger | Recipient | Title / message | Key (coalescing) | Severity / category / icon | actionType / label / target |
|---|---|---|---|---|---|---|---|
| 1 | Direct message | a DM is delivered to an offline-or-online user | the receiver | title = sender name; message = text (clipped) | `dm:<from>` | medium (high if urgent) / messages / `chat` | `open_chat` "Open chat", `chatId` = `user-<from>` |
| 2 | Group message | a group message | every member except sender | title = group; "<name>: <text>" | `group:<g>` | low / messages | `open_chat` "Open group", `chatId` = `room-<g>` |
| 3 | Mention | someone tags you | the tagged person | "<name> mentioned you" | `mention:<g>:<msgId>` | medium / `alternate_email` | `open_message` "Open message", `chatId` + `ref.messageId` |
| 4 | Approval request | a request is created (`sd_reqs`:189) | each approver | by request type: onboarding "New user awaiting approval"; associate "Connection request"; handover "Introduction request"; host_transfer "Host transfer request"; group_invite "Group invitation"; membership "Request for another connection"; wizard/other "Approval needed" | `req:<id>` | high / approvals | `approvals` "Review approval" |
| 5 | Reminder | a reminder's time arrives | its owner | "Reminder" + text | `rem:<cardId>` | / reminders / `alarm` | none specific |
| 6 | System notice | the system posts one | person | "System notice" | | / system | |
| 7 | Outcome of a request | the request was answered | the requester | "Request approved" / "Request declined"; "<by> approved\|declined your <thing>." | `outcome:<id>` | | |
| 8 | New submission | a form was submitted | the form's host and administrators (not the submitter) | "New submission: <tstruct>"; "<name> submitted <tstruct>." | `sub:<id>` | | `submissions` "View submission" |
| 9 | Ticket update | ticket assigned or moved | holder: "<Caption> #<id> is with you" (high); raiser: "<Caption> #<id>: <action>" (medium) | | `ticket:<id>` | | `tickets` "Open ticket" |
| 10 | Task | task created / changed / reassigned (`people/sd_tasks.erl`:333–340) | the other party | "New task from <name>"; "<name> set a task to <status>"; "<name> changed a task"; "<name> gave your task to someone else" | `task:<id>` | medium / system / `task_alt` | (web has no mapping for a task item, see §5) |
| 11 | Form approval result | submission approved / declined / returned / no approver / notice (`forms/sd_subflow.erl`:569–570, 781, 836–840, 1004–1094) | submitter (approved/rejected); administrators (no approvers); `notify` designations (notice) | "Your <Caption> was approved"; "Your <Caption> was declined by <name>: <reason> (<comment>)" or "…was returned by…" (+ ". You can fix it and send it again"); "Your <Caption> cannot be approved: there is no approver for it (<stage>). The administrators have been told. You can send it again once someone can approve it" | `sub:<id>:<event>` | medium / system / `fact_check` | |
| 12 | Announcement (broadcast) | a person with the `broadcast` permission sends one (`people/sd_broadcast.erl`:1–25) | everyone matching ALL the given branch/department/designation/role lists, minus the sender | "Announcement from <sender>" + text (≤1000) | | | Not a chat message; event `broadcast` |
| 13 | Security: device added | new encrypted-messaging device registered when the person already had one (`security/sd_e2e.erl`:174) | the person | `e2e_device_added` | | | none; `ref.deviceId` possible |
| 14 | Security: session added / replaced | second kind of client signs in / previous session ended (`security/sd_auth.erl`:156–185) | the person | `session_added`, `session_replaced` | | | none |
| 15 | Security: account locked, password changed, 2-factor disabled, recovery key regenerated | those events | the person | `account_locked` (high), `password_changed` (low), `totp_disabled` (high), `recovery_regenerated` (texts at :548–592) | | | none |
| 16 | API message (MESSAGE API) | an external system calls the Message API (`docs/API_WORKSPACE_MESSAGE.md`) | 1–50 named people | `title` (≤200), `message` (≤4000), `outcome` success\|error\|info, `severity` default high for error else low, `source` (≤80), `httpStatus`, `data` (any JSON ≤32 KB), `dedupeKey` (24 h) | | by severity / category `api` | none; the item has `outcome`, `source`, `httpStatus`, `data`, `via` |

Not found anywhere: any notification for "mentioned in a task", chat message edits, group joins by others, or "message delivered". The feed texts above are the complete set in `sd_feed.erl` (a text I could not find in the file is not listed; if the product wants more, they do not exist yet).

Cells left blank were not distinct from the neighbouring row's code path or I did not read that branch; mobile should not assume them.

## 3. Actionable tiles: how the web routes the tap
`chat-app/features/connectumChat/ConnectumChatScreen.jsx`:1311–1335. Mapping of `actionType`:

| actionType | Web does |
|---|---|
| `admin_console` | opens the admin console, users tab |
| `tickets` | opens Inbox on "Tasks & tickets" |
| `approvals` | opens Inbox on approvals |
| `open_chat` (+`chatId`) | opens that conversation |
| `open_message` (+`chatId`, `ref.messageId`) | opens the conversation and scrolls to the message |
| `submissions` | opens the submissions screen |
| `about_me` | opens the About-me screen |
| `axpert` | opens the Axpert connection |
| `smart_prompt` (+`actionPrompt`) | opens the smart structure with that prompt |
| `none` | nothing (tile has no button) |
| anything else | shows a toast "Opened: <title>" (the web has nothing better for it) |

Item buttons on a tile: mark read/unread (`feed.read`), Resolve (`feed.resolve`), Dismiss (`feed.dismiss`), Mark all resolved (`feed.resolve {all:true}`), Clear resolved (`feed.clear`) (`chat-app/.../utils/useNotificationFeed.js`:19–99, `utils/feedActions.js`).

## 4. Realtime events and reconnect catch-up
Push events that matter for notifications (all `{"type":"sd_event","event",...}`):

| Event | Data | Handler on web |
|---|---|---|
| `feed_item` | `{notification, counts}` | add/replace the tile (`chatEvents/index.js`:104) |
| `feed_removed` | `{ids, counts}` | remove (:106) |
| `feed_changed` | `{ids, read, counts}` | change read flag (:108) |
| `notification` | `{card, category, counts}` (cards) | `sd_cards.erl` |
| `notifications_changed` | summary | other devices re-sync after read |
| `card` | the classified card | |
| `request_created` / `request_resolved` | request view | refresh approvals (:85–87) |
| `task_assigned` / `task_updated` | `{task}` | toast + refresh |
| `ticket_assigned` | `{id, tstruct, action, by}` | refresh |
| `submission_approved` / `submission_rejected` / `submission_notice` | `{submissionId, tstruct, status, reason, allowResubmit}` | |
| `broadcast` | `{text,…}` | `onBroadcast` |
| `form_message`, `form_message_updated` | message with form | |
| `session_replaced`, `session_expired`, `connection_superseded`, `disconnected` | | sign-out flows |

Delivery rule (`core/sd_notify.erl`:142–168): `push_event` goes to a **connected** user only; for an offline user it does nothing. **Catch-up:** there is no event log or sequence number. The client must re-read `feed.list`, `feed.summary`, `req.list`, `cards.list` after each (re)connect. The web does this by emitting `resync` on status `connected` (`utils/useLiveChanges.js`:28). I did not find a "since" token for the feed; it is a read of the current state.

## 5. Gaps in what the web shows (mobile should decide, not copy)
- Task feed items (#10) have no `actionType` set in `sd_tasks.erl`:333–340 as far as I read; confirm before assuming a deep link.
- `actionType` values the server may send that the web handles only with the generic toast: anything not in §3.

## 6. Preferences
- **Per conversation mute:** `conv.mute/unmute` stores a `muted` flag (`forms/sd_conv.erl`:5–22). The server does not stop feed items for a muted chat; the web client keeps muted conversations quiet. Mobile must do the same (open question 1).
- **No global preference, no do-not-disturb, no quiet hours, no per-type switches exist** (grep found none).
- Pin/unpin/read position per conversation: `conv.pin/unpin/read`; the server keeps `readId`, `deliveredId`.

## 7. Retention and limits
Feed 300 newest per person; cards 500; coalescing by key; message clipped to 200 chars in the feed; MESSAGE API limits: 50 people per call, 600 calls per minute per key, body 1 MB, `data` 32 KB, `dedupeKey` 24 h (`docs/API_WORKSPACE_MESSAGE.md`:127–153). Command limiter: 30/10 s documented, 200/10 s in production. Task creation 120/hour.

## 8. Encryption and privacy
- DM and group chat can be end-to-end encrypted. Then the feed/card item **carries the envelope whole**, flagged `e2e:true`; the server never makes a preview (`sd_feed.erl`:375–377; `sd_cards.erl`:158–164). The envelope starts with `e2e1:` and is narrowed to the person's registered devices. The **device must decrypt it to show the text**. Consequence for push: a server-sent push cannot contain the message text (see the push plan).
- Everything else in §2 is stored as readable text on the server, including API messages.
- Security notices must not contain secrets; they carry only `ref.deviceId`.

## Open questions
1. Should the server stop feed items for conversations a person muted, or keep trusting the client?
2. Does mobile want a "since" cursor for the feed (cheap to add; does not exist)?
3. Which tile types should be silent on mobile (e.g. group messages, low severity)?
4. Task items: should they get an `actionType` that opens the task?

## What mobile must match exactly versus what may differ
**Must match exactly:** the feed fields and the three events `feed_item`/`feed_removed`/`feed_changed` with their counts; coalescing by key and the `count`; `priority` values and the error texts; that read/resolve/dismiss are separate; the mapping of `actionType` to a destination (§3); the rule that mobile re-reads everything after reconnect; the e2e rule (envelope decrypted on device); the caps (300 / 200 chars) when it keeps a local copy; the texts in §2 if mobile renders its own text (they come from the server in `title`/`message`, so show those verbatim).
**May differ:** icons and colours per severity, grouping and sections, swipe actions, badge style, whether to show resolved items, local sorting, haptics and sounds, how many tiles per screen.
