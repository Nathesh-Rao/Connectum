# Smart View: saved views, columns, group, hidden fields, customize (the web today)

**Read from:** web repo `~/Development/Axi-apps`, branch **`origin/dev`**, commit **`54a31d45699a4855bdd5da206ca7e1f8e80b9521`** (2026-11-18, after `git fetch`; read from a `git archive` extract, repo untouched). Smart View lives on `dev` (`connectum/chat-app/features/smartView/`, backend `connectum/connectum-backend/src/forms/sd_svviews.erl`, `sd_smartview.erl`, `core/sd_cmds.erl`, `core/sd_cmds_admin.erl`). BE docs synced with `tool/be_sync/sync_be_docs.sh` (state 54a31d4569). The code is the truth. Nothing here was run against a server; "[VERIFIED]" points to the BE's own captures in `test/fixtures/smart_view/real/`. File refs are relative to `connectum/chat-app/features/smartView/` (`SV:`) or `connectum/connectum-backend/src/` (`BE:`). Not mobile code; nothing was built.

Companions: `smart-view-views-be-questions.md`, fixtures `test/fixtures/smart_view/views/`, older BE study `reference/` copy of `MOBILE_SMART_VIEW.md` (2.8, 5.4).

---

## 0. Files
| Area | Files |
|---|---|
| Screen, state, menus, tab strip, save/create/remove | `SV:SmartView.jsx` (910 lines: reducer 76-90, views 517-560, tabs 785-800, tools 802-875) |
| View data rules (pure) | `SV:svViews.js` (29 lines) |
| Column layout (order, widths, row height) | `SV:svLayout.js` |
| Filters (panel model, chips, presets) | `SV:svFilters.js`, `SV:SvFilterBar.jsx`; condition engine `SV:smartViewEngine.js:102-176` |
| Select Fields / Group By dialog | `SV:SvFieldPicker.jsx` |
| Group tree, aggregates, export | `SV:smartViewEngine.js` (`groupRows` 216, `groupTree` 232, `flattenTree` 241, `aggregate` 295, `toCsv` 403, `exportMatrix` 413, `toTsv` 429) |
| Customize (cards and charts) | `SV:SvConfigure.jsx`, `SV:smartViewAttrs.js` |
| Server calls | `SV:smartViewSources.js:18-27` (`callRetrying`), `:320-364` |
| Backend views | `BE:forms/sd_svviews.erl`; attrs `BE:forms/sd_smartview.erl` |
| Tests | `connectum/tests/frontend/smartView*.test.mjs` (`smartViewHiddenOption`, `smartViewFilters`, `smartViewLayout`, `smartViewStructure`, `smartViewShareSwitch`, ...); `connectum/connectum-backend/test/connectum_smartview_test.mjs` |

---

## a) SAVED VIEWS

### a.1 Schema of a view (what the server keeps)
`BE:sd_svviews.erl:275-297` (`clean_view`) keeps ONLY these keys; anything else is dropped. `SV:svViews.js:12` (`captureView`) produces them.

| Key | Type | Rule (server) | Client notes |
|---|---|---|---|
| `id` | string | 1-40 chars `[A-Za-z0-9_-]`, else error "A view needs an id (letters, digits, - and _, up to 40)." | new views: `` `${Date.now()}` `` (SmartView.jsx:529); Default View: `"__default"`; shared: `"s<now_ms>"` (BE:59,195); server-made: `auto-open`, `auto-by-status`, `auto-by-choice`, `auto-newest` |
| `name` | string | trimmed, 1-40 chars, no control chars (`\x00-\x1f\x7f`), else "A view needs a name of 1 to 40 characters." | client `cleanName`: whitespace collapsed to one space, trimmed, cut at 40 (svViews.js:29) |
| `search` | string | trimmed, 0-200 chars; invalid becomes `""` | |
| `filters` | list of objects | max **30**, each a map whose JSON is <= **2000 bytes**; non-maps dropped. Content NOT validated | `captureView` drops conditions with `preset: true` (link conditions); shape in b) |
| `sort` | object or null | `{col, dir}` with `dir` `"asc"`/`"desc"` and `col` text <= 80; else `null` | tri-state in the reducer: none, asc, desc, none (SmartView.jsx:79-82) |
| `groupBy` | list of strings | max **5** names (each <= 80, no control chars) | older views stored one string; `groupList` accepts either (svViews.js:9); BE always writes a list |
| `hidden` | list of strings | max **300** names (<= 80) | keys of columns left out; a **quiet** column that is turned ON is stored as `"+<key>"` (SmartView.jsx:263, 540-544); see c) |
| `order` | list of strings | max 300 names | column keys in shown order; `[]` = the table's own order |
| `widths` | object key -> number | keys <= 80 bytes, values numbers **48-1200** (rounded), max 300 entries; others dropped | the web clamps to 64-800 itself (`svLayout.js:3-5`) |
| `kpis` | bool | `kpis =/= false` (default true) | whether the card row shows |
| `charts` | bool | `charts =/= false` (default true) | whether the charts show |

