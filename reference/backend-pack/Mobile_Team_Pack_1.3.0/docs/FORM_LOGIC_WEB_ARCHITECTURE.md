# How the web app uses the form logic (for the mobile team)

Written 4 November 2026 against `main` (published form-logic version **1.3.0**). An analysis of what the web does, so the mobile team can decide what to take from the shared files and what it must build itself. Nothing in the code was changed for this document. Every claim cites `file:line` (paths are from `connectum/`; `core/` means `form-studio/src/core/`; `modal` means `chat-app/features/connectumChat/components/modals/SmartStructureModal.jsx`). Companion: `docs/FORM_LOGIC_FOR_MOBILE.md` (what to fetch and how the engine must behave).

## 0. The short version

- **There are two web form screens, not one.** The screen people use in the web app is the chat app's `modal` (SmartStructureModal.jsx) with its helper `chat-app/features/connectumChat/utils/formEngine.js`. The Form Studio (the embeddable studio and builder) has its own renderer, `form-studio/src/ui/DynamicForm.jsx`. They share some files in `core/` and use different ones for others (section 1, section 3).
- **What is truly shared and published (bundle):** the expression parser, rules, auto values (calculations) and conditions: `axExpParser.js`, `fieldRule.js`, `fieldCalc.js`, `condition.js` (`core/formLogicEntry.js:3-6`).
- **What is NOT in the bundle, and decides a lot:** starting values (`defaults.js`, `timeDefault.js`), choice narrowing (`listChoices.js`), grid and repeat helpers (`gridModel.js`, `repeatSections.js`), what is sent and what is checked before sending (`chat-app/.../formEngine.js` for the web app, `validation.js` for the studio), phone checking (`utils/phone.js`). Plain JS that could be exported, or logic that sits in React components (sections 4 and 5).
- **The server has the final say** and checks required, types, limits, conditions and lists itself (`connectum-backend/src/forms/sd_config_values.erl`). It does **not** evaluate a field's `rule` or `calc`: those run only in the client (section 3, "rule").
- **Verdict:** the web's behaviour is **not** totally driven by the shared files. Replacing them would change rules, calculations and conditions, but leaves a good deal of logic in React (section 4).

## 1. Map of the modules

"Bundle" = exported by `core/formLogicEntry.js` into `core/form-logic.bundle.js`. "Published" = also served as a file under `/form-logic/` (`scripts/form-logic-lib.mjs:14`).

