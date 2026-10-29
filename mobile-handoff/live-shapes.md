# Live shapes (test server http://10.0.2.146, org Y2NH-GHP6 "Test organisation Mobile team", user amirthanath)

Captured 2026-10-29 from the phone log with the debug read tools (reads only; no conv.read, no markRead, nothing sent or submitted). Redacted: encrypted bodies (`ct`, `ek`, `keys`, `sig`, `iv`, `dev`, `mid`) and avatars. Session org/user confirmed on the debug screen: `org/user: Y2NH-GHP6 / amirthanath`. Note: logcat cuts very long `RAW` lines (the middle is lost); the on-screen "Last 20 events" shows the rest.

## Enterprises
`me.enterprises`: Agile Space WR4Q-BHSK, Kauvery hospital 2Z73-TQ5C, Test organisation Mobile team Y2NH-GHP6, all `status:"active"`. Public search "Test organisation" -> `[{"id":"Y2NH-GHP6","name":"Test organisation Mobile team"}]`.

## `/hosts`
`{"type":"hosts","list":[{"key":"openai","name":"Open AI","kind":"llm"},{"key":"ai_router",...,"kind":"llm"},{"key":"claude",...},{"key":"gemini",...},{"key":"workspace","name":"My work space","kind":"workspace"}]}` (no department hosts). `/history host workspace` -> `{"type":"history","scope":"host","host":"workspace","list":[]}`: empty, as expected (workspace is client-side only).

## Conversation row (`/conversations`)
`{"type":"conversations","list":[{"with":"arjun.s","id":4,"ts":1793251852752,"from":"arjun.s","text":"Test Mobile: Description Hi bro, Location Field {\"lat\":12.918566617853976,\"lng\":77.574456833656}","archived":false,"avatar":null}]}`. No kind, no unread, no e2e flag in this row. `id` = id of the last message (4 = arjun's form), `text` = `sd_formmsg:display` of that form message (server-built; this is where the web list preview comes from). `/groups` -> `[]`. Global history `[]`.

## DM history `/history dm arjun.s` (4 items)
- id 1 and 2: `kind:"chat"`, `private:true`, `e2e:true`, `text:"e2e1:{conv,ct,dev,ek,from,iv,keys,mid,sig,ts,v}"`, `reactions:[{"user":"amirthanath","emoji":"<laugh>"}]` on id 1, `deleted:false`, `editedTs:null`, `replyTo:null`, `previewUrl/Title/Description/Image:""`.
- id 3 (my form, sent as received): `{"id":3,"ts":1793251813955,"from":"amirthanath","text":"<88-char summary>","kind":"form","private":true,"reactions":[],"deleted":false,"editedTs":null,"replyTo":null,"form":{"by":"amirthanath","caption":"Test Mobile","fields":[{"caption":"Description","name":"description","value":"This is a test"},{"caption":"Location Field","name":"locationField","value":"{\"lat\":12.918562,\"lng\":77.57447}"}],"scope":"user","structure":"test_mobile","submissionId":25},"previewUrl":"",...}`.
- id 4 (arjun's form): same shape, `from:"arjun.s"`, `form.by:"arjun.s"`, `submissionId":26`, description "Hi bro", location value `"{\"lat\":12.918566617853976,\"lng\":77.574456833656}"`.
- Form items have **no `e2e` key** and a plain-text `text`, inside an e2e thread. No `label`, no `files`, no `about`, no `forwardedBy`.
- Location in a form message is a **string containing JSON** (not an object, not an address): the server is older than backend commit e865c83e. The grid section (`section2Sec`, "numeric Text 12", "test field test") is **absent** from `form.fields`.

## `options.list` / `options.categories`
`{"options":[{"caption":"Test Mobile","category":"data_input","display":null,"id":"test-mobile","order":0,"owner":null,"target":"test_mobile","targetScope":"user","type":"data_input"}]}` (one option). Categories (with counts, `includeEmpty:true`): data_input 1 (edit_note), download, upload, get_data (query_stats), link, axpert (executable:false), page (web) - others 0; `total:1`.

## `cmd.list` / `/cmds`
`cmd.list` -> `{"commands":[],"kinds":["option","tstruct","list","datasource"]}` (no custom commands on this account). `/cmds` -> `cmd_catalog` with `categories` and ~24 commands for this user (dm, reply, historydm, group..., host, historyhost, profile, requests, accept, reject, transfer, tstruct, tstruct-add, help ...; logcat cut the middle).

## `submissions.list {offset:0}`
`{"hasMore":false,"limit":500,"offset":0,"total":1,"structures":{"test_mobile":{"caption":"Test Mobile","fields":{"description":"Description","locationField":"Location Field","numericText":"numeric Text","testField":"test field"}}},"submissions":[{"by":"amirthanath","host":null,"id":25,"scope":"user","ts":1793251813953,"tstruct":"test_mobile","values":{"description":"This is a test","locationField":{"lat":12.918562,"lng":77.57447},"section2Sec":[{"numericText":12,"testField":"test"}]}}]}`. Only my submission (#25); arjun's #26 is not listed. The response carries a `structures` map (caption + field captions, no types), so cards can be titled and labelled without `tstruct.get`. Location is an object `{lat,lng}` without `address`; grid is an array of row objects (no `__k`). No `status`, `labels`, `ref` keys here.

## `tstruct.user.get {name:"test_mobile"}` (targetScope user)
`{"tstruct":{"caption":"Test Mobile","createdTs":1793251679040,"description":"","name":"test_mobile","owner":"amirthanath","registers":null,"saveToDb":true,"sections":[{"caption":"Section 1","condition":null,"name":"section1Sec"},{"caption":"Section 2","condition":null,"grid":true,"name":"section2Sec"}],"fields":[{"name":"testField","caption":"test field","type":"text","required":true,"multiline":false,"rich":false,"section":"section2Sec","condition":null},{"name":"numericText","caption":"numeric Text","type":"wholenumber","required":true,"section":"section2Sec","condition":null},{"name":"description","caption":"Description","type":"text","required":false,"multiline":true,"rich":false,"section":"section1Sec","condition":null},{"name":"locationField","caption":"Location Field","type":"location","required":false,"section":"section1Sec","condition":null}]}}`. Grid is flagged on the **section** (`grid:true`); its columns are the fields whose `section` is that name. No `allowForward`, `readableBy`, `defaultNow` keys on this person-made form.
