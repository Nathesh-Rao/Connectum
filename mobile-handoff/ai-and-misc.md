# Mobile handoff: AI assistant, files/media, E2E, notifications

Source of truth is code (paths at the end). Backend = `axi-chat-backend` (Erlang). `<token>` = session token from Connectum login. Placeholders only; no secrets.

## 0. Transport basics used below

| Item | Value |
|---|---|
| WebSocket | `ws(s)://<host>[/ws]`; first frame JSON `{"username","token"}` (`armSessionId` optional). Behind nginx the path is `/ws`; standalone it is the root path. |
| Connectum action call (WS) | send text frame `/sd <action> {json args incl. "reqId"}` |
| Reply envelope | `{"type":"sd","action":"<a>","reqId":<echo>,"ok":true,"data":{...}}` or `{"ok":false,"error":{"code","message","details"}}` |
| Live pushes | `{"type":"sd_event","event":"...","data":{...}}` |
| REST | `https://<host>/api/sd/...`, `Authorization: Bearer <token>`; JSON error shape `{"error":{"code","message"}}` (web client reads `error.message`) |
| Client timeouts (web) | default 10 s per `/sd` call; `assistant.relay` 40 s; `ai.models` 25 s |

## 1. AI assistant (My Workspace "AI" view)

**Not streaming.** One request, one complete JSON answer. The server removes any `stream` key from the payload (`relay_with`). No chunks, no SSE.

**Architecture (important):** the server is only a keyed relay to the LLM provider. The *client* builds the provider-format request, runs the tool loop (max 4 rounds), builds the system prompt and context. A mobile client must reimplement `workspaceAgent.js` logic or call the relay the same way.

### 1.1 Actions (WebSocket `/sd` only; no REST route exists for these)

| Action | Args | Returns (`data`) | Notes |
|---|---|---|---|
| `ai.agents` | `{}` | `{agents:[{id,name,alias,provider,model,modelChoice, ...plugin roles}]}` | Only agents the user may use; never key/address. Cached client-side. |
| `ai.models` | `{agent, refresh?:true}` | `{models:[{id,name}], source:"provider"\|"catalog", default, choice:bool, provider}` | Slow lane. Server caches 10 min; `refresh` limited 3/min. |
| `assistant.relay` | `{agent?, payload, model?, timeoutMs?}` | `{status:<provider HTTP code>, body:<provider JSON>, modelUsed, fellBack}` | Slow lane. `agent` optional only if user may use exactly one agent. `timeoutMs` 5000..90000 (default 20000). |
| `ai.enterprise` | `{what:"forms"}` or `{what:"people", q?}` | `{forms:[{name,caption,fields:[{name,caption,type}]}]}` / `{people,total}` | Tool data for the assistant; people = admins only (`forbidden` otherwise). |
| `ai.conv.list` | `{limit?:30, before?:<updated of last row>, q?, agent?}` | `{conversations:[{id,title,agent,preview,count,updated,created,focus,pinned}], pinned, more, total}` | `q` = search (max 50, not paged, 30/min). |
| `ai.conv.get` | `{id}` | `{conversation:{...,messages,focusText}}` | |
| `ai.conv.save` | `{id,agent,title?,messages,focus?}` | `{conversation}` | `id` is client-made, regex `^[A-Za-z0-9_-]{4,40}$` (web: `c<base36 time><rand>`). |
| `ai.conv.rename` / `pin` / `delete` | `{id,title}` / `{id,pinned}` / `{id}` | ok | Own conversations only; max 30 pinned. |

Stored-conversation limits: 200 per user, 4 MB total, 60 messages / 48 KB each (web trims to 44 KB, 60 msgs, 6000 chars/msg, oldest dropped), untouched 180 days deleted (pinned kept). Message saved shape: `{mid, role:"user"|"ai", text, quoteId?, quote?, jobId?}`; `focus:{label}` only (transcript not stored).

### 1.2 `assistant.relay` payload by provider (built by client)