| Module (`core/`) | What it does | Imported by | Bundle | Kind |
|---|---|---|---|---|
| `axExpParser.js` | The Axpert expression language: `Evaluate`, `RegisterVariable`, `SetDateFormat`, 75 functions. No imports. Module state: `RegVarFldList` (`:1`), `dateFormat` (`:2`) | `fieldRule.js:4`, `formLogicEntry.js:3` | **Yes** (published too) | shared logic |
| `fieldRule.js` | A field's `rule` (`{expr, message}`): `evaluateRule`, `evaluateExpression`, `fieldRuleError`, `withBlanks`, the signed-in person's variables (`setRuleGlobals`) | chat `formEngine.js:1`, `utils/ruleGlobals.js:5`, `DynamicForm` (via `validation.js:2`), `fieldCalc.js:12`, `builderModel.js:1` | **Yes** (published too) | shared logic |
| `fieldCalc.js` | A field's auto value (`calc`): `applyFormCalcs`, `applyCalcs`, `applyRowCalcs`, `fitCalc`, `hasCalc`, `canCalc`, `usedFields` | modal `:43`, `DynamicForm.jsx:17`, `gridModel.js`, `builderModel.js`, `FieldEditor.jsx` | **Yes** (published too) | shared logic |
| `condition.js` | Whether a field or section is shown (`evalCondition`, `isEmpty`); operators `eq ne gt lt gte lte in between notempty` (`:5`, `:32-53`) | chat `formEngine.js:2` | **Yes** (published too) | shared logic |
| `axFunctions.js` | The function catalogue with a worked example each | `exprSuggest.js`, `RuleCatalogSheet.jsx`, the conformance builder | No (published only) | shared logic (data) |
| `conditionCases.js` | The 63 hand-written condition cases for the conformance file | the bundle builder | No | shared logic (data) |
| `formLogicEntry.js`, `form-logic-host-shim.js`, `form-logic.bundle.js`, `form-logic-conformance.json`, `form-logic.version.json` | The bundle entry, the engine shim, the built bundle, the conformance cases, the version and hash | the build scripts | (they are the bundle) | shared logic |
| `defaults.js` | Starting values: fixed default, today for a date, the time now, toggle off; `withDefaults`, `startingValue` | chat `formEngine.js:4`, modal `:15`, `DynamicForm.jsx:2`, `gridModel.js`, `useFetchFill.js` | **No** | shared logic |
| `timeDefault.js` | The current time inside a field's min / max | `defaults.js:4` | **No** | shared logic |
| `validation.js` | The studio's checks: required, number range and size, text length, email, url, mobile (libphonenumber), date and time min / max, location, payment | `DynamicForm.jsx:16`, `DynamicField.jsx`, `gridModel.js` | **No** | shared logic, **needs `libphonenumber-js`** |
| `conditions.js` | The **studio's** condition engine: operators `equals notEquals gt lt contains between notEmpty`; `isFieldVisible`, `isSentField` | `DynamicForm.jsx:13`, `gridModel.js`, `options.js`, `localApi.js` | **No** | shared logic (a second, different vocabulary from `condition.js`) |
| `listChoices.js` | Which choices a narrowed list offers (`shownChoices`), what a value becomes (`fitValue`), the "choose X first" word | modal `:259, :287` area (imports at `:19`), `DynamicField.jsx` | **No** | shared logic |
| `gridModel.js` | Studio grid sections: rows, row checks (`gridErrors`), `rowsToSend` | `DynamicForm.jsx`, `RecordTable.jsx`, `RecordDetail.jsx` | **No** | shared logic |
| `repeatSections.js` | Repeat helpers (`insertAfter`, `errorsByRow`, `shortValue`) shared by both screens | modal `:48`, `RepeatedSection.jsx` | **No** | shared logic |
| `inherit.js`, `fetchFill.js`, `selectionSource.js`, `placeAddress.js`, `statusDefaults.js`, `queryScope.js`, `querySource.js`, `options.js`, `format.js`, `recordsCsv.js`, `cloneName.js`, `exprSuggest.js`, `builderModel.js`, `fieldTypes.js` | Smaller helpers for fill-from-record, data sources, addresses, ticket status, builder drafts, display formatting | the two form screens and the builder | **No** | shared logic (`recordsCsv.js` touches `document` for a download: UI-bound; `fieldTypes.js` names icons for the builder) |
| `api.js`, `localApi.js`, `localDb.js`, `reverseGeocode.js`, `embedBridge.js`, `logger.js` | Browser plumbing: REST calls (`api.js:30-34` reads `window`), the in-browser store (IndexedDB, `localDb.js:27`), a Nominatim lookup, iframe messages | the studio | **No** | UI-bound |
| `useAddress.js` | React hook for a place's address | `DynamicField.jsx`, `LocationField.jsx` | **No** | UI-bound (React, `:3`) |
| `tokens.js` | Theme (styled-components) | UI | **No** | UI-bound |

Outside `core/`, the web app's form logic that is not in any shared file: `chat-app/features/connectumChat/utils/formEngine.js` (193 lines: visibility, required, what to send, grids), `utils/phone.js` (`phoneProblem` `:100`, `toStored` `:111`), `utils/ruleGlobals.js` (loads the person's details for rules).

## 2. Flow in the web app

Described for the web app's screen (`modal`); where the studio's `DynamicForm.jsx` differs, it says so.

### (a) A form opens

1. The screen asks the server for the definition: `tstruct.get` (or `tstruct.user.get`) and the person's saved arrangement `formlayout.get` (modal `:608`). Comes back: the form (`fields`, `sections`, conditions, rules, calcs).
2. `initialValues(tstruct, currentUser, editing)` (modal `:462-490`) builds the starting values: a payment amount, a list that starts on a detail of the person (`prefill`), a `fill` field from the person's profile, and for a **new** record `startingValue(f)` from `core/defaults.js` for every non-grid field (`:482-486`; `defaults.js:21-29`).
3. Grid sections: `gridStartValues(tstruct, stored, isNew)` (`formEngine.js:48-56`) gives each grid one blank row made with `blankRow` (`:37-46`, which calls `startingValue` too).
4. The values are set (modal `:639`): for an edit, the saved values on top of the starting ones.
5. A location field that starts on where the person is asks the browser once (`useDevicePosition`, modal `:758`; `defaults.js:43-44`).
6. The person's own details are loaded for rules and calculations: `useRuleGlobals` (modal `:561`) → `setRuleGlobals` (`ruleGlobals.js:14-16`, `fieldRule.js:18-23`).
7. From then on the effects below run on every change.

