# Form logic: how the web runs it, and what the mobile app must match

Read-only study. Nothing was run, built or sent. Source: web repo `~/Development/Axi-apps` (git root; the app is the `connectum/` folder in it), read from `origin/main` at `36a6c431` (2026-11-02) via `git show`/`git grep` after a `git fetch`; the local checkout is 218 commits behind, so it was not used. Mobile code read from this repo. File paths below are inside `connectum/` unless stated. "Server" means `connectum-backend/src/...`.

Two corrections to older handoff docs, found on the way:
- `forms.md` says there is no Yes/No type and `docs/LITE_TSTRUCT.md` does not exist. On `origin/main` there IS a `toggle` field type (saved as the text `Yes`/`No`, `docs/FIELD_TOGGLE_AND_MULTI_SELECT.md`, `?FIELD_TYPES` in `sd_config.erl:45-47`) and `connectum-backend/docs/LITE_TSTRUCT.md` exists (but is an old 28 Sep note: 12 types, 5 actions; use it for nothing).
- `forms.md` section 0 says the chat form is the "lite tstruct" schema (`name`, `wholenumber`). Confirmed: the chat form is `chat-app/features/connectumChat/components/modals/SmartStructureModal.jsx`. The studio (`form-studio`) uses `id`/`wholeNumber` and shares the pure logic modules, which tolerate both spellings.

---

## 1. Where the web gets the parser

- **Bundled, not served.** `form-studio/src/core/axExpParser.js`, one ES module, imported by relative path: `import { RegisterVariable, Evaluate } from './axExpParser.js'` in `form-studio/src/core/fieldRule.js:4`. Nothing else imports it (only `tests/frontend/axFunctions.test.mjs:5`). The chat app reaches it through `fieldRule.js`/`fieldCalc.js` (`SmartStructureModal.jsx:42` imports `form-studio/src/core/fieldCalc.js` by relative path; `@tstruct/core/*` is a Vite alias to `form-studio/src/core`). Vite bundles it into the browser build.
- **Diff against `reference/parser/AxExpReactParser.jsx`: byte-identical** (886 lines, `diff` empty). Only the file name differs (`.js` vs `.jsx`). `docs/FIELD_RULES.md` says the same: "the parser supplied as `AxExpReactParser.jsx`, unchanged". Last touched by the folder rename commit `223da258` (2026-10-31). No version string exists in the file or the ReadMe; treat the git blob as the version, and pin a hash of the mobile copy.
- The web never uses: `GetValue` export, `SetDateFormat`, the `dateFormat` export, or the `context.dateFormat` override. The parser's default `dd/mm/yyyy` is what runs (see 6). `RegVar(...)` is in the function catalog (`axFunctions.js:114`) but no form code calls it; it is only available inside expressions.

## 2. Orchestration

### 2.1 The array is rebuilt every time (no persistent `reactFieldArray`)
`evaluateExpression(expr, values)` in `form-studio/src/core/fieldRule.js:55-75` is the only caller of the parser. Per call it:
1. starts with `arr = []`;
2. registers the signed-in person's globals, each twice, at `rno` 1: plain name and `global_<name>` (`GLOBALS`, set by `setRuleGlobals`; see 2.6);
3. registers every form value: a scalar goes in at `rno` **1** (all non-grid fields, and "variables"); a grid section (array of row objects) is registered cell by cell, **row i at `rno` i+1 (1-based)**, by the bare column name (no section prefix);
4. calls `Evaluate(text, '__rule', 1, { reactFieldArray: arr })` and returns the raw result (`null` if it throws).

`put()` skips names that do not match `/^[A-Za-z_]\w*$/` or contain `__`. `RegisterVariable` is used only to build this throwaway array; results are NOT written back with it.

**Types of `v`** (`forParser`, `fieldRule.js:43-50`): `undefined/null` -> `''`; array -> comma-joined text; object (location, payment) -> `''` (left out); string `yyyy-mm-dd` -> `dd/mm/yyyy`; everything else as is. The editor holds numbers as text (`"12"`), so `v` is mostly strings; the parser's `normalizeValue` turns numeric text into a Number and **empty text into 0** (which is why calc guards empty inputs, 2.3). Booleans are not produced. A toggle is the text `Yes`/`No`.

