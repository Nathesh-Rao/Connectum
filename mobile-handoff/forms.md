# Forms: schema, submit/edit, submission object, chat card

## 0. Which schema the chat uses

The chat uses the **"lite tstruct"** schema defined and validated by the backend (`axi-chat-backend/src/sd_config.erl`, types in `?FIELD_TYPES`). Field key is `name`, type `wholenumber` (lower case). The forms-studio builder in `web/` uses a different editor model (`id`, `wholeNumber`, see `web/src/core/builderModel.js`, `fieldTypes.js`) and its output is saved to the same server structure; the chat's `defaults.js` accepts both spellings. **Mobile should code against the server shape below.** The chat form itself is `SmartStructureModal.jsx`; shared pure logic comes from `web/src/core/{defaults,fieldRule,fieldCalc}.js`. docs/LITE_TSTRUCT.md is referenced by code comments but **does not exist** in docs/.

## 1. Form definition (what `tstruct.get` / `tstruct.user.get` returns as `tstruct`)

```json
{
  "name": "expense_claim", "caption": "Expense claim", "description": "", "allowForward": true,
  "sections": [
    {"name": "main", "caption": "Details", "condition": null},
    {"name": "items", "caption": "Items", "condition": {"field":"amount","op":"gt","value":0}, "grid": true}
  ],
  "fields": [
    {"name":"amount","type":"number","caption":"Amount","required":true,"section":null,"condition":null,"min":0,"max":100000}
  ]
}
```

Definition-level keys also present (not needed to render): `saveToDb`, `axpert`, approval/notify settings, `readableBy`, `keyField`, `fetchRules`. Limits: name `^[A-Za-z][A-Za-z0-9_]{0,39}$`, up to 100 fields, field names unique.

### Common field properties (every field)

| Key | Meaning |
|---|---|
| `name` | id used in submission `values` |
| `type` | one of the types below |
| `caption` | label (defaults to name) |
| `required` | bool (never for `autogenerate`) |
| `section` | section name or `null` |
| `condition` | show-only-when rule (section 3) or `null` |
| `readOnly` | bool; person cannot edit. New record gets `default`; edit keeps saved value. Required + readOnly needs a default or date/time/location start. |
| `default` | fixed starting value; only for text, email, url, mobile, wholenumber, number, date, time, single-choice list |
| `defaultNow` | date/time/location: `false` turns off "start on today / now / current location" |
| `rule` | `{"expr":"Length(phone)=10","message":"Ten digits please"}`; Axpert expression, max 500 / 200 chars. Not for autogenerate/fill. |
| `calc` | `{"expr":"IIF(age>18,\"Adult\",\"Minor\")"}`; auto value for text, wholenumber, number, date, single list; makes the field locked, not required |
| `fetch` | self-fill from another form or a Get API; types text, email, url, mobile, wholenumber, number, date, time |
| `axpertField` | Axpert mapping name, ignore in UI |

### Field types

