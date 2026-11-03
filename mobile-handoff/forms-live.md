# Forms: how the real data behaves (B, C, D, E)

Source: backend `origin/main` (sd_formmsg.erl, sd_config.erl, sd_place.erl, sd_e2e.erl, sd_cmds.erl), web `formMessages.js`, `formEngine.js`, `ConnectumChatScreen.jsx`. Live payloads are in live-shapes.md (captured 2026-10-29). The test server runs an OLDER build than `origin/main` (location and form-message shape differ, see C); trust live-shapes.md over the source where they differ.

## B. Flow
1. `options.list` -> option `{type:"data_input", target:"<form name>", targetScope:"admin"|"user"}`. `targetScope` = which kind of form the target is: `admin` (admin-managed) -> `tstruct.get` / `tstruct.submit`; `user` (made by a person) -> `tstruct.user.get` / `tstruct.user.submit` (set by `check_target` in sd_config.erl). `options.categories` only gives pills (icon/count).
2. `option.run` is for non-form types only (download, get_data, link...). Never for data_input.
3. `tstruct.submit {name, values, chat?, ref?, meta?, saveTo?, axpert?}`. `chat` (`dm:<u>`|`group:<g>`) makes the server also post a form **message** into that conversation (reply `data.message {id,ts,conversation}`, `null` if not posted; with approval pending it is posted after approval). Without `chat`: no message, only the submission (it shows in the workspace and My Submissions). `ref` is stored on the submission (client reference, text); `meta.clientId` = idempotency. The `host` arg in sd_cmds is the onboarding *approver* host of a user, unrelated to chat hosts. `scope` in the form message is the submission scope (`global` default, `user` for person-made forms).
4. The form message is a normal message row (`kind:"form"`, `private` for DMs), plain JSON text, stored once in the conversation (`dm:a|b` or `group:g`), rewritten on edit (`form_message_updated`).

## Payload as received (history item and `form_message` event)
`{id, ts, from, kind:"form", text:"<caption>: <field caption> <value>, ... (first 6)", form:{structure, scope, caption, submissionId, by, fields:[{name, caption, value, label?, files?, subject?}], about?, aboutCard?, forwardedBy?, result?}}`. Values: payment -> string "500 INR, UPI, paid"; list multi -> "A, B"; location -> address text, else "lat, lng" (6 decimals) since backend commit e865c83e (2026-10-29); null stays null; max 40 fields, 300 chars each. Fields are included only if their name is a top-level key of `values`. Sent side = the `tstruct.submit` args above; labels come from `submission.labels`.

## Why the three cards differ (same submission #25)
- Workspace card = rebuilt client-side from `submissions.list` (title `"<caption> submitted"`, line `Submission #25`, full `values`, Edit when status allows).
- DM card = `formToCard(form message)`: title caption, line `Form #<submissionId>`, details from `form.fields` only. **Edit button only when `mine && submissionId && !forwardedBy && !result`.**
- arjun's card is `from: arjun` -> not mine -> no Edit; his number is 26 simply because it is his submission (his `submissionId`). `forms.forward {id: msgId, chats:[...]}` copies the same document with `forwardedBy` (max 10 targets, 60/min, refused for `result` docs and `allowForward:false`); a forwarded card also loses Edit.

## C. Field value shapes
- Location (stored/submit): `{"lat":12.97,"lng":77.59,"address"?:"..."}` (also accepts "lat,lng"). Since e865c83e the address is saved with it; earlier builds kept lat/lng only (forms.md section 1 is outdated on that). In form messages: a **string** on new servers (address, else "lat, lng"); on an older server the value was the raw object, which matches the raw `{"lat":..,"lng":..}` seen in the DM card and list preview. Mobile card: handle both: string as is; object -> `address` else "Pinned location" (web `displayValue`), optionally coordinates.
- Grid section: `values["section2Sec"] = [{"colA":12,"colB":"test"}, ...]` (row objects, no `__k`; max 200). **The form message omits grid sections entirely** (`sd_formmsg:payload` takes only fields whose name is a key of `values`; grid columns live inside the section array). So the DM card cannot show them although docs/GRID_SECTIONS.md claims it does; only the workspace card (from `submissions.list`) shows `1. 12, test` (web `displayValue`: rows joined `"1. a, b; 2. c, d"`, empty cells dropped). Mobile: DM card = show what the message has; for the grid fetch `submission.get {id}` when the card opens (author only) or mark it a backend gap. Raise with backend.
- Description (`text`) -> plain string.
- **Confirmed live:** location in a form message is a *string containing JSON* (`"{\"lat\":12.918562,\"lng\":77.57447}"`), in `submissions.list` an object `{lat,lng}` without address; grid section absent from the form message, present in `submissions.list`. `tstruct.user.get` for test_mobile is in live-shapes.md (grid = `sections[].grid:true`). Mobile card: if value is a String that parses as a map with lat/lng, treat as object; object -> `address` else "Pinned location".

## D. List preview
"Test Mobile: Description Hi bro, Location Field {...}" = `sd_formmsg:display/1`, stored/pushed as the item `text` (and the conversation row's last text): `"<caption>: <field caption> <value>, ..."`, first 6 fields, `to_bin` of objects -> raw JSON on old builds. App now shows `"<caption> submitted"` plus a document icon (conversation_tile.dart `_text`), ignoring the server text.

## E. Encryption
- Forms are never encrypted: `post` saves `jenc(Doc)` as plain text with kind `form`; `check_target` only checks `can_message`/group membership; there is no e2e check in the form path (e2e is enforced only in `chat_web` send path `check_send`). `for_viewer` only touches texts starting with `e2e1:`. So a form can be sent into an e2e thread and is readable there.
- Mobile rule today is "e2e threads read-only", which blocks sending forms (the compose area is `isBlocked`). Decision for the user: allow the forms pills in an e2e thread (server allows it) or keep it blocked in v1.

## Mismatches app vs server/web
1. List preview ignores the server `text` (shows "<caption> submitted"; web shows the one-line summary).
2. No form card UI yet (only `form_json` stored): needs `formToCard` rules above (title caption||structure||"Form", `Form #id`, Edit rule, files, label over value, forwarded badge).
3. Edit button rule must be `mine && !forwardedBy && !result`; workspace cards come from `submissions.list` instead.
4. `lastIsEncrypted` is checked before `lastKind == 'form'` in the tile; a form must never be shown as "Encrypted message" even in an e2e thread.
5. Grid sections missing in form messages; location may arrive as a raw object on older servers.
6. forms.md section 1 "server keeps only lat/lng" is outdated; section 8 UNCLEAR about grid rows is answered: omitted.
7. `form_message_updated` must replace the card by id; unread for form messages follows the normal message path (not verified live).

## Confirmed / corrected by live data
- Form messages in the e2e DM are plain (`kind:"form"`, no `e2e` key), so forms are readable there. Server-side permission to *send* a form into the e2e thread still comes from source only (not tried; nothing was submitted).
- Conversation row has only `with,id,ts,from,text,archived,avatar`; `text` is the server's `display()` summary, so the web preview comes from the server. The app's own `<caption> submitted` replaces it.
- Form `scope` is `user` (person-made form, `targetScope:user`); submission ids are global (25 mine, 26 arjun's).
- `submissions.list` returns only my submissions and a `structures` map (caption + field captions).
- Still unverified: `ref`/`labels`/`status` keys (absent here), `forms.forward` result, approval flows.
