# Visibility, sharing and workspaces

How a record (a ticket, a task, a submission) is shared and made visible to a person, what "My workspace" is, how the server scopes every record command, what happened to the records that existed before the record flow of 11 Nov 2026, and which chat messages carry a record. Written for the mobile team on 16 Nov 2026 from the code on `dev` (`16f8e509`) and from a **runnable scenario against a scratch backend** (`tools/records-visibility-scenario.mjs`: 33 checks, all passing at the time of writing; how to run it is at the end). A probe the mobile team can run on their own account is `tools/records-probe.mjs` (question 8).

Read first (not repeated here): [RECORD_ACTIONS.md](RECORD_ACTIONS.md) (Send, Update status, the holder, the history), [CONNECTUM_API.md](CONNECTUM_API.md) "Team records", [RECORD_STORAGE.md](RECORD_STORAGE.md) (where a record is kept), [MULTI_ENTERPRISE.md](MULTI_ENTERPRISE.md) (accounts, organisations, sessions), [WORKSPACE_FEED_MOBILE.md](WORKSPACE_FEED_MOBILE.md) (the bell), [CHAT_MESSAGE_UI_FOR_MOBILE.md](CHAT_MESSAGE_UI_FOR_MOBILE.md) (cards).

How to read the tags: **verified** = the scenario returned it (the matrix and the numbers below are its output); **code** = read from the named `file:function`, not run; each statement has one or the other. Anything neither is in "Not verified / open questions" at the end.

## The short version