| Provider | `payload` (client sends) | Answer text read from `data.body` |
|---|---|---|
| openai, openrouter, grok, groq, deepseek, sambanova, custom | `{model, temperature:0, messages:[{role:"system",content},...past,{role:"user",content}], tools?:[{type:"function",function:{name,description,parameters}}]}` | `choices[0].message.content`; tool calls in `choices[0].message.tool_calls[]` (`function.arguments` is a JSON string); reply with `{role:"tool",tool_call_id,content}` |
| anthropic | `{model, max_tokens:1800, temperature:0, system, messages, tools?:[{name,description,input_schema}]}` | `content[]` blocks: `type:"text"` / `type:"tool_use"{id,name,input}`; reply `{role:"user",content:[{type:"tool_result",tool_use_id,content}]}` |
| gemini | `{systemInstruction:{parts:[{text}]}, contents:[{role:"user"\|"model",parts:[{text}]}], generationConfig:{temperature:0}, tools?:[{functionDeclarations}]}` | `candidates[0].content.parts[]` (`text` / `functionCall`); reply part `{functionResponse:{name,response:{result}}}`; schema types upper-cased |

Example call and reply:

```
/sd assistant.relay {"agent":"claude","model":"claude-haiku-5-5","reqId":"ui-3","payload":{"model":"claude-haiku-5-5","max_tokens":1800,"temperature":0,"system":"...","messages":[{"role":"user","content":"Summarise my group chat \"Ops\"..."}]}}
-> {"type":"sd","action":"assistant.relay","reqId":"ui-3","ok":true,"data":{"status":200,"body":{"content":[{"type":"text","text":"..."}]},"modelUsed":"claude-haiku-5-5","fellBack":false}}
```

Server behaviour: adds key and provider URL (anthropic `x-api-key` + `anthropic-version: 2023-06-01`; gemini `x-goog-api-key`; others `Authorization: Bearer`, `<base>/chat/completions`); `model` in args is honoured only if the provider lists it for that key and `modelChoice` is not false, else agent's model ("Auto"); on 404/429/5xx (or 400/403 mentioning model) retries up to 2 more models of the same provider (`fellBack:true`). Limits: request 200 KB, answer 2 MB, 20 s default timeout, 30 calls/min per user, 600/min per agent.

Error handling: transport-level `ok:false` codes `no_agent`, `no_access`, `not_found`, `invalid` ("Choose which AI agent"), `rate_limited`, `too_large`, `upstream_timeout`, `upstream_unavailable`, `forbidden_address`, `key_unreadable`. `ok:true` with `status` outside 2xx = provider error; web maps via `assistantErrors.js` (402/credit text -> no_credit, 401/403/key text -> bad_key, 429 -> rate, 404/model -> model, 413 -> too_large, 502/503/504/529 -> busy, 400 -> bad).

### 1.3 What the client adds around the question (`askWorkspaceAgent`)

