# Smart View: implementation spec and plan (revision 2; phase 1 built 16 Nov 2026)

Revision 1 written 16 Nov 2026 (stage 1). **Revision 2: 16 Nov 2026 (stage 1b)**, after the BE published revision 2 of its document. Goal (owner): a complete clone of the web's Smart View (same behaviour, data and wording) with a very clean phone UI in our design system, reached from `#` commands.

**Source of truth:** `reference/MOBILE_SMART_VIEW.md` (BE revision 2, copied by `tool/be_sync/sync_be_docs.sh` from `origin/dev` **`a5f28fca91`**; the document describes `origin/dev` `6dfeaedc` and was verified against a backend built from that commit). Cited as `[doc §n]` with the document's section numbers. Real captures: `test/fixtures/smart_view/real/` (107, `index.json` lists them; cited by number, e.g. `019-`); the BE's engine vectors: `test/fixtures/smart_view/engine/vectors.json` (also in `reference/smart-view/`). `incoming/be-answers/MOBILE_SMART_VIEW.md` is revision 1 and is superseded. Our code is cited `[our code path:line]`. Anything not in a source is `[ASSUMPTION]`. The web repo was not read by us (no `[web-local]` tags).
Also read: `mobile-handoff/records-and-tickets.md` (corrected in this revision), `mobile-handoff/commands.md`, `reference/MOBILE_RECORDS_FULL.md`, `reference/RECORD_ACTIONS.md`, `reference/hash/HASH_COMMANDS_FOR_MOBILE.md`.
`mobile-handoff/smart-view-plan.md` (11 Nov, an older plan from the unmerged `feat/smartview-fix` branch and a PDF) stays **superseded**.

**What is verified now, and what is not.** The API surface (107 captures: commands, refusals, events, the rate limit) and the web's pure engine functions (vectors) were **run** by the BE on 16 Nov 2026 against a backend built from dev, on a scratch organisation. **Not captured:** a real `api.run` with rows; a manager's `records.mine {as:"team"}` with data; a share to a **group**. **The web screens were never rendered by the BE**: every UI string and the phone-card layout in [doc §3] come from code and CSS, not from seeing them. This spec marks them **`[from code/CSS, not rendered]`** where it relies on them. The revision-1 caveat "every example is reconstructed" is gone; the five stage-1 fixtures stay as reconstructed history, each with a `note`.

## 0. Phase 1 built (16 Nov 2026): what, where, decisions, limits

**What.** `#view [name]` (aliases `#smartview`, `#list`) opens a structure's records as cards: pick a structure (sheet with Find, or the name), `submissions.list` pages for the person's own records plus `records.mine` with and involved merged by id, record cards, paging, pull to refresh, tap to open the record, Add, live refresh, DEMO_MODE. **Not built (later phases):** search, sort, filters, groups, columns, saved views, KPI, charts, sharing, CSV, API sources, customise/publish, Inbox kinds, edit and delete from the list. Entry details: `mobile-handoff/commands.md` (`#view`).

**Where.**
- Entry: `lib/data/commands/command_handlers.dart` (`CommandMode.smartView`), `command_menu.dart` (`localEntries`), `lib/data/repositories/command_repository.dart` (`HashKind.smartView`, `sourceSuggester`), `lib/features/conversation/models/command_prompt.dart` (suggestions), `lib/features/commands/command_runner.dart` (`_openSmartView`), `lib/features/smart_view/widgets/smart_view_picker.dart`.
- Data: `lib/data/smart_view/` (`smart_view_commands.dart`: `SvCmd`, `SvEvents`, `SvLimits`; `models/sv_source.dart`, `models/sv_row.dart`; `sv_cell_format.dart`; `sv_card_content.dart`), `lib/data/repositories/smart_view_repository.dart` (one class, plus `SvTable`).
- Screen: `lib/features/smart_view/` (`smart_view_controller.dart`, `smart_view_view.dart`, `smart_view_binding.dart`, `widgets/sv_record_card.dart`); route `AppRoutes.smartView = '/smart-view/:name'` (`smartViewOf(name)`).
- Demo and debug: `lib/core/debug/seed_smart_view.dart`, `lib/features/debug_smart_view/`, route `/debug/smartview`, gallery row `debug/smartview`; `SeedTickets` got `addDemoForm`, `addDemoRecord`, `recordsOf`, `setDemoStatus` (records live there so a tap opens the real record screen). All are on the "Before release" list in CLAUDE.md.
- Tests: `test/smart_view/` (models and cell text against the real captures, repository, command entry, screen, a composer-to-record navigation test, demo server), goldens in `test/smart_view/goldens/`.

