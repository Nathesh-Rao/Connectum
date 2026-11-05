# What the web chat shows for messages, and how the "@" list works (for the mobile team)

Written 4 November 2026 against `main`. This describes **what** is shown, **when**, and the **data** behind it, so the mobile app can build the same behaviour. Colours, fonts, spacing and visual style are left out on purpose. Nothing in the code was changed. Companions: `MESSAGE_FORMATTING.md` (the text marks), `MESSAGE_OPTIONS.md` (the menu), `CHAT_PROTOCOL.md` (events).

Paths are from `connectum/`. `cc/` = `chat-app/features/connectumChat/`, `be/` = `connectum-backend/src/`. Every claim has a `file:line`. Where the web does **not** do something a chat app might be expected to do, this document says so in plain words (sections 4 and 7), because the mobile app must not invent it.

## 1. Mentions

**Typed and stored.** A mention is plain text in the message: `@username`. Nothing else is stored (no id, no separate field): `MESSAGE_FORMATTING.md` section "Tagging people (@)". A username is 2 to 24 characters: letters, digits, `.`, `_`, `-`, starting with a letter or digit (`cc/utils/messageFormat.js:138`, server: `be/forms/sd_mentions.erl:8`).

**When `@` is a tag.** It must not be inside a word: it is a tag only at the start of the text or after something that is not a letter, digit, `@`, `.`, `_` or `-` (`cc/utils/messageFormat.js:163`). So `a@b.com` is an email, not a tag. A full stop, dash or underscore that ends the name is not part of the tag (`messageFormat.js:165`, `sd_mentions.erl:30-33`). The tag is stored lower case in the parsed tree: `{t: "mention", user: "ann"}` (`messageFormat.js:166`).

**How a tag is drawn.** The app looks the username up among the people it knows for this conversation (`cc/components/MessageText.jsx:13-18`):

| Case | Shown |
|---|---|
| The person is known | `@` + their display name (their username if they have no name), with the username as the tooltip (`MessageText.jsx:17`) |
| The tagged person is the signed-in person | the same text, marked as "me" (`is-me`, `MessageText.jsx:17`), so it can be drawn differently |
| The person is not known (never in this conversation, removed, a typo) | the text exactly as typed, `@username`, with no special drawing (`MessageText.jsx:16`) |

"Known" means: the other person of a direct chat, the group's members, everyone online, and everyone the person can message (`cc/components/ChatScreen.jsx:137-140`). The comment at `ChatScreen.jsx:143` says "only people of this conversation", but the code also includes online and available people: build it like the code.

**Direct messages.** There is no "@" list in a direct chat (section 2), and the server never sends a notification for a tag in a direct message (`be/people/sd_policy.erl:68-70` handles a direct message without a mention step). A tag typed by hand in a direct message is still drawn like any tag, if the person is known.

**Groups.** The list opens (section 2) and the server notifies (below).

**Encrypted messages.** The tag stays inside the plaintext. The server cannot read an encrypted message (`e2e1:` envelope), so it does **not** notify anyone (`be/forms/sd_mentions.erl:13, 30`); the app draws the tag after it decrypts. `MESSAGE_FORMATTING.md` says the same.

**Replies, forwards, edits.**
- A reply is a new message with its own text and its own tags (`replyTo` is just an id, section 5).
- A forward keeps its text as it is, so a tag inside it is drawn like any other (`cc/chatActions/forward.js:13`).
- An edit replaces the text; tags in the new text are drawn as usual. The edit box has **no** "@" list (section 2). The server does **not** notify when a message is edited: the notification step runs only when a group message is saved (`be/people/sd_policy.erl:72-77`).

**`@all`, `@everyone`, roles.** None exist. A search of the web app and the server finds no such word (`@all`, `@everyone`, `@here`, `@channel`). `@all` would be read as a person named "all".

**What the server does.** For a **new group message** (not encrypted) it reads the tags and, for each tagged person who is a **member of that group**, is **not the sender**, adds one item to their notification feed (`be/forms/sd_mentions.erl:25-28`, `be/forms/sd_feed.erl:361-373`):