1. **There are three different questions** a client can ask, and they have three different answers: "which records am I *working on*" (`records.mine`: `with`, `raised`, `involved`, `team`, `all`), "which records did I *make*" (`submissions.list`, the author's list) and "may I *open* this one" (`submission.get`, `record.actions`). They do not agree with each other. A record can be openable and in none of the lists (verified: an administrator, a manager, someone whose "involved" entry is missing), and a record can be in a list and not openable (verified, a bug: see Findings).
2. **"My workspace" is not a place on the server.** It is the person's own view inside **one organisation**: the one their session was made for. The web builds it on the device from `submissions.list` (what the person made), `records.mine` (`involved` and `with`: what was sent to them), the feed, the approvals and the messages of the host `workspace`. Nothing from another organisation is ever in it.
3. **The server scopes every command by the organisation of the session**, never by the person across organisations. A person in two organisations has two sessions (two tokens, two connections); records, feed items and live events of one never reach the other (verified).
4. **There was no migration** from the old ticket flow (PR #752, 11 Nov 2026): the lists `records.mine` reads are indexes written only when a record is made, sent or acted on after the change. A record from before is in `submissions.list` (for its author) and opens, but is in **none** of `with`, `raised`, `involved` (verified by reproducing the missing index entry). A client that reads `records.mine` only shows a person with old data an empty workspace.
5. **The old `ticket: true` flag on a form message is gone.** A card is a record card when its form object has a `submissionId` and is neither `readonly` nor a data-source `result`; whether it shows a status is decided by `record.actions` (question 5 quotes the web's rule).

## 1. How records and submissions are shared and made visible to a person

### In simple words

- Every record has an **author** (the initiator: who saved it) and a **holder** (who it is with now; the author until it is sent). **Send** hands it to someone: they become the holder and the person who sent it is the **assignor**. **Auto send** can share a new record with several people at once (the **claimants**): each may act on it, the first to act takes it, the others lose it from their list but keep it as "involved".
- Everyone a record was **sent or shared to** is a **participant** for good: they can open it, read its history and keep it in "involved", whether or not they still hold it.
- **Send rules** (a form's setting) only say **who a record may be sent to**; they never decide who can *see* a record. The same for **who may act** (the holder, a claimant or an administrator): that is separate from who may *read*.
- Who else reads a record without being sent it: its **author**, the author's **host**, the author's **reporting manager** (and a manager of anyone it is with or was sent to: "Team"), **administrators**, **approvers** while a stage is theirs, people **told once it is approved** (the form's notify settings), people the form lets **see every record** (a designation, a named person or the form's creator) and people with **branch access**.
- A person with none of these gets the answer `not_found`, the same as for a record that does not exist (never `forbidden`: the server does not say that a record exists).

### The roles and where each is kept

| Role | What it means | Kept as | Code |
|---|---|---|---|
| Author, initiator | who saved it | `by` | `sd_actions:initiator/1` |
| Holder | who it is with now (the author until sent) | `holder` (absent = the author) | `sd_actions:holder/1` |
| Assignor | who last sent it to the current holder | `assignor` | `sd_actions:assignor/1` |
| Participants | the author, and everyone it was sent or shared to | `participants` (list) | `sd_actions:participants/1`, `sd_actions:participant/2` (holder or listed) |
| Claimants | the people a record is shared with now (auto send to several) | `claimants` (list; the stored holder stays the author) | `sd_actions:claimants/1`, `sd_actions:can_act/3` |
| Recipient | someone it was sent or shared to | becomes a participant, and its id goes into their `sd:act:in:<person>` index | `sd_actions:involve/2` |
| Approver | the person asked to approve a stage | `approval.stages[].approvers` (filled when the stage opens) | `sd_subflow:can_view/2` |
| Notified | a person or designation told when it is approved | form's `notify`, `notifyUsers` | `sd_subflow:notified/2` |
| Form owner, "sees every record" | the form's creator, `seeAllUsers`, `seeAll` (designations) | on the form | `sd_config:sees_all_def/2` |
| Host, manager | the author's host or reporting manager (read only) | on the person | `sd_config:is_host_or_manager_of/2`, `sd_config:team_sees/2` |
| Administrator | | on the person | `sd_users:is_admin/1` |

The three indexes behind the lists, all per organisation and per person: `sd:act:with:<person>` (open records that are with them; written by `sd_actions:track/1`), `sd:act:in:<person>` (records they were given, shared or acted on; `sd_actions:involve/2`), and the author's list `sd:subs:u:<person>` (every record they made; `sd_subs`). `records.mine` reads these indexes; it does not scan records.

### Two different "may this person read it" rules (this is the source of the findings)

| Rule | Used by | Reads it for |
|---|---|---|
| `sd_subflow:can_view/2` | `submission.get`, `submission.history` | author, host, administrator, **an approver of an open stage**, **a notified person**, a participant, the author's manager, the team rule |
| `sd_config:can_see_submission/2` | every `record.*` command (`sd_actions:load/2`), `submissions.list`, `records.list`, `records.mine as=team` | administrator, author, host, the author's manager, a participant, the team rule, **"sees every record" (`sd_config:sees_all_def/2`)**, **branch access (`sd_dataaccess:can_view/2`)** |

They share: administrator, author, host, manager, participant, team. Only the first has approvers and notified people; only the second has "sees every record" and branch access (see Findings 1 and 2).

### The matrix (verified)

One organisation, one form **Ticket** (a status dropdown with a final status, Send on with no rules, a conversation per record, `fay` named as seeing every record), forms **Pool** (auto send to `dan` and `hal`), **Needs** (approved by the author's reporting manager `gus`), **Needs2** (approved by `gus`, then by the designation Lead held by `eve`; `ned` is told once approved), **Plain** (no status, no Send). People: `ann` (author), `bob`, `cat`, `dan`, `hal`, `gus` (ann's reporting manager), `fay`, `eve`, `ned`, the administrator, `yan` (no connection to anything). Each person calls each command about each record. `-` means "not in the answer / not_found". Columns: `with`, `raised`, `involved`, `team` = is the id in `records.mine as=...` (read through every page); `get`, `hist`, `actions` = `submission.get`, `submission.history`, `record.actions` (`ok` or the error code); `subs.list`, `rec.list` = `submissions.list {tstruct}` and `records.list {tstruct}` (the id is in the answer); `feed` = a `feed.list` item with `ref.submissionId` = the id.

**T1: ann makes a Ticket, sends it to bob, bob sends it to cat** (holder cat, assignor bob, initiator ann, participants ann, bob, cat)

| Person | with | raised | involved | team | get | hist | actions | subs.list | rec.list | feed |
|---|---|---|---|---|---|---|---|---|---|---|
| ann (author) | - | yes | - | - | ok | ok | ok | yes | yes | yes |
| bob (held it, sent it on) | - | - | yes | - | ok | ok | ok | - | - | yes |
| cat (holder) | yes | - | yes | - | ok | ok | ok | - | - | yes |
| dan, hal, yan (no part) | - | - | - | - | not_found | not_found | not_found | - | - | - |
| gus (author's manager) | - | - | - | yes | ok | ok | ok | yes | yes | - |
| fay ("sees every record") | - | - | - | - | **not_found** | **not_found** | ok | yes | yes | - |
| eve, ned | - | - | - | - | not_found | not_found | not_found | - | - | - |
| administrator | - | - | - | - | ok | ok | ok | yes | yes | yes |

**Other records, in one line each (same columns; only what differs from "no part")**

| Record | Result |
|---|---|
| T0, held by its author | ann: `with` yes, `raised` no. gus: `team`. administrator: opens it, in no `records.mine` list. |
| POOL, shared with dan and hal | dan and hal: `with` yes, `involved` yes, open, feed yes. ann: `raised` (it is away from her). After dan acts first: dan keeps `with`, **hal loses `with` but keeps `involved`**, both open it. |
| NEEDS, waiting for approval | ann: `raised`, opens it, not in `with`; nobody has it in `with`; `records.list` leaves it out (it is not a record yet). gus (manager and approver): opens, in `subs.list`. After approval: ann `with`. |
| NEEDS2, stage 2 open | eve (Lead, not the author's manager): `get` ok, `hist` ok, **`actions` not_found**, in no list. Before stage 1 is done eve gets not_found on all three. After approval ned (notified): `get` ok, `hist` ok, **`actions` not_found**, in no list. |
| PLAIN (no status, no Send) | ann: `with` yes, `record.actions` ok (the menu is empty). |
| CLOSED (held by ann, final status) | in nobody's `with`, `raised` or `involved`; ann still opens it and has it in `subs.list`/`rec.list`. |
| BACK (sent to bob and back) | ann: `with` yes again. bob: `involved`. |
| FIN (sent to bob, who set the final status) | bob: still `involved` (a final status does not remove it), not `with`. ann's `raised` drops it. |

Also verified: `records.mine as=all` (administrator) lists every open record that has a status and none without one, and not the finished ones; `as=team` answers `reports` and only the open records of the caller's direct reports; paging with `limit 2` over ten records read every record once (5 calls, 10 distinct).

### What each command returns (the rules, with code)

| Command | Returns | Code |
|---|---|---|
| `records.mine as=with` (default; any unknown `as` too) | open records **with me now**: I am the holder, or one of the claimants; not at a final status; a record waiting for approval is kept in the index but not shown. Newest first. | `sd_actions:with_me/3`, `sd_actions:check_with/3` |
| `records.mine as=raised` | records **I made** that are **away** from me (holder is someone else, or shared, or waiting for approval), not declined, not final | `sd_actions:raised_by/3`, `sd_actions:check_raised/3` |
| `records.mine as=involved` | records I was **given, shared with, or acted on**, never ones I made; I must still be a participant; not waiting for approval; **final records stay** | `sd_actions:involved_in/3` |
| `records.mine as=team` | a manager's view of direct reports (see "Team records") | `sd_actions:team_of/4` |
| `records.mine as=all` | administrators only: every open record of every form that has a status; anyone else gets `with` | `sd_actions:every_open/2` |
| `submission.get`, `submission.history` | one record, if the first rule above allows | `sd_cmds_forms:do/3` (`submission.get`), `sd_subflow:get/2`, `sd_subflow:can_view/2` |
| `record.actions`, `record.targets`, `record.people`, `record.send`, `record.status` | the menu, the Send picker and the actions, if the second rule allows | `sd_actions:load/2` |
| `submissions.list {tstruct?, limit, offset}` (the web's "my submissions") | records **I made**, plus those of people I host or who report to me, plus what is with or was sent to my reports; an administrator or a "sees every record" person with a `tstruct` gets that form's whole index. **Not** what was only sent to me. | `sd_config:list_submissions_page/2`, `sd_config:candidate_ids/5`, `sd_config:candidate_ids_own/4` |
| `records.list {tstruct}` (search) | the same people's records of one form, only real records (not waiting or declined), newest 1000 at most | `sd_config:search_records/2` |
| `records.about_me` | records whose "subject" field is me (not shared with me by Send) | `sd_config:list_about/2` |
| `feed.list` | the bell: one item per event for me, `ref.submissionId` names the record | `sd_feed:list/2`, `sd_feed:ticket_update/6`, `sd_feed:submission_created/1` |
| `req.list` | approvals waiting for me (the approver's own list) | `sd_reqs` |

What the web uses for My workspace and the Inbox: `submissions.list {offset, limit}` (own), `records.mine as=involved` and `as=with` (received), `records.mine as=with` and `as=raised` (Inbox, Smart View), `records.mine {}` and `as=team` (My submissions), `records.about_me`, `submission.get` + `submission.history` (open a record), `record.actions` (menu). See `chat-app/features/connectumChat/utils/useWorkspaceSubmissions.js`, `components/modals/SubmissionsModal.jsx`, `features/smartView/workItems.js`.

## 2. What "My workspace" is

**It is the person's own view inside the organisation of the session. Not a personal space of its own, not a view across organisations.** (code and verified)

- On the server "workspace" is only: the fixed chat host `workspace` ("My work space", `chat_hosts:?PRECONFIGURED`) and the **notification feed** (`sd_feed` module doc: "The 'My Workspace' notification feed"). Both live under the organisation's key prefix (`e:<id>:`), like everything else.
- On the web, the conversation `workspace` (`isWorkspace = activeChatId === "workspace"`, `ConnectumChatScreen.jsx`) is **assembled on the device** (`cardsHere`): the host's messages, plus `mwsSubmissions` (cards for the person's own latest records from `submissions.list` and the records sent to them from `records.mine as=involved` and `as=with`; `useWorkspaceSubmissions.js: loadReceived`, `readLatest`), plus the Message API items from the feed, plus the approval cards from `req.list`. Cards are rebuilt on `submissions_changed` and the other record events (`isRecordChange` in `recordActions.js`), at most every six seconds.
- **What appears in it:** your own records (latest 100), records sent or shared to you (up to 1000 per list), approvals waiting for you, API messages, notifications. **What does not:** records you made that are in no list (see 4), records of another organisation (see 3), records you can open but were never sent (administrator, manager, approver, notified: those are found through the Inbox, Smart View, Team, req.list or a search, not My workspace).
- **Which chat messages:** a record's card is in My workspace as a card built from the list, not as a stored chat message. The stored form messages (the card that was posted into a direct chat, a group or a record conversation) are in **that** conversation only.
- The "organisation" is the one the session was entered for. A person who belongs to several organisations has a separate My workspace in each, and the web shows one at a time (the log-out button is "switch organisation or sign out", MULTI_ENTERPRISE.md).

## 3. How the server scopes every record command

**By the organisation of the session, for every command; never by the person across organisations.** (verified)

- A session token is either an **account session** (after the email code; only used to list, join and enter organisations: `GET /api/sd/me`, `POST /api/sd/enter`) or an **organisation session** (made by `enter`; what the WebSocket and the app use). `sd_auth:session_record/1` reads the token and, for an organisation session, `enter_context/1` puts the process into that organisation (`sd_ent:put/1`, `sd_ent:ensure/1`). From then on `sd_ent:scope/1` (applied in `chat_redis`) puts `e:<id>:` in front of every key, so a command cannot read another organisation's key, and a process without an organisation fails (`no_enterprise`) instead of reading the wrong data. The files: `src/security/sd_auth.erl`, `src/core/sd_ent.erl`, `src/security/sd_ident.erl` (`memberships/1`, `enter/2`).
- `sd_ent:with/2` and `sd_ent:running/0` / `each_running/1` are for server code that works for **one named** organisation or for **all** (the scheduler, health, the message queue). No record command uses them: each runs inside the session's organisation.
- **Choosing and switching.** The client signs in with the email code (`login/start`, `login/verify`), gets the person's organisations (`GET /api/sd/me` with the account token: `enterprises: [{enterprise, name, username, category, status, ...}]`), and picks one with `POST /api/sd/enter {enterprise}`, which returns the organisation session token. **Switching is a new `enter` and a new connection.** There is no command to change organisation on an open connection (`enter` as an `/sd` action: `unknown_action`, verified). The two organisations can be open at the same time on two connections with two tokens (verified: both worked together).
- **Events and feed items do not cross.** A live event is delivered to the connection registered for `{organisation, username}` (`chat_room:get_pid/1`), so the same username in two organisations are two different recipients. Verified: a person in organisations A and B with one connection to each; a record sent to them in A produced `submissions_changed`, `ticket_assigned`, `form_message`, `feed_item` on the A connection and **nothing** on the B connection; `feed.list` on each lists only that organisation's records; `records.mine` (`with`, `involved`) on each lists only its own; `submission.get` of an id of the other organisation is `not_found`.
- **Ids are per organisation.** The record counter is `sd:seq:sub` under each organisation's prefix: in the run it read 99 in one organisation and 34 in the other, so **the same id can be two different records**. A client that stores records of several organisations must key them by `(organisation, id)`; the feed item's `ref` has no organisation, so the connection it came on is what says which.
- **A second sign-in replaces the first.** Entering the same organisation again (a second `enter` for the same person on the same kind of device) makes a new session and the earlier one stops working (verified: the first connection's next command failed). `docs/MULTI_ENTERPRISE.md` and `CONNECTUM_SESSION_SLOTS` describe the slots (web and mobile each have one).
- A call **without** a session names the organisation in the `x-connectum-enterprise` header (consumer calls, payment webhooks); there is no such thing for a person's record commands.

What the mobile symptom could mean here: if the phone's session was entered for a different organisation than the one that holds the records (the person belongs to several on dev), every command answers correctly and empty. The probe prints the organisation the session resolves to and the person's organisations (question 8).

## 4. Old data versus the new record flow (PR #752, 11 Nov 2026)

**There is no migration.** (code, from `git log -S` and `git show 46a8e0e0`; the missing-index state is verified)

- #752 (`46a8e0e0`, 11 Nov 2026) removed the old ticket flow in one commit: `sd_status.erl` (the `status` field type, `status.update/mine/get/history`, the `status_<form>` history, the `ticket` flag) and added `sd_actions.erl` and `sd_history.erl`. The commit message and RECORD_ACTIONS.md say it plainly: "Nothing was migrated: it starts fresh."
- The old "with me" list was the index `sd:status:with:<person>`, filled by a **backfill** per form (`sd_status:ensure_ready`, `backfill`). The new one is `sd:act:with:<person>`, written by `sd_actions:track_new/2` **only when a record is made** (`sd_config:store_claimed/8`, and when an approval finishes: `sd_config:on_approved/3`) and by `sd_actions:track/1` when it is sent or acted on. `git log -S"sd:act:with"` finds only #752; nothing in `src/` reads `sd:status:` any more; no backfill, rebuild or import of the old index exists.
- The involved index `sd:act:in:<person>` (what a person was given or acted on) came a day later with #773 (`7bb3ee00`, 12 Nov 2026, "records stay in My Workspace"), also with no backfill: records sent between #752 and #773 are not in the receivers' `involved` list.
- Who the record is "with" used to be the value of an assignee field; now it is `holder` on the record, **absent on an old one, which reads as the author** (`sd_actions:holder/1`). The old people-lists `participants` were not written either, so an old ticket's assignee is not a participant and **cannot open it any more** unless they are the author, an administrator, manager, host or approver (code; not run on real old data).

**So, for a record that existed before and was never touched since** (verified by removing the index entry of a normal record, which is exactly what an old one lacks):

| What | Result |
|---|---|
| In `records.mine` as `with`, `raised` or `involved` for its author | **no, in none of the three** (the author holds it, so it is not "raised"; the `with` index does not have it) |
| In `submissions.list` and `records.list` for its author | yes |
| `submission.get`, `submission.history`, `record.actions` for its author | ok |
| Manager of the author | in `team` (the team rule reads the author's list, not the index) |
| Once it is sent or acted on | `track` and `involve` write the indexes: the receiver has it in `with`, the author in `raised` (verified) |

**Is there a state where a record the person made and still holds, or an old/closed one, shows in none of with/raised/involved but IS visible on the web?** Yes, three (all verified):
1. a record made before #752 and never sent since: the web shows it through `submissions.list` (own list), `records.mine` cannot return it;
2. a record at a **final status**: `with` and `raised` leave it out by design (an `involved` entry stays only for a person it was sent to); the author finds it in `submissions.list`;
3. a record sent before #773 whose receiver no longer holds it: openable, in no list of theirs.

**Which command does the web use for its ticket and submission lists, with which filters?** My workspace and "My submissions": `submissions.list {offset, limit}` (no `tstruct`, so every form; the person's own records, 100 per page, up to 10 pages) **and** `records.mine as=involved` and `as=with` (limit 100 per page, up to 1000, de-duplicated by id, dropping the person's own and the waiting ones); the Inbox, Smart View "Tasks & tickets": `records.mine as=with` and `as=raised` (100 per page; `as=all` for an administrator); My submissions "Team": `records.mine as=team`; "About me": `records.about_me`. The web never relies on `records.mine` alone for a person's own records. A mobile screen that does will not show old ones.

**What happened to the chat messages of old tickets?** They are stored form messages (`kind: form`, JSON in the message text) and were not touched. An old ticket's card has `ticket: true` and a status table inside its `form` object, which the new code ignores; the card still carries `submissionId`, so a client that follows question 5 draws it as a record card. (code; no real old message was read.)

## 5. Chat messages: which ones, how history delivers them, how to tell a ticket

### Where a record's card appears

| Conversation | A card appears there when | Code |
|---|---|---|
| A direct chat or a group | someone **posted a form into it** (`tstruct.submit` with `chat: "dm:<user>"` or `"group:<name>"`) | `sd_formmsg:post/4` |
| The record's own conversation `group:rec-<form>-<id>` | the form has `recordThread` on: the author's card, then **one card per action** (Send, Update status); the people in it: the author, the people the form names (subject or "involve" fields) and every person the record is sent to | `sd_recthread:on_saved/3`, `sd_recthread:action_done/5` |
| My workspace | no stored message: cards are drawn from the lists (question 2) | `useWorkspaceSubmissions.js` |
| The general room, a host channel | never (forms are not posted there) | `sd_formmsg:check_target/2` |

Verified in the scenario: the record conversation of T1 held three cards (the form and two action cards); ann (author), bob (held it, sent it on) and cat (holder) read all three from history; gus (the author's manager), yan (a stranger) and the administrator read none, and asking the server for that conversation as a stranger is `not_found` ("No conversation for that record.").

### How a card arrives

- **History replay**: `/history dm|group <name>` answers `{type:"history", scope, list:[...]}`; a card is an item with `kind: "form"` and a `form` object next to the usual `id, ts, from, text, reactions, deleted, replyTo, ...` (verified keys: `deleted, editedTs, form, from, id, kind, previewDescription, previewImage, previewTitle, previewUrl, private, reactions, replyTo, text, ts`). `text` is a one-line summary (`sd_formmsg:display/1`). The web draws it in `chatEvents/history.js` (`if (m.kind === "form" && m.form) return formToCard(...)`).
- **Live**: an `sd_event` named `form_message` `{conversation, id, ts, from, form, text}` (`sd_formmsg:tell/5`), and `form_message_updated` `{conversation, id, from, form, text}` when the author edits the record, which rewrites the stored card in place (`sd_formmsg:refresh/3`). The conversation id is `dm:<other>` or `group:<name>` as seen by the receiver. Verified live events for a Send: the author `submissions_changed`, `form_message`, `form_message_updated`; the new holder `submissions_changed`, `ticket_assigned`, `feed_item`, `form_message`, `form_message_updated`; a stranger nothing.
- **The `form` object**: `{structure, scope, caption, submissionId, by, fields:[{name, caption, value, label?, files?, subject?}], about?, aboutCard?, forwardedBy?, result?, readonly?, record?}` (`record` only for people who may read the record, see "Summary on events and cards") (verified keys of a normal card: `by, caption, fields, scope, structure, submissionId`; of an action card: the same plus `readonly`). The status field and its four hidden companions are **not** in `fields` (`sd_actions:drawn_names/1`).

### Which field identifies the record

| Card | `form.structure` | `form.submissionId` | The record's number |
|---|---|---|---|
| The form posted into a chat, or the first card of a record conversation | the form's name | **the record's id** | `submissionId` |
| An action card in a record conversation (Send, Update status) | `record_history` (and `readonly: true`) | the id of the **history row**, not of the record | the field named `Record` in `form.fields` (whole number); the other fields are `Structure`, `Event`, `Actor`, `Target` (verified) |

A card has no `ticket` or `holder` field inside `fields`. It carries one extra key next to `fields`: **`form.record`** `{status, holder, claimants, completion, final, ts, by}`, the CURRENT state of the record (in the live `form_message`, in `form_message_updated` after every Send or Update status, and in `/history` replay, so a card replayed days later shows today's status). It is **not stored in the message**: the server adds it for each person who may read the record (the same rule as `record.actions`, `sd_config:can_see_submission`, not the card's own `visible_to`). A person who sees the card because they have access to the form but may not read this record gets the card WITHOUT `record`: show it as a plain card and do not read the missing key as "no status". A form without a status dropdown still gets `record` (`status` and `completion` null). Action cards (`record_history`, `readonly`) carry no `record`. Shapes: `docs/CONNECTUM_API.md`, "The `record` summary".

### Completion and closing (for the mobile team)

Only for a form whose status has a final option (`record.actions` returns `finalStatuses`; empty means none of this applies). Moving to a final status always stores completion 100, whatever `percent` is sent (none, lower or 100). `percent: 100` on a status that does not close is refused with `invalid`: "100% completion is only for a closing status. Choose a closing status." Other statuses take 0 to 99; no `percent` keeps the current completion. A member cannot go below `minCompletion` ("Completion cannot go down."); an administrator may lower it (`minCompletion` is 0). In the dialog: start at `completion`, minimum `minCompletion`; a final status shows 100 locked with "Closing this ticket sets completion to 100%. After it is closed, only an administrator can change it."; if the person picks 100 on a non-final status, select the first entry of `finalStatuses` (option order) and say so. Old final records below 100 stay as stored. Full rules: RECORD_ACTIONS.md, Completion and closing.

### Summary on events and cards

A `record` summary (`status, holder, claimants, completion, final, ts, by`) is added to `submissions_changed`, `ticket_assigned` and to a card (`form.record`), and answered for many records by `records.summary {ids}` (up to 50). It is given **only** to a person for whom `record.actions` would answer, that is the rule `sd_config:can_see_submission` (the rule the lists and `record.actions` use), never the card's own rule `visible_to` (access to the structure). So a person in a record's conversation who may not read the record gets the event and the card without `record`; the status is never stored in the shared message (it is added per person when the message is pushed or replayed); in `records.summary` an unreadable record and a missing one look the same. A manager of the holder (the team rule) does get it. Shapes and tests: `docs/CONNECTUM_API.md`, `connectum_record_summary_test`.

### The removed `ticket` flag, and the rule the web uses now

Before #752 `sd_formmsg:ticket_mark/2` added `"ticket": true` to the `form` object of a form with a status field, and the web drew the ticket under the card when `form.ticket && form.submissionId`. **#752 removed that**: `ticket_mark` now only adds `readonly: true` to a history row (verified: no card has a `ticket` key). A client that still tests `form.ticket` finds no tickets at all.

The web's rule today, quoted:

```js
// chat-app/features/connectumChat/utils/formMessages.js: formToCard
...(form.submissionId && !form.readonly && !form.result ? { recordId: form.submissionId } : {}),   // the record's actions (Send, Update status) are in the card's menu
```
A card with a `recordId` is a **record card**. Whether it shows a status line under the card is the card's own state, read from `record.actions`:
```js
// chat-app/features/connectumChat/components/modals/RecordActions.jsx: RecordCard
const hasStatus = !!(state.status || state.holder !== state.initiator || (state.claimants || []).length || state.lastUpdate || (state.files || []).length);
if (!hasStatus && !open && !notice) return null;
```
and the menu items come only from the answer (`MessageList.jsx`: `for (const it of recState.items || []) items.push(...)`; `Update status` is in `items` only when the form has a status: `sd_actions:menu/2`). **So "is it a ticket" is: the form has a status dropdown, i.e. `record.actions.status` is not `null` (or `statuses` is not empty, or `records.mine` `structures[<form>].status` exists).** Lists use the last one (`workItems.js: workItem`: `const status = form?.status`).

## 6. Visibility rules by role, and what a person without access gets

| Who | Can open the record (`submission.get`, `.history`) | Can use the menu and lists (`record.actions`, `submissions.list`, ...) | Sees the card in a chat they are not part of |
|---|---|---|---|
| Author | yes | yes | yes, in any conversation it was posted to |
| Holder, claimant, anyone it was sent or shared to | yes | yes | in the record conversation: yes |
| Administrator | yes | yes | yes, if the card was posted where they are |
| Author's host, author's reporting manager | yes | yes | no (not in the thread) |
| Manager of someone it is with or was sent to | yes (read only) | yes; every action refused | no |
| Approver of an open stage | **yes** | **no (not_found)** | no |
| Notified once approved | **yes** | **no (not_found)** | no |
| "Sees every record" (a named person: verified; a designation or the form's creator: code, same function) | **no (not_found)** | yes | no |
| Branch access (`sd_dataaccess`) (code, not run) | **no (not_found)** | yes | no |
| Anyone else | no | no | no |

**A card in a conversation** is delivered, live and in history, to a member of that conversation only if they are the author or the person it is about, an administrator, the form is a person's own (`scope: "user"`), or **the form is open to them** (`sd_config:tstruct_for_user/2`, or read-only access, `sd_config:readable_by_user/2`): `sd_formmsg:visible_to/2`. This is about the **form**, not the record: a member of a group who may open the form sees every card of it posted in the group, whether or not they may open that record. A member who may not open the form receives nothing, live or in history (verified: the card posted to a group of three was in the history of the two who can use the form and not of the third, and the third got no live event). Forwarding follows the same rule (`forms.forward`, `hiddenFrom`).

**What a person without access gets** (verified, strict mode, a person with no relation to the record; every one is the same answer, so the server never says that a record exists):

| Command | `error.code` | `error.message` |
|---|---|---|
| `submission.get`, `submission.history` (also an id that does not exist, and a missing id) | `not_found` | `No such submission.` |
| `record.actions`, `record.targets`, `record.people`, `record.send`, `record.status` (also an id that does not exist) | `not_found` | `No such record.` |
| `record.thread` | `not_found` | `No conversation for that record.` |
| A history row (a record Connectum keeps itself) for a person who may see it | `invalid` | `This record is kept by Connectum.` (code, `sd_actions:load/2`) |

`forbidden` is for someone who can see the record but may not do the action (not the holder: `Only the person it is with can do this.`), `stale` for a screen that saw an older state, `invalid` for a record in a final status or waiting for approval (RECORD_ACTIONS.md, Errors).

## 7. The back-end pieces to read

| What | Where |
|---|---|
| `records.mine` and its lists | `src/core/sd_cmds_forms.erl` `do(<<"records.mine">>, ...)` -> `src/forms/sd_actions.erl`: `mine/2`, `with_me/3`, `check_with/3`, `raised_by/3`, `check_raised/3`, `involved_in/3`, `team_of/4`, `every_open/2`; the indexes `with_key/1`, `in_key/1`, `track/1`, `track_new/2`, `involve/2` |
| The two visibility checks | `src/forms/sd_subflow.erl` `can_view/2`, `get/2`, `notified/2`; `src/forms/sd_config.erl` `can_see_submission/2`, `manager_reads/2`, `team_sees/2`, `sees_all_def/2`; `src/forms/sd_actions.erl` `participant/2`, `load/2`; `src/forms/sd_dataaccess.erl` `can_view/2` |
| The author's lists | `src/forms/sd_config.erl` `list_submissions_page/2`, `candidate_ids/5`, `candidate_ids_own/4`, `search_records/2`, `list_about/2` |
| History and menu | `src/forms/sd_history.erl` (`events/1`, `list/2`, `is_history/1`); `src/forms/sd_actions.erl` `menu/2`; `src/core/sd_cmds_forms.erl` `submission.history` |
| The organisation of a session | `src/security/sd_auth.erl` `session_record/1`, `enter_context/1`; `src/core/sd_ent.erl` `put/1`, `get/0`, `with/2`, `ensure/1`, `scope/1`, `running/0`; `src/security/sd_ident.erl` `me/1`, `enter/2`, `memberships/1`; `src/http/sd_http.erl` (`GET /api/sd/session` returns `enterprise`); `src/http/chat_web.erl` `complete_registration_checked/4`; `src/chat/chat_room.erl` `get_pid/1`, `takeover_user/3` |
| Chat cards | `src/forms/sd_formmsg.erl` `post/4`, `payload/3`, `tell/5`, `refresh/3`, `visible_to/2`, `ticket_mark/2`; `src/forms/sd_recthread.erl` `on_saved/3`, `action_done/5`, `thread/2` |
| The feed | `src/forms/sd_feed.erl` `list/2`, `ticket_update/6`, `submission_created/1` |
| **Migration from the old ticket model** | **none.** The old module `sd_status.erl` was deleted in `46a8e0e0`; nothing reads `sd:status:with:*`; there is no backfill of `sd:act:with:*` or `sd:act:in:*` (checked with `git log -S` and by reading `sd_actions.erl`) |

## 8. The probe

`tools/records-probe.mjs` asks the server what it answers to **one person** and prints **only counts, ids and yes/no**: never the text of a record, never a token. It changes no data. Node 22 or newer, no packages.

What it prints, per organisation: the organisation id the session resolves to (`GET /api/sd/session`); the person's list of organisations (`GET /api/sd/me`, only with an email sign-in); for `records.mine` `as=with`, `raised`, `involved` and `team`: how many records come back over how many pages, `total`, `hasMore`, the first ids, and whether offset paging works (two reads of one record at different offsets return different records); the number from `submissions.list` (the web's own list) and how many of them the person made; `feed.list` (items by category, how many are about a record, their ids); and `submission.get` + `record.actions` for the first id of each list (`ok` or the error code, and whether the person is the author or the holder, as yes/no). With `--shape` it also prints the first record of each list as JSON with every text replaced by `<text>` (the exact shape, no content).

### How to run it

```
# with the app's own session token (an ORGANISATION session; no new session is made)
node tools/records-probe.mjs --base https://dev.connectum.app --token <session token>

# with the email sign-in (what the sign-in screen does): ask for the code, then use it
node tools/records-probe.mjs --base https://dev.connectum.app --email me@example.com --start
node tools/records-probe.mjs --base https://dev.connectum.app --email me@example.com --otp 123456 --all-orgs --shape

# on a local scratch backend started with CONNECTUM_DEV_OTP=1 (the code comes back by itself)
node tools/records-probe.mjs --base http://localhost:8271 --email me@example.com --dev --all-orgs --shape
```
`--enterprise <id>` probes one organisation, `--all-orgs` every active one. With a token, the organisation list is not available (a token names one organisation): use the email sign-in for that.

Two side effects, both by design of the server, so choose the way knowingly: (1) an email sign-in **enters** an organisation, which makes a session of its own and **ends the person's earlier session of the same kind** there (verified: the first connection stopped working): the phone would be signed out; (2) while it runs, the probe's connection is the person's live connection of its kind and replaces an older one of the same kind (the app reconnects).

**We (the Connectum side) cannot read the mobile team's dev account**: we have no access to their session or their organisation on dev, and the sign-in code goes to their email. So they run the probe themselves, preferably with the app's own token (taken from the app's debug log or a proxy: the token is secret, so do not paste it anywhere) or with their email sign-in on a quiet moment, and send back **the whole output** (it holds no record text and no token), plus: the web's view of the same person on the same organisation (does My workspace there show the tickets?), and the organisation id the web shows for the same sign-in. What the output tells us:

| If the output shows | It means |
|---|---|
| the session resolves to another organisation id than the web's, or the person has several organisations | the app entered the wrong organisation: nothing is wrong with the records (question 3) |
| `submissions.list` has records made by the person, `records.mine` has none | old data or final records: the app must also use `submissions.list` (question 4) |
| `records.mine` has ids, the app shows nothing | an app problem (the `ticket` flag, the `as` used, paging by `next`, filtering by status), not a server one |
| `submission.get` is `not_found` for an id the feed names | that record is in another organisation's session, or the person lost access |
| `feed.list` has items about records, `involved` has none | records sent before 12 Nov (#773): openable, in no list |
| every count is 0 and `feed.list` is empty | the person really has nothing in this organisation (or the wrong one) |

### Captured example (scratch backend, ids only)

A person `sam` who belongs to **two** organisations on a scratch backend; one ticket was sent to them in each organisation by a person of the same username (`ann`) in both. Command: `node tools/records-probe.mjs --base http://localhost:8271 --email <sam's email> --dev --all-orgs --shape`. (The organisation ids differ in every run.)

```
organisations of the person (account Z8VB-JJSZ): 2
  - 8EGW-G5FA  username length 3  status active
  - XREQ-ZQZR  username length 3  status active

== organisation 8EGW-G5FA ==
  organisation the session resolves to: 8EGW-G5FA
  records.mine as=with: 2 records over 1 page(s), total 2, ids 28,25; paging ok (first 28, then 25, hasMore true)
  records.mine as=raised: 0 records over 1 page(s), total 0, ids none; paging n/a (fewer than 2)
  records.mine as=involved: 2 records over 1 page(s), total 2, ids 28,25; paging ok (first 28, then 25, hasMore true)
  records.mine as=team: 0 records over 1 page(s), total 0, reports 0, ids none; paging n/a (fewer than 2)
  submissions.list (the web's own list): 0 on the first page, 0 made by you, total 0, hasMore false, ids none
  feed.list: 3 items (security 1, submissions 2), 2 about a record, record ids 28,25; unread 3
  submission.get id 28 (first of with): ok; by you false, holder is you true, status none; record.actions ok (menu items 2)

== organisation XREQ-ZQZR ==
  organisation the session resolves to: XREQ-ZQZR
  records.mine as=with: 2 records over 1 page(s), total 2, ids 100,97; paging ok (first 100, then 97, hasMore true)
  records.mine as=raised: 0 records ...    records.mine as=involved: 2 records, ids 100,97
  submissions.list (the web's own list): 0 on the first page, 0 made by you, total 0
  feed.list: 4 items (security 2, submissions 2), 2 about a record, record ids 100,97; unread 4
```
Read it like this: the same person, two organisations, two different id sets (the ids 28 and 100 are different records in different organisations); `submissions.list` is empty for a person who only **received** records, which is why a client that wants them must use `records.mine`; `hasMore true` with a `limit` of 1 and a `next` of `null` (see below).

### The JSON shapes of `records.mine`

Request (WebSocket): `/sd records.mine {"as":"with","limit":100,"offset":0,"reqId":"x"}`. `as` is `with` (default), `raised`, `involved`, `team` or `all` (administrators; anyone else gets `with`); any other value is answered as `with`. `limit` 1 to 200 (default 100, clamped), `offset` 0 or more. Answer (`type: "sd"`, `ok: true`), captured with texts replaced:

```json
{ "ok": true, "type": "sd", "reqId": "x", "data": {
  "hasMore": true, "next": null, "total": 2,
  "structures": { "Ticket": {
      "caption": "<text>",
      "fields": { "title": "<text>", "stage": "<text>", "stage_comments": "<text>", "stage_completion": "<text>", "stage_files": "<text>", "stage_hours": "<text>" },
      "recordThread": true,
      "status": { "field": "<text>", "statuses": ["<text>", "<text>"], "final": ["<text>"] } } },
  "submissions": [ { "id": 28, "tstruct": "<text>", "scope": "<text>", "by": "<text>", "holder": "<text>", "assignor": "<text>",
                     "participants": ["<text>", "<text>"], "actionSeq": 1, "ts": 1794814801026, "editedTs": 1794814801051,
                     "branch": "<text>", "host": null, "values": { "title": "<text>", "stage": "<text>" } } ] } }
```
- **`as: "with"` and `"involved"`**: exactly the shape above. `next` is **always `null`**: continue with `offset = offset + number of submissions received` while `hasMore` is true (the web does `offset += page.length`). `total` is the size of the index (it can include a waiting record that is not shown, so `total` can be larger than what you finally read).
- **`as: "raised"`**: the same keys. `next` is `null` when the whole list was read, else the position to continue from (use it, as `team` does); `total` is the number of records in this answer, not of the whole list.
- **`as: "team"`**: the same plus `"reports": <number>` (how many people report to the caller), and each submission also has `"team": {"members": [...], "via": ["holder"|"sent"|"claimant"|"raised"]}`. Read in steps with `next` (CONNECTUM_API.md, "Team records").
- **`as: "all"`** (administrator): the same keys as `with`.
- A record that was shared with several people at once also has `"claimants": [...]`; one that was acted on also carries `"completion"` and `"hours"` when an update gave them (RECORD_ACTIONS.md). An empty answer is `{"hasMore": false, "next": null, "structures": {}, "submissions": [], "total": 0}` (captured), never an error; an error is `{ok:false, error:{code, message}}` (for example `rate_limited`).

## Findings

Two real inconsistencies, found while building the matrix. Nothing was changed in the backend; both reproduce with `tools/records-visibility-scenario.mjs` (checks marked INCONSISTENCY).

**1. A person who "sees every record" of a form lists the record but cannot open it.** `fay` is named in the form's "See every record" (`seeAllUsers`, set through the permissions form: `perm_modules`, "Ticket: See every record"). On a record of that form by someone else: `submissions.list {tstruct}`, `records.list {tstruct}` and `record.actions` include/answer ok, but `submission.get` and `submission.history` answer `not_found`. Cause: `submission.get` uses `sd_subflow:can_view/2`, which has no `sd_config:sees_all_def/2` (nor `sd_dataaccess`); the lists and `record.*` use `sd_config:can_see_submission/2`, which has. Effect on mobile: the record is in the list and the screen that opens it says "No such submission". Likely fix (not made): one shared predicate, or `can_view` also asking `sees_all_def` and the data-access rules.

**2. An approver and a notified person can open a record but cannot act on it or find it.** `eve` (holds the designation Lead, stage 2 of the approval) and `ned` (`notifyUsers`, told once approved), neither of them the author's manager: `submission.get` and `submission.history` are `ok` once the stage is open (and for `ned` once approved), but `record.actions` (and so the menu, `record.targets`, the card's status) is `not_found`, and the record is in no list. Cause: the same split, the other way: `can_view` has approvers and `notified`, `can_see_submission` does not. Effect: a card opened from an approval or notification fails when the app reads its menu. (A person who is also the author's manager does not see this, which is why the first matrix rows looked fine.)

**3 (documentation).** RECORD_ACTIONS.md says the commands are available as "WebSocket `sd` action or `POST /api/sd/<command>`". On this tree the only HTTP routes under `/api/sd/` are the sign-in, session, feed, files and similar ones (`sd_http.erl`); `POST /api/sd/records.mine` answers `not_found` "No such endpoint." (verified by the probe's first version). The record commands are WebSocket commands. The sentence now says so (fixed at the source in RECORD_ACTIONS.md, 16 Nov 2026).

**4 (a trap, not a bug).** `records.mine` `with` and `involved` answer `next: null` even when `hasMore` is true, `raised` and `team` answer a real `next`. A client that follows `next` blindly stops after the first page of `with`. Use `offset += received` for those two (the web does).

## Not verified / open questions

- **The mobile team's real data.** We cannot read their dev account (no session, the code goes to their email): everything above is from a scratch backend and from the code. That the app's symptom is caused by one of the cases in question 4, the `ticket` flag, or the wrong organisation is a **hypothesis**, in that order of likelihood; the probe is how to tell.
- **Real old data.** No pre-#752 record or message was available: "old data" was reproduced by removing the `sd:act:with` (and `sd:act:in`) entry of a normal record, which is exactly what an old record lacks; the old record's own shape (no `holder`, no `participants`, an assignee in a field, a `status`-typed field in the form's definition) was read from `git show 46a8e0e0^` and not run. Open: what `record.actions` and `submission.history` answer for a real old ticket (the old `status_<form>` history is not read by `sd_history`), and how a stored form definition with a `status`-typed field behaves after the type was removed.
- **The assignee of an old ticket losing access** (question 4) is deduced from code: `sd_status:sees/2` was removed and nothing replaces it for a person who is not a participant.
- **Branch access (`sd_dataaccess`)** and the form creator (`owner`) of a person's own form were read from code and not run (the matrix has no branch-rules person). The form-owner column of the matrix is the `seeAllUsers` grant; a user-made form's `owner` goes through the same function (`sd_config:sees_all_def/2`).
- **Anything in a real browser or on a phone.** The web statements about `useWorkspaceSubmissions`, `formToCard` and `RecordCard` are from reading the source, not from a browser run.
- **Several nodes** (`CONNECTUM_CLUSTER`): events across nodes use `chat_cluster:remote_online/2` keyed by organisation too; not run.
- **Concurrency of the indexes**: `with_me/3` removes entries that are no longer valid while reading; two simultaneous reads were not tested.
- **The probe against a real server**: it was run only against the scratch backend. On `dev.connectum.app` the email sign-in sends a real code to the person; do not run it for a person who has not agreed.

## Re-running everything

Needs `erl` (OTP 27), `redis-server`, Node 22 or newer. From `connectum/connectum-backend`: `rebar3 compile` (or `./tools/rebar3 compile`); start a scratch Redis and a backend of your own, never a shared one:

```
redis-server --port 6411 --save "" --appendonly no --bind 127.0.0.1 --databases 16 &
REDIS_HOST=127.0.0.1 REDIS_PORT=6411 REDIS_DB=5 CONNECTUM_DEV_OTP=1 CONNECTUM_OTP_COOLDOWN_SEC=0 CONNECTUM_FORMLOGIC_URL=off \
  CONNECTUM_MODE=strict CONNECTUM_ADMIN_UNLOCK=1 CHAT_RATE_LIMIT_MAX=5000 \
  erl -noshell -pa _build/default/lib/connectum_backend/ebin -pa _build/default/lib/eredis/ebin -s chat_app start 8271 &
node ../tools/records-visibility-scenario.mjs http://localhost:8271 /tmp/records-scenario.json     # the matrix and 33 checks; about four minutes
node ../tools/records-probe.mjs --base http://localhost:8271 --email <an email the scenario made> --dev --all-orgs --shape
```
The scenario refuses a base URL that is not `localhost`/`127.0.0.1`. Start a fresh backend (and `FLUSHDB`) for a second run: organisation set-up is rate limited per address. Tests of the rules themselves are in `connectum-backend/test/connectum_actions_test.mjs`, `connectum_autosend_test.mjs`, `connectum_team_records_test.mjs`, `connectum_recthread_test.mjs`, `connectum_formfwd_test.mjs`.
