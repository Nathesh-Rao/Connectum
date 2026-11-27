# My Work Space notes: sync with the server (recon)

Recon only. No app code was changed, nothing was built or tested. Written 25 Nov 2026.

Sources read (web repo `~/Development/Axi-apps/connectum/`, read-only, no git): `docs/WORKSPACE_MESSAGES_SPEC.md`, `docs/CHAT_PROTOCOL.md`, `docs/E2E_ENCRYPTION.md`, `docs/MESSAGE_CACHE.md`; `chat-app/features/connectumChat/{chatEvents/{selfMessages,history,index,connection}.js, utils/{messageCache,convOfChat,useMessageMarks}.js, chatActions/{send,attachFile,editMessage}.js, ConnectumChatScreen.jsx}`, `chat-app/services/connectumSocket.js`; `tests/frontend/workspaceMessagesLive.test.mjs`; `connectum-backend/test/connectum_selfmsg{,_e2e}_test.mjs`; `connectum-backend/src/{chat/chat_room.erl, chat/chat_store.erl, http/chat_web.erl, http/chat_web_send.erl}`.

**Caveat on the version read.** `WORKSPACE_MESSAGES_SPEC.md` line 3 says the feature is on the branch `feat/workspace-messages`, "NOT on `dev` and not released". I read the working tree and could not run git there, so I cannot confirm that the files I read are the same as `origin/dev`. The protocol rows in `CHAT_PROTOCOL.md` (lines 113, 137-140, 168, 190-193) are present in the tree. Confirm the BE release that carries `/self` before phase 1 ships.

---

## 0. Two corrections to the brief

1. **The web never migrated old notes, because it never stored them.** Before this change the notes lived only in React state (`messagesByChat` in `ConnectumChatScreen.jsx:183`, a `useState`). They were not in IndexedDB or localStorage. The only IndexedDB database is `connectum-msgs`, which caches server history windows (`messageCache.js:12-13`). A reload lost them. The spec states the decision: "The old workspace messages (typed before this ships) are gone with the page and are not recovered" (`WORKSPACE_MESSAGES_SPEC.md`, section 7 item 3). Nothing uploads, merges or drops old notes: `selfMessages.js`, `history.js`, `index.js`, `connection.js`, `messageCache.js` and `convOfChat.js` contain no migration code. On sign-out the screen keeps only the welcome line (`utils/workspaceMessages.js:6`, `ConnectumChatScreen.jsx:1125`).
2. **The phone has no local free-text notes to migrate.** Free text is off in the mobile workspace. `WorkspaceController.send()` (`lib/features/workspace/workspace_controller.dart:295`) accepts only a `#` command or `@name text`. Anything else shows `nudgeText` (`:76`) and is "sent nowhere". `WorkspaceNote` (`lib/features/workspace/models/workspace_note.dart`) is an in-memory row for a `#` answer or "Sent to @name". It is never written to SQLite. There is no workspace row in `messages`, `conversations` or `outbox` (`lib/data/db/app_database.dart:29-70`). So "never lose notes on the first sync" is satisfied by default: there are none. Section B.4 says what to do anyway.

---

## A. Web behaviour

### A.1 Sending
- Composer to socket: `chatActions/send.js:79-81`. In `workspace`, `connectumSocket.sendSelf(text, validReplyId)`. The reply id must be a real server id (`send.js:73-76`: not `temp-` and not `ws-`).
- Wire: `/self <text>`, or `/replyself <id> <text>` (`connectumSocket.js:576-578`). It goes through `sendProtected('self', me, ...)` (`:463-476`). When the org encrypts, the text is turned into an `e2e1:` envelope for `conv = self:<username lowercase>` first.
- **The web does not use a `cid` for `/self`.** `sendProtected` calls `this.send(build(out))` with no `/c <cid>`. The BE supports it (`chat_web.erl:1175-1176` lists `/self` and `/replyself`), but the web does not use it. The web's only retry is the `e2e_stale_devices` re-send (`connectumSocket.js:481`, `staleRetry`, at most twice). The mobile app will do better than the web here.
- A temp message `temp-<ms>` is added with `status: "sending"` (`send.js:58-70`). For `workspace` it is not marked `sent` locally (`send.js:118-121`). It waits for the server.
- Attachments: `attachFile.js:57-58` sends the `[ATTACHMENT:{json}]` tag as a note through `sendSelf(wireTag)`, encrypted for the person's own devices (`attachFile.js:11`). The live copy is matched back to the pending row by `wireText`.