**Row convention:** the evaluation row is always 1 for an ordinary field. A grid cell's rule/calc does NOT use `rno` = its row: the cell's own row object is spread into the flat context (`rowContext = {...values, ...row}`, `formEngine.js:~78`) and registered at `rno` 1, after the grid arrays (which also registered every row). So inside a cell, `qty*price` reads the row's own cells because they are the scalars at rno 1. Side effect to confirm (question 6): in a cell rule, `Total(qty)` sees row 1 replaced by the current row's value.

### 2.2 When it runs
| Moment | What runs | File |
|---|---|---|
| Form opens (new or edit) | Calc pass over all fields and rows (effect depends on `values`, so it fires after the initial `setValues`) | `SmartStructureModal.jsx:683-686` |
| Any value change, row add/delete, fill from selection/fetch/inherit | Same effect again (React effect `[values, tstruct, personVersion]`); the engine returns the same object when nothing moves, so no loop | same |
| Person's details arrive (`globals.list`/`globals.resolve`) | `personVersion` changes, calc pass again | `ruleGlobals.js`, `useRuleGlobals` |
| Blur | **Nothing.** Rules are not checked on blur or on change; field errors are only cleared when the person edits (`setFieldErrors`) | `setValue`, `setCell` |
| Submit | `requiredErrors(tstruct, values)` = required + rule + phone per visible field, then grid errors; any error blocks the submit | `formEngine.js:requiredErrors`, `SmartStructureModal.jsx:807` |

So: **calc = continuous, rule = on submit only** (both client-side only; the server stores `rule` and `calc` but never evaluates them: `FIELD_RULES.md`, `forms.md` section 5).

### 2.3 Calculated fields (`calc`), `form-studio/src/core/fieldCalc.js`
- Which fields: type in `text, wholenumber, number, date, list` and not `multi` (`canCalc`, line 18). Never required/typed-in: the form shows it locked (`isRO`, `SmartStructureModal.jsx:~528`).
- **Dependency order is by repetition, not a sorted graph.** `applyCalcs` (line ~140) loops over the calc fields in definition order, up to `calcs.length + 1` passes, until nothing changed ("calc of calc" settles; real cycles stop after the limit with no meaningful value). `applyFormCalcs` (line ~185) repeats ordinary fields -> each grid row -> again, up to 4 outer passes, so `Total(lineTotal)` outside the grid sees a column just worked out.
- **Empty guard:** if any field the expression reads (`usedFields`: words equal to a field id, not followed by `(`, not inside quotes, not itself) is empty, the result is `''`, not 0.
- **Bare-name shortcut:** an expression that is only a name (`firstName`, `global_employeeCode`) copies the text as is without the parser (keeps `0012`, 18-digit codes).
- **Fit to the field** (`fitCalc`): text as is; booleans -> `''` (except text -> `"true"`); number must be finite (whole number must be an integer) else `''`; date `d/m/yyyy` -> `yyyy-mm-dd` (anything else not already `yyyy-mm-dd` -> `''`); list must match an option case-insensitively, stored with the option's own spelling, else `''`.
- **Memory (cache):** answers cached per (field, expression) under the values of every word in the expression + today's date; skipped for expressions containing `time(`. Pure performance; mobile may skip it, but must keep `Total(...)` correct when rows change.
- **Grid rows** (`applyRowCalcs`): row calcs see the row's own cells + the form's non-grid values; not other grids. Outside-grid fields see whole columns by name.
- **Written back** by `setValues` replacement of `values[fieldName]` (not `RegisterVariable`). `Evaluate`'s numeric `Infinity/NaN` becomes `0` inside the parser (so `x/0` gives 0, not an error).

### 2.4 Hidden fields
`isMadeFor(f)` = has `calc`, `fetch`, or type `autogenerate`/`fill` (`formEngine.js:~118`). A field hidden by `hidden: true` or by a failed condition is not shown and not required. **Hidden + made-for + condition holds: still calculated and still SENT** (`isSentField`, `buildSubmission`). A hidden ordinary field is not sent. Condition-hidden fields are not sent either. (Mobile today never sends a `hidden` field; see gaps.)

