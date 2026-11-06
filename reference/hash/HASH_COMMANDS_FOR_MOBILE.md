# "#" commands: what they are, how they run, how mobile should show them

Analysis only, no code changed. Paths are relative to `connectum/` (repo root of the app): backend files `connectum-backend/src/...`, web files `chat-app/...`. Line numbers are as of `main`, 5 Nov 2026; search by the quoted text if one moved.
Cross-link: `TASKS_AND_ACTIONS_FOR_MOBILE.md` (tasks, tickets, approvals; not repeated here) and `NOTIFICATIONS_FOR_MOBILE.md`. Both are on the Desktop next to this file; they move to `docs/` together when the load test is over.

**Three facts to know first**
1. A `#` line is **never executed by its own code**. The server parses it, validates it, and **rewrites it into an existing command** (`/msg …` or `/sd <action> {json}`), which then runs with all the usual rules (`chat/chat_cmds.erl`:7–15, `http/chat_web.erl`:1033–1041). So mobile can run any of them by sending either the `#` line or the underlying call.
2. The server's list has **22 built-in commands** (`chat_cmds.erl`:59–137) plus the person's custom commands. The web's menu does **not** read that list: it uses its own hard-coded catalogue of 24 entries plus AI-agent, custom and plugin commands (`chat-app/features/connectumChat/data/hashCommandsCatalog.js`:25–282; `Composer.jsx`:358). The two lists differ (section 3.3).
3. There is **no metadata action** that describes a command's inputs beyond a flat list of `{name,type,required}`. Forms, options and records are fetched by separate actions (section 5).

---

## 1. The list

### 1.1 Which call
Send the text line `/cmds` (all commands) or `/cmds <prefix>` (name or alias prefix). The reply is one frame of `"type":"cmd_catalog"` (`http/chat_web.erl`:989–991, run off the connection in `sd_lane:aux`). The web sends `/cmds` once, right after sign-in (`chat-app/services/connectumSocket.js`:306). `#help` with no argument returns the same frame; `#help <command>` returns `"type":"cmd_help"` with one command (`chat_cmds.erl`:508–520).
This is a chat-socket line, **not** an `/sd` action: the answer has no `reqId` envelope.

### 1.2 Response shape (`chat_cmds.erl`:489–512, command object 456–468)
```
{"type":"cmd_catalog","prefix":"#","escape":"##","filter":"<prefix typed or empty>",
 "categories":[{"id","label"}], "commands":[ <command>, … ]}
```
| Field of `<command>` | Type | Meaning |
|---|---|---|
| `name` | string | the word typed after `#`, lower case, ≤32 chars of `[A-Za-z0-9_-]` |
| `aliases` | string[] | other words that run the same command (may be empty) |
| `category` | string | one of the category ids below |
| `summary` | string | one plain-ASCII sentence |
| `usage` | string | built text such as `#dm <user> <text...>`; `<x>` required, `[x]` optional, `...` = rest of line (`chat_cmds.erl`:392–398) |
| `args` | array | `{name, type, required}`; plus `values` (for `enum`) or `rest:true` and `max` (for `text`) (`:416–431`) |
| `reply` | string[] | the names of the event types the command answers with, e.g. `["dm_ack"]` or `["sd"]` (informational) |
| `available` | boolean | `false` if the caller lacks the right to the underlying action (advisory) |
| `requires` | string | `"none"` or the level the caller lacks: `signin`, `host`, `manage`, `admin` (`core/sd_cmds.erl`:40–60) |

Argument `type` values seen: `user`, `group`, `host`, `word`, `text` (with `rest:true`,`max`), `url`, `emoji`, `msgid`, `enum`. A `phrase` argument is reported as `text` (`chat_cmds.erl`:407–409). **Not in the response:** icon, colour, default values, placeholder text, where options come from, result kind, confirmation text, permissions beyond `requires`. The web chooses its icons itself (`COMMAND_CATEGORIES` has an icon per category, `hashCommandsCatalog.js`:17–27); the server carries none.

Categories (`chat_cmds.erl`:142–144): `messaging` "Messaging", `lookup` "Look things up", `groups` "Groups", `profile` "Your profile", `people` "People and approvals", `inbox` "Notifications and cards", `forms` "Forms", `admin` "Administration", `custom` "Custom", `help` "Help". (`profile` and `inbox` categories exist but hold no server commands today; `inbox` is only a category name.)