### A.2 Offline and failure
- `sendProtected` returns `false` when the socket is not open (`connectumSocket.js:464`). `send.js:109-115` then adds the message as `failed` with the toast "Cannot send message: disconnected from server". **No queue, no automatic retry on reconnect.** An encryption failure raises `e2e_send_failed`, which marks the chat's pending messages failed (`connection.js:39-42`).
- The spec's "retry, exactly as a direct chat does" (section 4) is what the existing failed-message UI offers. There is no outbox on the web.

### A.3 Acks and statuses
- `self_ack {id, ts, status:"delivered", cid?, duplicate?}`. `onSelfAck` (`selfMessages.js:45`) gives the **first** still-pending outgoing message the stored id and status `sent`. It has no cid to match on, so it is first-pending-wins. A repeated ack for an id already on screen changes nothing.
- The web shows **no "delivered" status**. `status` becomes `sent` and `ticks` becomes `read` (`adopt`, `selfMessages.js:16`). The BE's `delivered` is kept only as `serverStatus` (`:54`). A note has no recipient, so there are no tick states to show.
- The sender also gets its own `self_message`. `onSelfMessage` (`:19`) handles either order of ack and event: it skips an id already on screen, otherwise adopts the first pending row whose text equals the event text or `wireText`. If the live copy could not be decrypted (`event.e2eFailed`), the one still pending is it. This is tested in `workspaceMessagesLive.test.mjs:39-60`.

### A.4 Showing the thread, and what is mixed in
- The thread is `mergeByTime(messages, cardsHere)` (`ConnectumChatScreen.jsx` about 1490-1497). `messages` are the notes. `cardsHere` is `mwsSubmissions` (my submissions), `apiMessageCards(priorityNotifications)` (Message API items) and `approvalCards(...)`, sorted by `ts`. Records and tickets come from their own sources and are **not** stored as notes. A private AI summary is appended at the end, on that person's screen only.
- The welcome line is local, id `ws-msg-1` (`utils/workspaceMessages.js:3`), always first, and is never stored (`history.js:174`).
- `#` commands go through `routeHashCommand.js`. They and their results are temporary and not kept (spec section 1 item 2). They never reach `/self`.
- Notes are all `dir:"out"` with `from = me`. There are no reactions (`MessageList.jsx:883`, `canReact={!workspaceChat}`). I found no per-chat message search code on the web. I cannot say how notes are searched, if at all.

### A.5 History: load and paging
- Opening or reconnecting calls `connectumSocket.sendHistory("self")` (`ConnectumChatScreen.jsx:627`, `chatEvents/connection.js:25-26`). The wire line is `/history self` with no name (`connectumSocket.js:697-700`).
- The device cache is used as for other chats. `convKey(user,"self","")` is one entry per enterprise and person (`messageCache.js:20-24`). A cache hit is shown at once (`fromCache`), then `/history self delta <lastId> <now>` is sent (`connectumSocket.js:697-720`, `docs/MESSAGE_CACHE.md`). The server answers with changed messages plus `window` (the ids in the conversation now), and the client merges (`mergeDelta`, `messageCache.js:39`). A delta naming an unknown id drops the cache and asks for the full history.
- Page size is 50 (`WORKSPACE_MESSAGES_SPEC.md` section 4, "paged (50 at a time), the cache keeps the last 50"). Older pages use `before <messageId>` with `hasMore` and `next` (`chat_web_send.erl:203-231`). The server test checks 60 messages: first page 50, then 12 and `hasMore:false` (`connectum_selfmsg_test.mjs:62-70`).
- `onHistory` (`history.js:55-180`) maps scope `self` to chat id `workspace`, drops `deleted` entries, resolves `replyTo` quotes from the same list, and keeps still-pending local rows and the welcome line. It sets the sidebar preview from the last note (`:147-152`).

