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

## `#tstruct-add` and `#tstruct` (built 16 Nov 2026)
**Web** (`routeHashCommand.js` forwards the raw line once; `chatEvents/workspace.js onSdReply`; server `chat_cmds.erl:125-131`, `sd_cmds_forms.erl:190`): `#tstruct-add <name>` (aliases `create`, `ts-add`, `struct-add`) = `tstruct.user.open {name, mode:"add"}`; the server takes the caption or the name, checks access (`not_found`: "No such structure, or it is not available to you."), answers `{tstruct, scope:"user"|"admin", submissions}`. The web then opens its fill-in form (SmartStructureModal) with `{type:"data_input", target, targetScope: scope}`. No chat message is posted; the composer clears. The submit is the ordinary `tstruct.submit` / `tstruct.user.submit` with `chat` only when the form's "Also post this to the chat" box is ticked (unticked by default, ticked in a person's care thread); no `ref`, no `meta`. `#tstruct <name>` (aliases `ts`, `struct`) = the same open without `mode`; the web shows the Studio's record list of that structure (my own records, Edit/Delete).
**BE doc check:** `MOBILE_RECORDS_FULL.md` has no section on creating a ticket from chat; the rule used is the code above plus section 5 (a form posted into a chat carries `chat`).
**App:** handler modes `form` / `records` in `command_handlers.dart`; `CommandRepository.run` returns `HashKind.form|records` with the typed name (nothing is sent, no empty name: usage text of the web). `CommandRunner._openStructure` calls `SubmissionRepository.openStructure` (one `tstruct.user.open`, definition kept per organisation, the form screen reuses it for 30 s: no second fetch; offline it opens a form already kept on the device by name or caption). Form: the existing `/form` screen, outbox, `cid`, per-field `invalid_values`, rate_limited retry, `SavedRecordNotice`; launched with no `convId`, so nothing is posted into the chat (the `chat` switch is a separate choice, see below) and the record shows in My Work Space. Records: `HomeShellController.openSubmissionsOf` shows My Submissions filtered to that form (an empty filter shows the normal empty state).
**Failures keep the text:** not_found (server text), rate_limited, offline with nothing kept ("Needs a connection"), anything else "Couldn't open that structure."
**Not built / simplified:** custom commands of kind `tstruct` still run `cmd.custom`. Every other `#` command not in the handler table stays "coming soon" (`find`, `connect`, `remind`, `host`, `profile`, ...).

