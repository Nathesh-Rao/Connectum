# Connectum chat: WebSocket protocol (for the Flutter client)

Derived from the web client (`src/services/connectumSocket.js`) and the Erlang backend (`axi-chat-backend/src/chat_web.erl` and friends). Where `docs/*.md` and code disagree, code wins (noted below). Placeholders: `<TOKEN>` = enterprise session token, `<HOST>` = server host.

## 1. Opening the connection

| Item | Value |
|---|---|
| URL (https site) | `wss://<HOST>/ws` (nginx routes `/ws` to the backend; the backend accepts an upgrade on any path) |
| URL (http site) | `ws://<HOST>/ws` |
| URL (local dev, backend standalone) | `ws://<host>:8080` (root path) |
| Override in web client | `localStorage.connectum_ws_url` (dev only) |
| Sub-protocol / headers | none required |
| REST base (sign-in, upload) | `https://<HOST>/api/sd` (web: `connectum_api_base` / `VITE_CONNECTUM_API_BASE`, else same origin, else a hard-coded VM fallback) |

**Frame rules.** Client to server: every frame after the handshake is a plain-text command line (`/msg bob hi`), not JSON. Server to client: every frame is one JSON object with a `type`. The only JSON the client sends is the first frame.

**Handshake (first text frame, JSON):**
```json
{"username": "alice", "token": "<TOKEN>", "armSessionId": "sess-1790071256909"}
```
- `token` = the **enterprise session token** returned by `POST /api/sd/enter` (see `sessions.md`). `armSessionId` is optional (server defaults to `"app"` and ignores it); the web client still sends `"arm-<ms>"` or `"sess-<ms>"`.
- `username` is the person's username inside the chosen enterprise. Web client sends it trimmed, lower-cased, spaces replaced by `_`, cut to 24 chars. Server rule: max 24 chars, no whitespace or control chars. The server compares it with the username stored on the session; a mismatch is rejected.
- **The organisation is not a field in the handshake.** It is implied by the token: an enterprise session belongs to exactly one enterprise, and resolving the token puts the connection into that enterprise (`sd_auth:session_record/1`). To use another organisation, call `POST /api/sd/enter` for it and open a new socket with the new token.
- Success: `{"type":"welcome","name":"alice"}`, then immediately a `history` event (`scope:"global"`, with `now`), then one `profile` event per known person (self, online users, DM partners, connections, max 300) that has an avatar or status.
- Failure: `{"type":"error","text":"..."}` and the socket **stays open** for a corrected retry. Texts seen in code: `Username cannot be empty`, `Username too long (max 24 chars)`, `Username cannot contain spaces or control characters`, `Expected {"username":..,"token":..} (armSessionId is optional)`, `That session belongs to a different username.`, `Sign in to Connectum first (POST /api/sd/login) and pass the returned token.`, `Username taken`.
- The web client does not retry on a handshake error: it waits for `welcome`. UNCLEAR: what the mobile client should do on a handshake `error` (the web client relies on its 60 s `GET /api/sd/session` poll to notice a dead token and sign out).

**After `welcome` the web client sends, in order:** `/hosts`, `/list`, `/groups`, `/conversations`, `/history global` (delta form once it holds a cache), `/cmds`. Then `/sd me`-style calls as screens need them.

## 2. Heartbeat, reconnect, limits

