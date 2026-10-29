# Messages, ids, ordering, history and receipts

Based on code (backend `chat_web.erl` is the source of truth, per docs/CHAT_PROTOCOL.md). Client ids, `before` paging and the `e2e` flag were checked against backend commit 869913fe (`origin/main`). Transport: one WebSocket. Client sends **plain-text commands** (one per frame); server sends **JSON events** with a `type` field.

## 1. Connect

First frame (JSON): `{"username":"alice","token":"<session token from POST /api/sd/login>"}` ; reply `{"type":"welcome","name":"alice"}` then a `history` for the global room. `username` max 24 chars, no spaces; in a Connectum organisation send it in lower case. Rate limit: 30 commands / 10 s per connection (`chat.hrl`); over the limit an `/sd` call gets `{"ok":false,"error":{"code":"rate_limited"}}`. Max message text 2000 chars (longer gets an `error` event). Session lasts 15 days (hard limit; use `expiresTs`), then `{"type":"sd_event","event":"session_expired"}` and close.

## 2. Sending a message

| Scope | Command sent | Ack event from server | Live event to recipients |
|---|---|---|---|
| Direct (DM) | `/msg <user> <text>` | `{"type":"dm_ack","with":"bob","status":"delivered"\|"queued","id":123,"ts":1790071256909}` | `private` |
| Group | `/groupmsg <group> <text>` | `{"type":"group_msg_ack","group":"g","id":124,"ts":...}` | `group_message` |
| Global room | bare text (no leading `/`) | `{"type":"own_message_id","id":125,"ts":...}` | `chat` |
| Department host | `/hostmsg <hostKey> <text>` | `{"type":"host_ack","host":"hr","status":"delivered","id":..,"ts":..}` | `host_message` |
| Reply | `/reply <id> <text>`, `/replydm <user> <id> <text>`, `/replygroup <group> <id> <text>` | same as above | same, with `replyTo` |
| Edit | `/edit dm <user> <id> <text>` (also `group`, `global`) | none to sender; everyone gets `edited` / `dm_edited` / `group_edited` `{messageId,text,editedTs}` or sender gets `edit_denied {messageId,reason}` | |
| Delete | `/delete dm <user> <id>` (also `group`, `global`) | `deleted` / `dm_deleted` / `group_deleted` `{messageId}`; sender gets `delete_denied {messageId,reason:"forbidden"\|"not_found"}` | |
| React | `/react dm <user> <id> <emoji>` (toggle) | `reaction` / `dm_reaction` / `group_reaction` `{messageId, reactions:[{user,emoji}]}` | |

**Client id (`/c`).** Wrap a send as `/c <clientId> <command>`, for example `/c 7f3a-0001 /msg ravi hello`. Works for `/msg`, `/replydm`, `/groupmsg`, `/replygroup`, `/hostmsg` (also with the `#dm` shortcut). It does not work for a bare global-room message, `/reply` (global), `/edit` or anything else: the server answers `{"type":"error","code":"cid_unsupported"}`. The id is 1 to 64 characters from letters, digits and `- _ . :`, otherwise `{"type":"error","code":"bad_cid"}`; `/c <id>` with no command gives code `usage`. The ack is the usual ack plus `"cid":"<id>"`. The same id again from the same person (remembered one day, `CONNECTUM_CID_TTL_SEC`) sends nothing and returns the stored first ack, same message `id` and `ts`, with `"duplicate":true`. Only a successful send is remembered; a refused send (error event) is not, so it can be retried under the same id.

