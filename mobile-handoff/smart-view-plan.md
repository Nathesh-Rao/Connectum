# Smart View: audit and plan (Phase 1, no code)

Written 11 Nov 2026. Sources read:
- PDF: `reference/screenshots/smart-view/Smart_View_Update_Knowledge_Transfer.pdf` (9 pages, all read). The task said `reference/smart-view/`; the file is under `screenshots/`. Not copied.
- Mobile docs: `reference/MOBILE_HANDOVER.md`; mentions in `reference/tickets/TICKETS_AND_TASKS.md` (line 32), `reference/hash/HASH_COMMANDS_FOR_MOBILE.md` (`#view`, line 141), `mobile-handoff/screens-and-features.md` (line 83), `reference/backend-pack/Mobile_Team_Pack/docs/SD_ACTIONS_REFERENCE.md` (`isource.table`).
- Web repo `~/Development/Axi-apps/connectum` (read only, via `git show`, no checkout). **The update is not on `origin/main`.** It is on `origin/feat/smartview-fix` (head `691d79b7`, "Smart View Ui Updated", 11 Nov, 58 files). I ran `git fetch origin feat/smartview-fix` to get it (this only added a remote-tracking ref). The PDF says "not pushed"; the branch is on the remote now, still not merged.
  Files read on that branch: `docs/SMART_VIEW.md`, `docs/CONNECTUM_API.md` (lines 1096-1102), `docs/PERMISSIONS.md`, `chat-app/features/smartView/{smartViewSources,smartViewAttrs,smartViewEngine,svViews,svFilters,svFiles,svLayout}.js`, `SmartViewModal.jsx`, `SvChart.jsx`, `SmartView.jsx` (skimmed), `connectum-backend/src/forms/{sd_smartview,sd_svviews}.erl`, `src/core/sd_cmds.erl` (681-697), `src/core/sd_cmds_admin.erl` (811-836), `src/people/sd_perm.erl` (41, 54).

## a) What Smart View is

**In plain words.** A table viewer for any "source": a structure's records, a data source, an API result or a Connectum list. It is opened on the web with `#view <name>` in the composer (a card in the chat, "Expand" for full screen) or `#view` alone (Overview of every structure plus all sources). Everyone who may open a source sees it; the source list is built from calls the app already makes, so nobody sees what they could not already see.

**What a user can do (web).** Search; filter (panel with one line per column the admin marked "Apply filter": list, text, number range, date range with presets, yes/no; applied filters shown as chips); sort (asc/desc/off, blanks last); group (up to 5 levels, counts and totals); choose columns; resize and reorder columns; KPI cards and charts (only if an admin defined them); save views (own, shared); click a hyperlink cell (opens a structure record or another Smart View, filtered); file chips with preview; refresh; download CSV/TSV/Excel/PDF/PPTX/PNG. Admins with `smartview.configure` can set up a source (Configure) and share views. **Editing rows is not built** (not even on web).

**What "the update" changes versus before** (PDF section 1, confirmed in code):
1. Configure ("Smart view attributes"): per source an admin decides columns, captions, key and hidden columns, filter columns, links, KPI cards, charts. A source with no definition is a **plain table: no KPI cards, no charts**. Before, cards and charts were worked out automatically for every source. Only the inbox lists (Tasks, Approvals, Reminders) still do that.
2. Hyperlinks between sources (column mapping).
3. Filter panel limited to the admin's "Apply filter" columns.
4. Charts from the definition: 13 types (before: fewer, built-in).
5. Views kept **on the server**, own and shared (before: browser local storage). Old browser views migrate on first open.
6. Column resize/move saved in views.
7. File chips and preview for file-like cell values.
8. Native dialogs replaced (web only, irrelevant for mobile).

Status per the PDF: built and tested locally on the web, **not merged**; the file preview, touch resize grip and full regression were not verified. So every action below is **NOT AVAILABLE on production until the BE merges `feat/smartview-fix`** (the actions `smartview.*` and `admin.smartview.*` do not exist on `main`). The older read paths (`datasource.run`, `api.run`, `submissions.list`, `isource.*`) exist today.