- **No application heartbeat** in either direction (no ping command, no server `ping` event). The server answers a WebSocket protocol Ping (opcode 9) with Pong (opcode 10) and honours Close (8). It never sends Pings itself. The web client sends none (browsers cannot). A mobile client may send protocol Pings to detect dead links; this is not required by the server.
- Server drops a connection whose socket write cannot finish in 15 s (`send_timeout`), or whose backlog exceeds 5000 pushes (it first sends `sd_event` `disconnected` with `reason:"too_slow"`).
- **Reconnect (web client):** on `onclose` without a manual disconnect: set status `offline_fallback`, fail pending `/sd` requests with code `disconnected`, wait a fixed **2500 ms**, run the full connect + handshake again with the stored token. No backoff, no retry cap. `onerror` only sets status `offline_fallback` (the close that follows triggers the reconnect).
- **No reconnect** after: manual `disconnect()` (sign-out, switching enterprise), `connection_superseded`, and the three forced sign-out events (`session_replaced`, `session_expired`, `disconnected`/`account_deactivated`).
- Status values: `connecting`, `connected` (set on `welcome`), `disconnected`, `offline_fallback`.
- **Nothing is replayed on reconnect.** Pushes sent while offline are lost; the client re-fetches (`/conversations`, `/history`, `/sd req.list`, `cards.list`, `feed.list`). The web client emits an internal `resync` after each reconnect for this.
- `/sd` requests that hit a connection gap (`not_connected` / `disconnected`) are retried once after the next `welcome`, waiting up to 12 s. `timeout` and server errors are not retried. Default `/sd` timeout 10 s (some calls 15 to 60 s).
- **Rate limit:** 30 commands per 10 s window per connection (env `CHAT_RATE_LIMIT_MAX`); `/cmds` and `/cmdcomplete` have a separate 120 per window. Over the limit: `{"type":"error","text":"Too many commands -- slow down"}`; for `/sd` the reply is an `sd` envelope with `error.code:"rate_limited"`. Also `error.code:"busy"` ("Too many requests at once") from the per-connection `/sd` lane.
- Max chat text 2000 chars (E2E envelope has a larger cap). Max group name 32. Max status 140.
- The session check (`session_expired`) runs only when the server **receives a line** from the client, at most every 30 s. An idle socket is not closed on expiry until it sends something. The web client also polls `GET /api/sd/session` every 60 s.
- **History delta (optional optimisation):** `/history <scope> [target] delta <lastId> <now>` where `now` is the `now` field of the last `history` answer. The answer then carries `delta:true`, `window:[ids]` and only changed items; a client that holds no cache sends the plain form.

## 3. Reply envelope for `/sd` calls

Request (one text frame): `/sd <action> <json-args>`; put a unique `reqId` string in the args (web client: `ui-1`, `ui-2`, ...). A bare `/sd` means `/sd me`.
```
/sd cards.list {"section":"all","reqId":"ui-7"}
```
Reply (matched by `reqId`; the web client delivers it only to the caller):
```json
{"type":"sd","action":"cards.list","reqId":"ui-7","ok":true,"data":{"cards":[],"sections":[]}}
{"type":"sd","action":"x","reqId":"ui-8","ok":false,"error":{"code":"forbidden","message":"Administrators only.","details":null}}
```
Error codes seen: `unauthenticated`, `session_expired`, `account_inactive`, `forbidden`, `unknown_action`, `bad_json`, `rate_limited`, `busy`, `internal`, `invalid_values` (with `details.fields`). Full list: `docs/CONNECTUM_API.md` section 7. Client-side synthetic codes: `not_connected`, `disconnected`, `timeout`.

## 4. Event catalog

Direction: C>S = client sends (text line), S>C = server pushes JSON. "Reply" = event that answers a command. Ids are integers; `ts` is epoch ms.

### 4.1 Session / connection

