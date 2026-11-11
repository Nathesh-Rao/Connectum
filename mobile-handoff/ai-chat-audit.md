# AI in chat: audit of the BE doc against our fake

Source: `reference/ai-chat/AI_in_Chat_for_Mobile.pdf` (16 pages, read in full, as of 10 Nov 2026). The doc's section 10 "Recommendations for mobile" is listed in its table of contents but is not in the PDF (it ends at 9.3).

## (a) What the doc says

The server has **no summarise action**. The client reads the chat itself, builds the prompt and sends it through a generic relay. The answer is one non-streamed response, shown only to the asker.

| Feature | Action / route | Request | Response / events | Errors |
|---|---|---|---|---|
| Is AI available | `/sd ai.agents {"reqId"}` | none | `data.agents[]` `{id,name,alias,provider,model}`; only enabled agents this person may use. Unknown fields ignored | none specific |
| Agents changed | event `sd_event` `ai_agents_changed` `{action: saved\|deleted}` | | re-call `ai.agents` on it and after every reconnect | |
| Summarise | `/sd assistant.relay {agent, payload, model?, timeoutMs?}` (slow lane) | `agent` = agent id (optional when exactly one); `payload` = provider's own body; `timeoutMs` 5000-90000 (default 20000) | `data {status, body, modelUsed, fellBack}`; `ok:true` only means the provider was reached: check `data.status` | server codes and provider statuses below |
| Read the chat | client side (`/history ...`) | | | web: 8 s wait |
| Cancel | not implemented | | closing does not abort; ignore a late answer | |
| Share in chat | not implemented | | Copy is the only way out | |
| Stream | no (`stream` is removed by the server) | | one response | |
| Rewrite / translate / suggest / ask about this chat / AI on one message | not implemented in the chat window | | | |
| Care thread summary | `/sd care.summary {"person"}` (not AI-written) | | `{person,team,stats,latest,timeline}` | `not_found` |
| AI notifications / feed / unread / history of summaries | none | | | |

Relay errors (`error.code` of the sd envelope) and the web's text:

| Code | Web text |
|---|---|
| `no_agent` | No AI agent is set up for you yet. Ask your administrator. |
| `no_access` | You do not have access to this AI agent. Ask your administrator. |
| `not_found` | That AI agent no longer exists. |
| `invalid` | payload must be an object. / Choose which AI agent to ask. / No provider address is set for this agent. |
| `key_unreadable` | The stored key could not be read. Add it again. (this agent's key cannot be read. Tell your administrator.) |
| `rate_limited` | Too many questions in a minute. Try again shortly. (agent-wide: The AI is busy right now. Try again in a moment.) |
| `too_large` | That question came with too much data. Ask something narrower. |
| `upstream_timeout` | The AI provider took too long to answer. Try again. |
| `upstream_unavailable` | Can't reach the AI provider right now. Check the connection and try again. |
| `forbidden_address` | The provider address is not allowed. Check the address in the key settings. |
| `timeout`, `disconnected`, `not_connected`, `test_timeout` | Can't reach Connectum right now. Check the connection and try again. |
| anything else | `error.message` or Something went wrong. Please try again. |

Provider status inside `data.status`:

| Status / body | Class | Web text |
|---|---|---|
| 402, or body with insufficient quota / billing / credit | no_credit | Your AI provider account has no credit left. Add credit on the provider's billing page, then ask again. Your key is fine. |
| 401, or 400/403 with invalid/expired/revoked key words | bad_key | The AI provider no longer accepts this key (it may have been rotated, revoked or expired). Add the new key to continue. |
| other 403 | bad_key | The AI provider refused this key (it may not be allowed to use this model, or it was revoked). Add a key that has access. |
| 429 | rate | The provider is limiting how fast you can ask. Wait a minute and try again. |
| 404, or 400 mentioning model | model | That model is not available to this key. Open the key settings and choose a model your account can use (or clear it to use the default). |
| 413 | too_large | That question came with too much data. Ask something narrower. |
| 502/503/504/529/other 5xx | busy | The AI provider is busy or down right now. Try again in a moment. |
| other 400 | bad | The AI provider could not use that request: <first 160 chars of provider message> |
| anything else | other | The AI provider returned an error (HTTP <n>). |

Other texts: empty answer: The assistant could not answer that. Window fallback: The summary could not be made. The web texts for key problems are written for admins; mobile should say "Tell your administrator".

## (b) Setup state

There is no status flag. Derived from `ai.agents`:

| State | How it shows | Web text |
|---|---|---|
| Set up and allowed | `agents.length >= 1`; with 2+ agents an "AI" chip row picks one, the first is the default | window works |
| Not set up / disabled / no permission | `agents` is `[]` (the server does not say which of the three) | No AI is set up for you yet. Ask your administrator. |
| Agent removed or revoked between list and call | `assistant.relay` fails `not_found` / `no_access` | texts above; the web drops its cached list |
| Key invalid | provider 401/403 or `key_unreadable` | texts above |
| No credit | provider 402 | texts above |
| Rate limited | `rate_limited` (30/min person, 600/min agent) or provider 429 | texts above |
| Per-user or org quota; org-wide AI toggle | not implemented | |

Only administrators can set it up (Admin console > AI agents). Non-admins cannot request it.

## (c) Header icon visibility

| Conversation | Icon |
|---|---|
| Direct, group, host, general broadcast (`global`) | yes, Summarise |
| Care or patient thread (`room-care-<person>`) | different button (care summary, not AI): no AI icon |
| My Workspace | no header |
| Ticket / record conversation | UNSURE, same button unless id starts with `room-care-` |
| Reply thread under one message | not implemented |
| End-to-end encrypted chat | shown, no difference |

No role, permission or feature-flag check. The button is shown even when no AI is set up; the window then says so. Mobile may hide it.

## (d) Summarise options

From: Everything (default), Today, Last 7 days, Last 30 days, A date (date picker, max today). Nothing else: no last-N, unread, language, length, style or custom prompt. The date is applied as `ts >= YYYY-MM-DDT00:00:00` device-local. The Summarise button is disabled while loading, with no agent, or with A date and no date.

Transcript (client built): drop deleted messages and anything without a numeric `ts`, sort by `ts`, newest 300 messages, at most 60 000 characters (dropping the oldest, never below 20 lines), each text cut to 600 characters. Header `CHAT: group Sales - 3 messages, 2026-11-09 09:12 to 2026-11-09 09:20 (the whole conversation).`, then `[2026-11-09 09:12] ravi: text`, mine as `meera (you)`, replies as `(reply to ravi: "...")`, forms as `[form submission] <caption> #<id> (<status>) - ...` (each value cut to 200). If truncated the header says `(only the newest 120 of 540 are shown: older messages were not read)` and the prompt tells the model to say so. Empty: `The group Sales has no messages since 2026-11-01.`

Limits: request 200 000 bytes, provider answer 2 000 000 bytes, 20 s per provider call by default (90 s max), 30 calls/60 s per person, 600/60 s per agent, `max_tokens` 1800 (Anthropic), temperature 0. Up to 2 fallback models server side.

Payloads: OpenAI-compatible `{model, temperature, messages, tools?}`; Anthropic `{model, max_tokens, temperature, system, messages, tools?}`; Gemini `{systemInstruction, contents, generationConfig, tools?}`. Text: Anthropic `content[].text` where `type=="text"`; Gemini `candidates[0].content.parts[].text`; others `choices[0].message.content`. The result is Markdown-style plain text (headings, bullets, bold, tables); treat as untrusted, no HTML, no links followed.

## (e) Share in chat

Not implemented. No message type, no marker, no AI sender. If mobile adds it, the only mechanism is an ordinary text message from the user (not marked as AI): a product decision.

## (f) End-to-end encryption

The web has no E2E check: it decrypts on the device and sends the plain transcript to the provider through the server (the server sees it in memory, logs only provider, status and time). No consent text, no block, no preview, no notice to the others. `docs/PRIVATE_AI_SUMMARY.md` (consent preview, on-device model) is a proposal, "Nothing here is built".

## (g) Other AI actions in the chat

None besides Summarise (and the care-thread summary, which is not AI). `#<alias> chat summary [since date]` in the composer opens the web window (web shortcut). `#<alias> <question>` opens the AI tab (out of scope).

## (h) Feed, notifications, persistence

No feed item, notification, push or unread for AI. No history of summaries; nothing stored, no id, cannot be fetched again; doing it again is a new, paid provider call. Only live event: `ai_agents_changed`.

## (i) Test org and samples

Admin on the web: Admin console > AI agents > name Claude, command claude, provider Anthropic, model blank (claude-haiku-5-5), key, access everyone, Test. Not set up: `ai.agents` answers `{"agents":[]}`; a relay call then fails `no_agent`. One-shot Anthropic request: `/sd assistant.relay {"agent":"claude","payload":{"model":"claude-haiku-5-5","max_tokens":1800,"system":...,"messages":[{"role":"user","content":<transcript>}]}}`; answer `data {status:200, body:{content:[{type:"text",text}]}, modelUsed, fellBack:false}`. These samples were built from the code, not captured live.

## Differences (our fake against the doc)

| # | What we had | The doc | What we did |
|---|---|---|---|
| 1 | `AiRepository.summarize(chatId, range)` as if the server summarised | no summarise action: the client builds the transcript from the chat and calls `assistant.relay` | transcript builder from SQLite + relay call in `AiRepositoryImpl` |
| 2 | Setup states ready / notSetUp / disabled / quotaExceeded / noPermission from one call | only `agents.length` is known; the other states appear as relay errors | `AiSetupState` is ready / notSetUp; the rest are `AiErrorKind`s with the doc's texts |
| 3 | `isAdmin` flag (// ASSUMPTION) and admin path text | no admin flag; a non-admin cannot set up | removed; texts say "Tell your administrator" |
| 4 | Ranges Everything / Today / 7 days / 30 days | plus A date (max today) | added A date with a date picker |
| 5 | No agent choice | 2+ agents: an "AI" chip row, first default | added |
| 6 | Streamed chunks and a server cancel | no streaming, no cancel | one final event; Cancel ignores the late answer. Fake keeps its streaming switch for the debug page only |
| 7 | Error kinds offline, timeout, failed, noMessages, tooMany, rateLimited, noPermission | about 20 codes and 9 provider classes | mapped to 15 kinds, each with the doc's text |
| 8 | Share in chat as a marked text (`AI summary · range`) | not implemented; no marker exists | removed the share button, the marker format and `sendAiSummary`; Copy stays. Open question |
| 9 | E2E chats blocked with "the server cannot read them" | web sends the decrypted text to the provider, no consent | still blocked (the doc gives no consent text, and says it is a product decision); the dialog text no longer claims the server cannot read them. Open question |
| 10 | Icon in dm / group / host / global | same, minus care threads (`group:care-*`) | care threads hidden |
| 11 | Message count came "from the API" | the API returns none | count of the messages read into the transcript |
| 12 | Nothing on `ai_agents_changed` | re-call `ai.agents` on it and after every reconnect | setup cache cleared on both |
| 13 | Feed / notifications for AI | none exist | nothing added |
| 14 | Rewrite / translate / ask rows | not implemented | nothing added |

## Open questions for the BE

See the report: share (product decision), E2E consent, care summary, admin flag, `ai_agents_changed` wire details, prompt text, and the missing section 10.