## b) API / protocol

All over the socket: `/sd <action> {json}` (same layer as the rest, `connectumSocket.sd(action, args, waitMs)` on web; `sdCall` on mobile). Errors come as `{ok:false, error:{code, message}}`; codes seen in the Smart View code: `invalid`, `bad_request`, `not_found`, `limit`. UNSURE: whether `forbidden`/`permission` is the code for a missing `smartview.configure`.

### New (update branch)
| Action | Who | Request | Response | Notes |
|---|---|---|---|---|
| `smartview.attrs` | any signed-in | `{kind: structure\|datasource\|api\|list, name}` | `{attrs: Definition\|null, canConfigure}` | Names of columns, never data. `attrs` null = plain table. |
| `smartview.views` | any signed-in | `{kind, name}` | `{mine:[View], shared:[View], canPublish}` | `shared` ids start with `s<ms>`, have `by`. Default View id `__default` has no tab. |
| `smartview.views.save` | any signed-in | `{kind, name, views:[View]}` | `{views}` | **Replaces the whole own list.** Max 20 named + Default; names unique (later wins); one view max 16 KB, else `invalid`. |
| `admin.smartview.save` | `smartview.configure` | `{kind, name, metadata, hyperlinks, kpis, charts}` | `{attrs}` | Admin only: out of scope on mobile. |
| `admin.smartview.delete` | `smartview.configure` | `{kind, name}` | `{deleted:true}` / `not_found` | Admin only. |
| `admin.smartview.view.publish` | `smartview.configure` | `{kind, name, view}` | `{shared}` | Max 20 shared (`limit`); Default cannot be shared. |
| `admin.smartview.view.unpublish` | `smartview.configure` | `{kind, name, id}` | `{shared}` / `not_found` | |

Any action starting `admin.smartview.` needs `smartview.configure` (`sd_perm.erl:54`; admins always). `smartview.configure` is also in `perm.mine` / `permissions.mine`, which mobile already reads (`CommandRepository.permissions`). UNSURE: it is listed with default `admin`; confirm the exact string appears in `perm.mine`.

**Definition** (`attrs`): `{kind, name, metadata:[{field, caption, type: Character|Numeric|Date|Boolean|File, hide, key, filter, sourceForm, sourceField}], hyperlinks:[{field, type: tstruct|smartview, target, inline, mappings:[{from, to}]}], kpis:[{caption, agg: sum|avg|min|max|count, column}], charts:[{caption, chart: 13 types, groupBy, agg, column}], updatedBy, updatedTs, createdTs}`. Limits: 200 fields, 50 links, 30 KPIs, 30 charts, 10 mappings per link; names 1-120 chars.

**View**: `{id, name, search(<=200), filters:[{col, op, value}](<=30), sort:{col, dir:asc|desc}|null, groupBy:[col](<=5), hidden:[col](<=300), order:[col](<=300), widths:{col:px 48-1200}, kpis:bool, charts:bool}` (+ `by` on shared). Filter ops: text `contains|equals|not|starts|empty|filled`; number `eq|ne|gt|gte|lt|lte|between|empty|filled`; date `on|after|before|between|empty|filled` (value `"today"` allowed); bool `true|false`; choice `in` (list). `between` value `{from,to}`. Filter column keys are the **source's column key**, not the caption. UNSURE: how a view stores the key when the admin renamed a caption (code uses `col.key`).