| Name | Dir | Payload (example) | When | Reply / client reaction |
|---|---|---|---|---|
| (handshake) | C>S | `{"username":"alice","token":"<TOKEN>"}` | first frame | `welcome` or `error` |
| `welcome` | S>C | `{"type":"welcome","name":"alice"}` | handshake accepted | client starts bootstrap sends, sets E2E up |
| `/quit` | C>S | `/quit` | clean disconnect (web sends it on sign-out) | server unregisters the user and closes |
| `sd_event` `connection_superseded` | S>C | `{"type":"sd_event","event":"connection_superseded","reason":"opened_elsewhere"}` | the **same token** opened a second socket; the newer wins | socket closed. Client: no reconnect, no sign-out, toast "reload to use it here" |
| `sd_event` `session_replaced` | S>C | `{"type":"sd_event","event":"session_replaced","reason":"signed_in_elsewhere"}` | the same person entered the same enterprise again elsewhere (old token revoked) | socket closed. Client: forced sign-out (see `sessions.md`) |
| `sd_event` `session_expired` | S>C | `{"type":"sd_event","event":"session_expired","reason":"two_week_login"}` | session TTL (15 days) passed, noticed on next client line | socket closed. Client: forced sign-out |
| `sd_event` `disconnected` | S>C | `{"type":"sd_event","event":"disconnected","reason":"account_deactivated"}` | admin deactivated the account, or `reason:"too_slow"` | socket closed. `account_deactivated`: forced sign-out. `too_slow`: web client just reconnects |
| `error` | S>C | `{"type":"error","text":"Unknown command: /xyz (see docs/CHAT_PROTOCOL.md for the command list)"}` | any refused or malformed command | web client shows a toast. Optional `code`: `not_allowed`, `not_associated`, `unknown_command`, `usage`, `invalid_encoding`, `internal`, E2E codes (`e2e_*`, `bad_envelope`) |
| `error` (refused DM) | S>C | `{"type":"error","code":"not_associated","text":"...","to":"bob","conv":"dm:bob","sent":false}` | `/msg` or `/replydm` to someone you are not connected with | client marks that message "Not sent" in the thread |

### 4.2 Enterprises (organisation context)

There are **no WebSocket events to list or switch enterprises**. Listing and entering is REST (`GET /api/sd/me`, `POST /api/sd/enter`; see `sessions.md`). Over the socket the enterprise is fixed for the connection's life. Related `/sd` calls and pushes:

| Name | Dir | Payload | When | Reply |
|---|---|---|---|---|
| `/sd me` | C>S | `/sd me {"reqId":"ui-1"}` | after connect | `data`: `{authenticated, mode, user, org, sessionExpiresTs, notifications, feed, permissions:{isAdmin,isHost,canManageUsers}, pendingRequests, adminUnlocked}`; unauthenticated: `{authenticated:false, sessionExpired}` |
| `/sd org.name` | C>S | `{}` | header title | `data:{name}` |
| `/sd perm.mine` | C>S | `{}` | after connect and on `permissions_changed` | `data:{permissions:[..], isAdmin}` |
| `/sd membership.list`, `membership.request` | C>S | `{}` ; `{"membership":{...}}` | extra connections (memberships) inside the enterprise | `data` per `CONNECTUM_API.md` ("Several connections for one person") |
| `sd_event` `membership_added` | S>C | `{"event":"membership_added","data":{"by":"carol"}}` | a connection was approved/added | client re-reads `options.list` and `options.categories` |
| `sd_event` `permissions_changed` | S>C | `{"data":{"user":"alice","by":"admin1"}}` or `{"permission":"..","by":".."}` | roles/permissions changed | client re-calls `perm.mine` and `GET /session` |
| `sd_event` `org_config_changed`, `roles_changed`, `affiliates_changed`, `catalog_changed`, `interaction_rules_changed`, `setup_changed`, `plugins_changed`, `links_changed` | S>C | e.g. `{"data":{"kind":"branches","name":"..","action":"saved","by":".."}}` | admin edited organisation setup; sent to everyone online (setup_changed: admins only) | hint only: re-read what you show. Web client's live-change hook also lists `pages_changed`, but no backend code emits it (UNCLEAR: is it dead?) |

### 4.3 Conversations (lists, groups, hosts, profiles)