### A.6 Edit, delete, reply, pin, save
- **Edit:** `/edit self <id> <text>` (`connectumSocket.js:658-660`), encrypted for self when the org encrypts. Server window is `CHAT_EDIT_WINDOW_SEC`, default 900 s (`chat_room.erl:201-205`, `:438-447`). All connections get `self_edited {messageId, text, editedTs}`. Another person's note answers `edit_denied not_found`, the same as a missing one. There is no ack, only the event.
- **Delete:** `/delete self <id>` (`connectumSocket.js:646-647`). The server checks the conversation key, not just the sender (`chat_room.erl:425-437`). All connections get `self_deleted {messageId}`. The web also removes the row locally at once (`ConnectumChatScreen.jsx` about 785-798). History marks it `deleted` and the web filters it out.
- **Reply:** `/replyself <id> <text>`. The reply target must be in the person's own conversation (`chat_room.erl:500-507`), else the error "No such message in your own conversation to reply to". `self_message` and history carry `replyTo` (an id). The web resolves the quote on screen (`selfMessages.js:11-14`, `history.js:96-109`).
- **Save and pin:** `connectumSocket.sd('msg.save' | 'msg.unsave' | 'msg.pin' | 'msg.unpin' | 'msg.pins', {conv:"self", id})` (`useMessageMarks.js:43-69`). `marksConvOfChat('workspace')` is `"self"` (`convOfChat.js:12`). Saved is private to the person. A pin in `self` is only theirs ("Pinned" versus "Pinned for everyone in this chat", `useMessageMarks.js:62`). The Saved list names it "My Work Space" (`utils/savedMessages.js:5`). Events `saved_changed` and `pins_changed {conv}` refresh other devices (`useMessageMarks.js:29-39`). Saved and pinned items for `self` come back as narrowed envelopes. `connectumSocket.js:106-113` `opened()` has a label only for `dm:` and `group:`, so I could not confirm the web opens a saved or pinned `self` envelope (see D.9).
- **No reactions.** `/react` is refused. The BE test checks nobody gets a reaction event (`connectum_selfmsg_test.mjs:111-133`). The old `/delete global|dm|group` commands do not reach a self note.
- **Forward** works as for any message (spec section 2).

### A.7 Migration of old notes
None. See section 0 item 1.

---

## B. Mobile today

### B.1 Storage
No table or row holds free-text workspace notes. Schema v16 (`app_database.dart:29`): `messages` (`:43`, keyed `org_id,user_id,msg_id`, columns `conv_id, sender, is_mine, kind, text, ts, reply_to, status, is_encrypted_unsupported, edited_ts, is_deleted, reactions_json, form_json, preview_json, fail_reason, local_seq, cid, plaintext, decrypt_state`), `conversations` (`:37`, has `is_list_hidden` since v10), `outbox` (`:62`, has `cid`, `first_attempt_ts`), `sync_cursor` (`:68`: `last_server_id, last_history_now, has_more, next_id, gap_to`).

### B.2 How the thread is built
`WorkspaceController._apply()` (`workspace_controller.dart`) merges three sources into `rows`, newest first, grouped by day. These are my submissions (`SubmissionRepository`), received records (`WorkspaceRepository.received`, from `records.mine` involved and with) and in-memory `WorkspaceNote`s. The welcome text is built in the controller (`welcome`). The composer (`widgets/workspace_composer.dart`) has a forms button, a `#` commands panel and `@name`. There is no message list for notes and no reply, edit, delete, save or pin UI in the workspace screen. `WorkspaceRepository` (`lib/data/repositories/workspace_repository.dart`) only reads records and does no note sync.