The studio does the same through `toInputValues` → `withDefaults` (`DynamicForm.jsx:200-203`) and loads the person's details with `listGlobals` + `setRuleGlobals` (`DynamicForm.jsx:232`).

### (b) A value changes

1. The field's `onChange` calls `setValue(name, v, raw)` (modal `:692-700`): stores the value; an Auto Fill field (`fill`) copies a property of the chosen item; the field's error is cleared.
2. An effect re-runs **auto values** after every change: `applyFormCalcs(flat, grids, prev, idOf)` (modal `:660-666`; `fieldCalc.js:189-207`). Inputs: the non-grid fields, the grid sections (`{id, fields}`) and the current values. Output: the same values object with every calculated field filled in (the same object back when nothing moved, so there is no loop).
3. **Visibility** is worked out on every render: `groupBySection` → `isFieldVisible` → `evalCondition(field.condition, values)` (`formEngine.js:100-108, 166-182`; `condition.js:27`). Rows use `rowFieldVisible` with `rowContext` (`formEngine.js:33-34`).
4. **Drop-down cascades.** A narrowed list shows `shownChoices(field, values)` (`listChoices.js:17-25`); when the parent changes, a value that no longer fits is cleared in a React effect: single choice `modal :287`, several `modal :259` (`fitValue`, `listChoices.js:28-36`).
5. **Fill from another form** (`useFetchFill`, modal `:669`) and **inherit from a chosen record** (`useInherit`, modal `:678`) call the server (`datasource.run`, `form.inherit`) and write values back.
6. **Slots:** `SlotField` asks `avail.slots` and clears a time that no longer exists (modal `:194-215`).
7. Rules are **not** run while typing in the web app's screen. They run when Save is pressed (below). The studio also checks on submit only (`DynamicForm.jsx:366-372`).

### (c) The person presses Save / Submit

1. `handleSubmit` → `doSubmit` (modal `:846`, `:784`): `requiredErrors(tstruct, values)` (`formEngine.js:150-163`, modal `:787`). For each visible field: **required** (`:154`), then the field's **rule** `fieldRuleError(f, value, withBlanks(allNames, values))` (`:158`; `fieldRule.js:91-99`), and for a mobile field `phoneProblem(...)` (`phone.js:100`). Grid cells go through `gridRequiredErrors` (`:60-80`). Any message stops the submit and shows under the field.
2. `buildSubmission(tstruct, values)` (`formEngine.js:111-147`, modal `:796`): only fields that are visible, or hidden but made for the person (`isSentField` `:97`); empty values left out; `autogenerate` left out; numbers as numbers (`:124-125`); payment as `{amount, status, method?}` (`:119-123`); mobile as `toStored` (`:126`); other strings trimmed (`:127`); each grid row built with its own visibility (`:130-145`, an empty row is sent as `{}`).
3. A place gets its street address first: `withAddresses` (modal `:796`; `placeAddress.js`).
4. The call: `tstruct.submit` / `tstruct.user.submit` or, when editing, `submissions.update` / `submission.resubmit` (modal `:797-803`).
5. Back: `{ok, data: {submission, recordStatus, message}}`, or an error. `invalid_values` with `details.fields` shows the **server's** words under each field (modal `:806-808`); any other error shows its message (`:810-812`). The server checks everything again (section 3).

The studio's `submit` is the same shape with different helpers: `validateField` per visible field (`DynamicForm.jsx:366-372`), `gridErrors`, `isSentField` from `conditions.js` (`:384`), numbers via `Number(v)` and mobile via libphonenumber `p.number` (`:389-396`), `rowsToSend` (`:398`), then `onSubmit(sendable)` (`:406`).

## 3. Who decides what