- System prompt = persona + data-use rules + `AI_STYLE_GUIDE` + chat directory + attached files + chat in focus + a compact "WORKSPACE DATA" of notifications/tasks (30 s cache; loaded from `GET /api/sd/feed?limit=120`, `/sd task.list`, `/sd assoc.list`).
- History: last 10 turns, each cut to 2500 chars (`user`/`assistant`).
- Client-side tools (executed on device, results fed back to the model): `list_chats`, `read_chat {chat,kind?,since?}` (loads history via the chat WebSocket `history` event, up to a transcript limit), `find_notifications`, `enterprise_forms/_submissions/_people` (via `ai.enterprise`/`submissions.list`), `list_patients`/`patient_overview`, Data Bin report tools (`list_data_bins`, `create_report`; separate report service), optional plugin tools (`search_workspace`, `ask_retrieval_agent`, `design_structure`).
- Reports return `{ok:true,text:"",job}` (a job card, not text).
- Result shape to UI: `{ok:true,text,job?,cards?}` or `{ok:false,code,error,needsKey?,needsTopUp?}`.
- Answer rendering (`aiFormat`): Markdown plus a fenced ```` ```chart ```` block holding JSON `{"type":"bar|column|line|donut","title","unit","data":[{"label","value"}]}` or `{"labels":[],"series":[{"name","data":[]}]}` (max 40 labels, 6 series). Mobile must render these itself.
- Attached files in AI view are NOT uploaded: read on device as text, max 5 files, 5 MB each, 40,000 chars each, 120,000 total; text-like extensions only (`aiFiles.js`).

### 1.4 Chat summaries

| Kind | How | Source |
|---|---|---|
| "Summarise this chat" | No dedicated endpoint. Client sends one `askWorkspaceAgent` question: `Summarise my <group chat\|private chat> "<label>"<, only the messages from YYYY-MM-DD on \| , from the beginning>. Give the main points, the decisions made, anything still open or unanswered, and the action items with who owns each. Keep it short...`; model calls `read_chat` itself. Ranges: Everything / Today / 7 d / 30 d / date. History `[]`, nothing posted to the chat. | `ChatSummaryModal.jsx` |
| Care-thread summary card Q&A (patient thread) | `askAboutThread`: loads group history `care-<username>`, transcript max 400 msgs / 70,000 chars + structured record + team roster, one relay call (single round, no tools) | `workspaceAgent.js`, `threadAsk.js`, `careSummary.js` |

Care-thread Q&A is kept only on-device (`threadAsk.js`); not saved on the server.

### 1.5 AI agents and provider selection

| Topic | Fact |
|---|---|
| Who defines agents | Admin only (`admin.ai.list/save/delete/test`); keys belong to the organisation, sealed on the server, never returned (only `last4`). Employees cannot enter keys (old browser-stored keys are purged). |
| `admin.ai.save` args | `{id?,name(1-40),alias(2-20 chars [a-z0-9_-], starts with letter; command typed after #),provider,model?,baseUrl?(custom/optional),key?,enabled?,modelChoice?,access?,roles?}`; max 12 agents. |
| Providers | `openai, anthropic, gemini, openrouter, grok, groq, deepseek, sambanova, custom` (custom needs public http(s) `baseUrl`; private addresses refused). |
| Who may use | per-agent permission `ai:<id>` (Admin console > Permissions); `ai.agents` already filters. |
| Roles (plugin) | `docs/AI_AGENT_ROLES.md`: orchestration / RAG / coding agent; My Work Space lists RAG agents and orchestration agents whose place includes Structures. Role fields come back in `ai.agents`. |
| Selection in UI | Agent chips (when >1 agent) in the AI view and summary modal; model picker from `ai.models` (sent as `model` on every relay while chosen agent matches). |
| Default models (client) | openai `gpt-4o-mini`, anthropic `claude-haiku-5-5`, gemini `gemini-2.0-flash`, openrouter `openai/gpt-4o-mini`, grok `grok-3-mini`, groq `llama-3.3-70b-versatile`, deepseek `deepseek-chat`, sambanova `Meta-Llama-3.3-70B-Instruct` |
| Not for mobile | `providerSwitcher`, `promptTemplates`, `systemPromptEditor`, `exportChat` are ported from the older Axpert DataBin page (browser-global keys / DOM scraping; export = DOM to `.md` download). They do not use `ai.agents` / `assistant.relay`. |

### 1.6 Other assistant-related

`#<alias>` chat commands exist for agents (alias reserved list in `sd_assistant.erl`); how `#alias` is answered is outside this scope (see `docs/HASH_COMMANDS.md`). UNCLEAR: does `#<alias>` in a chat call the relay server-side (`relay_embed`/other) or is it only a menu entry? Embeddings (`relay_embed`) exist server-side for the RAG service (OpenAI/Gemini only) but have no client action.

## 2. Files and media

Two separate mechanisms.

### 2.1 Chat attachments: `POST /upload` + `GET /uploads/<name>`

| Item | Value |
|---|---|
| Upload | `POST {origin}/upload`, `multipart/form-data`, one file part named `file` (any field name works: first file part is taken; `filename` and part `Content-Type` are used). Not JSON. |
| Auth | `Authorization: Bearer <token>`. Optional in plain/open mode; **required** in strict Connectum orgs (`401 "Sign in to upload."`). Invalid/expired token = `401 "Session expired. Sign in again."`. Signed-in uploads count against the user's "media" allowance (`413` with message when full). |
| Origin | Web tries the page origin then `connectumApi.getServerOrigin()` (base URL minus `/api/sd`). |
| Success `200` | `{"url":"/uploads/<48 hex>.<ext>","type":"<normalized mime>","size":<bytes>,"name":"<cleaned original name, max 100>"}` (URL is relative: prefix with server origin). |
| Allowed types / max | images png,jpeg,gif,webp and audio webm,ogg,mp4: **8 MB**; PDF, docx, xlsx, pptx, text/plain: **20 MB**; video mp4,webm,quicktime: **25 MB**; E2E blob `application/x-connectum-e2e`: ~25.5 MB. Request body hard cap ~26 MB. Mime params (`;codecs=opus`) are stripped. Magic bytes are checked against the declared mime; text must be UTF-8 without NUL. |
| Errors | `400` empty / no file / not multipart; `401`; `413` too large (message names the max MB) ; `415` type not allowed or content mismatch; `429` rate limit **20 uploads / 60 s per IP**. Body `{"error":"..."}`. |
| Extensions stored | png jpg gif webp webm ogg m4a mp4 vwebm mov pdf docx xlsx pptx txt e2e |
| Download | `GET {origin}/uploads/<name>`. **No auth header needed** (name is the unguessable 24-byte random hex). `Content-Type` by extension; `X-Content-Type-Options: nosniff`; documents get `Content-Disposition: attachment`; `Accept-Ranges: bytes`; supports `Range: bytes=N-M` / `bytes=N-` (`206`) for audio/video seek. `Cache-Control: no-cache`. Bad names (`/`, `\`, `..`) give 404. |
| Thumbnails | **None.** No thumbnail/resize endpoint; images are served as uploaded. UNCLEAR: whether mobile should generate thumbnails locally (nothing in code does server-side). |
| Linking to a message | No server link. Client sends the text `[ATTACHMENT:{"kind":"image\|video\|audio\|file","name","size","url":"/uploads/...","type","e2e"?:{"key","iv"}}]` as the message body (plus optional text outside the tag). A bare `/uploads/...` or `http(s)://host/uploads/...` message is also parsed as an attachment (legacy). |
| Avatar | upload same endpoint (images only, 8 MB), then `/setavatar <url>`; url must start with `/uploads/` or `https://`, max 300 chars. |
| Web fallback | If upload fails the web app embeds a data/blob URL locally (`isLocal:true`); not valid for other users. Do not copy. |
| Client-side checks (web) | attachment max 25 MB; avatar 8 MB and image types only. |

Inconsistency: `docs/CHAT_PROTOCOL.md` says only images/voice up to 8 MB; `chat_web.erl` allows docs/video as above. Code wins.

### 2.2 Form/option files: `/api/sd/files` (REST, authenticated)

| Call | Detail |
|---|---|
| Upload | `POST /api/sd/files?name=<url-encoded filename>`; **raw bytes as body** (not multipart); `Content-Type: <file mime>` (default `application/octet-stream`); `Authorization: Bearer <token>`. Response `{ok,data:{file:{id,name,mime,size,by,ts}}}`. |
| Limit | 10 MB default (`CONNECTUM_MAX_FILE_MB`; nginx must match); 60 uploads/hour per user; per-user "files" allowance. Errors `too_large` ("File too large (max N MB)"), `rate_limited`, `bad_request` (empty). |
| List | `GET /api/sd/files` -> `{data:{files:[...]}}` (own uploads). |
| Download | `GET /api/sd/files/<id>` with Bearer; response body is bytes, always `application/octet-stream`, `Content-Disposition: attachment; filename*=UTF-8''<enc>`, header `X-File-Name` (URL-encoded name); `Cache-Control: private, no-store`. Readable by uploader, admin, or anyone a download option points at. |
| URL-sourced download option | `GET /api/sd/option-file/<optionId>` with Bearer (server fetches the file for the user); same response headers. |

## 3. End-to-end encryption (affects mobile)

Doc: `docs/E2E_ENCRYPTION.md`. Server mode `CONNECTUM_E2E` = `off` (default) / `optional` / `required`; check `e2e.status` -> `{mode, devices, maxDevices}` after connecting.

| Topic | Fact |
|---|---|
| Covered | text, voice, photos, video, files, GIFs, stickers in **direct chats and groups**. |
| Not covered | forms, `#` commands, topic messages, **the AI chat / assistant relay**, global room (`e2e_unsupported`), host chats. AI conversations and relay traffic are plaintext to the server (conversations stored sealed at rest by the server key). |
| Mobile must implement | per-device key pairs ECDH P-256 + ECDSA P-256 (private keys stay on device); register with `e2e.register {id,ecdh,sign,label,proof}` (proof = ECDSA signature over `connectum-e2e-register\|user\|id\|ecdh\|sign`); max 10 devices/user; envelope `e2e1:{json}` `{v,mid,from,dev,conv,ts,ek,iv,ct,sig,keys:{deviceId:{iv,w}}}` built with AES-256-GCM, HKDF-SHA-256 wrapping per recipient device, 64-byte padding, AAD binding msg id/conversation/sender/device; verify signatures; pin first-seen device keys (TOFU); safety number. Exact byte formats are in `e2eCrypto.js` (reference implementation; not fully specified in the doc). |
| Directory calls | `e2e.devices {users:[...]}`, `e2e.group_devices {group}`, `e2e.remove {id}`; push `e2e_devices_changed {user}`; cache 5 min. |
| Send errors | `e2e_disabled, e2e_required, bad_envelope, e2e_peer_not_ready, too_long, e2e_unsupported`. Edits cannot downgrade to plain. |
| Attachments | encrypt bytes (AES-256-GCM, random key+iv) on device; `POST /upload` with part type `application/x-connectum-e2e` (stored `.e2e`, min 28 bytes, no magic-byte check); put `{key,iv}` in the `[ATTACHMENT:...]` tag's `e2e` field inside the encrypted message; receiver downloads blob, decrypts locally. |
| Notifications | cards/feed items carry the envelope (`e2e:true`); the app decrypts to build previews. |
| Limits | groups up to 200 members x 10 devices; no key recovery; new device cannot read older messages ("This message can't be read on this device"). |
| Caveat | Web uses IndexedDB + Web Crypto; the doc says it is not independently audited. UNCLEAR: whether native iOS/Android secure storage can reproduce the exact web envelope (needs byte-level check of `e2eCrypto.js`; interop is untested in code). |

## 4. Notifications

| Mechanism | Detail |
|---|---|
| **Push (FCM / APNs / Web Push / service worker)** | **None exists.** Repo search of `src/`, `axi-chat-backend/src/`, `docs/` found no FCM/APNs/web-push/VAPID/service worker/device-token registration; `public/` has no service worker or manifest. There is no endpoint to register a device token. Offline users only accumulate items and must reload on reconnect. Mobile push would need new backend work. |
| In-app live events (WebSocket) | `sd_event` `feed_item {notification,counts}`, `feed_removed {ids,counts}`, `feed_changed {ids,read,counts}`, `session_expired {reason}`; plus `request_created`, `request_resolved`, `card`, and admin/config events (`permissions_changed`, `roles_changed`, `user_updated`, ...). Only delivered while the socket is connected. Chat events (chat, private, group_message...) are in `docs/CHAT_PROTOCOL.md`. |
| Feed (My Workspace panel) | REST: `GET /api/sd/feed?priority=&category=&unreadOnly=&limit=(50,max200)&before=<ts>`, `GET /api/sd/feed/summary`, `POST /api/sd/feed/read {ids\|all,read?}`, `/resolve {id}`, `/dismiss {id}`, `/clear`. WS equivalents `feed.*`. Reload `feed.list` on every reconnect. |
| Cards | `cards.list {section?,limit?}`, `cards.dismiss {id\|"all"}`. |
| Sound | `notifySound.js` (web only). |
| Email | SMTP (Office 365 etc.) via `sd_notify`/`sd_mail`/`sd_mailq`: user invitations and one-time codes (sign-in, admin unlock, first set-up). Env: `CONNECTUM_OTP_MODE` = `smtp` / `log` / `fixed` / `webhook`, `SMTP_*`, `APP_URL`. Non-secret mail is queued in Redis and retried (0,5 s,30 s,2 min,10 min,1 h); OTP mails are retried in memory about 1 minute. No email for chat messages or feed items was found. Admin: `admin.mail.queue`, `users.resend_invite {username}`. `CONNECTUM_DEV_OTP=1` returns codes in API responses (dev only). The mobile app signs in with the emailed code; there is no password except admins (per `docs/EMAIL_SETUP.md`). |
| SMS | Not implemented; `webhook` mode posts JSON to `CONNECTUM_NOTIFY_WEBHOOK` for an external SMS/email gateway. |

## UNCLEAR items

- UNCLEAR: does `#<alias>` typed in a chat call `assistant.relay` server-side, or is it only a command-menu entry? (Not traced.)
- UNCLEAR: should mobile generate image/video thumbnails locally? The backend has no thumbnail endpoint and the web app shows originals.
- UNCLEAR: can native Flutter crypto reproduce the web E2E envelope exactly? `E2E_ENCRYPTION.md` describes the scheme; byte-level encodings (key export format, HKDF info, AAD layout, base64 variant) are only in `src/features/connectumChat/e2e/e2eCrypto.js`.
- UNCLEAR: `docs/CHAT_PROTOCOL.md` (images/voice, 8 MB) disagrees with `chat_web.erl` (documents 20 MB, video 25 MB, E2E blob ~25.5 MB); the web error text for oversize says "max 25 MB" while per-type limits differ. Code used here.
- UNCLEAR: `GET /uploads/<name>` is unauthenticated (security relies on random names); is this intended for mobile, or will downloads gain auth? Nothing in code says.
- UNCLEAR: no push notification infrastructure exists; is it in scope for the mobile build (needs new backend endpoints for device tokens and a sender)?
- UNCLEAR: whether `AI_STYLE_GUIDE`, the `chart` block format and tool definitions must be identical on mobile, or whether the backend/AI service (`Rag_Agent_Connectum`, referenced in `AI_AGENT_ROLES.md`, not in this repo) will take over the tool loop; today all tool logic is in `workspaceAgent.js`.

## Source files used

- /Users/narasimhanatheshrao/Development/Axi-apps/connectum/src/features/connectumChat/services/workspaceAgent.js, aiFiles.js, aiHistory.js, aiModels.js, assistantErrors.js, enterpriseData.js
- /Users/narasimhanatheshrao/Development/Axi-apps/connectum/src/features/connectumChat/components/modals/ChatSummaryModal.jsx, AdminAiPanel.jsx; components/AssistantView.jsx; utils/threadAsk.js
- /Users/narasimhanatheshrao/Development/Axi-apps/connectum/src/features/connectumChat/ConnectumChatScreen.jsx (attachment tag parsing/sending)
- /Users/narasimhanatheshrao/Development/Axi-apps/connectum/src/features/aiFormat/aiStyleGuide.js, chart.js; features/providerSwitcher, promptTemplates, systemPromptEditor, exportChat (legacy)
- /Users/narasimhanatheshrao/Development/Axi-apps/connectum/src/services/connectumSocket.js, connectumApi.js, connectumFiles.js; features/connectumChat/e2e/e2eMedia.js
- /Users/narasimhanatheshrao/Development/Axi-apps/connectum/axi-chat-backend/src/chat_web.erl, chat.hrl, chat_upload_limiter.erl, sd_http.erl, sd_files.erl, sd_assistant.erl, sd_aiconv.erl, sd_cmds.erl, sd_notify.erl
- /Users/narasimhanatheshrao/Development/Axi-apps/connectum/docs/AI_AGENT_ROLES.md, E2E_ENCRYPTION.md, EMAIL_SETUP.md, CONNECTUM_API.md, CHAT_PROTOCOL.md, SD_ACTIONS_REFERENCE.md