### B.3 Sends, outbox, cid, encryption (the chat path it would reuse)
- `MessageRepository.sendText` (`message_repository.dart:477`) writes a `messages` row with `temp-<ts>` and an `outbox` row (`kind` `message` or `reply`, with a `cid`) at once. `flush()` (`:736`) sends one entry per conversation in flight. `_commandFor` (`:970`) builds `/msg`, `/groupmsg`, `/hostmsg`, `/replydm`, `/replygroup`, `/edit dm|group|global`. `wireCommand` (`:951`) wraps it as `/c <cid> ...`. **There is no `self` branch**: `_commandFor` returns text for an unknown kind, which would send the note to global chat. `ConversationRepository.targetOf('self')` also returns `'self'`, because there is no colon (`conversation_repository.dart:634`).
- Acks: `_ack` (`:1423`) matches by cid in `outbox` for `kind IN ('message','reply')`, with or without `duplicate`. `_ackTimeout` is 15 s, `_maxAttempts` 5, and an entry first sent more than 23 h ago fails with "couldn't confirm delivery" (`_isPastCidMemory`, `:794`).
- **Encryption of self notes today: none.** `EncryptionPolicy.evaluate` (`encryption_policy.dart:54`) returns `plain` for any conversation whose kind is not `dm` or `group`. So a naive "send to `self`" would go out **in plain text** even when the org requires encryption. That would break the "never downgraded" rule. `E2eRepository.expectedConv` (`e2e_repository.dart:1072`) knows only `dm:` and `group:`, so an incoming `self:` envelope could not be opened either. `seal` (`:692`) needs a decision with recipients. `decide` (`:96`) is built around a peer, and for self there is no peer: recipients are my own devices.
- Edits in encrypted chats are refused today with "Editing isn't supported in encrypted chats yet" (`message_repository.dart:853`). So an edit of an encrypted self note cannot be sent yet.
- Reply, edit and delete exist for DMs, groups and global (`:970-1000`, `:360`, `:638`). Delete needs the connection. Reactions are not offered in self (BE refuses).
- Save and pin: not implemented anywhere (`workspace-notifications.md:56` and `:86`, grep finds nothing in `lib/`). No `msg.save`, `msg.pin` or `msg.pins` calls and no `saved_changed` or `pins_changed` handling.

### B.4 Receiving today, and the drop
- `SocketService._handleFrame` (`socket_service.dart:314-323`) drops `self_message`, `self_edited`, `self_deleted`, `self_ack` (also inside an `sd_event`) with `AppLog.d('ignored ...')`, through `selfEvents` and `selfEventName` (`:294-312`). They never reach any repository. `test/socket/self_events_test.dart` asserts the drop.
- `MessageRepository._onHistory` (`:1924-1936`) maps `global|dm|group|host` and ignores any other scope, so `scope:"self"` is discarded.
- History is full-page only (`/history <scope> [before <id>]`). Mobile does not use `delta` (no `delta` in `lib/data`). `_syncConversation` (`:1154`) pages back at most 10 pages until my last known id is found.

### B.5 What would change (summary)
| Area | Change |
|---|---|
| `socket_service.dart` | Remove the drop. Let the four events through to `events`. Keep them redacted in `_log` (`Redact.event`: add `self_message.text`, `self_edited.text` and the history `list[].text` for `self` to `LogRedaction`). |
| `conversation_repository.dart` | `self` conv id. Fix `kindOf`/`targetOf` for an id with no colon. Hide it from the chat list (`is_list_hidden`), never unread, never push. |
| `message_repository.dart` | Scope `self` in `_onHistory`. Handlers for the four events. `self` branch in `_commandFor`, `_ack` and the outbox. Do not count `self` as unread or notify. |
| `encryption_policy.dart`, `e2e_repository.dart`, `e2e_crypto.dart` | A `self` rule (recipients = my own devices, label `self:<me lowercase>`). Open `self:` envelopes. Seal edits (or keep edits blocked for encrypted notes). |
| `workspace_controller.dart`, `workspace_composer.dart`, new widgets | Show notes among the cards. Free text becomes a note. Reply, edit, delete, save, pin menu. `#` commands and `@name` stay as they are (not stored). |
| New | `msg.save/unsave/pin/unpin/pins/saved` client calls and event handling (none exist today). |
| `app_database.dart` | Probably no new table: use `messages` rows with `conv_id='self'`. A version bump only if a new column is needed (for example none). |

