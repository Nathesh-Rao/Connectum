# Chat message UI audit

Source: `reference/backend-chat-ui/CHAT_MESSAGE_UI_FOR_MOBILE.md` (4 Nov 2026). Status after this change. "built" = done in this task, "verified" = already worked, "not now" = out of scope or needs data the app does not store yet.

| Element | Web | App before | Gap | Action / status |
|---|---|---|---|---|
| Sender name | Above incoming bubble, plus role | Name above first bubble of a run in groups/teams, no role | partial | name verified; role not now (no role cache) |
| Avatar | Beside every incoming message | None in the thread (prototype has none) | partial | not now: prototype is the approved design |
| Reply quote | Author + plain text | Author + text | none | verified |
| Reply fallback | "Replied message" / "Message #id" | "Original message", no author | partial | built: both strings; quote text also drawn through the mention parser, forward line stripped |
| Tap quote scrolls + highlight 1.6 s | Yes, only when id known | Not tappable | missing | built: scrolls (pages older messages in until the row is built), bubble flashes 1.6 s |
| Edited " • edited" | After the time | Not shown | missing | built (display only; there is no edit action in the app) |
| Deleted | Removed, no placeholder | "Message deleted" placeholder | partial | built: removed from the thread; a quote of it uses the fallback |
| Pinned bar / pin marker | Bar + icon | Not present | missing | not now: `pins_changed` is not stored or handled |
| Saved marker | Bookmark icon | Not present | missing | not now: `saved_changed` not stored |
| Reactions | Count pills, own marked, tap toggles | Same (`ReactionChips`) | none | verified |
| Group system lines | Only `group_system` | Event only refreshes `/groups`, no line | missing | not now: needs a stored line type |
| Form cards | Card, status, enlarge | `AppFormCard` | none | verified |
| Attachments | file/image/video/audio, size, encrypted placeholders | `AttachmentView` | none | verified |
| Link previews | Card under message | Not present | missing | not now: no preview columns or events |
| Text formatting | `MESSAGE_FORMATTING.md` | Plain text + mentions | partial | not now (separate doc) |
| Mentions drawing | Name for known person, "me" style, as typed if unknown | Username, members only, no names | partial | built: one parser (`mention_text.dart`) + `AppMentionText` in bubble, quote, reply bar |
| "@" list | Groups, rules in section 2 | Not present | missing | built: `MentionPicker` (pure) + `MentionPanel` |
| Forwarded message | Banner "Forwarded by" | Raw line shown | missing | built: `ForwardedText` parser + `ForwardBanner` (adds " • from author"); the chats-list preview and Copy show the text without the forward line (no feed item is drawn from message text) |
| Forward action (sending) | Menu item | Not built | missing | not now: pending; forms use `forms.forward`, also pending |
| Date separators | None | Already present (`DayDivider`) | none | verified |
| Unread divider | None | Already present (`UnreadDivider`) | none | kept (existing); not added by this task |
| Grouping consecutive | Not done | Already runs | none | verified, untouched |
| Ticks | sending/failed/sent/delivered/read, "Not sent" | `MessageStatusMark` + "Not sent. Tap to retry" | none | verified |
| Encryption placeholders | "Encrypted message" / unreadable text | `E2eTexts`, "Decrypting..." | none | verified; mentions and forward line are parsed from the decrypted text |
| Time | Device language, 12/24 h | Always 12 h | partial | built: follows the device 24-hour setting |
| Long press | 500 ms | `onLongPress` (500 ms default) | none | verified |
| Selection mode, several-message forward, who reacted, original time of a forward | Not in web | n/a | n/a | not now |

## Mentions: people the app knows
Known = me, the direct peer (name = conversation title), the group's members (username only: only usernames are stored) and everyone in `PresenceRepository.online` (username only). No "available people" list is cached by the conversation, so it is not used. Until display names are stored for group members, a known tag shows `@username`.

### BE question: display names and avatars of group members and online people
Checked the code (`GroupRepository`, `PresenceRepository`, `Conversation.members`), `websocket-protocol.md`, `group-create.md` and the Postman collection: the app drops nothing. Both sources carry usernames only.
- `/groups` (`list[].members`), `group_created`, `added_to_group`: `members` is an array of username strings. Missing: `name`, `avatar` per member.
- `/list` -> `users`: `list` is an array of username strings. Missing: `name`, `avatar`.
- `profile` events carry `user`, `avatar`, `status` but no display name.
- The web draws names and avatars from `chat.members` (`cc/ConnectumChatScreen.jsx:1343-1355`). Question: which call fills `chat.members` with names and avatars for a group? Is it `users.colleagues` / `assoc.list` (those carry `name` and `avatar`, but only for colleagues or connections, so a member who is neither would have none), or a per-group members call we do not know of? What does the web show for a member it has no name for?
Until answered, nothing in the data layer changes.

## Decisions applied
Forward shows the original author; "@" only where the group's members are loaded; day separators already existed; no new unread divider; tags use conversation people plus online people.
