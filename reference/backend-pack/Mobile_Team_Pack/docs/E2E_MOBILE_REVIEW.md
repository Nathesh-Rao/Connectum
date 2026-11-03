# Review of `e2e-mobile-implementation.md`, and answers for the mobile team

Written 1 November 2026 against the backend and web code in this repository. Everything below was checked in the code (file names given); nothing was observed on a live server. Companion pages: `E2E_FRESH_DEVICES_CHANGE.md` (the server change), `E2E_MOBILE_KIT.md` (checker and vectors), `E2E_SIMPLE_GUIDE.md`.

## In short

1. **The mobile crypto matches our spec** in every point your document lists (raw 64-byte r‖s signatures, base64url without padding, HKDF salt = decoded `mid`, the three additional-data strings, 64-byte padding with a big-endian length, 65-byte public keys). Nothing in section 3 needs to change. The format is not the problem.
2. **Your own diagnosis is right** (section 8 mechanisms 1 and 2, section 12 gap 1): the phone trusts a cached device list for up to 5 minutes and does not refresh before sealing, so a device the other person registered in the last 5 minutes gets no wrap. That is exactly the "Sent before this browser was set up for encryption" case.
3. **The server now refuses such a message** (`e2e_stale_devices`) instead of delivering it. See `E2E_FRESH_DEVICES_CHANGE.md`. **The app needs two small changes** (below) so that this refusal never reaches a person.
4. **One assumption in your document is wrong and it matters:** `e2e_devices_changed` is **not** sent to the people who message that user (section "Corrections").

## Corrections to assumptions in the mobile document

| Your assumption | What the code does | Where |
|---|---|---|
| 11.4 #2: `e2e_devices_changed` goes to every connection that might send to or read from that user | It goes **only to the user whose devices changed** (their own sockets). Peers are never told. | `sd_e2e.erl` calls `sd_notify:push_event(User, ...)` for that one user |
| So the 5-minute cache is invalidated by the event | For a **peer's** entry, never. Only the TTL, a server error, or a forced refresh clears it. The event is useful only for "my own list changed" (which you already use to re-run `ensureSetup`). | same |
| A1: the web caches the directory for 5 minutes | For direct chat the web asks `e2e.devices` **fresh for every message** (`e2eClient.js`, `#plan`, `fresh: true`), and `e2e.group_devices` for every group message. It uses the cache only when reading (a sender device it has not seen is looked up once). | `chat-app/features/connectumChat/e2e/e2eClient.js` |
| A4: the server only requires one wrap per person | That was the rule until this change. **Now a wrap is required for every device that exists now**, the sender's other devices included (the sending device itself may omit its own). | `sd_e2e.erl`, `validate_wraps/5` |
| 11.2: chat error codes the app handles | Add **`e2e_stale_devices`** (new). It carries `mid`, `conv`, `users`. | below |

## Answers to the questions for the backend team

1. **`e2e: true` on every history item and `/conversations` row?** Yes. The server adds `"e2e": true` to any history line and any `/conversations` row whose text starts with `e2e1:` (`chat_web_send:e2e_field/1`, used by `history_line` and the `/conversations` handler). Live `private`/`group_message` events do not carry it (you detect the prefix, which is right). A sample row without it is a sample of a non-encrypted row.
2. **Who receives `e2e_devices_changed`?** Only the user whose devices changed, on their own connections. Not peers. A socket that connects after the change does not get the event; it learns the list from `e2e.status`/`e2e.devices`. Do not depend on the event for peers (see above).
3. **Same `cid`, different envelope?** The server runs the command the first time and **remembers the ack** (one day, `CONNECTUM_CID_TTL_SEC`). A second send with the same `cid` does not create a second message: you get the **same ack** (same message id) with `"duplicate": true`, and the **first envelope stays**. **A send that is refused is not remembered**, so after a refusal (`e2e_stale_devices` included) you may send a **new** envelope under the **same** `cid`. (`chat_web.erl`, "a client id on a send".)
4. **Is `keys` trimmed when stored or served?** Served. The stored envelope keeps the full wrap list; each reader gets only the wraps for their own currently registered devices (`sd_e2e:for_viewer/2`, applied to history, live delivery, cards and the feed). We can give you the wrap device ids for a message id on request, from the server; the registration time of a device is its `ts` in `e2e.devices`.
5. **Can the refusal name who is missing?** Yes, for the new code: `users` lists the people whose devices to look up again; `mid` and `conv` name the message and the conversation. It does not list device ids (the client can look them up with `e2e.devices`). `e2e_peer_not_ready` already names the people in its text.
6. **Maximum WebSocket frame size?** We found **no explicit frame limit** in our code (`chat_web_frame.erl`) or in the nginx reference config for `/ws`. The envelope cap is enforced by the server's own check (about 120000 characters). We have not load-tested a maximum-size envelope through the proxy; if you build one near the cap, tell us how it behaves.
7. **Do reader lookups count against `e2e.devices` 600 per 600 s?** Yes, per user, and the code is `rate_limited`. One lookup per unknown sender (plus one forced retry) is well inside the limit. Batching several users into one call (up to 50) is allowed and cheaper. Refreshing `[peer, me]` once per send is one call per send: also well inside the limit unless a person sends more than about one message a second for ten minutes. Debounce (do not refresh again if you refreshed in the last ~10 seconds) if you want to be safe.
8. **Plan to re-wrap history for a new device, or a "no wrap for device X" signal?** No re-wrap exists: a message key is only ever held inside the wraps, so nothing can add a wrap afterwards. The options being weighed (company recovery key, devices helping each other, or turning end-to-end off) are in `E2E_SIMPLE_GUIDE.md`; not decided. A precise reason on the reader's side is possible on the web and in your app: `not_for_this_device` is exactly "no wrap for my device id", and it is final.

