# Connectum web app: screens and features (for the Flutter build)

Source of truth is the code in `connectum/src`. The web app is ONE page (no router): `App.jsx` renders only `ConnectumChatScreen`, which shows either the auth screen or the chat shell, and opens everything else as modals (`setModal("<key>")`). WS events and `/sd` actions are named only; the protocol is in another doc.

"In prototype?" = does the user's React prototype have it. The prototype has ONLY: splash, onboarding, auth, OTP, enterprises, chats, AI agents, conversation with forms and summary, submissions, profile, notifications. Y = yes, P = partly, N = missing in prototype.

## 1. Pre-login (ConnectumAuthScreen, JoinWizard)
| Screen / feature | Shows and actions | REST / WS used | In prototype? |
|---|---|---|---|
| Splash | None in the web app (only a brief "booting" state while a saved identity is re-checked via `me`) | `GET me` | Y (prototype extra) |
| Sign in tab | Email, then 6-digit code; optional "sign in with a password" if set; "Change email"; resend with 30 s cooldown; trusted device (15 days) skips the code | `login/start`, `login/verify`, `login/password` | Y (email + OTP) P (password sign-in N) |
| Set up enterprise tab | Enterprise name, owner name, email, mobile -> code -> enterprise created, you become admin; "created" screen shows the enterprise Connectum ID/QR | `setup/start`, `setup/verify` | N |
| Register tab | Username, email, mobile (PhoneField), country/city/state (pickers), "more details" -> code -> welcome | `register/start`, `register/verify`, `geo/countries`, `geo/cities` | P |
| Enterprise list (after auth) | Your enterprises with status (pending / rejected / inactive); tap to enter; add/find another | `me`, `enter` | Y |
| Find enterprise | Search by name or Connectum ID | `enterprises?q=`, `enterprise/<id>` | P |
| JoinWizard | Pick who you are (employee / associate via affiliate / individual associate), employee code, affiliate+branch or category, details, review, send; may end "waiting for approval" | `join/check`, `join` | N |
| Set/remove own password | In auth screen and account settings, confirmed by an email code | `account/password/start`, `/set`, `/remove` | N |
| 2FA (TOTP / email, recovery codes) | API exists in `connectumApi` (`2fa/totp`, `2fa/email/request`, disable, regenerate recovery); UNCLEAR: which UI calls it (not found in auth screen) | `2fa/*` | N |
| Saved servers | List of server addresses on this device; switching reloads the app against that server | none (device storage) | N |
| Sign out / switch enterprise | Account menu (3 dots in sidebar card): Switch enterprise (keeps account session) or Sign out | `logout`; WS `session_expired`, `session_replaced`, `connection_superseded` | P |

## 2. Main shell (ConnectumChatScreen, Sidebar, TopBar, MyWorkspace)
| Screen / feature | Shows and actions | Uses | In prototype? |
|---|---|---|---|
| My Workspace (home) | Greeting/workspace chat, left chats slider, right priority-notifications slider (red/yellow/grey/green counts, mark resolved), smart prompts, mini chat | `feed.list`, `feed.read/resolve/dismiss/clear`; WS `feed_item`, `feed_changed`, `feed_removed` | P |
| Sidebar (chat list) | Own profile card (presence/status), search, filters (All / Direct and Teams), archived section, "+ New Group / Chat", unread badges, mute icon, host seal | WS `users`, `groups`, `conversations`, `status_change` | Y |
| Top bar tabs | Messages, AI, Structures, Apps, Studio, Connect (QR), Add (group only), Approvals (badge), Org (admin console), Account, Notifications bell, Chats toggle | see below | P |
| Chat row options | Archive/Unarchive, Mute/Unmute, Mark read/unread, Delete conversation (local prefs in `chatPrefs`/`chatOrganiser`) | WS `sendRead`, `sendList` | P |
| Connection state | Banner/button "Click to retry backend connection"; typing, presence | WS `status_change`, `typing`, `typing_dm`, `group_typing` | N |
| Plugin tabs (Apps, Studio) | Shown only when plugin enabled; Apps runs published pages in a sandboxed frame | `page.*`, `AppsModal`, `CodeStudioModal` | N |