Notes:
- Text is sent raw after the command; command splits on the first space (group names have no spaces).
- Attachments: `POST /upload` (multipart, max 8 MB) returns `{"url":"/uploads/<name>"}`; the URL (or the web client's `[ATTACHMENT:{json}]` text tag) is then sent as the message text. UNCLEAR: exact `[ATTACHMENT:...]` JSON schema is client-side only (`parseAttachmentFromText` in the web app); the protocol doc says there is no server command tying a file to a message.
- Refusal (strict mode): `{"type":"error","code":"not_associated"|"not_allowed","text":"...","to":"bob","conv":"dm:bob","sent":false}`. The web client marks its newest pending outgoing message in that thread "failed / Not sent" and never retries.
- **End-to-end encryption** exists for DM and group text (`src/features/connectumChat/e2e/*`, `docs/E2E_ENCRYPTION.md`): the client encrypts before sending and the server stores/relays an opaque envelope. Mobile must implement it or interoperate. Not covered further here.
- Text of normal messages is encrypted at rest by the server (`chat_store:encrypt_text`), transparent to clients.

## 3. Message ids and ordering

| Topic | Fact |
|---|---|
| Id generator | **Server**. `chat_store:save_message` uses Redis `INCR next_msg_id`: one integer sequence shared by all conversations, monotonic, survives restarts. |
| Client-generated id | **`/c <clientId> <command>`** (see section 2). The web client still makes a local placeholder `temp-<Date.now()>` (status `sending`) and replaces it with the server `id`/`ts` when the ack arrives. Mobile also sends a client id (`m-` plus a UUID, 38 characters) with every DM, group and host send. The global room cannot take one, so a resend of a global message still creates a second message. |
| Ack matching | **By `cid`** for sends made with `/c`: the ack echoes it, and a repeated send gets the first ack back with `duplicate:true`. A bare global-room send is acked by `own_message_id` with no id, matched only by being the one global send in flight. |
| `ts` | Epoch milliseconds assigned by the server at save time. Echoed in ack, live events and history. |
| Order | Server order = ascending `id` (conversation sorted set, score = id). History is returned oldest first. Display by `id` (or `ts`); `ts` and `id` are both from the server. |
| Conversation keys | DM = pair of usernames (`chat_store:dm_key`), group = group name, global = one room, host = per host key. |
| Reply | `replyTo` is the numeric id of the original message or `null`. |

## 4. History and pagination

| Request | Result |
|---|---|
| `/history global` , `/history dm <user>` , `/history group <name>` , `/history host <key>` | `{"type":"history","scope":"dm","with":"bob","now":1790071256909,"list":[...]}` (`with` / `group` / `host` identify the thread; global has none) |
| `/history dm bob delta <highestIdHeld> <now>` | `{"type":"history", ..., "delta":true,"now":...,"window":[ids],"list":[changed messages only]}` |
| `/conversations` | `{"type":"conversations","list":[{"with","id","ts","from","text","archived","e2e"?}]}` : last message per DM thread, newest first (how to learn of messages received while offline) |

- **Plain `/history` returns the last 50 messages** (`HISTORY_LIMIT` in `chat_store.erl`), oldest first.
- **Older pages:** `/history <scope> [<name>] before <messageId>` (global, dm, group, host; the id is 1 to 18 digits) returns up to 50 messages with an id below it, oldest first: `{"type":"history","scope":"dm","with":"bob","now":..,"before":<id asked>,"hasMore":true|false,"next":<id>|null,"list":[...]}`. `hasMore` is true when still older messages exist. `next` is the oldest id the server found before it filtered the page for what the person may see, so use `next` for the following request: a page can come back empty or short while `hasMore` is true. `next` is `null` when nothing was found. A conversation the person cleared stays cleared. A `before` that is not followed by a number gives `{"type":"error","code":"usage"}`. A group name with spaces works (`/history group design team before 123`: the scope word is split off first and the rest is the name). A non-member of a group, or a person who shares nothing in the global room, gets an empty page with `hasMore:false`.
- Delta: `window` lists the ids that currently make up the conversation. The client keeps its copy, overlays `list` (changed = newer than held id, or `mod` stamp >= `since`, or form messages), and drops ids not in `window`. If `list` names something not held and not in the cache, ask for the full history. Server `now` is taken before reading; store it and send it back as `<now>`. Servers that never send `now` (older) do not understand `delta`. See docs/MESSAGE_CACHE.md. Optional for mobile (a full `/history` always works).
- "Deleted for me" (conversation clear) uses a per-user cut id on the server; history respects it.

## 5. Message object (history `list` item)

```json
{
  "id": 123, "ts": 1790071256909, "from": "alice", "text": "hello", "kind": "chat",
  "private": false, "reactions": [{"user": "bob", "emoji": "👍"}],
  "deleted": false, "editedTs": null, "replyTo": null,
  "previewUrl": "", "previewTitle": "", "previewDescription": "", "previewImage": ""
}
```

| Field | Type / meaning |
|---|---|
| `id` | int, server id |
| `ts` | int, epoch ms |
| `from` | username string |
| `text` | string. Deleted message: `deleted:true` (text may be empty). `kind:"form"`: one-line summary of the form. E2E text is an envelope starting `e2e1:`. |
| `e2e` | only when the text is an end-to-end envelope: `true`. Absent otherwise. Sent in `history` (every page) and in `/conversations` items, **not** in the live events `private`, `group_message`, `host_message`, `chat`. A deleted message has no flag. The organisation-wide mode (off, optional, required) is `e2e.status`. |
| `kind` | `"chat"` or `"form"` |
| `form` | only when `kind:"form"` and not deleted: the form document (see forms.md) |
| `private` | bool, true for DM |
| `reactions` | `[{user, emoji}]`; one emoji per user toggles |
| `deleted` | bool |
| `editedTs` | int epoch ms or `null` |
| `replyTo` | int id or `null` |
| `preview*` | link preview, `""` when none; arrives later as `link_preview` / `dm_link_preview` / `group_link_preview` `{messageId, previewUrl, previewTitle, previewDescription, previewImage}` |

Live events carry a subset (no `e2e` flag): `chat`/`private` = `{type,id,ts,from,text,replyTo}`; `group_message` adds `group`; `host_message` adds `host`.

Conversation lists: DM key is the other username lowercased; web ids are `user-<name>`, `room-<group>`, `host-<key>`.

## 6. Sent / delivered / read states and unread counts

**Receipts are kept on the server (backend update 2).** For a direct conversation the other person's positions are stored, so a sender who was offline still learns them.

| State | Source | Notes |
|---|---|---|
| `pending`, `sending` | local, before the server ack | the client shows its temp id until the ack |
| `failed` | local, for a non-retryable refusal (`not_associated`, `not_allowed`, validation) or an unconfirmed delivery | see `CLAUDE.md` Offline |
| `sent` | the ack (`dm_ack`, `group_msg_ack`, `own_message_id`, `host_ack`) | gives the real `id` and `ts` |
| `delivered` | a message of mine with id at or below `peerDeliveredId` | `conv.list {full:true}` gives it; the live `sd_event receipt` (`kind:"delivered"`, `upTo`) moves it. `dm_ack.status "delivered"/"queued"` is only a first hint |
| `read` | a message of mine with id at or below `peerReadId` | same sources (`kind:"read"`); read implies delivered. The old `dm_read` push (no id) is still sent and means "up to now" |

- **Ids are compared as numbers only here**, and in the unread rule below. They are stored as text; parse only all-digit ids and ignore anything else.
- **Receipts are for direct conversations.** For a group the author asks `conv.readers {id:"group:<name>", messageId}` (`readers[{user, readTs}]`, `readCount`, `total`); only the author may ask and a direct conversation answers `invalid`. The global room and hosts have no receipts.
- **Sending a read position:** `conv.read {id, upTo}` when messages are actually on screen (forward only; the server clamps to the newest). `conv.delivered {id, upTo}` when messages from others arrive or sync in. Do not send a read just because a row was tapped.
- **Unread counts come from the server.** `conv.list {full:true}` gives `unread` (at most 99) and `unreadMore` per conversation (messages from others above the read position and above what was cleared) plus `lastId` and `readId`. Between syncs a live message from someone else counts once when its id is newer than the known `lastId`; the next sync replaces the number. Host conversations are not in `conv.list`, so their count stays local.
- **Pin and mute** are kept on the server (`conv.pin/unpin/mute/unmute`, flags `pinned`/`pinnedTs`, `muted`/`mutedTs` in `conv.list`).
- Typing: `/typing dm|group <name>|global` ; received as `typing_dm {from}`, `group_typing {group,from}`, `typing {text: username}`.
- Notification counts come from `/sd feed.summary` etc. (docs/CONNECTUM_API.md).
- `/conversations` items now also carry `avatar` (the other person's picture address or null). `conv.list` carries `avatar` only on direct rows; `assoc.list` and `users.search` rows carry it per person.

## 7. Related `/sd` envelope (used by forms and everything else)

Send `/sd <action> {json with reqId}`; reply `{"type":"sd","action":..,"reqId":..,"ok":true,"data":{}}` or `{"ok":false,"error":{"code","message","details"}}`. Server pushes: `{"type":"sd_event","event":"<name>","data":{}}`.

## Source files

- axi-chat-backend/src/chat_web.erl, chat_store.erl, chat_room.erl, chat.hrl, sd_cmds.erl, sd_notify.erl
- src/services/connectumSocket.js, src/features/connectumChat/ConnectumChatScreen.jsx (send, ack, dm_read handlers), src/features/connectumChat/components/MessageList.jsx (TicksIcon), src/features/connectumChat/utils/messageCache.js
- docs/CHAT_PROTOCOL.md, docs/MESSAGE_CACHE.md, docs/E2E_ENCRYPTION.md (referenced, not read in full)
