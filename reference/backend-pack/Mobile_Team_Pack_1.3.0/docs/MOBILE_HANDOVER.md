# Start here: everything the mobile team needs

Written 2 November 2026, updated 3 November 2026 (rows 8 to 11). One page that points at every document, file and tool made for the mobile app, in the order you will need them, with what the app must do for each. Everything named here is in the repository (`connectum/`) and live on the server unless it says otherwise.

## 1. Read in this order

| # | What the app does | Read | Check your work with |
|---|---|---|---|
| 1 | **Opens from a QR code or a link**: the link, the app-link files, the landing page, the three flows | `MOBILE_QR.md` | the Postman collection (folders 1 to 4, and 7 for the Play referrer) |
| 2 | **End-to-end encryption**: make keys, register the device, send, read | `E2E_ENCRYPTION.md`, `E2E_SIMPLE_GUIDE.md`, `E2E_MOBILE_REVIEW.md` (the two changes the app needs) | `E2E_MOBILE_KIT.md`; `e2e-test-vectors.json`; `node tools/e2e-kit/e2e-check.mjs reference` |
| 3 | **Earlier messages on a new device, and backup and restore** with the recovery code | `E2E_HISTORY_SYNC_MOBILE.md` | `e2e-test-vectors.json` (section `rewrap`: fixed inputs, the bytes to match, the boxes to refuse; section `recovery`: a fixed code, the sealed copy, HKDF info and AAD, the plaintext it must open to, seven refusals); `e2e-sync-replies.json` (real replies); `node tools/e2e-kit/e2e-rewrap.mjs reference`; the stand-in new device `tools/e2e-kit/new-device.mjs` |
| 3b | **Encrypted files, photos, videos, voice notes**: lock, upload, the tag, open | `E2E_ATTACHMENTS.md` | `e2e-attachment-vectors.json` (four real files with fixed keys, eight blobs to refuse); `node tools/e2e-kit/e2e-attachment.mjs reference` or `check input.json` |
| 4 | **Message text**: line breaks, bold, lists, code, links | `MESSAGE_FORMATTING.md` | `message-format-vectors.json` (41 messages with the exact result) |
| 5 | **Message options**: reply with quote, forward, copy, copy link, edit, delete, **save, pin, mark as unread**; the link to a message | `MESSAGE_OPTIONS.md` | the worked examples in the Postman collection |
| 6 | **Forms**: run the same logic as the web, field by field | `FORM_LOGIC_FOR_MOBILE.md` (the files, what the engine needs, grid cells, what the server checks, offline choices), `FORM_FIELD_TYPES.md` (every field type and the value it is saved as) | `sample-forms/` (twelve sample forms, `cases.json` with the numbers to expect); the published logic at `/form-logic/manifest.json` (one-script bundle, host shim and a conformance file to run in your engine) |
| 7 | **Every action and event**: the whole interface | `SD_ACTIONS_REFERENCE.md`, `CHAT_PROTOCOL.md`, `CONNECTUM_API.md` | the Postman collections |
| 8 | **Tickets and tasks**: any form with a status field; send, update, complete, return, drop, close; history | `TICKETS_AND_TASKS.md`, `TICKETS_AND_TASKS_MOBILE.md` (what to draw, every call with a real reply, the person's lists) | the mobile Postman collection, folder 6 |
| 9 | **The Inbox: Tasks & tickets**: what is with me, what I raised, act on the row; kept current by a live event | `INBOX_TASKS_AND_TICKETS.md` | folder 6 (`status.mine`, `ticket_assigned`) |
| 10 | **Approvals and sign-up as cards**: Approve / Reject on a card, one list, the rules | `APPROVALS_AND_SIGNUP.md` | folder 6 (`req.list`, `req.respond`) |
| 11 | **Messages from other systems in My Workspace**: an API puts its result or error into a person's notification feed (category `api`, with `source`, `outcome`, `httpStatus`, `data`) | `API_WORKSPACE_MESSAGE.md` (section "For the mobile app") | folder 6 (`feed.list`) |
| 12 | **The My Workspace feed (the bell)**: every kind of item, what a tap opens, the calls, `conv.read` and the feed, push | `WORKSPACE_FEED_MOBILE.md` | `feed-replies.json` (real replies); Postman folder 8 |

## 2. Postman

Both are in `docs/postman/`.

- **`Connectum_Mobile_QR.postman_collection.json`**: the one for you. Folder 5 is **"What changed for the mobile app (read this first)"**, numbered 1 to 15, and folder 6 is **"Tickets, tasks, the Inbox and approvals (3 November 2026)"**, each with real replies as examples (end-to-end recovery, a new device shown the past, backup and restore, message formatting, message options, save and pin and unread, the form logic). A WebSocket request cannot run in a collection run, so each is shown as its message.
- `Connectum.postman_collection.json` and `Connectum.postman_environment.json`: the whole platform, for when you want any other action.

## 3. Tools (Node 22 or newer, nothing to install)

| Tool | For |
|---|---|
| `tools/e2e-kit/e2e-check.mjs` | opens an envelope the way a receiving device does and names the first step that fails |
| `tools/e2e-kit/e2e-rewrap.mjs` | the older device's job (lock the past for a new device) as a reference, and a check of a box your app made |
| `tools/e2e-kit/new-device.mjs` | a stand-in for the **new** device, so the older-device side can be tested with one phone |
| `tools/sample-forms/load.mjs` | loads the sample forms into a test organisation (an administrator's session) |

## 4. Rules that shape the app

- **Two sessions per person: one phone and one laptop.** Send `"client": "mobile"` when you enter an organisation: without it the phone is treated as a laptop and ends the laptop's session. A second phone ends the first one. Keep the device keys when a session ends. Handle `sd_event` `conv_changed` (`data.by`): the other device changed a conversation, read it again. (`E2E_HISTORY_SYNC_MOBILE.md`, "Sessions".)
- **The server never runs a form's rules or calculations**; it checks the shape of each value. The app is the only place they run. (`FORM_LOGIC_FOR_MOBILE.md`, section 6.)
- **Send plain JSON values:** dates `yyyy-mm-dd`, times `HH:MM`, numbers without thousands commas, a switch as `Yes` or `No` (`FORM_FIELD_TYPES.md`).
- **Limits** (per person): `e2e.sync.put` 400 calls per 10 minutes (1 to 500 items), `e2e.sync.page` 600, `e2e.devices` 600; saving, pinning and unpinning 300 a minute, reading the saved and pinned lists 1200; a person may save 500 messages and pin 10 per conversation. The QR flows have their own limits (`MOBILE_QR.md`, section 4). A refused call answers `rate_limited`: wait and send the same thing again.
- **Encrypted messages:** the server only ever holds envelopes. Saved and pinned messages and the pages of `e2e.sync.page` come back narrowed to the person's own boxes; open them as any history.

## 5. What we are waiting on from you

- The two encryption changes in `E2E_MOBILE_REVIEW.md`, and reading a box that carries its own one-time key (`E2E_HISTORY_SYNC_MOBILE.md`); the offer, the hand-on and the backup can follow.
- iOS values for the app-link file (the Team ID and the bundle id).
- The testing branch in the test organisation (an administrator adds it under Admin console, Branches).
- Any place two of these documents disagree: tell us which and we will fix it.

## 6. How we keep this current

The Postman collections and the action reference are **generated** from the code (`node tools/postman/build.mjs`, `node tools/postman/mobile-changes.mjs`), so they cannot fall behind the server. The vectors and the sample forms are checked by tests on every change. If a document here and the code ever disagree, the code and its tests are right and the document is a bug.