### 2.5 Errors and the silent `''`
`Evaluate` wraps everything in try/catch and returns `''` for: empty expression, unknown variable/function, bad syntax, bad date, unsupported character. Consequences in the web:
- **rule:** `''`/non-boolean-looking result -> `ruleResult` null = "no opinion", never blocks (`fieldRule.js:ruleResult`). True/valid: `true`, non-zero number, any text except `false, f, 0, no, n`. Failure message: `rule.message` or `"<caption> is not valid"`.
- **calc:** `''` -> `fitCalc` -> `''` -> the field is emptied. A broken formula and a legitimately empty answer look the same.
- Unknown variable: not an error to the person; also `''`. This is why `withBlanks(ids, values)` is called before a rule is checked (every field id present, blank), so `lastPunchOut=""` can be read.
- Empty values are not rule-checked at all (`fieldRuleError` returns null for empty); that is what `required` is for.

### 2.6 Globals (`global_<name>`)
`ruleGlobals.js`: once per sign-in the form calls `globals.list` (`values` = what this person has, `attributes`) then `globals.resolve` (slower, includes ones a data source supplies) and registers them via `setRuleGlobals` (only string/number/boolean/null values with `/^[A-Za-z_]\w*$/` keys). Names: `global_fullName, username, email, mobile, employeeCode, category, affiliate, branch, department, designation, reportingManager, city, country, pin`, custom globals, and attribute fields (`global_branchRegion` ...). Both `employeeCode` and `global_employeeCode` work; a field of the form with the same plain name wins; in a field's own calc a word equal to its own id means the global. A rule that needs globals not yet known cannot be read -> no opinion.

### 2.7 Grid functions
`Total, GetRowCount, GetValue, Sum, SumTill, GetRow, GetMin/GetMax, GetAllValues` read the array by name across all `rno` (parser `evaluateFunction`). They work because step 3 of 2.1 registered every grid cell. `Total(qty)` takes a bare identifier first arg; the others take the name in quotes: `GetRowCount("lineqty")` (`FIELD_RULES.md`). `ActiveRow` is a built-in variable = the evaluation row (always 1 in the web, see 2.1).

### 2.8 `regvar`
Parser feature `RegVar(name, type, value)` stores `name:type:value` in a module-level list that survives for the engine's lifetime and is read by `resolveVariable` after field lookup (typed prefixes `n:`/`s:`/`d:`). The web form code never calls it. It is session-global state shared across forms: **a mobile host that reuses one engine across forms would leak it**; create the engine per form or reload the module (question 7).

### 2.9 Other client-side fill logic (not the parser)
- **`fetch`** (`useFetchFill.js` + `fetchFill.js`): single-value field that fills itself from the first matching row of another form (`fetch.type: "query"`) or a Get API (`"api"`). Asks `datasource.run {tstruct, scope, field, values, limit:1}` 250 ms after a dependency changes; waits while a param field is empty; never overwrites what the person typed (only replaces an empty value or the value the fetch itself put there, tracked in `last`); an API answer also fills sibling fields whose id/caption matches a node (names compared without case, spaces, `_`).
- **`fill` (Auto Fill)**: copies `item[sourceProp]` from the chosen item of `fillFrom` when the selection changes (`setValue`/`setCell`), same row for grids.
- **`inherit`** (`useInherit.js`, `form.inherit {tstruct, scope, values}`): a field starts from the record chosen in a dropdown and stays locked until an Override switch is Yes. Not read in depth (question 9).
- **Starting values** (`defaults.js`, `initialValues`): see 3.

## 3. Field properties

Definition keys come from `tstruct.get` / `tstruct.user.get` (`sd_config.erl`, `sd_config_forms.erl`). "Mobile today" cites `lib/`.

Definition level: `name, caption, description, allowForward, sections[], fields[], registers{subject}, keyField, readableBy, saveToDb, axpert, fetchRules, approval/notify` (last ones not needed to render). Limits: 100 fields, name `^[A-Za-z][A-Za-z0-9_]{0,39}$`.