### Existing reads Smart View depends on (already in our docs)
| What | Action | Request | Response / limit |
|---|---|---|---|
| Structures list | `ai.enterprise {what:"forms"}` | | `{forms:[{name, caption, fields, sections, keyField, canFetch, system, ticket, status, recordThread}]}` (field list gives column captions/types). Not in `SD_ACTIONS_REFERENCE` detail: UNSURE field shape. |
| Data sources | `datasource.list` then `datasource.run {name, values, limit:500, refresh?}` | | `{columns, rows, total, truncated, refreshedAt, cached, origin...}`; 60 s wait; **no paging beyond 500** (NOT AVAILABLE). Slow lane. |
| APIs | `api.list` then `api.run {name, values, limit:500, refresh?}` | | same shape; Put-type APIs are not offered; 120 calls/min slow lane; `cacheSec`. |
| Connectum lists | `isource.list` then `isource.table {name, limit?}` (api / `linked`: up to 5000 rows, `notes`, `summary`, `fetchedTs`) or `isource.values {key:"isource:<name>"}` (form/custom lists: one column "Value", up to 2000) | | skip entries with `useTable === false`. |
| Structure rows | `submissions.list {tstruct, limit:500, offset, fetch:true}` | | `{submissions:[{id, by, byName, ts, status, values}], total, hasMore}`; web loads up to 6 pages (3000). `fetch:true` UNSURE (not in the action reference). |
| Parameters | source `params:[{name, default}]` | `values:{name:value}` | Web asks for them first and remembers the last values (localStorage). |

**Pagination:** there is none for views. Every filter, sort, group, KPI and chart is computed **on the client over the loaded rows** (max ~500 for data source/API, 3000 for structures, 5000 for linked lists). No server-side filter/sort exists. Truncation is reported (`truncated`, `total`).
**Realtime:** none documented for Smart View (no `smartview_*` events; the web re-reads on refresh). UNSURE: whether `permissions_changed` or a submission event should refresh an open view.
**Ids from other features:** structure `name` (forms/structures), `submissions` ids (`#` column, link to submission detail), hyperlink `target` (structure name or another Smart View name), file ids `/api/sd/files/<24 hex>` (same file store as attachments), ticket forms' status model (`status.*`).

## c) Data model: local vs fetched

| Thing | Where | Rule |
|---|---|---|
| Source list (4 reads in parallel) | memory per session | Re-read on open and on pull to refresh. A failed part is left out and named ("Structures could not be read"). |
| Rows of a source | **memory only, never SQLite** (Phase 2) | Large, can be sensitive, no change events to keep a cache correct. Re-fetched on open/refresh. |
| Definition (`attrs`) | memory; optional small SQLite cache later | Small and rarely changing. |
| Own + shared views | memory in Phase 2; SQLite cache (`sv_views`, scoped by organisation + user) later | Server is the source of truth; save = read-modify-write of the whole list. |
| Last parameter values | SQLite or prefs, per org+user+source | Web keeps them in localStorage. |

**Offline:** unlike Chats/Submissions, Smart View data comes from live calls (some slow, some Axpert-backed). Recommendation: treat it like the AI tab (needs a connection, shows the offline state), not cached-first. This deviates from the "SQLite is the UI's only source" rule for rows, so it is **decision 2**.
**Relation to mobile data:** structures = our forms/structures (`FormCard`, form fields from `ai.enterprise`); a structure row's `#` is the submission id, so a row can open `/submissions/:id` (SubmissionDetail); ticket forms have their own screens (`tickets/`, `tasks/`), and the web's six default ticket views ("With me", "Waiting on me", "Everything open", "Open by category", "High priority", "Overdue") are built client-side from `status.assignee`/`status.field` and the user name, so mobile can skip them (the Tickets screen already covers them). Users: `By` is `byName || by`. No other table changes.

## d) Mobile design proposal (our design system, light theme)

**Where it lives.** Not a new bottom tab (4 tabs are full). Entry points:
1. A "Smart View" entry on the **Submits** tab (header action or a row above the list), opening `/smart-view`.
2. `#view [name]` typed in a composer or picked from the `#` suggestions: opens `/smart-view/:kind/:name` (today `view` is hidden or unlisted; HASH doc line 141 says the server action was not traced; this plan traces it).
3. Deep link / notification later (see below).

**Routes** (constants in `app_routes.dart`): `/smart-view` (sources), `/smart-view/:kind/:name` (a source). Parameters come from the route, per the deep-link rule; a pending link is kept until login and organisation selection.

