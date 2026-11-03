# Creating a group chat

Read-only investigation, 2 Nov 2026. Sources: backend and web chat client on `origin/main` of `~/Development/Axi-apps/connectum` (commit `3063d3ed`, nothing modified). Backend paths are under `connectum-backend/src/`, web paths under `chat-app/`. Group messaging itself (send, history, receipts) is already in `websocket-protocol.md` and `messages-and-receipts.md`; this file covers only **creating** a group and adding people. What the code does not answer is in section 6.

## 1. The web flow and the exact commands

There is **no "create group with members" command and no REST endpoint**. A group is created and filled by plain WebSocket lines, one command each:

1. `/creategroup <name>`: makes the group; the caller becomes its **owner/admin** and its only member.
2. `/addmember <group> <username>`: once per person, owner only.

The web sends exactly that, back to back, without waiting for any reply (`chat-app/features/connectumChat/components/ChatModals.jsx:243-262`, via `connectumSocket.sendCreateGroup` / `sendAddMember`, `chat-app/services/connectumSocket.js:703-712`). The same two commands are also the `#creategroup <name>` / `#newgroup` and `#addmember <group> <user>` / `#invitegroup` hash commands (`chat/chat_cmds.erl:84-89`); `chat_cmds` rewrites them to the slash lines.

### 1.1 The screen

`NewGroupModal.jsx`: a "Group name" field (32-char counter, `maxLength=32`, client check "Please enter a group name." / "at most 32 characters", `NewGroupModal.jsx:9-14`) and an "Add people" `PeoplePicker` (`:72`). Members are optional (a group of one can be created). Before sending, the web strips control characters, collapses whitespace runs to one space, trims and cuts to 32 (`ChatModals.jsx:248-249`).

The people list comes from `/sd users.colleagues {q?, after?, limit?(1..50, default 30)}` (`chat-app/features/connectumChat/components/PeoplePicker.jsx:19-33`, backend `core/sd_cmds_people.erl:139-171`). **This call is not in our handoff docs yet.** Reply: `{people:[{username,name,designation,department,branch,avatar,status,connected,online}], hasMore, next}`; `next` is an opaque cursor to pass as `after`; sorted by name; `connected` = already associated with me; `online`. Who is listed: for an employee or admin, every active person the organisation's interaction rules allow; for anyone else (a customer) only their connections. A 250 ms-debounced query `q` filters by name, username, designation or department. When the query has 3+ characters the web also calls `users.search {q}` and appends extra people not already listed, tagged "Invite" when not connected (`PeoplePicker.jsx:34-39`; `users.search` is in `websocket-protocol.md` line 267).

### 1.2 Rules for the name

| Rule | Where |
|---|---|
| Max **32** characters (`MAX_GROUP_NAME_LEN`); longer: `{"type":"error","text":"Group name too long (max 32 chars)"}` | `chat.hrl:5`, `http/chat_web.erl:883-885` |
| Spaces allowed inside (`design team`); runs of spaces collapse to one; leading/trailing trimmed | `chat_web.erl:878` |
| Empty: `error` "Usage: /creategroup <name>" | `chat_web.erl:879-881` |
| No control characters: `error` "Group name cannot contain control characters" | `chat_web.erl:886-890` |
| Unique **case-sensitively** inside the organisation: `error` "A group with that name already exists" | `chat_web.erl:891-896`, `chat_groups.erl:94-97` |
| No name may be a whole-word prefix of another, in either direction (`design` vs `design team`): `error` "That name is too close to an existing group's name (one starts with the other)". Case-sensitive. Exists because commands find the group by longest-matching name in `/groupmsg design team hi` | `chat_names.erl:28-29`, `chat_web.erl:891-896` |
| No other character restriction found (no check for `/`, `#`, `:` or emoji). The name is later used in `conv` ids (`group:<name>`), `/history group <name>` and `/groupmsg <name> <text>` | none in code, see Q4 |