**Reading.** One gate for every Smart View command: one at a time, at least 300 ms apart, inside the one shared read gate (`ReadGate`: 20 reads in any 10 s; the server's limit is 30 per 10 s per connection, see CLAUDE.md "Command budget"), `rate_limited` / `busy` wait 1, 2, 3, 4 s and retry, then an error with Retry. `submissions.list {tstruct, limit:500, offset, fetch:true, withDetails:true}`: `offset += 500` while `hasMore`, at most 20 pages, stop on `hasMore:false` or an empty page; each page shows at once. Then `records.mine as=with` and `as=involved`: `limit` 200, `offset += rows received` (`next` is always null), at most 3 pages each, only rows of this structure, rows already held are not replaced (the `submissions.list` copy wins and keeps `canEdit`), a failure leaves the table as it was. `raised` is never read for a structure (if it were, `RecordLimits.mineLimit` makes it 200). Sorted newest first by `ts`. A received row has no `canEdit` (the document gives no rule for it besides "not editable, not deletable"): read-only. Rows are in memory only (CLAUDE.md exception); the organisation switch clears everything and drops reads in flight (`_epoch`, `loadId`). Not found is a calm "Not available" (`AppViewState.locked`), never forbidden.

**Hidden fields.** The source list leaves them out (`fields`); every row is cut to the keys of that list when it is read, so a hidden value is never held, drawn, logged or searched. Logs (`[records] smartview ...`) carry ids and counts only. A test scans the log output.

**Card.** Title = key field, else the first filled field that is not a file, else `<caption> #<id>`; `No. <id>`; `<by name or user> · <date, time>`; the approval word only when it is not `Recorded`; the first three own fields (label, text per [doc §3.8.1] in `SvCell`, dash for blank; the status field, grid sections and the key field are not repeated); for a structure with a status, the shared `RecordCardActions` (status, with whom, progress, action buttons from the card-actions queue: nothing is read for a card by Smart View). Long press: the record's actions from `record.actions` (read when the menu opens) and History. Tap: a structure with a status, or any received record, opens `/tickets/:id`; a plain structure opens `/submissions/:id`.

**Add.** The floating button (only when the list shows cards; the empty state has its own `Add a record`) runs `SubmissionRepository.openStructure` (the `#tstruct-add` open) and the form screen without a chat; on a save it reads page 1 (50 rows, one command) 1.5 s later (the save goes through the outbox) and the live event adds the card too.

**Live.** `submissions_changed`, `submission_approved`, `submission_rejected`, `ticket_assigned` whose `tstruct` is absent or equals this structure. The first event decides the mode and logs `[records] smartview live mode=record|refetch`. `data.record` present and the row held: the row, the card's live state and the status text change in place, no command. `action:"deleted"`: the row is removed. Otherwise (no `record`, or a record we do not hold): events are collected 600 ms (trailing), coalesced by id, one refresh in flight per table, `submission.get {id}` per affected record only; an event with no id reads page 1 (50 rows). A full re-read happens only on reconnect (`onOnline`), `resync`, the app back after 30 s or more, `tstructs_changed` for this structure, pull to refresh and Retry. Changed cards fade in over 150 ms; the scroll position stays.

**Decisions where the document is silent** (all `[ASSUMPTION]`): page size 500 (the read budget is the shared `ReadGate`, 20 per 10 s); the card layout above (the document's phone card is six columns of the web's default order and the BE recommends showing more); status, With and Progress come from the status block, not as label/value lines; no `intl` package (not allowed here), so dates use English month names, numbers `,` and `.`, and the device locale is not applied; a date without a time is local midnight; `submission.get` rows keep the held row's `canEdit`, labels and files (else read-only, no labels); a row from `submission.get` is "received" when `by` is not me; the demo ids start at 1000 so they never meet the sample rows (200 to 269); `api.list` and API sources are not read (structures only); the picker's empty text is `Nothing matches.` and the wrong-name text is `Nothing is called “X” that you can open.` (the document's, shown as a notice with the text kept, not as a picker note).

**Field types with no formatting rule in the document** (shown as safe raw text: strings as saved, numbers trimmed, lists joined with `, `, maps as `a: 1 · b: 2 fields`): a grid-section value (the stored shape of the rows is not in the document; grid fields are left off the card), `signature` and any type the app does not know, `json`. A `file` of a received record has no `files` map: its chip name is `File`.

**What only a real dev run can settle.** That a server without #822 behaves as `refetch`; that `submission.get` of a record I raised carries what the `submissions.list` row does not (`canEdit`, labels, files: the held copy is kept); that the card-actions queue does not read `record.actions` again for every visible card after each event (the record flow marks cards stale on every `submissions_changed`; its own 8-per-10-s budget applies, Smart View adds none); the real cost of 20 pages at 6 commands per 10 s (about 35 s for 10,000 records); the look of the cards against the web (the BE did not render the web screens).

## Revision 2: what changed against revision 1
1. **Paging:** `records.mine` `next` is always `null` for `with`, `involved`, `all` (and `team` without reports): continue at `offset += rows received`. Only `raised` and `team` give a real `next`. This agrees with what our code already does; our Q3 is closed.
2. **Server defect:** `records.mine {as:"raised"}` drops records with a small `limit` and says `hasMore:false`. **Fixed on our side** (the only app-code change of this stage): `raised` is always asked with `limit` 200 (`RecordLimits.mineLimit`).
3. **No access = `not_found`** for `submission.get`, `submission.history`, `record.actions` (never `forbidden`).
4. **Received records** (`records.mine`) carry no `canEdit`/`canDelete`, no `byName`, `files`, `labels`; a received record is neither editable nor deletable, only the workflow (`record.actions` -> `send`/`status`). An administrator cannot delete someone else's record either.
5. **Hidden fields are not removed by the server** (only the source list omits them): a data-exposure decision for the BE owner (section 5.3).
6. **Live refresh:** the web re-reads the whole table once per event (up to 27 of the 30 commands per 10 s). The BE recommends a strategy built on `data.record` (section 3.6). `data.record` is on `dev` only since 16 Nov 2026 (#822), in no release: we keep the quiet-refresh fallback.
7. **Saved views overwrite each other silently** between two devices (no `rev`/`stale`): safe client behaviour in section 3.9.
8. **`#view` is not known to the server** (`/cmds` has 22 commands, none is `view`; `/cmdcomplete` answers `none`): the app builds the entry and the suggestions.
9. **No server option for filter, sort, group, aggregate** (one small server search, `records.list`); the BE gives the exact rules and test vectors: owner decision **B1** (section 3.8).
10. `data.record` events, `records.summary`, `POST /api/sd/<command>` (does not exist), `canEdit` only on `submissions.list` rows: sections 3 and 5.

## 1. One-page summary

**What it is.** Smart View turns a structure's records (or an API's rows) into one table that a person can search, filter, sort, group, chart, total, download and save as named views; a row opens the record in the structure's own form (edit or read-only). It adds no permission of its own: rows and actions are the structure's rules, decided by the server. The only new permission is `smartview.configure` (organisation default set-up). [doc §1.1]

**Entry points.**
- `#view [name]`, aliases `#smartview` and `#list`. Argument `name`: type `source`, optional, `rest: true`; `requires:"none"`, `available:true`. **This entry lives only in the web client: the server does not know `#view`** (`/cmds` lists 22 commands, none is `view`; `/cmdcomplete {"input":"#view le"}` answers `kind:"none"`, capture `101-`), so the app builds the entry and the suggestions itself. No name: the Overview pane. A name: exact match on name or caption (case-insensitive), else the first source whose name or caption contains it; no hit: the note `Nothing is called “X” that you can open.` [doc §1.3 E1, §1.3.1]
- Suggestions after `#view `: built by the app from the source list (cached 60 s), never from `/cmdcomplete`; only `canFetch !== false`; `#list` shows structures only; "starts with" ranks before "contains"; the person's own structures before built-in; max 30; one exact match + Enter runs it. [doc §1.3 E2, §1.3.1]
- Other web entries: card Expand (E3), Overview card (E4), Inbox Visualize (E5), file chip "Open as a table" (E6), hyperlink cell (E7), Excel/CSV drop zone (E8). **No deep link, URL or push notification exists (E9).** [doc §1.3]

**Source kinds.** `structure` and `api` are ON; `work`, `approvals`, `reminders` are Inbox-only; `file` is local; `datasource` and `list` are OFF and "must not be built". [doc §1.4]

**Data model.** A source (`ai.enterprise` forms: name, caption, keyField, owner, fromSheet, system, canFetch, canAdd, recordThread, status, fields, sections; hidden fields are left out of `fields`) -> rows (`submissions.list` pages of 500 with `canEdit`, plus `records.mine` with/involved merged by id, which carry no `canEdit`) -> a client-built table -> set-up (`smartview.attrs`: metadata, hyperlinks, kpis, charts) and saved views (`smartview.views`: own + shared). A view is an arrangement (search, filters, sort, groupBy, hidden, order, widths, kpis, charts), never data. [doc §0, §2.2-2.8]

**Commands and events.** `ai.enterprise`, `submissions.list`, `records.mine`, `submission.history`, `submissions.delete`, `tstruct.user.get`/`tstruct.get`, `smartview.attrs`/`.attrs.save`/`.attrs.delete`, `admin.smartview.*`, `smartview.views`/`.views.save`, `smartview.targets`/`.share`/`.shares`/`.unshare`/`.view.unshare`, `smartview.sheet.save`/`.delete`, `api.list`/`api.run`; events `submissions_changed`, `submission_approved`, `submission_rejected`, `ticket_assigned`, `tstructs_changed`, `task_assigned`, `task_updated`, `submission_notice`, and a synthesised `resync` on reconnect. [doc §2.1, §2.11]

**Biggest risks to clone** (revision 2, [doc §7.5]): (1) hidden fields and who sees which values: the server sends the values to every reader (section 5.3, owner and BE-owner decision); (2) all filter/sort/group/aggregate/type-inference logic is client-side and the BE gives exact rules plus vectors (owner decision B1, section 3.8); (3) merging `records.mine` rows into the table (no `canEdit` on received rows); (4) live correctness under 30 commands/10 s (section 3.6); (5) saved views are whole-list replacements and two devices lose each other's views (section 3.9).

**NOT BUILT in the web (verified absent) [doc §7.2, §7.6]:** deep links/URLs/push for Smart View; a "publish to everyone" button (the server command exists); server-side filter/sort/group/aggregate; a "changed since" read; a batch `record.actions`; a batch `submission.get`; `canEdit`/`canDelete` on `records.mine` rows; a `rev`/`stale` error on saved views; Read/Add checkboxes when sharing; overdue rules, formulas, conditional formatting, RTL; an offline cache or banner; Axpert and Connectum data sources as sources (switched off); `POST /api/sd/<command>` for record commands (never existed). **Still UNSURE or not captured:** a real `api.run` with rows; `records.mine {as:"team"}` with data; a share to a group; rendered web screens (every string in section 4 is `[from code/CSS, not rendered]`); which release carries `data.record`; whether the BE owner will fix the defects (all in `mobile-handoff/smart-view-be-questions.md`).

---

## 2. Mapping the web onto our app

Size S = under a day, M = 1-3 days, L = more. "Reuse" = exists and is used unchanged; "extend" = exists, small change; "new" = new file.

**Revision 2 note.** The "doc §" column still points at the BE document (now revision 2). Every layout or string taken from [doc §3] is **`[from code/CSS, not rendered]`**: the BE read the web's code and CSS and did not render the screens. Pictures and wording are therefore ours to confirm against the web by eye (BE follow-up file, last item).

### 2.1 Entry and sources

| Web element | doc § | Our equivalent | Action | Size |
|---|---|---|---|---|
| `#view`/`#smartview`/`#list` handler | 1.3 E1, 1.3.1 | `CommandHandlers._byName` has no `view` => "coming soon" [our code lib/data/commands/command_handlers.dart:46-59]; `CommandMode.screen` opens an app screen without sending [command_handlers.dart:14-15]. **The server never sees the line**; the app builds the entry (`{name:"view", aliases:["smartview","list"], category:"lookup", requires:"none"}`) itself | extend: add a mode that carries the typed name and never sends the line (also build the catalogue entry locally, because `/cmds` has none) | S |
| Arg type `source` | 1.3 E1 | `CommandArg.type` is a free string, default `word` [our code lib/data/models/hash_command.dart:7,27]. `source` exists **only in the web client** (the server's types are `user, group, host, msgid, emoji, url, word, enum, text`) | extend: a local type, treated like `text`+`rest` | S |
| Suggestion menu (built by the app, 60 s cache, max 30, ranking) | 1.3 E2, 1.3.1 | composer arg mode uses `/cmdcomplete` [mobile-handoff/commands.md "Web composer behaviour"]; for `#view le` the server answers `kind:"none"` (`101-`); menu code `lib/data/commands/command_menu.dart` | extend: for `view`/`smartview`/`list` build items from the source list and never call `/cmdcomplete` | M |
| Source list | 2.2, 3.3 | none (`ai.enterprise` is not called anywhere in `lib/`; `openStructure` uses `tstruct.user.open` [our code lib/data/repositories/submission_repository.dart:1358]). **One call** `ai.enterprise {what:"forms"}`; `failed` is a web-client idea (the web's `listSources` joins separate calls), not a server field (`004-`, `005-`) | new: `SmartViewRepository.sources()` | M |
| Left list with groups Work/Your files/Structures/APIs | 3.3 | none | new: one picker screen with grouped `AppListRow`; Work and data-source groups not shown | M |
| Find box in the list | 3.3 | `AppTextField` [our code lib/core/widgets/app_text_field.dart:11] | reuse | S |
| Overview pane (KPI band, card per structure, 7-day sparkline) | 3.5 | none; chart widget exists [lib/core/widgets/app_chart/app_chart.dart:17] | new, deferred to the last phase (nice to have) | L |
| Compact card in the chat + Expand | 1.2, 3.4 | none | **not built**: `#view` opens the full screen directly (chat card is a web-only embedding) [ASSUMPTION] | - |
| Inbox "Visualize" (work/approvals/reminders) | 1.3 E5 | Tasks, Approvals, Inbox exist [our code lib/core/routes/app_routes.dart:22-23] | **skip** (kept as BE Q20) [ASSUMPTION] | - |
| Open Excel/CSV drop zone, Save to my files, Delete file | 1.3 E8, 2.10 | none; no file-parse code in app | deferred, last phase; BE Q18 | L |
| Hyperlink cell | 1.3 E7, 2.7 | none | deferred (phase 8) | M |

### 2.2 The table

| Web element | doc § | Our equivalent | Action | Size |
|---|---|---|---|---|
| Title bar `N row(s) · updated <ago>` | 3.6 | none | new (30 s tick text only) | S |
| Table, header, sortable headers, resize, drag-reorder | 3.6 | none | **not built as a table**: the web itself becomes cards at ≤600 px, which is what a phone is; header sort becomes the sort bar; resize and drag are irrelevant on cards [doc §3.6 "Phone", §3.10] | - |
| Record card (first 6 columns, label/value, 168 px) | 3.6 | closest: `TicketTile` [lib/features/tickets/widgets/ticket_tile.dart], `AppKeyValueRow` [lib/core/widgets/app_key_value_row.dart], `AppStatusPill` [lib/core/widgets/app_status_pill.dart:8], `AppProgressBar` [lib/core/widgets/app_progress_bar.dart:9] | new `SvRecordCard` built from those | M |
| Virtualised list (overscan 24) | 4.5 | `ListView.builder` | reuse (framework) | S |
| Select-all + row checkboxes | 3.6 | none | new: long-press starts selection mode (doc's own touch alternative) [doc §3.10] | M |
| Status pill colours (`statusClass`: final=good, defined=plain, waiting for approval=warn) | 3.7 | `AppStatusPill`, `TicketStatusPill` [lib/features/tickets/widgets/ticket_status_pill.dart]; the tone parser `toneOf` is the web's record-card parser | extend: map `final`/`status` to our pill tones; colours from AppColors only [doc §3.7 last sentence] | S |
| Progress bar `NN%` | 3.6 | `AppProgressBar` | reuse | S |
| File chips + preview | 3.6, 4.8 | `AttachmentRepository`, `attachment_cache.dart` fetch files with the session [mobile-handoff/records-and-tickets.md "Files"] says download `GET /api/sd/files/<id>` is "not built" | deferred (phase 8); sniff-by-bytes needed | M |
| `forum` button (record thread) | 3.6 | `record.thread` exists [our code lib/data/records/record_commands.dart:15] | reuse: button on card when `recordThread` | S |
| History button + panel under a row | 3.6, 2.5 | `TicketHistoryTimeline` [lib/features/tickets/widgets/ticket_history_timeline.dart], `RecordEvent` | reuse: open the record screen's history (`/tickets/:id`) rather than an inline panel; web's `eventWord` words are the web's, ours are existing | S |
| Group rows (count + sum of first measure) | 3.6, 5.1 | none | new, client engine (phase 2) | M |
| Single-record card (Get API / link target) | 3.6 | none | with APIs / links phases | S |
| Empty states `Nothing matches…` / `There is nothing here yet.` | 3.6 | `AppStateView` (`empty`, `noResults`) [lib/core/widgets/app_state_view.dart:9] | reuse | S |
| Loading `Loading <caption>…` | 3.6 | `AppSkeletonScope`, `AppSpinner` | reuse | S |
| Error + Try again | 3.6 | `AppStateView.error` | reuse | S |
| KPI strip | 3.6, 3.7 | stat-card style exists in Tasks/Home [ASSUMPTION: which file reused to be picked in phase 5] | new `SvKpiStrip`, only when the source is set up | M |
| Charts (13 types) | 3.7 | `AppChart` draws bar, column, line, donut only [our code lib/core/widgets/app_chart/app_chart_data.dart:5] | extend: map 13 → 4, fallback note for scatter/funnel | M |

### 2.3 Footer, filters, views, dialogs

| Web element | doc § | Our equivalent | Action | Size |
|---|---|---|---|---|
| Footer bar (tabs, filter, tools) | 3.6.1 | `AppPillBar` for tabs [lib/core/widgets/app_pill_bar.dart:47], `AppActionBar` [app_action_bar.dart:46] | reuse; tools go to a top-right menu + a bottom sort/filter bar | M |
| View tabs: Default, own, shared (group icon), `+` | 3.6.1 | `AppPillBar` with `AppPill` kinds | reuse | S |
| Filter button + chips + panel (`controlFor`: choice, text, number, date presets, yes/no) | 3.6.2 | `AppFilterChips` [app_filter_chips.dart:17], `AppBottomSheet` [app_bottom_sheet.dart:12] | new sheet; engine rules in phase 2 | L |
| Search (footer icon + input) | 3.6.1 | `AppTextField` | reuse | S |
| Sort bar (cards mode: "Sort by", direction button) | 3.6 | none | new, S inside phase 2 | S |
| Options menu (Columns, Group, Save view, Share, Hide KPI, …) | 3.6.1 | `AppPopupMenu` [app_popup_menu.dart:38] or bottom sheet (doc §3.10 says bottom sheet) | reuse `AppBottomSheet` rows | M |
| Select Fields (Columns) / Group By dialogs | 3.6.2 | none | new `AppBottomSheet` with checkbox list; "Keep at least one field." | M |
| Name dialog (Save as new / own / Update) | 3.6.2 | `AppBottomSheet` + `AppTextField` | new | S |
| Remove / Stop sharing / Delete records confirms | 3.6.2 | confirm sheet used by `deleteSubmission` [our code lib/features/submission_detail/submission_detail_controller.dart:53] | reuse pattern | S |
| Share dialog (targets, chips, shared-with list) | 3.6.2, 2.9 | none | new sheet, phase 7 | M |
| Customize View (Cards, Charts editors) | 2.7, 3.6.2 | none | **not built on mobile** (admin/author set-up; "nice to have"); a person's own set-up is only read [doc §3.10] [ASSUMPTION] | L if ever |
| Download menu (Excel/CSV/Sheets/PDF/PPTX/PNG) | 3.6.1 | share sheet exists for other things (not verified) | CSV via OS share sheet in a late phase; PDF/PPTX/PNG not built [doc §3.10 "nice-to-have"] | M |
| Parameters form for APIs | 3.6 | form screen is for structures only | new small sheet, with APIs phase | S |
| Add a record (`+`, empty state) | 2.12, 3.6 | `SubmissionRepository.openStructure` + `/form` [our code submission_repository.dart:1358; app_routes.dart `form`] | reuse (`FormLaunch` with no `convId`) | S |
| Open a record (edit or read-only) | 4.4 | record screen `/tickets/:id` [app_routes.dart:24]; edit flow in the submission detail [mobile-handoff/commands.md "Edit and Delete"] | reuse: tap → record screen; Edit only when `canEdit` and the row is mine | M |
| Delete selected (350 ms apart, ≤200) | 2.12 | `SubmissionRepository.deleteSubmission` (needs connection, never queued) [submission_repository.dart:420] | extend: loop over ticked ids with the web's pacing | M |

---

## 3. API plan

### 3.1 Where things live

- `lib/data/smart_view/smart_view_commands.dart`: `SvCmd`, `SvEvents`, `SvLimits` (constants only), same pattern as `RecordCmd`/`RecordEvents`/`RecordLimits` [our code lib/data/records/record_commands.dart:4,46,59].
- `lib/data/repositories/smart_view_repository.dart`: ONE class `SmartViewRepository extends GetxService` (CLAUDE.md "one repository per domain"), built in `initial_binding.dart` like `TicketRepository` [initial_binding.dart:139].
- `lib/data/smart_view/models/` plain models: `SvSource`, `SvField`, `SvRow`, `SvPage`, `SvAttrs`, `SvView`, `SvShareTarget`.
- `lib/data/smart_view/sv_engine.dart`: static functions only (like `PagedRead` [lib/data/records/paged_read.dart]); exists only from the phase that is unblocked (section 3.8).
- `lib/features/smart_view/`: `smart_view_sources_*` (picker) and `smart_view_*` (source screen), each controller + view + binding [CLAUDE.md "Architecture"].
- DEMO fake: `lib/core/debug/seed_smart_view.dart` (like `SeedTickets` [lib/core/debug/seed_tickets.dart:15]); added to the "Before release" list when built.
- Routes: `AppRoutes.smartView = '/smart-view'` (picker) and `AppRoutes.smartViewSource = '/smart-view/:kind/:name'`; parameters come from the route although no deep link exists (E9), so a future link needs no change [CLAUDE.md "Routing"; ASSUMPTION].

### 3.2 Transport, retries, rate budget

- All commands: `SocketService.sdCall(action, args)`, 12 s default timeout [our code lib/data/socket/socket_service.dart:401]; errors are `SocketCallError(code)` [socket_service.dart:27]. Envelope `{"type":"sd","reqId","ok","data"|"error":{code,message}}` [doc §2.0].
- Timeouts to pass per call (web values): lists/records 30 s, API 60 s, views/attrs/share 15 s, sheet 120 s [doc §2.14 last row]. Our default 12 s is shorter, so every Smart View read passes an explicit `timeout` [ASSUMPTION: the app may keep a shorter cap for mobile networks; owner to confirm].
- `callRetrying`: on `rate_limited` wait `1000 × (attempt+1)` ms and retry, up to 4 retries; any other refusal is the answer [doc §2.0]. Implemented once in the repository.
- Error codes to handle: `invalid`, `bad_request`, `forbidden`, `not_found`, `limit`, `rate_limited` [doc §2.0]; plus our transport codes `timeout`, `disconnected`, `not_connected` [socket_service.dart:34-35]. The server message is shown as written [doc §2.0].
- Budget: 30 commands / 10 s per connection [doc §2.0], shared with chat and the record queue (8 starts/10 s) [mobile-handoff/records-and-tickets.md "Queue"]. Smart View rules: one Smart View command at a time (a single `Future` chain), 450 ms between page reads (≤22 commands/10 s alone, leaving room for chat) [ASSUMPTION; the web only says "one after another"], delete 350 ms apart [doc §2.12], suggestions and sheets read nothing extra.
- `records.summary {ids ≤50}` budget 1500 ids/min and `api.run` 120/60 s are separate limits [doc §2.0].

### 3.3 Commands: request, response, limits, where

| Command | Request | Response (models) | Limits / errors | Lives in | Phase |
|---|---|---|---|---|---|
| `ai.enterprise` | `{what:"forms"}` | `{forms:[SvSource{name,caption,keyField,owner,fromSheet,system,canFetch,canAdd,recordThread,status{field,statuses,final} or null,fields[{name,caption,type,section,rich}],sections[{name,caption,grid}]}]}` [doc §2.2] | hidden fields never listed; re-read on `tstructs_changed`/`resync`; a part failing is named in `failed` (see Q4) | repo `sources()`; cache in memory 60 s | 1 |
| `submissions.list` | `{tstruct, limit:500, offset, fetch:true, withDetails:true}` | `{submissions:[SvRow{id,tstruct,by,byName,ts,status,holder,claimants,completion,values,labels,files,canEdit}], total, offset, limit, hasMore, structures}` (captures `007-`, `008-`; without `withDetails` there is no `canEdit`, `files` or `labels`, `009-`) | limit 1-500, offset 0-100000, out-of-range clamped (`013-`); continue by `hasMore`, never `offset+items`; web cap 20 pages; note "Showing the first N of M rows. Filter to narrow it down." only if `total > read`; a structure the person may not read gives an **empty page** (`091-`), a missing one an error (`014-`) | repo `loadRows(source)` using `PagedRead` | 1 |
| `records.mine` | `{as:"with" or "involved", limit:200, offset}` (3 pages each, only this structure, dedupe by id, never throws) | `{submissions, structures, total, hasMore, next}`; row = `actedBy, actionSeq, assignor, branch, by, editedTs, holder, host, id, participants, scope, ts, tstruct, values` (+`completion`, `hours`); **no `byName`, `canEdit`, `files`, `labels`** (`019-`, `027-`) | `with`/`involved`/`all`: `next` always null, continue at `offset += received` while `hasMore` (`019-`..`022-`); `raised`/`team`: real `next` (`023-`, `025-`); **`raised` is always asked with `limit` 200** (server defect, `023-` vs `024-`); `limit` over 200 clamped (`028-`); `all` for non-admins silently is `with` (`026-`); a received record is neither editable nor deletable (`039-`, `040-`) | repo, merged into rows | 1 |
| `submission.history` | `{id}` | `{events (oldest first), names, files, caption, fields}` [doc §2.5], `033-` | a record the person may not open: **`not_found`** "No such submission." (`034-`, `036-`), never `forbidden` | existing `TicketRepository.history` | 4 |
| `submissions.delete` | `{id}` | `{deleted:true}` [doc §2.12], `096-` | **author or the structure's owner only** (the client rule `deletePlan`, no `canDelete` flag exists); the server re-checks: `forbidden` "You can only delete your own submission, or any record of a structure you created." (`040-`, `095-`); **an administrator cannot delete someone else's record** (`044-`); max 200 per go, 350 ms apart | existing `SubmissionRepository.deleteSubmission` | 4 |
| `tstruct.user.get {name}` then `tstruct.get {name}` | `{name}` | `{tstruct}` with `scope` [doc §2.12] | else "This form is not available to you." | **our app already has `tstruct.user.open` for Add** [commands.md]; hidden-field toggle is the only user (blocked, owner decision B2) | 9 |
| `smartview.attrs` | `{kind,name}` | `{attrs or null, mine, canConfigure, canDefault}` [doc §2.7] | `attrs:null` is not an error; unknown columns skipped; read with the data, failure leaves a plain table | repo `attrs()` | 5 |
| `smartview.attrs.save`/`.delete`, `admin.smartview.*` | see doc | - | **not built on mobile** [ASSUMPTION] | - | - |
| `smartview.views` | `{kind,name}` | `{mine:[SvView], shared:[SvView], canPublish}` [doc §2.8] | Default View id `__default` has no tab | repo `views()` | 3 |
| `smartview.views.save` | `{kind,name,views:[ALL]}` | `{views}` | **replaces the whole list; no `rev`, no `stale` error: two devices overwrite each other silently** (`061-`..`063-`); <=20 + Default ("At most 20 views.", `064-`); name needed (`065-`); name <=40; view <=16,384 B; 30 filters; groupBy <=5; later duplicate wins. Client rule: section 3.9 | repo `saveViews()`: re-read, merge, then save | 3 |
| `smartview.targets` | `{q}` | `{people[{type,id,name,detail}], groups[...]}` (8 people, ≤6 groups) | web debounce 180 ms | repo | 7 |
| `smartview.share` | `{kind,name,to:[{type,id}],view}` | `{views:true,noAccess:[names]}` | 1-50 targets; Default View refused; 20 shared per source; exact error sentences in [doc §2.9] | repo | 7 |
| `smartview.shares` / `.unshare` / `.view.unshare` | see doc §2.9 | `{shares}`, `{unshared:true}`, `{shared}` | `not_found` "No such shared view of yours." | repo | 7 |
| `api.list` / `api.run` | `{name, values, limit:500, refresh?}` | `{columns, rows, total, truncated, refreshedAt, cached, origin, store, cacheSec, expiresAt, via}` [doc §2.6] | cut at 500; `api.run` 120/60 s, `rate_limited` "Too many calls; wait a minute."; 60 s timeout; `put` APIs never offered | repo | 6 |
| `smartview.sheet.*` | see doc §2.10 | `{name, caption, added, failed}` / `{deleted, rows}` (`097-`, `098-`) | 20 MB/50,000 rows read (the web reads the file in the browser); 2,000 rows/60 columns save | - | deferred (phase 9) |
| `records.summary`, `record.actions` | `{ids <=50}` / `{id}` | `records.summary` -> `{id, tstruct, record:{by, claimants, completion, final, holder, status, ts}}` (`037-`, `038-`; on **dev since 16 Nov 2026 (#822)**, in no release); `record.actions` (`030-`) | 1500 ids/min; batch `record.actions` and batch `submission.get` NOT BUILT; `record.actions` for a person who may not read: `not_found` (`032-`); `POST /api/sd/record.actions` does not exist (`045-`) | existing `TicketRepository`/`RecordActionsQueue` [record_actions_queue.dart:13] | 4 |

Test fixtures: **real captures** `test/fixtures/smart_view/real/` (107, by number) and the engine vectors `test/fixtures/smart_view/engine/vectors.json`; the five stage-1 files `test/fixtures/smart_view/{ai_enterprise,submissions_list,records_mine,smartview_attrs,smartview_views}.json` are reconstructed history (each has a `note`) and are superseded by `real/` wherever a real capture exists (section 10).

### 3.4 Paging and the merged table (phase 1)

1. `submissions.list` page loop: `offset += 500` while `hasMore`, <=20 pages, one at a time, 450 ms apart; the first page is shown at once, later pages append in place (the web waits for all pages [doc §4.1]; showing early is a mobile improvement; the BE also suggests a smaller first page, `limit` 200, and continuing while the person scrolls, or at once if they sort/filter/group/search [doc §4.5.1 step 6]) [ASSUMPTION which of the two]).
2. Then `records.mine as=with` and `as=involved`: 3 pages x 200, only this structure, dedupe by `id` (records already there are not replaced), failure leaves the table as it was, rows sorted newest first by `ts`.
3. **Continuation of `records.mine` (resolved by the BE, revision 2):** `with`, `involved`, `all`: `next` is always `null`, continue at `offset + rows received` while `hasMore`; `raised` and `team`: continue at the real `next`. `PagedRead` already does this [lib/data/records/paged_read.dart header; `TicketPage.nextOffset`]. Question Q3 is closed. `raised` is not part of a structure's table (the web reads it only for Tasks & tickets); when asked it is always with `limit` 200.
4. **Rows from `records.mine` have no `canEdit`/`canDelete`.** Rule for a row that came only from `records.mine` (a received record): not editable, not deletable; offer only what `record.actions` enables (`send`, `status`) [doc §2.4.2]. For a row from `submissions.list`: `canEdit` from the server; delete only by the web's client rule (author, or owner of the structure, `deletePlan`), the server re-checks and an administrator cannot delete another person's record. A row present in both sources keeps the `submissions.list` copy (with `canEdit`). A row from `records.mine` has no `labels`/`files`/`byName`: look the username up in what we hold; show file names and option labels only when a `submissions.list` copy exists [doc §2.4].
5. Truncation: if `total > rows read`, show the web's sentence (`Showing the first N of M rows. Filter to narrow it down.`). Filtering is client-side, so on mobile "narrow it down" only works after phase 2 [doc §5.1].
6. Only the newest load may land: a monotonic load id (the web's `runSeq`) plus `PagedRead.isStale` comparing organisation and user [doc §4.1; our code paged_read.dart `isStale`].
7. Access: a source the person may not read gives an empty page, not an error (`091-`); a record the person may not open gives `not_found` on `submission.get`/`submission.history`/`record.actions` (`032-`, `034-`, `035-`) [doc §2.13].

### 3.5 Caching, refresh, scoping, organisation switch

- **Rows: memory only, connection needed** (like the AI tab). Reason: rows can be sensitive, there is no change-since read and no web cache [doc §4.6 row "offline", §7.2]. This departs from "SQLite is the UI's only source" in CLAUDE.md; **owner must approve and CLAUDE.md gets one exception line when built** [ASSUMPTION]. Nothing of Smart View is written to SQLite in phases 1-4.
- Source list: memory, 60 s TTL, re-read on pull to refresh, on `tstructs_changed`, on `resync` [doc §1.3 E2, §2.2].
- Views, set-up: memory per open source; re-read on open and on pull to refresh; whole-list save is read-merge-write [doc §5.1 risk 5].
- API parameter memory: the web keeps last values per person+source in localStorage [doc §3.6]; mobile keeps them in the existing prefs store per org+user+source [ASSUMPTION].
- Scoping: every call runs in the session's organisation; there is no `enterprise` argument [doc §2.13; mobile-handoff/records-and-tickets.md "Organisations"]. Switching organisations is a new session and a new socket, so `SmartViewRepository` clears everything on `SessionStore.current` change, exactly like `TicketRepository._reset` [our code ticket_repository.dart:299]; a read in flight is dropped via `isStale`. Rows are never keyed to anything but (org, user, source).
- `session_replaced`, expired token, sign-out: memory is dropped with the repository's reset [CLAUDE.md "Sessions"; ASSUMPTION that no extra hook is needed].
- Never log row text; log ids and counts only, in the style of `RecordsLog` [our code lib/core/debug/records_log.dart; doc §6.2 "ids and counts only"].
- **Hidden fields:** see section 5.3 (Security: hidden fields). Rows are kept in memory only, never written to SQLite or a log, so a hidden value the server sent never lands anywhere the record screen would not already put it.

### 3.6 Real-time within the rate limit

What the web does [doc §4.5.1]: on `submissions_changed`, `submission_approved`, `submission_rejected`, `ticket_assigned` (whose `tstruct` is absent or equals this structure, case-insensitive) it starts a **quiet full re-read once per event** (no debounce beyond a 150 ms batch, reads in flight not cancelled; only the newest answer lands). A full re-read is up to 20 + 6 + 1 = **27 commands** for a 10,000-record structure (typically 4); the connection allows 30 per 10 s, so a burst hits `rate_limited` at once and the web survives only through its 1-2-3-4 s retry. **We do not copy this.** On reconnect the web synthesises `resync` and re-reads everything; `tstructs_changed` re-reads the source list and the open structure only if its definition changed. There is no timer.

**Our strategy (the BE's recommendation [doc §4.5.1], built from commands that exist; the sequence itself was not run on a device):**
1. **Collect, then act:** gather events for 500-1000 ms (trailing debounce, we use 1 s), coalesce by record id, **at most one refresh in flight**, a new batch while one runs is queued as one more. Smart View stays under **20 of the 30 commands per 10 s** (shared with chat and the record queue); on `rate_limited` wait 1, 2, 3, 4 s and retry.
2. **Patch instead of re-read when the event says it (needs `data.record`):** `submissions_changed` with `data.record = {by, claimants, completion, final, holder, status, ts}` and an `id` we hold: update that row's status value, holder/claimants (With), completion (Progress) and `final` in place, no command. `action:"deleted"` (no `record`): remove the row by id. `action:"updated"` (a field was edited, no values in the event): `submission.get {id}` (one command, exists) and replace the row. A new id (`created`, `Send`): read page 1 only (`submissions.list limit 50 offset 0`) and merge by id. An event **without** `record` means "unknown": do the `submission.get`, never "no status".
3. **Full re-read only** on `resync` (reconnect, or the app back from a long background), on `tstructs_changed` for **this** structure, or on pull to refresh; trailing debounce 1 s.
4. **Screenful without rows:** `records.summary {ids:[<=50]}` for the rows on screen when the app comes to the foreground (budget 1500 ids a minute).
5. **First load:** page 1 shown at once, remaining pages as in 3.4.
6. **`data.record` is on `dev` only (16 Nov 2026, #822), in no release (`main` and tag `v0.1.0` lack it).** Until a release carries it, steps 2 and 4 are **not usable on a server without it**: the fallback is today's behaviour, a quiet refresh (1 s debounce, at least 6 s between refreshes, one in flight, the workspace's numbers) using `submission.get` for a single event when the id is known (an `updated`/`Send`/`Status update` event) and a full re-read only for `resync`/`tstructs_changed`/pull to refresh. The code reads `data.record` only when present (a server that sends it is used, one that does not is the fallback), so no version switch is needed. This also touches our records flow, which says "no event carries status": that stays true for released servers (`mobile-handoff/records-and-tickets.md`).
- Events to listen to: `submissions_changed`, `submission_approved`, `submission_rejected`, `ticket_assigned` (table); `tstructs_changed {action, by, name, scope}` goes to everyone connected (`104-`; source list + definition); reconnect (our app handles `resync` as an event name [our code lib/data/repositories/conversation_repository.dart:670]). Who gets an event: only people who may read the record (after a record is created only its author, `103-`; after a send the author and the new holder, `017-`).
- Quiet refresh: same loader, no spinner, scroll and selection kept, **selection keyed by record `id`, not row index** (the web keys by index and can point at another record after a re-read); a failure keeps what is shown; the new answer replaces rows only if it is still the newest load.
- Pull to refresh = `AppRefresh` [our code lib/core/widgets/app_refresh.dart:12] -> a full re-read (with `refresh:true` only for APIs [doc §2.6, §3.6.1]).
- Reconnect/app resume: quiet refresh of the open table, source list and views (there is no event when views change, so views are re-read on open and on resume) [doc §4.5, §2.8.1].

### 3.7 Offline behaviour

- Smart View is connection-only for rows (see 3.5): opening with no socket and nothing in memory shows `AppStateView.offline` with retry; with rows in memory and the socket gone it keeps them and shows only the existing offline bar [our code lib/core/widgets/app_offline_bar.dart:13; CLAUDE.md "Cached-first screens… offline bar only"]. Quiet refresh failures are silent [doc §4.6]. No queueing of any Smart View write (views save, delete, share) offline: they need a connection and say so [CLAUDE.md "Offline"; ASSUMPTION].
- `#view` itself needs the source list: with no connection and no list in memory the `#` line shows the app's "Needs a connection" notice [mobile-handoff/commands.md "Failures keep the text"].

### 3.8 Server versus client (the honest table), and owner decision B1

The server does NOT filter, sort, group, search, aggregate or compute any Smart View column. **Answer of the BE (revision 2, [doc §5.1.0]): no server option exists and none is planned that they can name.** The one server-side search is `records.list` (a text search over every record value and a `ts` range, `limit` clamped to 100, captures `105-`..`107-`); it is **not** what the web's Smart View search does (that searches the visible columns' text) and must not replace it. [doc §5.1, §5.1.2]

| Concern | Server | Client | Our position |
|---|---|---|---|
| Which structures, which rows, `canEdit`, `canAdd`, labels, file names, hidden-field omission in the source list, status/final/completion | yes | shows | nothing to compute |
| Newest-first order, 500 per page, the API's 500 cut | yes | - | nothing to compute |
| Column order of a structure (key, No., By, Submitted, Status/Approval, status field, With, Progress, rest) and cell text per field type | no | yes: [doc §3.8, §3.8.1] with real output and the vectors `structureCellsDisplayed`, `formatCell`, `structureColumnTypes` | **display rules**, needed in phase 1; the cell-text table now exists (our old Q2 is answered) |
| Search, filter operators, sort, group, group sums, measure rule, aggregate, type inference, chartable columns, defined cards/charts | no | yes: exact rules in [doc §5.1.1], vectors in [doc §5.1.3] / `vectors.json` | **OWNER DECISION B1 (below)** |
| Saved views storage, validation, sharing rules, `noAccess` | yes | sends the whole list | client reads, merges, then saves (3.9) |
| Status pill colour | `final` and status defined by the server | maps to tone | reuse our pill tones |

**Owner decision B1: port the Smart View engine rules to Dart, driven by the BE's vectors as tests.** This is an **exception to the "no engine port" rule, which was written for the form engine** (CLAUDE.md "Forms": no Dart port of the web's form logic); the Smart View engine is a different, much smaller, pure-function set whose exact rules and expected outputs the BE has published. **Not built; waits for the owner.**
- **What it would be:** one pure-function file `lib/data/smart_view/sv_engine.dart` (static functions, no state, no GetX) for: column type inference over the first 200 values with ID-like names, number/date regexes (day-first `d/m/yyyy`), search (case-insensitive `includes` over the visible columns), filter operators per type (`in`, `between` inclusive, inactive conditions ignored, AND across conditions), sort (none -> asc -> desc -> none, blanks last, `localeCompare` numeric on lower-cased text), group (order of appearance, `(empty)`, count and sum of the first measure column), aggregate, chartable-column rule (more than 1 and fewer than rows distinct values, <=40). Tests: every case of `test/fixtures/smart_view/engine/vectors.json` (input rows -> expected output, produced by the web's own functions).
- **Recommendation: yes, approve it, limited to Smart View, with the vectors as the acceptance test.** Reasons: there is no server option, so the alternative is a Smart View with no search, filter, sort, group, KPI or chart, which is not the clone the owner asked for; the rules are small and fully specified; the vectors make a wrong port visible at once; the form-engine reasons for the ban (the form logic changes constantly and is large) do not apply.
- **Risks:** (1) the Dart runtime differs from the web's JavaScript: `localeCompare` numeric collation, `Intl` number/date formatting, locale and time zone (the vectors were produced in time zone Asia/Calcutta, locale en-GB: the tests must pin zone and locale or the date and number cases will differ by machine); (2) the web can change a rule later and the port drifts: the vectors must be regenerated from the BE (`tools/smartview-vectors.mjs`, reference copy only) and the test re-run on every BE sync; (3) 10,000 rows filtered on a phone: run the engine once per change off the UI path, not per scroll (an isolate above a few thousand rows); (4) the precedent: the exception must be written into CLAUDE.md in one line, scoped to Smart View; (5) the BE says `[UNSURE]` which columns a plain source offers as filterable (our old Q10): the port needs the answer, or we assume all non-file/json/list columns. 
- **If the owner declines:** phase 2, 3 (capture of an arrangement), 5 and the group/aggregate parts of 6 do not exist; a Smart View with sorted-as-the-server-sends rows and no tools is what remains (phase 1 and 4 are still worth shipping).

### 3.9 Saved views: the overwrite risk and the safest client behaviour [doc §2.8.1, §4.3]

`smartview.views.save` replaces the person's **whole list** and answers `{views}`. There is **no `rev`, no version check, no per-view command, no `stale` error and no event when views change**. Reproduced by the BE with one person and two stale copies: device 1 saves its list plus `From phone` (`061-`); device 2, which read the same list before, saves its copy plus `From tablet` (`062-`); the server answers success and the phone's view is **gone** (`063-`), with no error or warning. Also refused: 21 views (`invalid` "At most 20 views.", `064-`), a view with no name (`065-`).

Safest client behaviour until the server has a revision (all five come from the BE and are what we build):
1. **Read before write:** call `smartview.views` immediately before every save and merge by `id`: keep every view we did not change, take the server's copy of those we did not touch.
2. **Whole-list replace of what we just merged:** send the merged list, never a list read more than a few seconds ago.
3. **Warn:** if the freshly read list differs from the one the screen holds (another device saved in between), say so in one line ("Your views changed on another device and were merged.") and show the merged result; if a view we edited was changed or removed elsewhere, ask before overwriting it ("Save over the other device's version?") [ASSUMPTION: wording is ours].
4. **Unique ids per device:** a UUID-like id of at most 40 characters from `[A-Za-z0-9_-]` (the web uses `String(Date.now())`).
5. **Redraw from the answer:** the `views` in the reply are the truth. Re-read when the screen opens and when the app comes to the foreground. Save failure toast: `Your views could not be saved. Try again.` (no optimistic state on our side).
The residual race (two saves inside the same few seconds) cannot be closed on the client. **Owner decision B3:** ship saved-view writes with this behaviour (recommended, with the warn line), or ship saved views read-only until the BE adds `rev`/`stale` (safe but a smaller feature). The BE owner decides whether `rev`/`stale` will exist (follow-up file).

## 4. UI proposal (our design system)

Principles: pure-white scaffold, `AppScaffold` packed to the viewport [CLAUDE.md "UI consistency"], tokens only, `AppTextField` for every input, bubble buttons (`AppButton`), `AppStateView` for loading/empty/error, `AppRefresh` for pull to refresh, `AppBottomSheet` for every dialog, `AppPillBar` for view tabs. No banners except the one note that the document asks for. Copy strings are the document's, in English as written there [doc §3.3-3.6; doc §3.8 says there is no translation layer]. **All strings and layouts in section 4 that come from [doc §3] are `[from code/CSS, not rendered]`: the BE did not render the web screens.**

### 4.1 `#view` in the composer

- `#view`, `#smartview`, `#list` open the picker; `#view <name>` opens that source (exact name/caption, else first that contains); no hit: the picker opens with the note `Nothing is called “X” that you can open.` and `X` kept in the Find box. The composer text is cleared, nothing is posted, nothing is sent to the server (the server does not know the command, `101-`) [doc §1.3 E1, §1.3.1; our code command_handlers.dart:14-15 for "screen" mode].
- Menu items after `#view `: `label` caption, `value` name, `hint` "your structure" / "built-in structure" / "api", sub "N fields" (structures); ≤30; ranking and "Enter runs it if exactly one and it equals the typed text" [doc §1.3 E2].
- The `view` entry in the `#` command list is available (`requires:"none"`) [doc §1.3 E1].

### 4.2 Source picker (`/smart-view`)

```
┌──────────────────────────────────┐
│ ←  Smart view                    │
│    Your structures and data as…  │  (the doc's subtitle; AppText caption)
│ [ 🔍 Find                       ]│
│  (note if any: Nothing is called │
│   “X” that you can open.)        │
│ YOUR FILES   (only when present) │
│ STRUCTURES                    12 │
│  ▢ Leave Request     12 fields  ›│
│  ▢ Purchase Order     9 fields  ›│
│ APIs                           0 │
│  None set up yet.                │
└──────────────────────────────────┘
```
- Groups and order: Structures (not-system first, then caption A→Z) [doc §2.2], Your files, APIs; small-caps title and count; empty groups hidden except APIs shows `0` and **"None set up yet."** [doc §3.3]. The "Work", "Data sources" and "Connectum data sources" groups are not shown (Work is Inbox-only; the other two are OFF) [doc §1.4].
- Row = `AppListRow` with caption and hint `N fields`; `Nothing matches.` for a Find miss; `Nothing else you can open as a table yet.` for zero sources; compact variant's "There is nothing you can open as a table yet." + Try again is the `empty` `AppStateView` [doc §3.3-3.4].
- States: loading `Looking for what you can open…`; error from the server message + Try again; a partial-failure notice (`<names> could not be read just now.`) is **not needed**: `failed` is a web-client idea, our one `ai.enterprise` call succeeds or errors (error + Try again) [doc §2.2, §3.4; `004-`]; offline = `AppStateView.offline`; no permission: nothing (a source the person may not open is simply not listed) [doc §2.13]; live: list re-read on `tstructs_changed`/`resync`; an open source is re-read only if its definition changed, and a removed source returns the person to the picker with the "Nothing is called…" note [doc §2.2].
- Gestures: tap a row opens; pull to refresh. Accessibility: each row is one `Semantics` button "<caption>, <hint>"; heading semantics on group titles. 200 % text: hint wraps under the caption; no fixed row height [ASSUMPTION].

### 4.3 Source screen (`/smart-view/structure/<name>`)

```
┌──────────────────────────────────┐
│ ←  Leave Request              ⋮  │  ⋮ = options sheet
│    1,234 rows · updated 2 min ago│
│ [Default View][Open by status][+]│  AppPillBar (phase 3)
│ [ 🔍 Search leave request ] [⛃ 2]│  search + filter button (phase 2)
│ Sort: as it comes            ↓   │  sort bar (phase 2)
│ ┌──────────────────────────────┐ │
│ │ ☐  No. 41        ● Approved  │ │
│ │ Fever                        │ │  key field / first text
│ │ BY            SUBMITTED      │ │
│ │ Ann Rao       12 Nov 2026    │ │
│ │ WITH          PROGRESS       │ │
│ │ Bob           ▓▓▓░░ 40%      │ │
│ └──────────────────────────────┘ │
│ … (virtualised)                  │
│ Showing the first N of M rows…   │  only when total > read
└──────────────────────────────────┘
```
- Title bar: caption; sub-line `N row(s) · updated <ago>` (`1 row`; `<45 s` "just now", `<1 h` "N min ago", else "N h ago"; a 30 s tick re-renders the text only) [doc §3.6].
- Card content: the first six columns of the person's layout (the Columns picker chooses and orders them), as two-column label/value; a `No.` that is a button opens the record; a blank value is a dash `–` with semantics "empty"; text over 24 characters is shown in full on tap (no tooltips on touch) [doc §3.6, §3.10, §4.8].
- Column order and cell text follow [doc §3.8] (key field first, then No., By, Submitted, Status — labelled **Approval** when the structure has its own status — then status field, With, Progress, rest). Numbers use the device locale with ≤2 decimals, values written with symbols stay as written; dates `12 Nov 2026` in the device zone, time added only if present; booleans `Yes`/`No`; rich text as words only, never as markup; grid sections one column [doc §3.8]. Approval words: `Recorded`, `Waiting for approval`, `Declined`, `Approved` [doc §3.7].
- Status pill: final → good tone, defined status → plain, waiting for approval → warn [doc §3.7]; progress bar `NN%` (rounded, clamped 0-100) [doc §3.6, §2.5].
- Tap a card: open the record. `canEdit` → the existing edit flow; otherwise read-only; manager's/"team" rows read-only [doc §4.4, §2.4]. Long-press starts selection (phase 4) [doc §3.10].
- Empty states: filters hide everything → `Nothing matches. Try fewer conditions.` + link `Clear search and filters`; really empty → `There is nothing here yet.` + `Add a record` (primary) when `canAdd` [doc §3.6]. Loading `Loading <caption>…`; error message or `It could not be loaded.` + Try again [doc §3.6, §4.6].
- Live-updated: rows change in place, no spinner, scroll kept [doc §4.4]. Offline: rows stay with the offline bar.
- No KPI strip and no charts unless the source is set up [doc §2.7]; the menu then says `No KPI` / `No charts` (greyed) [doc §3.6.1].
- Accessibility: one `Semantics` container per card ("Leave Request record 41, Approved, by Ann Rao, 40 percent"); the checkbox has its own label; pills have text, never colour only; the label/value grid becomes a single column when text scale is above about 1.3 [ASSUMPTION]; min font 11 labels / 12 text [CLAUDE.md].

### 4.4 Options sheet and the other sheets

Options (bottom sheet, rows with icon + label, conditional ones in the web's order [doc §3.6.1]): Columns · Reset column layout (only if changed) · Group / Group (n) · Save view (on Default View) / Update current view (on a tab, hidden on a shared one) · Save as new view / Save as my own view (shared) · Remove view (own tab) · Share (structures, APIs) · Delete file ("Your files") · Stop sharing this view · Hide KPI / Show KPI / No KPI · Hide charts / Show charts / No charts · Parameters (APIs) · Customize (not built on mobile; row omitted) [ASSUMPTION].
- Columns / Group sheets: searchable checkbox list (caption + name), Select all, Reset, Apply; "Keep at least one field."; the "Show hidden fields" switch with hint `Fields the form keeps off its screen. Off unless you turn it on.` is **not built until owner decision B2** (section 5.3) [doc §3.6.2, §5.4].
- Filters sheet: one line per filterable column (only columns with `filter:true` in the set-up, or all columns for a plain source [still open with the BE, question 10 of the follow-up file; we assume all columns whose type is not file/json/list]); controls per type (choice multi-select "Any"; text condition `Starts with / Contains / Is` + input ≤200; number From/To; date period `Custom, Today, Yesterday, This week, Last 7 days, This month, Last month, This year` + From/To; yes/no Any/Yes/No); footer `Clear` / `Apply`; closing without Apply discards [doc §3.6.2]. Chips under the search bar: `Customer: ACME, BETA` (first two then `+N`), `Net: from 500`, `Status is Open`; each removable ("Remove the filter …") [doc §3.6.2].
- Name sheet: one `AppTextField` (max 40), Cancel/Save; errors `Give the view a name.` / `That name is taken by the Default View. Choose another.`; toasts `View "X" saved`, `Default View saved`, `View updated`, `View "X" removed` [doc §3.6.2, §2.8].
- Confirm sheets: `Remove the view "X"?` / "Its filters, grouping and columns are forgotten. The data is not touched." / **Remove view**; `Delete this record?` / `Delete N records?` / "This record of <caption> will be deleted for good. This cannot be undone." + " N ticked record(s) is/are not yours to delete and will stay." / **Delete**; result toasts `Record deleted`, `N records deleted`, `N deleted, M could not be deleted: <first reason>` [doc §3.6.2].
- Share sheet (phase 7): title `Share`, subtitle the caption, label `Share with`, input `Type a name or a group` then `Add more`, chips, `Nobody matches “q”.`, hint "They see this view as a tab. What they can open, add or change is decided by their own access to this <structure|API>.", list `Shared with` with `Stop sharing with X` and `Cannot open this <noun>`, buttons `Close`/`Share` (`Sharing…`); toasts and errors as [doc §3.6.2, §2.9]. It shares the lit view as captured now; the Default View cannot be shared [doc §2.9].
- API parameters sheet: caption, text "<description or 'Fill these in to run it.'>" (+ " Fill in what to filter by, or leave a box empty to see everything it returns." for APIs), one `AppTextField` per parameter, primary `Show the data` [doc §3.6].

### 4.5 Set-up (KPI cards, charts) — phase 5

- Shown only if `smartview.attrs` returned a set-up and the view's `kpis`/`charts` are true; cards follow search and filters [doc §2.7, §6.3 item 20]. KPI: icon, label, value, tone cycling brand → green → waiting; decimals unless `count` [doc §3.7]. Charts: horizontal scroll row of `AppChart`, tap to enlarge in a sheet; type map `bar`/`stacked-bar` → bar; `column`/`stacked-column`/`stacked-percentage-column`/`stacked-group-column` → column; `line`/`area` → line; `pie`/`donut`/`semi-donut` → donut; `scatter-plot` and `funnel` have no drawing: show a one-line "This chart can't be shown on the phone yet." in place [ASSUMPTION: wording is ours]. Max 40 groups, date columns in date order else biggest first, subtitle `SUM Net by Channel` [doc §3.7]. Colours from our tokens, never the web's `--chart-*` [doc §3.7 last paragraph].

---

## 5. Permissions and visibility

### 5.1 Matrix (from [doc §4.7]; nothing added)

| Operation | Owner of the view | Viewer of a shared view | `smartview.configure` holder | Form owner | Admin | No access |
|---|---|---|---|---|---|---|
| See the source and rows | by the structure's rules | same | same | yes | yes | not listed, no rows |
| Change search/filter/sort/group/columns temporarily | yes | yes | yes | yes | yes | - |
| Save/update/remove own view (≤20 + Default) | yes | n/a (own copy) | yes | yes | yes | - |
| Edit a shared view | no (share again) | no ("Save as my own view") | server-side publish only | - | - | - |
| Share a view (≤50 targets) | yes, if they can open the source | - | yes | yes | yes | `forbidden` "You can only share what you can open yourself." |
| Stop sharing | yes (own) | no | - | - | - | - |
| Customize own look | yes | yes | yes | yes | yes | - (not built on mobile) |
| Set organisation default look | no | no | yes | no | yes | - (not built on mobile) |
| Publish a view to everybody | no | no | yes (no web UI) | no | yes | - (not built) |
| Open a record to edit | when `canEdit` | per record | same | per rules | per rules | - |
| Open a record read-only | any record shown | same | same | same | same | - |
| Delete a record | author | - | - | owner of the structure | **cannot** delete another person's record (`044-`); a received record cannot be deleted by its holder (`040-`) | - |
| Add a record | needs `canAdd` | same | same | same | same | - |
| Show hidden fields | any person who can open it (dev #810) | same | same | same | same | - (not built until owner decision B2, section 5.3) |
| Delete/save own spreadsheet | yes | no | - | - | - | - |

A manager's direct-report records are read-only and never deletable [doc §4.7 note]. The client never filters by permission: it shows what the server returns [doc §2.0]. An administrator cannot delete someone else's record (`044-`, verified).

### 5.2 How errors are shown

| Situation | Code | What the person sees |
|---|---|---|
| Source gone / not openable | none (absent from `ai.enterprise`) | back in the picker with `Nothing is called “X” that you can open.` [doc §2.2] |
| Record not readable (history/get/actions) | `not_found` always, never `forbidden` (`032-`, `034-`, `035-`) | our record screen's existing handling; toast `This form is not available to you.` when the definition is unavailable [doc §4.6; our code ticket_detail_controller.dart] |
| `smartview.attrs` of unknown source | none (`attrs:null`) | plain table [doc §2.13] |
| Shared view for a non-opener | none (empty `shared`) | nothing [doc §2.9] |
| `rate_limited` | `rate_limited` | silent retry 1,2,3,4 s; after that the server text [doc §2.0] |
| First load fails | any | `error_outline` state: message or `It could not be loaded.` + Try again [doc §4.6] |
| Quiet refresh fails | any | nothing [doc §4.6] |
| Views read fails | any | toast `Your saved views could not be read just now.` [doc §4.6] |
| Views save fails | any | toast `Your views could not be saved. Try again.` (web keeps the optimistic state; we re-read and merge instead, section 3.9) [doc §4.6] |
| Delete refused | `invalid`/others | counted: `N deleted, M could not be deleted: <first reason>` [doc §3.6.2] |
| Share `noAccess` | none | toast `Shared with <name> or <N people and groups>` + ` <name> cannot open this <noun>, so they will not see it.` [doc §3.6.2] |
| Timeout / not connected | `timeout`, `not_connected` | Try again; offline state if nothing is held [our code socket_service.dart:34-35] |

---

### 5.3 Security: hidden fields

**Facts (verified by the BE, [doc §5.4], `004-`, `005-`, `007-`, `009-`, `012-`, `046-`):** the server removes a hidden field from exactly one thing, the source list (`ai.enterprise {what:"forms"}`, the field and the four a status keeps: `<f>_comments`, `_completion`, `_files`, `_hours`). It **sends** the hidden field's **value** in `submissions.list` rows (and, by the code, in `records.mine` and `records.list` rows, not checked with a hidden field in the run) to every person who may read the record, its **caption** in `structures.<form>.fields`, and its **definition with its `default`** in `tstruct.user.get` to any colleague who can open the form. The web only decides not to draw it; "Show hidden fields" in Columns reads the same `values`.

**Rules for the mobile app (ours, not the BE's):**
1. **Mobile hides the same fields the web hides.** Smart View columns come only from the source list's `fields`; a key in `values` that is not in that list is never drawn, never searched, never offered in Columns, Filters, Group or charts. The same holds for any other screen that draws record values (record screen, cards, history): a field marked `hidden` is not drawn. [Check, not done here: whether our record screen and form cards already skip `hidden` fields; the entry form does, `form_controller.dart:202,269`.]
2. **No logging and no extra caching:** hidden values are never logged (`RecordsLog` logs ids and counts only), never written to SQLite or any file by Smart View (rows are memory only, 3.5), never put in a notification, a share sheet or a CSV; nothing beyond what the record view already keeps.
3. **We never call hidden fields secret** in any text.
4. **"Show hidden fields" is not built** (phase 9, last, behind a switch) until the owner decides B2.
5. **Whether the server should send hidden values at all is a decision for the BE owner** (keep and document "hidden = not shown, not secret"; strip hidden values for people other than owner/administrators, a breaking change; or make "Show hidden fields" the creator's only again). It is in the BE follow-up file. A *restricted* structure is the real access control: absent from `ai.enterprise` (`086-`), an empty `submissions.list` (`091-`), `attrs:null` (`092-`), no shared views (`088-`).


## 6. Phases (revision 2)

Common acceptance for every phase: `dart analyze` clean on changed files; every screen has loading/empty/error/offline through `AppStateView`; no `Get.find` outside bindings; strings from the document; no hardcoded colours or sizes; DEMO_MODE works offline (section 7). Common test plan: fakes only (`test/support/fake_socket.dart`), bounded pumps (`pump(Duration)`, never `pumpAndSettle` on a screen with a ticker), goldens for the card and each sheet in `test/goldens/`, integration tests start with `DevGuard.assertDevOnly(baseUrl)` and follow `test/README.md` [CLAUDE.md "Dev environment"]; the owner decides when tests are run. The BE's seed, probe and capture scripts are reference copies and are never run by us.

Status words: **UNBLOCKED** = can be built now (real shapes known); **WAITS FOR BE** = needs something only the BE can give; **WAITS FOR OWNER** = needs a decision in 6.1.

| Phase | Scope | Size | Status | What it waits for / notes |
|---|---|---|---|---|
| **1: `#view` -> a structure's records (read-only, no engine)** | local `#view` entry and suggestions; picker with Find; source screen with cards, key-first column order, cell text per [doc §3.8.1], status pill/progress, 500-row paging (<=20 pages), `records.mine` with/involved merge (3 pages x 200), truncation sentence, tap -> record screen, `Add a record` when `canAdd`, pull to refresh, quiet live refresh (1 s debounce, 6 s gap, `submission.get` for one event), reconnect re-read, org-switch reset, `rate_limited` retry, states, DEMO | M | **UNBLOCKED** | Old Q2 (cell text) and Q3 (`next`) are answered. Memory-only rows need the owner's one-line CLAUDE.md exception (6.1 item B4). UI strings `[from code/CSS, not rendered]` |
| **2: client engine: search, sort, filters, group, columns** | `SvEngine` pure functions, vectors as tests, search bar, sort bar, Columns and Group sheets, filter sheet + chips | L | **WAITS FOR OWNER (B1)** | The BE says no server option exists and gave exact rules and vectors. Needs the filterable-columns answer or our assumption (our old Q10) |
| **3: saved views** | `smartview.views` read, Default View applied once, tabs, save/update/save-as/remove with read-merge-warn (3.9), 20-view and 16 KB errors, "Save as my own view" | M | **WAITS FOR OWNER (B1 for capturing filters/sort/group; B3 for write behaviour)** | Real shapes known (`058-`..`066-`). BE `rev`/`stale` would remove the race but is not required |
| **4: record operations** | multi-select (long-press), delete with the web's confirm text and pacing (client rule `deletePlan`), record thread button, history via the record screen, `canEdit` edit path (submissions.list rows only), single-row refresh by `submission.get` | M | **UNBLOCKED** (without the patch path) | Row patch from `data.record`: **WAITS FOR BE** (a release carrying #822); a `canEdit`/`canDelete` flag on `records.mine` rows would replace the client rule (BE follow-up). Admin cannot delete (verified) |
| **5: set-up (KPI cards, charts)** | `smartview.attrs` read with the data; KPI strip; `AppChart` with the 13->4 map; "No KPI/No charts" rows | M | **WAITS FOR OWNER (B1)** | Cards and charts follow filters and aggregate; shapes are real (`049-`, `051-`, `056-`). Chart look `[from code/CSS, not rendered]` |
| **6: API sources** | `api.list`/`api.run`, parameters sheet, 500-row cut note, `cacheSec`, refresh icon, single-record card | M | **WAITS FOR BE** | No real `api.run` with rows was captured (`093-`, `094-` only); also needs B1 |
| **7: share views** | `smartview.targets/share/shares/unshare/view.unshare`, share sheet, `noAccess` wording | M | **UNBLOCKED** (after phase 3) | Real captures `067-`..`083-`, `087-`..`090-`; a share to a **group** was not captured (BE follow-up) |
| **8: files and links** | file chips + preview, hyperlink cells | M | **WAITS FOR BE** | File fetch route, bearer use and content type (our old Q17) is still open |
| **9: Overview, downloads, hidden fields, spreadsheets** | Overview band + cards + sparkline; CSV via OS share; "Show hidden fields"; Excel/CSV open and save | L | **WAITS FOR OWNER (B2 for hidden fields)**; Overview **WAITS FOR BE** (not rendered, totals wording) | `smartview.sheet.save/delete` captured (`097-`, `098-`); the web reads `.xlsx` in the browser, a phone would need its own reader |

Order of value: 1 -> 4 -> (B1) 2 -> 3 -> 5 -> 7 -> 6 -> 8 -> 9. Phase 1 is shippable alone and is reached from the `#` command.

### 6.1 Owner decisions needed

| # | Decision | Recommendation |
|---|---|---|
| **B1** | Port the Smart View engine rules to Dart, driven by the BE's vectors as tests, as an exception to the no-engine-port rule (written for the form engine) (3.8) | **Yes**, limited to Smart View, vectors as the acceptance test, pinned zone/locale in tests, one CLAUDE.md line. Risks listed in 3.8 |
| **B2** | Hidden fields (5.3): confirm that mobile hides what the web hides and builds "Show hidden fields" last or never; and who asks the BE owner whether the server should strip hidden values | Confirm rules 1-4; send the BE question (follow-up file) |
| **B3** | Saved-view writes before the BE has `rev`/`stale` (3.9): ship with read-before-write + merge + warn, or read-only | Ship with the safe behaviour and the warn line |
| **B4** | Rows in memory only, connection needed (3.5), a departure from "SQLite is the UI's only source" in CLAUDE.md (carried over from revision 1) | Approve and add one exception line when phase 1 is built |
| **B5** | Is it acceptable that the live-refresh patch path (`data.record`) waits for a release while phase 1 ships with the quiet-refresh fallback (3.6)? | Yes |

## 7. DEMO_MODE fixtures and tests

**Fake server** `lib/core/debug/seed_smart_view.dart`, active only in demo/debug like `SeedTickets` [our code seed_tickets.dart:15; initial_binding.dart:242], answering by `(cmd, args)`:

| Need | Fixture / behaviour |
|---|---|
| `ai.enterprise` | 4 structures: one with a status + `recordThread`, one without status, one `system:true`, one `canFetch:false` (absent from lists), one `canAdd:false`; field types text, number, date, toggle, list, people, file |
| `submissions.list` | one structure with 1,234 generated rows (paged 500, `hasMore`, `total`), mixed approval states, `canEdit` on mine only, `labels`, `files`; a second with 3 rows; a third empty |
| `records.mine` | `with` and `involved` pages (with `next:null`, short page + `hasMore:true`) containing rows not in `submissions.list` and some duplicates; rows without `canEdit`/`labels`/`files`/`byName`; `raised` copies the server defect (a small limit drops records and says `hasMore:false`, already in `SeedTickets._mine`) |
| `smartview.attrs` | null for most; one structure with 2 KPIs + 2 charts incl. a `funnel` |
| `smartview.views` / `.save` | Default View, 2 own, 1 shared; save replaces the whole list; 21st refused with "At most 20 views."; duplicate-name later-wins |
| `smartview.targets/share` | 5 people, 2 groups, one person who cannot open the source (`noAccess`) |
| `submissions.delete` | accepts own, refuses one "waiting for approval" with a server-style message |
| Events | after 10 s `submissions_changed` for a record (with and without `record`), `ticket_assigned`, `tstructs_changed` renaming a caption, then a removal of the open source; reconnect `resync` |
| Faults | `nextError` and `rate_limited` injection (retry 1,2,3,4 s), timeout, `ai.enterprise` error, two-device views overwrite (a second `smartview.views.save` from a stale copy drops a view), an administrator refused on delete (`forbidden`) |
| Time | injectable clock for the "updated N min ago" text |

**Unit tests** (fakes): models parse each file in `test/fixtures/smart_view/`; command request shapes; paging by `hasMore` with short pages; merge/dedupe by id with `canEdit` only from the first source; `rate_limited` retry schedule; stale-load guard on org switch; suggestion ranking (starts-with before contains, own before built-in, ≤30, exact+Enter); `findSource`; list-name notes. **Widget/golden tests**: source card (status pill, progress, dash for blank, text scale 2.0), picker (empty, partial failure), states, options sheet. **Integration (dev, `DevGuard`)**: only after A0 and a seeded organisation (`tools/smartview-seed.mjs` is the BE's, run by the owner only, never by Claude) [doc §6.1; mobile-handoff/records-and-tickets.md "Probe"].

---

## 8. BE question list (our 25) and 9. Discrepancies (our 15): status after revision 2

The full text, status and what we assume meanwhile is in **`mobile-handoff/smart-view-be-questions.md`** (written to be sent to the BE as it is). Summary:

| Our Q | Topic | Status |
|---|---|---|
| 1 | server-side computation | ANSWERED (none; vectors given) -> owner decision B1 |
| 2 | cell text per field type | ANSWERED ([doc §3.8.1], vectors) |
| 3 | `records.mine` continuation | ANSWERED ([doc §2.4]) |
| 4 | `ai.enterprise` `failed` | ANSWERED (a web-client idea) |
| 5 | refusal code | ANSWERED (`not_found`) |
| 6 | event summary | ANSWERED (`data.record` on dev only) |
| 7 | `tstructs_changed` | ANSWERED (to everyone connected) |
| 8 | `source` type / catalogue | ANSWERED (web client only) |
| 9 | A0 capture | PARTLY (107 captures; three gaps) |
| 10 | filterable columns of a plain source | STILL OPEN |
| 11 | single-row refresh | PARTLY (`submission.get` exists; its shape vs the row shape) |
| 12 | page cap on mobile | PARTLY (BE suggests page 1 of 200 first) |
| 13 | overdue/due dates | ANSWERED (none) |
| 14 | batch `record.actions` | ANSWERED (not built) |
| 15 | views conflict | ANSWERED (none; safe behaviour) |
| 16 | admin delete | ANSWERED (cannot) |
| 17 | file fetch | STILL OPEN |
| 18 | spreadsheet open/save | PARTLY |
| 19 | API sources | STILL OPEN (no `api.run` capture) |
| 20 | Inbox-only kinds | OURS (ignore them; no BE input needed) |
| 21 | Overview totals wording | STILL OPEN (not rendered) |
| 22 | `smartview.configure` | PARTLY |
| 23 | hidden fields | ANSWERED -> owner/BE-owner decision |
| 24 | deep link / push | ANSWERED (none) |
| 25 | time zone / `ts` | ANSWERED (device zone) |

Discrepancies 1-15: 1-7, 9, 12, 13 answered by revision 2; 8, 10, 15 partly; 11 is about our own older plan (superseded); 14 still open. Per-item status in the follow-up file.

## 10. Test fixtures

- `test/fixtures/smart_view/real/`: the BE's 107 real captures (and `index.json`), copied unchanged from `docs/examples/smartview/`; refresh with `tool/be_sync/sync_be_docs.sh` then copy.
- `test/fixtures/smart_view/engine/vectors.json`: the engine vectors (input and output of the web's own functions): type inference, filters, sort, group, aggregate, formatting, cells of every field type. For B1.
- `test/fixtures/smart_view/{ai_enterprise,submissions_list,records_mine,smartview_attrs,smartview_views}.json`: stage-1 files reconstructed from revision 1 of the BE document, each with a `note` key; **superseded by `real/` where a real capture exists** (`004-`/`005-`, `007-`/`008-`, `019-`..`029-`, `049-`..`057-`, `058-`..`066-`); not deleted.
- `test/tickets/records_mine_limit_test.dart`: the `records.mine` limit rule and a fake server that copies the raised defect.