Fake example:
```
{"type":"cmd_catalog","prefix":"#","escape":"##","filter":"","categories":[{"id":"messaging","label":"Messaging"}],
 "commands":[{"name":"dm","aliases":["msg","pm"],"category":"messaging","summary":"Send a direct message to someone",
  "usage":"#dm <user> <text...>","args":[{"name":"user","type":"user","required":true},
  {"name":"text","type":"text","required":true,"rest":true,"max":2000}],"reply":["dm_ack"],"available":true,"requires":"none"},
 {"name":"find","aliases":["search"],"category":"people","summary":"Find a person by username, email or mobile number",
  "usage":"#find <query...>","args":[{"name":"query","type":"text","required":true,"rest":true,"max":100}],"reply":["sd"],"available":true,"requires":"none"}]}
```
(`max` for a bare `text` argument is `?MAX_MESSAGE_LEN`, `:421`; the 2000 above is the value the web catalogue shows for `#dm`, `hashCommandsCatalog.js`:36.)

### 1.3 What the list depends on
- **Person:** built-in commands are the same for everybody; `available`/`requires` change with the person's level (`chat_cmds.erl`:456–468 → `sd_cmds:availability/2`). A command whose target is a plain slash line (`dm`, `groupmsg`, `users`, `groups`, `inbox`, `historyhost`, `profile`, `creategroup`, `addmember`, `leavegroup`, `help`) is always reported `available:true` (`:458`); the real check happens when it runs (e.g. `sd_policy`).
- **Custom commands** (the person's own plus those an administrator made "applicable" to them) are appended with `category:"custom"`, arg `[{input, text, optional, max 200}]`, `reply:["sd"]` (`core/sd_cmdx.erl`:139–147, `chat_cmds.erl`:219–220). Custom commands are visible when active and either owned by the person or applicable to them (`sd_cmdx.erl`:29–36).
- **Organisation / role / conversation:** the built-in list does **not** depend on the conversation, the conversation type, or the role beyond `requires`. `host.transfer` (`#transfer`) is retired unless the server runs hosts (`sd_cmds.erl`:290) but is still listed.
- **Hidden by the web:** `forms` and `form` (`IGNORED_COMMANDS`, `hashCommandsCatalog.js`:288), and everything not in `FRIENDLY_COMMAND_NAMES` (:290–301): `historyhost`, `transfer`, `scan`, `lookups`, `forms`, `form`. They still work if typed in full.
- Permission filter in the web: a command with a required permission is offered only to people holding it (`COMMAND_PERMS`: broadcast/announce → `broadcast`; studio/code/ide → `studio.use`; addemployee/inviteemployee → `invite.employees`, `utils/permissions.js`:15–23; applied `hashCommandsCatalog.js`:325–333), and `requires:"admin"` entries only to admins (:322–323). The web also stops a typed one with "You don't have access to #<cmd>. Ask your administrator to give you the permission." (`routeHashCommand.js`:12–16).

### 1.4 Filtering while typing (web)
Local first, then server. Local: `filterCatalogCommands` scores name = 100, alias = 90, name starts with 80, alias starts with 70, name contains 50, alias contains 40, summary contains 30, category contains 20; with nothing typed they are grouped by category order (`hashCommandsCatalog.js`:335–372). Server: after 150 ms of no typing the web sends `/cmdcomplete {"input":"<text up to caret>","page":1,"pageSize":10,"reqId":n}` and ignores replies whose `reqId` is not the latest (`Composer.jsx`:438–452, 177–182).

`/cmdcomplete` reply (`chat_cmds.erl`:565–640): `{"type":"cmd_suggestions","input","reqId","kind":"command"|"arg"|"text"|"none","token", "command"?,"arg"?:{name,type,required,index,…},"items":[{"value","label","hint", "usage"?,"category"?,"available"?}], page, pageSize, total, totalPages, hasMore}`. Input limit 512 bytes (error `usage` otherwise; `invalid_encoding` for bad UTF-8). Page size 0 means default (25 for commands, 10 for arguments), maximum 25. The input travels inside JSON because the server trims bare lines and would lose the trailing space that means "now typing the first argument" (`:552–556`).
Argument candidates are only data the person may already see: `user` = people online now (hint "online") plus their connections (hint `<name> · connected`) and, in strict mode, administrators; `group` = groups they are in (hint "<n> members"); `host` = department hosts; `enum` = its values; `phrase` (form names) = forms visible to them; for `accept`/`reject` the pending requests (those two commands are not in the table today; the code remains) (`:660–720`). Prefix matches first, then substring matches, each alphabetical (`:735+`).

### 1.5 Caching, ordering, favourites
- Catalogue: fetched once per connection; the web does not refresh it on change. AI-agent and custom commands are fetched separately on screen load and after changes (`cmd.list`, `ai.agents`): `services/dynamicCommands.js`:13–16, `ConnectumChatScreen.jsx`:280.
- Order from the server: table order, custom commands after. The web re-sorts (above).
- **No recently-used or favourites exist** (searched `Composer.jsx`, catalogue): not built.

---

## 2. Typing syntax

- **Trigger.** The message box is in command mode when the text, ignoring leading spaces, starts with `#` (`Composer.jsx`:336–341). The server treats a line as a command only when `#` is followed by a **letter**; `#1 priority` or `# 5` is ordinary chat text (`chat_web.erl`:1035–1036).
- **Escape.** `##text` posts the literal message `#text` **to the global room** (`chat_web.erl`:1028–1032). It always goes to the global room, whatever chat is open.
- **Name.** `#` then the longest run of letters, digits, `_`, `-`; case-insensitive; **exact name or alias only** to run; a prefix never runs (`chat_cmds.erl`:232–237). Web regex: `^#([A-Za-z][\w-]*)` (`hashCommandsCatalog.js`:380).
- **Arguments.** Separated by single spaces; no quoting or escaping exists. Space-delimited only; tab/newline inside a token is rejected as a control character (`:339–345`). Rules:
  - `user`, `word`, `host`, `emoji`: one token, ≤ username/group/64/32 chars, no control characters (`:295–323`).
  - `msgid`: digits only, ≤18 → integer ("<name> must be a number.").
  - `enum`: case-insensitive, one of the values ("<name> must be one of: a, b.").
  - `url`: `http://`, `https://` or `/uploads/…`, ≤512.
  - `text` / `{text,Max}`: the **rest of the line**, must be the last argument; empty if required → "Missing <name>."; too long → "<name> is too long (max N characters)." (`:262–275`).
  - `phrase` (multi-word names, e.g. a form called "Leave Request"): takes every token except those the later single-token arguments need.
  - `group` and `host` match known multi-word names first (longest wins), else fall back to one token / a phrase (`:247–260`).
- **Chosen or typed in full?** Both. Mobile may let the person pick from the list and fill arguments one by one, then send the assembled line; or send the typed line. The server needs the full line either way.
- **Unknown command** (`chat_cmds.erl`:371–378): `{"type":"error","code":"unknown_command","text":"#xyz is not a command. Type #help to see them all, or ## to send a message that starts with #.","suggestions":[up to 5 names]}`. Only plain tokens are echoed. (A custom command name is recognised from an in-memory list, so it is not "unknown", `:57–68`.)
- **Malformed:** `{"type":"error","code":"usage","text":"<problem> Usage: #dm <user> <text...>","command":"dm","usage":"…"}` (`:366–369`). Other codes: `invalid_encoding` ("That command is not valid UTF-8 text."), `internal` ("Something went wrong running that command.").
- **Where they run.** The `#` line is handled at connection level, **independent of the open conversation** (`chat_web.erl`:1033–1041): `#dm ana hi` works the same from a group, a DM, My Workspace or the general room, and nothing about the current chat is passed to the server. In the web, `#tasks`, `#view` etc. open screens, and plain messages typed in My Workspace starting with `@name` are DMs (`chatActions/send.js`:26–60) — that is a web convenience, not a command. Not found: any per-conversation restriction on commands.
- **Rate limit.** A `#` line is one chat line: it counts against the per-connection limit like every line (documented 30 per 10 s, production 200 per 10 s). When refused: `{"type":"error",…,"Too many commands -- slow down"}` for slash lines, or the `/sd` envelope with code `rate_limited` for `/sd` lines (`chat_web.erl`:596–606).
- **Idempotency.** A `#` line is not idempotent by itself. A client id wrapper `/c <clientId> #dm ravi hi` works for the sends `/msg, /replydm, /groupmsg, /replygroup, /hostmsg, /creategroup, /addmember`, i.e. for `#dm`, `#groupmsg`, `#creategroup`, `#addmember` (the line is rewritten first, then checked), 1–64 chars `[A-Za-z0-9_.:-]`, remembered one day, repeat gets the same ack with `"duplicate":true`; other commands answer `cid_unsupported` (`chat_web.erl`:1053–1105).
- **Encrypted chats:** section 8.

---

## 3. Catalogue

### 3.1 How to read the entries
"Runs" is what the line is rewritten to (`chat_cmds.erl` line given). "Result" is what comes back on the socket. "Who" is the advisory `requires` from `sd_cmds:access/1` (`core/sd_cmds.erl`:157+) — `none` means any signed-in person; the server still re-checks on execution. Error codes are the ones a mobile client will see from the command table itself (`usage`, `unknown_command`, `invalid_encoding`, `internal`, `rate_limited`) **plus** whatever the underlying action returns. For the underlying actions' own codes see their modules; I list the ones I read.
Web class (A–E) is explained in section 4.

### 3.2 The 22 built-in commands (server table)

| # | Command (aliases) | Does | Inputs (type, req) | Runs → result | Web class |
|---|---|---|---|---|---|
| 1 | `dm` (msg, pm) | send a direct message | `user` user req; `text` text req (rest) | `/msg <user> <text>` → `dm_ack` {with,status delivered\|queued,id,ts} (`chat_web.erl`:1132–1136); idempotent with `/c` | A* |
| 2 | `groupmsg` (gm) | message a group | `group` group req; `text` req | `/groupmsg <group> <text>` → `group_msg_ack` | A* |
| 3 | `users` (online, who) | who is online | none | `/list` → `users` | B (web: modal) |
| 4 | `groups` | groups you are in | none | `/groups` → `groups` | B |
| 5 | `inbox` (conversations) | DM threads, newest first | none | `/conversations` → `conversations` | B |
| 6 | `historyhost` | load a conversation with a department host | `host` host req | `/history host <h>` → `history` | A (hidden in web) |
| 7 | `profile` | someone's avatar and status | `user` req | `/getprofile <u>` → `profile` | C |
| 8 | `creategroup` (newgroup) | create a group; name may have spaces | `name` group req | `/creategroup <name>` → `group_created`; idempotent with `/c` | A |
| 9 | `addmember` (invitegroup) | add an online user to a group | `group` req; `user` req | `/addmember <g> <u>` → `group_created` or `group_invite_pending`; web checks you are the owner first | A |
| 10 | `leavegroup` (leave) | leave a group | `group` req | `/leavegroup <g>` → `left_group` | A |
| 11 | `me` (whoami) | your account, permissions, counters | none | `/sd me` → `{authenticated,mode,user,org,sessionExpiresTs,notifications,feed,…}` (`sd_cmds.erl`:366+); access `none` | C |
| 12 | `associates` (contacts) | people you are connected with | none | `/sd assoc.list` → `{associates:[{user,relation,online,…}]}` (`sd_cmds_people.erl`:14–21) | B/C |
| 13 | `find` (search) | find a person by username, email or mobile | `query` text req ≤100 | `/sd users.search {q}` (strict mode: only an exact username/email/mobile finds anyone, `sd_cmds_people.erl`:125–135) | C |
| 14 | `transfer` | ask another host to take over a user (hosts only) | `user` req; `toHost` user req | `/sd host.transfer {user,toHost}` → `{request}`; retired unless hosts are on | A (hidden) |
| 15 | `scan` | connect with someone by their Connectum code | `code` text req ≤100 | `/sd connect.scan {code}`; error `wrong_org` "That code is for a different organisation…" on the lookup side | A (hidden) |
| 16 | `forms` | forms and options available to you | none | `/sd options.list` → `{options:[…]}` (`sd_cmds_forms.erl`:85–89) | hidden in web |
| 17 | `options` (opts) | options of lite structures, optionally one category | `category` word opt | `/sd options.list {category}`; web: opens the smart-structure picker | C |
| 18 | `lookups` (cfg-lookups) | org lists (branches, departments, designations, affiliates, categories) | none | `/sd cfg.lookups` (names only, `sd_cmds_forms.erl`:52–68) | A (hidden) |
| 19 | `form` | open a form definition | `name` word req | `/sd tstruct.get {name}` → `{tstruct, rev}`; hidden in web | hidden |
| 20 | `tstruct` (ts, struct, tstructs, structure, structures) | open a form in the viewer: definition plus your records | `name` phrase req | `/sd tstruct.user.open {name}` → `{tstruct, scope, …}` | C |
| 21 | `tstruct-add` (create, ts-add, struct-add, structures-add) | open a form to fill in | `name` phrase req | `/sd tstruct.user.open {name, mode:"add"}` | C |
| 22 | `help` (commands) | list commands or explain one | `command` word opt | `cmd_catalog` or `cmd_help` | C |

`*` A for the server; the web handles `dm`/`groupmsg` itself (switches conversation) — see section 4.

Common to all server-table commands: events are only the normal events of the underlying action (e.g. `dm_ack`, `group_created`, `sd` replies keyed `reqId:"#<name>"`, `chat_cmds.erl`:196); errors are the 5 command-level codes plus the action's own; rate limit is the per-connection limit; Idempotent: only those in the `/c` list above. "Who": `dm`, `groupmsg`, group commands, `users`, `groups`, `inbox`, `profile`, `help` are slash lines (no access level; policy checks inside, e.g. `sd_policy:may_interact`, `can_broadcast`); `me` is `none`; `assoc.list`, `users.search`, `connect.scan`, `options.list`, `cfg.lookups`, `tstruct.get`, `tstruct.user.open` are user-level actions in the `access` table (user-level actions are listed `sd_cmds.erl`:180–199). I did not trace each action's full error list.

### 3.3 Web-only commands (not in the server table)
The server answers these with `unknown_command`. The web (and so mobile, if it wants parity) must handle them as **screens that call `sd` actions**; the web's own comment says so (`routeHashCommand.js`:25–26).

| Command (aliases) | What the web opens | Data/actions behind it |
|---|---|---|
| `connections` (contacts, associates) | associates modal | `assoc.list` (`routeHashCommand.js`:205). **Name differs from the server's `associates`.** |
| `customcmds` (custom, mycommands) | "custom commands" manager | `cmd.list` → `{commands, kinds}`, `cmd.save`, `cmd.delete` (`sd_cmds.erl`:617–623; `CustomCommandsModal.jsx`:22) |
| `broadcast` (announce) | announcement modal | `broadcast.preview/send/list`; needs permission `broadcast` (`sd_broadcast.erl`) |
| `addemployee` (inviteemployee) | invite modal | `users.invite`, needs `invite.employees` (`sd_cmds_people.erl`:232+) |
| `tasks` (task, todo) | Inbox → tasks | see TASKS doc |
| `view` (smartview, list) | smart view named by the rest of the line | opens `smart_view` with `{name: rest}` (`routeHashCommand.js`:243–245). Server action not traced |
| `links` (link) | links modal | `links_changed` events; action not traced |
| `affiliates` (affiliate) | affiliates modal | action not traced |
| AI-agent commands (`#<alias> [question…]`) | AI chat with the question | list from `ai.agents`; `agentForCommand` (`hashCommandsCatalog.js`:419+, `routeHashCommand.js`:198–201) |
| plugin commands: `studio`/`code`/`ide`, `meeting`/`minutes` | Code Studio / meeting notes | defined by plugins; the open-source stubs export `hashCommands = []` (`plugin-stubs/studio/index.js`:3, `speech/index.js`:3); real definitions are in the separate `connectum-plugins` repo, not read |
| custom commands `#<name> [input]` | runs on the server | below |

**Custom commands** (`core/sd_cmdx.erl`): a name (2–32 chars, `^[a-z][a-z0-9_-]{1,31}$`, not a built-in name or `custom`) pointing at: `option` → `option.run {id, values:{input}}`; `tstruct` → `tstruct.user.open {name}`; `list` → `records.list {tstruct, q}`; `datasource` → `datasource.run {name, values:{input}}` (`:166–169`). The header also mentions `wizard` and `catalog` but `?KINDS` only allows the four above (`:20`): treat wizard/catalog as **not available**. The line `#name [input≤200]` is rewritten to `/sd cmd.custom {name,input}` and run in `sd_lane` (`chat_cmds.erl`:70–78); the reply is `{command, action, result}` where `result` is the underlying action's data (`sd_cmdx.erl`:158). Errors: `not_found` "No such command."; save errors `invalid` ("name must be 2-32 letters, digits, - or _, starting with a letter.", "That name is already a built-in command.", "Unknown option.", "Unknown T-Struct.", "Unknown data source."), `too_many` "You have too many custom commands." (20 per person), `forbidden` "That command belongs to someone else." The underlying action applies its own permission checks (`sd_cmdx.erl`:12–13).

Count of what mobile can see by default from `/cmds`: 22 built-in + the person's custom ones. The web's menu shows (`FRIENDLY_COMMAND_NAMES`) 23 names plus agents/custom/plugin commands.

---

## 4. How the web renders each one

Classes: A generic (inputs → execute → plain result); B list/rows; C custom page or component; D only navigates; E background/automated.

| Command | Class | Evidence |
|---|---|---|
| `dm`, `groupmsg` | A, with a local twist: the web does not just send; it switches the open conversation to that person/group, or opens the directory modal when arguments are missing | `routeHashCommand.js`:68–153 |
| `creategroup` | A (opens "new group" modal if no name) | :136–147 |
| `addmember` | A (checks you are the owner, sends via `sendAddMember`; opens members modal if args missing) | :148–166 |
| `leavegroup` | A | :171–181 |
| `historyhost`, `transfer`, `scan`, `lookups`, `forms`, `form` | A on the server; **hidden** in the web menu | `hashCommandsCatalog.js`:288–301 |
| `users` | B (rows of online people) shown in a modal | :94–97 |
| `groups` | B (groups directory modal) | :99–102 |
| `inbox` | D (opens the Inbox tool) | :104–108 |
| `profile` | C (profile modal for a person, or yours) | :110–131 |
| `me` | C (profile modal fed by `me`) | :182–192 |
| `associates`/`connections` | B (associates modal) | :205 |
| `find` | C (find-people modal; `users.search`) | :210 |
| `options` | C (smart-structure picker) | `workspace.js`:193–197 |
| `tstruct` | C (records viewer of the Studio: list + open a record) | `workspace.js`:198–202 |
| `tstruct-add` | C but reducible to a form (the web reuses the same lightweight form as Smart Prompts) | `workspace.js`:203–216 |
| `customcmds` | C (manager with create/edit/delete) | :216 |
| `broadcast` | C (audience pickers, preview, send) | :226 |
| `addemployee` | C (invite form) | :221 |
| `tasks` | D → Inbox tasks | :231 |
| `view` | D → smart view tool with a name | :243 |
| `links`, `affiliates` | C (modals) | :249, :261 |
| `help` | C (commands directory modal; `#help <q>` pre-filters) | `send.js`:11–18 |
| AI agents | D → AI chat with the question | :198–201 |
| `studio`, `meeting` | C/D plugin screens | :237, :255 |
| custom commands | A (line sent, server runs) – the web shows nothing special; the result frame is a normal `sd` reply | `routeHashCommand.js`:40–41 |

**Counts** (web classification of the 22 built-ins + the 8 web-only + custom): A = dm, groupmsg, creategroup, addmember, leavegroup, historyhost, transfer, scan, lookups + custom (9 built-in/web + custom kind). B = users, groups, associates/connections (3). C = profile, me, find, options, tstruct, tstruct-add, help, customcmds, broadcast, addemployee, links, affiliates (12). D = inbox, tasks, view, AI agents (3 + the dynamic agents). E = **none**: no `#` command is background or automated; reminders and scheduled work are not `#` commands (`sd_scheduler`, see notifications doc). Two server commands (`forms`, `form`) are hidden and have no web handling.

`#`-reply handling for sd-based commands is **thin**: the only replies the web interprets are keyed `#associates`, `#options`, `#tstruct`, `#tstruct-add`, `#tstruct-delete`; any other failed `sd` reply becomes an error toast `error.text || error.message` (`workspace.js`:190–229). Successful replies of other `#` commands (e.g. `#find`, `#lookups`) are not drawn by that handler; the web's own screens call the actions themselves.

---

## 5. How a client learns what a command needs

- **Hard-coded in the web:** which screen a command opens, argument pickers (`computeLocalArgSuggestions` in `Composer.jsx`), the friendly list, the permission map, the custom-command "what" wording (`setCustomCommands`, `hashCommandsCatalog.js`:437+).
- **From the server:** `args` with type/required/enum values/max (1.2) and, while typing, candidates per argument via `/cmdcomplete` (1.4). There is **no** call that returns defaults, option sources, or a result kind.
- **Data fetched before running (by command):** `tstruct`/`tstruct-add`/`form` → the definition arrives *in the result* of the command itself (`tstruct.user.open` / `tstruct.get`, returns `{tstruct, rev}` or scope) — the command is the fetch; `options`/`forms` → `options.list` (optionally `{category,q,page,pageSize}`, `options.categories`); `lookups` → `cfg.lookups`; `broadcast` → `broadcast.preview` is a real **dry run** (returns recipient count and a sample of ≤10 names before `broadcast.send`, `sd_broadcast.erl`:14–21); custom commands → `cmd.list`. `find` has no preview. No other dry run exists.
- Form definitions: `tstruct.get`/`tstruct.user.open`; fields follow `docs/FORM_FIELD_TYPES.md` (types: text, email, url, mobile, wholenumber, number, date, time, slot, location, barcode, payment, file, toggle, list, selection, fill, autogenerate; `rule`/`calc`/`fetch` run in the app).

---

## 6. A uniform descriptor (recommendation, nothing of this exists)

Proposed: extend the existing `command` object (1.2) with optional fields. Old clients ignore unknown fields.
```
{ "name":"leave","title":"Apply for leave","category":"forms","description":"…",
  "availability":{"available":true,"requires":"none","where":["dm","group","workspace"]},
  "inputs":[{"name":"text","caption":"Search","type":"text","required":false,"max":200}],   // same field types as FORM_FIELD_TYPES.md
  "execute":{"action":"tstruct.user.open","args":{"name":"leave_request"},"map":{"input":"values.input"}},
  "result":{"kind":"form","form":{"action":"tstruct.get","name":"leave_request"}},
  "confirm":null, "permissions":["…"] }
```
- `result.kind`: `message` (render text/ack), `card` (render a card payload), `list` (rows: `{columns,rows,paging}`), `form` (open the form engine on a definition), `navigate` (a mobile route id such as `inbox`, `approvals`, `tasks`), `job` (accepted, then progress events by name).
- `confirm`: text shown before running a risky command (`transfer`, `leavegroup`, `broadcast.send`).
- **Describable today with no server change (use existing fields):** `dm`, `groupmsg`, `creategroup`, `addmember`, `leavegroup`, `users`, `groups`, `inbox`, `profile`, `me`, `associates`, `find`, `scan`, `help`, `historyhost`, `transfer`, `lookups`, and all custom commands (their kind/target is already data). Mobile can hard-code the `result.kind` per name now.
- **Need small server changes:** `options`/`forms` (a `list` kind with columns), `tstruct`/`tstruct-add`/`form`/custom `tstruct` kinds (kind `form` plus the definition action; the engine and the form-logic bundle already evaluate rules/calc on the app, `FORM_FIELD_TYPES.md`:42–44, so a descriptor can say "open this definition", no new page), `broadcast` (inputs are four lists plus a text: describable as a form, plus a preview action), `customcmds`, `addemployee` (forms of `users.invite` fields).
- **Cannot be generic (class C pages with real behaviour):** the `tstruct` records viewer (list/search/paging/edit/delete), Studio/IDE and meeting notes (plugins), smart views (their own layout), links and affiliates managers (not traced). For these mobile either builds its own screen or hides the command.
- Reuse of the form engine: a descriptor with `inputs` typed like form fields can be rendered by the same form renderer and validated with the same rules (server validation is the judge).

---

## 7. Results and updates

- A rewritten line runs as if typed, so its result is the underlying event on the socket: acks/events for chat commands (`dm_ack`, `group_created`, `left_group`, `users`, `groups`, `conversations`, `history`, `profile`), `{"type":"sd","action","reqId":"#<name>","ok","data"|"error"}` for sd-based ones (`chat_cmds.erl`:196). The `reqId` is the string `#<name>`, which lets a client tell a `#` reply from its own numbered calls.
- Other devices of the same person: `sync_other_device(Name, Line)` is called after each accepted line (`chat_web.erl`:597); I did not read what it forwards.
- Messages sent by `#dm`/`#groupmsg` reach the other side as ordinary messages (live or queued, `dm_ack.status` delivered|queued).
- **No command returns a job or progress.** Every `#` command is request/response.
- Errors: command-level frames `{"type":"error","code","text"}`; action errors in the `sd` envelope. Permission changes arrive as the `permissions_changed` event (`sd_cmds.erl`:786–826); the web does not re-fetch `/cmds` on it, so `available`/`requires` can go stale until reconnect.

## 8. Encryption

- `#` commands are **not end-to-end encrypted**: the server must read and act on them (`security/sd_e2e.erl`:14–15; `docs/E2E_ENCRYPTION.md`:9). Their results (lists, forms, profile, associates) are plain.
- `#dm` / `#groupmsg` are rewritten to `/msg` / `/groupmsg` **with the typed text in the clear**. If the organisation's mode is `required`, a plain direct or group text is refused with `e2e_required` "Messages here are end-to-end encrypted. Update your app, or sign in again, so your device can encrypt." (`sd_e2e.erl`:438). In mode `off` or `optional` they send as plain text. I found no code that encrypts a `#dm` text on the device. **Open question 1.**
- Mobile should therefore send a DM to a person from the normal composer (encrypted) and offer `#dm` only as a shortcut that switches to the conversation (the web's behaviour) rather than sending plain text.
- Any message the command creates as plain text in an e2e chat is shown as plain; the global room is never e2e (`sd_e2e.erl`:429–433).

---

## Open questions
1. Under `CONNECTUM_E2E=required`, should `#dm`/`#groupmsg` be refused (today) or should the app encrypt and send a normal message instead?
2. The web's hard-coded catalogue and the server list disagree (`connections` vs `associates`, web-only commands). Should the server list become the single source (adding the 8 web-only commands, `kind`/`target`, and the descriptor in section 6)?
3. Should `/cmds` be re-sent after `permissions_changed`?
4. Do you want recent/favourite commands (not built)?
5. Which web-only commands must mobile have in v1 (suggest: tasks, broadcast, view, find)?
6. Is `#transfer` still a product feature (retired unless hosts are on)?
7. Plugin commands (`studio`, `meeting`) live in a separate repo I did not read: who documents them for mobile?
8. `view`, `links`, `affiliates`: I did not trace their server actions. Needed before mobile can build them.

## 9. What mobile must match versus what may differ

**Must match**
1. Fetch the list with `/cmds`; honour `available`/`requires` (grey out, never hide silently) and the `##` escape (a message starting with `#`).
2. The line grammar: `#name` + space-separated args, last `text` argument is the rest of the line, no quoting; exact name or alias to run.
3. Argument rules and the exact usage/validation messages from the server (`usage`, `unknown_command` with suggestions).
4. Use `/cmdcomplete` (JSON body, `reqId`, ignore stale replies) for pickers; the 512-byte limit and paging.
5. Rewrite semantics: the server is the judge; treat `reqId:"#<name>"` replies as the result; show `error.text` or `error.message`.
6. Plain-text-only for `#` commands; do not put e2e text through them; honour `e2e_required`.
7. One chat line per command; respect `rate_limited`; `/c` client id for `#dm`, `#groupmsg`, `#creategroup`, `#addmember` retries.
8. Custom command rules (2–32 chars, input ≤200, 20 per person) and calling `cmd.list` to learn them.
9. Permission gating of broadcast, addemployee, studio (hide or refuse in words).

**May differ:** how the menu is drawn, grouping, ordering and scoring, icons, whether arguments are typed or picked, whether `help` is a screen or a sheet, whether `#dm` switches chat, which class-C pages are built as screens or as generic forms, caching of the list, haptics.

**Recommended order for mobile:**
1. Class A, server-driven: `dm`, `groupmsg`, `creategroup`, `addmember`, `leavegroup` (+ custom commands, which are class A and cost nothing).
2. B lists as rows: `users`, `groups`, `inbox`, `associates`.
3. D navigations: `inbox`, `tasks` (see TASKS doc), `view`, AI agents.
4. Simple C via the form engine: `tstruct-add`/custom `tstruct`, `options`, `find`, `me`/`profile`.
5. `broadcast` (preview then send), `addemployee`.
6. The records viewer, `customcmds` manager, `links`, `affiliates` — last, each its own decision; plugin commands only if the plugin is licensed.