**Screens and states**
| Screen | Content | States |
|---|---|---|
| Sources (`SmartViewSourcesView`) | search field (AppTextField), grouped list by kind (Structures, Data sources, APIs, Connectum lists) with `AppListRow`; structures first, user-made before built-in (like web) | loading `AppSkeleton`/`AppSpinner`; empty and error with retry via `AppStateView`; offline state; partial failure notice (`AppNoticeCard`); pull to refresh `AppRefresh` |
| Source (`SmartViewView`) | title, `AppPillBar` of views (Default + own + shared with a group icon), search, filter button with count badge, sort, group, columns, refresh; KPI strip; result list; footer "Showing 500 of 1,230" when `truncated` | same states; params sheet first for sources with parameters; "no rows match" empty state for filters |
| Filter sheet | `AppBottomSheet`: one control per column marked `filter` (choice multi-select, text op + value, number from/to, date presets + custom, yes/no); Apply / Clear; chips under the search bar | |
| View menu | `AppPopupMenu`: Save / Update, Save as new, Remove (confirm), shared view: Save as my own; Reset column layout only if used | |
| Row detail | `AppBottomSheet` or page with `AppKeyValueRow` for every visible column; link cells, file chips | |
| Columns / Group sheets | checkbox lists, at least one column stays | |

**Phone presentation of tables.** Primary: **cards**, one per row. Title = the key column (`key:true`) or the first visible column; subtitle = second column; up to 3-4 more fields as `label: value` lines (configurable via Columns); status-like columns as `AppStatusPill`/`AppTag`. Tap = row detail with all columns. Grouping = sticky group headers with count. **No horizontally scrolling grid in Phase 2**; offer an optional "Table" toggle later (fixed first column, horizontal scroll, widths from the view, clamped 64-800). Column order/hidden from the view apply to cards and detail; **resizing is skipped** on mobile (but kept untouched when saving a view so web widths are not lost).

**Charts.** `AppChart` (`lib/core/widgets/app_chart/`) takes the web's `{type, title, unit, labels, series:[{name, values}]}` JSON and draws **bar, column, line, donut (pie)**, max 40 labels, 6 series. A Smart View chart is exactly `{type, title, subtitle, labels, series:[{name, values}], unit}` (`definedChart` in `smartViewAttrs.js`), so `AppChartData` can be built directly. Mapping: `bar`/`stacked-bar` -> bar; `column`/`stacked-column`/`stacked-percentage-column`/`stacked-group-column` -> column; `line`/`area` -> line; `pie`/`donut`/`semi-donut` -> donut. **Not covered:** `scatter-plot`, `funnel` (and true stacking/percent). Fallback: render as bar (funnel) and show a note, or hide. Charts are computed on the client with the web's rules (group by, aggregate, biggest first, dates in order, max 40 groups, `more` count), so the aggregation code has to be ported (see below). Phase 3.

**KPI cards.** Computed client-side per `kpis` over the filtered rows (sum/avg/min/max/count). Use existing card visuals (`AppCardCircles` or stat card style from the Home/Tasks area). Phase 2.

**Saved views.** Read own + shared and apply (Phase 2); create/update/remove own (Phase 3); publish/unpublish shared = admin, not on mobile (view only).

**Deep links and notifications.** Smart View is not mentioned in `deep-links.md` or the notification docs. Proposal: `.../view/<kind>/<name>` style link only once the BE defines one (question 14); until then only `#view` and the Submits entry.

**Read-only first.** Everything on mobile is read-only: no Configure, no publish, no edits, no downloads, no upload.

## e) Reuse map