| Field | Value |
|---|---|
| title | `<sender's display name> mentioned you` |
| message | `<group>: <the message text, shortened>` |
| category / severity / icon | `messages` / `medium` / `alternate_email` |
| actionType / actionLabel | `open_message` / `Open message` |
| chatId | `room-<group>`; `ref.messageId` = the message id; `chat` = `{scope: "group", group}` |
| key | `mention:<group>:<message id>` (one item per message per person) |

Limits: at most **10** different tags are read per message, each once, in order (`sd_mentions.erl:7, 20`). A tag of a non-member, of the sender, or of an unknown name gives no notification and no error. There is no count of mentions on a conversation and no live event just for a mention: the person gets the feed item (see `WORKSPACE_FEED_MOBILE.md`).

## 2. The "@" list

**Where it exists.** Only in the **message box of a group** (`cc/components/Composer.jsx:558-560`: the people come from `chat.isGroup`, otherwise the list is empty and never opens). Not in a direct chat, not in the rich editor (`Composer.jsx:949`: `!richOpen`; `MESSAGE_FORMATTING.md`: "In the rich editor there is no list yet"), not while recording or when the box is disabled (`Composer.jsx:559`), and **not in the Edit message box** (the edit window is a plain text area with a formatting row and no list: `cc/components/MessageList.jsx:1074-1110`).

**When it opens** (`cc/utils/mentionPicker.js:11-24`): an `@` counts when it is the first character, or follows a space, a line break or one of `( [ { " '`. What follows it up to the caret must have no space and be at most 24 characters. So it opens in the middle of the text, but **not** inside a word (`a@` does nothing). It follows the caret, not the end of the text.

**Where the names come from.** The people of the group already loaded in the chat (`chat.members`), with their display names and avatars (`Composer.jsx:558`, `cc/ConnectumChatScreen.jsx:1343-1355`). No request is made while typing. Yourself is never listed (`Composer.jsx:560`). A member that is only a username shows that username as the name (`Composer.jsx:558`).

**Filtering and order** (`mentionPicker.js:28-47`), case-insensitive, no accent folding:
1. nothing typed yet: everyone, sorted by name;
2. rank 0: the username or the whole name **starts with** what was typed;
3. rank 1: any **word** of the name starts with it;
4. rank 2: the username or name **contains** it;
5. within a rank, by name (or username when there is no name), alphabetical.
It shows at most **6** rows (`mentionPicker.js:5`), each person once.

**What a row shows** (`cc/components/MentionMenu.jsx:12-19`): the avatar (their picture, or the first two letters of the name), the **display name** and `@username`. No role, no online status.

**Keys and touch** (`Composer.jsx:573-578`, `MentionMenu.jsx:13-15`): Arrow down / up move (and wrap around); **Enter** (not Shift+Enter, not while an input method is composing) or **Tab** chooses the highlighted row; **Esc** closes only the list; a click or tap on a row chooses it and keeps the typing focus; moving the pointer over a row highlights it. The list closes by itself when what is typed stops being a tag (a space, the caret moves away) or nobody matches: **no row, no list, no "no results" text** (`Composer.jsx:561`).

**What is inserted** (`mentionPicker.js:51-56`): the typed `@query` is replaced by `@username` (the real username, lower case as stored) **plus one space**, unless a space already follows; the caret goes after that space. The display name is not inserted.

**Backspace.** There is no special behaviour: a mention is ordinary text, so Backspace removes one character at a time (no search of `Backspace` in `Composer.jsx` handles tags). Backspacing into the name reopens the list.

## 3. Forwarded messages

