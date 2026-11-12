# In-chat AI: audit against the BE follow-up (11 Nov 2026)

Source: `reference/ai-chat/MOBILE_AI_IN_CHAT_FOLLOWUP.md`. It replaces `ai-chat-audit.md` where the two differ. `PRIVATE_AI_SUMMARY.md` is a proposal and is not implemented.

Copied from `origin/dev` of the BE repo (`~/Development/Axi-apps`, folder `connectum/`):

| Copied to | BE path |
|---|---|
| `reference/ai-chat/MOBILE_AI_IN_CHAT_FOLLOWUP.md` | `connectum/docs/MOBILE_AI_IN_CHAT_FOLLOWUP.md` |
| `reference/ai-chat/PRIVATE_AI_SUMMARY.md` | `connectum/docs/PRIVATE_AI_SUMMARY.md` |
| `reference/test-env/MOBILE_TEST_ENVIRONMENT.md` | `connectum/docs/MOBILE_TEST_ENVIRONMENT.md` |
| `reference/MOBILE_HANDOVER.md` | `connectum/docs/MOBILE_HANDOVER.md` |
| `reference/test-env/tools/seed.mjs` | `connectum/tools/mobile-test/seed.mjs` |
| `reference/test-env/tools/mock-ai-provider.mjs` | `connectum/tools/mobile-test/mock-ai-provider.mjs` |

## Audit

| # | Doc says | App did | Action |
|---|---|---|---|
| 1 | Question is word for word (3.1): `Summarise my {kind} "{label}"{from}. Give the main points, ...`; `{from}` is `, only the messages from YYYY-MM-DD on` or `, from the beginning` | Own short question `Summarise my {kind} "{title}".`, no "from the beginning" | Replaced. `lib/data/ai/ai_prompt.dart` (`AiPrompt.question`) |
| 2 | System prompt (3.2): opening line, chat rules paragraph, `Be warm, concise and clear.`, style guide, `CHAT IN FOCUS (...)` + transcript, all verbatim, join and all | Own invented system prompt; transcript in the user message | Replaced. `AiPrompt.system`; transcript now in the system part, the question is the only user turn (3.4). Strings generated from the doc and tested against it |
| 3 | Transcript format (3.3): head `CHAT: {kind} {label} - {n} message(s), {first} to {last}{note}. Times are the viewer's local time.`; kinds `private chat with` / `group` / `host chat` / `chat`; empty sentence; `(you)`; reply `(reply to X: "60 chars")`; `someone`; skip empty; form line with `#number`, `(status)`, `Caption: value; ...`, `no values`; cuts 600 / 200 / 60; oldest dropped, at least 20 kept | Different head (`team`, `everyone chat`, `from X on`), no `someone`, empty messages kept, form line was the bare caption | Rewritten. `lib/data/ai/ai_transcript.dart`; compared character for character with the doc's example in a test. Limits 300 / 60,000 unchanged |
| 4 | Agent fields: `id, name, alias, provider, model, modelChoice` | `alias`, `modelChoice` not read | `AiAgent` now holds them |
| 5 | `ai.agents` has no reason; `isAdmin` comes from `me`; empty list: "No AI agent is set up for you yet. Ask your administrator." (admin: set up in web app) | One text, no admin wording | `AiTexts.setupText(isAdmin:)`; controller takes `isAdmin`, read from `CommandRepository.isAdmin` (`perm.mine`; the BE confirms `me` returns the same value, so no `me` call) |
| 6 | `ai_agents_changed` re-fetch, and re-fetch on open | Already done | No change |
| 7 | `rate_limited`: 30/min per person ("Too many questions in a minute. Try again shortly.") vs 600/min per agent ("The AI is busy right now. Try again in a moment."), told apart by message text only | One kind | New `AiErrorKind.agentBusy`; `AiRelay.fromSocket` picks by the message (contains "busy"); texts are the server's. A missing message counts as per person. Provider 429 stays `providerRateLimited` |
| 8 | Tickets and records: same button and flow, they are group chats | Icon shows in any `group:` chat | Verified by test; no change |
| 9 | Care threads: `care.summary {person}` instead of AI | Icon hidden for `group:care-*` | Built, see "BE answers" below: icon shows when the person's username is in the thread name |
| 10 | Sharing: no server marker; mobile plan "first line ✨ AI summary" works; decision whether to allow in v1; preview before posting | Share existed, first line `✨ AI summary · last 7 days`, confirm dialog without the text | First line is exactly `✨ AI summary` (parts: `✨ AI summary (1/2)`). The confirm dialog shows a preview of exactly what will be posted. Sharing stays (open question 3) |
| 11 | E2E chats: rule not decided, AI stays blocked | A consent flow had been added (consent dialog, stored per chat, "decrypted on your phone" caption) | Removed and blocked again, see below |
| 12 | Answer is Markdown, a `chart` fence may arrive: do not show raw JSON | Not handled | Charts are drawn, see "BE answers" below |
| 13 | Wait up to 40 s, request over 200 KB is `too_large`, 20 s server limit | 40 s wait, 30 s `timeoutMs` | No change |
| 14 | `{name}` in the opening line, `Today is {toDateString()}` | n/a | Username (`userId`) and a JS-style date (`Wed Nov 11 2026`); open question 2 |