| Need | Reuse | New |
|---|---|---|
| Socket/RPC | `SocketService.sdCall`, repository pattern, error mapping | `SmartViewRepository` (one class: sources, load source, attrs, views) |
| Permissions | `CommandRepository.permissions` (`perm.mine`) | check for `smartview.configure` (only to show a hint) |
| List rows / headers | `AppListRow`, `AppKeyValueRow`, `AppDetailRow`, `AppIdCopyStrip` | row card widget |
| Filters / views bar | `AppPillBar` (views), `AppFilterChips`, `AppFilterTabs`, multi-select filter code used in Chats/Submissions | filter sheet per column type |
| Actions | `AppActionBar`, `AppPopupMenu`, `AppBottomSheet` | |
| States | `AppStateView`, `AppSkeleton`, `AppSpinner`, `AppRefresh`, `AppOfflineBar` | |
| Chart | `AppChart`, `AppChartData` | 13-to-4 type mapping, an aggregate/group helper |
| Submission link | `SubmissionDetail` route, `submission_repository.dart` paging loop (lines ~1043-1073) | |
| Files | `AttachmentRepository`/`attachment_cache.dart` (authenticated file fetch), image/PDF viewers if present | sniff-by-bytes check, chip widget |
| Notifications / deep links | `deep_link_service.dart`, route params | route + link only once defined |
| Data engine | none in Dart | port of `smartViewEngine.js` pure functions: `buildTable`/`inferType`, `applyFilters`, `applySort`, `groupRows`, `aggregate`, `toTime`; `smartViewAttrs.js` `applyAttrs`, `definedCards`, `definedChart`; `svFilters.js` `controlFor`, `rangeFor` |

## f) Phasing

| Phase | Scope | Screens | Files (new) | Tests | Size |
|---|---|---|---|---|---|
| **2: smallest useful slice (read-only)** | Source list (4 reads), open a source, params sheet, plain table as cards, `smartview.attrs` applied (captions, hide, key, filter columns), search, sort, filters (panel + chips), KPI cards, read own+shared views and apply them (no editing), truncation notice, pull to refresh | Sources, Source, Filter sheet, Row detail | `lib/features/smart_view/{smart_view_controller,smart_view_view,smart_view_binding}.dart`, `smart_view_sources_*` (3 files), `models/{sv_source,sv_attrs,sv_view,sv_table}.dart`, `lib/data/smart_view/{sv_engine,sv_attrs_logic,sv_filters}.dart`, `lib/data/repositories/smart_view_repository.dart`, widgets for card, filter sheet, KPI strip; route consts + `app_pages.dart` entries | unit: engine (type inference, filters, sort, `between`, `today`), attrs (applyAttrs, KPIs), view whitelist parsing; widget: row card, filter sheet, states; goldens: source card, filter sheet; integration (test env): list sources + open a structure of the seeded org, apply a filter. Seed data for Smart View does not exist in the test env (UNSURE, ask) | **M-L** |
| **3: views, groups, charts, links** | Save/update/save-as/remove own views (read-modify-write, 20 limit, 16 KB), group (counts), Columns picker, charts via `AppChart` (4 types + fallback), hyperlinks (open structure record / another source preset-filtered), `#view` command + suggestions, entry in Submits | Group sheet, columns sheet, chart row, save-view dialog | `sv_charts.dart`, `sv_links.dart`, `sv_views_logic.dart`, widgets | unit: group/aggregate/definedChart vs the web test vectors (`tests/frontend/smartViewAttrs.test.mjs`), view save round trip with a fake repo; widget; goldens for charts; integration: save a view, reopen on a second login | **M** |
| **4: files, table mode, cache** | File chips + preview (image/PDF, sniff by bytes), optional Table mode with horizontal scroll, SQLite cache for views/attrs/params, deep link / notification routing, `smartview.*` error mapping, tablet layout | Preview, Table | `sv_files.dart`, `sv_table_view.dart`, DB tables + migration | unit: `safeUrl`/file detection vs `smartViewFiles.test.mjs`; widget; integration | **M** |
| **Later (BE first)** | Edit/Enable new/bulk save, Excel upload, server paging, downloads (CSV share), Configure/publish for admins | | | | **L each** |

## g) Risks and gaps

