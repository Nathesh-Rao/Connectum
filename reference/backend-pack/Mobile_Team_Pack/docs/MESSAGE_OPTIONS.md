# Message options (the bar, the menu, edit, copy, links, save, pin, unread)

Written 2 November 2026. How a person reacts to, replies to, copies, edits and links to a message in the web app. Teams-like, in the app's own colours, light and dark. Code: `chat-app/features/connectumChat/components/MessageActions.jsx` (the bar), `MessageMenu.jsx` (the menu), `MessageList.jsx` (what each item does), `utils/messageLink.js`, `utils/useOpenMessageLink.js`, `utils/menuKeys.js`, `utils/clipboard.js`; save, pin and unread: `utils/useMessageMarks.js`, `components/PinnedBar.jsx`, `components/modals/SavedMessagesModal.jsx`, `chatActions/markUnread.js`, and on the server `connectum-backend/src/forms/sd_msgmarks.erl` and `sd_conv.erl`.

## What the person sees

**The bar** shows when the pointer is over a message (or a button in it has the focus):

| Button | What it does |
|---|---|
| 👍 ❤️ 😂 😮 | react with that emoji; press again to take it away; a reaction you gave is marked |
| add-reaction | the full emoji picker |
| pencil | edit the message: **only your own text messages** |
| ⋯ | the menu |

**The menu** (⋯, a right click on the message, or a finger held on it for half a second on a phone):

| Item | Key | For |
|---|---|---|
| Reply with quote | Q | every message |
| Forward | F | every message |
| Copy text | C | a message with text |
| Copy link | L | every message |
| Edit | E | your own text messages |
| Save this message / Remove from saved | S | every chat message in a direct chat, group or the general room |
| Pin for everyone / Unpin | P | a direct chat or a group (not the general room) |
| Mark as unread | U | someone else's message |
| Delete | ⌫ | your own messages (the server only lets the author delete) |

Keys work while the menu is open: arrows, Home and End move, Enter chooses, a letter chooses its item, Esc closes (the focus goes back to the button). The emoji picker (more reactions) is drawn straight into the page too, so it opens next to its button. The menu keeps itself on the screen (above the point when there is no room below), is drawn straight into the page, and closes when the window changes size. A right click on a **link** or over **selected text** keeps the browser's own menu (so the selection can be copied).

**Edit** opens the edit window with the message as it was and the same formatting row as the message box (see `MESSAGE_FORMATTING.md`). Editing an end-to-end encrypted message re-encrypts it, as before.

## Save, pin, mark as unread

**Save** is private. A saved message gets a small bookmark next to its time, and the **Saved messages** list (account menu, the three dots by your name) shows them newest saved first, from every chat: choosing one opens its chat and flashes the message; the bookmark button takes it off. At most 500 per person (a message says so in words when the list is full). It follows the person to their other devices.

**Pin** is shared. A pinned message gets a small pin, and a bar under the chat header shows the newest pinned message (who pinned it, its first words). Choosing it shows the message in the chat; the x unpins; with several, "n pinned" opens the list. Either person of a direct chat, or any member of a group, may pin and unpin. At most 10 per conversation. The general room has no pins (it is for announcements to everyone, and has no one to unpin).