Groups are scoped to the organisation (`sd_ent:srv(chat_groups)` per enterprise, `chat_groups.erl:27-31`). The name is the group's only identity: there is no id, no avatar, no description, no rename, no delete.

### 1.3 Who may create, who may add, and limits

| Rule | Detail | Code |
|---|---|---|
| Create | Open server: anyone. Strict Connectum org: any **registered, active** user (employee or external): `error` code `not_allowed` "Only registered users can create groups." / "Only active users can create groups." | `people/sd_policy.erl:363-376` |
| Add | **Only the group's creator** may add. Another member gets `error` code `not_allowed` "Only the group admin (<owner>) can add members" (checked first, before any other rule) | `chat_web.erl:911-923`, `chat_groups.erl:118-119` |
| Add: open server | the person must be online now, or have connected before; else `error` "<user> isn't online right now" | `chat_groups.erl:123-133` |
| Add: strict org | `sd_policy:group_add` (`sd_policy.erl:379-421`): unknown user "No such user: x"; the org's interaction rules (`may_interact`) can refuse with their own text (`not_allowed`); an **admin, the person's host, or someone already connected** adds directly; **anyone else gets an invitation** that the invitee must accept (section 2.2) | `sd_policy.erl:385-421` |
| Duplicate | `error` "<user> is already in the group" | `chat_web.erl:240`, `chat_groups.erl:120-121` |
| Size | **No member cap in the group registry** (no limit in `chat_groups.erl`). The only cap is 200 members for encryption (section 3) | |
| Number of groups | no limit found | |
| Pace | WebSocket commands are limited to **30 per 10 s per connection** (`chat.hrl:13-14`); the 31st line gets `{"type":"error","text":"Too many commands -- slow down"}` and is **dropped, not queued** (`chat_web.erl:560-571`). The web sends create + N adds with no pacing, so more than ~29 members in one go silently loses the rest | |
| No `cid` | `/creategroup` and `/addmember` are **not** in the `/c <cid>` list (`chat_web.erl:1068-1069`: only `/msg /replydm /groupmsg /replygroup /hostmsg`); a `/c` wrapper on them returns `cid_unsupported`. So there is no server-side idempotency: a retry of `/creategroup` answers "already exists", which is also what an earlier success looks like | |
| After creating | no remove-member, rename, delete-group or transfer-owner command exists. A member can `/leavegroup`. When the **last** member leaves the group is deleted. If the owner leaves, the group stays and keeps that owner name, so **nobody can add anyone any more** | `chat_groups.erl:166-188` |

## 2. What the server returns and pushes

All events are plain WebSocket JSON frames (shapes also in `websocket-protocol.md` lines 98-107, verified against `http/chat_web_send.erl:88-125`).

### 2.1 To the creator

| Step | Event | Detail |
|---|---|---|
| `/creategroup` ok | `{"type":"group_created","name":"design team","owner":"alice","members":["alice"]}` | one member, the caller. No other member is told (there are none). `chat_web.erl:877-909`, `chat_web_send.erl:88-93` |
| `/creategroup` fail | `{"type":"error","text":"..."}` (plain) or `{"type":"error","code":"not_allowed","text":"..."}` | texts in 1.2/1.3 |
| each `/addmember` ok | **the same `group_created` event** with the full new member list (`members` sorted, `lists:usort`) | the web only treats a `group_created` with `members.length <= 1` as "new group, open it" (`chat-app/.../chatEvents/groups.js:75-79`). Mobile must do the same (or track the name it just asked for) |
| `/addmember` pending (strict, not connected) | `{"type":"group_invite_pending","group":"g","user":"bob","request":{...request view}}` | the person is **not** added; web toast "Invitation sent. <name> will be added to <group> when they accept." (`groups.js:46-50`). `request.subjectName` is the display name |
| `/addmember` fail | `{"type":"error","text":...}` / `code:"not_allowed"` | Texts: "No such group: x", "You're not in that group", "Only the group admin can add members", "<u> is already in the group", "<u> isn't online right now" |