## 3. Conversation (ChatScreen, MessageList, Composer, ConversationHeader)
| Feature | Actions | Uses | In prototype? |
|---|---|---|---|
| Chat kinds | Direct (DM), group, global, host (department/role host chat), My Workspace | WS `private`, `group_message`, `chat`, `host_message`, `history` | P |
| Message list | Text, files, images, voice notes, GIF/stickers, link previews, system messages, date grouping, delivered/read marks | WS `dm_ack`, `group_msg_ack`, `host_ack`, `dm_read`, `file`, `*_link_preview`, `group_system` | P |
| Message actions menu | Reply, Edit (own), Copy, React (quick-react popup), Forward, Star, Delete | WS `reaction`, `dm_reaction`, `group_reaction`, `edited`, `dm_edited`, `group_edited`, `deleted`, `dm_deleted`, `edit_denied`, `delete_denied`; `forms.forward` | N |
| Composer | Text, emoji/GIF/sticker, attach (document/photo/media), record voice note (mic), send, cancel reply, typing indicator; `#command` menu with as-you-type args; options bar (buttons for forms, downloads, uploads, links, pages) ; shortcuts "Your submissions" and "What others recorded about you" | `/cmds`, `/cmdcomplete`, `options.list`, `options.categories`, `option.run`; HTTP `POST /upload`; WS `cmd_catalog`, `cmd_help`, `options_changed` | P |
| Header buttons | Thread summary, "Summarise this chat with AI", Members (groups), Back to workspace | `care.summary`, `care.names`, `care.done`; chat summary modal (AI reads chat via `read_chat` tool) | P (summary Y) |
| Forms in chat (SmartStructureModal, formEngine) | Admin-defined forms: field types text, number, wholenumber, date, time, email, mobile, url, selection, list (lookup), file, location (capture), barcode (camera scan), slot (booking time), payment, query/api/datasource-filled, autogenerate, conditional show/required rules, grid (repeating rows), save draft/submit, edit own submission | `avail.slots`, `datasource.run`, `submission.*`; WS `form_message`, `form_message_updated`, `submission`, `submissions_changed`, `tstructs_changed` | P (basic forms Y; grids, barcode, slot, location, payment, rules N) |
| Form approvals flow | Submitted form goes to approver; approve/decline/return with comment; requester notified | `req.list`, `req.respond`; WS `pending`, `submission_approved`, `submission_rejected` | N |
| Care summary card | Private card in the thread (only requester sees), ask follow-ups, Dismiss | `care.summary` | Y |
| Inline AI card | AI assistant inside the thread, "Open full view" goes to AI tab | AI services | N |
| E2E badge | Shows end-to-end encryption state (`E2EBadge`, `e2e/`); UNCLEAR: exact scope/which chats are E2E (see `docs/E2E_ENCRYPTION.md`) | WS (encrypted payloads) | N |

## 4. AI view (AssistantView, AiPromptBar, AiHistoryPanel)
| Feature | Actions | Uses | In prototype? |
|---|---|---|---|
| AI chat | Ask about work/people/reports/slides; quote a message; edit/delete own prompts; stop using attached chat focus; thinking indicator; rich output (markdown, charts, callouts, code copy) | `assistant.relay`, `ai.agents`, `ai.models`, `ai.enterprise.*`; WS `ai_agents_changed` | Y (AI agents) |
| History | List, pin, rename, delete, open saved conversations; New conversation | `ai.conv.list/get/save/pin/rename/delete` | N |
| Reports panel | Data Bins and reports, report cards in chat with downloads | DatabinReports (`api.js`) | N |
| AI settings shortcut | Admin only, opens Admin console > AI agents | `admin.ai.*` | N |