### B.6 Handling of notes already on the phone when sync turns on
- There is nothing stored, so nothing to upload, merge or keep. After the update the thread simply fills from `/history self`.
- Keep `WorkspaceNote` for `#` answers and "Sent to @name" (BE: `#` commands and results are not stored).
- One edge to guard: a note typed while an older build runs does not exist, so no guard is needed. If a future build ever stores a pending self note locally before sync is on (for example during a staged rollout), it should enter the outbox with a `cid` and be sent, never dropped.

---

## C. Mapping and phase plan

### C.1 BE to mobile mapping

| BE | Direction | Mobile component |
|---|---|---|
| `/self <text>` (with `/c <cid>`) | send | `MessageRepository.sendText` for conv `self`, outbox kind `message`, `_commandFor` self branch |
| `self_ack {id,ts,status,cid,duplicate}` | event | `_ack('self', e)`: match by cid, swap temp id, adopt `ts`; `duplicate` is a normal ack |
| `self_message {id,ts,text,replyTo}` | event | New handler: insert or ignore by id; if it is my in-flight send, merge (see C.3); decrypt `self:<me>` |
| `/replyself <id> <text>` (cid ok) | send | outbox kind `reply` for `self` |
| `/history self [before <id>]` | request | `_fetchHistory` and `_syncConversation` with scope `self` (no name); `_onHistory` scope `self`; `hasMore`/`next` as now |
| `/history self delta <id> <now>` | optional | Not used by mobile for any chat; skip (SQLite is the cache) |
| `/edit self <id> <text>` | send | outbox kind `edit` for `self`; no ack, the `self_edited` event confirms |
| `self_edited {messageId,text,editedTs}` | event | Update text, `edited_ts`; decrypt |
| `/delete self <id>` | send | `MessageRepository.deleteMessage` self branch (connection needed, like today) |
| `self_deleted {messageId}` | event | `_setDeleted(id)` |
| `msg.save/unsave {conv:"self",id}`, `msg.saved`, `saved_changed` | sd call and event | New saved-marks client; list names "My Work Space" |
| `msg.pin/unpin/pins {conv:"self"}`, `pins_changed` | sd call and event | New pins client; the pin is private to the person |
| `e2e.devices` (my own) and `self:<me>` label | encryption | `EncryptionPolicy` self rule, `E2eRepository.expectedConv` and `seal` |
| `/react` | refused | Never offered |

**What replaces the drop in `_handleFrame`:** delete `selfEvents`/`selfEventName` and the early `return` (`socket_service.dart:294-323`). The frames go on through the normal `_log(Redact.event)` and `events` stream. `MessageRepository._handle` (`:1356`) gets the four new cases. The `AppLog.d('ignored')` line goes. `test/socket/self_events_test.dart` changes from "dropped" to "delivered". Do this in the same phase as the handlers: delivering events with no handler is harmless, but an unhandled `self_message` must never be turned into unread, push or a chat row.

### C.2 Phases (each shippable on its own)

| # | Phase | Contents | Size | Needs BE answer? |
|---|---|---|---|---|
| 1 | **Receive** | Remove the drop. `self` hidden conv. `_onHistory` scope `self`, paging with `before`, reconnect sync, `self_message`/`self_edited`/`self_deleted` into `messages`. Show notes in the workspace thread among the cards (read-only: no free-text composer yet). **Read-side decrypt of `self:<me>` envelopes lands here**, otherwise an encrypted org shows only locked rows. Notes from other devices appear, offline shows the cached rows. | medium | Q1 (version on dev), Q4 (new device reading), Q9 (ordering) |
| 2 | **Send** | Free text in the workspace composer becomes a note. Outbox with `cid` for `self`, `self_ack` matching, `_commandFor` self branch, pending, retry, "couldn't confirm delivery" after 23 h, one in flight, the shared pacing. **The encryption rule for self lands here too** (recipients = my other devices plus this one; blocked, never plain, when required or when the thread is encrypted). Do not ship a plain send path first. | large | Q2 (single-device case), Q3 (limits), Q7 (self_message vs ack order, cid on `self_message`) |
| 3 | **Edit, delete, reply** | Menu on a note. `/replyself`, `/edit self`, `/delete self`. Edit in an encrypted org needs sealing for edits (today blocked at `message_repository.dart:853`), so either build it here or keep "Editing isn't supported in encrypted chats yet" for notes. Edit window 15 min applies. Reply quote needs the target id to be a server id. | medium | Q5 (offline edit/delete rules) |
| 4 | **Save and pin** | New `msg.*` client (nothing exists on mobile), `saved_changed`/`pins_changed`, a pinned bar in the workspace, a Saved list entry "My Work Space". Reading a narrowed `self` envelope in `msg.saved`/`msg.pins`. | medium | Q8 (does the BE return `self` items with a label the device can open) |
| 5 | **Encryption hardening** | New-device history (device added later reads old notes through the usual history sync, `mobile-handoff/history-sync-older-device.md`), single-device person, key change on my own device, `e2e_stale_devices` re-send for `self` (once), recovery device. | medium | Q2, Q4, Q10 |
| 6 | **Migration of old local notes** | No local notes exist (section B.6). Work is a guard and a test: first sync with an empty phone fills from history, plus the optional "queue pending note if one ever exists" rule. | small | Q6 (confirmation only) |

