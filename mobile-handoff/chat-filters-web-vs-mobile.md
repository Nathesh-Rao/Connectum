# Home chats filters: web vs mobile

Web paths are under `~/Development/Axi-apps/connectum/` (read only). `WCS` = `chat-app/features/connectumChat/components/WorkspaceChatsSlider.jsx`, `careTitle` = `chat-app/features/connectumChat/utils/careTitle.js`, `recthread` = `connectum-backend/src/forms/sd_recthread.erl`.

## 1. The chips

| | Web |
|---|---|
| Set and labels | `All`, `Direct & Teams`, `Threads` (WCS:295-298). The internal keys are `all`, `direct`, `threads`. A `hosts` key is still handled in the code (WCS:216, 368) but has no chip. |
| Order | All, Direct & Teams, Threads. |
| Threads chip | Shown only when at least one thread conversation exists, archived ones included (WCS:190, 297). |
| Default | `all` (WCS:60). |
| Remembered | **No.** It is plain `useState("all")`; it resets whenever the panel is rebuilt. |
| Count / badge | Only on Threads: the sum of `unread` over every thread conversation (muted and archived included), shown as a badge (WCS:191, 308). No count on All or Direct & Teams. |
| Result count | A grey count chip next to the "ACTIVE CONVERSATIONS" heading (WCS:329). This is not a pill count. |

## 2. Predicates

The list is `allConversations` (WCS:111-161): the chats the socket delivered, plus online users and available users who have no chat yet (those are web-only placeholders). Order is the order the chats arrive in. `/conversations` inserts new ones at index 1 (`chatEvents/history.js:42`), and My Work Space is pinned to the top (`pinWorkspaceGroup`, WCS:223). **There is no sort by time, unread or pin** on the web, and there is no pin feature besides My Work Space.

Per conversation `c`, in this order (WCS:192-221):

1. `room-general` or name "General Broadcast" is **never** listed.
2. `threads` filter: keep only `isSharedThread(c)`.
3. Any other filter: drop `c` if its id is in `hiddenIds` (a record conversation whose structure has `recordThreadInList: false`).
4. Archived: with "archived only" off, archived chats are dropped; My Work Space is exempt.
5. Search (case-insensitive substring) on `c.name`, on the shown title and on `c.preview`. It is ANDed with the filter.
6. `direct`: `!c.isHost && !category.includes("host")`. That is everything that is not a host or AI channel: DMs, groups, team groups, threads. `all`: no further test.

Thread test, `isSharedThread` (careTitle:41-46): take `c.id` (or `c.name`), strip a leading `room-`, then match `^care-[A-Za-z0-9._-]+$` (a person's shared thread) or `^rec-(.+)-(\d+)$` (a record's own conversation). A direct chat id `user-<name>` never matches. Host chats have id `host-<key>`.

Muted: no effect on any filter (a muted icon on the row only). Muted unread still counts in the Threads badge.

## 3. Threads

- A thread is an **ordinary server group**. There are two kinds:
  - `rec-<structure>-<record number>`: one per record of a structure with the flow setting `recordThread` (a ticket, a claim, an order). The server creates it when the record is saved, adds the person who saved it, the `subject` person and everyone in an `involve` field, and posts the form into it as a card (`recthread` header comment; `post/4` at :312). Each status update posts a card too (`status_changed/5` at :301). Members follow the record's fields when it is edited.
  - `care-<username>`: one per person (the care thread). Out of scope for titles here, see the table below.
- Delivery: no special call. They arrive in `/groups`, `conv.list {full:true}` and as live group messages like any group. Mobile already gets them.
- Title: the group name is the identity and never changes. The shown title is from `record.names {}` -> `{names: {"rec-ticket-12": "Ticket #12: printer is down"}, canRename: [...], hidden: [...]}` (`sd_cmds_forms.erl:341`, `recthread:115,133`). Until it is known the web shows the tidied name `Ticket #12` (careTitle:49-53). The web asks for it on connect and when the thread count changes (ConnectumChatScreen:337), and again on `submissions_changed` and `resync` (:351). `canRename` allows the row menu "Rename" (`record.rename {id, name}`).
- Row: title, time, last message preview (a form card gives its text), unread badge, mute icon. There is **no** "Ticket" or "Task" marker on the web. Nothing else is shown.
- Open: the normal conversation view of a group (message list with form cards, composer). Not read only.
- Disappears: when the record is deleted (`on_deleted`, :76: everyone leaves and the group is removed), when the person leaves or is removed from it, or when it is archived. Closing a ticket does not remove it.
- `hidden`: a structure with `recordThreadInList: false` keeps its record conversations out of All and Direct & Teams. They show under Threads only.

## 4. Empty states and texts (WCS:360-446)

| Situation | Title | Text | Buttons |
|---|---|---|---|
| Archived view | No archived conversations | You have no archived conversations. ... | Back to Active Conversations |
| Search with no hit | No matching conversations | No conversations match "q". Try checking your spelling or clear the search. | Clear Search |
| Direct & Teams | No direct conversations | You don't have any direct messages or team conversations open. | New Conversation, View all conversations |
| Threads, All | No conversations found | Start a new chat to begin collaborating with your team. | New Conversation (+ View all conversations when not All) |

The web has no thread-specific empty text; Threads falls through to the default.

## 5. Web vs mobile (before this change)

| Topic | Web | Mobile before | Action |
|---|---|---|---|
| Chips | All, Direct & Teams, Threads (when any) | All, Direct & Teams | Added Threads, same condition, now an `AppPillBar` |
| Threads | filter by `care-` / `rec-` group name | none | Added (`ChatFilter`) |
| Pill count | Threads only, sum of unread | All had a count of unread chats | All count removed; Threads sum added |
| Remember choice | no | no (resets) | Unchanged: not remembered |
| `hidden` record threads | out of All and Direct, in Threads | not known | `record.names` read, stored, applied |
| Thread titles | `record.names`, else tidied name | raw `rec-ticket-12` | Stored per conversation, tidy fallback |
| Direct & Teams | everything except hosts (and never room-general) | everything except global and host | Same result, now in `ChatFilter` |
| General Broadcast | never listed | listed in All once it has a message | **Kept** (deliberate in the app), see BE/product question |
| Order | arrival order, My Work Space first | pinned first, then newest | Kept (the server has pin; the web does not use it) |
| Search | text in the list's title/preview, ANDed with the filter | global search ignored the filter | Conversation hits now respect the filter |
| My Work Space row | listed in All and Direct, not in Threads | hidden in Direct & Teams | Now shown in All and Direct & Teams, hidden in Threads |
| Empty per filter | Direct & Threads have text and "View all" | blank list under the tab | Added with our wording |
| Threads chip when the last thread goes while selected | stays on a missing chip | n/a | Falls back to All |
| Ticket/Task marker | none | n/a | Not added (the web has none) |
| Rename a record thread (`record.rename`) | row menu, owner only | none | Not done, see report |
| `care-` titles | `care.names` + `org.name` | raw | Tidied only; names not fetched, see report |