| `type` | Extra properties | Value in submission |
|---|---|---|
| `text` | `multiline`, `rich` (bool) | string, max 5000 chars |
| `email` | | string, lowercased/normalised, must be valid |
| `url` | | string, must match `^https?://` |
| `mobile` | `withCountryCode` (needs `+...`), `countryPicker`, `defaultCountry` | string normalised (web `toStored`: "+", country code, digits) |
| `wholenumber` | `min`, `max` | integer (sent as number) |
| `number` | `min`, `max` | number (decimal) |
| `date` | `min`, `max` (`YYYY-MM-DD`) | string `"YYYY-MM-DD"`, must be a real date inside min/max |
| `time` | `min`, `max`, `defaultNow` | string `"HH:MM"` or `"HH:MM:SS"` |
| `list` (dropdown) | `options`: [string] **or** `source`: one of `branches, departments, designations, users, people, categories, affiliates, roles` or `isource:<name>`; `multi`, `allowAll` (multi+source), `where`, `dependsOn {field,prop}`, `prefill` (person detail), `subject`, `involve` | single: string that matches an option (case-insensitive for sourced lists); `multi`: array of strings; `"All"` if `allowAll` |
| `selection` | `api` (URL), `source` {type: `datasource`\|`api`\|`query`, name, params {p:{field}\|{value}}}, `allowTyping` | string (<=500). The server also stores a display label in `labels[name]` |
| `fill` (Auto Fill) | `fillFrom` (field name), `sourceProp` | string, read-only, copied from the chosen selection |
| `location` | `defaultNow` | `{"lat":12.97,"lng":77.59}` (web may add `address`; server keeps only lat/lng). Also accepts string `"lat,lng"` |
| `file` | `multi` | array of file ids (max 1, or 10 if `multi`); upload first via the files API (`src/services/connectumFiles.js`, `sd_files`) |
| `payment` | `amount` (usual fee), `currency` (label), `methods` (default `["Cash","Card","UPI"]`) | `{"amount":500,"method":"UPI","status":"paid"\|"pending"}`; amount >= 0; method must be on the list and is required when `paid` |
| `slot` (booking time) | `of` (name of the field holding the person booked) | string `"YYYY-MM-DD HH:MM"`, chosen from `avail.slots {user, days}` |
| `barcode` | none | string (scanned), <=5000 |
| `autogenerate` | `prefix`, `suffix` (<=20), `digits` (1-18), `start`, `resetEvery` (`never\|year\|month`) | **never sent**; the server makes it (e.g. `INV-0001`) and returns it in the saved values |

**Yes/No: there is no boolean or yes/no field type** (`check_type` has no boolean clause; unknown types are refused). UNCLEAR: how should a yes/no question be modelled; presumably `list` with `options:["Yes","No"]`, but no code or doc says so. (Only the card summary helper prints a JSON boolean as `yes`/`no`.)

**Amount:** either a `number` field (plain) or a `payment` field (amount + method + paid status). Money has no currency formatting rule except the optional `currency` label.

## 2. Defaults and read-only (when the form opens)

Order: fixed `default`; else `date` = today, `time` = now (unless `defaultNow:false`); `location` = device position (ask permission once for the form). Dates/times are clamped into min/max. Not applied to autogenerate, fill, file, payment, slot, selection, barcode. Numbers are held as text in the editor. Edits show the saved record, not defaults. A grid row starts with the same defaults; a row holding only form-supplied values counts as empty.

## 3. Conditional logic

A `condition` (on a field or section) is evaluated on the client against the current values and again on the server:

```json
{"field":"leaveType","op":"eq","value":"Sick"}
{"all":[ {...}, {...} ]}      {"any":[ {...}, {...} ]}
```

| `op` | Meaning |
|---|---|
| `eq`, `ne` | equal / not equal (if the value is an array, "includes") |
| `gt`, `lt`, `gte`, `lte` | numeric if both numbers, else text compare; false when empty |
| `in` | value is one of `value` (array) |
| `between` | `value:[from,to]` inclusive |
| `notempty` | has a value (no `value`) |

A field is visible if its own condition **and** its section's condition hold. Hidden fields are not required, not validated and not sent. A grid field's condition sees its own row first, then the form values. A condition outside a grid cannot reference a field inside a grid. Source: `src/features/connectumChat/utils/formEngine.js` (`evalCondition`), `utils/conditions.js`, server `sd_config:eval/2`.

## 4. Grid sections (repeating rows)

Section `{"grid": true}`; its fields (those with `section` = that name) live in the rows. Value: `values["items"] = [{"item":"Bolt","qty":4},{"item":"Nut","qty":9}]`. Max 200 rows. The client sends **every row in place**; an empty row is `{}` (server drops it) so error indexes match. Not allowed inside a grid: `slot`, `payment`, `file`, `subject`/`involve` lists. Errors: `items` for the count, `items.1.item` (row from 0) for a cell. See docs/GRID_SECTIONS.md.

## 5. Validation