### Common
| Property | Meaning / example | Mobile today |
|---|---|---|
| `type` | `text date time wholenumber number email url mobile location list selection fill barcode autogenerate slot payment file toggle` (`?FIELD_TYPES`) | supports `text email url mobile wholenumber number date time list location autogenerate` (`form_rules.dart:14-26`). Rest unsupported |
| `caption`, `name`, `section` | label, id, section name or null | yes (`form_definition.dart`) |
| `required` | `true`; never for autogenerate; meaningless for toggle | yes. A form with a required unsupported field blocks sending (`form_controller.dart:127`), except when it has `calc` |
| `condition` | `{field,op,value}` / `{all:[]}` / `{any:[]}`, ops `eq ne gt lt gte lte in between notempty` (array value: eq=includes) | yes, all ops (`FormRules.matches`), field + section, grid row first. Slight differences: `_equals` is case-insensitive text for strings; web `eq` is `cmp===0 && non-empty` (text compare is case-SENSITIVE). See gap table |
| `hidden` | switched off for the person; server keeps default/saved | hides and never sends (`isVisible`). Web still sends a hidden `calc/fetch/autogenerate/fill` field |
| `readOnly` | locked; new record gets `default`; edit keeps saved | yes (`form_field_row.dart:75`) |
| `default` | fixed starting value for text, email, url, mobile, wholenumber, number, date, time, single list | yes (`startingValue`) |
| `defaultNow` | `false` turns off today/now/location start | date, time yes; location start (GPS) no |
| `rule` | `{expr, message}`, max 500/200 chars. Example `{"expr":"Length(phone)=10","message":"Ten digits please"}` | **missing** (field kept in `raw`, ignored) |
| `calc` | `{expr}`. Example `IIF(age>18,"Adult","Minor")` | **missing**; only shown locked (`hasCalc`) |
| `fetch` | `{type:"query"\|"api", form, valueField, labelField, where, sort, params:{p:{field}}}` | **missing** |
| `min`, `max` | numbers: numeric; date/time: strings `YYYY-MM-DD`/`HH:MM` | yes (`_range`, date) ; time min/max not checked |
| `multiline`, `rich` | text box size / rich | multiline yes; rich no |
| `unique`, `keyField` | duplicates refused by the server (`duplicate`) | server-only; mobile shows the server message (error mapping `describe`) |
| `axpertField`, `axpertDc` | Axpert mapping | ignore |

### Type-specific
| Property | Meaning | Mobile today |
|---|---|---|
| list `options` | `["A","B"]` | yes |
| list `source` | `branches departments designations users people categories affiliates roles` or `isource:<name>` | partly: fetched via `isource.values`, `users.search`, `cfg.lookups` (`form_options_repository.dart:193-215`). The server also sends the resolved names as `options` for sourced fields (`sd_config.erl:514`); mobile ignores them |
| list `multi`, `allowAll`, `where`, `dependsOn {field,prop}`, `prefill`, `subject`, `involve`, `optionLabels`, `optionProps` | multi pick (max 50), "All", narrow a people list, narrow by another field (`shownChoices`), start on a detail of the person, who the record is about | `multi` yes; `allowAll`, `where`, `dependsOn`, `prefill`, `optionLabels`, `subject` no |
| selection `api` / `source {type: datasource\|api\|query, name, params, valueColumn, labelColumn}`, `allowTyping`, `multi` | options from a data source/API/other form; server stores `labels[name]` | **missing** |
| fill `fillFrom`, `sourceProp` | read-only copy from a selection or a profile key | **missing** |
| mobile `countryPicker`, `defaultCountry`, `withCountryCode` | phone UI | no; validated only as 6-15 digits |
| location | `{lat,lng,address?}`; start on GPS | typed "lat, lng" only, no capture/map |
| toggle `default:"Yes"` | switch, saved `Yes`/`No` | **missing** |
| file (`multi`), payment (`amount, currency, methods`), slot (`of`), barcode | upload, amount+method+status, booking slot, scan | **missing** |
| autogenerate `prefix suffix digits start resetEvery` | never sent; server fills | yes (not sent) |
| date format | stored `yyyy-mm-dd` | yes |

### Sections
`{name, caption, condition, grid}`; grid -> rows `values[section] = [ {...} ]` (max 200; empty row = `{}`; not allowed inside: slot, payment, file, subject/involve lists). Mobile: grid editor exists. Mobile omits the whole grid key when every row is empty and, in that case, sends no row at all; web sends every row in place (empty rows as `{}`) so server error indexes match (`buildSubmission`).

## 4. Validation