## E2E: what was removed and what blocks now

Removed completely:
- `lib/data/ai/ai_consent_store.dart` and `test/ai_chat/ai_consent_test.dart` (the whole file).
- Table `ai_consent`: version 12 now creates nothing, and new version 13 runs `DROP TABLE IF EXISTS ai_consent` (a phone that ran the unreleased 12 loses the table; fresh installs never create it). The version never goes down, so a phone already on 12 is not downgraded. `ai_consent` left `_scopedTables`; the `left_group` delete is gone.
- `AiConsentStore` in `InitialBinding` and `ConversationBinding`; `aiConsent` in `ConversationController`.
- Controller: `hasConsent`, `giveConsent`, `summarizeAsking`, `_isCheckingConsent`, `AiSummarizeResult.consentRequired`.
- Texts: `consentTitle`, `consentText`, `consentConfirm`, `privacyEncrypted`. Sheet: the consent dialog and `_summarize` helper.
- `/debug/ai`: the "E2E consent given" switch and the consent dialog button.
- Tests: the consent group in `ai_summary_test.dart`, the consent dialog test in `ai_widgets_test.dart`, the "encrypted chat shares" test.

Blocked behaviour:
- The icon still shows in encrypted chats. Tapping it opens a dialog: "Not available in encrypted chats. Summaries aren't available in end-to-end encrypted chats yet. Nothing from this chat was read or sent." No `ai.agents` call, no sheet.
- `AiSummaryController.summarize()` returns `AiSummarizeResult.blocked` first thing for an encrypted chat: nothing is read, built or sent (also if the chat became encrypted while the sheet was open).
- `/debug/ai` has an "E2E chat" switch and a button for the dialog, and an "I am an admin" switch.

## BE answers (11 Nov 2026) and what changed

| Question | Answer | What the app does now |
|---|---|---|
| 1. `isAdmin` | `perm.mine` and `me` give the same value (`sd_users:is_admin`) | `perm.mine` only (`CommandRepository.isAdmin`). No change |
| 6. Error words | The web's `assistantErrors.js`, with these server texts | Ported, pure, to `lib/data/ai/ai_error_text.dart` (`AiErrorText.classifyRelayError`, `classifyProviderError`), texts exact. `AiRelay.fromSocket` / `fromProvider` use it; `AiTexts` takes the words from it. Provider 429 without credit wording, 401, 403, 404, 413, 5xx and 400 follow the web table. Our own two rate-limit texts stay (the web's generic `rate_limited` text is only the fallback and is not reachable: a missing message already counts as per-person). New kinds `noKey`, `forbiddenAddress`, `serverTimeout`. A server code that is not listed shows the server's own message, else "Something went wrong. Please try again." |
| 5. Chart fence | (owner) draw a real chart | `AppChart` (`lib/core/widgets/app_chart/`): bar, column, line, donut, single and multi series, `CustomPainter`, no package. `AiAnswer` (`lib/data/ai/ai_answer.dart`) splits an answer into text and charts; a malformed or still-open fence shows nothing. Copy, share and the share preview carry the chart as `Title (unit)` and `- label: value` lines |
| 4. Care threads | `care.summary {person}`, response shape given in the task | Converter `lib/data/ai/care_summary_text.dart` (port of `careSummary.js` `toPlainText`); the icon shows in `group:care-<username>`; "Summarize this thread" |

Action offered per error (the person cannot fix key, credit, model or address on the phone):

| Kind (web code) | Words | Action |
|---|---|---|
| `noKey` (no_key), `keyUnreadable` (bad_key), `badKey` (bad_key, provider 401/403), `noCredit` (no_credit), `modelUnavailable` (model), `forbiddenAddress` (bad) | the web text, then "Ask your administrator." or, for an administrator, "Set it up in the web app (Admin console > AI agents)." | Close |
| `noPermission`, `notSetUp`, `agentGone` | as before | Close |
| `careNotFound` | the server's `not_found` text ("No such user." / "No shared conversation with that person.") | Close |
| `offline`, `serverTimeout` (network), `timeout`, `providerUnreachable`, `failed`, `badRequest`, `emptyAnswer` | web text | Retry |
| `rateLimited`, `agentBusy`, `providerRateLimited` (rate), `providerBusy` (busy) | server / web text | Try again |
| `tooLarge` (too_large) | "That question came with too much data. Ask something narrower." | Change range (a care thread has none: Close) |
| `noMessages` | "There are no messages in this range." (care: "Nothing has been recorded in this thread yet.") | Change range (care: Close) |

