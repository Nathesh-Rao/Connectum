# `#tstruct`, `#tstruct <name>`, `#tstruct-add <name>`: what the web does

Read from `origin/dev` of ~/Development/Axi-apps, commit 4184e548589a2d4ac586ead28bcad69d26db6bc7 (paths under `connectum/`). Aliases: tstruct = ts, struct, tstructs, structure, structures; tstruct-add = create, ts-add, struct-add, structures-add (`connectum-backend/src/chat/chat_cmds.erl:126-131`). Web menu shows both by name (`chat-app/features/connectumChat/data/hashCommandsCatalog.js:293`).

## Suggestions while typing (same for both commands)
- Name mode (no space yet): the catalogue filtered by prefix (`Composer.jsx`, `updateMenuState`). Choosing a command only puts `#name ` in the box (`handleSelectCommand`, `Composer.jsx:~497`); Enter on a command that has a required argument does not run it.
- After a space: `/cmdcomplete {input,page:1,pageSize:10,reqId}` after 150 ms (`Composer.jsx:441-455`). The argument is type `phrase` (`chat_cmds.erl:127,130`), so the server lists the structures this person may fill, `fillable_tstructs` (`chat_cmds.erl:684-687`). Row: value = caption (else name), hint = internal name. A caption with spaces is one argument (`walk/4`, `chat_cmds.erl:613-630`).
- A row does one thing: it replaces the typed word with the value (`handleSelectArg`, `Composer.jsx:~526`). It does not run. No space is added after the last argument (`requiresNextArg`). No extra controls on a row. Server pages of 10 with a pager.
- Not found by `/cmdcomplete`: the menu closes (`Composer.jsx:196-205`).

## On send (all three): the raw line goes to the server once (`routeHashCommand.js:36-38`; neither command is in `sendsItself`). There is no tstruct branch in `routeHashCommand.js`; the screen opens from the answer (`chatEvents/workspace.js:197-231`, matched by `reqId` = the typed `#tstruct` / `#tstruct-add`).
- The composer always clears on send (`Composer.jsx` `handleSend`).
- Server: `tstruct.user.open {name}` (+ `mode:"add"` for tstruct-add) (`chat_cmds.erl:128,131`; `sd_cmds_forms.erl:190-222`). The name may be a caption (`find_tstruct_name`). Looks up the person's own structures, then admin ones the person may read. Answer: `{tstruct, scope:"user"|"admin", submissions:[my own records]}`. The `mode` is ignored by the server (same answer).

### `#tstruct-add <name>`
- Web opens `smart_structure` modal (SmartStructureModal) with `{type:"data_input", target:name, targetScope:scope}`, no record being edited (`workspace.js:211-224`). A single fill-in form; nothing is posted to the chat by the command. Submit is the ordinary submit (`tstruct.submit` / `tstruct.user.submit`); "Also post this to the chat" per `mobile-handoff/commands.md`.

### `#tstruct <name>`
- Web opens the `tstruct_user` modal = the Studio (`TStructUserModal.jsx`) at `/structs/<name>/records` (`workspace.js:206-210`), page `Records` (`form-studio/src/studio/pages/RecordPages.jsx:17-130`).
- It reads `getStruct` and `listRecords(id,{withMine:true})` = `submissions.list {tstruct, recordsOnly:true}` plus, from a second `submissions.list`, my own pending/rejected ones (`core/api.js:765-785`). So it lists every record of that structure the server shows this person (not only mine), newest first, with "N records".
- Actions: "New record" (opens the form page, `RecordPages.jsx:67,110`; hidden when read-only); per record Edit (only my own, not pending: `canEdit`, line 129) and Delete (line 130); header buttons Edit definition / Clone / Delete definition for the structure's creator or an editor (lines 89-107). Not an in-chat card; a full-screen modal.