- **Not merged / not on production.** All `smartview.*` actions are on an unmerged branch; do not build views/attrs before the BE merges and deploys (Phase 2 can start against the dev instance only if they deploy there). Without attrs the app can still show plain tables from the old reads.
- **Client-side everything.** Rows up to 500 (data source/API), 3000 (structure, six pages of 500), 5000 (linked lists). Memory and CPU on low-end phones: compute filter/sort/group once per change, off the build path; cap rendering with `ListView.builder`. Group/chart code must be a faithful port or numbers will differ from the web. The web's type inference (number vs id-like columns, phone numbers, dates `DD/MM/YYYY`) has many rules; copy them with the same tests.
- **Slow and rate-limited calls.** `datasource.run` and `api.run` are slow lane, 120/min; waits up to 60 s. Need a timeout state and cancel. API results may be cached on the server (`cacheSec`, `refresh:true`).
- **Truncation.** `truncated`/`total` must be shown; users may think 500 rows is everything. No paging fix exists (not built).
- **Views whole-list replace.** `smartview.views.save` overwrites the list: two devices saving can lose a view. Always re-read before write and merge. Web has the same limit. 16 KB per view; keep unknown keys? The server drops unknown keys, so web-only keys cannot be round-tripped through mobile: **widths/order are kept (they are whitelisted)**, fine.
- **Privacy / e2e.** Forms and structure records are never end-to-end encrypted, so Smart View over structures reads server-side data; nothing e2e is involved. Rows may be sensitive (HR, finance): keep them in memory only (decision 2), clear on logout/`session_replaced`, never in logs (`redact.dart`), never in push or notification text.
- **Permissions edge cases.** Source list is "what the person may open"; a source can disappear between list and open (`forbidden`/`not_found`: show a plain message and go back). Definition naming a removed column must be skipped quietly (PDF says do not make it an error). `canConfigure` only changes admin UI, hidden on mobile. Session replaced mid-load: follow the existing session rule.
- **Files.** Connectum files at `/api/sd/files/<id>` need the signed-in fetch and are sent with no type: must sniff the first bytes (PNG, JPEG, GIF, WebP, PDF) and never trust names; never draw SVG or plain `http`; reject `javascript:`, `data:` pages, `blob:`, `file:`, `//host`. The web preview was **not** verified in Chrome.
- **Hyperlinks.** A link opens the target with a filter built from mappings; on web the target rows are loaded and filtered client-side. Mobile needs the target's rows (or a record lookup) to resolve one row: UNSURE which call.
- **Dates.** `today` in a filter means the day the view is opened; local-time days (web uses local, not UTC). Ticket/other time zones: use device local time like web.
- **Test env gaps.** No seed data for Smart View (no definitions, no demo org: the PDF's demo org README is on a developer's Desktop, not in the repo). We cannot trigger events. Unit tests with fixtures only until BE gives sample JSON.
- **PDF vs code mismatches.** (1) Comment on `admin.smartview.save` says `kind: datasource|api|list`, but the code and docs accept `structure` too. (2) The Configure grid in `SMART_VIEW.md` lists 4 types, the server allows 5 (`File`). (3) PDF says views limit "20 plus Default"; matches code. (4) PDF says "not pushed", the branch is on the remote. None blocks mobile; (1) goes to the BE.
- **Postman.** `postman/api_collection_connectum.json` and the backend pack Postman do not contain `smartview.*` (searched); only the docs on the branch do. If Postman is updated later and disagrees, ask.

## h) Questions for the BE (paste as one message)