Dependencies: 1 before everything. 2 needs the encryption rule. 3 needs 2. 4 only needs 1. 5 can start after 2.

---

## D. Questions for the BE

1. **Which release carries `/self`?** The spec says branch `feat/workspace-messages`, not on `dev`, not released (spec line 3). Which BE version and environment can the phone test against, and does the dev machine have it?
2. **One-device person.** The spec's own open question is whether `sd_e2e:validate` refuses a conversation with one member (spec section 5). The tests use two devices (`connectum_selfmsg_e2e_test.mjs:25`, "Ann has two devices"). With one device the only box is the sender's own. Is that accepted, or does a person with one device get `e2e_stale_devices` or `bad_envelope`? Does the recovery device count as a box that must be present?
3. **Limits.** `MAX_MESSAGE_LEN` is 2000 characters (`chat.hrl:6`) and an envelope has its own cap (`sd_e2e:max_len`, `chat_web_send.erl:56-60`). What is the longest note a phone can type when encrypted? Is there any cap on the number of notes (the spec says none "for now", with LRU later)? What are the history page size, the `hasMore` behaviour and a maximum depth?
4. **New phone or new device and old notes.** Notes sealed before this phone existed have no box for it. The doc says the usual history sync (a device already in use hands the past on) covers it. Does that cover `self:` conversations? What does a person with only one device and a new phone see (nothing readable, even with the recovery key)?
5. **Edits and deletes while a device was offline.** Edit has a 15 minute window (`CHAT_EDIT_WINDOW_SEC`, `chat_room.erl:201`). A queued offline edit may be refused with `edit_denied`. Should the app retry, drop with a message, or keep as a new note? Is a delete allowed at any age? A repeat of an edit or delete has no `cid`. Is it safe to send again after a dropped connection (delete a second time: `not_found`; is an edit twice harmless)?
6. **Local notes on first sync.** Confirm there is no import: nothing is uploaded from the clients, the web dropped its old notes (spec section 7 item 3) and mobile has none. Is there any BE-side import or backdated `ts` path, or must every note be newly created with server `ts`?
7. **Ack and event order, cid on the event.** `do_self` pushes `self_message` to the person's connections before returning the ack to the caller (`chat_room.erl:500-507`), so the sending connection may see the event before `self_ack`. `self_message` carries no `cid`. For an encrypted note the sending device can match by the envelope `mid`, for plain text only by text. May the BE add `cid` to `self_message` for the sending connection?
8. **Saved and pinned `self` items.** `msg.saved` and `msg.pins` return a narrowed envelope per the notes in `MOBILE_OPEN_QUESTIONS.md`. For `conv:"self"`, what `conv` label does the device open it with (`self:<me>`)? Is `conv:"self"` in `msg.saved` items accepted as is?
9. **Ordering and concurrency.** Two devices send at once: ordering is "server `ts` and id" (spec section 4). Is the id strictly increasing across devices (the phone must not compare ids numerically, per the repo rule)? If `ts` differs between devices (clock skew), which key does history sort by? Does the `before` page boundary use id?
10. **Duplicate window.** The `cid` is remembered for `CID_TTL_SEC` (default 86400, max 604800, `chat_web.erl:1170`). Is 24 h the value in production? The app fails an entry after 23 h. Is the memory per user and per cid (`chat:cid:<Name>:<cid>`), so the same `cid` cannot clash between conversations?
11. **Attachments and forms in a note.** The web sends attachments as the `[ATTACHMENT:{json}]` tag through `/self` (`attachFile.js:57`). Is that the contract for the phone too (upload first, then the tag)? Can a form or a record be a note? The spec says `#` results and cards are never stored. Confirm that a form posted from the workspace stays outside `self`.
12. **Rate limit.** `/self`, `/replyself`, `/edit self`, `/delete self` and `msg.*` count against the 30 per 10 s per connection (`check_rate_limit`). Confirm there is no separate limit for `self`.
13. **Deletion semantics.** History marks `deleted:true` for a deleted note. Is the row ever purged, and does `self_deleted` come for a note deleted on the same connection that sent it?