Whole view <= **16384 bytes** as JSON ("That view is too big to keep.", BE:15, 292). **There is NO `wrap`, `rowSizes`, `mode`, or `hiddenFieldsToggle` key**: wrapping, record heights (`tall`, `autoRows`, `wrapAll`) and "Show hidden fields" are screen state only and are never stored in a view (SmartView.jsx:277-283, 182). `closed` (collapsed groups) and the ticked rows are never stored either (svViews.js:11). The server-written views (`sd_svviews:view/3`, BE:170) also carry `search:""`, `filters`, `sort`, `groupBy`, `hidden:[]`, `order:[]`, `widths:{}` but no `kpis`/`charts` before the clean pass adds `true`.

Real example [VERIFIED]: `real/060-smartview-views-after-saving.json`. Fixtures: `views/*.json`.

Shared views (read-only copies for other people) add `by` (author username), `to` (audience, removed before it is sent to viewers) and, in the answer to a viewer, `mine: bool` (BE:79).

### a.2 Where stored, commands, shapes
Redis, never the device (SV svViews.js:1-4; BE:1-8):
- `sd:svviews` hash, field `"<username>|<kind>:<source>"` lower-case, value `{views:[view]}`: a person's own views of one source. **Per user, per source.**
- `sd:svshared` hash, field `"<kind>:<source>"` -> `{views:[view]}`: views published for people who open the source (a source deletion removes them, BE:218-232).

Allowed kinds (`BE:sd_smartview.erl:65`): `structure`, `api`, `approvals`, `reminders`, `file`, `work`. `datasource` and `list` are on hold. Source name <= 120 chars. (Docs say Inbox lists keep views on the device; the code stores them on the server with kind `approvals` / `reminders` / `work`.)

| Command | Request | Reply `data` |
|---|---|---|
| `smartview.views` | `{kind, name}` | `{mine:[view], shared:[view], canPublish:bool}`; `canPublish` = holds `smartview.configure` (sd_cmds.erl:726-732) |
| `smartview.views.save` | `{kind, name, views:[view]}` | `{views:[cleaned list]}`; **replaces the whole list** (sd_cmds.erl:748-753) |
| `smartview.view.unshare` | `{kind, name, id}` | `{shared:[...]}`; only for a view the caller shared, else `not_found` "No such shared view of yours." |
| `admin.smartview.view.publish` / `.unpublish` | `{kind, name, view}` / `{kind, name, id}` | `{shared:[...]}`; needs `smartview.configure`; **no UI in the web calls them** (publishView/unpublishView are defined, never imported by SmartView.jsx) |
| `smartview.share`, `.shares`, `.unshare`, `.targets` | see MOBILE_SMART_VIEW 2.9 | **hidden in the web** since 17 Nov 2026 (`SV:svShareSwitch.js:5`, `SMART_VIEW_SHARE_ENABLED = false`): creating shares is off, existing shared tabs still show |

Web timeout 15 s; every call goes through `callRetrying`: on `rate_limited` waits `1000 x (attempt+1)` ms, up to 4 retries (smartViewSources.js:18-27).

**Limits:** 20 named views per person and source, plus the Default View (`clean_list`: list <= 21; named > 20 -> "At most 20 views."); 20 shared per source ("There are already 20 shared views. Remove one first.", code `limit`). The client keeps `slice(0, MAX_VIEWS + 1)` in `upsert` (svViews.js:24).

**Ids and ordering.** A new view goes FIRST in the list (`upsert`: `[view, ...others]`); an existing id is replaced in place; the list order is the tab order (Default tab is fixed first, own views next, shared views after with a group icon, SmartView.jsx:787-798). Nothing can reorder tabs. The server keeps list order and removes duplicates: one id once and one name once (case-insensitive), "the later one wins" (`dedupe`, BE:264-273; implemented by folding the reversed list, so the LAST occurrence in the list survives).

**Server-made views.** When a person creates a structure the server seeds their own list (`sd_svviews:seed/2`, BE:134-168), only if their list for that structure is empty: a status field -> "Everything open" (`filters: [{col: <status>, op: "not", value: <final>}, ...]`) and "Open by status" (same + `groupBy:[status]`); the first single-choice list field -> "By <caption>" (`groupBy:[field]`, name cut to 40); the first date field -> "Newest first" (`sort {col, dir:"desc"}`). [VERIFIED: capture 058.]

