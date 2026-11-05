# My Work Space and notifications: study

Study only. Nothing was built, sent or run. Sources: backend pack `reference/backend-pack/Mobile_Team_Pack/docs/` (`SD_ACTIONS_REFERENCE.md` = SDA, `CHAT_PROTOCOL.md` = CP, `E2E_ENCRYPTION.md` = E2E, `E2E_MOBILE_REVIEW.md` = REV, `MESSAGE_OPTIONS.md` = MO); Postman `Connectum_Mobile_QR.postman_collection.json` folder 5 (= PM5) and `postman/api_collection_connectum.json` (= PMAPI); backend `origin/main` `docs/CONNECTUM_API.md` (= API, line numbers of that file at origin/main), `connectum-backend/src/forms/sd_cards.erl`, `sd_feed.erl`; web `chat-app/features/connectumChat/...` (= W).

## A. Actions, events and pushes

### A1. Two separate layers (API:426-428)
"It is a separate layer from `notifications.*` (the four badge categories). Keep using `notifications.*` for the chat-list badges; use `feed.*` for the workspace panel." Cards (`cards.*`) are a third thing that both are derived from.

| Layer | Actions | Where documented |
|---|---|---|
| Cards (inbox, sections) | `cards.list {section?, limit?}` -> `{cards, sections}`; `cards.dismiss {id \| "all"}` -> `{dismissed}`; `sections.list/save/delete`; `reminder.add {text, dueTs?}` -> `{card}` | SDA:101-106, API:~320-384 |
| Badge counts (four categories) | `notifications.summary {}` -> `{counts:{priority,pending,personal,reminders}, total, personalBySender:{username:n}}`; `notifications.list {category?, unreadOnly?, limit?}` -> `{notifications:[card], counts}`; `notifications.read {ids \| category \| all}` -> new summary | SDA:107-109, API:~397-410 |
| Workspace feed (the panel) | `feed.list {priority?, category?, unreadOnly?, limit?, before?}` -> `{notifications, counts, hasMore}`; `feed.summary` -> `{high,medium,low,resolved,unread,total}`; `feed.read {ids \| all, read?}` -> `{updated, counts}`; `feed.resolve {id}` -> `{notification, counts}`; `feed.dismiss {id}` -> `{dismissed:true, counts}`; `feed.clear {}` -> `{cleared, counts}`. REST twins `GET /api/sd/feed`, `/feed/summary`, `POST /feed/read|resolve|dismiss|clear` | SDA:110-115, API:~480-490, `mobile-handoff/postman-crosscheck.md:28-33` |

Not in SDA or API but in code: `feed.resolve {all:true}` -> `{resolved:n}` (`sd_feed.erl` `do_call(<<"resolve">>, User, #{<<"all">> := true})`; web `utils/feedActions.js`, used by "Mark All Resolved"). `mobile-handoff/websocket-protocol.md:208` already lists it.

### A2. Events and pushes (S>C, only while the socket is open; nothing is replayed, API:~495-500 "Reload `feed.list` on every (re)connect")
| Event | Data | Meaning | Source |
|---|---|---|---|
| `sd_event feed_item` | `{notification, counts}` | new or changed item; upsert by `notification.id` | API:731 area, `websocket-protocol.md:210` |
| `sd_event feed_removed` | `{ids, counts}` | dismissed or cleared (also from my other devices) | same |
| `sd_event feed_changed` | `{ids, read, counts}` | marked read or unread | same |
| `sd_event card` | `<card>` with `section, category, read, due` | a new card (message, approval, reminder) | API:728 |
| `sd_event notification` | `{card, category, counts}` | a new badge-category notification; reminder only once due | API:729 |
| `sd_event notifications_changed` | `{counts, total, personalBySender}` | counts changed (read, answered, dismissed, also on my other tabs) | API:730 |
| `sd_event request_created` / `request_resolved` | `<request>` | approvals | API:726-727 |
| `/read dm <user>` (chat command) | none | "For a signed-in Connectum user it also clears that sender's personal/priority notifications and pushes `notifications_changed`" | CP:121 |
| REST push | none exists. `ai-and-misc.md:161`: "no push notification infrastructure exists" (no FCM/APNs, no device-token endpoint) | | `ai-and-misc.md` section 4 |