Care threads:
- The person is the `<username>` of the group name `care-<username>` (the web does the same: `chatId.replace(/^room-care-/, "")`). A name without a usable username (`care-`, spaces) hides the icon.
- Sheet: no range; the note "Up to the latest 500 messages and the person's forms"; "Older messages were left out." after the answer when `stats.truncated`. The e2e block and the privacy caption are as in other chats.
- Prompt: the web has no AI "summarise" for a care thread. Its card is built from data with no AI, and the AI box takes the person's own question (`askAboutThread` in `workspaceAgent.js`, which reads the thread itself and builds its own record). So the system prompt is that function's text word for word (team and patient wording), the house style guide, and the `care.summary` text under `THE THREAD, FORMS AND GROUP CHAT IN ORDER` in place of its two data sections. The question text is an assumption (the chat question reworded for a thread): `AiPrompt.careQuestion`.

## Open questions for the BE / owner

1. (resolved) `isAdmin`: same value in `perm.mine` and `me`.
2. `{name}` in the opening line: the app sends the display name of chat titles (`TicketRepository.nameOf`), the username when there is none. Confirm that is what the web puts there.
3. Sharing in v1 (doc decision 5): the doc recommends on-screen first. Kept, with the preview, until the owner decides.
4. (resolved) Care threads: built from the shape in the task.
5. (resolved) Charts are drawn.
6. (resolved) Error words: ported from `assistantErrors.js`.
7. The note `(the whole conversation)` is, by the doc's wording, the head even when a start date was chosen. Followed literally; the question itself says "only the messages from ...".
8. Consent for chats that are not encrypted (doc decision 1): none, as the web.
9. The form field values use the raw `label`/`value` of the message, as the doc's example shows. Grid sections are not in form messages, so they are not in the transcript.
10. Care prompt: is the care system prompt of `askAboutThread` with a "Summarise the care thread ..." question what the BE wants for a one-tap summary? The question text is ours (`AiPrompt.careQuestion`).
11. Care thread of the person themselves (`care-<me>`): the patient wording is used, as the web does; confirm `care.summary` accepts the person asking about their own thread.

## Care threads: typed questions (12 Nov 2026)

Source of the texts: `connectum/chat-app/features/connectumChat/services/workspaceAgent.js`, `askAboutThread` (lines 490-521), read from `origin/main` of the web repo.

- **Verbatim rule.** The PATIENT and TEAM system texts and the shared rules are constants of `AiPrompt` (`carePatientOpening`, `careTeamOpening`, `careThreadIntro`, `careUnderstand`, `careNotRecorded`, `careFormat`) with a comment naming the web file. Do not paraphrase. The web's `FORMS AND NOTES, BY VISIT` block (`summarisePatientThread`) is not ported (no Dart port of the form logic): the forms are in the chat as `[form submission]` lines.
- **Which call.** One-tap "Summarize this thread": `care.summary` (clipped: 8 fields per form, 160 characters per value, 500 messages). A typed question: `care.thread {person}` (existence, `not_found`, the `conversation` id), then the newest history pages of that conversation (`/history group care-<user>`, `before` paging, at most 10 pages, into SQLite like any history), then `care.summary` only for its `team` and the person's name. The transcript is built from SQLite.
- **Patient or team.** `AiPrompt.isPatient(me, person)`: the signed-in username equals the thread person, ignoring case (the web's test). The patient answer carries the line "You see the parts of the conversation you have access to".
- **Trimming.** 400 messages and 70,000 characters, header included (500 characters are kept for it). The oldest messages go first; the header says "only the newest N of M are shown: older messages were not read", also when the server still holds older pages.
- **Errors.** `not_found` is matched by `error.code` only, never by text. Patient: "Your care conversation starts once your care team is connected with you. Please check again after that." Anyone else: "There is no shared care conversation with this person yet." (unknown user and no thread share one code and one wording). History that did not arrive: the server-timeout error.
- **Typed answers** stay on the person's screen: no "Share in chat". They are single turns (no earlier questions are sent).
- **Differs from the BE message.** `care.thread` returns only `{conversation, person}` (`sd_cmds_people.erl:38`, `CONNECTUM_API.md:925`). There are no messages, team or limits in it; 400 / 70,000 are the web client's `formatTranscript` limits. Visibility (a patient sees fewer forms) is applied by the server on the history and on `care.summary`.

Open BE test: a patient (`care-<own username>`) with `care.thread`, `/history group care-<own>` and `care.summary`: confirm all three are allowed for the owner, that the history is already visibility-filtered, and that `not_found` carries the code before the first employee is connected.
