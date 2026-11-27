# Ticket submission: web change and mobile gap (recon, 23 Nov 2026)

Read-only recon. Web repo: `~/Development/Axi-apps` (`origin/main` / `origin/dev`, fetched 23 Nov). Nothing was run or changed.

**Terms.** There is no separate "ticket submit" call. A ticket is a form (structure) with a Status field, saved with `tstruct.submit` / `tstruct.user.submit` like any form. What changed is the optional `chat` argument of that call: whether the filled form's card is also posted into the open conversation. The record itself always lands in the person's own submissions, which is what "My Work Space" lists. A ticket form with `recordThread` also gets its own `rec-<structure>-<id>` thread; the server posts there by itself and that did not change.

## 1. What changed on web

| Commit | Date | Author | What |
|---|---|---|---|
| `7f0277e7` "Chats panel shell…" (tests/docs in `6563c38b`, v1.5.0.47) | 2026-11-20 | Arjun Sridhar | Web client: new `utils/formChatTarget.js`; `SmartStructureModal.jsx`, `ConnectumChatScreen.jsx` use it |
| `930d901a` "Records from an option: no post-to-chat in a private chat (server ignores dm), threads post by themselves, a saved record returns to My Work Space" | 2026-11-20 | Arjun Sridhar | Backend: `sd_cmds_forms.erl` `post_target/1`; 4 BE test files |

Both are on `origin/main` and `origin/dev`; the earliest release tag containing `930d901a` is **v0.2.47** (latest seen: v0.2.54, 23 Nov).

Files touched: `chat-app/features/connectumChat/{utils/formChatTarget.js (new), components/modals/SmartStructureModal.jsx, ConnectumChatScreen.jsx}`, `connectum-backend/src/core/sd_cmds_forms.erl`, tests `connectum_{approvals,formfwd,formmsg,location}_test.mjs`, `tests/frontend/chatPane.test.mjs`, `tools/ui-audit/chat-shell.e2e.mjs`, docs `docs/CONNECTUM_API.md:955`, `docs/UI_DESIGN.md:26`.

| Chat the form is opened in | Before (web) | After (web) |
|---|---|---|
| Private one-to-one (`user-*`, `dm:<u>`) | Checkbox "Also post this to the chat with X", unticked. If ticked: `chat:"dm:<u>"`, card posted in the DM | No checkbox, no `chat`. Card only in My Work Space. After saving the person is taken to My Work Space (`returnsToWorkspace`; cancel and edits stay in the chat) |
| Shared thread: `room-care-<user>` or `rec-<struct>-<n>` | Checkbox; ticked and the person field locked **only** for `care-*` | No checkbox; always `chat:"group:<name>"`; card posted by itself |
| Team group (any other `room-*`) | Checkbox, unticked | Unchanged: checkbox, unticked |
| General room | none | none |

Shared-thread test (web `careTitle.js:isSharedThread`): the group **name** matches `^care-[A-Za-z0-9._-]+$` or `^rec-(.+)-(\d+)$`. No flag, no server field: it is a naming convention.

Request/response: `tstruct.submit {name, values, chat?}` (web does not send `cid` here). Answer `{submission, recordStatus, message?: {id, ts, conversation}}`; `message:null` = saved but not posted. With approvals on, nothing is posted until approved (server remembers the chat). Source: `CONNECTUM_API.md:955`, `formChatTarget.js`.

Backend (`930d901a`): `post_target(<<"dm:",_>>) -> undefined`. A `dm:<user>` chat is accepted and ignored: record saved, nothing posted, **nothing checked** (self, unknown user, non-contact all succeed). `group:<name>` unchanged (checked before saving: `not_found`, `forbidden`, `invalid`). The commit message says the old mobile app sent `dm:` explicitly.

Tests/docs added by web: BE tests above (dm ignored; cards now posted to groups); `chatPane.test.mjs` (rules, asserts no `setPostToChat(true)`); e2e checks (no checkbox in private chat and in a thread, checkbox in a team); docs lines above.

## 2. Current mobile behaviour (before)

Three ways a form is opened from a chat, one rule each:

| Entry | Code | `chat` sent today |
|---|---|---|
| Forms button (composer sheet) | `conversation_controller.dart:175` -> `FormsPickerController(convId: dm/group id)` -> `forms_picker_controller.dart:94`, `FormLaunch` with no `postChoiceTitle` | `chatToSend` (`form_controller.dart:119`) returns `launch.convId`: **always**, for every DM and group, no choice |
| `#tstruct-add <name>` | `command_runner.dart:160` (`_openStructure`) | `chat` only if box ticked (`hasPostChoice`); box offered in DM and group; default-on only for `care-*` (`ChatThread.careUser`), not `rec-*` |
| My Work Space, `/struct_records`, ticket detail, Smart View | `workspace_controller.dart:496`, `struct_records_controller.dart:171/191`, `smart_view_controller.dart:680`, `ticket_detail_controller.dart:369` | none (`convId` null) |

Send path: `FormController.done` -> `SubmissionRepository.submitForm` (`submission_repository.dart:~225`): writes `form_submissions` row + `outbox` row (`form_submit`, one `cid`), and **if `chat != null` writes a pending form message into that chat at once** (`_putPendingMessage`). `flush` -> `sdCall(tstruct.submit | tstruct.user.submit, submitArgs)`; `submitArgs` adds `chat` and `cid`. `_adopt` -> `_settleMessage`: server `message` id swaps the temp card; no message and not waiting-for-approval **deletes** the pending card; approval-pending keeps it. Offline: outbox entry waits, pending card shows; error handling per `_onSendError` (network drop stays pending, refusals fail with tap-to-retry). Encrypted chats: form screen shows a note that the form is not encrypted. Notifications: none specific to this.

Workspace and thread awareness already exist:
- Workspace is local only: feed built from `submissions.list` + `records.mine` (`WorkspaceRepository`, `mobile-handoff/workspace.md`). A saved record already appears there with no `chat`. **The data needed is already there.**
- Shared thread: `lib/data/models/chat_thread.dart` has the same two regexes as web (`isThreadName`, `careUser`, `isRecordName`), used for chat filters, avatars, chat info. Conversation kind comes from `ConversationRepository.kindOf(id)` (`dm|group|host|global`); group name from `ChatThread.groupName(convId)`. No new server field is needed.

Tests touching this: `test/forms/create_from_hash_test.dart:310-373` (asserts `chatToSend == 'dm:ana'`), `test/commands/command_runner_test.dart:148,215-260`, `test/struct_records/struct_records_test.dart:285-302`, `test/demo/demo_create_flow_test.dart`.

## 3. Gap analysis

| # | Web now | Mobile now | Gap |
|---|---|---|---|
| 1 | DM: never posts, no checkbox | `#tstruct-add` in a DM: checkbox, may send `dm:`; forms button in a DM: always sends `dm:` | **Wrong.** BE now ignores `dm:` so the record saves, but the app writes a pending card into the DM at once and removes it on the ack (a flicker; offline, a stuck "pending" card that never becomes real) |
| 2 | Shared thread (`care-*`, `rec-*`): always posts, no checkbox | `#`: checkbox, on by default for `care-*` only; `rec-*` unticked. Forms button: always posts (correct by accident) | Needs one rule: thread -> post, no box |
| 3 | Team group: checkbox, unticked | `#`: checkbox (matches). Forms button: **always posts** | Forms button posts without asking; web asks |
| 4 | Encrypted chats: web has no check (card is plain, BE confirmed) | App offers the choice in encrypted chats (decision 16 Nov); forms button always posts | Keep; rule 1-3 apply on top |
| 5 | After saving in a private chat: go to My Work Space | Stays on the chat (form closes) | Optional parity |
| 6 | Record saved in My Work Space | Already works (no `chat`) | None |
| 7 | `dm:` only "accepted and ignored" | App's mobile-handoff docs (`forms.md:109`, `commands.md:41`, `records-and-tickets.md:298`) still describe `dm:` | Docs stale; `reference/.be-sync-state` is 2026-11-18, before the change |
| 8 | Ticket `rec-*` thread card posted by server | Handled by live events (unchanged) | None |

## 4. Backend readiness

**Ready, no BE work needed.** The BE change is already in `main`/`dev` (v0.2.47+) and is backward compatible: old clients sending `dm:` still succeed. Group posting, approvals deferral and `message:null` are unchanged. No feature flag or version gate found (`grep` in `sd_cmds_forms.erl`). Confirm that the dev and prod servers the app uses run >= v0.2.47 (`GET /version`). Note the BE does **not** enforce "thread always posts"; that is purely client behaviour (client sends `chat`).

## 5. Implementation plan (smallest safe first; none needs a BE change)