| Name | Dir | Payload | When | Reply |
|---|---|---|---|---|
| `/conversations` | C>S | `/conversations` | after connect | `conversations` |
| `conversations` | S>C | `{"type":"conversations","list":[{"with":"bob","id":12,"ts":1790071256909,"from":"bob","text":"hi","archived":false}]}` | reply | `text` is `""` if deleted; deleted-for-me threads omitted |
| `/history ...` | C>S | `/history global` ; `/history dm bob` ; `/history group design_team` ; `/history host hr` ; optional ` delta <lastId> <now>` | open a conversation, connect | `history` (last 50, oldest first) |
| `history` | S>C | `{"type":"history","scope":"dm","with":"bob","now":1790071256909,"list":[<message>]}` (`group`/`host` key instead of `with` for those scopes; `delta`,`window` when delta) | reply; also auto after `welcome` for global | see message object in 4.4 |
| `/groups` | C>S | `/groups` | after connect | `groups` |
| `groups` | S>C | `{"type":"groups","list":[{"name":"design_team","owner":"alice","members":["alice","bob"]}]}` | reply | |
| `/creategroup <name>` | C>S | `/creategroup design team` | new group (spaces allowed, max 32) | `group_created` or `error` |
| `group_created` | S>C | `{"type":"group_created","name":"design team","owner":"alice","members":["alice"]}` | also after a successful `/addmember` (carries new member list) | |
| `/addmember <group> <user>` | C>S | `/addmember design_team bob` | group owner adds a member | `group_created` (updated), or `group_invite_pending`, or `error` (`not_allowed` if not owner) |
| `group_invite_pending` | S>C | `{"type":"group_invite_pending","group":"g","user":"bob","request":{...request view}}` | strict mode: invitee is not your connection | invitee must accept |
| `added_to_group` | S>C | `{"type":"added_to_group","name":"g","owner":"alice","members":["alice","bob"],"by":"alice"}` | you were added | |
| `/leavegroup <group>` | C>S | `/leavegroup design_team` | | `left_group` |
| `left_group` | S>C | `{"type":"left_group","text":"design_team"}` | | `text` holds the group name |
| `group_system` | S>C | `{"type":"group_system","group":"g","text":"alice added bob to the group"}` | group notices | web client parses "X added Y to the group" to update members |
| `/hosts` | C>S | `/hosts` | after connect | `hosts` |
| `hosts` | S>C | `{"type":"hosts","list":[{"key":"claude","name":"Claude","kind":"llm"}]}` | reply | `kind`: `llm`, `workspace`, `department` |
| `/list` | C>S | `/list` | online users; web re-sends on `system` join/leave | `users` |
| `users` | S>C | `{"type":"users","list":["alice","bob"]}` | reply (filtered by visibility rules) | |
| `/getprofile <user>`, `/setavatar <url>`, `/removeavatar`, `/setstatus <text>` | C>S | `/setstatus In a meeting` | avatar url must be `/uploads/..` or `https://..` (max 300); bare `/setstatus` clears | `profile` (broadcast) |
| `profile` | S>C | `{"type":"profile","user":"alice","avatar":"/uploads/x.png","status":null}` | change, `/getprofile` reply, and after `welcome` | `null` = none |
| `sd_event` `conversation_changed` | S>C | `{"data":{"id":"dm:bob","change":"archived\|unarchived\|deleted","conversation":{...}}}` | archive/delete state changed (also other devices) | UNCLEAR: web client has no handler for it and never calls `conv.*` (backend and `CONNECTUM_API.md` define them) |
| `/sd conv.list / conv.archive / conv.unarchive / conv.delete` | C>S | `{"id":"dm:bob"}` (id = `global`, `dm:<user>`, `group:<name>`) | server-side archive/delete | `data:{conversation:state}`; see `CONNECTUM_API.md` "Conversations: archive and delete" |

### 4.4 Messages (payloads only; semantics are in the message doc)

Message object inside `history.list`: `{id, ts, from, text, kind, private, reactions:[{user,emoji}], deleted, editedTs, replyTo, previewUrl, previewTitle, previewDescription, previewImage}`; `kind:"form"` items also carry `form` (the form document). `text` may be an E2E envelope starting `e2e1:`.