### "Also post this to the chat" (web `SmartStructureModal.jsx:581,632,804,1086-1090`, `ConnectumChatScreen.jsx:963-977`)
- Web: the box exists only when the form has a `chatTarget` and is not an edit. `chatTarget` is the open chat: a direct chat `dm:<user>` or a group `group:<name>`; never the general room, so not in the workspace. Label: "Also post this to the chat with <chat title>". Unticked by default; ticked by default in a person's care thread (`room-care-<user>`, which also locks the form's `subject` list field to that person). Ticked: the submit carries `chat: <chatTarget.id>`; unticked: no `chat`. A record waiting for approval is posted only once approved (server).
- App: `CommandRunner` passes the open chat (`FormLaunch.convId`, `postChoiceTitle`, `isPostedByDefault`); `FormView` footer shows the switch (`hasPostChoice`); `FormController.chatToSend` sends `chat` only when ticked. Shown for `dm` and `group` chats only, **encrypted ones included** (decision of 16 Nov 2026, as on the web: the web has no encryption check and the server posts the card as a plain `form_message`). Hidden in the workspace, the global room and team (`host`) chats. A card the server posts into an encrypted conversation is stored as a plain `kind: form` row (no `e2e`, no `e2e1:` text, so no decrypt state) and drawn as a card between the encrypted messages; it never enters the decrypt queue. **For the BE to confirm: the server sees the form card content of a record posted into an encrypted chat; this is intended.** The form screen adds no warning for the `#` path; the forms button keeps its existing encryption note.
- Not built: locking the `subject` list field to the care person (the web's care-thread prefill, `prefill` lists).

### Edit and Delete of a record opened with `#tstruct <name>` (web `SubmissionsModal.jsx:196-212`, `submissionState.js:4`)
- Web gates: both buttons only for my own submission that is not pending/approved; Edit also hidden when declined and the approver did not allow a resend, and for a ticket form when the status is not in `editableIn`; a declined one allowed to resend shows "Fix and send again" (`submission.resubmit`). Delete = `submissions.delete {id}`; the server's message is shown on a refusal. No "may overwrite newer edits" text exists on the web, so the app only logs it (`RecordsLog`, debug).
- App: the detail screen (`submission_detail_view.dart`, `_Footer`): Edit/"Fix and send again" by `FormCardData.canEdit` / `canFix` (existing flow: outbox, `cid`, full value set), Delete by `FormCardData.canDelete` (mine, sent, not pending, not approved) after a confirm sheet; `SubmissionRepository.deleteSubmission` needs a connection, is never queued, drops the row, reads the list again (the workspace card follows) and returns plain words for `submission_locked`, `forbidden`, `not_found`, rate limit and offline. History rows stay on the server. The BE `editableIn` status table is not used (the record flow decides through `record.actions`); a refused edit shows as the existing "An edit was not saved: ..." notice.

### Field types in our form screen (audit against the web `FieldInput`, `SmartStructureModal.jsx:397-460`, and `CONNECTUM_API.md` field types)
Unknown types: the web falls back to a plain text input; we show a locked box "Supported in the next update" (`form_field_row.dart:98`), send nothing for it and block Done only when it is required (`form_controller.dart:217`). Nothing is dropped silently, nothing crashes.

| Type / construct | Status | Where (ours) | Size to finish |
|---|---|---|---|
| text, multiline | supported | `form_field_row.dart:259` (`_typed`) | - |
| text `rich` | partial: plain multiline, no formatting | same | M |
| email, url | supported (format checks) | `form_rules.dart:209-213` | - |
| mobile | partial: typed number with `withCountryCode` check, no country picker | `form_rules.dart:213-216`, `form_formats.dart:25` | S |
| wholenumber, number (min/max) | supported | `form_rules.dart:219-226` | - |
| date, time (min/max) | supported | `form_field_row.dart:145-154`, `form_rules.dart:227-250` | - |
| toggle (Yes/No) | supported | `form_field_row.dart:144,232` | - |
| list (options, `source`, multi) | supported | `form_field_row.dart:155`, `form_choice_menu.dart` | - |
| list `allowAll`, `allowTyping` | missing | no reader | S |
| list `prefill`, `subject` (care lock) | missing | no reader | S |
| selection (data source, `dependsOn`) | supported | `form_field_row.dart:156`, `form_controller.dart:377,400` | - |
| fill (`fillFrom`, `sourceProp`) | supported | `form_field_row.dart:132`, `form_controller.dart:654,689` | - |
| autogenerate | supported (shown, never sent) | `form_field_row.dart:121`, `form_rules.dart:79` | - |
| barcode | supported (typed or scanned) | `form_field_row.dart:158` | - |
| location | partial: typed `lat, lng`; no map/GPS, no street address lookup | `form_field_row.dart:169` | M |
| file | supported | `form_file_field.dart` | - |
| payment | supported (no payment service on the web either) | `form_payment_field.dart` | - |
| slot (booking) | supported | `form_slot_field.dart` | - |
| any other type | unsupported marker; required blocks Done | `form_field_row.dart:98`, `form_controller.dart:217` | per type |
| `required`, `readOnly`, `hidden`, `condition` (field and section), `default`, `min`/`max` | supported | `form_rules.dart`, `form_controller.dart:259-270` | - |
| `calc`, `rule`, `fetch` | supported (web logic bundle) | `assets/form_logic`, `form_controller.dart:1098` | - |
| `statusLocked` (status and completion of a ticket form) | supported since 16 Nov: not shown, not sent, not required | `form_controller.dart:266` | - |
| `statusAssignee` | partial: shown as an ordinary list (web: chosen at raise, locked later) | - | S |
| grid (repeating) sections, 200 rows | supported | `form_grid_editor.dart`, `form_controller.dart:196` | - |
| section captions and conditions | supported | `form_view.dart` | - |
| the person's own arrangement (`formlayout.get/save/reset`) | missing | - | M |
| `tstructs_changed` live notice while a form is open | missing | - | S |

### Demo structures (DEMO_MODE / SEED_UI, in `SeedUi.createFlowForms`)
`help_ticket` ("Ticket"): a status field (`stage`, `statusLocked`, so not shown) and an automatic send: saving shows "Saved", then "Sent on to Sam Joseph" from the fake record server (`SeedTickets`, `record.actions`). `help_task` ("Work order"): its status update asks for comments, completion, hours and a file. `asset_check` ("Asset check"): an optional `signature` field, a type the app cannot fill (shows the locked box). The four older demo forms are kept. `#create ticket`, `#ts ticket`, `#create nope` (notice, text stays) work offline in the demo; `test/demo/demo_create_flow_test.dart` (the demo-on cases run with `--dart-define=DEMO_MODE=true`).

## `#view`, `#smartview`, `#list` (built, phase 1; BE document revision 2, 16 Nov 2026)
- The server does **not** know them: `/cmds` lists 22 commands and none is `view`, `smartview` or `list`; `/cmdcomplete {"input":"#view le"}` answers `kind:"none"` with no items (capture `101-`). So **the app builds the entry and the suggestions itself** and never sends the line to the server; nothing is posted to the chat.
- Entry: a local catalogue entry (`CommandMenu.localEntries`: `view`, aliases `smartview`, `list`, category `lookup`, one `source` argument with `rest`), handler `CommandMode.smartView` (`CommandHandlers`), result `HashKind.smartView` with the typed name (`CommandRepository.run`), run by `CommandRunner._openSmartView`. Works in the Work Space, a direct chat and a group (every composer has a runner).
- `#view` with no name: a bottom sheet (`SmartViewPicker`) with Find (filters the list already loaded, as you type) and the structures, own before built-in, then caption A to Z. `#view <name>`: exact name or caption (case-insensitive), else the first that contains it; no hit: the warning `Nothing is called “X” that you can open.`, the text stays. No connection and no list in memory: `Needs a connection`, the text stays. A pick or a hit opens `/smart-view/<name>` and clears the box.
- Suggestions after `#view `: from the source list (`ai.enterprise {what:"forms"}`, read once per organisation per session, never per keystroke; cleared on an organisation switch, on `tstructs_changed` and after a reconnect), only `canFetch !== false`, contains the typed text, "starts with" first, own before built-in, at most 30, hint `your structure · N fields`; exactly one that equals the typed name: none (Enter runs it). Choosing one replaces everything typed after the command. `/cmdcomplete` is never called for them.
- Argument type `source` is not one of the server's types (`user, group, host, msgid, emoji, url, word, enum, text`); it stays a local type. The whole rest of the line is the name (spaces belong to it).
- `#list` is documented as "structures only"; only structures exist in phase 1, so the three words are the same.
- No deep link, URL or push opens Smart View (nothing to build). Details: `mobile-handoff/smart-view.md` section 0.