1. **Re-sync BE docs** (`tool/be_sync/sync_be_docs.sh --dry-run`, read the diff, then run). Risk: none. Verify: `CONNECTUM_API.md` line about `dm:` appears; update `mobile-handoff/{forms,commands,records-and-tickets}.md` to the new rule.
2. **One pure rule, `FormChatRule`** (new small static class in `lib/features/forms/models/`, or a method on `ChatThread`): `decide(convId) -> {none | ask | always}`: DM/host/global/null -> none; group with `ChatThread.isThreadName(name)` -> always; other group -> ask. Files: `chat_thread.dart` or new file. Risk: low. Verify: unit test of the table above (only run tests when asked).
3. **Stop sending `dm:`**: in `FormLaunch`/pickers set `convId` only for groups (`conversation_controller.dart:175`, `command_runner.dart:208 _postableChat`). Fixes gap 1 (no phantom pending card in a DM) as soon as it lands. Risk: low. Verify: submit in a DM online and offline; no card in the DM, record in Work Space and My Submissions.
4. **`#tstruct-add` in threads**: no box, `chat` always sent (`command_runner.dart:150-170`, `FormLaunch`: replace `isPostedByDefault` with a `postMode`; `form_controller.dart:119 chatToSend`). Update the tests listed in section 2. Risk: low-medium (test churn).
5. **Forms button in a team group**: pass `postChoiceTitle` so the same box appears (`forms_picker_controller.dart`, `conversation_controller.dart:175`); in a thread pass mode "always". Risk: medium (behaviour change: today it always posts in teams). Verify: group chat -> box, unticked, nothing posted unless ticked; care and rec thread -> posts, no box.
6. **Return to My Work Space after a save from a DM** (web `returnsToWorkspace`): after `Get.back(result:true)` from a form opened in a DM, open `/workspace`. Files: `conversation_controller.dart` (picker/hash result), `workspace_controller.dart`. Risk: medium (navigation). Optional; decide in section 6.
7. **Docs**: update `mobile-handoff/*` lines from step 1 and the CLAUDE.md "Workspace and forms" paragraph (it currently says the box is offered in a direct chat or group).

## 6. Edge cases to decide

1. Group that is not a shared thread: keep the checkbox (web) on both `#` and the forms button? Recommended yes.
2. Thread becomes shared later: the rule is by name, so a group renamed to `care-*`/`rec-*` is not possible (names are fixed identities); no case unless the BE adds shared flags.
3. Old-way tickets still in a DM: they are ordinary stored form messages, stay visible and keep working (history, edit, record menu). Nothing to migrate.
4. Offline submit: the pending card is written into the chat only when a post is going to happen (groups/threads); DMs show only the Work Space row. Check that Work Space shows pending rows for a pending outbox form.
5. Approval on: in a thread/group the card appears only after approval; the pending card stays (existing behaviour).
6. Permissions: a thread member without access to the form still posts; the server decides who receives the card (`visible_to`). A forbidden/not_found `group:` target fails before saving (existing `_onSendError`).
7. Notifications: DM recipients no longer get a form-card push or live `form_message` for forms filed from a DM; check whether any mobile notification test expects it.
8. Encrypted group/thread: keep the existing note; thread posts always (BE posts plain card). Confirm this is acceptable for encrypted threads.
9. What the chat shows when the ticket goes only to the workspace: nothing; confirm with design whether a one-line "Saved to My Work Space" notice (the existing `SavedRecordNotice`) should appear after closing the form.
10. Edits/resubmits are never posted (unchanged).

## 7. Open questions

For you:
1. Should the forms button in a team group ask (box) like web, or keep always posting? (Recommended: ask.)
2. Do you want the "go to My Work Space after saving from a DM" jump (step 6), or just the existing saved notice?
3. Encrypted threads: always post (web does) or keep asking?

For web/BE team:
4. Is `isSharedThread` (name pattern) the intended permanent definition, or will a server flag (`thread:true`) be added to conversations?
5. Is the web's deliberate silence on a `dm:` target final (accepted and ignored), and will it ever return an error or `message:null` hint for it?
6. Which environments run v0.2.47+ (dev machine, test, prod) at the time of our release?
7. Should the BE enforce "a shared-thread record is posted" when a client omits `chat`, or is it client-only?
8. Does the web send `cid` on `tstruct.submit` yet? The app always does (duplicate-safe), so confirm nothing changed in `cid` handling.