1. Is `feat/smartview-fix` (head `691d79b7`) going to be merged into `main`/`dev`, and when will `smartview.attrs`, `smartview.views`, `smartview.views.save` be live on the dev instance (10.0.2.113)? Until then they do not exist for us.
2. What error `code` does a call return when the person may not open the source (`datasource.run`, `api.run`, `submissions.list`, `isource.table`) and when `smartview.configure` is missing on an `admin.smartview.*` call? We only see `invalid`, `bad_request`, `not_found`, `limit` in the code.
3. Does `perm.mine` / `permissions.mine` return the string `smartview.configure`? Please send a sample answer.
4. `submissions.list {tstruct, limit, offset, fetch:true}`: what does `fetch:true` do (it is not in `SD_ACTIONS_REFERENCE`), what is the maximum `limit`, and is there a server-side filter, sort or search we can use instead of loading 3,000 rows?
5. `datasource.run` / `api.run` return at most 500 rows (`truncated`). Is server-side paging (offset/limit) planned? What is the real maximum and the timeout?
6. `ai.enterprise {what:"forms"}`: please send the exact answer shape (field `type` values, `sections`, `keyField`, `status`, `ticket`, `system`, `canFetch`) and say whether it is the right call for the mobile source list or if there is a lighter one.
7. Are there any realtime events for Smart View (definition changed, view published, new rows in a structure)? If not, should mobile refresh on `permissions_changed` and on submission events?
8. Hyperlink `type: tstruct` / `smartview` with `mappings`: how should a client find the one target record? Is there a call that returns one record by field value, or do we load the target's rows and filter locally (as the web does)?
9. A view's `filters[].col`, `hidden`, `order`, `widths`, `groupBy`: are these the source's column `key` (not the caption)? What are the `key`s for a structure's built-in columns (`#`, `By`, `On`, `Status`)? Are they stable and language independent?
10. `smartview.views.save` replaces the whole list. Is there (or will there be) a per-view save/delete or a version/`updatedTs` for conflict detection, so two devices cannot overwrite each other?
11. Filter op names and the `today` value: is this the full list for mobile to support (`contains equals not starts empty filled eq ne gt gte lt lte between on after before true false in`)? Is `date` `between` `{from,to}` always `yyyy-mm-dd`?
12. Files in cells: for `{fileId}` / `/api/sd/files/<id>`, which call fetches the bytes with a session token (the HTTP route with a bearer token, or a socket action)? Is there a size limit, and will the server send a content type?
13. Is a Smart View in the web backed by anything else we must call (ticket default views, `status.*`, the inbox lists "Tasks & tickets / Approvals / Reminders")? Should mobile ignore the inbox-only Smart View modes (we already have Tasks, Approvals, Notifications)?
14. Is there a deep-link format for a Smart View (`#view <name>` equivalent URL) and a notification type that opens one? Not in `deep-links.md`.
15. `admin.smartview.save` comment says `kind: datasource|api|list` but the server accepts `structure`: confirm `structure` is supported, and that the `kind` strings are exactly `structure`, `datasource`, `api`, `list`.
16. Can we have test data: an organisation on the dev instance with a structure, a data source, an API, a definition (metadata, links, KPIs, charts), own and shared views, and a file column; ideally added to `tools/mobile-test/seed.mjs`? Also sample JSON answers for each action above.
17. Is `list` (Connectum data sources via `isource.list`/`isource.table`/`isource.values`) meant to be in the mobile scope, and which of them have `useTable:false`? Same for `linked` lists (5,000 rows, `notes`, `summary`): how should `notes`/`summary` be shown?
18. Is any part of Smart View data permission-scoped per row beyond what the source calls already do (e.g. a structure's records "as the person who asks")? Anything the mobile app must not cache or display?

## i) Decisions needed (with my recommendation)

| # | Decision | Recommendation |
|---|---|---|
| 1 | Where it lives | Entry from **Submits** tab plus `#view` in composers; no new bottom tab. |
| 2 | Offline | **Connection only**, rows in memory, nothing stored in SQLite in Phase 2 (privacy, size, no change events). Cache only definitions/views/params later. This is an exception to the "SQLite is the only UI source" rule for this feature. |
| 3 | Table on phone | **Cards** with key fields and a detail sheet; optional Table mode in Phase 4. |
| 4 | Read-only scope | Mobile is read-only (view, filter, sort, search; own views in Phase 3). No Configure, publish, edit, upload, download. |
| 5 | Start before the BE merges? | Start Phase 2 only against plain sources (no attrs) if the BE says the merge is weeks away; otherwise **wait for the merge** so we build once against the real shape. |
| 6 | Charts | Phase 3, reuse `AppChart` (4 types) with a fallback for funnel/scatter, instead of building 13 types. |
| 7 | Structures rows | Load all up to 3,000 (web parity) vs first 500 with "load more": recommend **500 + load more** on mobile for memory and speed, pending BE answer 4. |
| 8 | Files | Phase 4; chips first, preview images/PDF only. |
| 9 | Inbox-mode (Tasks/Approvals/Reminders as Smart View) | **Skip**: we already have those screens. |