Order matters: the server handles lines in the order they arrive on one connection, so create-then-add is safe without waiting for `group_created`. Replies come in the same order, interleaved with other traffic; nothing carries a request id, so a client must match replies to its own pending commands by order/type (`command_repository._sendRaw` already does this for `#` commands, `lib/data/repositories/command_repository.dart:319-351`).

### 2.2 To the people added

| Case | What they get |
|---|---|
| Added directly and **online** | `{"type":"added_to_group","name":"g","owner":"alice","members":["alice","bob"],"by":"alice"}` (`chat_groups.erl:134-136`, `chat_web_send.erl:118-124`). Web shows a toast and a new chat row "Added by alice", unread 1 (`groups.js:82-110`) |
| Added directly and **offline** | nothing on the socket. A workspace feed item: title "Added to a group", message "<inviter> added you to the group <g>.", icon `group_add`, key `group:<g>` (`chat_groups.erl:300-311`); the group is in `/groups` the next time they connect |
| Invited (strict, not connected) | a **request** of type `group_invite` in their `req.list` / feed, text "<from> invites <you> to a group" (`sd_reqs.erl:136-142`, `206`, `chat_cmds.erl:672`). They answer with `req.respond` (accept / reject); on accept the server adds them with `force_add` (`sd_reqs.erl:452-459`): if they are online they get `added_to_group` (`chat_groups.erl:155-158`), existing members get the `group_system` line below. Rejecting does nothing visible to the group. The inviter gets no `group_created` at that moment, only whatever generic request-response notification exists (Q6) |
| Not added | nothing |

### 2.3 To the existing members

`{"type":"group_system","group":"g","text":"alice added bob to the group"}` (direct add, `chat_groups.erl:138-139`), `"bob was added to the group"` (added through an accepted invite or a form, `chat_groups.erl:160-161`), `"bob left the group"` (leave, `:176-177`). Sent to the members that were in the group *before* the change (so the new person does not get it), online ones only. It is a plain event, **not a stored chat message**: it never appears in `/history`. The web parses "X added Y to the group" to update its member list; mobile should rather refresh with `/groups` (full `members` and `owner`).

### 2.4 Reading groups afterwards

`/groups` → `{"type":"groups","list":[{"name","owner","members":[...]}]}` (`chat_web_send.erl:126-`). This is how a phone learns the group after a reconnect. It carries `owner`, which this app does not store today (see 4.1).

`/leavegroup <group>` → `{"type":"left_group","text":"<group>"}` to the leaver.

## 3. Encryption for a newly created group

**There is no extra step when creating a group.** Encryption is per message, not per group:
- A group has no key, no key exchange, no "encrypted" flag set at creation. Nothing in `/creategroup`, `/addmember` or the events mentions e2e (`chat_groups.erl` has no e2e code).
- A group's e2e status is decided at send time by the **sender's app**. With server mode `optional` a send is encrypted when the client chooses to (the web does when every member has a device, `connectumSocket.e2e.canEncrypt('group', name)`); with `required` a plain send is refused `e2e_required` (`security/sd_e2e.erl:420-427`).
- To encrypt, the sender calls `/sd e2e.group_devices {group}` and wraps the message key for **every device of every current member** (`sd_e2e.erl:383-399`; web `e2eClient.js:293-296`). The server validates that the envelope's `conv` is `group:<name>`, that the sender is in the group, and that **every existing device of every member has a wrap** (else `e2e_stale_devices`, the client refreshes and resends) and that nobody has no devices (`e2e_peer_not_ready`: "These people have not set up secure messaging yet: ..."; `sd_e2e.erl:449-500`).
- So in a brand-new group: members who have not set up secure messaging make an encrypted send fail with `e2e_peer_not_ready` in `required` mode; in `optional` mode the web sends plain when anyone lacks a device. This app's `EncryptionPolicy.evaluate` already treats a thread with no history as plain/encrypted by that lookup (`lib/data/repositories/encryption_policy.dart`).
- **Members added later** are wrapped for from the next message on and **cannot read earlier encrypted messages** (their devices had no box). They can read earlier plain messages, because `/history group` gives the whole history to any current member with no join cut-off (`http/chat_web_send.erl:166-175`). The "history for a new device" feature (`E2E_HISTORY_SYNC_MOBILE.md`) is about a person's own new device, not a new member (Q8).
- **Limit:** `e2e.group_devices` refuses a group with more than **200 members** (`sd_e2e.erl:33`, `392-393`): error code `limit` "Groups of more than 200 people cannot use end-to-end encryption yet."; one envelope may carry at most 250 wraps (`MAX_WRAPS`, `:31`, `:464`) and 10 devices per person. Consequence: a group over 200 members can only be plain (`optional` mode) and cannot be written to at all in `required` mode. The group registry itself has no 200 cap, so the group can be created and added to beyond 200.
- This app: **encrypted groups are read-only** today (CLAUDE.md; `EncryptionPolicy`). A group the app creates is therefore sendable in `off`/`optional` mode (plain) and, once it has encrypted history, read-only until group sending is built. That affects the first-run experience of a created group in an organisation with e2e switched on (Q9).

