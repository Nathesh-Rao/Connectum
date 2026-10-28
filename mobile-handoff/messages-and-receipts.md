# Messages, ids, ordering, history and receipts

Based on code (backend `chat_web.erl` is the source of truth, per docs/CHAT_PROTOCOL.md). Transport: one WebSocket. Client sends **plain-text commands** (one per frame); server sends **JSON events** with a `type` field.

## 1. Connect

First frame (JSON): `{"username":"alice","token":"<session token from POST /api/sd/login>"}` ; reply `{"type":"welcome","name":"alice"}` then a `history` for the global room. `username` is case-sensitive, max 24 chars, no spaces. Rate limit: 30 commands / 10 s per connection (`chat.hrl`); over the limit an `/sd` call gets `{"ok":false,"error":{"code":"rate_limited"}}`. Max message text 2000 chars (longer gets an `error` event). Session lasts 14 days, then `{"type":"sd_event","event":"session_expired"}` and close.

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
| Client-generated id | **None sent to the server.** The command has no id/nonce. The web client makes a local placeholder `temp-<Date.now()>` (status `sending`), and replaces it with the server `id`/`ts` when the ack arrives. So there is **no server-side idempotency / dedupe**: resending a command creates a second message. |
| Ack matching | By position, not by id: the web client replaces the **first** outgoing message in that thread that is `sending` or has a `temp-` id. Acks arrive in order per connection. A mobile client should send one message at a time per thread or keep a FIFO queue of pending temp ids. |
| `ts` | Epoch milliseconds assigned by the server at save time. Echoed in ack, live events and history. |
| Order | Server order = ascending `id` (conversation sorted set, score = id). History is returned oldest first. Display by `id` (or `ts`); `ts` and `id` are both from the server. |
| Conversation keys | DM = pair of usernames (`chat_store:dm_key`), group = group name, global = one room, host = per host key. |
| Reply | `replyTo` is the numeric id of the original message or `null`. |

## 4. History and pagination

| Request | Result |
|---|---|
| `/history global` , `/history dm <user>` , `/history group <name>` , `/history host <key>` | `{"type":"history","scope":"dm","with":"bob","now":1790071256909,"list":[...]}` (`with` / `group` / `host` identify the thread; global has none) |
| `/history dm bob delta <highestIdHeld> <now>` | `{"type":"history", ..., "delta":true,"now":...,"window":[ids],"list":[changed messages only]}` |
| `/conversations` | `{"type":"conversations","list":[{"with","id","ts","from","text","archived"}]}` : last message per DM thread, newest first (how to learn of messages received while offline) |

- **Page size is fixed: the last 50 messages** (`?HISTORY_LIMIT` in `chat_store.erl`). **There is no "load older" / before-id / cursor pagination** in the protocol or web client. Anything older than the newest 50 is not reachable. UNCLEAR: should the mobile app be limited to 50, or will the backend add a `before <id>` parameter?
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
| `text` | string. Deleted message: `deleted:true` (text may be empty). `kind:"form"`: one-line summary of the form. E2E text starts with an envelope prefix. |
| `kind` | `"chat"` or `"form"` |
| `form` | only when `kind:"form"` and not deleted: the form document (see forms.md) |
| `private` | bool, true for DM |
| `reactions` | `[{user, emoji}]`; one emoji per user toggles |
| `deleted` | bool |
| `editedTs` | int epoch ms or `null` |
| `replyTo` | int id or `null` |
| `preview*` | link preview, `""` when none; arrives later as `link_preview` / `dm_link_preview` / `group_link_preview` `{messageId, previewUrl, previewTitle, previewDescription, previewImage}` |

Live events carry a subset: `chat`/`private` = `{type,id,ts,from,text,replyTo}`; `group_message` adds `group`; `host_message` adds `host`.

Conversation lists: DM key is the other username lowercased; web ids are `user-<name>`, `room-<group>`, `host-<key>`.

## 6. Sent / delivered / read states

**Receipts partly exist, for direct messages only. They are not persisted.**

| State (web `status`/`ticks`) | Source | Notes |
|---|---|---|
| `sending` | local, before the socket write is confirmed | Web sets it, then flips to `sent` immediately after `ws.send` succeeds (before the ack). |
| `failed` | local: socket closed on send; E2E encrypt failure; `error` with `not_associated`/`not_allowed` | Not retried. |
| `sent` | local after write, and again on ack (`dm_ack`, `group_msg_ack`, `own_message_id`, `host_ack`) | Ack gives the real `id` and `ts`. |
| `delivered` | **`dm_ack.status`** is `"delivered"` (recipient online and pushed live) or `"queued"` (recipient offline, stored). | The web app saves it as `serverStatus` but **shows only the "sent" tick**; the "delivered" double tick icon exists in `TicksIcon` but nothing sets `ticks:"delivered"`. There is no later "delivered" event when a queued message is eventually received. |
| `read` | Recipient's client sends `/read dm <user>`; server pushes `{"type":"dm_read","from":"bob"}` to the other party **only if they are online** (`chat_room` mark_read: silently dropped otherwise). | The web client then marks **all** its outgoing messages in that DM `read` (no per-message id in the event). |

Facts a mobile developer must know:
- `dm_read` has no message id or timestamp: it means "bob has read the thread up to now".
- Read state is **not stored**: history items carry no read/delivered flag. The web client marks every message loaded from history (even its own) as `read`. After reconnect the read state of your own messages is unknown; show them as sent/read by convention, as the web does.
- `/read dm <user>` is sent when the DM is opened, and when a `private` message arrives while it is open. It also clears the sender's personal notifications server-side (`notifications_changed`).
- **Groups, global room, hosts: no delivery or read receipts** (`/read` accepts only `dm`).
- Typing: `/typing dm|group <name>|global` ; received as `typing_dm {from}`, `group_typing {group,from}`, `typing {text: username}`.
- Unread counts are client state (incremented per `private`/`group_message` when the chat is not on screen); badge/feed counts for notifications come from `/sd` actions (`feed.summary` etc., see docs/CONNECTUM_API.md).

## 7. Related `/sd` envelope (used by forms and everything else)

Send `/sd <action> {json with reqId}`; reply `{"type":"sd","action":..,"reqId":..,"ok":true,"data":{}}` or `{"ok":false,"error":{"code","message","details"}}`. Server pushes: `{"type":"sd_event","event":"<name>","data":{}}`.

## Source files

- axi-chat-backend/src/chat_web.erl, chat_store.erl, chat_room.erl, chat.hrl, sd_cmds.erl, sd_notify.erl
- src/services/connectumSocket.js, src/features/connectumChat/ConnectumChatScreen.jsx (send, ack, dm_read handlers), src/features/connectumChat/components/MessageList.jsx (TicksIcon), src/features/connectumChat/utils/messageCache.js
- docs/CHAT_PROTOCOL.md, docs/MESSAGE_CACHE.md, docs/E2E_ENCRYPTION.md (referenced, not read in full)