**In the data.** A forwarded text is an ordinary message whose text **starts with** a fixed line (`cc/chatActions/forward.js:13`):
```
↪ [Forwarded by <forwarder's name>]: <the text>
↪ [Forwarded by <forwarder's name> • from <original author>]: <the text>
```
There is no flag and no quote on the server: a forward is an ordinary new message (`MOBILE_OPEN_QUESTIONS.md`, "Message options", item 3). The second form is used only when the original author is someone else than the forwarder. The app reads the line back with `^↪\s*\[Forwarded(?:\s+by\s+([^•\]]+))?(?:\s*•\s*from\s+([^\]]+))?\]:\s*([\s\S]*)$` (case-insensitive) into `forwarded`, `forwardedBy` (the forwarder, or the sender when the name is missing), `originalFrom` (or `null`) and the text without the line (`cc/utils/chatMessages.js:11-25`). The same happens for live messages and for history (`chatEvents/messages.js:16, 130, 246, 372`; `chatEvents/history.js:18, 90`).

**What is shown.** A banner above the message: **`Forwarded by <forwarder>`** (`cc/components/MessageList.jsx:564-573`). **The original author (`originalFrom`) is parsed and kept but not shown anywhere** (no use of `originalFrom` in any component): the web shows only who forwarded. There is no original time or conversation, and no "no access" name rule for text. Match this, or decide to show more (open question 1).

**What can be forwarded.**
- **Text:** the text, with an earlier forward line removed first (`forward.js:9-11`), so a forward of a forward shows one banner: **"forwarded content can be forwarded again"**, and the original author is kept when known (`forward.js:12`).
- **Attachments:** the file, picture, video or audio keeps its kind, name, size and address (`forward.js:17-30`); the wire text is the forward line followed by the attachment tag (`cc/utils/chatMessages.js:32-33` reads the tag; the forward line is added by `forward.js:13`, with the file name as the text, `forward.js:11`). A message with no text uses the file name or title as its text (`forward.js:11`).
- **Replies:** the quote is not carried; only the text is forwarded.
- **Several messages at once:** not supported; one message is forwarded to one or more **conversations** at once (`forward.js:15-92`; toast `Message forwarded to N recipient(s)`, `forward.js:94-96`).
- **Forms (cards):** sent with the server call `forms.forward {id, chats}` to people and groups only, never the general room or a host channel (`cc/ConnectumChatScreen.jsx:800-823`). Texts: `This form can't be forwarded yet.`, `Forms can be forwarded to people and groups, not to the general room or host channels.`, `Form forwarded to N conversation(s).`, and `N person/people in it/them can't see it because they don't have access to this form.` (people without access to the form are told nothing in the thread; the sender is told in the toast).
- **Encrypted chats:** the forward line is part of the text that is encrypted, like any text; the app reads it after decrypting. Forwarding a message you could not decrypt has nothing to forward.

## 4. Every other message element