**Mark as unread** (someone else's message): the message and the ones after it count as unread again in the chat list here, and the server keeps the mark (`conv.unread`), so the mobile app's list shows it too. The web app's own unread counts are kept on the device, so another browser does not show it. Nothing the other people see changes (no "read" tick is taken back). Opening the chat reads them.

Rules that apply to all three: a message deleted for everyone leaves the saved list and the pins for good; a message the person cleared with "delete for me" is not shown to them; forms are not saved or pinned; a message that cannot be opened (end-to-end encrypted for a device that cannot read it) shows as "Encrypted message"; text is narrowed to the person's own end-to-end boxes like any history.

### The server (for the mobile app)

| Action | Arguments | Reply |
|---|---|---|
| `msg.save` / `msg.unsave` | `{conv, id}` / `{id}` | `{saved}` |
| `msg.saved` | `{limit?, offset?}` or `{ids:true}` | `{items:[{id, conv, from, text, ts, kind, savedTs}], total, limit, offset}` or `{ids}` |
| `msg.pin` / `msg.unpin` | `{conv, id}` | `{pinned, count}` |
| `msg.pins` | `{conv}` | `{pins:[{id, by, ts, message}], max}` |
| `conv.unread` | `{id, messageId}` | `{conversation}` with `unreadFrom` |

`conv` is `dm:<user>`, `group:<name>` or `global`. Errors: `limit` (500 saved, 10 pinned: both can be changed on the server with `CONNECTUM_SAVED_MAX` and `CONNECTUM_PINS_MAX`; the limits hold even when two things happen at the same moment), `not_found` (no such message in that conversation, or it was deleted), `invalid` (a missing or odd id; pins in the general room; a form), `rate_limited` (writing: 300 a minute per person, `CONNECTUM_MARKS_WRITES_PER_MIN`; reading the lists: 1200 a minute, `CONNECTUM_MARKS_READS_PER_MIN`). Events: `saved_changed {id, saved}` (to the person's own devices) and `pins_changed {conv, id, pinned, by}` (to everyone in the conversation, `conv` as it is for each of them). Real replies are in the mobile Postman collection ("Worked examples"). The server keeps a saved list in `sd:saved:<user>` and pins in `sd:pins:<conversation store>`; both only point at messages, the text is read from the message store when asked for.

Department channels (`host-<key>`) have no server name, so the web app offers none of these three there.

## A link to a message

**Copy link** puts `https://<the app>/?chat=<chat>&msg=<message id>` on the clipboard. `<chat>` is the app's name for the conversation: `user-<username>`, `room-<group name>`, `room-general`, `host-<key>`. Opening the link (signed in, or after signing in: it is kept for an hour and used once) shows that chat, scrolls to the message and flashes it once; the address is cleaned afterwards so a refresh does not jump again. Messages the person cannot see are not shown: a chat they are not in says "That chat is not available to you".

**Known limit:** a chat shows its latest messages (about 50) and the app does not page back yet, so a link to a **older** message says "That message is older than what this chat shows. Scroll up to find it." and opens the chat only. This improves when the chat can load older messages (the server already serves them: `/history <scope> <name> before <id>`).

## For the mobile app

The link format above is the one to **share** and to **open** (a `chat` and a `msg` query on the app's address). The option set is the one to match; the server rules are the same for the mobile app: only the author edits or deletes, a reaction is a `/react`, a reply is a `/reply`. Saving, pinning and marking as unread are server actions (the table above).

## Tests

- `connectum-backend/test/connectum_msgmarks_scale_test.mjs` (13): the real limits (500 saved, 10 pinned): the lists come back in about 25 ms, paging reaches every message once, a full list can be emptied.
- `tools/ui-audit/message-marks-e2e.e2e.mjs` (21, real Chrome): saved and pinned messages in end-to-end encrypted chats (readable, also after a reload; a message the browser cannot open gives a reason, never the envelope), a save or a pin made elsewhere showing live, and the keyboard (the Saved dialog keeps the focus inside and gives it back).
- `connectum-backend/test/connectum_msgmarks_test.mjs` (71): saving (order, pages, ids, the other person sees nothing, limits in words, refusals, a deleted message leaves), pinning (both people, limit, outsiders, the general room, groups, live events), mark as unread (count, receipts untouched, cleared by reading, refusals).
- `tests/frontend/messageMarks.test.mjs`: chat id to server name, message numbers, how many count as unread.
- `tools/ui-audit/message-marks.e2e.mjs` (41, real Chrome): the menu items and keys for someone else's and for your own message, the bookmark and pin marks, the pinned bar (one, several, the list, jump, unpin, a pin made by the other person live), the Saved messages list (open, remove, empty), mark as unread in the chat list, dark theme, a phone-sized window (the pinned bar and its list fit, the emoji picker stays inside).

- `tests/frontend/messageOptions.test.mjs` (8): the link (reads back, wrong kinds, once, an hour, no storage, cleaned address), the menu's keys, copying with and without the clipboard.
- `tools/ui-audit/message-options.e2e.mjs` (46, real Chrome): the bar, four quick reactions and their state, more emoji, the menu's items for someone else's and for your own message, keys, focus, copy text and link (the real clipboard), reply with quote, forward, edit with a line break reaching the other person, a right click, selected text, a long press and a scroll and a tap on a phone, staying inside a small window, closing on resize, delete, a link opening the message, an old message, a chat that is not there, dark theme.