| Check | Client (web) | Server (authoritative) | Mobile today |
|---|---|---|---|
| required | visible fields only; "This field is required." | same message (`sd_config_values.erl:295`); hidden fields dropped | yes |
| type/shape | number ("must be a number" / whole), email regex `^[^\s@]+@[^\s@]+\.[^\s@]+$`, url `^https?://`, mobile via libphonenumber-js (default country), `payment`, `location` | "Enter a whole number." "Enter a number." "Enter a valid email address." "Enter a valid http(s) URL." "Enter a valid mobile number." "Use the format YYYY-MM-DD." "That date doesn't exist." "Use the format HH:MM." | similar with own wording; mobile = digits 6-15 only |
| range | "must be at least N" etc. | "Must be at least N." / "Must be at most N." / "Must be on or after DATE." | yes |
| list membership | picker | "Choose from the list." / "That is not one of the choices on offer." / `Choose at most N.` | picker |
| `rule` | `fieldRuleError` per field and per grid cell, on submit | **not evaluated** (API submissions bypass) | missing |
| `calc` | continuous | not evaluated | missing |
| uniqueness / key | none | `duplicate` error (keyField/unique) | server message only |
| length | text <= 5000 | "Too long (max 5000 characters)." | yes |
| grid | "Add at most 200 rows." per-cell required + rules | keys `items` and `items.1.item` (row index from 0) | yes |
| conditions/read-only/dependsOn | UI | rechecked; read-only keeps saved value; sourced values rechecked against the list the person may see | server only |

**When errors show:** web checks all on submit (a second click); field errors clear on edit; server errors set `fieldErrors` from `error.details.fields` when `error.code == "invalid_values"`; other codes (`duplicate`, `forbidden`, `invalid`, `submission_locked`, `not_found`) show the server message as a banner, and a "Retry" appears when the options source was down (`SmartStructureModal.jsx:826-834`, `1097-1100`). Submit is blocked by any client error. Server shape: `{ok:false,error:{code:"invalid_values",message:"Some fields need attention.",details:{fields:{"amount":"Enter a number.","items.1.item":"This field is required."}}}}`. Mobile: `serverErrors` + `describe` already match this.

## 5. Dropdowns and data sources

| Need | Call | Parameters -> reply | Notes |
|---|---|---|---|
| Static list | none | `field.options` | |
| Org list (`source`) | server resolves into `options` at `tstruct.get`; also `isource.values {key}`, `isource.catalog`, `users.search`, `cfg.lookups` | | `where` narrows (every property equals, ignoring case); `myBranch/myDepartment` limits |
| People narrowed by another field | none (client) | `optionProps` per person: text or list; `shownChoices(field, values)` | `dependsOn {field, prop}`: nothing offered until the other field is filled; values that no longer fit are dropped on change (one value cleared, multi keeps those that fit); server re-checks |
| Selection from a form/datasource/API | `datasource.run {tstruct, scope:"admin"\|"user", field, values:{<other field>:<plain value>}, limit:500, search?}` (`sd_cmds_forms.erl:407`, `sd_config:form_options/2`) | `{columns, rows, truncated}`; `rowsToItems` -> `[{value,label,raw}]` (value column default first, label default second) | Whoever may open the form may read what its field offers; only mapped params reach the source. Standalone (no form): `datasource.run {name, values, limit}` and `api.run` (120/min) |
| Cascading | the same call, again | `sourceParams`: params `{p:{field:<id>}}` taken from other fields; `missing` -> `{waiting:[names]}` (list shows waiting); `{value:x}` = fixed; `optional` = empty ok. `sourceKey` changes exactly when params change -> reload | a chosen value that is no longer offered is cleared (not while narrowed by typing); inherit-locked values are kept |
| Search-as-you-type | same call with `search` | 300 ms debounce, `query` sources only (the server narrows) | "keep" the chosen item on the list while narrowed |
| Paging | none | one page of up to 500 rows; `truncated:true` says more exist; UI narrows by typing instead of paging | |
| Caching | none beyond in-memory | web has none; reloaded when the key changes | |
| Multi-select | `multi:true`, max 50 | list of text values; server rechecks every item | no Auto Fill from multi |
| Fetch/Auto Fill from a record | `datasource.run` with `limit:1`; `rows[0].record` for an API (all nodes) | see 2.9 | `form.inherit` for inherit |
| Labels | server stores `labels[name]` (and `"section.row.field"` for grids) beside values | used to display | |
| Slots | `avail.slots {user, days:14}` | for `slot` fields | |

**Offline:** choices that could be cached per form+field+param key: static options and org lists (`isource.values`, `users`), and the last `datasource.run` result per `sourceKey`. Nothing about cascading or `fetch` can be computed offline (needs the server); a form with such fields opened offline must either use the cached last result or show the field as needing a connection (decision for the user, question 10).