- Client pre-check (`requiredErrors`): required (visible fields only, message "This field is required."), the field `rule` (if any, "<field> is not valid" or its message), phone validity for `mobile`. Rules are evaluated only on the client (the server stores them but does not run them); `calc` likewise.
- Server (`sd_config:check_values`, authoritative): required, type checks, ranges (`Must be at least N.` / `Must be at most N.` / `Must be on or after DATE.`), list membership, payment, file ids exist, read-only enforcement, conditions, grid rules.
- Error shape: `{"ok":false,"error":{"code":"invalid_values","message":"Some fields need attention.","details":{"fields":{"amount":"Enter a number.","items.1.item":"This field is required."}}}}`. Other codes seen: `submission_locked`, `forbidden`, `not_found`, `invalid`, `duplicate`.

## 6. Submitting

All over the WebSocket `/sd` envelope (see messages-and-receipts.md section 7).

| Step | Action and payload |
|---|---|
| List what the user can fill | `options.list` (options have `type:"data_input"`, `target` = form name, `targetScope`), `options.categories` |
| Get definition | `tstruct.get {"name":"expense_claim"}` (admin forms) or `tstruct.user.get` (forms made by people) -> `data.tstruct` |
| Submit | `tstruct.submit {"name":"expense_claim","values":{...},"chat":"dm:bob"}` or `tstruct.user.submit` for person-made forms. `chat` is optional: `dm:<user>` or `group:<name>` (never the global room); when present the server also posts the form into that conversation. Optional: `ref` (text <=200), `meta` (JSON object). |
| Reply | `{"ok":true,"data":{"submission":{...},"recordStatus":"saved"\|"pending","message":{"id":901,"ts":...,"conversation":"dm:bob"}}}` ; `message` is `null` if posting failed; `pending` = needs approval, and the chat message is posted only after approval. |
| Edit | `submissions.update {"id":42,"values":{...}}` (full values object, the same validation, read-only fields keep the saved value). Only author (or user with edit access). Locked while `status` is `pending` or `approved` (`submission_locked`). Refreshes every chat card of that submission. |
| Fix after rejection | `submission.resubmit {"id":42,"values":{...}}` (only if approver allowed) |
| Fetch one | `submission.get {"id":42}` -> `data.submission`; `submission.history {"id"}` -> events |
| List mine | `submissions.list {"offset":0}` (paged: `total, offset, limit, hasMore`) |
| Delete | `submissions.delete {"id":42}` |
| Forward card | `forms.forward {"id":<message id>,"chats":["dm:bob"]}` (max 10 targets; recipients without access never receive it) |

What the web client sends as `values` (`buildSubmission`): only visible, non-empty fields; strings trimmed; `wholenumber` -> integer, `number` -> number; `mobile` normalised; `payment` -> `{amount, status, method?}` (omitted if no amount); `autogenerate` omitted; grid sections as row arrays.

## 7. Submission object

```json
{
  "id": 42, "tstruct": "expense_claim", "scope": "global",
  "by": "alice", "host": null, "branch": "HQ", "ts": 1790071256909,
  "values": {"amount": 500, "date": "2026-10-28", "type": "Travel"},
  "labels": {"customer": "Acme Ltd"},
  "editedTs": 1790071999999,
  "status": "pending", "approval": {"stages":[{"type":"manager","status":"pending","name":"..."}], "current":0},
  "rejection": {"returned": true},
  "ref": "...", "meta": {}
}
```

`scope` is `"global"` (admin form) or `"user"` (person-made). `status` is absent for a plain record, else `pending` / `approved` / `rejected` (client `submissionState.js`). `editedTs` only after an edit. `labels` hold the text the person saw for sourced choices (also `"section.row.field"` keys for grids). Ids come from the server counter `sd:seq:sub`. Responses may add `files`, `byName`.

## 8. Form message in the conversation, and the chat card

A posted form is a normal chat message with `kind:"form"`, **stored once** and rewritten on edit (same id, `editedTs` set). It reaches the client three ways:

1. History item: `{id, ts, from, kind:"form", text:"Expense claim: Amount 500, Date 2026-10-28", form:{...}}` (`form` omitted if deleted).
2. Live: `{"type":"sd_event","event":"form_message","data":{"conversation":"dm:bob"|"group:name","id":901,"ts":...,"from":"alice","form":{...},"text":"<summary>"}}`; `conversation` is relative to the receiver.
3. Edit: `{"type":"sd_event","event":"form_message_updated","data":{same fields}}` (replace the card with the same id; show "edited").