---

## E. Risks

1. **Plain text into an encrypted org.** `evaluate` returns `plain` for any kind other than `dm` and `group` (`encryption_policy.dart:54`). If `self` is sent before the self rule exists, notes go out unencrypted. The first send build must not exist without the rule. (Phase 2.)
2. **A note sent as a global message.** `_commandFor` falls through to plain `text` for an unknown kind (`message_repository.dart:970-980`). A `self` outbox entry without its branch would be posted in the global room.
3. **Duplicates after retry.** Mitigated by `cid` and `duplicate:true`. The remaining gap is the order of `self_message` and `self_ack` (D7): two rows can appear for one send if the event arrives first and the match fails. Dedupe by server id on insert, and merge the temp row when the ack arrives for an id already present.
4. **Losing local notes on first sync.** No local notes exist, so no loss. The risk to check is the other direction: a sign-out wipe followed by a history sync must refill everything. For encrypted notes that depends on this device being able to read them (E5).
5. **Unreadable own notes.** A phone that was reinstalled, or a second phone, has no box for old envelopes. A person with one device, no recovery key and no other device cannot read old notes (D2, D4). Plain notes are unaffected.
6. **Ordering.** The thread merges notes and cards by `ts` (`_apply` sorts by `ts`). Notes use the server `ts`, cards use theirs, and a pending note uses the phone clock. A pending note can jump after its ack gives the server `ts`. Keep the local order for pending rows (`local_seq`).
7. **Key boxes for a person with one device** (see D2). If the BE refuses a one-box envelope, every encrypted note from a one-device person fails.
8. **Rate limits.** Each note is a command. Today's outbox pacing (under 30 per 10 s) and one in flight per conversation cover it. `msg.save`, `msg.pin`, `msg.pins` and `msg.saved` are reads or writes and must go through the shared `ReadGate` or the outbox rules, not a new counter (CLAUDE.md, command budget). History reads for `self` use the same gate as any chat sync.
9. **Offline-first rules (CLAUDE.md).** SQLite is the only source the screen reads. The workspace must open offline with cached notes and no offline state (it is cached-first). A send writes the row and the outbox entry at once. `failed` only for non-retryable refusals or an unconfirmed delivery, never for a network drop. A `session_replaced` wipes `self` rows with the rest. A sign-out wipes them. Never log note text (add `self_*` to `LogRedaction`, check `Redact.event`).
10. **Unread, sound, push.** The server sends none for `self`. The app must not count `self` messages as unread, not raise a local notification, and not show the hidden conversation in the chat list (`is_list_hidden`).
11. **Edit window and queued edits** (D5): an edit queued offline for longer than 15 minutes will be refused.
12. **Plaintext at rest.** Notes follow the existing decision (`plaintext` column holds decrypted text, listed under "Before release" in CLAUDE.md). They are as sensitive as DMs. No change, but note that the self conversation is added to that decision.
13. **Spec not on `dev`** (D1): building before the BE release would test against a server without `/self`.