### a.3 "Default View"
- Always the first tab, never in the saved list as a tab. `DEFAULT_ID = "__default"` (svViews.js:5). If the person saved one, it is a normal entry in the same list with id `__default` and name `"Default View"`; `tabsOf` hides it from the strip, `defaultOf` finds it (svViews.js:18-19).
- **When the source opens**, once the views are read, the stored default (if any) is applied: `dispatch({type:"reset", view: viewState(def, internalKeys(source))})` (SmartView.jsx:227-232). The Default tab stays lit (`viewId === null`).
- **How it is changed:** with the Default tab lit, **Save view** stores the current screen state as the `__default` entry (SmartView.jsx:540). There is no way to delete it from the UI except the quirk below; no rename (name is forced to "Default View").
- The name "default view" (any case) is refused for a new view: "That name is taken by the Default View. Choose another." (SmartView.jsx:524). The server has no such name check (it dedupes the Default by id, other views by name), so a direct API save with that name would be kept.
- The server refuses to share the Default View ("The Default View cannot be shared; save it as a view with a name first.", BE:50, 193).
- **Code quirk (read, not run):** the Default tab's click is `showView(defaultOf(views))` and `showView` sets `viewId = v.id` (SmartView.jsx:550). With a stored default, clicking the Default tab sets `viewId = "__default"`, not `null`: the tab then does not show as lit (`aria-selected={viewId === null}`), and **Remove view** (`viewId !== null && !sharedNow`) appears and would delete the stored default. Without a stored default it sets `null` (correct). Mobile should treat "default" as one state.

### a.4 The Save menu and the options menu: exact semantics
Bottom icon `save` (menu "Save"), SmartView.jsx:802-815:
| Item | When shown | What it does |
|---|---|---|
| **Save view** (`updateCurrent`, 539-543) | not on a shared tab (`!sharedNow`) | Default lit: upserts the `__default` entry with the current state, toast "Default View saved". A saved tab lit: replaces that view's captured parts (`{...v, ...captureView(s)}`, id and name kept), toast "View updated". Always enabled (no "unsaved" state) |
| **Save as new view** (`saveAsNew`, 530) | not for `kind: file` | opens the name dialog; creates a new tab from the CURRENT screen state |
| **Save as my own view** | replaces the previous on a shared tab | same, name prefilled with the shared view's name (copy of a shared view; readers never change a shared view) |
| **Save to my files** | `kind: file` only | out of scope (f) |

Options menu (three dots), SmartView.jsx:855-875:
| Item | Rule |
|---|---|
| **Create view** | always. Name dialog; the new tab starts from `initial` = the plain list (every column, no search/filter/sort/group; `hidden/order/widths` empty; `kpis` true; `charts` null, which stores as true) NOT from the current screen. It opens at once (`showView`) |
| **Remove view** | only when `viewId !== null` and the tab is not shared (`!sharedNow`). Confirm dialog: title `Remove the view "<name>"?`, text "Its filters, grouping and columns are forgotten. The data is not touched.", button "Remove view" (danger). Then the whole list is saved without it and the screen shows the Default (`showView(null)`) |

**Name rules (client):** empty -> "Give the view a name."; "default view" -> taken message; max 40 (`maxLength`, `cleanName`). **Duplicates:** a new view whose name matches another view (case-insensitive) REPLACES that view (the older one with the same name is dropped; `upsert` filter, svViews.js:24), silently. No rename, no reorder, no sharing UI (hidden). After creating or saving as new, that tab is lit.

**Unsaved changes:** none tracked. Search, filters, sort, group, columns, order and widths are screen state; clicking another tab calls `showView`, which applies that view over a fresh state and **drops every unsaved change without asking** (`dispatch({type:"apply", view})`, `closed: {}`). Saving is the only way to keep a change.

**Persisting is optimistic:** `persist(next)` sets state first, then calls `smartview.views.save` and only toasts "Your views could not be saved. Try again." on failure, without rollback (SmartView.jsx:518-521). The server's answer (cleaned list) is not applied back.

**Permissions:** anybody who can open the source saves and removes their own views (the per-user key). `smartview.configure` is needed only for `admin.*` publish/unpublish (no UI). A structure's shared views show only to people who may open the structure (`may_open`, BE:74). Server also ignores a name check for the person's own views beyond dedupe.

**Concurrency:** none. `save` replaces the person's whole list; no `rev`, no `stale` error; two devices overwrite each other, the loser's view vanishes silently [VERIFIED: captures 061-063; `MOBILE_SMART_VIEW.md` 2.8.1].