## 6. Formats
- **Date:** stored and sent `yyyy-mm-dd` (server rejects other shapes). Passed to the parser as `dd/mm/yyyy`. **There is no organisation or user date-format setting in the web or in `sd_globals.erl`/`forms/`** (grep: none). Parser default `dd/mm/yyyy` is never changed (`SetDateFormat` unused). `chat_arm.erl` has `AxClient_dateformat` `MM/dd/yyyy`/`yyyy-MM-dd` only for the Axpert (ARM) connection; unrelated to the chat forms. Display uses the browser locale (`toLocaleDateString(undefined, …)`); `formatValue` shows the stored text.
- **Time:** `HH:MM` (or `HH:MM:SS`), 24h; `currentTimeValue` for "now".
- **Numbers/amounts:** no locale formatting in forms; `number`/`wholenumber` held as text, sent as numbers; `payment` is `{amount, status, method?}` with a `currency` label only. Parser functions `InsertCommas`, `FormatAmount`, `FormatAccAmount` use `en-IN` (lakh grouping) or `en-US`; `AmtWord` is Indian ("Rupees ... Only", Lakh/Crore) hard-coded.
- **Mobile numbers:** stored E.164-like via `toStored` (`+`, country code, digits).
- **Time zone:** the parser's `Date()` returns the UTC date (uses `getUTC*`), `Time()` returns local time; see 8.

## 7. Gap table (web behaviour vs this app)

| # | Behaviour | Status | Size |
|---|---|---|---|
| 1 | Embedded JS engine running the unchanged parser file | missing | large (engine choice, host prelude, bridge) |
| 2 | Build `reactFieldArray` as in 2.1 (globals, scalars rno 1, grid cells rno i+1) | missing | medium |
| 3 | `calc` (continuous, fixpoint, empty guard, fit, bare-name copy, grid rows, outside-grid columns) | missing | large |
| 4 | `rule` on fields and grid cells at submit, `withBlanks`, `ruleResult` | missing | medium |
| 5 | Globals: `globals.list` + `globals.resolve`, `global_` names | missing | small |
| 6 | Conditions: ops/values | done; fix `eq` case-sensitivity and empty handling to match `evalCondition` | small |
| 7 | Hidden handling: send hidden `calc/fetch/autogenerate/fill` fields when counted | missing (mobile drops all hidden) | small |
| 8 | Types: toggle | missing | small |
| 9 | Types: selection (datasource/api/query), fill, `fetch` (`datasource.run`) | missing | large |
| 10 | List `dependsOn`, `where`, `optionProps`, `optionLabels`, `prefill`, `allowAll` | missing (list sourced via other calls) | medium |
| 11 | Types: file, payment, slot, barcode | missing | large each |
| 12 | Location capture (GPS) and `defaultNow` start; address | partly (typed only) | medium |
| 13 | Mobile phone validation (libphonenumber) and `countryPicker` | partly (digit count) | medium |
| 14 | Required/range/type messages | done (wording differs from server; fine) | none |
| 15 | Server error mapping `details.fields` incl. `items.1.item` | done | none |
| 16 | Grid: all rows in place; empty row `{}`; blank-row `__p` "form-supplied" detection | partly (sends none if all empty) | small |
| 17 | `unique`/`keyField` errors | done through server message | none |
| 18 | Reload on `tstructs_changed` while a form is open | missing | small |
| 19 | Outbox for form saves, one `cid`/`meta.clientId` | done (per CLAUDE.md) | none |
| 20 | Offline form open with cached definition; cached choices | partly | medium |
| 21 | `inherit` (`form.inherit`) | missing, not studied in depth | medium |
| 22 | Form layout (`formlayout.get/save`: per-person arrangement) | missing; optional | small |
| 23 | Time `min`/`max` check | missing | small |
| 24 | Start of a new row / `isUntouched` | partly | small |

## 8. Parser runtime needs (host prelude)

Loaded as a plain script: the file has `export let dateFormat` and three `export function`s; a script host must strip `export` or load it as an ES module. Syntax used: ES2022 (`.at(-1)` in `infixToPostfix`, `**`, `?.`, `??`, optional catch binding `catch {`, spread, destructuring, `Array.from`, `Uint8Array.from`, `padStart/padEnd`, `Number.EPSILON`, `Set`, regex lookahead `(?=...)`). No timers, no `console`, no `Math.random`, no network.