| Name | Dir | Payload (example) | When | Reply / response |
|---|---|---|---|---|
| global text | C>S | `hello everyone` (any line not starting with `/`) ; `##text` posts literal `#text` | send to global room | `chat` to everyone, `own_message_id` to sender |
| `/reply <id> <text>` | C>S | `/reply 123 ok` | reply in global | as above |
| `/msg <user> <text>` | C>S | `/msg bob hello` | DM | `dm_ack`; recipient gets `private` |
| `/replydm <user> <id> <text>` | C>S | `/replydm bob 12 yes` | reply in DM | same |
| `/groupmsg <group> <text>` | C>S | `/groupmsg design_team hi` | group message | `group_msg_ack`; members get `group_message` |
| `/replygroup <group> <id> <text>` | C>S | `/replygroup design_team 5 ok` | | same |
| `/hostmsg <hostKey> <text>` | C>S | `/hostmsg hr leave request` | department host only (not `llm`/`workspace`) | `host_ack`; error if host unknown |
| `chat` | S>C | `{"type":"chat","id":1,"ts":1790071256909,"from":"bob","text":"hi","replyTo":null}` | global message | |
| `private` | S>C | same fields as `chat`, `type:"private"` | DM received | |
| `group_message` | S>C | `{"type":"group_message","group":"g","id":5,"ts":..,"from":"bob","text":"..","replyTo":null}` | | |
| `host_message` | S>C | `{"type":"host_message","host":"hr","id":3,"ts":..,"from":"x","text":"..","replyTo":null}` | | |
| `system` | S>C | `{"type":"system","text":"bob has joined"}` | global notices: `has joined`, `has left`, `has disconnected` (also the only presence signal) | web client re-sends `/list` |
| `own_message_id` | S>C | `{"type":"own_message_id","id":7,"ts":..}` | echo of your global broadcast | |
| `dm_ack` | S>C | `{"type":"dm_ack","with":"bob","status":"delivered\|queued","id":9,"ts":..}` | `/msg` accepted | `queued` = recipient offline |
| `group_msg_ack` | S>C | `{"type":"group_msg_ack","group":"g","id":6,"ts":..}` | | |
| `host_ack` | S>C | `{"type":"host_ack","host":"hr","status":"delivered","id":4,"ts":..}` | | |
| `/edit global <id> <text>` / `/edit dm <user> <id> <text>` / `/edit group <group> <id> <text>` | C>S | `/edit dm bob 9 fixed` | sender only, within 900 s (env `CHAT_EDIT_WINDOW_SEC`) | `edited` / `dm_edited` / `group_edited`, or `edit_denied` |
| `edited` | S>C | `{"type":"edited","scope":"global","messageId":1,"text":"..","editedTs":..}` | | |
| `dm_edited` | S>C | `{"type":"dm_edited","messageId":9,"text":"..","editedTs":..,"userA":"alice","userB":"bob"}` | | |
| `group_edited` | S>C | `{"type":"group_edited","group":"g","messageId":5,"text":"..","editedTs":..}` | | |
| `edit_denied` | S>C | `{"type":"edit_denied","messageId":9,"reason":"..."}` | | UNCLEAR: full list of `reason` values (atoms from `chat_room`; not enumerated here) |
| `/delete global <id>` / `/delete dm <user> <id>` / `/delete group <group> <id>` | C>S | `/delete dm bob 9` | sender only | `deleted` / `dm_deleted` / `group_deleted` or `delete_denied` |
| `deleted` | S>C | `{"type":"deleted","scope":"global","messageId":1}` | | |
| `dm_deleted` | S>C | `{"type":"dm_deleted","messageId":9,"userA":"alice","userB":"bob"}` | | |
| `group_deleted` | S>C | `{"type":"group_deleted","group":"g","messageId":5}` | | |
| `delete_denied` | S>C | `{"type":"delete_denied","messageId":9,"reason":"forbidden\|not_found"}` | | |
| `/react global <id> <emoji>` / `/react dm <user> <id> <emoji>` / `/react group <group> <id> <emoji>` | C>S | `/react dm bob 9 👍` | toggles | `reaction` / `dm_reaction` / `group_reaction` |
| `reaction` | S>C | `{"type":"reaction","scope":"global","messageId":1,"reactions":[{"user":"bob","emoji":"👍"}]}` | | full reaction list replaces the old one |
| `dm_reaction` | S>C | `{"type":"dm_reaction","messageId":9,"reactions":[..],"userA":"alice","userB":"bob"}` | | |
| `group_reaction` | S>C | `{"type":"group_reaction","group":"g","messageId":5,"reactions":[..]}` | | |
| `link_preview`, `dm_link_preview`, `group_link_preview` | S>C | `{"type":"link_preview","scope":"global","messageId":1,"previewUrl":"https://..","previewTitle":"..","previewDescription":"..","previewImage":".."}` (dm: adds `userA`,`userB`, no scope; group: adds `group`) | link fetched after send | strings are `""` if none |
| `/gifsearch [q]`, `/stickersearch [q]` | C>S | `/gifsearch cat` | picker | `gif_results` / `sticker_results` |
| `gif_results`, `sticker_results` | S>C | `{"type":"gif_results","query":"cat","results":[{"id":"..","url":"..","preview":"..","width":"200","height":"150"}]}` | | width/height are strings |
| File upload | HTTP | `POST {origin}/upload` multipart field `file`, header `Authorization: Bearer <TOKEN>`; answer `{"url":"/uploads/<name>","name","size","type"}` | before sending an attachment | then send the url (or the `[ATTACHMENT:{...}]` text the web client builds) as ordinary text. Limits: images/audio 8 MB, docs 20 MB, video 25 MB, 20 uploads/60 s/IP |

