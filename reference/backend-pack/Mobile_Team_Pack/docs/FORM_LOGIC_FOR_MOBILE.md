# Form logic for the mobile app

Written 2 November 2026 for the mobile team. The mobile app runs **the same JavaScript files** as the web (the Axpert expression parser and the code around it), in an embedded engine, never a port. This page says what to fetch, what the files need from the engine, how grid cells and dates behave, what the **server** does and does not check, and how to cache choices offline. Companions: `FORM_FIELD_TYPES.md` (every field type and the value it is saved as), `docs/sample-forms/README.md` (one sample form per feature, with expected results), `FIELD_RULES.md`, `FIELD_DEFAULTS.md`, `FETCH_RULES.md`.

## 1. What to fetch, and how to know it changed

Seven files, published as they are (byte for byte, line endings included) with a manifest:

```
GET /form-logic/manifest.json
GET /form-logic/form-logic.bundle.js          ALL the logic as ONE script (ES2019, no modules): defines the global ConnectumFormLogic. Easiest for an embedded engine.
GET /form-logic/form-logic-host-shim.js       fills in what a small engine lacks (TextEncoder, atob, Intl ...); load it BEFORE the bundle
GET /form-logic/form-logic-conformance.json   every operator and function of the catalogue with the answer the web gives: a test for your engine
GET /form-logic/axExpParser.js                the same code as separate ES modules: the parser (Evaluate, RegisterVariable)
GET /form-logic/fieldRule.js                  rules and the values a rule reads (evaluateExpression, fieldRuleError, withBlanks)
GET /form-logic/fieldCalc.js                  auto values (applyFormCalcs, applyCalcs, applyRowCalcs)
GET /form-logic/axFunctions.js                the catalogue of functions with a worked example each (for a builder; not needed to run a form)
```

They are static files served by the web server at the app's address, so no sign-in is needed. `manifest.json`:

```json
{ "name": "connectum-form-logic", "version": "1.1.0", "sha256": "<64 hex: the hash of everything>",
  "files": [ { "path": "axExpParser.js", "sha256": "<64 hex>", "size": 33506 }, "..." ],
  "requires": [ "ECMAScript 2020 modules", "Intl.NumberFormat en-IN and en-US", "..." ] }
```

- `version` goes **up** whenever any of the files changes (a test fails the build if a file changes without a new version). Patch: a fix. Minor: a new function or a new behaviour that is safe to take. Major: a change an app must react to.
- `sha256` of everything is the SHA-256 of the lines `<path>:<sha256 of that file>` (each followed by a new line), in the order of `files`. Check each file against its own `sha256` after downloading, then the whole.
- **Suggested use:** bundle a copy as the fallback. At start-up (and about once a day) read the manifest. If `version` is newer than the bundled copy, download the files you use (the bundle, the shim and the conformance file, or the modules), check every hash, then switch. If anything fails, keep what you have. Never load a file whose hash does not match.
- The modules import each other as `./axExpParser.js`, `./fieldRule.js`: keep them in one folder. The bundle needs no folder: it is the same code as one script.
- **Use of the bundle** (any JavaScript engine): evaluate `form-logic-host-shim.js`, then `form-logic.bundle.js`, then call `ConnectumFormLogic.applyFormCalcs(fields, grids, values, idOf)`, `ConnectumFormLogic.fieldRuleError(field, value, valuesWithBlanks)`, `ConnectumFormLogic.evaluateExpression(expr, values)` and so on (`Evaluate`, `RegisterVariable`, `SetDateFormat`, `evaluateRule`, `withBlanks`, `setRuleGlobals`, `ruleResult`, `applyCalcs`, `applyRowCalcs`, `fitCalc`, `hasCalc`, `canCalc`, `usedFields`).
- **Prove your engine:** after loading the two scripts, `ConnectumFormLogic.runConformance(<the JSON of form-logic-conformance.json>)` answers `{total, passed, failures}`; `failures` must be empty.
- Version 1.1.0 has the `Date()` fix below, the bundle, the shim and the conformance file.

## 2. What the files need from the engine, and what was tested

The web has all of this. Many embedded JavaScript engines do not, so the host shim fills in whatever is missing (and changes nothing where it is there):

| Needed | Used by | The shim |
|---|---|---|
| `Date` in the person's own time zone | `Date()`, `Time()` | (the engine's own) |
| `Intl.NumberFormat` with `en-IN` and `en-US` | `InsertCommas`, `FormatAmount`, `FormatAccAmount`, `AmtWord`, `CurrAmtWord` | an exact stand-in for the two ways the logic uses it (lakh grouping, rounding as the standard does) |
| `Date.prototype.toLocaleString('en', { month: 'long', timeZone: 'UTC' })` | the month name functions | the English month name |
| `TextEncoder`, `TextDecoder`, `atob`, `btoa` | `Encode`, `Decode`, `ConvertMD5` | UTF-8 encode and decode, base64 |