### a.5 The bottom tab strip
`<div role="tablist" aria-label="Views">` (SmartView.jsx:787): `Default View` tab, then own views (`tabsOf(views)`, newest first because new views are put at the head), then shared views (group icon, tooltip "Shared with everybody who opens this"). Click = `showView`. Tabs are plain buttons; no close, rename, drag, overflow rule (the strip scrolls in CSS). Opening a source resets `viewId` to null (the Default). The strip lives in `sv-foot` beside the filter bar and the icon row.

Bottom icon row (`sv-tools`): **Save** (menu), **Refresh** (`run(values, true)` and clears the ticked rows; tooltip "Get the latest data (last updated ...)"), **Delete** (structures only: deletes the ticked records via `submissions.delete`, <= `DELETE_MAX`; not a view action), **Add** (`+`, only with `onAddRecord` and `canAdd`), **Download** (menu, disabled with no rows), **Search** (opens an input, filters live), **Options** (three dots).

---

## b) FILTERS ("Click here to Filter Data")

**Condition model** (`SV:smartViewEngine.js:102-146`): a filter is `{col, op, value}` (`col` = column key). `filterActive` rules: no `col` or `op` -> inactive; ops `empty`, `filled`, `true`, `false` need no value; `in` needs a non-empty array; `between` needs `value.from` or `value.to` non-blank; others need a non-blank, non-whitespace value. Inactive conditions are ignored when filtering (not "match nothing"). All active conditions are ANDed; the search box is a separate AND: the needle (lower-case) must be contained in the text of at least one searchable column (`searchIn` = the listed columns, so a hidden column cannot find rows, engine line 160-163). **There is no OR and no nesting.**

Operators per type (`OPS`, engine:102-114):
| Type | Ops (key) |
|---|---|
| text, list, json, file | `contains`, `equals`, `not`, `starts`, `empty`, `filled` (`list`/`json`/`file` use the text ops on the shown text) |
| number | `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `between`, `empty`, `filled` |
| date | `on`, `after`, `before`, `between`, `empty`, `filled` |
| bool | `true`, `false` |
| (any column) | `in` with `value: [text, ...]` (case-insensitive equality with any), used by the panel's choice lists |

Value shapes: string for text/number/date; `{from, to}` (either may be `""`) for `between`; `string[]` for `in`; `null` for no-value ops. Number values are parsed by `num`, dates by `toTime`; `value: "today"` is also accepted for date ops (engine:148). Dates compare by day. `between` bounds are inclusive; a row whose cell cannot be parsed never matches a number/date op.

**The panel** (`SV:svFilters.js`, `SvFilterBar.jsx`): one line per filterable column. Control by `controlFor`: number -> range (`between`); date -> range with presets `custom`, `today`, `yesterday`, `week` (Monday to Sunday), `7days`, `month`, `lastmonth`, `year` (computed on the client as `from`/`to` days; the preset itself is NOT stored, only the resulting `between` dates; `draftFor` finds the preset again by matching); bool -> `true`/`false`; other columns: **choice** (`in`) when the column has 1 to 60 distinct values (500 for a column whose `sourceForm` is set), else text with `starts`/`contains`/`equals` (default `starts`). `conditionFrom` builds one condition per column; `applyDrafts` keeps conditions the panel does not show (a link's, a saved view's on a hidden column) and replaces the panel's columns' ones. Chips show each condition (`chipText`: e.g. "Customer: ACME, BETA", "Net: from 500", "Stage is not Closed", words in `svFilters.js:74`). Which columns are filterable: structures with no attrs -> all listed; with attrs -> those with `filter: true` (`filterCols`, smartViewAttrs.js:83).

**Storage:** `view.filters` = the active conditions list as above, `preset: true` ones removed (svViews.js:12). Server stores <= 30 conditions, each <= 2000 bytes, unvalidated. A stored filter on an internal column (`#`) is dropped on load (`viewState`, svViews.js:15).

**Versus the ported engine** (`test/fixtures/smart_view/engine/vectors.json`): the filter vectors (`filters`, `chips`, `filterControl`, `datePresets*`, `captureView`) are **identical** to what the current web code produces (I regenerated the vectors from the dev extract with `TZ=Asia/Kolkata node tools/smartview-vectors.mjs` into a scratch file and compared section by section). No difference in ops, `in`, `between`, presets. Sections that differ: see "disagreements" below.

---

## c) SELECT FIELDS (Columns)