"Server" = `connectum-backend/src/forms/sd_config_values.erl`. "Web screen" = `modal` + `formEngine.js`. "Studio" = `DynamicForm.jsx` + `validation.js`.

| Behaviour | Where decided | Evidence |
|---|---|---|
| **Required** | **Duplicated in three places.** Web screen: `requiredErrors` (`formEngine.js:154`, `"This field is required."`). Studio: `validation.js:31` (`"<label> is required"`). Server: `check_one` (`sd_config_values.erl:313-322`, `"This field is required."`) | the server's is final |
| **Max / min length (text)** | Server: `check_type(<<"text">>)`, max 5000 and the field's `length` (`:468-478`). Studio: `validation.js:45-48`. **Web screen: nowhere** (no `maxLength` on the input: modal `:377-394`) | the web screen relies on the server |
| **Number range, decimals, digits** | Server: `in_range` and the size checks (`:658-708`). Studio: `validation.js:17-27, 34-44`. Web screen: only HTML `min` / `max` / `step` attributes (modal `:405-415`), and the form is `noValidate` (modal `:957`), so the browser does not block on them. **The web screen does not check them; the server answers `invalid_values`** | no shared file in the web screen's path |
| **Email / URL format** | Server (`:485-492`, `"Enter a valid email address."`). Studio: `validation.js:4-5, 49-52`. Web screen: `type="email"` / `"url"` only (modal `:418-421`), with `noValidate` so not enforced | different wording server vs studio |
| **Mobile format** | Web screen: `phoneProblem` (`formEngine.js:158`; `phone.js:100`, libphonenumber). Studio: `validation.js:53-57` (libphonenumber). Server: `check_type(<<"mobile">>)` (`:493`). Three separate implementations | stored as E.164 digits (`phone.js:111`, `toStored`) |
| **Date and time min / max** | Server `in_range` (`:502-515, 658-664`). Studio `validation.js:58-62`. Web screen: only passes `min` / `max` to `GlassDate` (modal `:402`); `GlassTime` gets none (`:404`); nothing checks on submit. The `defaults.js` clamp (`:9-13, 26`) keeps the **starting** date and time inside min / max | |
| **Rule expressions (`fieldRule`)** | **Client only.** Shared file `fieldRule.js` runs the expression in the web screen (`formEngine.js:73, 158`) and the studio (`validation.js:13`). The server **never evaluates** `rule` or `calc`: a search of `connectum-backend/src` finds them only when a form definition is saved (`sd_config_forms.erl:314-330`) | this is why the conformance file matters: only the client enforces a rule |
| **Calculations (`fieldCalc`, grid rows, totals)** | **Shared file only**, called from React: web `modal :665`, studio `DynamicForm.jsx:246` → `applyFormCalcs` (`fieldCalc.js:189-207`); row cells via `applyRowCalcs` (`:172-182`); a total outside a grid reads a whole column through `columns` (`:191-193`). Server does not recompute (it saves what it is sent) | |
| **Conditions and visibility** | Web screen: shared `condition.js` (`evalCondition`) called by `formEngine.js:34, 58, 87-108`. Server: its own Erlang copy `eval/2` (`sd_config_values.erl:421-443`, same operators) and it **skips** fields a condition hides (`:313-314, 406-411`). Studio: a **different** engine, `conditions.js` (operators `equals notEquals ...`, `:12-`), so a studio form's conditions are not the format of a server form | the web and the server are meant to agree; `conditionCases.js` pins `condition.js` |
| **Default values; today / now** | Shared `defaults.js` + `timeDefault.js`, called from React / `formEngine.js` (`modal :482-486`, `formEngine.js:40, 49-52`; studio `DynamicForm.jsx:202`). Server: a read-only field gets its fixed default whatever is sent (`sd_config_values.erl:279-290`) | uses the device clock |
| **Drop-down cascades, clearing dependents** | Choice list: shared `listChoices.js` (`shownChoices`, `fitValue`). **The clearing is a React effect** (`modal :259-261, :287`). Server re-checks (`check_type(<<"list">>)` `:579`) | |
| **Hidden fields on submit** | Shared nowhere: `formEngine.js:84-97` (`isMadeFor`, `isSentField`) for the web screen; `conditions.js:65` for the studio. Server: a hidden field's value is ignored unless it is made for the person (`sd_config_values.erl:279-290`, `hides_value`) | |
| **Value formatting before sending** | Web screen: `buildSubmission` (`formEngine.js:119-141`): `parseInt` / `Number`, phone to E.164, trim, payment object. Dates stay `yyyy-mm-dd`, times `HH:mm`, a toggle stays `"Yes"` / `"No"` text (`defaults.js:23`). Studio: `DynamicForm.jsx:384-398`. Server normalises a toggle's spellings (`:267, :642-654`) | |
| **File fields** | Upload is React + a service (`FileField` `modal :335-371`, `uploadFile` `services/connectumFiles.js:33`); the value is a list of file ids. Server `check_type(<<"file">>)` (`:537`) | |
| **Payment fields** | Entry is React (`PaymentField` `modal :310-`); shape built in `buildSubmission` (`formEngine.js:119-123`); studio checks in `validation.js:65-71`; server `:521-536` | |
| **Booking-slot fields** | React + server call (`SlotField` `modal :194-215`, `avail.slots`); server `check_type(<<"slot">>)` (`:516`) | |
| **Error wording** | Three vocabularies: web screen `"This field is required."` (`formEngine.js:71, 155`); studio `"<label> must be ..."` (`validation.js`); server `"Must be at least 5."`, `"Enter a valid email address."`. A rule's text is the form author's `rule.message` (`fieldRule.js:98`). After submit the web screen shows the **server's** messages | |

