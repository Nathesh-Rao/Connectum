# API-visible changes, and the schema version

For the mobile team and anyone else who builds against the API: **what changed that a client can see**, newest first, and the version number to compare against. A change that a client cannot see (an internal fix, a screen) is not listed here. The commit on `dev` is the `release` in `GET /api/sd/version`; the docs of that commit are the docs of that release.

## Schema versions

`GET /api/sd/version` answers `{ ok, data: { release, node, environment, schema } }`. `schema` is a **whole number kept in the code** (`?SCHEMA_VERSION` in `connectum-backend/src/http/sd_http.erl`). It is raised **in the same pull request as anything that breaks a client**: a request or answer field removed or changed in meaning, a command removed, a stored shape an older app cannot read. Adding a field, a command or a refusal code does **not** raise it.

A client reads `schema` before a test run or at start-up and compares it with the number its own docs were written for. A different number means: read the entry below for that number before trusting the app against this server.

| schema | from | what it is |
|---|---|---|
| 1 | 13 Nov 2026 | The first number. It describes the API as documented in `docs/CONNECTUM_API.md`, `docs/MULTI_ENTERPRISE.md` and `docs/CHAT_PROTOCOL.md` at that date. |

## Changes (newest first)

Rule: the pull request that changes the API adds its line here and updates the document of the endpoint, in the same change.

### 16 Nov 2026 (schema 1, nothing breaking): the conditions of a list of employees can wait on a field of the form
- A field `{type:"list", source:"users"|"people"}` whose `peopleQuery.params` is not empty ("Only when Designation is the Helper field of this form") is **asked for**, not carried with the form: ask `datasource.run {tstruct, scope?, field, values, search?}` like a Drop Down that reads another form, and show it as that kind of field (`selection`, `source = peopleQuery`, Multi Select too). The answer is `{rows:[{value, label}], total, truncated, waiting?}`: `value` is what the record keeps (Save: the username unless the list says otherwise), `label` what people see (Show); `waiting: true` (no rows) while a field it waits on is empty. `search` narrows by the label.
- The form still carries `options` (everyone) for such a field, so a client that does not know this shows everybody; the server refuses a person the conditions do not offer when the record is saved (`invalid_values`, details.fields.<field>: "Choose only people this list offers." / "Fill in the fields this list depends on first."). Mobile: treat such a field as a selection (the same rule as the web: `list` with a non-empty `peopleQuery.params`).
- A list without such a condition is unchanged. "Narrow by another field" (`dependsOn`) is unchanged and now offers any single-value field in Studio.
- A list of employees also has the other parts of a Drop Down that reads another form: `peopleQuery.sort` (`{field, dir, calc?}`: the order of the choices, in `options` and in the answer to `datasource.run`) and `peopleQuery.columns` (Employee columns brought with each person). The columns reach a Fill field below in two ways: the form carries `optionData` (`{ <saved value>: { <column>: text } }`, the same as for a list from an API; the screen passes it to the Fill when a person is chosen), and a list that is asked for gives each row the columns (`columns: ["value","label",...]`). The e-mail and the mobile number are never brought to someone who is not an administrator.

### 16 Nov 2026 (schema 1, nothing breaking): auto send takes people from a Drop Down that reads another form
- `query.forms`: each field of a form may carry `person: true` (it holds a person: a people drop down, a Drop Down that reads or a Fill that copies a people field of yet another form, or the Employee form's employee code and its unique own fields). Only added where true.
- A form's `autoSendRules[].fields` may now name such a Drop Down, Multi Select or Fill (a task's "Assign to" fed by a project master's "Project team"); saving still refuses a field that holds no person. At run time the person is found through the other form's own Save (alias, employee code).

### 16 Nov 2026 (schema 1, nothing breaking): hidden fields are not listed for the Smart view
- `ai.enterprise {what:"forms"}`: a field with `hidden: true` is no longer in a form's `fields` (for everyone, administrators included), and neither are the four hidden fields a status keeps (`<status>_completion`, `_comments`, `_files`, `_hours`). A client that drew columns from this list now shows no hidden column. `tstruct.get`, the records (`submissions.list`, `records.mine`) and `form.*` are unchanged: a hidden field is still in the form's definition and in the stored values. `schema` is not raised (no field of the answer's shape was removed or changed in meaning).

### 14 Nov 2026 (schema 1, nothing breaking): managers read their team's records
- `records.mine` has a new `as: "team"` (a manager's list: the open records that are with, sent or shared to, or raised by one of their direct reports, whoever made them; never the caller's own; newest first; read in steps, continue from `next`). Every item carries `team: {members, via}`; the answer carries `reports` (the number of direct reports). Full description, example and rules: `docs/CONNECTUM_API.md`, "Team records".
- A person's own object (`me` -> `user`, the sign-in answers, `profile.get`, `profile.update`) carries `hasReports` (true while an active person reports to them). Offer the Team list only then.
- A manager now **reads** (read only) every record that is with, or was sent or shared to, a direct report: `submission.get`, `submissions.list`, `records.list` and the Smart View lists include them. `submission.get` also opens what a direct report made (it did not before; the lists already did).
- New form setting `hideFromManagers` (boolean, default false): `admin.tstruct.save`, `tstruct.user.save`, `tstruct.user.update` accept it, the `*.get` answers return it. It turns the team rule off for that form.

### 14 Nov 2026 (schema 1, nothing breaking)
- An API whose stored key cannot be read (the server's encryption keys changed) is no longer given a new key behind the administrator's back. Its Get, List and Put calls, the test button and `admin.api.key` (read) now fail with `unavailable` (a Put through the consumer: status 503, so it is tried again later) and the message "This API's key cannot be read ...". `admin.api.key` with `value` or `rotate:true` repairs it. `admin.api.list` / `admin.api.save` answer carry a new boolean `keyReadable` (`false` when a key is stored and cannot be read; `true` otherwise, also for an old API that has no key yet, which still gets one on first use).

### 13 Nov 2026 (schema 1, nothing breaking)
- `GET /api/sd/version` has a new field `schema` (above).
- `/setavatar`, `/removeavatar` and `/setstatus` now answer their sender: `{"type":"ack","cmd":"setavatar","ok":true}` on success, `{"type":"error","cmd":"setavatar","code":"invalid_avatar"|"invalid_status","text":...}` on refusal (`docs/CHAT_PROTOCOL.md`). A command refused for going too fast says `{"type":"error","cmd":...,"code":"rate_limited"}`. The text of every error is unchanged.
- `POST /upload` is limited per signed-in person (20 a minute), no longer per address; a request with no session is still limited per address (`docs/CHAT_PROTOCOL.md`, `POST /upload`).
- `POST /api/sd/login/password`: a `429 rate_limited` carries `error.retryAfter` (whole seconds); the section "Signing in with a password of one's own" is added to `docs/MULTI_ENTERPRISE.md`. `error_body` now lifts a `retryAfter` out of `details` for any refusal that has one.
- Dev only: `CONNECTUM_MAIL_ALLOW` limits mail to listed addresses and domains (`docs/EMAIL_SETUP.md`); `tools/mobile-test/seed.mjs --password` (`docs/MOBILE_TEST_ENVIRONMENT.md`).