### 4.5 Receipts

| Name | Dir | Payload | When | Reply |
|---|---|---|---|---|
| `/read dm <user>` | C>S | `/read dm bob` | web client sends when a DM is opened or a message arrives while open | server pushes `dm_read` to `bob`; also clears that sender's personal notifications (`notifications_changed`) |
| `dm_read` | S>C | `{"type":"dm_read","from":"alice"}` | the other person read your DM thread | `from` = the reader. Only thread-level; no per-message id |
| `dm_ack` / `group_msg_ack` / `host_ack` | S>C | see 4.4 | delivery acks (`delivered`/`queued`) | there is no "delivered to device" or per-recipient read event |

### 4.6 Forms and submissions (list only; detail is in the forms doc)

| Name | Dir | Payload | When | Reply |
|---|---|---|---|---|
| `/sd options.list`, `options.categories` | C>S | `{}` | forms/prompt menu | `data:{options}` / `data:{categories,...}` |
| `/sd tstruct.get` / `tstruct.user.get` | C>S | `{"name":"leave_request"}` | open a form | `data:{tstruct:{...}}` |
| `/sd tstruct.submit` / `tstruct.user.submit` | C>S | `{"name":"leave_request","values":{...},"chat":"dm:bob"}` (`chat` optional: post into a conversation) | submit | `data:{submission}`; error `invalid_values` with `details.fields` |
| `/sd submissions.list` | C>S | `{"offset":0}` (also `tstruct`, `limit`, `fetch`) | my submissions | `data` page |
| `/sd submission.get`, `submission.history` | C>S | `{"id":42}` | | `data:{submission}` / history |
| `/sd submissions.update`, `submission.resubmit`, `submissions.delete` | C>S | `{"id":42,"values":{...}}` ; `{"id":42}` | edit, resubmit after rejection, delete | |
| `/sd records.about_me` | C>S | `{"limit":50,"offset":0}` | records about me | |
| `/sd datasource.run`, `api.run`, `form.options` | C>S | `{"tstruct":"x","scope":"user\|admin","field":"f","values":{...},"limit":..}` | dependent dropdowns | |
| `/sd forms.forward` | C>S | `{"id":..,"chats":[..]}` | forward a form message | |
| `/sd req.list`, `req.respond` | C>S | `{"status":"pending\|all"}` ; `{"id":5,"action":"accept\|reject",...}` (+ `reason`, `comment`, `allowResubmit`) | approvals inbox | `data:{requests}` |
| `form_message` | S>C | `{"type":"sd_event","event":"form_message","data":{"conversation":"dm:bob","id":..,"ts":..,"from":"alice","form":{...},"text":".."}}` | a form was posted into a conversation | |
| `form_message_updated` | S>C | same keys without `ts` | that form changed status | |
| `submissions_changed` | S>C | `{"data":{"id":42,"tstruct":"..","action":"created\|updated\|deleted","by":".."}}` | to submitter, host, admins, subject, manager | re-read lists |
| `submission_approved` / `submission_rejected` / `submission_notice` / `submission_no_approvers` | S>C | `{"data":{"submissionId":42,"tstruct":"..","status":"..","reason":null,"allowResubmit":false}}` | decision on your submission | web client toasts; rejected shows reason and "fix it and send again" |
| `request_created` / `request_resolved` | S>C | `{"data":{id,type,status,from,fromName,subject,subjectName,approvers[],data,createdTs,resolvedTs,resolvedBy}}` | approval request for you / decided | `status`: pending, accepted, rejected, ignored |
| `tstructs_changed`, `options_changed` | S>C | `{"data":{"scope":"user\|admin","name":"..","action":"created\|updated\|saved\|deleted","by":".."}}` ; `{"id":..,"action":"saved\|deleted","by":".."}` | form definitions/options changed (everyone online) | re-ask `options.list` |

