# "#" commands: audit before the build

Source: `reference/hash/HASH_COMMANDS_FOR_MOBILE.md`. Web router read (read-only) in `~/Development/Axi-apps/connectum/chat-app/features/connectumChat/chatActions/routeHashCommand.js`.

## What was already there
- `HashCommand` model, `CommandRepository` (catalogue from `/cmds` + `cmd.list`, cached per organisation), `CommandPrompt` (name-stage list), `CommandsPanel`. Both composers (conversation, workspace) already routed a "#" line to `commands.run`.
- The guard that is gone: `_blockedMessage` / `encryptedBlock` ("Can't send in encrypted chats from mobile yet") and the raw sending of `#dm` (expanded into a normal send). `#dm`/`#groupmsg` are now drafts.
- Not there: argument stage, `/cmdcomplete`, scoring, permission filter, local commands, results sheets, `cid` for `#creategroup`/`#addmember`.

## Socket helpers
- `SocketService.sendCommand(line)`: raw chat line, paced 400 ms. `sdCall(action, args)`: `/sd action {..., reqId:"m-n"}`. `hashCall(line, name)`: raw `#` line whose `sd` answer has `reqId:"#name"`. `sd` frames with a pending id are consumed by the socket and never reach `events`; every other frame (`cmd_catalog`, `cmd_suggestions`, `cmd_help`, `error`, `users`, `groups`, `group_created`, `left_group`) is on `events`.
- Group flows (`GroupRepository`) already wait for the same frames; `ConversationRepository._onEvent` writes `groups`, `group_created`, `left_group` into SQLite by itself.

## The "@" picker reused
`MentionPanel` (compact card above the keyboard, surface + line border, 6 rows, `PopScope` to dismiss) is the model for `CommandsPanel`; the controller side is `CommandPrompt` (like `MentionPicker`).

## Screens that serve as results
No people directory, groups list or associates screen exists; Tasks (`/tasks`, To-dos first) and the Chats list do. Results are therefore one light sheet (`CommandSheets.showRows`) fed from the command's own answer (`users`, `groups`, `assoc.list`).

## Decisions
- `/cmds` is sent on every connection (`onOnline`) and after `permissions_changed`; `/sd perm.mine` gives the permission list and `isAdmin` (websocket-protocol.md), so the permission filter uses real data. Until `perm.mine` has answered, permission-gated and admin-only commands stay out of the menu.
- `connections` is a local entry whose aliases skip any word the server already uses (`contacts` belongs to `associates`).