**What was tested** (`tests/frontend/formLogicEngines.test.mjs`):

- **JavaScriptCore, the engine of iOS** (the `jsc` shell on a Mac): the catalogue passes with the shim. **Without the shim exactly three functions fail there: `Encode`, `Decode` and `ConvertMD5`, because JavaScriptCore has no `TextEncoder`.** Everything else, money formatting included, works as it is.
- **A bare engine** (a context with only the language: no `Intl`, no `TextEncoder`/`TextDecoder`, no `atob`/`btoa`, a `toLocaleString` that ignores its arguments, the way small engines such as QuickJS behave): without the shim the money, Base64, MD5 and month-name cases fail; with it **all 84 cases pass**, the sample forms' calculations and rules give the same answers as the web, and the money, Base64 and MD5 functions agree with the web over many inputs.
- **The shim against the standard pieces it replaces:** `TextEncoder`/`TextDecoder` on text, emoji, lone surrogates and random (also invalid) bytes; `atob`/`btoa` on random data and bad input; `Intl.NumberFormat` over 4,000 random numbers for every setting the logic uses; the month names.
- **Not tested: the real QuickJS or Hermes.** Installing a QuickJS package here was not allowed, so QuickJS is covered only by the bare-engine simulation above. **Run `runConformance` on the phone, in your real engine, before relying on it** (Android especially).

**Which functions real forms use** (a read-only count of the form definitions on the live server, 2 November 2026, all organisations together: 99 forms, 755 fields, 8 forms with a rule or a calculation): `Substr` 58 times, `Val` 50, `Date` 17, `IIF` 6, `Time` 4, `Length` 3, `Total` 2, `DaysElapsed` 2, `Trim` 2. **No form uses a money function (`InsertCommas`, `FormatAmount`, `FormatAccAmount`, `AmtWord`, `CurrAmtWord`), `Encode`, `Decode` or `ConvertMD5` today.** The field types in use: text 374, drop down 194, whole number 36, date 29, number 23, file 20, Auto Generate 17, switch 14, mobile 12, email 8, selection 8, location 6, time 6, payment 5, booking slot 2, fill 1. So test `Substr`, `Val`, `Date`, `IIF` and `Total` first; the rest are in the conformance file anyway.

The catalogue (`axFunctions.js`) lists 75 functions in seven groups, all in `form-logic-conformance.json`.

## 3. How values go in

`fieldRule.js` registers each field for the parser: a date saved as `2026-11-03` goes in as `03/11/2026` (the parser reads day/month/year); a list goes in as comma text; an object (a place, a payment) goes in as empty; a missing field is given as empty (`withBlanks` does this for every field of the form before a rule is checked). A calculation shows `fitCalc`: a number must be a number, a whole number a whole one, a date comes back as `yyyy-mm-dd`, a drop down must be one of its options (any capitals).

A calculation that reads an **empty** field stays empty (an empty number would otherwise count as 0).

## 4. Grid cells (as built, on purpose)

- A formula **inside a grid row** is worked out for each row from **that row's cells** and from the fields **outside** the grids. The row's cells are registered as ordinary fields at row number 1, so `qty*rate` works in each row with that row's `qty` and `rate`.
- Because a cell sees only its own row, the row functions inside a cell see one row: `Total(qty)` is that row's `qty`, `GetRowCount("qty")` is 1. (The catalogue says so: "Inside a grid cell a rule sees its own row.")
- A total over the **whole column** belongs on an ordinary field **outside** the grid: `Total(lineTotal)`. There every row is registered at its own number (1, 2, 3, ...), so `Total`, `GetRowCount`, `Sum`, `GetValue` and the rest see all rows. It is worked out again whenever the rows change.
- The sample form `sample_grid` does exactly this, and `docs/sample-forms/cases.json` has the numbers (two rows: line totals 20 and 7.5, total 27.5; a row with the rate still empty has no line total and counts as nothing; no rows: the total is 0).

## 5. Today's date

`Date()` is **today where the person is** (day/month/year, or month/day/year when the form uses that format), and `Time()` is the local time. Until version 1.0.0 `Date()` was the UTC date, so between midnight and 5:30 in the morning in India it gave yesterday; that was a mistake and is fixed. `tests/frontend/axToday.test.mjs` checks it in six time zones at every half hour.

## 6. What the server checks (and what it does not)

