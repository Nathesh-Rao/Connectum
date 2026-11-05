# Push and local notifications: what exists, and a proposed design

Paths relative to `connectum/connectum-backend/src/` unless noted. **Part A is fact from the code; Part B is a proposal, nothing of it is built.**

## Part A. What exists today

1. **No push service in the backend.** Searching the backend for FCM, APNs, Firebase, web-push and "push token" found nothing. There is no table or action for registering a device token.
2. **No browser notifications in the web app.** No `Notification` API use and no service worker in `chat-app`, `form-studio/src` or `public`.
3. **The only live channel is the open socket.** `sd_notify:push_event/3` sends `{"type":"sd_event",…}` to a connected user and does nothing for an offline user (`core/sd_notify.erl`:142–168). Offline people catch up by reading `feed.list`, `req.list`, `cards.list`.
4. **Outbound messages that do exist are not notifications:** OTP and invites by log / fixed / SMTP / webhook (`core/sd_notify.erl`:1–140; mail queue `sd_mailq`; generic `CONNECTUM_NOTIFY_WEBHOOK` for kinds `otp` and `invite`).
5. **No do-not-disturb, quiet hours or per-type preference.** Only the per-conversation `muted` flag (`forms/sd_conv.erl`:5–22), which the client honours.
6. **Sessions:** one active session per client kind, `web` or `mobile` (`security/sd_auth.erl`:156–190). So there is already a place to know "this person has a phone session"; a push token could hang off that session.
7. **End-to-end messages:** the server holds only ciphertext (`security/sd_e2e.erl`:1–25). It cannot write the message text into a push.

## Part B. Proposed design

### B1. Token registration
New actions (proposal): `push.register {platform: ios|android, token, deviceId?, appVersion}`, `push.unregister {token}`. Store per person, per mobile session, max 10 tokens (same limit as e2e devices). Delete the token when the session ends (`session_replaced`, sign-out), when the provider says it is invalid, and after 60 days unused. Never log the token. Rate-limit registration.

### B2. When a push is sent
Send a push only if the person has **no live connected socket** at that moment (otherwise the in-app event suffices). Hook at the point where the feed item is created (`sd_feed:notify`), because that is the single place all of §2 of `NOTIFICATIONS_FOR_MOBILE.md` passes through, and respect: muted conversation (server flag today), severity floor chosen by the person, and coalescing (use the item `key` as the collapse key so 20 DMs show as one).

### B3. Payload (privacy first)
- Plain items (tasks, tickets, approvals, announcements, API messages): `title`, short `message` (≤ 100 chars), `itemId`, `actionType`, `chatId?`, `ref?`, `count`. These are readable on the server already.
- **E2E chat messages: no text.** The push says "New message" (sender name optional, off by default) with `itemId`/`chatId`; the app wakes, fetches the envelope, decrypts on the device and posts a **local** notification with the real text. This needs a silent/data push (iOS: notification service extension with mutable-content; Android: data message).
- Never put tokens, OTPs or e2e envelopes in a push.

### B4. Deep links
Reuse `actionType` as the contract: `open_chat` → chatId, `open_message` → chatId + messageId, `approvals`, `tickets`, `submissions`, others → My Workspace. A tap opens the app, then the app calls `feed.read` for that item.

### B5. Local notifications
Used for: (a) decrypted e2e messages (B3); (b) reminders due while the app is in background (the server already knows `dueTs`, `sd_cards.erl`:194–231; a local schedule avoids waiting for the server tick, but the server remains the source of truth and must cancel the local one when dismissed); (c) foreground toasts for `feed_item` while connected.

### B6. Delivery rules
Collapse by `key`; badge = `feed.summary.unread`; clear a push when the item is read/resolved/dismissed on any device (`feed_changed` / `feed_removed`); no push for the person's own actions; no push for `low` severity unless chosen; honour per-conversation mute; retry with provider back-off, drop after 24 h.

### B7. Reliability
A push is a hint, never the data. After opening, the app re-reads state (as in the notifications doc §4). Silent pushes can be throttled by the OS; do not rely on them for correctness.

## Open questions (decisions needed before building)
1. Provider and accounts: FCM for both platforms, or APNs directly for iOS? Who owns the credentials and where are they kept (not in the repo)?
2. Is showing the sender name in an e2e push acceptable?
3. Do we add global preferences and quiet hours (none exist)?
4. Should the server stop creating feed items for muted chats (today only the client hides them)?
5. Private-cloud organisations: does each have its own push credentials?
6. Where does the push worker run (the feed already uses a background worker, `sd_feed_srv`)? Load impact has not been measured.
7. Data-protection: is a message title (task title, ticket text) allowed to pass through Apple/Google?

## Suggested build order
1. Backend: token table + `push.register/unregister` + tests (no sending).
2. Backend: sender behind a switch, only for items that are plain text; sandbox accounts.
3. Mobile: register, receive, deep link, badge, clear on read.
4. E2E path: silent push + on-device decrypt + local notification.
5. Preferences and quiet hours.
6. Load test with real fan-out (a broadcast to many people).

## What mobile must match exactly versus what may differ
**Must match exactly:** the deep-link contract (`actionType` values and `chatId`/`ref`); the rule that e2e text never travels in a push; the collapse key = item `key`; badge = `unread`; clearing on read/resolve/dismiss; re-reading state after open.
**May differ:** notification channels/categories, sounds, grouping style, whether sender names appear (once decided), quiet-hour UI, local scheduling details for reminders.