### A3. Shapes (quoted)
Feed item, from API docs (API:~440-448):
```json
{ "id": "k3J…", "priority": "high", "category": "messages",
  "title": "Sam W", "message": "!server is down", "ts": 1790000000000,
  "icon": "chat", "read": false, "resolved": false, "resolvedTs": null,
  "actionType": "open_chat", "actionLabel": "Open chat", "chatId": "user-sam1",
  "count": 3, "severity": "high", "from": "sam1",
  "chat": {"scope":"dm","with":"sam1"}, "ref": null }
```
Real item, `postman/api_collection_connectum.json` "Feed: list" (the only real example in either collection):
```json
{"data":{"counts":{"high":0,"low":0,"medium":1,"resolved":0,"total":1,"unread":1},"hasMore":false,
 "notifications":[{"category":"reminders","count":1,"icon":"alarm","id":"KksbK34AJwh6V7VBcmH2vRxQjzIDuYwtUS9qjUUXP4U",
 "message":"Call the lab","priority":"medium","read":false,"ref":{"cardId":"IiXBHFkxCeihKgVpgTf-27k3otFFLX1n3IEXBZE-Wpc"},
 "resolved":false,"resolvedTs":null,"severity":"medium","title":"Reminder","ts":1793166706292}]},"ok":true}
```
Note: the real item has no `actionType`, `actionLabel`, `chatId`, `chat` or `from`. The documented sample has them. A client must treat all of these as optional.
Real summary / read: `{"data":{"high":0,"low":0,"medium":1,"resolved":0,"total":1,"unread":1},"ok":true}` and `{"data":{"counts":{...,"unread":0},"updated":1},"ok":true}`.
Resolve, dismiss, clear: no example anywhere (`postman-crosscheck.md:31-33` "no example").
Card (API:~375): "A **card** is `{id, kind, from, text, ts, section, chat?, ref?, messageId?, dueTs?}`. `kind`: `dm`, `group`, `request`, `reminder`, `system`." The only real `cards.list` reply on hand is empty: `"data":{"cards":[],"sections":[]}` (`websocket-protocol.md:52`). Built-in sections (`sd_cards.erl:48-52`): `priority, pending, reminders, updates, general, personal`.
Field values: `priority` high|medium|low|resolved; `category` messages|approvals|submissions|reminders|security|system|api; `actionType` open_chat|open_message|approvals|submissions|axpert|none (API) and, in web `ConnectumChatScreen.jsx:1266-1290` also `admin_console`, `about_me`, `smart_prompt` (not in API). `ts` is epoch ms; no pre-formatted time.
Priority rules (API:~455): DM medium, group low, either high if text starts with `!` or contains `#urgent`/`#priority`; approval waiting high; form submitted to you medium; due reminder medium; security: locked / 2FA off high, signed in elsewhere / recovery codes medium, password changed low; outcome of my own request low. Coalescing: messages fold into one row per conversation (`count` rises, turns unread again, re-opens a resolved one). Keeps the newest 300 items per user.

### A4. Message options that touch the workspace (MO:25-52)
`msg.save {conv,id}` / `msg.unsave {id}` / `msg.saved {limit?,offset?}` (`{items:[{id,conv,from,text,ts,kind,savedTs}],total,limit,offset}`, max 500); `msg.pin` / `msg.unpin` / `msg.pins {conv}` (max 10; not in the general room); `conv.unread {id,messageId}` -> `{conversation}` with `unreadFrom`. Events `saved_changed`, `pins_changed`. Real replies are in PM5 items 26-31. This app does none of these yet (grep `msg.save|msg.pin|conv.unread` in `lib/` finds nothing).

## B. What the web shows

### B1. My Workspace (home)
- A client-only thread. Welcome message from "Workspace Assistant"/"Connectum Workspace". Submission cards rebuilt from `submissions.list` (`mobile-handoff/workspace.md`). Typing in the composer sends nothing to the server. `/hostmsg workspace` is refused.
- Left slider (`WorkspaceChatsSlider.jsx`): the chat list (search, All/Hosts/Direct, quick buttons Group, New chat, Account). Right slider = the notification panel (below). "Smart Prompts" bar, mini chat, AI view: out of scope here.
- `useWorkspaceSubmissions.js` loads `submissions.list` for my cards.