### 4.7 AI

AI chat is **not** a WebSocket event stream. It is request/reply over `/sd`; no streaming pushes exist.

| Name | Dir | Payload | When | Reply |
|---|---|---|---|---|
| `/sd ai.agents` | C>S | `{}` | list agents available to me | `data` agent list |
| `/sd ai.models` | C>S | `{"agent":"claude","refresh":true}` (timeout 25 s) | model picker | `data` models |
| `/sd assistant.relay` | C>S | `{"agent":"claude","payload":{<provider request body>},"model":"<optional>"}` (timeout up to RELAY_WAIT_MS) | ask the model; the server forwards to the provider | `data:{status,body}` (provider HTTP status and body); errors `bad_key`, `no_key`, `no_agent`, `no_access` |
| `/sd ai.conv.list / get / save / rename / pin / delete` | C>S | `{"q":".."}` ; `{"id":..}` ; `{"id":..,"agent":"claude","messages":[..],"focus":..}` ; `{"id":..,"title":".."}` ; `{"id":..,"pinned":true}` | saved AI conversations | `data` |
| `/sd ai.enterprise` | C>S | `{"what":"forms"}` or `{"what":"people","q":".."}` | context for the model | `data` |
| `sd_event` `ai_agents_changed` | S>C | `{"data":{"action":"saved\|deleted","by":".."}}` | agents changed | client reloads agents |
| `host` kinds `llm`/`workspace` | n/a | from `/hosts` | selecting one is a client-side switch; never `/hostmsg` it | |

### 4.8 Notifications, cards, workspace feed

| Name | Dir | Payload | When | Reply |
|---|---|---|---|---|
| `/sd feed.list` | C>S | `{"priority":"high","category":"..","unreadOnly":true,"limit":50,"before":..}` | workspace panel | `data:{notifications,counts,hasMore}` |
| `/sd feed.summary` | C>S | `{}` | | `data:{high,medium,low,resolved,unread,total}` |
| `/sd feed.read` | C>S | `{"ids":["n1"],"read":true}` or `{"all":true}` | | `data:{updated,counts}` |
| `/sd feed.resolve` | C>S | `{"id":"n1"}` or `{"all":true}` | | `data:{notification,counts}` |
| `/sd feed.dismiss` / `feed.clear` | C>S | `{"id":"n1"}` / `{}` | | `data:{dismissed:true,counts}` / `{cleared,counts}` |
| `feed_item` | S>C | `{"data":{"notification":{...},"counts":{...}}}` | new or changed item | upsert by `notification.id` |
| `feed_removed` | S>C | `{"data":{"ids":["n1"],"counts":{}}}` | dismissed/cleared | |
| `feed_changed` | S>C | `{"data":{"ids":["n1"],"read":true,"counts":{}}}` | read/unread toggled | |
| `/sd cards.list` | C>S | `{"section":"all"}` | inbox cards | `data:{cards,sections}` |
| `/sd cards.dismiss`, `reminder.add`, `sections.list/save/delete` | C>S | `{"id":..}` ; `{"text":".."}` | | |
| `/sd notifications.summary / list / read` | C>S | `{"all":true}` or `{"category":"priority"}` for read | | `data`: counts summary |
| `card` | S>C | `{"data":{...card with section, category, read, due}}` | new card | |
| `notification` | S>C | `{"data":{"card":{},"category":"..","counts":{}}}` | new notification | web client plays a sound |
| `notifications_changed` | S>C | `{"data":{counts,total,personalBySender}}` | counts changed | |
| `broadcast` | S>C | `{"data":{"id":..,"from":"u","fromName":"..","text":"..","ts":..}}` | announcement | |
| `task_assigned` / `task_updated` | S>C | `{"data":{"task":{...}}}` | task events | `/sd task.create/update/list/get/send` |
| `associate_connected` | S>C | `{"data":{"user":"x","via":"code\|handover","from":".."}}` | someone connected with you | |
| `profile_changed` | S>C | `{"data":{"changes":{...}}}` | your profile changed elsewhere | |
| `axpert_status_changed` / `axpert_access_changed` | S>C | `{"data":{"connected":true}}` / `{"data":{"access":"allowed\|denied"}}` | Axpert link state | |
| `e2e_devices_changed` | S>C | `{"data":{"user":"bob"}}` | a person's E2E device list changed | client drops its cached keys for that user |

