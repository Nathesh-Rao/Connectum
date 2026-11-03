# Connectum Backend — WebSocket Protocol

What the frontend team builds the frontend chat UI against today. Source
of truth is `connectum-backend/src/http/chat_web.erl` — if this doc and the code
ever disagree, the code wins; flag it to the backend owner to fix the doc.

> **Connectum (organisation, users, hosts, approvals, login, cards, forms, admin
> console) is documented separately in [`CONNECTUM_API.md`](CONNECTUM_API.md).**
> It adds one WebSocket command (`/sd <action> {json}`), a small REST API
> under `/api/sd/`, and — only when the backend runs with
> `CONNECTUM_MODE=strict` — extra rules on the commands below. In the default
> `open` mode everything in *this* document behaves exactly as written.
> New here: refused chat commands may carry a machine-readable
> `{"type":"error","code":"not_associated"|"not_allowed","text":…}`.
>
> **`#commands` (Discord-style action menu for the prompt bar) are documented
> in [`HASH_COMMANDS.md`](HASH_COMMANDS.md).** Typing `#` opens a menu of every
> feature; the server rewrites a `#command` into the `/command` below, so all
> the events in this document are unchanged. New frames: `/cmds`,
> `/cmdcomplete`; new events: `cmd_catalog`, `cmd_suggestions`, `cmd_help`.

**Scope note, read this first:** this documents the real-time messaging
transport plus the host directory — connect, DM, group chat, host
messaging, reactions, typing, uploads. The **directory itself** is real
today (`/hosts` lists the fixed preconfigured hosts always, per the boss's
spec) but **department hosts are empty until the backend dev creates the
chat-host tstruct** — the mechanism is wired end-to-end, there's just
nothing configured to return yet. The **prompt engine**
(List/Input/Upload/Download/Payment/OTP as a configurable per-host
interaction unit) doesn't exist at all yet — that's separate, future work
(Phase 3+ in `NEXT_STEPS.md`).

---

## Connecting

1. Open a WebSocket to the backend.
   - **Local dev** (running `connectum-backend` standalone, no nginx in
     front): `ws://localhost:8080` — root path, no prefix.
   - **On the deploy VM** (behind nginx, which also serves this frontend's
     build at `/`): `ws://<vm-host>/ws` — nginx routes `/ws` specifically
     to the backend; `chat_web.erl` itself doesn't care what path a
     WebSocket upgrade arrives on, so this is purely nginx's routing
     choice, not a protocol detail. `/upload` and `/uploads/*` are routed
     the same way for file attachments.
   - Whatever environment you're in, the frontend needs to pick the right
     URL — this is not something the protocol itself can tell you at
     runtime.
2. The **first text frame you send must be JSON**, not a bare string:
   ```json
   {"username": "alice", "token": "<session token>"}
   ```
   **Updated 24 Sep 2026 — the ARM sign-in is no longer part of this
   handshake.** The app signs in with its own Connectum login
   ([`CONNECTUM_API.md`](CONNECTUM_API.md)) and `token` is the session token that
   login returns. **`armSessionId` is now optional** (omitted or empty → the
   backend uses `"app"` and never interprets it); a client that still forwards
   the old ARM values (`token` = ARM token, `armSessionId` = ARM session id
   from `shared/connectum-standalone-bridge.js`) keeps working unchanged. In the
   default `open` mode any non-empty `token` is accepted for **plain chat**; in
   `strict` mode it must be a live Connectum session for exactly this username. A
   Connectum session ends after **15 days** — an open connection is then sent
   `{"type":"sd_event","event":"session_expired",…}` and closed.
   `username` max 24 chars, **no spaces or control characters** (rejected at handshake — a name with a space can never be addressed by `/msg`). In a Connectum organisation (strict mode) usernames are stored in **lower case** and the handshake must use exactly that (`CaseGuy` is refused: "That session belongs to a different username"; spaces around the name are trimmed). In the open mode of the plain chat they are case-sensitive. Always send the lower-case form, as the web client does.
   **Reconnecting.** A connection that opens with a live session while the same person's previous socket is still registered takes it over **at once** (no waiting time and no "Username taken"):
   the old socket receives `{"type":"sd_event","event":"connection_superseded","reason":"opened_elsewhere"}` and is closed. A fresh **sign-in** on another device ends the old session instead:
   the old socket receives `session_replaced` with `signed_in_elsewhere`. "Username taken" only appears for the old handshake with no Connectum session (open mode). A takeover is not
   a trip offline and back: no `presence` event is sent for it.