## 4. This app today and what a minimal create screen needs

### 4.1 Current state

- New chat sheet: a row **"New group", subtitle "Not available yet"**, greyed, `comingSoon` image, no `onTap` (`lib/features/chats/widgets/new_chat_sheet.dart:92-105`). The task text calls it "Group chat"; the label in the code is "New group".
- Already handled when events arrive: `groups`, `group_created`, `added_to_group` upsert the conversation and its `members_json` (`lib/data/repositories/conversation_repository.dart:488-496`, `524-531`); `left_group` archives it (`:497-501`). So a group created by anyone shows up in Chats and the Members sheet (`lib/features/conversation/widgets/members_sheet.dart`, read-only usernames).
- **Not handled:** `owner` is not stored (only `members_json`), so the app cannot tell whether "Add people" should be offered; `group_system` and `group_invite_pending` have no handler; there is no `users.colleagues` call (`NewChatController` uses `assoc.list` and `users.search`, `lib/features/chats/new_chat_controller.dart`).
- `#creategroup <name>` and `#addmember` already work through the hash-command path (`command_repository._sendRaw`, reply types from `chat_cmds.erl:86,89`: `group_created`), so a group can be created today by typing the command; there is no UI.
- Online only: group creation needs a connection and cannot be queued (no `cid`, no idempotency). That matches CLAUDE.md's rule for connection-only actions; the create screen should show the offline state, not queue.

### 4.2 Minimal create screen

A route `/new-group` (feature `new_group`, controller + view + binding per CLAUDE.md), opened from the New chat sheet row (which becomes enabled):

1. **Name** `AppTextField`, 1-32 chars, counter, strip control chars and collapse spaces before sending. Client pre-checks that do not need the server: not empty, <= 32, not equal / whole-word prefix of one of my known group names (the server checks the whole organisation, so also expect "already exists" / "too close" errors from groups I am not in).
2. **People** (optional): searchable list from `users.colleagues` (paged by `next`), multi-select with chips; show "Invite" for `connected:false` (strict mode: they get an invitation instead of being added). Use `users.search` for longer queries as the web does. Reuse `ChatPerson`.
3. **Create** button: send `/creategroup <name>`; on `group_created` (members length 1) open the new conversation; then send each `/addmember` **paced** (<= 1 per ~350 ms, under 30 per 10 s) and update from each `group_created`/`group_invite_pending`/`error`; show a one-line result ("3 added, 1 invitation sent, 1 failed: not online"). Keep the dialog on failures with retry for the failed people only.
4. States via `AppStateView`: offline (create needs a connection), loading and empty/error for the people list; error text from the server `text` as is.
5. In the group's Members sheet (later): "Add people" for the owner only (needs `owner` stored: one column or a JSON field on `conversations`, read from `groups` / `group_created` / `added_to_group`).