## 4. Dependency verdict

**No. The web's form validation and behaviour is not totally driven by the shared core files.** Replacing `axExpParser.js`, `fieldRule.js`, `fieldCalc.js` and `condition.js` would change what rules, calculations and conditions answer, with no React change. But these pieces live only in React or in `formEngine.js` (neither is in the bundle):

| Logic that lives outside the bundle | Where | What it does |
|---|---|---|
| What is required, and the order of checks | `chat-app/.../formEngine.js:150-163` | required → rule → phone, and the grid row checks (`:60-80`) |
| What is sent, how it is typed | `formEngine.js:84-97, 111-147` | visible-or-made-for-the-person, numbers, payment, trim, empty rows as `{}` |
| Grid and repeat rules | `formEngine.js:18-58` | rows, blank row, "at least 1 row", maximum 200 rows, row visibility |
| Starting values | `defaults.js`, `timeDefault.js` | not in the bundle (plain JS) |
| Phone checking | `utils/phone.js:100, 111` | libphonenumber, E.164 |
| Clearing dependent drop-downs | `modal :259-261, :287` | React effects calling `onChange("")` / `fitValue` |
| Location / address, file upload, payment entry, slot choice | `modal :194-215, :310-371, :758`; `placeAddress.js` | UI and server calls |
| Fill from a record, inherit, data-source choices | `useFetchFill` (`modal :669`), `useInherit` (`:678`), `selectionSource.js` | server calls |
| Auto Fill of a chosen item | `setValue` `modal :692-700`, `setCell` `:729` | copies a property of the selected item |
| Number range, text length, email / url, date and time limits | **nowhere in the web screen**; only the server (and `validation.js` in the studio) | the mobile app must either check them itself or rely on the server's `invalid_values` |

Pieces that are plain JS (no React) but simply not exported: `defaults.js`, `timeDefault.js`, `listChoices.js`, `validation.js`, `gridModel.js`, `repeatSections.js`.

## 5. The bundle against section 3

`formLogicEntry.js:36` exports exactly: `evalCondition, isEmpty, Evaluate, RegisterVariable, SetDateFormat, evaluateExpression, evaluateRule, fieldRuleError, withBlanks, setRuleGlobals, ruleResult, applyCalcs, applyFormCalcs, applyRowCalcs, fitCalc, hasCalc, canCalc, usedFields`, and `runConformance` (`:12-34`).