| API | Used by (function names, `evaluateFunction` cases) | If missing |
|---|---|---|
| `TextEncoder` | `Encode` (`encodeBase64`), `ConvertMD5` (`md5`) | those throw -> `''` |
| `TextDecoder` | `Decode` (`decodeBase64`) | throws -> `''` |
| `atob`, `btoa` | `Encode`, `Decode` | throws -> `''` |
| `Intl.NumberFormat('en-IN'/'en-US', {useGrouping, minimumFractionDigits, maximumFractionDigits})` | `InsertCommas`, `FormatAmount`, `FormatAccAmount` (via `formatFormulaAmount`) | throws -> `''`. **QuickJS has no `Intl`.** Needs lakh grouping `1,23,456.00` for `en-IN` |
| `Date.prototype.toLocaleString('en', {month:'long', timeZone:'UTC'})` | `CMonthYear` | wrong or throws if the engine ignores options/`timeZone` |
| `Date.prototype.toTimeString()` | `Time` (`.slice(0,8)` -> `HH:MM:SS`, local zone) | format differs per engine: check the output starts `HH:MM:SS` |
| `new Date()` (clock) | `Date` (formatted with `getUTC*`: **UTC date, not local**), `Time` | tests must freeze the clock |
| `Date.UTC`, `getUTC*/setUTC*`, `new Date(Date.UTC(...))` | all date functions (`LastDayOfMonth, AddToMonth, AddToDate, DaysElapsed/DateDiff, TimeElapsed, NetworkDays, Days360, MakeDate, ValidEncodeDate, MAndY, DayOfDate, MonthOfDate, YearOfDate, DtoC/CtoD, DaysInMonth`) | engine-independent for correct ES |
| `Math.sin` (md5 constants) | `ConvertMD5` | |
| `RegExp` with `g`/`i` flags and escaped user text | `FindAndReplace`, `CheckEmail`, `ExtractNum` | |
| `String.prototype.toUpperCase/toLowerCase/normalize` etc. | text functions | |

Also: `Evaluate` mutates module state only through `RegVar` (2.8). `Evaluate` replaces the character `♦` with `,` before parsing (`String(expression).replace(/♦/g, ',')`); why definitions carry it is unknown (question 16). Pass expressions through untouched and keep the file UTF-8.

**Parity test source:** `form-studio/src/core/axFunctions.js` holds `AX_SAMPLE` (field values + grid rows) and ~75 functions + 9 operators, each with an example `e` and its exact expected text `r`; `tests/frontend/axFunctions.test.mjs` runs all of them through the parser. The mobile engine can run the same table to prove it behaves like the web. Dates in `AX_SAMPLE` are converted to `dd/mm/yyyy` before registering (same as `forParser`).

## 9. Sample forms

Test organisation (live server, `live-shapes.md`): only **`test_mobile`** (scope `user`) is known: description (text), location, numeric, `section1`, `section2` (grid). `postman/api_collection_connectum.json` examples use **`orders`** for `tstruct.submit`; `docs/postman/Connectum.postman_collection.json` (web repo) has the same requests. No test-org form uses `rule`, `calc`, `fetch`, `dependsOn`, `selection`, `toggle`, `inherit`.

Backend tests build throwaway forms (names generated per run, so they are definitions in the test code, not forms in an org) and are the best sample definitions:
| Feature | Test file (`connectum-backend/test/`) | Frontend test (`tests/frontend/`) |
|---|---|---|
| `rule`, `calc`, globals | `connectum_field_rule_test.mjs` | `fieldRule.test.mjs`, `fieldCalc.test.mjs`, `axFunctions.test.mjs` |
| grid sections, rows | `connectum_grid_sections_test.mjs`, `connectum_grid_rows_test.mjs` | `formEngine.test.mjs` |
| `fetch` (query/api) | `connectum_getfill_test.mjs`, `connectum_fetch_rules_test.mjs`, `connectum_fetchapi_test.mjs` | `fetchFill.test.mjs` |
| selection/query dropdowns, scope limits (`where`, my branch/department, Yes/No lift) | `connectum_query_test.mjs`, `connectum_form_scope_test.mjs`, `connectum_org_scope_test.mjs` | `formScope.test.mjs` |
| `inherit` | `connectum_inherit_test.mjs` | |
| `toggle`, `multi` | `connectum_toggle_test.mjs`, `connectum_multi_select_test.mjs` | |
| unique/key | `connectum_unique_scope_test.mjs` | |
| autogenerate | `connectum_autogen_test.mjs` | |
| defaults / conditions | `connectum_interaction_rules_test.mjs`, `connectum_rules_test.mjs` | `formEngine.test.mjs` |