### B2. Notification panel (`WorkspaceNotificationsSlider.jsx`, "Notifications Center")
- Header: bell icon with a pulse dot when `counts.unread > 0`; text "<role> Workspace • N unread" (or "My Workspace").
- Quick actions: "Mark All Resolved" (-> `feed.resolve {all:true}`; falls back to one by one) and "Clear Resolved" (-> `feed.clear`).
- Search box ("Search notifications...", matches title, message, text, actionLabel, category, client-side) and a filter menu: Priority All/High/Medium/Low/Resolved (each with its count) and "Unread only" (with unread count); a count badge on the filter button; "Reset filters". Filter choice is kept in localStorage (`connectum_notif_filter_prefs`).
- Card per item: priority pill (High Priority red `#ef4444`, Medium Priority yellow `#f59e0b`, Low Priority grey `#64748b`, Resolved green `#10b981`) + "15m ago"-style time (`formatTimeAgo`: Just now, Nm, Nh, Yesterday, Nd, Nw, then a date; refreshed each minute); category icon (messages chat, approvals how_to_reg, submissions description, reminders alarm, security security, api api; fallback by priority); title with ` (count)` when count > 1; message; for `category:"api"` an extra block (outcome tag, "from <source>", collapsible "The response" with `data`).
- Footer buttons per card: action arrow (`actionLabel`, hidden if `actionType === "none"`), "Resolve" (hidden when resolved), read/unread toggle (`feed.read {ids,read:!read}`), dismiss (x) (`feed.dismiss`). Unread cards have an `is-unread` style.
- Empty state: "No notifications" / "You are completely caught up."; with a search or filter: "No matching notifications" / "Try a different search term or filter."
- Footer legend: "High: Urgent, Med: Action, Low: Info, Resolved: Done".
- Bell in the top bar (`TopBar.jsx:187-196`): red corner badge with `priorityCounts.high` (99+), else a yellow badge with `medium`; none when the panel is open. Icon becomes a chevron while open.
- Live: `onFeedItem` (`chatEvents/workspace.js:110`): if not resolved, not read and Do Not Disturb is off -> chime, and a 3 s slide-in "peek" under the bell (`NotificationPeek.jsx`) except for `category:"messages"` (those come through the mini chat); then upsert and counts. A tap on the peek opens the panel. `feed_removed`/`feed_changed` update the list.
- Tapping an item's arrow (`handleNotificationAction`, `ConnectumChatScreen.jsx:1266`): `admin_console` -> admin console users tab; `approvals` -> Inbox, Approvals folder (and reloads requests); `open_chat` -> open `chatId`; `open_message` -> open `chatId` and show `ref.messageId` (the message-link path); `submissions` -> My Submissions modal; `about_me` -> profile modal; `axpert` -> Axpert dialog; `smart_prompt` -> smart structure modal; anything else other than `none` -> a toast "Opened: <title>". Tapping the card body does nothing.
- Not used by the web: `cards.list`, `notifications.summary/list/read`, `personalBySender` (grep of `chat-app` finds `cards.list` only in the decrypt whitelist `connectumSocket.js:99`). The web's chat-list unread counts are local and come from chat events. So the "four categories" layer exists on the server but no screen shows it.