## What the app should change (in this order)

1. **Refresh before sealing.** Before building an envelope, force-refresh `[peer, me]` (`e2e.devices {users:[peer, me]}`; your `isForced`). This is your own idea in section 12 and it removes the cause, not only the symptom. After this the refusal below becomes rare.
2. **Handle `e2e_stale_devices`.**
   - It arrives as a chat `error` event: `{ "type":"error", "code":"e2e_stale_devices", "text":"…", "mid":"…", "conv":"dm:a|b", "users":["bob"] }`.
   - Match it to your send by `mid`: your stored envelope in `messages.text` contains it, so you can find the exact outbox row (no "oldest in-flight" guess, which your gap 11 says can pick the wrong message).
   - Drop the directory cache for `users`, then rebuild a **new** envelope from the same text (new `mid`) and send it again **under the same `cid`** (the server did not remember the refused send). Do it silently. Allow two attempts, then show the error.
   - Until this is done: the code is **not in your handler's list**, so a stale send is retried after the 15-second ack timer using the **same stale cache** (your `_onE2eError` drops the cache only for the codes it knows). It would fail up to five times and show "too many attempts". The smallest change is to add the new code to the list that drops the cache and attributes the error to the send.
3. **Optional, from your own list:** clear the directory cache on `welcome`; re-run `_decryptPending` when the app returns to the foreground; treat `directory_<code>` errors as retryable, not final.

## Rollout note

The rule is on by default on the server. Until the app does change 2, a person messaging someone who registered a device in the last 5 minutes will see a failed send (later fixed by the cache expiring) where before the message was delivered but unreadable on that one device. If that is not acceptable for a period, the backend can be switched back with `CONNECTUM_E2E_REQUIRE_ALL_DEVICES=0` (see `E2E_FRESH_DEVICES_CHANGE.md`). Messages to a person who has had the same devices for more than 5 minutes are not affected.

## Things in your document that need no action but are worth knowing

* **Retry rebuilds the envelope under the same `cid` (your gap 8).** Safe: the server keeps the first and answers `duplicate: true` (answer 3).
* **Plaintext in SQLite (gap 6).** A decision for you. It is a design trade-off, not a protocol issue.
* **No multi-device history (gap 7).** That is the recovery question above, for all clients, not only mobile.
* **Group send is blocked on mobile.** Fine. Note: if the phone is registered, a web user's encrypted group message is wrapped for the phone too, and the phone shows "can't be read" until groups are supported. If that is unwanted, the options are on the product side (not registering the phone for end-to-end until groups work, or a mode that does not encrypt groups). Not changed here.

## Later the same day: device alerts and a Content-Security-Policy (do they change anything for the app?)

**No change is required in the mobile app for either.** Details, so nobody has to guess:

| Change | What the server sends or does | Effect on the Flutter app |
|---|---|---|
| **Alert to the account owner when a device is added** | A new item in the notification feed (`feed.list` / the live `feed_item` push): `category: "security"`, `severity: "medium"`, title "A new device was added to your encrypted messages", `message` with the device's name. Nothing new on the chat connection, no new `sd` action, no changed field. | **None required.** If the app shows the notification feed it shows this like any other item; if it does not, nothing breaks. It is a good thing to show (it is the only way a person finds out that someone else added a device). Your own phone's first registration does **not** produce it; a second device on the account does, and it is shown on the phone too. |
| **Contact notice** ("@bob added a new device") | Nothing from the server. The web app detects it from the keys it already pins. | **None.** Optional and worth having: your app already pins devices (`e2e_pins`); when `checkPins` pins a device id for a user who already has pinned devices, you can tell the person once. Skip your own devices and `recovery: true` devices. |
| **`e2e_stale_devices` log line** | One server log line per refusal. | None. It lets us count how often the old-list case still happens after your release. |
| **Content-Security-Policy** | An HTTP header on the **web page** only, in report-only mode, plus `POST /api/sd/csp-report` for browsers. | **None.** It concerns browsers; the Flutter app does not load our web page and does not send or receive these reports. Pages the app opens in a web view (if any) are served by the same nginx; in report-only mode nothing is blocked. |

The mobile Postman collection (`docs/postman/Connectum_Mobile_QR.postman_collection.json`, folder 5, change 8) describes the feed item.

## Later: the past on a new device (this one needs the app)

A device added after other messages were sent can now be shown the past by a device the person already uses (the way WhatsApp does it for a linked device). **Unlike the alerts and the CSP above, this needs work in the app:**

1. **Reading:** a box in `keys` may carry its **own** one-time key, `keys[<device>].ek`. Use it instead of the envelope's `ek` when it is there. A reference message is in `docs/e2e-test-vectors.json` (`lateBox`) and the checker opens it.
2. **Handing on, and the cards around it:** when `e2e.status` says this device is `late`, show "waiting"; on an older device, `e2e.sync.pending` lists the waiting devices: offer, then (after Approve) make a box per message with a fresh one-time key, send them with `e2e.sync.put`, finish with `e2e.sync.done`.

3. **Backup and restore for the recovery code:** the same job with the recovery key as the target (turn recovery on, the earlier messages are backed up), and on a new device the code brings everything back and the device locks the past for itself. WhatsApp's encrypted backup, with no file in a cloud.

Everything is in **`docs/E2E_HISTORY_SYNC_MOBILE.md`**: the story, the four new actions, the exact crypto, the edge cases, the session rule to know about (one active session per person), and a test list. The mobile Postman collection (folder 5, change 9) has the real replies. Nothing else in this review changes: do the two items of "What the app should change" above first.