Features with no sample in any org we can reach: everything in the gap table rows 3, 4, 9, 10, 21, plus `slot`, `payment`, `file`, `barcode`. Ask the team to publish one form per feature in the test org (question 12).

## 10. Questions for the web/backend team

1. **Parser versioning.** The parser has no version. Which commit/blob is "the" release? Will it change, and how will mobile be told (hash in `tstruct.get`, a doc, a release note)? Why it matters: mobile bundles a copy; a silent web change makes the two disagree.
2. **Is the web the reference for `rno` inside a grid cell?** The web evaluates a cell at `rno` 1 with the row spread as scalars (2.1) instead of `rno` = row number. Is that intended? Why: `Total(col)`, `GetRowCount`, `ActiveRow` and `GetValue(name,row)` in a cell may behave differently from the parser's ReadMe. Mobile must copy the web, not the ReadMe.
3. **Date format.** Is there an organisation or user date format that the web will adopt (a setting, a global)? Until then mobile will use `dd/mm/yyyy` into the parser and `yyyy-mm-dd` stored. Why: `SetDateFormat` exists but is unused; a later setting would change every date formula.
4. **`Date()` is UTC today.** Intended? For a user in India at 02:00 `Date()` returns yesterday. Why: formulas like `Date()-DOB` differ near midnight; mobile will reproduce the engine's behaviour.
5. **Engine without `Intl`.** Which of `InsertCommas/FormatAmount/FormatAccAmount/CMonthYear/Time/Encode/Decode/ConvertMD5` do real forms use? Why: sets whether the host prelude must implement `Intl.NumberFormat('en-IN')` and `TextEncoder`/`btoa`, or whether those can be ignored.
6. **Row context quirk.** In a cell rule/calc is `Total(col)` meant to include the current row, and is it read from the grid arrays or the cell scalar? (2.1, last paragraph.)
7. **`RegVar` lifetime.** Is `RegVar` used by any real definition? It is global module state; mobile will create a fresh engine per open form unless told otherwise.
8. **Rules for hidden or condition-hidden fields.** `fieldRuleError` is skipped for hidden fields in the chat form (`requiredErrors` checks `isFieldVisible`). Is a rule on a hidden `calc` field ever expected to run? (docs say rules never block when unreadable.)
9. **`inherit`.** Needs a doc: the shape of `field.inherit`, the Override switch, and the `form.inherit` request/reply. Please extract: one field example from `connectum_inherit_test.mjs` plus a real `form.inherit` reply.
10. **Offline.** May mobile cache `datasource.run` results and `isource.values` per `sourceKey`, how long, and what should a dependent dropdown do offline (empty, cached, "needs connection")? Why: CLAUDE.md says cached-first screens; a form is one.
11. **Server value semantics for hidden made-for fields.** Does the server accept (and keep) a `calc` value sent for a hidden field that its condition hid? `isSentField` sends it only when its condition holds; confirm the server does not drop it.
12. **Please write one doc** (`mobile-handoff` style) with one sample definition per feature (rule, calc with grid + `Total`, fetch query, fetch api, selection datasource with `params`, selection query with `search`, dependsOn people list, toggle, multi, inherit, grid with calc) and a real `tstruct.get` reply plus the `datasource.run` reply for each, and publish them as forms in the test org. Why: today mobile can only be tested against `test_mobile`.
13. **`eq` on text.** Web `evalCondition` compares text case-SENSITIVELY and server `sd_config:eval/2` is the authority; mobile is case-insensitive. Which is right? (Matters only for hand-typed condition values.)
14. **Yes/No.** `forms.md` still says no boolean exists; `toggle` does. Confirm `toggle` is the way and that the value is `"Yes"`/`"No"` text in `values`, conditions and parser.
15. **Properties the brief named but the code does not have.** `git grep` of the form backend, `SmartStructureModal.jsx` and `fieldTypes.js` finds no `pattern`, `regex`, `maxLength`, `format` or `placeholder` field property (only `min`/`max`, the 5000-char text limit and `rule`). Please confirm there is no regex/length property planned, since a pattern check today can only be a `rule` such as `CheckEmail(x)`.
16. **What is the `♦` character in expressions?** The parser turns it into `,`. Do definitions stored in Connectum ever contain it (e.g. imported from Axpert)? Why: if yes, mobile must not strip or re-encode it.