| Behaviour | In the bundle? | To get it |
|---|---|---|
| Rule expressions, calculations, grid totals, auto values | **Yes** | nothing |
| Conditions / visibility | **Yes** (`evalCondition`). Not the section-level helpers (`isFieldVisible`, `isFieldCounted`, `isSentField`, `groupBySection` are in `formEngine.js:87-108`) | export: plain JS, but `formEngine.js` also imports `phone.js` (libphonenumber) so those few functions must be moved to their own file first |
| Default / today / now values | No | plain JS (`defaults.js`, `timeDefault.js`): add to the entry |
| Required | No | `formEngine.js:154` is mixed with phone checking: pull `requiredErrors` apart, or write the one-line `isEmpty && required` |
| Number range / decimals / text length / date and time limits / email / url | No | plain JS in `validation.js:17-62` (one import: `libphonenumber-js`, used only for mobile): split the mobile case out, then export |
| Mobile format | No | needs libphonenumber (a library); `phone.js` is the web screen's version |
| Choice narrowing and clearing | `shownChoices` / `fitValue` not exported | plain JS (`listChoices.js`): add to the entry; the effect that calls `onChange("")` is React and has to be rewritten by the host |
| What to send | No | `buildSubmission` (`formEngine.js:111-147`) is plain JS but sits next to `phone.js`; move it out, then export |
| Hidden-field handling | No | `isMadeFor`, `isSentField` (`formEngine.js:84-97`): plain JS, move and export |
| Grid rows | No | `formEngine.js:18-80` plain JS (the web screen's version) or `gridModel.js` (the studio's) |
| File, payment entry, slot, location | No | UI + server calls: the host builds these; only the **shape** can be shared (`formEngine.js:119-123`) |
| Error wording | Only a rule's own message | the server's words come back from `invalid_values` |

## 6. Contract and versions

- **Current manifest version: 1.3.0** (`core/form-logic.version.json`, sha256 `bd36551466e20766061560b293d7303f7eff179e28de5f1ca11921461c37c65d`); the files are listed in `scripts/form-logic-lib.mjs:14`: `axExpParser.js, axFunctions.js, fieldCalc.js, fieldRule.js, condition.js, form-logic.bundle.js, form-logic-host-shim.js, form-logic-conformance.json`.
- **Since 1.1.0:**
  - **1.2.0** (`2c6626b2`, 2 Nov): `condition.js` joined the bundle (`evalCondition`, `isEmpty`) and the conformance file gained 63 condition cases (`conditions`, run by `runConformance` `formLogicEntry.js:25-31`).
  - **1.3.0** (`19d2b63b`, 2 Nov): the signed-in person's details are written `login_<name>` (`fieldRule.js:11, 67`); the old `global_<name>` still reads (`:13`). An app on 1.1.0 does not know `login_`.
  - 1.1.0 itself is `7058a977` + `553f1644` (the `Date()` fix, the bundle, the shim, the conformance file). The conformance file is now 84 expression cases plus 63 conditions.
- **The old parser copy.** In this repository the file has been called `axExpParser.js` since it was added (23 Oct 2026, `bf9786fe`; moved from `connectum/web/src/core` to `form-studio/src/core` on 31 Oct, `223da258`). No file named `AxExpReactParser.*` exists in it or in any other folder of the working copy; the name survives only in comments (`fieldRule.js:1`). So `AxExpReactParser.jsx` is the mobile team's own snapshot, not a file we have. **The current `core/axExpParser.js` is the single source of truth for the formula parser in our repositories; there is no other copy of it.** The one change since the snapshot you describe is `Date()` (`axExpParser.js:666-668`: today's local date; `Time()` is `new Date().toTimeString()`, `:670`).
- **Exports.** The module `axExpParser.js` still exports `dateFormat` (`:2`), `RegisterVariable` (`:4`), `GetValue` (`:26`), `Evaluate` (`:33`) and `SetDateFormat` (`:73`). The **bundle** exposes only `Evaluate`, `RegisterVariable` and `SetDateFormat` (`formLogicEntry.js:3, 36`): `GetValue` and `dateFormat` are not on the `ConnectumFormLogic` global. Both are one-line additions to the entry if the mobile app wants them; the web does not need them.
- **Time zone.** The host cannot set a zone through the bundle: `Date()` and `Time()` use the engine's own `new Date()` (`axExpParser.js:667-670`), and starting values use `getFullYear/getMonth/getDate/getHours/getMinutes` (`defaults.js:7`, `timeDefault.js:4`). The host must make the engine's local time zone the person's. Date arithmetic inside the parser is UTC (`Date.UTC`, e.g. `:217, :576`), on purpose, so it does not drift with the zone. `SetDateFormat('dd/mm/yyyy' | 'mm/dd/yyyy')` is the only date setting; the web never calls it (a search of `chat-app/` and `form-studio/src/ui/` finds no call), so the web is always `dd/mm/yyyy` (`axExpParser.js:2`).
- **Globals the shim provides** (`form-logic-host-shim.js`, only where missing): `TextEncoder` (`:8`), `TextDecoder` (`:25`), `btoa` (`:54`), `atob` (`:65`), `Intl.NumberFormat` for `en-IN` and `en-US` (`:82, :126-127`), and the English month name of `Date.prototype.toLocaleString` (`:130-136`). Load it before the bundle. `ConnectumFormLogic.runConformance` proves the engine.

