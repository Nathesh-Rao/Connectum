# "#" commands

Source: docs/HASH_COMMANDS.md, FRONTEND_HANDOFF_HASH_COMMANDS.md, chat_cmds.erl, sd_cmdx.erl, web Composer.jsx / dynamicCommands.js. Live `/cmds` and `cmd.list` NOT run (server unreachable).

## Web composer behaviour
- Trigger: text (after `trimStart`) starts with `#`. Closes when it does not. No chat-kind check: the menu works in every conversation, not only the workspace (the workspace only *advertises* it).
- While no space typed: command-name mode. Filter the cached catalog locally by prefix on `name` and `aliases`, group by `category`, grey out `available:false` (`requires`: signin|host|manage|admin).
- After a space: argument mode. Send `/cmdcomplete {"input":"<text to caret>","reqId":n,"page":1,"pageSize":10}` debounced 150 ms; reply `cmd_suggestions {kind:"command"|"arg"|"text", command, token, items:[{value,label,hint}], page,pageSize,total,totalPages,hasMore,reqId}`. Ignore stale `reqId`. Selecting replaces `token` with `value`. `kind:"text"` = free text, no suggestions. Multi-word names (tstruct caption, group, host) must not be split on spaces; use `arg.index` / `token` from the reply.
- Enter: if first word is a known name or alias, send the raw `#line` as its own WS frame; else send as a normal message (`##` escapes a literal `#`).
- Choosing a command from the menu only **inserts `#name `** into the composer. Nothing runs until Enter.

## Catalog: `/cmds [prefix]` -> `cmd_catalog`
`{type:"cmd_catalog", prefix:"#", escape:"##", filter, categories:[{id,label}], commands:[{name, aliases[], category, summary, usage, args:[{name,type,required,rest?,max?,values?}], reply:[event types], available, requires}]}`. `args[].type`: user|group|host|msgid|emoji|url|word|enum|text. ~15 KB; fetch once per session and after sign-in/out. `available` is advisory; the server re-checks every run.

## What running does
The server rewrites `#cmd` to the `/command` it stands for and runs the same path: `#dm alice hi` = `/msg alice hi`; `#host Human Resources need a form` = `/hostmsg`; `#groupmsg g text`; `#accept 12` = `/sd req.respond`; `#tstruct <name>` opens a form (web opens the form UI, the reply is an `sd` envelope); `#remind <text>` creates a card. Shown in the web menu (`FRIENDLY_COMMAND_NAMES`): dm, host, groupmsg, users, hosts, groups, inbox, profile, creategroup, addmember, leavegroup, me, associates, find, connect, disconnect, requests, accept, reject, remind, tstruct(ts,struct), tstruct-add, help. Removed (`unknown_command`): gif, sticker, status, avatar, cards, delete*, react*, read, markread, dismiss, ignore, myusers.

## Custom commands (`cmd.list`)
- `sd cmd.list` -> `{commands:[...], kinds:["option","tstruct","list","datasource"]}`; the web merges them into the menu under category "Your commands" (bolt icon) and AI agents as commands (`ai.agents`).
- Kinds (what `target` names -> what running does): `option` -> `option.run`; `tstruct` -> `tstruct.user.open`; `list` -> `records.list` (typed text = search); `datasource` -> `datasource.run` (typed text = `input`). Running = `sd cmd.custom {name,input}`; never code, same permission checks as the target action.
- Defined by: an administrator (for everyone it applies to, `applicableTo` rules) or a person (own, max 20): `cmd.save {name,kind,target,summary}` (name 2-32 chars, not a built-in), `cmd.delete {name}`; admin UI = web CustomCommandsModal / AdminOptionsPanel.

## Mobile notes
- Prototype "#" sheet: build from `/cmds` (cached in SQLite or memory) + `cmd.list`; send the raw `#line`; refuse nothing locally except offline.
- Read-only for investigation: `/cmds` and `cmd.list` only.

## Live (test server, user amirthanath)
`cmd.list` -> `{"commands":[],"kinds":["option","tstruct","list","datasource"]}` (none defined). `/cmds` -> `cmd_catalog` with categories and about 24 commands (dm, reply, historydm, historygroup, host, historyhost, profile, requests, accept, reject, transfer, tstruct, tstruct-add, help ...). Shapes in live-shapes.md.

## "#command" typed in the workspace (web `ConnectumChatScreen.jsx` send handler)
A known `#command` is routed **before** the workspace's local branch, by the same `handleRouteHashCommand` as in every other chat: permission check, then the raw line is sent once to the server (except commands that are screens only or send themselves: help/commands/cmds, summary, tasks, apps, ai, agent commands, addmember, leavegroup...). So it is NOT faked locally and does not differ from other chats. Differences that exist only in the workspace: (1) text starting with `@user msg` or `@group msg` is sent as a DM/group message with a local echo "Sent to @user: ..."; (2) any other plain text, including an unknown `#word`, is local-only with a canned "Workspace Assistant" tip, whereas elsewhere it is sent as a normal message. `#summary`/AI commands switch the view to the workspace to show the answer.