Dialog `SvFieldPicker mode="columns"` (`SV:SvFieldPicker.jsx`; opened from Options > **Columns**):
- Title "Select Fields". A "Search fields..." box filters by caption OR key (case-insensitive substring); grid of checkboxes, each `caption` + small `key`.
- **Select all** toggles all fields *currently shown by the search* (not hidden ones).
- **Reset** = tick exactly the original set: `listed.filter(c => !c.quiet)` (the table's default columns: quiet ones off).
- **Apply** is disabled when no listed field is ticked ("Keep at least one field."). The checks run over ticked keys that exist in `cols`.
- Footer: Reset, Apply. No cancel button (close the dialog).

**How the choice is stored** (`applyColumns`, SmartView.jsx:539-548): `hidden` = keys of listed non-quiet columns that are NOT ticked, plus `"+<key>"` for each quiet column that IS ticked. `order` = the ticked keys in tick order, except `[]` when that equals the table's natural order. Shown columns = `listed` filtered by `hidden` (a quiet column shows only when `"+key"` is in `hidden`), then `orderColumns(cols, order)`: keys in `order` first in that order, others after in natural place (svLayout.js:9-13); if nothing is left, the non-quiet columns show (SmartView.jsx:263).

**Quiet columns** (`SV:svStructure.js:128-139`): the structure's own status field, `With`, `Progress` (`#progress`) when the structure has a status, and the record's approval column (`Status`, called "Approval" when the structure has its own status). They are off by default. `By` is dropped when one person made all rows; `Status` is dropped when every record is "Recorded" (SmartView.jsx:253-257).

**Meta columns and the checkbox column.** The first grid column is a fixed checkbox column of width 44 (`TICK_W`, row selection by row index `__i`), never part of `hidden`/`order`. The record number `#` ("No.") is an **internal** column: kept in each row as data, never a column, filter, sort, group, picker row or download (`RECORD_NO`, `internalKeys`, smartViewAttrs.js:27-30). The record's `By` and `On` (caption "Submitted", date) are normal columns after the structure's fields.

**Column order / drag / reorder:** YES, in the web: drag a header onto another to move (`moveColumn`), Alt+Left/Right on a focused header (`nudgeColumn`); the grip on a header edge resizes (64-800 px, arrow keys by 16 px, double click fits). All stored as `order` and `widths` in the view. The dialog itself has no drag.

### "Show hidden fields"
- **What a hidden field is:** a field the form builder marks `hidden: true` (not on the entry form's screen), plus the four hidden helper fields a status keeps (`<f>_comments`, `_completion`, `_files`, `_hours`). The server leaves them out of the source list `ai.enterprise {what:"forms"}` so a table has no column for them by default.
- **Where the toggle is:** inside the Columns dialog, under "Select all" (`hiddenOption`), label "Show hidden fields", hint "Fields the form keeps off its screen. Off unless you turn it on." (SvFieldPicker.jsx:49-52). Shown only when `canSeeHidden = source.kind === "structure" && !source.system` (SmartView.jsx:187): **any structure's table, for anybody who can open it** (changed 16 Nov 2026 from "only the creator", test `smartViewHiddenOption.test.mjs`). No permission check beyond opening the table.
- **What it does** (`toggleHidden`, SmartView.jsx:371-387): turn ON: reads the form definition once with `tstruct.user.get` (via `loadDefinition`), takes fields with `hidden === true` and not kept by the status (`keptParts`), maps to `{name, caption, type, section, rich}`, puts them in `extraFields`, and re-reads the table with `source.fields + extraFields` (`run(values, false, true)`). Those columns appear ticked. If the form has none: note "This form has no hidden fields." Errors show as a note in the dialog. Turn OFF: clears `extraFields`, re-reads.
- **Does the server already send the values? YES.** `submissions.list` rows carry `values` for hidden fields; the web only decides not to draw them; "Show hidden fields" reads the same `values` plus the form definition (`tstruct.user.get`, which also sends the hidden field's `default`) [VERIFIED: `MOBILE_SMART_VIEW.md` 5.4, captures 007, 012, 046]. A security question for the owner; see the BE questions.
- **Persisted?** NO. The toggle and `extraFields` are screen state and last "while the view is open" (SmartView.jsx:182, doc line 112). A saved view may list such a column in `hidden`/`order` (with or without `+`) but the column only exists again after the person turns the switch on; `viewState` does not filter unknown keys, the screen ignores keys not in `listed` (`groupKeys` and `shown` both filter by `listed`).
- Hidden columns never feed the search (`searchIn = listed`).

---

## d) GROUP BY

Dialog `SvFieldPicker mode="group"` (Options > **Group**, label "Group (N)" when N levels are active): title "Group By", subtitle "Rows are grouped in the order you tick the fields". Footer: **Clear**, **Cancel**, **Apply**. Ticked fields are numbered 1..n when more than one ("Group level n"); the first ticked is the outer group. No Select all; Apply stores `groupBy = keys` and resets collapsed groups.

- **Allowed fields:** every listed (visible, non-internal) column of any type; no type restriction in the dialog or the server (BE: any <= 80-char names, max 5). Active keys are filtered to columns that exist (`groupKeys`, SmartView.jsx:267).
- **Levels:** multi-level. `groupTree(rows, keys, sumKey)` nests: first key outer (`engine:232`).
- **Group order:** by first appearance in the (already filtered, sorted) rows, NOT sorted by name or count (`groupRows` uses a Map in row order, engine:216-228). So the sort setting orders groups only through the rows' order. A blank value forms the group `"(empty)"`. Keys are `String(value)`.
- **Header rendering** (SmartView.jsx:761-764): a full-width button (height 48) with chevron (`expand_more` open / `chevron_right` closed), the group label in bold, the row count (`toLocaleString`), and, if the table has a measure column, a total of that one column (`em`, `maximumFractionDigits: 2`). `sumKey = listed.find(isMeasure)?.key`: **the first measure column** (a number column that is not an id/year/code/age/phone, rule `isMeasure`), the same for every level; a sub-group shows its own sum. Indentation: `14 + depth * 22` px. The count is the rows inside (all descendants), not child groups.
- **Collapse:** click toggles (`closed[path]`, `path` = parent path + label concatenated, e.g. `"DirectIntra State"`); all groups start open; state is not saved and is cleared on Apply or a view switch. Closed group hides children/rows (`flattenTree`).
- **Interaction:** filters and search apply first, then sort, then grouping on what is left (`rows` -> `groupTree`). Totals/KPIs use the filtered rows. Download uses the plain filtered/sorted rows `outRows` (not the group structure; no group headers in a file).
- **Stored:** `view.groupBy` (list; a legacy single string is read as a one-item list). Compare engine vectors: `group`, `aggregate` sections are unchanged and match the web.

---

## e) MORE MENU, KPI / charts, Customize, bottom icons

Options menu items in order (SmartView.jsx:857-873); exact labels are the web's:
| Item (label) | Action and state |
|---|---|
| **Columns** | opens Select Fields (c) |
| **Wrap text (fit every record to its text)** / **Stop wrapping text** | toggles `wrapAll` (screen state only); hidden in the card (narrow) layout (`asCards`, <= 600 px) |
| **Reset column and record sizes** | shown only when something was moved or sized: `!isDefaultLayout(order, widths) || wrapAll || autoRows.size || Object.keys(tall).length`; clears `order`, `widths`, `tall`, `wrapAll`, `autoRows`, `measured` (not saved until Save view) |
| **Group** / **Group (N)** | opens Group By |
| **Create view** | a.4 |
| **Remove view** | a.4 |
| Share / Stop sharing this view | hidden (switch off) |
| Delete file | only the owner's saved spreadsheet file |
| **Hide KPI** / **Show KPI** / **No KPI** | toggles `kpis` (saved in views); **disabled and labelled "No KPI" when `cards.length === 0`** |
| **Hide charts** / **Show charts** / **No charts** | toggles `charts`; disabled "No charts" when nothing to draw |
| **Parameters** | only when the source has parameters (APIs) |
| **Customize** | only when `configurable && canConfigure` (SmartView.jsx:872); opens the Customize dialog |

**When "No KPI" / "No charts" appear** (SmartView.jsx:313-324, 647): for a structure, API or file (configurable: `structure, api, file, work`) the cards and charts are **exactly those set up in Customize** (`definedCards(rows, cols, attrs.kpis)`, `definedCharts(rows, cols, attrs.charts)`), none until then, so "No KPI"/"No charts" show until the person defines some. A definition naming a column the source lacks is skipped. Only the inbox lists (approvals, reminders) work cards out from the rows (`kpiCards`, `chartableColumns`).

### Customize ("Customize View", `SV:SvConfigure.jsx`)
Only two tabs are on: **Cards** and **Charts** (Columns and Links editors exist but are commented out, `TABS` line 17-21). Stored per person (`smartview.attrs.save`, private to the person and source, even admins cannot read it) and, for holders of `smartview.configure`, optionally as the organisation default (`admin.smartview.save`); everybody without their own sees the default. `smartview.attrs {kind,name}` -> `{attrs|null, canConfigure:true, mine, canDefault}`. `smartview.attrs.save {kind, name, metadata, hyperlinks, kpis, charts}` -> `{attrs}`. `smartview.attrs.delete` returns to the default. Allowed kinds for attrs on the server: `structure`, `api` (+ `file`, `work` personal, `sd_smartview.erl:20`).
- KPI definition: `{caption, agg, column}`; `agg` in `sum, avg, min, max, count`; `count` may leave `column` empty (counts rows) else a column is needed. Card shape computed: `{id:"kpi:<i>", label, value, decimals (agg != count), tone: cycle brand/green/waiting, icon: functions/avg_pace/arrow_downward/arrow_upward/tag}` (smartViewAttrs.js:92-97).
- Chart definition: `{caption, chart, groupBy, agg, column}`; `chart` one of 13: `line, bar, stacked-bar, column, stacked-column, stacked-percentage-column, area, pie, semi-donut, donut, stacked-group-column, scatter-plot, funnel`. Computed (`definedChart`): groups of `groupBy` with aggregate of `column`, biggest first (date column in date order), **at most 40 groups** (`MAX_DISTINCT_FOR_CHART`), `more` = groups cut; subtitle "SUM Net by Channel". Web maps to the report as `pie/donut/semi-donut -> donut`, `line/area/scatter-plot -> line`, others bars (SmartView.jsx:57).
- Limits: 30 cards and 30 charts (`MAX_CARDS`), 200 fields, 50 links, 10 mappings per link (`sd_smartview.erl:42-46`). Validation messages: "KPIs, line 2: choose an aggregate function.", "Charts, line 2: choose what to group by." etc. (`problemWith`).
- Computed on the client from the rows on screen (after filter/search); "Hide KPI/charts" is a view flag. No server computation.
- A definition does not hold the layout of the view; `kpis`/`charts` flags in a view only say whether the row/sections show.

### Download (bottom icon, disabled with no rows)
Items: **Excel** (`.xlsx`, real numbers and dates), **CSV** (`.csv`, UTF-8 with BOM, CRLF, quoted cells), **Google Sheets** (copies a tab-separated table and opens a new sheet; falls back to Excel when too big), then **PDF / PowerPoint / Image** reports (12 rows a page, <= 20 pages PDF, 6 slides; Excel has all rows). Rules: the rows are `outRows` = the filtered and sorted rows, **only the ticked rows if any are ticked** (`rows.filter(r => picked.has(r.__i))`); columns are `shown` (visible columns in view order; **hidden fields are included only when "Show hidden fields" is on and the column is shown**); `file` cells export the file addresses (URLs); dates as dates in Excel, plain text in CSV; blank -> empty. No group headers; no record number. (SmartView.jsx:458-487, engine:403-436.) Mobile should not copy the web's browser download; just note the rules.

---

## f) Local file mode and APIs: out of scope for mobile now

- **"Open an Excel or CSV file"** (`SvOpenFile.jsx`, `svFileSource.js`): a person picks or drops a `.xlsx`/`.csv` (limit `MAX_FILE_BYTES`); read in the browser only; the table is a `kind:"file"` source in memory (`loadSource` returns `source.rows` directly, smartViewSources.js:303). **Save to my files** (`smartview.sheet.save {caption, columns:[{name,type}], rows}` -> `{name, caption, added, failed}`) turns it into a structure the person owns; **Delete file** `smartview.sheet.delete {name}`. Views for a file are filed under its file name with kind `file`. **Out of scope.**
- **API sources** (`kind:"api"`): `api.list`, `api.run {name, values, limit:500, refresh?}` (rate limit 120 per 60 s per person), columns/rows/total/truncated/cache info; saved views and set-up use kind `api`. Parameters dialog under Options. Already in the existing Smart View docs. Not part of this task.
- Axpert data sources (`datasource`) and Connectum lists (`list`): **on hold** in the code (`SMART_VIEW_KINDS = ["structure","api"]`, `sd_smartview.erl:35-36`): do not build.

---

## g) CLIENT vs SERVER
| Feature | Where | Commands |
|---|---|---|
| Search, filters, sort, group, totals, KPI cards, charts, column order, widths, wrap, row heights, download files | **client only**, over rows already read | none |
| Rows of a structure | server (paged) | `submissions.list {tstruct, limit:100 first then 500, offset, fetch:true, withDetails:true}` up to **10,000** records (`MAX_ROWS`), plus `records.mine` pages (200) for records tagged to the person (smartViewSources.js:77-112) |
| Saved views (own + shared), read/save/remove | server | `smartview.views`, `smartview.views.save` (whole list) |
| Publish/unpublish for everyone | server, no UI | `admin.smartview.view.publish/unpublish` |
| Share with people/groups | server, UI hidden | `smartview.share/shares/unshare/targets`, `smartview.view.unshare` |
| Cards and charts set-up | server (definition) + client (numbers) | `smartview.attrs`, `.attrs.save`, `.attrs.delete`, `admin.smartview.save/delete` |
| Show hidden fields | server (definition read) + client | `tstruct.user.get` (then a full table re-read) |
| Live follow | server events | events `submissions_changed`, `submission_approved`, `submission_rejected`, `ticket_assigned`, `resync` -> the web re-reads the whole table quietly **once per event** |
| Server-side filter/sort/group/aggregate | **does not exist** | `records.list` is the only server search and the Smart View does not use it |

---

## h) PHONE-RELEVANT RISKS
1. **Hidden-field exposure.** Values of hidden fields are in every `submissions.list` reply to everybody who may read the record, and `tstruct.user.get` sends them (with `default`) to anybody who can open the form. A phone should not draw them silently: either follow the web's "off until turned on" switch or wait for the owner's answer (question 1).
2. **Overwrite of the saved-view list by two devices.** Whole-list replace, no revision. On the phone: always re-read (`smartview.views`) immediately before a save, apply the one change to the fresh list and save (still a race of seconds), never save a stale list, and show a notice when the re-read list differs from what the screen had. A server `rev` would end this (question 2).
3. **Rate limits.** 30 commands per 10 s per connection (`rate_limited`; web retries 1 s x (n+1), 4 times). The web re-reads a whole table (up to 20 pages) on every event; on a phone coalesce events (debounce) and re-read only while the Smart View is open. Views save is one command; do not save on every change (the web saves only on explicit Save/Create/Remove).
4. **Limits to enforce on the phone:** 20 named views (+ Default); name 1-40, no control characters; <= 30 filters; <= 5 group levels; <= 300 hidden/order keys; widths 48-1200 (web UI 64-800); view <= 16 KB; 10,000 rows; 40 chart groups.
5. **Silent name replacement and unsaved-state loss** in the web (a duplicate name replaces the older view; switching tabs drops changes). Decide on the phone whether to copy that or warn.
6. **Default tab quirk** (a.3) must not be copied.
7. Existing stored views may name columns the structure no longer has, internal `#`, or `+key` for quiet columns; load them tolerantly (`viewState`: drops internal keys; unknown keys are ignored on screen).

---

## Disagreements: docs vs code (the code wins)

Checked `reference/SMART_VIEW.md` (the synced doc, = `connectum/docs/SMART_VIEW.md` on dev) and `MOBILE_SMART_VIEW.md` against the code:
1. **Hidden fields:** doc paragraph at line 37 ("not in the Smart view for anyone, creator and administrators included") contradicts line 112 and the code: anybody who can open a structure may turn on "Show hidden fields" (SmartView.jsx:187). Already item 1 of MOBILE_SMART_VIEW 7.4.
2. **Menu labels:** doc says "Configure" and "Reset column layout" and "Hide KPI / Hide charts (or No KPI / No charts)"; code says **"Customize"**, **"Reset column and record sizes"**, plus **"Show KPI"** / **"Show charts"** when off and **"Wrap text (fit every record to its text)"** / **"Stop wrapping text"** (SmartView.jsx:861-872).
3. **Saved views location for the Inbox lists:** doc says "Sources that cannot be configured (the Inbox lists) keep their views on the device"; the code and the doc's own "Where saved views live" put them on the server (kinds `approvals`, `reminders`, `work`; BE:65). svViews.js:3-4 header repeats the older "stay on the device" claim.
4. **"Share with everyone" / "Update shared view" / "Stop sharing" in the menu** (doc line 66): not in the menu; only the hidden per-person Share, and no UI calls `admin.smartview.view.publish`.
5. **Wrap/record heights in views:** doc says the layout is kept in views; only `order` and `widths` are. Wrap and record heights are never stored.
6. **"Remove view" for a shared view:** not offered (`!sharedNow`); doc does not say.
7. **Column order of a structure's table (changed since the engine vectors were made):** the current code puts the key field first, the internal `#` column (`internal: true, hide: true`), then the structure's other fields, the status field (as quiet), then `With`/`#progress` (quiet), `By`, `On` ("Submitted"), `Status` ("Approval" or "Status", quiet). The vectors file in `test/fixtures/smart_view/engine/vectors.json` (made 16 Nov) still has `By`, `On`, `Status` first and no `#` column. Sections `structureCells` and `structureCellsDisplayed` of a fresh run differ from our copy; `formatCell` differs only in locale (en-US `Nov 12, 2026` against `12 Nov 2026`; a vector-generation environment difference, not an engine change). **A BE sync of the vectors (and a check of `SmartViewColumns`) is needed.** All other sections (`toTime`, `inferType`, `filters`, `sort`, `group`, `aggregate`, `csv`, `chips`, `datePresets`, `captureView`, `definedCards`, `definedChart`, `structureColumnTypes`) match exactly.
8. **Server-side name check:** the "Default View" name refusal is client-only.