Size: create screen with name + member picker + paced adds + result summary: **3 days**; plus storing `owner`, handling `group_system` / `group_invite_pending` and the Members-sheet "Add people": **1.5 days**. Encrypted group sending is separate, larger work.

No new package needed.

## 5. Not covered here

Leave group UI, removing members (no server command), renaming/deleting (no server command), group avatar/description (no field), invitation inbox (`req.list`, covered by the connections work), encrypted group sending.

## 6. Questions for the backend team

1. **Atomic create.** Is there (or will there be) a single "create group with members" command, so a client does not need N+1 lines and a 30/10 s pace? If not, please confirm that create-then-add on one connection is processed strictly in order.
2. **Idempotency.** `/creategroup` and `/addmember` reject `/c <cid>`. If a client's create reply is lost (network drop), a retry answers "A group with that name already exists" and the client cannot tell its own success from someone else's group. Will these commands get `cid` support, or should the client check `/groups` (owner == me) before reporting a failure?
3. **Who may create.** In a strict org we found only "registered and active". Is there any intended restriction by role (employee vs customer/external) or a per-user group quota? Is there an org-wide cap on groups or on members per group (none found in code)?
4. **Name rules.** Only length 32, no control characters, case-sensitive uniqueness and the whole-word prefix rule were found. Are `/`, `#`, `:`, `@`, leading/trailing punctuation or emoji really allowed, given the name becomes `group:<name>` ids, `/groupmsg <name> <text>` and `#groupmsg`? Is `Design` vs `design` meant to be two groups?
5. **Owner leaves / ownership.** When the owner leaves, the group keeps the old owner and nobody can add members; the last leaver deletes it. Intended? Is "remove member", "rename", "transfer owner" or "delete group" planned? What should the app show a non-owner who wants to add someone ("Only the group admin (<owner>) can add members" is the only hint)?
6. **Invitations.** After an invite is accepted, the inviter gets no `group_created`/`added_to_group` (only existing members get `group_system "X was added to the group"`). What notification should the inviter's app expect: a feed item, a `req.respond` push, or nothing? What exactly does the invitee's `req.list` row look like for `group_invite` (fields `group`, `subject`, `from`; we have only the Erlang code)? And what happens to a pending invite when the group is deleted or the inviter leaves?
7. **Offline add (open mode and strict mode).** Direct add of an offline person works in strict mode (feed item "Added to a group"); in open mode only for names that have connected before. After an *accepted invite* (`force_add`), an offline invitee gets no feed item (`told_later` is not called there). Intended?
8. **History for new members.** A member added later reads the **entire** plain history of the group (no join cut-off). Is that the intended privacy rule? For an encrypted group they cannot read older messages; will history be handed on to added members (as for a person's own new device)?
9. **Encrypted groups for a new app.** In a group that is e2e (optional mode, everyone has devices) this app can read but not send. For `optional` mode: should a newly created group be sendable as **plain** by the mobile app until encrypted group sending is built, or must the app refuse because the web would have encrypted? Does the server ever mark a group as e2e on its own (flag), or is it only the presence of encrypted messages? (`/groups` and live group events carry no `e2e` flag, noted earlier in `postman-crosscheck.md`.)
10. **200-member limit.** The group registry allows more than 200 members but encryption refuses them (`limit`). Should the creation flow warn at 200, or will the server refuse `/addmember` past 200 when the mode is `required`? Today in `required` mode a 201-member group simply cannot be written to.
11. **`users.colleagues`.** Please add it to the published API notes (`sd_cmds.erl:180` lists it as an allowed `/sd` action). Confirm the request/response above, the 50 cap, that `next` is an opaque cursor (it is `name<NUL>username`), and that the same list is the right source for a mobile member picker for customers (who see only their connections).
12. **Group events and `/groups` for a hidden host.** Is `owner` always present in `groups`, `group_created` and `added_to_group` (the Erlang code can send `null` when it cannot find the group)?
13. **Rate limit feedback.** "Too many commands -- slow down" has no `code` and the line is lost. Is a `code`/`retryAfter` planned? Until then the app paces itself.
