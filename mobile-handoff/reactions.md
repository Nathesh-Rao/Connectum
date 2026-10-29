# Reactions

Source: backend `origin/main` (`chat_web.erl` `/react` handler and the `reaction` / `dm_reaction` / `group_reaction` pushes, `chat_room.erl` `react_global`/`react_dm`, `chat_groups.erl` `react`, `chat_store.erl` `toggle_reaction`, `reactions_json`), `docs/CHAT_PROTOCOL.md`, web `connectumSocket.js` `sendReaction`, `ConnectumChatScreen.jsx` `handleToggleReaction`, `QuickReactPopup.jsx`, `sampleData.js` `quickReactions`, `MessageList.jsx`. The test server was not asked; the shapes below come from code plus the one stored reaction in `live-shapes.md`.

## Command (sent as a plain frame, no `/c` id)
| Conversation | Command |
|---|---|
| Direct | `/react dm <user> <messageId> <emoji>` |
| Group | `/react group <group name> <messageId> <emoji>` (the name may contain spaces: the last two tokens are id and emoji) |
| Global room | `/react global <messageId> <emoji>` |
| Department host (team) | **none**. There is no `host` form: the server ignores the line. Mobile does not offer reactions in teams. |

- The id must be all digits (`with_int`), otherwise the line is silently ignored. The emoji is one token with no space (a multi-code-point emoji such as `❤️` is fine).
- It is a **toggle**: the server adds the `(user, emoji)` pair, or removes it when it is already there. It never answers the sender with an error or an ack: an unknown message id, a bad id or a group the sender is not in is silently dropped. So never queue it, never retry it (a retry would undo it), and render only from the pushed set.
- The command counts toward the 30 commands per 10 s limit.
- `#react`, `#reactdm`, `#reactgroup` are the `#` shortcuts of the same command (`HASH_COMMANDS.md`); `commands.md` lists "react*" among names removed from the web menu, but the `/react` frame itself is handled. Mobile sends `/react` directly.

## Events
| Event | Shape | Sent to |
|---|---|---|
| `reaction` | `{type:"reaction", scope:"global", messageId, reactions:[{user,emoji}]}` | everyone in the global room |
| `dm_reaction` | `{type:"dm_reaction", messageId, reactions:[...], userA, userB}` | both people of the direct conversation, **including the reactor** |
| `group_reaction` | `{type:"group_reaction", group, messageId, reactions:[...]}` | the group members (the reactor included) |

Each event carries the **whole current set** for the message, not a delta. So the UI renders from the event and never predicts. `messageId` is a number. Ids are one sequence across all conversations, so `messageId` alone finds the row.

## Shape in history and in form messages
`reactions` is `[{user, emoji}]` on every history item (`[]` when none), the same array for `kind:"chat"` and `kind:"form"`. Mobile stores it as `reactions_json`. The server keeps `[user, emoji]` pairs with the newest first; the JSON out is objects. A history page replaces the stored set; a delta page carries the message because every reaction stamps its `mod`.

## Rules the server applies
- **Several reactions per user**: yes, one per distinct emoji (`toggle_reaction`: "Slack/Discord-style"). The same emoji twice removes it. Chips group by emoji; a chip is "mine" when my user is among its reactors.
- **Own messages**: no restriction, anyone in the conversation may react to any message including their own.
- **Form messages**: no restriction, a form is a message row with the same `reactions` field. Works.
- **Deleted messages**: the server does **not** check. Mobile does not offer reactions on a deleted message (it shows no body).
- **Encrypted DM or group messages**: the server does **not** check; reactions are plain metadata outside the envelope (the stored live sample has a reaction on an `e2e1:` message). Mobile allows reacting to and shows reactions on them, since a reaction sends no text. The thread stays read-only for text.
- **Membership**: a group reaction from a non-member is dropped. For a DM the server does not check that the id belongs to that conversation; mobile only sends ids of the open conversation.
- **Teams (host)**: not supported (no command, no event). Hidden.

## Web UI (for the design)
- Quick row: `👍 ❤️ 😂 😮 😢 🙏`; a "+" button expands it with `🔥 🎉 👏 💯 🚀 ✨ 🤝 🥰 🤩 👀`. There is no full emoji grid.
- Chips under the bubble: emoji and count, accent style when mine; tapping toggles that emoji.

## Mobile behaviour
- Online only: offline shows "Needs a connection" and sends nothing. A message with a temp id (pending, sending, failed) cannot be reacted to.
- Local state changes only from the pushed set, so a toggle made on the web or by the other person arrives the same way as my own.
- An event for a message not stored is ignored (the update matches no row).