| Element | What is shown and when | Data |
|---|---|---|
| **Sender name** | In a conversation with others, above the first bubble of a message that is not yours: the name, plus the person's **role** when known (`MessageList.jsx:576-580`). Hidden when `grouped` is true, **but nothing in the web ever sets `grouped`** (no assignment in `cc/`): in practice every incoming message shows its sender. | `from` |
| **Avatar** | Beside every incoming message (`MessageList.jsx:547-557`): the person's picture, or two letters; the assistant (no sender) shows an orb. | profile `avatar` |
| **Reply** | A quote block above the text: the quoted author and the quoted text as plain text (`MessageList.jsx:600-603`). Tapping it scrolls to the message and highlights it for about 1.6 s (`:589-596`); only when the id is known. If the original is not loaded, the block shows the author **`Replied message`** and the text **`Message #<id>`** (`:526-531`). If it was deleted, it is gone from the list (see "Deleted"), so the same fallback shows. | `replyTo` (id, or `null`) |
| **Edited** | The text **` • edited`** after the time, when `editedTs` is set (`MessageList.jsx:846-849`). Edits are for your own plain text messages only; a failed edit says `Cannot edit: this message was deleted.` and other reasons (`chatEvents/edits.js:78-85`). | `editedTs` (ms or `null`) |
| **Deleted** | **Not shown at all.** History drops messages with `deleted: true` (`chatEvents/history.js:76`) and a `deleted` event removes the message from the list (`chatEvents/edits.js:31-41`). There is no "message deleted" placeholder. Toast after you delete: `Message deleted` (`ConnectumChatScreen.jsx:773`). | `deleted`, event `deleted` / `dm_deleted` / `group_deleted` |
| **Pinned** | A bar under the chat header: `Pinned by <You or the person's name>` and the first words of the newest pin, `Encrypted message` when it cannot be read, `Attachment` or `Message` when there is no text; with several, a count that opens the list (`cc/components/PinnedBar.jsx:6-40`). A pin icon (`Pinned`) also marks the message itself (`MessageList.jsx:852`). Jumping to an old pin that is not loaded says `That message is older than what this chat shows. Scroll up to find it.` (`PinnedBar.jsx:30`). | event `pins_changed`; `msg.pins {conv}` |
| **Saved** | A bookmark icon (`Saved`) on the message (`MessageList.jsx:853`). | event `saved_changed` |
| **Reactions** | A row under the bubble: one pill per emoji with its **count**; your own are marked (`MessageList.jsx:860-874`). The list of who reacted is **not shown** (only counts). Tapping a pill toggles your reaction. | `reactions: [{user, emoji}]`, folded by emoji (`chatEvents/history.js:79-90`) |
| **System messages** | A centred line with an info icon, and an optional action button (`MessageList.jsx:495-508`). Only **group** system lines are put in the thread (`chatEvents/messages.js:473-483`): **`<name> was added to the group`** (`be/chat/chat_groups.erl:160`) and `<x> added <y> to the group`. The room-wide notices `<name> has joined`, `<name> has left`, `<name> has disconnected` (`be/chat/chat_room.erl:244, 271, 478`) are **not shown**: the app only refreshes its online list (`chatEvents/connection.js:65-70`). Other texts (renamed, created) are not sent by the server as thread lines. | event `group_system {group, text}` |
| **Form / card** | A card with a title, a status pill (`actionStatus`, for example `Submission #37`, `Submitted`, `Waiting for approval`), the field lines (`details`), and an **Enlarge** button for forms, submissions and messages from another system (`MessageList.jsx:606-620`, `enlargeForm.test.mjs`). A card has no "More reactions" button and no "Copy link" (PR #670). | history item with `kind: "form"`, drawn as a card (`chatEvents/history.js:80`) |
| **Attachments** | By kind: file (name, size), image, video, audio (`MessageList.jsx:687-781`). The wire text carries `[ATTACHMENT:{"kind","name","size","url","type"}]` (`cc/utils/chatMessages.js:32-45`; `MOBILE_OPEN_QUESTIONS.md`, "Attachments"). Size is written `<n.n> MB` above 1,048,576 bytes, else `<n> KB`. Encrypted ones show `🔒 Decrypting attachment…` and `🔒 This attachment can't be decrypted on this device.` (`MessageList.jsx:346-347`). | text tag; `e2e` block |
| **Links and previews** | A link card under the message with the page title, description and picture, when the server found them (`MessageList.jsx:796-820`). | `previewUrl`, `previewTitle`, `previewDescription`, `previewImage` (`""` when none); live events `link_preview` / `dm_link_preview` / `group_link_preview` |
| **Text formatting** | See `MESSAGE_FORMATTING.md`. Difference to note: a **mention** is drawn as the person's name only when the person is known (section 1). | text |
| **Date separators** | **None.** The message list has no day headings (no code in `MessageList.jsx` or its helpers draws one). Each message shows its time only. | `ts` |
| **Unread divider** | **None** in the message list. Unread is shown as a count on the conversation row, and a person can **Mark as unread** (menu `U`, `MessageList.jsx:961`). | |
| **Ticks** | Only on your own messages, after the time: `sending` (a dashed circle, tooltip `Sending...`), `failed` (a circle with `!`, `Failed to deliver`), `sent` (`Sent`), `delivered` (`Delivered`), `read` / `seen` (`Read`, aria label `Read receipt`) (`MessageList.jsx:165-215, 854`). A message that never left shows the red text `Not sent` (`:855`). | `ticks` / `status` / `read`; receipt event `receipt {conversation, by, kind: delivered \| read, upTo}` (`CHAT_PROTOCOL.md`) |
| **Encryption indicator** | A badge in the conversation header (`cc/components/E2EBadge.jsx:28`: a closed lock when on, an open lock when off, a warning shield when a device changed) that opens a window titled `End-to-end encryption`. There is no lock on each message. A message that cannot be opened shows `Encrypted message` in lists (`PinnedBar.jsx:10`) and cannot be edited (`MessageList.jsx:449`). | `e2e: true` on the item |
| **Grouping of consecutive messages** | Not implemented (see Sender name). | |
| **Selection mode** | **None** (one message at a time). | |
| **Menu on a message** | Hover bar on a computer: four quick reactions (👍 ❤️ 😂 😮), "More reactions", Edit (your own text), `⋯` (`cc/components/MessageActions.jsx`). Right-click on a computer or a **long press of 500 ms** with a finger opens the menu (`MessageList.jsx:453-468`). Items, in order: **Reply with quote** (Q), **Forward** (F), **Copy text** (C, only when there is text), **Copy link** (L), **Edit** (E, your own text), then **Save this message / Remove from saved** (S), **Pin for everyone / Unpin** (P), **Mark as unread** (U, not yours), then **Delete** (⌫, yours) (`MessageList.jsx:945-964`). Cards: no "More reactions" and no "Copy link". See `MESSAGE_OPTIONS.md`. | |
| **Time** | The time of day only, in the device's language and 12/24-hour setting (`cc/utils/chatMessages.js:6-10`). The full date and time is not shown on a message (a hover title is not used). | `ts` (ms) |

## 5. Data

A message in `history` (`be/http/chat_web_send.erl:229-241`; `CHAT_PROTOCOL.md`, "Message object shape"):

```json
{ "id": 123, "ts": 1790071256909, "from": "alice", "text": "hello @bob", "kind": "chat",
  "private": false, "reactions": [{"user": "bob", "emoji": "👍"}], "deleted": false,
  "editedTs": null, "replyTo": null, "e2e": true,
  "previewUrl": "", "previewTitle": "", "previewDescription": "", "previewImage": "" }
```

| Field | Type | Optional | Notes |
|---|---|---|---|
| `id` | number | no | ordering, `replyTo` target, notification `ref.messageId` |
| `ts` | number (ms) | no | |
| `from` | string | no | username |
| `text` | string | no | the whole text; for an encrypted message the `e2e1:` envelope |
| `kind` | string | no | `chat`, `form`, ... |
| `private` | bool | no | |
| `reactions` | array of `{user, emoji}` | no (may be `[]`) | one entry per person per emoji |
| `deleted` | bool | no | the web hides `true` |
| `editedTs` | number or `null` | no | |
| `replyTo` | number or `null` | no | |
| `e2e` | `true` | yes (absent when plain) | `be/http/chat_web_send.erl:260` |
| `preview*` | strings | no (`""` when none) | `chat_web_send.erl:330-333` |
| form fields | | only for `kind: "form"` | `form_fields` |

Live events: `private`, `chat`, `group_message`, `host_message` (`id`, `ts`, `from`, `text`, `replyTo`), `own_message_id`, `edited` / `dm_edited` / `group_edited` (`messageId`, `text`, `editedTs`), `deleted*` (`messageId`), `reaction*` (`messageId`, `reactions`), `*_link_preview`, `group_system` (`group`, `text`), `receipt`, `pins_changed`, `saved_changed` (`CHAT_PROTOCOL.md`; `be/http/chat_web.erl:466-518`).

**Plain versus inside the envelope.** For an encrypted message the server sees and sends in the clear: `id`, `ts`, `from`, `kind`, `reactions`, `deleted`, `editedTs`, `replyTo`, `e2e`. **Inside the envelope (readable only after decrypting):** the text, so the **mentions, the forward line, the attachment tag and any link** are all inside it. Previews are not fetched for an encrypted message, because the server cannot read the link. A notification item for an encrypted message carries the whole envelope (never shortened) and `e2e: true` (`be/forms/sd_feed.erl:344-346, 383-388`).

## 6. Edge cases and limits

- **Mentions per message:** the server reads 10 (`sd_mentions.erl:7`). The app draws every valid tag it finds; there is no limit in the drawing.
- **Username length:** 2 to 24 characters; a tag shorter than 2 is text (`messageFormat.js:166`).
- **Very long messages:** the tag rule has no length limit; the "@" list only looks at the 25 characters before the caret (`mentionPicker.js:4, 14`). The message itself is limited to **2,000 characters** by the server (`be/chat.hrl:6`; the answer is `Message too long (max 2000 chars)`, `be/http/chat_web.erl:651-653`), so a tag can never be far into an oversized text.
- **Right-to-left text and emoji:** nothing in the tag or list code treats them specially. A tag is ASCII letters, digits and `. _ -` only, so a name in another script cannot be a tag (`@` followed by such letters is plain text); display names in any script are shown in the list and in the drawn tag. Emoji-only messages are drawn larger (`MessageList.jsx:510`); no tag rule depends on them.
- **Tagging a person who is not in the conversation:** the web cannot offer them (the list shows members only). If it is typed by hand, in a group the tag is drawn as plain `@username` when the person is not known, as a name when they are known to the app (for example online), and the server gives **no** notification because they are not a member (`sd_mentions.erl:25-28`).
- **Case:** `@Ann` and `@ann` are the same person (lower case everywhere).
- **A person who is removed or renamed later:** the old message keeps the old username; it is drawn as a name only while the username is known.

## 7. What mobile must match, and what may differ

**Must match (the data and the rules):**
1. A mention is `@username` plain text, with the username rules and the "not inside a word" rule (section 1). Insert `@username` + a space, using the real username.
2. Notifications for mentions are the server's (groups, not encrypted, members only). Do not send your own; do not expect one for a direct message, an edit or an encrypted message.
3. Draw a tag as `@<display name>` for a known person (and mark your own), and as typed for an unknown one. There is no `@all`.
4. The "@" list: groups only; opens after the start, a space or an opening bracket; filter and rank as in section 2; at most 6; yourself excluded; no list when nothing matches.
5. A forward is the line `↪ [Forwarded by <name> • from <author>]: <text>` at the start of the text; parse it back the same way, and strip an earlier line before forwarding again. Forms are forwarded with `forms.forward`, not as text.
6. Deleted messages are removed, not shown as placeholders; edited messages show ` • edited`.
7. `replyTo` is an id; show a fallback (`Replied message` / `Message #<id>`) when the original is not loaded.
8. Ticks have five states (`sending`, `failed`, `sent`, `delivered`, `read`) and only on your own messages; the receipt event carries `upTo`.
9. Encrypted messages: everything (mentions, forward line, attachment tag) is inside the envelope; show `Encrypted message` where text cannot be read.

**May differ (the web does not do it, or it is device style):**
10. Day separators and an unread divider: the web has none; mobile may add them.
11. Grouping of consecutive messages from one sender: not done by the web; mobile may group.
12. Selection mode, several-message forward: not in the web.
13. Showing the original author on a forward: the data has it, the web does not show it.
14. Showing who reacted: the data has it, the web shows counts only.
15. How the list opens (a popup above the box, or a sheet), keys, hover and long-press gestures, and the look of every element.

## Open questions

1. **Forwarded messages: show the original author?** `originalFrom` is parsed but not displayed. Should mobile show "from <author>" (the web would then follow), or match the web (forwarder only)?
2. **The general room:** does it have members for the "@" list? `room-general` is a group in the chat list (`isGroup: true`, `cc/data/sampleData.js:42-46`), so the list is switched on there, but it offers only the people in `chat.members`; whether the general room gets a members list was not verified. Until decided, mobile should offer "@" only where the group's members are known.
3. **Days and unread:** the web has no day separators or unread divider. Please confirm mobile should add them as an improvement.
4. **Notification for a tag in the general room:** the server step runs for group messages (`sd_policy:after_group`); whether the general room goes through it was not checked.
5. **Dropping the "everyone online/available" lookup:** `personOf` draws a tag for any known person, not only conversation members (section 1). The comment says members only. Which rule should mobile follow?