## 7. Risks in an embedded engine

1. **Time zone.** `Date()`, `Time()`, today's default and the time default all read the device's local clock (section 6). A wrong zone gives the wrong day around midnight (the reason for the 1.1.0 fix).
2. **State kept between calls.** There is module-level state that outlives a call: the parser's `RegVarFldList` (`axExpParser.js:1, :455-460`), the globals (`fieldRule.js:16-23`), and `fieldCalc.js`' answer memory (`MEMORY`, `:77`, keyed by the expression, the values it reads and today's date `:115`; cleared at 500 fields `:128`). Call `setRuleGlobals` once per sign-in and again when the person changes; use **one engine instance per signed-in person** or reset it between people.
3. **Dates are text in two layouts.** Stored values are `yyyy-mm-dd`; the parser wants `dd/mm/yyyy`. `fieldRule.js` converts in (`forParser` `:46-52`) and `fieldCalc.js` converts a date answer back (`fitCalc` `:59-63`). A host that bypasses those functions and feeds the parser directly must do the same.
4. **Locale and numbers.** Money functions use `Intl.NumberFormat` (`axExpParser.js:291`), month names use `toLocaleString('en', ...)` (`:631`): fine with the shim, otherwise wrong. No form on the live server used a money function when this was counted (`docs/FORM_LOGIC_FOR_MOBILE.md`, section 2).
5. **Order of calls.** Calculations must run after every change and before a rule is checked or the form is sent (`modal :660-666` then `:787`). `fieldRuleError` needs every field present, blank when empty (`withBlanks`, `fieldRule.js:84-88`), or the rule is skipped (`:81-83`). Conditions must see the calculated values.
6. **A rule that cannot be read does not block** (`fieldRule.js:54-58, 74-78`), and a rule on an empty field is not checked (`:94`). The server does not backstop a rule (section 3): a mobile app that skips rules lets those values through.
7. **A calculation that names a field with no value stays empty** (`fieldCalc.js:159`), so a total over an empty column is blank, not 0.
8. **Two validators and two condition vocabularies exist** (section 3). A mobile app that follows the studio's `validation.js` and `conditions.js` gets different wording and different operator names from a server form's (`eq` / `ne` against `equals` / `notEquals`).
9. **Libraries.** `validation.js` and `utils/phone.js` need `libphonenumber-js`; neither is in the bundle.

## What mobile should do

1. Take the bundle (**1.3.0**), the shim and the conformance file; run `runConformance` on the real engine before trusting it.
2. Set the engine's time zone to the person's, and use one engine per signed-in person (or `setRuleGlobals` again at every sign-in).
3. Run **calculations first, then visibility, then rules**, on every change; run **rules only at Save**, with `withBlanks`.
4. Use the bundle's `evalCondition` for visibility and the section's condition; keep the server's `eq / ne / ...` vocabulary, not the studio's.
5. Write your own **required** check, and your own number, length, email / url and date-limit checks if you want them before the round trip; the web screen has none of them and relies on the server (`invalid_values`). Show the server's messages under each field.
6. Do not rely on the server for **rules and calculations**: it saves them but never runs them (section 3).
7. Copy the **sending rules** (`formEngine.js:84-97, 111-147`): hidden-but-made-for-the-person fields are still sent, empty values are left out, numbers as numbers, phone as E.164, an empty grid row as `{}`.
8. Ask us to add `defaults.js`, `timeDefault.js`, `listChoices.js` and the sending / required helpers (moved out of `formEngine.js`) to the bundle, and `GetValue` / `dateFormat` if you need them; each is a small export change plus a version bump.