### 4.9 Presence and typing

| Name | Dir | Payload | When | Reply |
|---|---|---|---|---|
| `/typing global` / `/typing dm <user>` / `/typing group <group>` | C>S | `/typing dm bob` | web client sends while the user types; receiver shows the indicator for 3.5 s then clears it | peers get typing events |
| `typing` | S>C | `{"type":"typing","text":"bob"}` | someone typing in global (`text` = username) | |
| `typing_dm` | S>C | `{"type":"typing_dm","from":"bob"}` | | |
| `group_typing` | S>C | `{"type":"group_typing","group":"g","from":"bob"}` | | |
| presence | n/a | `users` list + `system` join/leave text | no dedicated presence event | |

### 4.10 `#commands` (prompt-bar menu)

| Name | Dir | Payload | Reply |
|---|---|---|---|
| `/cmds [prefix]` | C>S | `/cmds` | `{"type":"cmd_catalog","prefix":"#","escape":"##","filter":"","categories":[{id,label}],"commands":[...]}` |
| `/cmdcomplete {"input":"#dm al"}` | C>S | optional `reqId`, `page`, `pageSize` | `{"type":"cmd_suggestions","input":"#dm al",...}` |
| `#help [cmd]` | C>S | | `cmd_catalog` or `{"type":"cmd_help","command":{...}}` |
| `#<cmd> <args>` | C>S | e.g. `#dm alice hi` | server rewrites to the matching `/command`; unknown word gives `error` code `unknown_command` |

### 4.11 E2E key exchange (legacy and current)

| Name | Dir | Payload | Reply |
|---|---|---|---|
| `/pubkey <base64>` / `/getpubkey <user>` | C>S | | `{"type":"pubkey","user":"bob","key":null}` (legacy; UNCLEAR whether current clients still use it) |
| `/sd e2e.status / register / remove / devices / group_devices` | C>S | `{"users":["bob"]}` ; `{"group":"g"}` ; `{"id":..,"ecdh":..,"sign":..,"label":..,"proof":..}` | `data` per `docs/E2E_ENCRYPTION.md` |

## 5. Source files used
`src/services/connectumSocket.js`, `src/services/connectumApi.js`, `src/features/connectumChat/ConnectumChatScreen.jsx` (event handlers around lines 940 to 2200, `forceSignOut` 3713), `src/features/connectumChat/utils/useLiveChanges.js`, `src/features/connectumChat/services/workspaceAgent.js`, `aiHistory.js`, `src/features/connectumChat/e2e/*`, `tests/frontend/socket.test.mjs`, `axi-chat-backend/src/chat_web.erl`, `chat_room.erl`, `chat.hrl`, `chat_cmds.erl`, `sd_cmds.erl`, `sd_notify.erl`, `sd_policy.erl`, `sd_auth.erl`, `sd_cards.erl`, `sd_feed.erl`, `sd_formmsg.erl`, `sd_reqs.erl`, `sd_subflow.erl`, `sd_tasks.erl`, `sd_conv.erl`, `docs/CHAT_PROTOCOL.md`, `docs/CONNECTUM_API.md`, `docs/MULTI_ENTERPRISE.md`.