## 5. Modals reachable from chat and nav (all keys in `setModal`)
| Modal (key) | What it does | Uses | In prototype? |
|---|---|---|---|
| Profile (`profile`) | View/edit own profile, avatar set/remove, status, own connect code | `profile.get/update`; WS `sendSetAvatar`, `sendRemoveAvatar`, `sendSetStatus`, `profile` | Y |
| User profile view (`user_profile`) | Another person's card, start chat | `sendGetProfile` | P |
| Account Center (`user_settings`) | Tabs Appearance (theme light/dark/system, glass strength), Chat colours (global and per chat), Connections, Account (sign out); toggles vibration, soft click, notification sound | local prefs | N |
| About me (`about_me`) | Records others made about me (payslip, certificate), with files | `records.about_me` | N |
| Submissions (`submissions`) | My submissions, filter, open, edit/delete own | `submissions.list/delete` | Y |
| Record history (`record_history`) | One record in full + history timeline (made, edited, sent, approved, declined, returned) | `submission.get`, `submission.history` | N |
| Approvals (`approvals`) | Requests waiting for me; search; accept/reject/ignore; "view full data" | `req.list`, `req.respond` | N |
| Notifications (bell, `NotificationsModal`; modal key UNCLEAR) | Priority feed; read, resolve, dismiss, clear; sound | `feed.*`, `notifications.read`; WS `feed_item` | Y |
| Inbox (`inbox`) | Unread/incoming list | `people.cards` etc.; UNCLEAR: exact contents | N |
| Find people (`find_people`) | Search users, start chat | `users.search` | N |
| Online users (`online_users`) | Who is online | WS `users` | N |
| Groups directory (`groups_directory`) | Browse/join groups | WS `groups`, `group_invite`, `group_invite_pending` | N |
| New group (`new_group`) | Create group with members | WS `sendCreateGroup`, `sendAddMember`; `group_created` | N |
| Members (`members`) | Group members, add, leave | WS `sendAddMember`, `sendLeaveGroup`, `left_group`, `added_to_group`, `group_deleted` | N |
| Associates (`associates`) | Contacts: invite, accept/reject/ignore, handover | `assoc.list/invite/handover`; `#associates`, `#accept`, `#reject`, `#connect`, `#disconnect`; WS `associate`, `handover` | N |
| Connect code (`connect_code`) | My QR, enterprise QR (per-branch QR), scan or type 8-char code, rotate code, share | `connect.my`, `connect.rotate`, `connect.scan`; camera | N |
| Cards (`cards`) | Home cards/sections for the user (admin-defined); dismiss | `cards.list/dismiss`, `sections.list/save/delete` | N |
| Forward (`forward`) | Forward a message/form to chat or person | `forms.forward` | N |
| Commands help (`commands_help`) / Custom commands | `#command` catalogue; create own commands | `cmd.list/save/delete` | N |
| Tasks (`tasks`) | Create task for self/other, status open/in progress/done/cancel, reassign | `task.create/list/update/send` | N |
| Broadcast (`broadcast`) | Announcement to branches/departments/designations, preview, history (permission `broadcast`) | `broadcast.list/preview/send` | N |
| Employee invite (`employee_invite`) | Invite employee by email/code (permission-based) | `users.invite`, `permissions.mine`, `users.codeentry` | N |
| Affiliates (`affiliates`) | Register/lookup affiliate organisations | `affiliate.list/register` | N |
| Applications (`applications`) / Axpert (`axpert`) | List connected apps; connect/disconnect Axpert (own credentials), request access, menu, open in popup/frame | `applications.list`, `axpert.*` | N |
| Links (`links`) | Named external links; open in window or frame, params filled with my details | `link.list/open/frame`; `links_changed` | N |
| Apps (`apps`), Code Studio (`code_studio`) | Published pages in sandbox; build apps (plugin) | `page.*` | N |
| Smart View (`smart_view`) | `#view`: table of a structure/data source/API: search, filter, sort, group, chart, save view, download; inbox of waiting items | `datasource.run` etc. | N |
| Structures (`tstruct_user`, `smart_structure`) | Embedded structure studio (MemoryRouter, no URL change); fill forms | `tstruct.user.list` | N |
| Meeting notes (`meeting_notes`) | Notes, post to chat | UNCLEAR: endpoints (component not read) | N |
| Chat summary (`chat_summary`) | AI summary of open chat from a start date | AI `read_chat` | P |
| Setup wizard (`setup_wizard`) | Admin: basic details, branches, departments, designations, employees, affiliates, categories, interaction rules; skippable, resumes | `admin.setup.*` | N |
| Data Bin reports (`DatabinReportsModal`) | Open via event; reports from Data Bins | DatabinReports api | N |

