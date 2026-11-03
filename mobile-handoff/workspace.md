# My Work Space

Source: backend `origin/main` (chat_hosts.erl, chat_web.erl, chat_room.erl), web `ConnectumChatScreen.jsx`, `sampleData.js`, `pinWorkspace.js`. Not verified live (test server unreachable from the dev machine).

## What it is
- **A client-side entity of the web app. The server has no workspace conversation.** `chat_hosts.erl` lists `{"workspace","My work space","workspace"}` as a "preconfigured" host (kind `workspace`, key `workspace`) so `/hosts` returns it, but its own comments say it "never gets routed through here": the web client switches its own view.
- Web id `"workspace"`, `isWorkspace:true`, `isHost:true`. Always pinned first in the list (`pinWorkspaceFirst`), shown as "My Work Space" (renamed from the data name), avatar = the user's own avatar, fallback initials "WS" on `#ff7a59`. Not shown to people in a shared thread who have no workspace.
- Row text "Type '#' for commands, automated tasks & alerts" is a **hard-coded string in web `sampleData.js`** (`preview`), `designation: "Enterprise Workspace & Automation"`. Not from the data. No unread, no time from the server.

## Reading and sending
- `/hostmsg workspace <text>` is NOT used. The web composer for the workspace does `status "sent"`, ticks "read", and sends **nothing** to the server. It then fakes a "Workspace Assistant" reply after 400 ms ("Tip: Type `#`..."). Plain text typed here is therefore local only and lost on reload.
- Server side, `/hostmsg <key> <text>` resolves only *department* hosts (`chat_hosts:resolve_host`); for `workspace` it answers `error "No such host, or it has no one assigned yet: workspace"`. `/history host <key>` is for department hosts only. `host_message` / `host_ack` events are department-host only. The department-host list is empty today (`decode_department_hosts` is a placeholder).
- Per user: yes, entirely local per signed-in user.

## Welcome message
- Built locally: first message `id "ws-msg-1"`, sender "Workspace Assistant", display "Connectum Workspace", bot avatar "WS". Text: `Welcome <name>. This is your personal workspace for direct tasks, enterprise updates, and automation commands. You can type hash commands in the composer below ...`. Rebuilt with the user's name on login. Not stored, not delivered by the server.

## What fills the thread
- **Form submission cards**: rebuilt from `sd submissions.list {offset}` (paged, loop while `hasMore`), filtered to `by == me`. Per card: title `"<form caption> submitted"`, status line `Submission #<id>` (+ approval detail), details from `values` (captions from `tstruct.get` / `tstruct.user.get`), time-sorted among the local messages. That is why the workspace shows "Test Mobile submitted / Submission #25 / Edit". See forms-live.md.
- **Feed / tasks / reminders / cards / notifications**: separate sliders and modals (Workspace notifications slider, `cards.list`, `feed.*`, `#remind <text>` creates a card). They are not messages of the workspace thread.
- **AI**: `@agent text` in the workspace (and "summary") goes to the AI agents (`assistant.relay`, `ai.agents`); the web jumps to the workspace to show the answer. AI hosts (`openai`, `ai_router`, `claude`, `gemini`, kind `llm`) are also "preconfigured hosts" handled client-side and belong to the AI tab on mobile.

## Mobile mapping (decided)
- **Local only.** The workspace is a pinned row above the chat list and a `/workspace` screen. It is not a conversation, so it has no SQLite conversation row, is never archived, never muted, and always sorts first (even with no chats, while loading, offline or in error). It is hidden only while searching. The server's `workspace` host kind (`/hosts`) exists but is never used: `/hostmsg workspace` is refused, `/history host workspace` is always empty.
- **Row:** title "My Work Space", a PINNED tag, the web's exact preview string `Type '#' for commands, automated tasks & alerts`, the prototype's icon tile (accent-tinted, accent icon). No time, no unread.
- **Feed:** the welcome message first (bot avatar "WS", sender "Connectum Workspace", the web's exact text with my name), then my submissions as sent-style cards from `submissions.list` (newest last). Pending, failed and waiting-for-approval states show as on chat cards.
- **Composer:** free text is off, with the hint "Pick a form or type # for commands". The forms button works; a form filled in here is submitted with no `chat`, so no form message is posted anywhere and the submission shows only here and in My Submissions.
- Not built: `#` commands, `@user` shortcuts, the feed/tasks/reminder lists, AI relay. The `#` hint is only text for now.

## H. Web header icons (TopBar.jsx navItems) and the lightning button
Chat bubble = Messages; sparkle (`auto_awesome`) = AI; `tstruct` clipboard-with-gear icon = Structures (create and manage data structures / forms); apps grid = Apps (pages made for you); `code` = Studio; `qr_code_2` = Connect (show my QR / scan); `approvals` shield-style icon = Approvals (badge = waiting count; only for approvers); `admin` icon = Org / Admin console (admins); `account` = Account (profile, theme). Glyph-to-meaning of "shield" vs "clipboard-with-gear": clipboard-with-gear = Structures, shield = Approvals or Org (two custom SVGs; which one looks like a shield not checked visually). The floating orange lightning button: no matching floating `bolt` found in `origin/main`; `bolt` is used for the "Smart Prompts" tab in MyWorkspace (opens Smart Prompts), the default pill icon, and Admin > Options. Probably the Smart Prompts opener in the deployed build; UNVERIFIED.

## Live confirmation
`/hosts` lists `{key:"workspace",name:"My work space",kind:"workspace"}` after the four llm hosts; `/history host workspace` returns an empty list. See live-shapes.md.