`form` document (`sd_formmsg:payload`):

```json
{"structure":"expense_claim","scope":"global","caption":"Expense claim","submissionId":42,"by":"alice",
 "fields":[{"name":"amount","caption":"Amount","value":500},
           {"name":"paid","caption":"Payment","value":"500 INR, UPI, paid"},
           {"name":"doctor","caption":"Doctor","value":"dr.rao","label":"Dr. Rao"},
           {"name":"scan","caption":"Scan","value":"a.pdf","files":[{"id":"..","name":"a.pdf","mime":"application/pdf","size":123}]}],
 "about":"patient1","aboutCard":{"name":"..","username":"..","rows":[{"label":"Age","value":"34 years"}]},
 "forwardedBy":"carol","result":{"total":3,"message":"..."}}
```

Value rules in the card document (max 40 fields, each value clipped to 300 chars): payment becomes the string `"<amount> <currency>, <method>, paid|to pay"`; multi-choice list becomes `"A, B"`; numbers and booleans stay as is; null for empty; `label` carries the display text for sourced choices; `files` for file fields; `subject: true` marks the "about" field. Only fields present in `values` are included.

Card build (`utils/formMessages.js::formToCard`, rendered by `MessageList.jsx`): `title = form.caption || form.structure || "Form"`; subtitle/status = `Form #<submissionId>`; `details` = ordered map `caption (or name) -> displayValue(label ?? value)`; `detailFiles` from `files`; `dir` out if `from` is me; message id = server message id. If `aboutCard` is present, a first row (caption of the `subject` field, else "About") shows `name · age · gender · mobile · city` and the subject field is skipped. The author (and only when not forwarded and no `result`) can tap to re-open and edit via `submission.get` then `submissions.update`. Forwarded cards show "forwarded by". `displayValue`: arrays joined by ", "; object with `lat` -> `address` or "Pinned location"; object with `amount` -> `amount, method, paid|to pay`; else `String(v)`.

| Field kind | On the card (text) |
|---|---|
| Yes/No | no dedicated type (see UNCLEAR above); a list answer is the chosen string |
| Date | raw `YYYY-MM-DD` string; no locale formatting in the card |
| Amount (number) | the number as text, no currency |
| Amount (payment) | `"500 INR, UPI, paid"` (or `to pay`) |
| Location | `Pinned location` (or address if present) |

Summary `text` (sidebar preview, notifications): `"<caption>: <field caption> <value>, ..."` for the first 6 fields, with `-` for null, `yes`/`no` for booleans; a result document shows `"<caption> (N rows)"`. The conversation list shows this text only if the viewer may see the form, else empty.

Visibility: the submitter, the person it is about (`about`), admins, any user with access to the structure (or read access `readableBy`) see it; others in the conversation never receive it. Forms can be posted only to a DM or group, never the global room.

UNCLEAR: are grid-section rows included in the chat card? `payload` only takes fields whose name is a top-level key of `values`, and grid fields live inside `values[sectionName]`, so rows look to be omitted from the `form.fields` list, yet docs/GRID_SECTIONS.md says the chat card shows "1. Bolt, 4; 2. Nut, 9". Not confirmed by running it.

UNCLEAR: submission `status`/`approval` shape beyond `pending|approved|rejected` and `stages` (owned by `sd_subflow.erl`, not read in detail).

## Source files

- axi-chat-backend/src/sd_config.erl (types, validate_fields, field_extras, check_type, check_values, do_submit, update_submission, eval), sd_formmsg.erl, sd_cmds.erl (tstruct.*, submissions.*, submit_with_chat, submit_reply), sd_notify.erl
- src/features/connectumChat/utils/formEngine.js, formMessages.js, conditions.js, submissionState.js
- src/features/connectumChat/components/modals/SmartStructureModal.jsx (submit/edit), src/features/connectumChat/ConnectumChatScreen.jsx (form_message handlers, openSubmissionEdit), components/MessageList.jsx
- web/src/core/defaults.js, fieldTypes.js, validation.js (studio side), docs/FIELD_DEFAULTS.md, FIELD_RULES.md, GRID_SECTIONS.md, FETCH_RULES.md