## Bare `#tstruct`, bare `#tstruct-add`, unknown name
- Bare: the server refuses with `usage` (missing required `name`; `chat_cmds.erl:194-203,399-401`). The web turns it into an info tip "Command Tip" with a fixed text (`utils/serverMessageFormatter.js:70-73,134-160`): `#tstruct` -> "Please provide the struct name, e.g. #tstruct leave-request."; `#tstruct-add` -> "Please provide the struct name, e.g. #tstruct-add leave-request." (the server names the canonical command, so `#ts` / `#create` give the same two texts). Nothing lists structures on a bare send; the list is only the suggestions after `#tstruct `.
- Unknown / not allowed name: `not_found` "No such structure, or it is not available to you." (`sd_cmds_forms.erl:~205`), shown as an error toast (`workspace.js:228-229`). Nothing opens.

## Differences between the modes
- add: fill-in form, one record. (no mode) show: Studio list of the structure's records with New / Edit / Delete. Server call is the same.

## UNCLEAR
- Whether an unrecognised caption is matched case-insensitively is inside `sd_config:find_tstruct_name` (not read).
- Which records `submissions.list {recordsOnly:true}` returns to a non-creator (server-side visibility) was not traced.

## Mobile vs web
| Command | Web | Mobile (after this task) | |
|---|---|---|---|
| suggestions after `#tstruct ` / `#tstruct-add ` | `/cmdcomplete`, phrase list, row fills the caption | same `/cmdcomplete` | SAME |
| row pick | replaces word, no trailing space | replaced word + space; now no space for these two | was DIFFERENT, fixed |
| `#tstruct-add <name>` | one `tstruct.user.open`, fill-in form, nothing posted | same (`/form`, one open, no post unless ticked); also opens a kept form offline | SAME (offline extra is earlier owner work) |
| bare `#tstruct` | tip "struct name ... #tstruct leave-request." | had "structure name ... #tstruct-add ..."; now web text | was DIFFERENT, fixed |
| bare `#tstruct-add` (and `#create`) | tip "struct name ... #tstruct-add leave-request." | had "structure name"; now web text | was DIFFERENT, fixed |
| unknown name | server text, error toast | server text, warning notice, text kept | SAME text |
| `#tstruct <name>` | Studio records list of the structure (everyone's visible records, New record, Edit, Delete, definition tools) | My Submissions filtered to that form | DIFFERENT, needs decision |

## Task P: the exact typing sequence on the web (`Composer.jsx`, origin/dev `chat-app/features/connectumChat/components/`)
1. Typing `#`: `updateMenuState` (340-) sees no space yet: command menu, the friendly catalogue filtered by what follows `#` (`filterCatalogCommands`); `#tstruct` shows `tstruct` and `tstruct-add` (a prefix match), still the command menu, no names (356-368).
2. Picking a command row (tap, or Tab): `handleSelectCommand(cmd,false)` (501-523) writes `#<name> ` WITH a trailing space, then `updateMenuState` runs on it.
3. Enter on a command row while the menu is open (`handleKeyDown` 604-611): `handleSelectCommand(cmd,true)`; a command with a required argument is not run, it only writes `#<name> ` (501-512). So Enter on `#tstruct` never sends it while the command menu is open.
4. Text with a space after a known command: argument mode (371-385). The catalogue arg is `word` (`hashCommandsCatalog.js:231,241`), so there are no local suggestions; `/cmdcomplete {input:<text up to caret>,page:1,pageSize:10,reqId}` goes out after 150 ms on EVERY change (441-455). The server types the argument `phrase` (`chat_cmds.erl:127,130`).
5. `#tstruct ` / `#tstruct le`: the server's rows (caption as value) fill the dropdown; nothing is hidden because the argument is text-like.
6. Picking a name row: `handleSelectArg` (525-557) replaces the typed token with `item.value`; no trailing space (the command has one argument); menu closes; nothing is sent.
7. Send button / Enter with the menu closed: `handleSend` (486-499) sends the trimmed line once and clears the box. Send clicked with `#tstruct` typed (menu open): same, the line goes to the server, which answers `usage`; the web shows the tip "Please provide the struct name, e.g. #tstruct leave-request." (`serverMessageFormatter.js:70-73,134-160`).
8. The screen opens from the server's answer (`workspace.js:197-231`).