## 6. Admin console (`admin_console`, AdminConsoleModal). Opened by admins or holders of `users.view`, `invite.employees`, `options.manage`
| Tab | Does | In prototype? |
|---|---|---|
| Org setup (wizard), Org profile | Org details, branches, departments, designations, affiliates, categories; `admin.cfg.*`, `admin.org.*`; bulk upload from Excel/CSV | N |
| Structures (builder), Options, Packs, Variables | Make forms; buttons above chat and who sees them; ready-made packs; global variables | N |
| Onboarding | Rules for employee sign-up | N |
| People: Users (Employees), Invite user, Import employees, Roles, Permissions grid, Administrators (incl. handover), Memberships, Working hours | Manage everyone; `admin.user.*`, `admin.employees.*`, `admin.perm*`, `admin.admins.*`, `avail.*` | N |
| Access rules, Data access | Who may talk to whom; per-person option/view/edit limits (`admin.interaction.*`, `admin.access.*`) | N |
| Connections: Associated datastore (Axpert), API plugins, Links, URL configuration, Connectum API's (keys shown once), Postback | `admin.appconn.*`, `admin.api.*`, `admin.link.*`, `admin.url.*`, `admin.pubkey.*` | N |
| AI agents | Providers/keys (key never shown again), test; `admin.ai.*` | N |
| Plugins, Studio, Published pages | Switch plugins on/off with usage; built only when plugin installed | N |
| Shopify | Connect store; Shop view in chat (`admin.shopify.*`, `shopify.*`) | N |
| Unlock | Strict mode asks an emailed one-time code to unlock the console (`admin.unlock*`) | N |
| Allowance, Applications, Affiliates tabs | Present in `ADMIN_ONLY_TABS`; UNCLEAR: whether visible in nav (a hidden-tabs list exists in the modal) | N |

## 7. Legacy / not mounted in the SPA
`src/features/exportChat`, `promptTemplates`, `providerSwitcher`, `systemPromptEditor`, `databin` (wizard), `admin` (AdminDashboardShell, Assignments, Data bins), `composer`, `messageThread` are old per-feature bundles. `ConnectumChatScreen` does not import them (only `smartView` and `databinReports` are imported). UNCLEAR: should the mobile app include chat export (PDF/DOCX/JSON in `services/chatExport.js`), prompt templates, or the AI provider switcher? `chatExport.js` exists but no import from the screen was found.

## Source files used
`src/main.jsx`, `src/app/App.jsx`, `src/features/connectumChat/ConnectumChatScreen.jsx`, `components/ConnectumAuthScreen.jsx`, `JoinWizard.jsx`, `Sidebar.jsx`, `TopBar.jsx`, `AccountMenu.jsx`, `MyWorkspace.jsx`, `ChatOptionsMenu.jsx`, `ConversationHeader.jsx`, `MessageActionMenu.jsx`, `Composer.jsx`, `AssistantView.jsx`, `components/modals/*` (headers), `utils/adminTabs.js`, `utils/formEngine.js`, `services/connectumApi.js`, `services/connectumSocket.js`, `src/features/smartView/*`, `databinReports/*`, `docs/HASH_COMMANDS.md`, `docs/LINKS.md`, `axi-chat-backend/src/chat_cmds.erl`.