## C. What this app does now
| Area | State | Where |
|---|---|---|
| Bell on Chats header | Opens `/notifications`. Shows a plain accent dot when `feed.unread > 0`; no number, no colour by priority. | `lib/features/chats/chats_view.dart:143-165`, `chats_controller.dart:193` |
| Unread source | `FeedRepository`: `feed.summary` on socket online, then `unread` from `counts` in `feed_item` / `feed_changed` / `feed_removed`. In memory only; no dot until the first answer. Reads `unread` only. | `lib/data/repositories/feed_repository.dart:1-46`, registered `core/routes/initial_binding.dart:80` |
| Notifications screen | Stub: title text only. Controller empty. | `lib/features/notifications/notifications_view.dart:14`, `notifications_controller.dart:3` |
| Local tables | None for feed, cards or notifications. (`form_submissions`, `form_definitions`, `messages`, `conversations`, `outbox`...) | `lib/data/db/app_database.dart` |
| Events handled | Only the three `feed_*` events above (for the count). `card`, `notification`, `notifications_changed`, `request_*` are not handled. | grep over `lib/` |
| Not called | `feed.list/read/resolve/dismiss/clear`, `cards.*`, `notifications.*`, `reminder.add`, `msg.save/pin`, `conv.unread` | grep over `lib/` |
| Marking read | Opening a chat sends `conv.read` (debounced, forward only). It does not send `/read dm`. Whether `conv.read` clears the sender's personal/priority notifications is not documented (question 6). | `lib/data/repositories/conversation_repository.dart:244-291` |
| My Work Space | Pinned row above the chat list (`chats_controller.dart:197` `openWorkspace`) and a `/workspace` screen: welcome text (the web's exact string), then my submissions as form cards (cache first, refresh when online) with day dividers, plus local "notes" (answers to `#` commands, "Sent to @name"). Composer: free text off, `#` commands and `@name` direct messages work, forms button works. Empty text "Forms you submit show up here." Mentions "the sliders on the left and right" in the welcome (web text), which mobile does not have. | `lib/features/workspace/workspace_controller.dart:100,120-170`, `workspace_view.dart:25-125`, `models/workspace_row.dart`, `workspace_note.dart` |
| Card list in the conversation | The "Work Space card list" is only the submission `FormCardData` rows. No notification or feed cards, no reminders, no approvals. | `workspace_controller.dart:_apply` |
| Push | No push provider, no device token, no `POST_NOTIFICATIONS` (CLAUDE.md "Permissions"). | |
| E2E | No decryption of cards or feed items (nothing reads them yet). | |

## D. Gaps, web vs mobile
| # | Web | Mobile | Gap |
|---|---|---|---|
| 1 | Panel with list, 4 priority tabs/filter, counts | Stub screen | whole screen |
| 2 | `feed.list` on connect and reconnect, upsert by id | only `feed.summary` | no list, no cache |
| 3 | Bell badge number, red `high` else yellow `medium` | one dot for any unread | counts by priority not shown or stored |
| 4 | Resolve, mark read/unread, dismiss, mark all resolved, clear resolved | none | all five writes (`feed.read/resolve/dismiss/clear`, `resolve all`) |
| 5 | Search and unread-only filter | none | |
| 6 | Item action by `actionType` (open chat, open message, approvals, submissions, axpert, ...) | none. Routes exist for chat and submissions; approvals/axpert/admin/profile destinations are mostly not on mobile | deep-link mapping needed |
| 7 | Live peek + sound (DND-aware) | none | needs a local-notification design |
| 8 | `category:"api"` details block | none | |
| 9 | Security items (signed in elsewhere, device added) | none | |
| 10 | Offline | web is online-only | mobile is cached-first by rule: needs tables `feed_items`, counts, and an outbox for the writes in #4 (stable `cid`-like handling is not defined for `feed.*`, question 8) |
| 11 | Reminders via `#remind` -> `reminder.add` | `#` command list is server-driven; whether `remind` is present is not checked | verify |
| 12 | Saved messages list, pins bar, mark unread | none | MO |
| 13 | `notifications.*` and `personalBySender` unused by web | unused | decide whether mobile uses them for per-chat badges (question 5) |
| 14 | Workspace thread shows submissions | same | web also slots approval cards in by time (`ConnectumChatScreen.jsx:1447`); mobile does not |
| 15 | Bell works with the panel docked | screen push | mobile layout to design |

## E. Encrypted items
- "The server's notification cards and feed carry the same envelope (narrowed to that person). The *app* decrypts it and builds the preview" (E2E:54-55). "`sd_cards.erl`, `sd_feed.erl` carry the envelope (flagged `e2e:true`) into notification cards and the feed instead of text" (E2E:250). Events with an envelope "are decrypted before any screen code sees them" (E2E:237).
- Web behaviour (`connectumSocket.js:99, 433-470`, `decryptSdData`): for `cards.list` and `feed.list` replies, and for a live `feed_item` whose `notification.e2e` is true: each card's `text` and each notification's `message` is opened (`openText(x[field], null)`, no conversation label); the preview is `e2ePreview(text)`; on failure the reason text is shown; for a group (`kind === 'group'`, `scope === 'group'` or `chat.scope === 'group'`) the result is `"<from>: <preview>"`. `msg.saved` / `msg.pins` items are opened with the label of their `conv`.
- What changes in mobile: every path that shows `message`/`text` of a card or feed item (list, live `feed_item`, any local notification, the peek) must run the same open-then-preview step before display and before it is written to SQLite or shown on the lock screen. The DB rule in CLAUDE.md ("decrypted text stored unencrypted on the device") applies: decide whether previews are stored decrypted. `title` is the sender name and stays plain in the sample. A device with no box shows the existing "This message can't be read on this device" text.
- Counts and priority are not encrypted. The server cannot see the text, so `!` / `#urgent` priority from text content cannot be judged by the server for encrypted messages (question 10).
- Device-added item: `category:"security"`, `severity:"medium"` (so `priority:"medium"`), title "A new device was added to your encrypted messages", `message` names the device (REV:60, E2E:302, PM5 item 8). Not for the first device, not for the same device re-registering, not for the recovery key; shown on every device including the new phone; device name is plain text, control characters removed, cut to 60 chars. Nothing new on the wire; REV says "None required" but "a good thing to show". The tap target (`actionType`) is not specified for it (question 9). Optional contact notice ("@bob added a new device") is app-side from `e2e_pins`, not a feed item (REV:61, E2E:303).

## F. What depends on the backend or a push provider
- Works with what exists: feed list/read/resolve/dismiss/clear, summary, live `feed_*` events, cards, notification counts, reminders, security items. All need an open socket.
- Needs a push provider and new backend work (nothing exists, `ai-and-misc.md:161`): any notification while the app is closed or the socket is down (FCM/APNs, a device-token endpoint, a sender, and a plan for E2E previews because the server cannot write the text). Until then, offline users see items only after the next `feed.list`.
- Local notifications while the app is open in the background are possible without a provider but depend on the OS keeping the socket alive (not reliable).
- Needs product decisions (not backend): which destination each `actionType` opens on mobile.

## G. Questions for the backend team
1. Does a real `feed.list` item always carry `actionType`/`actionLabel`/`chatId`/`chat`/`from`? The real "Feed: list" example (a reminder) has none of them; the doc sample has all. Which are optional, per `category`?
2. Is `actionType` a closed list? The web handles `admin_console`, `about_me`, `smart_prompt` that API does not list. What is the exact list, and which carry which `ref` keys?
3. Please add real replies for `feed.resolve`, `feed.dismiss`, `feed.clear`, `feed.resolve {all:true}`, `feed.read {read:false}`, `notifications.*`, and a non-empty `cards.list` (we only have `cards:[]`).
4. Is `feed.resolve {all:true}` supported and stable (it is not in SDA)? What does it return when nothing is open?
5. The web never calls `notifications.summary` / `personalBySender`. Is it meant for per-chat badges on mobile, and does it duplicate the `unread` in `conv.list`?
6. Does `conv.read` (what the app sends) clear the sender's personal/priority notifications and the DM feed row like `/read dm <user>` does? If not, should mobile send `/read dm` as well, or will `conv.read` be changed?
7. `feed.list` paging: `before` = last item's `ts`; two items with the same `ts` can be skipped. Is there a stable cursor? Is `hasMore` always present?
8. Are `feed.read/resolve/dismiss` idempotent and safe to repeat after a dropped connection (we queue them offline)? Is there a client id like `cid`?
9. For the "device added" item and the other security items, what are `actionType`, `chatId` and `ref`? Is there a screen the person should be sent to (devices list)?
10. For encrypted messages, how is priority decided (the server cannot read `!` or `#urgent`)? What is `title`/`icon` for an encrypted DM or group item? Does `count` coalescing still work?
11. How does an encrypted item look in `cards.list` and `feed.list`: the exact fields (`e2e:true`, envelope in `text` / `message`), and the `conv` label to use when opening (the web passes `null`).
12. Is there a plan for push (device-token registration, sender, payload without text for E2E)? Which provider, and when?
13. Is the 300-item cap and `feed.clear` (resolved only) the full retention story? Do dismissed items come back?
14. When a socket reconnects, is `feed.list` + `feed.summary` the full resync, or can a `since` be used to avoid refetching up to 200 items?
15. Does `notifications_changed` / `card` / `notification` also fire for the feed, or are they a separate stream we may ignore if we only use `feed.*`?