**The server never runs the expression language.** A field's `rule` and `calc` are saved with the form and checked only by the app (web or mobile). So the phone is the only place a rule such as `Length(phone)=10` is enforced; a record sent straight to the API with a short phone is saved. (`docs/sample-forms/cases.json`, form `sample_rule`, shows exactly that.)

What the server **does** check on `tstruct.submit` / `submissions.update`, field by field:

- the **type and shape** of the value (see `FORM_FIELD_TYPES.md`), with the message in words, and the values saved in their normal form (an email in lower case, a toggle as Yes or No, a number as a number);
- **required** (a field that is not shown is not required);
- **conditions** (`condition`: a field shown only when another has a value; a section too): a field that is not shown is not checked and its value is not saved;
- **limits** (`min`, `max`, at most 5000 characters of text, at most 10 files, at most 200 grid rows);
- a drop down's value against its **options** (fixed lists exactly; lists fed from the organisation's data, any capitals, saved in the list's own spelling), and a choice from a data source against what the source offers;
- **uniqueness** where a form asks for it, and that a file exists and is the person's own;
- **grid rows**: each row field by field (the problem is named `section.row.field`, rows from 0), a row with nothing in it is left out.

**Hidden fields:** a hidden ordinary field's value is ignored (its default is saved, an edit keeps what was there). A hidden field whose value is made for the person (an auto value, a fetch, a fill, a number the system makes) is still **taken from the phone, checked and saved**: hide it on the screen but still send it. The `Auto Generate` number is made by the server; do not send one.

**A switch** (`toggle`) is saved as the text `Yes` or `No`. Any of `true`, `false`, `yes`, `no`, `y`, `n`, `t`, `f`, `on`, `off` (any capitals, spaces round it) is accepted, and **conditions see the saved text** (a condition on `Yes` is met by `true`; this was fixed alongside this page).

## 7. Offline: caching choices and forms

What the server gives you to decide with:

- **`rev` on `tstruct.get`:** a short fingerprint of the saved form. It changes when the form is changed (a field, a rule, a calculation, a fixed option) and **not** when the current choices of a list fed from data change. Keep a form with its `rev`; when `tstruct.get` gives another `rev`, drop everything you kept for that form.
- **`etag` and `cacheSec` on `form.options`:** `etag` fingerprints the choices (and `columns`); `cacheSec` is how long the **server** keeps this source's answer: a data source or an API says so itself (0 to 3600 seconds), and it is 0 for choices read live from Connectum's own forms. `form.options` also says `cached: true` when the server reused its own copy, and `datasource.refresh` forgets the server's copies.
- **`ifNoneMatch`:** send the `etag` you hold with `form.options`. While the choices are the same the answer is `{notModified: true, etag, cacheSec}`, with no choices (so a refresh is cheap); otherwise the full answer with the new `etag`. There is no etag while `waiting` is true (a list still being prepared).
- On **submit** the server checks the choice again against the live list: a choice kept on the phone that is no longer offered is **refused** ("That is not one of the choices on offer." or "Choose one from the organisation's list.").
- The event **`options_changed`** is sent when an option of the organisation is changed.

**Suggested for the phone** (a recommendation: the app decides, nothing on the server enforces what the phone keeps):

- Key the cache by form, field and the **values of the fields the list depends on** (a cascading list is a different list for each parent value); keep it with the form's `rev`.
- **Online:** use a kept list for at most `cacheSec` (5 minutes when it is 0 and you want some reuse); then ask again with `ifNoneMatch`.
- **Offline:** show the last list, marked as possibly old, for a day or two.
- **Drop it** when the person signs out or changes organisation, the form's `rev` changes, the event `options_changed` arrives, a parent field changes, or the server refuses a choice.
- A record saved offline and sent later may be refused for a stale choice or a file that is gone: keep it, show the message from `error.details.fields`, and let the person fix it. Send the same `cid` (1 to 64 characters) on a retry so a record that did get through is not saved twice (`duplicate: true`).

## 8. How to check your work

- `docs/sample-forms/` (load with `node tools/sample-forms/load.mjs`): one form per feature, and `cases.json`, the numbers to expect from the shared logic and from the server.
- `tests/frontend/sampleForms.test.mjs` runs the shared logic over those cases; `connectum-backend/test/connectum_sample_forms_test.mjs` runs the server over them (99 checks).
- `tests/frontend/axFunctions.test.mjs` runs every example of the catalogue through the parser (so what the catalogue says is what the parser answers); `formLogicEngines.test.mjs` runs the same in small engines (section 2); `connectum-backend/test/connectum_form_cache_test.mjs` checks `rev`, `etag`, `cacheSec` and `ifNoneMatch` (29 checks).
