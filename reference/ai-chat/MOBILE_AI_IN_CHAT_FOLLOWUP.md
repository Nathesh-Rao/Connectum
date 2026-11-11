# AI summary in chat: answers for the mobile team (follow-up to AI_in_Chat_for_Mobile.pdf)

Written 11 Nov 2026 from the code in this repository. Every fact names the file it comes from, so you can read it yourself and so this page can be checked when the code changes.
Things that are **decisions, not facts** are marked **DECISION** and listed again at the end (section 8): nothing marked that way is built or agreed yet.

Where the web does it: `chat-app/features/connectumChat/` (`components/modals/ChatSummaryModal.jsx`, `services/workspaceAgent.js`, `services/chatReader.js`, `services/assistantErrors.js`); server: `connectum-backend/src/integrations/sd_assistant.erl`.

## 1. Section 10: Recommendations for mobile

(The PDF's section 10 was never in the file. This is a new version, written for this answer.)

1. **Get the agents first.** Call `ai.agents` when the person opens "Summarise" and again when an `ai_agents_changed` event arrives (section 4). If the list is empty, show: *"No AI agent is set up for you yet. Ask your administrator."* (the web's own words, `workspaceAgent.js`, code `no_agent`). `me` already returns `permissions.isAdmin` (`sd_cmds.erl`): an administrator can be told where to set one up (Admin console > AI agents, on the web). If the list has one agent use it; with several, show a picker (the web preselects the first).
2. **Build the transcript on the phone** in the web's format (section 3.3) and send **one** request through `assistant.relay` with the transcript inside the system prompt as `CHAT IN FOCUS`. This is exactly what the web sends for a *follow-up* question, so the answer is the same kind as the web's. The web's first turn lets the model call a `read_chat` tool (up to 4 rounds); you do not need the tool loop, because you already hold the text.
3. **Use the web's question and rules** (sections 3.1 and 3.2) so a summary reads the same on both. Temperature 0, as the web sets.
4. **`assistant.relay` forwards a provider-native payload** and returns the provider's own answer as `{status, body}` (section 3.4). Check `status` 200 to 299 first; anything else goes through the error classes in section 3.5. The server stops a provider call at 20 s; wait up to 40 s on the phone (the web's `RELAY_WAIT_MS`).
5. **Errors:** reuse the web's classification (`assistantErrors.js` is pure code with no network: port it, or copy its table in section 3.5) so the same failure gives the same words and the same next step on both clients.
6. **The answer is Markdown.** The style guide the web appends tells the model to use bullet lists, tables, and, for figures, a fenced block whose language is `chart` holding JSON. A summary rarely needs a chart, but if one arrives, render it or hide the fence: do not show raw JSON. The web renders with `aiFormat/AiMessage`.
7. **End-to-end encrypted chats:** keep AI **blocked** in them until the owner decides the rule (section 2). Everything below is only for chats that are not end-to-end encrypted.
8. **Nothing is posted by the AI.** On the web the summary stays on the person's screen. Mobile should do the same in the first version; sharing is section 7.
9. **Size:** the server refuses a request over 200 KB (`too_large`). The web's transcript is capped at 300 messages and 60,000 characters, which keeps a request far below that.

## 2. PRIVATE_AI_SUMMARY.md, the consent preview and the end-to-end rule

**What exists.** `docs/PRIVATE_AI_SUMMARY.md` (8 Oct 2026) is a **design proposal. Nothing in it is built.** It describes three tiers: the model on the person's device (nothing leaves it), the enterprise's own private cloud (the messages go encrypted for one request, with a preview and an audit line), and **a public AI vendor, which it says is "not offered" for chat content.**

**What the web does today.** The summary reads the open chat from the same `history` list the chat screen shows (the web's own socket service opens end-to-end envelopes before it hands the list on, so it is plain text), builds the transcript, and sends it through `assistant.relay` to the organisation's AI provider. There is **no consent screen and no preview**, and nothing tells the other people in the chat. That is tier 3 in the proposal's words, so **today's web behaviour is the one the proposal says not to offer.** You read this correctly.

**The consent text.** There is **no consent text yet**: no screen, no wording and no setting exist on the web or the server. Nothing can be quoted. A **draft** for the owner to approve (not agreed, do not ship it as final):

> **Summarise this chat with AI?**
> The messages of this chat will be sent to your organisation's AI provider (*<provider name>*) to write the summary. The people in this chat are not told. The summary stays on your phone and is not saved on Connectum.
> [Cancel] [Summarise]

**The intended rule for end-to-end encrypted chats.** The proposal's rule: the server must not be able to read these chats, so a summary must be made **on the device**, or, in the private-cloud tier, with the messages encrypted to the AI service for one request, a preview, an audit line and a notice in the chat; sending the plain text to a public vendor is **not offered**. **No tier has been built and no decision has been taken** (the proposal's section 6 lists the four open decisions). So, for mobile:
- **End-to-end chats: keep AI blocked.** This is the safe reading of the proposal and matches what you do now.
- **Other chats:** the web summarises without consent today. **DECISION (owner):** keep that, or add the consent notice above on both clients.

## 3. The canonical prompt, question and transcript

### 3.1 The summarise question (`ChatSummaryModal.jsx`, `run()`)

```
Summarise my {kind} "{label}"{from}. Give the main points, the decisions made, anything still open or unanswered, and the action items with who owns each. Keep it short and in the order things happened where that matters.
```
- `{kind}` = `group chat` for a group (`chat.isGroup`), otherwise `private chat`.
- `{label}` = the chat's title as the web shows it (`chatTitle(chat)`).
- `{from}` = `, only the messages from YYYY-MM-DD on` when a start date is chosen, otherwise `, from the beginning`.
- The web's range choices: Everything, Today, Last 7 days, Last 30 days, or a chosen date (`since`, `YYYY-MM-DD`, local midnight).

### 3.2 The system prompt (`workspaceAgent.js`, `systemPrompt()`)

The web uses **one** system prompt for the whole workspace assistant (a general assistant that is also connected to organisation data), and the summary is simply a question put to it. It is assembled; the parts that matter for chats are below, **verbatim**. The wording, including a join in the middle of the third paragraph, is the code's: copy it, do not tidy it, so both clients behave alike.

1. Opening line: `You are the friendly My Workspace assistant for {name}. Today is {new Date().toDateString()}.`
2. The chat rules (the third paragraph of the prompt):
```
You can read the user's own chats (groups and private chats) with read_chat. When they ask to summarise, analyse or answer something about a chat, call read_chat for that chat and answer ONLY from the transcript it returns: name who said what and when, quote exactly, Forms (T-Struct submissions) posted in a chat appear as [form submission] lines with the form's name, who submitted it, when, and the values filled in: when asked what was submitted, when and why, list them in date order with the exact values, and give a reason only if a field or a message states it (never infer one). and if something is not in the transcript say it is not there. Never fill a gap, never guess a name, date, number or decision, and say plainly if the transcript was cut (it tells you how many messages were read). Their reply to you may be a follow-up about the same chat: answer it from the CHAT IN FOCUS below without reading again, unless they ask for another chat or for newer messages.
```
3. Closing parts, in this order: `Be warm, concise and clear.`, then the **house style guide** (below), then, when a chat was read, `CHAT IN FOCUS (read earlier in this conversation: "{label}")` followed by the transcript, then `WORKSPACE DATA` followed by the person's notifications and tasks.

The other paragraphs of the prompt (organisation data tools, patient records, Data Bins, search) are not about chats; a mobile summary can leave them out. **For a chat-only call on mobile, assemble:** (1), (2), `Be warm, concise and clear.`, the style guide, then the `CHAT IN FOCUS` block. That is the web's own prompt minus the parts that need tools mobile does not use. **The code is canonical:** if `systemPrompt()` changes, this page is out of date.

**The house style guide** (`aiFormat/aiStyleGuide.js`, `AI_STYLE_GUIDE`, appended at the end of every assistant prompt), verbatim:

```
Answer style (follow it in every answer):
- Lead with the answer in one or two sentences. Then, only if useful, the detail.
- Use only facts, figures and names given to you. Never estimate or invent a figure. If you do not know, say so and say what would settle it.
- Plain, specific sentences. No filler ("Great question", "As an AI"), no repeating the question, no apologies.
- Numbers: thousands separators (12,400), at most two decimals, units and the period stated ("Revenue was 89,412 in Q3"). Name the column or source a figure comes from.
- Structure: short paragraphs; a bulleted list for three or more parallel points; a table (Markdown) for comparing items over several measures; a numbered list only for steps.
- Charts: when figures are worth seeing (a comparison, a share, a trend over time), draw a real chart and never one made of text characters: a fenced block whose language is chart, holding JSON, for example {"type":"bar","title":"Employees by city","unit":"people","data":[{"label":"Bangalore","value":22},{"label":"Chennai","value":13}]}. type is bar (a ranked comparison, the default), column (a few categories or months), line (a trend; for several lines give "labels" and "series":[{"name":"2025","data":[1,2]}]) or donut (parts of a whole, up to 6 parts). Use only figures you were given, then add one or two sentences on what it shows.
- Code: always in a fenced block with its language (```python), complete and runnable, with a one-line comment saying what it does; mention how to run it after the block.
- Say what is a fact from the data and what is your interpretation ("Possible explanation: ..."). Do not state causes as facts.
- Write in the language the person used. Keep it as short as the question allows.
```

### 3.3 The transcript format (`chatReader.js`, `formatTranscript()`)

What it takes: the chat's history list (any order; sorted by time here), the viewer's username (`me`), an optional `since` date, and the caps `maxMessages = 300`, `maxChars = 60000`.

Rules, in the order the code applies them:
1. Messages that are **deleted** or have no numeric `ts` are dropped. Sorted oldest first. With `since`, only messages at or after local midnight of that date.
2. A normal message becomes one line: `[YYYY-MM-DD HH:mm] {from}{ (you)}{ (reply to X: "first 60 characters of the quoted message")}: {text}`. The time is the **viewer's local time**. `(you)` is added when the sender is the viewer. Line breaks and runs of spaces in a message become one space; the text is cut at 600 characters with `…`. A message with no text and no form is skipped. A sender with no name shows as `someone`.
3. A **form** posted in the chat becomes `[form submission] {form caption}{ #{number}}{ ({status})} - {Caption: value; Caption: value}`: each field uses its label if it has one, else its value; fields with no value are left out; a list is joined with `, `; an object is written as JSON; each value is cut at 200 characters; no values at all gives `no values`.
4. If more than 300 lines or 60,000 characters, the **oldest lines are dropped** (never fewer than 20 lines are kept) and the head says so.
5. The head line comes first: `CHAT: {kind} {label} - {n} message(s), {first time} to {last time}{note}. Times are the viewer's local time.` Here `{kind}` is `private chat with`, `group`, `host chat` or `chat`, and `{note}` is ` (the whole conversation)` or, when lines were dropped, ` (only the newest {n} of {available} are shown: older messages were not read)`. An empty chat gives `The {kind} {label} has no messages{ since DATE}.`

A real example, made by this function:

```
CHAT: group Reports team - 4 messages, 2026-11-09 10:02 to 2026-11-09 11:40 (the whole conversation). Times are the viewer's local time.
[2026-11-09 10:02] asha (you): Can we ship the report on Friday?
[2026-11-09 10:05] ravi (reply to asha: "Can we ship the report on Friday?"): Friday works if finance sends the numbers today.
[2026-11-09 10:06] asha (you): I'll chase finance. Will confirm by 3pm.
[2026-11-09 11:40] ravi: [form submission] Leave Request #12 (Approved) - From: 2026-11-20; Leave type: Casual Leave
```
(Four messages were given plus one deleted one; the deleted one is not shown.) The function is pure and tested (`tests/frontend/chatReader.test.mjs`): port it and compare your output with the web's on the same input.

### 3.4 The request the web sends, per provider (`workspaceAgent.js`, `converse()`)

`assistant.relay {agent, payload, model?}` with the provider's own request body as `payload`; the server adds the key, drops `stream`, sets the agent's `model` and calls the provider.

| Provider (agent `provider`) | `payload` | Where the answer text is in `body` |
|---|---|---|
| `anthropic` | `{model, max_tokens: 1800, temperature: 0, system, messages: [...earlier turns, {role:"user", content: question}]}` | `content[]`: join the `text` of the blocks |
| `gemini` | `{systemInstruction:{parts:[{text: system}]}, contents:[...{role:"user"\|"model", parts:[{text}]}], generationConfig:{temperature:0}}` | `candidates[0].content.parts[]`: join the `text` |
| `openai`, `openrouter`, `grok`, `groq`, `deepseek`, `sambanova`, `custom` | `{model, temperature: 0, messages: [{role:"system", content: system}, ...earlier turns, {role:"user", content: question}]}` | `choices[0].message.content` |

An empty text is treated as "the assistant could not answer that". Earlier turns of a conversation are the last 10, each cut at 2,500 characters (a summary needs none).

### 3.5 Error classes (`assistantErrors.js`)

From the server (`error.code` of the `sd` answer): `no_key`, `key_unreadable` → key problem; `rate_limited` → wait; `too_large`; `upstream_timeout` → timeout; `upstream_unavailable` → can't reach the provider; `forbidden_address`; `no_agent`, `no_access`, `not_found` (the agent was removed), `invalid`; `timeout`, `disconnected`, `not_connected` → can't reach Connectum.

From the provider (`status` of the relayed answer, not 2xx): 402 or a credit message → **no_credit** (key fine, top up); 401 / 403 or a key message → **bad_key**; 429 or a rate message → **rate**; 404 or "model not found" → **model**; 413 → **too_large**; 502, 503, 504, 529, any 5xx → **busy**; other 400 → **bad** (message shown); else **other**. The exact words the web shows for each are in the file: use them so both clients match.

## 4. `ai.agents` and the `ai_agents_changed` event

**Today** `ai.agents {}` returns `{agents: [...]}` only: the agents this person may use, nothing else (`sd_assistant:for_user/1`).

**An agent** (as an employee sees it): `id`, `name`, `alias` (the command word, e.g. `claude` for `#claude`), `provider`, `model`, `modelChoice` (boolean: may the person pick another model of the provider's), plus anything an installed plugin adds (the AI agent plugin adds its roles). An agent is listed only if it is **enabled and the person is permitted** (Admin console > Permissions, resource `ai:<id>`). Never an address or a key; an administrator sees more (`baseUrl`, `last4`, `enabled`, `updated`, `access`) through a different call.

**The reason for an empty list: not available today.** The answer carries no reason and no admin flag. The ways to tell are:
- `isAdmin`: **already available**, `me` → `permissions.isAdmin`.
- Not set up / disabled / no permission: **not available**; the person sees the same empty list in all three cases (that is deliberate: an employee must not learn what exists).
**DECISION (owner):** add `reason` (`none_set_up` | `all_disabled` | `no_permission`) and `isAdmin` to the `ai.agents` answer. It is a small backend change; say yes and it will be built with a test. Until then, show the single message in section 1.

**The event.** `ai_agents_changed` arrives as `{"type":"sd_event","event":"ai_agents_changed","data":{"action":"saved"|"deleted","by":"<username of the administrator>"|null}}` (`sd_cmds_admin.erl`, `announce_ai_agents`). It goes to **everyone online in the organisation**, not just people who gain or lose access; the person's own list may or may not have changed. Re-fetch `ai.agents` when it arrives (the web turns it into an in-page event, `connectum:ai-agents-changed`, and the AI screens reload their list; `metaCalls.js` maps it to the `agents` meta call). It is sent after an agent is saved or deleted; nothing is sent when a permission rule changes, so also re-fetch when the summary is opened.

## 5. `rate_limited`

Both, and they have different messages (`sd_assistant.erl`, `relay_with/6`, same in `embed_with/5`):
- **Per person: 30 calls per minute** (counter `ai:u:<username>`, window 60 s) → `rate_limited`, "Too many questions in a minute. Try again shortly."
- **Per agent: 600 calls per minute across everybody** (counter `ai:a:<agent id>`, window 60 s) → `rate_limited`, "The AI is busy right now. Try again in a moment."
The two cannot be told apart by `code`, only by the message text. The web treats both as the class `rate` ("wait a moment"). The provider has limits of its own (HTTP 429 from it is the separate class `rate`, section 3.5). Other limits: request 200 KB in, answer 2 MB out, 20 s per provider call (a caller may ask for up to 90 s with `timeoutMs`), 12 agents per organisation.

## 6. Tickets, records and care threads

**On the web today.**
- **Ticket and record conversations:** a record's own conversation is added to the person's chat list as an ordinary **group chat** (`ConnectumChatScreen.jsx`, `openRecordThread`), so it gets the same header button, "Summarise this chat with AI". So **yes, the web summarises them,** by the same code as any group.
- **Care threads** (`room-care-<username>`) are the exception: the header shows **"Summary of this thread"** instead, and the plain "Summarise this chat" button is hidden (`ConversationHeader.jsx`).
  - `care.summary {person}` is **not AI**: the server builds it from stored data ("never written by a model": the person, the team, the latest of each kind of form, and a timeline of up to 500 messages and forms, only what the asker may see; `sd_carethread.erl`).
  - The summary card also lets the person ask the AI questions about the thread (`askAboutThread`, its own prompt, answers only from that thread's forms and messages). That is a separate prompt from section 3.2.

**For mobile. DECISION (owner)**, recommended:
- Tickets and records: **yes**, same button and same flow as chats, identical to the web.
- Care threads: show `care.summary` first (no AI, so no consent question). The AI question box on the card can come later: it needs the care prompt, which is a separate page of work. If you want it, say so.
- End-to-end chats: blocked (section 2). A care thread and a record conversation are group chats on the server; whether they are encrypted depends on the organisation's `CONNECTUM_E2E` mode.

## 7. Sharing a summary

- **Server:** there is **no marker field and no message type for an AI summary.** A message is plain text (or the other existing kinds); the server cannot tell an AI summary from any other text.
- **Web:** never posts one: the summary stays on the person's screen ("Nothing is sent to the chat or to anyone").
- **Mobile's plan** (a normal text message from the user, first line "✨ AI summary") **works with no server change.** It is acceptable. Two things to decide: **DECISION (owner)** whether to allow it in the first version (the recommendation is to ship the on-screen summary first and add sharing afterwards), and, if allowed, a **preview before posting** (the person sees exactly what goes into the chat). Posting puts the model's wording of other people's messages in front of the whole chat. In an end-to-end chat the post is an ordinary message, encrypted like any other, but AI is blocked there anyway (section 2).
- If you later want a real marker (so every client can show it differently), that is a backend change: tell us and we will add a field.

## 8. Decisions needed from the owner

1. Consent for AI summaries in chats that are not end-to-end encrypted: keep none (today), or add the notice (section 2).
2. The rule for end-to-end encrypted chats (proposal tiers in `PRIVATE_AI_SUMMARY.md`); until then AI stays blocked on mobile.
3. Add `reason` and `isAdmin` to `ai.agents` (section 4).
4. Summary of ticket and record conversations on mobile (section 6) and the AI question box in care threads.
5. Sharing a summary into a chat in the first version (section 7).