3. Server replies:
   - Success: `{"type":"welcome","name":"alice"}`, immediately followed by
     a `history` event for the global room (see below).
   - Failure: `{"type":"error","text":"..."}` — malformed/missing fields,
     empty/too-long username, or username already taken. Connection stays
     open, retry with a corrected payload on the same socket.

**Security note — read this before assuming more than it claims.** *(This
paragraph describes the earlier ARM-token handshake and still applies to plain
chat in `open` mode. In `strict` mode the backend verifies identity itself with
sessions it issued — see `CONNECTUM_API.md` §1–§3.)* This
is **not** independent cryptographic re-verification of the token.
`ARMToken` is an HMAC-signed JWT (confirmed from the real `AXput` release
notes' worked example), which by construction can't be verified by
anyone without ARM's own signing secret — unlike the RS256 tokens the old
ConnectumChat project's Google/Apple sign-in could check against a public JWKS.
There's also no documented "verify this session" ARM endpoint to call
instead. What this buys: a connection now requires having actually gone
through a real ARM sign-in (the browser blocks the app until Signin
succeeds), rather than the previous behavior of accepting literally any
typed string as an identity. It does not confirm the token is *currently*
still valid — that only gets checked the first time it's actually used
for a real ARM API call.

Once connected, every message you send is a **plain-text command** (not
JSON); every message you receive is a **JSON event**. This is intentionally
asymmetric — commands are cheap to parse server-side, events are easy to
consume client-side.

---

## Commands you send (plain text, one per WS text frame)

| Command | Effect |
|---|---|
| `/list` | Server replies with `{"type":"users","list":[...]}` — currently-online usernames. |
| `/hosts` | Server replies with `{"type":"hosts","list":[...]}` — the full host directory (see "Host directory" below). |
| `/hostmsg <hostKey> <text>` | Send a message to a **department** host (see below — do NOT use this for `llm`/`workspace`-kind hosts). Reply: `host_ack` event, or an error if the host doesn't exist or has no one assigned yet. |
| `/msg <username> <text>` | Send a DM to another associate. Reply: `dm_ack` event with `status` `"delivered"` (recipient online, pushed live) or `"queued"` (recipient offline but has connected before — stored, and they read it after reconnecting via `/conversations` + `/history dm`). Error `No such user` only if that username has never connected. |
| `/conversations` | Reply: `conversations` event — every DM thread you have, newest first, each with the last message. How a client discovers who messaged it while it was offline. Threads you deleted for yourself are left out until something newer arrives. |
| `/reply <messageId> <text>` | Reply to a message in the **global** room. |
| `/replydm <username> <messageId> <text>` | Reply to a message within a DM thread. |
| `/history global` | Re-fetch global room history (also sent automatically on connect). |
| `/history dm <username>` | Fetch DM history with that user. |
| `/history group <groupName>` | Fetch a group's history. |
| `/history host <hostKey>` | Fetch your history with a department host. |
| `/history <scope …> before <messageId>` | The page of up to 50 messages **older** than that id (oldest first), for scrolling back. The `history` event carries `before`, `hasMore` (more older messages exist) and `next` (the id to ask with next, `null` when the page is empty). Works for `dm`, `group` and `host`. A conversation the person cleared stays cleared. `before` without a number is an `error` with code `usage`. |
| `/c <clientId> <command>` | Send with a **client id**, so a retry after a lost connection does not send twice. Runs `<command>` as usual; the ack carries `"cid":"<clientId>"`. The same id again from the same person (within a day, `CONNECTUM_CID_TTL_SEC`) sends nothing and returns the first ack again with `"duplicate":true`. Works for `/msg`, `/replydm`, `/groupmsg`, `/replygroup`, `/hostmsg` (and their `#` shortcuts); any other command or a plain global message is an `error` with code `cid_unsupported`. The id is 1–64 characters of letters, digits and `- _ . :` (else code `bad_cid`). A send that was refused is not remembered, so the same id can be retried once the cause is fixed. |
| `/read dm <username>` / `/read group <name>` | I have read that conversation. Kept on the server (the read position, see `conv.read` in SD_ACTIONS_REFERENCE.md); a direct conversation also gets the live `dm_read` to the other person when they are online. |
| `/typing global` | Broadcast a typing indicator to the global room. |
| `/typing dm <username>` | Broadcast a typing indicator to that DM. |
| `/typing group <groupName>` | Broadcast a typing indicator to that group. |
| `/read dm <username>` | Mark a DM thread as read (triggers `dm_read` to the other party). For a signed-in Connectum user it also clears that sender's *personal/priority* notifications and pushes `notifications_changed` ([`CONNECTUM_API.md`](CONNECTUM_API.md) "Notifications"). |
| `/pubkey <base64Key>` | Publish your E2EE public key (for DM encryption support — currently only consumed by the iOS client's crypto, not yet by any web/React flow). |
| `/getpubkey <username>` | Fetch another user's public key. |
| `/setavatar <url>` | Set your avatar. Only an `/uploads/…` path or an `https://…` link (max 300 chars, no spaces/control characters); anything else gets an `error`. Broadcasts a `profile` event. |
| `/removeavatar` | Remove your avatar. Broadcasts a `profile` event with `avatar: null`. |
| `/setstatus <text>` | Set your status line. Same broadcast as above. A bare `/setstatus` (or only spaces) **clears** it: everyone gets the `profile` event with `"status": null`, and `/getprofile` then also says `null`. |
| `/getprofile <username>` | Fetch another user's avatar/status. |
| `/gifsearch [query]` | Search GIFs (Giphy-backed). Reply: `gif_results` event. |
| `/stickersearch [query]` | Same, for stickers. Reply: `sticker_results`. |
| `/react global <messageId> <emoji>` | Toggle a reaction on a global message. |
| `/react dm <username> <messageId> <emoji>` | Toggle a reaction on a DM message. |
| `/react group <groupName> <messageId> <emoji>` | Toggle a reaction on a group message. |
| `/delete global <messageId>` | Delete your own message (sender-only, enforced server-side). |
| `/delete dm <username> <messageId>` | Same, for a DM. |
| `/delete group <groupName> <messageId>` | Same, for a group message. |
| `/creategroup <name>` | Create a group (you become the sole/owner member). Max 32 chars, **no spaces** (use e.g. `design_team`) — `/groupmsg <group> <text>` splits on the first space. |
| `/addmember <group> <username>` | Add a user to a group you're in. In strict mode a person you are connected with (or, for a host, one of your own users) is added at once; anyone else gets an invitation and is added only if they accept (`group_invite_pending`). Anyone can create a group. |
| `/leavegroup <group>` | Leave a group. |
| `/groupmsg <group> <text>` | Send a message to a group. |
| `/replygroup <group> <messageId> <text>` | Reply within a group thread. |
| `/groups` | List the groups you're in. Reply: `groups` event. |
| `/cmds [prefix]` | The `#command` catalog. Reply: `cmd_catalog` event ([`HASH_COMMANDS.md`](HASH_COMMANDS.md)). |
| `/cmdcomplete {"input":"#dm al"}` | As-you-type suggestions for a `#command`. Reply: `cmd_suggestions` event. Has its own, larger rate-limit budget. |
| `#<command> <args>` (e.g. `#dm alice hi`) | Runs the equivalent `/command` — see [`HASH_COMMANDS.md`](HASH_COMMANDS.md). An unknown `#word` gets `error` code `unknown_command`; `##text` posts the literal `#text` to the global room; `#` followed by a non-letter (`#1 priority`) is plain text. |
| `/quit` | Clean disconnect. |
| Anything else starting with `/` + a letter | **`error` event** `Unknown command: /xyz` — never broadcast (a typo used to post publicly to the global room). |
| Anything else (no leading `/`) | Broadcast as a plain message to the **global** room. |

Messages are capped at 2000 chars — longer ones get an `error` event back
instead of being sent.

---

## Events you receive (JSON, one object per WS text frame)

Every event has a `"type"` field. Shapes below use `...` for fields that
mirror the command that triggered them.

| `type` | When | Key fields |
|---|---|---|
| `welcome` | Right after a successful handshake | `name` |
| `history` | On connect, or after `/history ...` | `scope` (`global`/`dm`/`group`/`host`), `with`/`group`/`host` (if scoped), `list`: array of message objects (see below) |
| `hosts` | Reply to `/hosts` | `list`: array of `{key, name, kind}` — see "Host directory" below |
| `host_ack` | Your `/hostmsg` was delivered | `host`, `status`, `id`, `ts` |
| `host_message` | You received a message via a department host | `host`, `id`, `ts`, `from`, `text`, `replyTo` |
| `chat` | Someone posted in the global room | `id`, `ts`, `from`, `text`, `replyTo` (int or `null`) |
| `private` | You received a DM | same shape as `chat` |
| `system` | A system notice (join/leave, etc.) | `text` |
| `group_message` | A group message | `group`, `id`, `ts`, `from`, `text`, `replyTo` |
| `group_system` | A group system notice | `group`, `text` |
| `added_to_group` | You were added to a group | `name`, `members` (array), `by` |
| `group_created` | Your `/creategroup` succeeded | `name`, `members` |
| `groups` | Reply to `/groups` | `list`: array of `{name, members}` |
| `users` | Reply to `/list` | `list`: array of usernames |
| `typing` | Someone's typing in global | `text` (the username) |
| `typing_dm` | Someone's typing in your DM | `from` |
| `group_typing` | Someone's typing in a group you're in | `group`, `from` |
| `dm_read` | Your DM was marked read | `from` |
| `presence` | A person you know (connected to them, or who could message you) went online or offline. A takeover of a live connection sends none | `user`, `online` (true / false), `ts` |
| `sd_event` `receipt` | The other person of a direct conversation received or read your messages | `data`: `conversation` (`dm:<them>`), `by`, `kind` (`delivered` / `read`), `upTo` (a message id), `ts`. Kept on the server too: `peerReadId` / `peerDeliveredId` in `conv.list {full:true}` |
| `sd_event` `saved_changed` | A message was saved or un-saved on another device of yours | `data`: `id` (message id), `saved` (true / false). Only to you |
| `sd_event` `pins_changed` | A message was pinned or unpinned in a direct chat or group you are in (by you or by someone else) | `data`: `conv` (`dm:<them>` / `group:<name>`, as it is for you), `id`, `pinned` (true / false), `by`. Ask `msg.pins {conv}` for the list |
| `dm_ack` | Your `/msg` was accepted | `with`, `status` (`delivered`/`queued`), `id`, `ts` |
| `conversations` | Reply to `/conversations` | `list`: array of `{with, id, ts, from, text, archived, avatar}` (`avatar`: the other person's picture address or null) (last message per DM thread; `text` is `""` if it was deleted; `archived` is true when you archived it; a thread you deleted for yourself is left out until something newer arrives; see *Conversations: archive and delete* in `CONNECTUM_API.md`) |
| `group_msg_ack` | Your `/groupmsg`/`/replygroup` was delivered | `group`, `id`, `ts` |
| `reaction` / `dm_reaction` / `group_reaction` | A reaction changed | `messageId`, `reactions`: array of `{user, emoji}`; DM/group variants add `userA`/`userB` or `group` |
| `profile` | Someone's avatar/status changed | `user`, `avatar` (or `null`), `status` (or `null`) |
| `deleted` / `dm_deleted` / `group_deleted` | A message was deleted | `messageId`; DM/group variants add `userA`/`userB` or `group` |
| `delete_denied` | Your `/delete` was rejected (not your message, or it doesn't exist) | `messageId`, `reason` (`"forbidden"` or `"not_found"`) |
| `own_message_id` | Echo of your own broadcast's assigned id/timestamp | `id`, `ts` |
| `link_preview` / `dm_link_preview` / `group_link_preview` | A pasted link's preview finished fetching | `messageId`, `previewUrl`, `previewTitle`, `previewDescription`, `previewImage` (all `""` if none) |
| `gif_results` / `sticker_results` | Reply to a search | `query`, `results`: array of `{id, url, preview, width, height}` |
| `pubkey` | Reply to `/getpubkey` | `user`, `key` (or `null`) |
| `left_group` | Your `/leavegroup` succeeded | (text payload, not JSON object — see `json_obj` vs `json_obj2` in source) |
| `error` | Any command usage error | `text`; sometimes `code` (`not_allowed`, `not_associated`, and for `#commands` `usage`, `unknown_command`, `invalid_encoding`, `internal`) |
| `cmd_catalog` / `cmd_help` / `cmd_suggestions` | Reply to `/cmds`, `#help`, `/cmdcomplete` | see [`HASH_COMMANDS.md`](HASH_COMMANDS.md) |

### Message object shape (inside a `history` event's `list`)

```json
{
  "id": 123,
  "ts": 1790071256909,
  "from": "alice",
  "text": "hello",
  "private": false,
  "reactions": [{"user": "bob", "emoji": "👍"}],
  "deleted": false,
  "replyTo": null,
  "previewUrl": "", "previewTitle": "", "previewDescription": "", "previewImage": ""
}
```

`ts` is epoch milliseconds (`erlang:system_time(millisecond)` at the
moment the message was saved) — this is what "Date & time" on a message
card and any month-grouping should be computed from.

History returns at most the last 50 messages for that conversation, oldest
first.

Optional field `e2e`: `true` on a message (and on a `/conversations` item) whose text is an end-to-end
encrypted envelope (`e2e1:…`); absent otherwise. The organisation-wide mode is in `e2e.status`.

---

## Host directory

Per the boss's spec, the directory a user sees is **associates + hosts**.
Associates are just other online users (`/list`) — no separate concept
needed there yet since there's no "user master"/org-chart data source
wired up. Hosts come from `/hosts`, and are one of three `kind`s:

- **`"llm"`** (`openai`, `ai_router`, `claude`, `gemini`) and
  **`"workspace"`** (`workspace`, "My work space") — fixed, always
  present regardless of backend config, per spec. **Selecting one of
  these is a client-side-only concern** — per the boss's doc, it's "the
  same experience as today's AXI chat" (the existing Provider Switcher/
  Composer/MessageThread). **Do not** call `/hostmsg` for these — there's
  nothing on the backend to route to, since the LLM call itself doesn't
  go through this Erlang service at all.
- **`"department"`** (e.g. a future `hr`, `finance`) — configured chat
  hosts (HR, Finance, IT Support, etc. per the spec's "Chat host tstruct").
  **Currently always an empty list** — the backend dev hasn't created the
  chat-host tstruct yet, so there's nothing to populate this with. The
  mechanism (`/hostmsg`, `/history host`, message routing, resolving a
  host to whichever person/group is currently assigned) is fully wired
  and tested end-to-end — it just has no real hosts to resolve to yet.
  Calling `/hostmsg` for a host key that doesn't exist (which, right now,
  is any department host key at all) gets you back an `error` event.

Once the chat-host tstruct exists, department hosts will start appearing
in `/hosts`'s response with no frontend changes needed — the shape
(`{key, name, kind: "department"}`) is already final.

A department-host conversation threads separately from an ordinary DM
with whoever currently happens to be assigned to that host — if HR's
assigned person changes later, your history with "HR" stays intact rather
than splitting.

---

## File uploads (separate from the WS protocol — plain HTTP)

- `POST /upload` — multipart/form-data, one file field. Images
  (png/jpeg/gif/webp) and voice notes (webm/ogg/mp4 audio), max 8MB.
  Returns `{"url": "/uploads/<random-name>"}` on success. Content-type is
  verified against the file's actual magic bytes, not just the declared
  header — a mismatch is rejected. Rate-limited per client IP (20
  uploads/60s) — a `429` with `{"error": "..."}` means slow down, same
  error shape as every other rejection on this endpoint (400/413/415).
- `GET /uploads/<name>` — serves it back. Supports HTTP Range requests
  (needed for `<audio>`/`<video>` elements to seek/preload correctly).

There's no `chat` command tying an uploaded file to a message yet — the
current pattern (inherited from the original single-page client this
protocol was built for) is: upload the file, get the URL back, then send
that URL as the `text` of an ordinary `/msg`/`/groupmsg`/broadcast. Worth
revisiting once the frontend's actual attachment UX is designed.

---

## Health check (ops use, not for the frontend)

- `GET /health` — plain HTTP, no WS upgrade. Returns JSON:
  `{"status": "ok"|"degraded", "redis": "ok"|"unreachable", "uptime_ms": N}`,
  with HTTP 200 when `status` is `"ok"` and 503 when `"degraded"` (Redis
  unreachable). Meant for `curl`/uptime monitors/ops, not something the
  chat UI calls — nothing about the frontend's flow depends on this route.

---

## What's deliberately NOT here yet

- Real department hosts — the directory mechanism exists (`/hosts`,
  `/hostmsg`, host-scoped history/routing) but has nothing configured
  until the backend dev creates the chat-host tstruct (see "Host
  directory" above).
- An associate directory beyond "who's currently online" — no user-master/
  org-chart data source exists yet either.
- Prompts (List/Input/Upload/Download/Payment/OTP) as a configurable
  interaction unit.
- Independent cryptographic verification of the ARM token on connect
  (see the security note under "Connecting" for exactly what this does
  and doesn't guarantee).
- Month-grouping itself — `history` returns a flat, most-recent-50 list.
  Every message now carries `ts` (epoch ms), so the client has what it
  needs to compute month groups itself; the backend doesn't pre-group.

These land once the backend dev's `AxExternalUsers`/chat-host/prompt
tstructs exist and `chat_arm.erl` has real data to read — see
`NEXT_STEPS.md` Phase 3 and Section 8.
