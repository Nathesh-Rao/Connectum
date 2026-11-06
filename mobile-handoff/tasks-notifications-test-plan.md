# Manual test plan: notifications, To-dos, approvals, tickets

Phone: moto g32, debug build. "Web" = the web app signed in as the other person (or an administrator where it says so). Automated tests already cover the logic (392 tests, `flutter test`); this plan checks what only a phone and a server can show: the system tray, permissions, real timing, real server texts, two devices.

Findings of the audit that change what you should *expect* are named as `G-xx` / `B-xx` (see `tasks-notifications-audit.md`). Where the app does something the product may still change, the expected result says "today".

Legend: ☐ = not run. Mark P (pass), F (fail, write the case ID in the bug), S (skipped, why).

## 0. Test data to prepare (once)

People (all in one organisation, `Org A`; a second organisation `Org B` only for X-01):
| Name | Role / setup |
|---|---|
| **Me** (phone) | employee, signed in on the phone; Ana's colleague; also the approver of the expense form in the approval cases (give Me the approver designation of the 1-step form, Meg stays for step 1 of the 2-step form). |
| **Ana** | employee, web. Assignee of tickets, creator of To-dos for Me. |
| **Meg** | Me's reporting manager (approver for expense/leave forms), web. |
| **Admin** | administrator (can approve sign-ups, act on any ticket, has `broadcast` permission), web. |
| **Sam** | employee with the **Support** designation (the pool), web. |
| **Eve** | has an encrypted-chat device (web or second phone) for the e2e cases. |
| **Rhea** | employee, raises tickets, web. |
| **Newbie** | an invite/QR for a person who is not yet in the organisation (R-01, R-02). |

Things:
- Forms: `help_ticket` (the pack `support`, install with `admin.packs.install {pack:"support"}`) with a **Status** field, a **Support group** (pool) field and a *Suggested handler*; `help_task`; an **expense claim** with a 1-step approval (Meg) and a **2-step** approval (Meg, then a designation Admin has) to see "step n of m".
- Chats: a DM Ana-Me, a DM Eve-Me that is **end-to-end encrypted** (both devices registered, recovery on), a group `Team` with Me, Ana, Sam; the group `Quiet` that Me has **muted** (`conv.mute`) with Ana in it.
- Phone: notifications **allowed** at the start of each group unless the case says otherwise; battery saver off; a second Android phone or the emulator for the two-device cases is optional (the web counts as the second device).
- Feed fill: a script or the web "Message API" (`POST /api/sd/pub/message` with a key) to put **60 items** into Me's feed for N-17 (paging). If you have no key: send 60 DMs from Ana with different text (each person-key coalesces: use 20 different groups/senders instead, or use the `/debug/notifications` page "add sample" 60 times). Mark the API case S if there is no key.
- The phone's own debug page `/debug/notifications` (debug build): sample feed items and a local-notification test. Use it only when a case says so.

Order with the least setup: **N (needs only Ana) -> L (same) -> T (Ana) -> R (Meg, Admin, Newbie) -> K (Rhea, Ana, Sam, Admin) -> X (Org B, second account)**. Do N-01 to N-06 first: they prove the socket and the feed work; everything else builds on them.

Reset between groups: on the phone pull to refresh Notifications and Tasks; "Clear resolved" and "Mark all read".

---

## N. Notifications (the bell and the list)

Preconditions for all N cases unless stated: Me signed in on the phone, app **in the foreground on the Chats screen**, notifications allowed, feed empty (Mark all read, Dismiss all, Clear resolved).

| ID | Title | Phone steps | Web / other person | Expected on phone | Expected on web | P/F |
|---|---|---|---|---|---|---|
| N-01 | Direct message makes a tile | Open Chats. Stay there. | Ana sends Me "Hello 1" in the DM. | Bell badge goes 0 -> 1 within a second. Tap bell: one tile "Ana" with the text, priority medium, "Open chat". In-app notice appears while on Chats. | – | ☐ |
| N-02 | Coalescing: 3 messages, 1 tile | Open Notifications. | Ana sends 3 more DMs "A","B","C". | Still one tile for Ana, count 4 (N-01 plus these 3), unread again, moved to the top. The bell badge follows the server's `unread` (one tile = 1). | – | ☐ |
| N-03 | Group message | Notifications open. | Ana writes in `Team`. | A tile titled `Team`, text "Ana: …", priority **low**, "Open group". **No** in-app notice (low; the foreground never shows low items). | – | ☐ |
| N-04 | Mention | Notifications open. | Ana writes "@me please look" in `Team`. | Tile "Ana mentioned you", medium, "Open message". In-app notice shown. | – | ☐ |
| N-05 | Approval request | Notifications open. | Rhea submits the 1-step expense claim (Me is its approver). | Tile "Approval needed" (or the type's title), **high**, "Review approval". Notice "You have a new request to review." | – | ☐ |
| N-06 | Outcome of my request | Me submits an expense claim (Forms) while on Notifications. | Meg approves it. | Tile "Request approved" / "Your Expense claim was approved". Read state: unread. | Meg's own request card turns answered. | ☐ |
| N-07 | Outcome: declined and returned | Me submits two claims. | Meg declines one with reason "No receipt", returns the other with "Fix date". | Two tiles: "…was declined by Meg: No receipt…" and "…was returned by Meg…. You can fix it and send it again". | – | ☐ |
| N-08 | New submission (host/admin) | Sign in as Admin on the phone for this case, or use Me if Me is the form host. | Ana submits a form that Me hosts. | Tile "New submission: <form>", "View submission". | – | ☐ |
| N-09 | Ticket update | Notifications open. | Rhea raises a `help_ticket` assigned to Me. | Tile "<Ticket> #id is with you", **high**, "Open ticket". Notice "A ticket was raised to you." | – | ☐ |
| N-10 | To-do task | Notifications open. | Ana creates a task for Me (see T-05). | Tile "New task from Ana", medium, **no action button**. In-app line "You have a new task." with an Open button. | – | ☐ |
| N-11 | Form approved / declined / returned | See N-06/N-07; also an approved one with a 2-step chain. | Meg approves step 1; Admin approves step 2. | After step 1 no outcome yet (or a step notice); after step 2 "was approved". | – | ☐ |
| N-12 | Announcement | Notifications open, app foreground. | Admin sends a broadcast "Office closed Friday" to Me's department. | Foreground notice "Announcement: Office closed Friday". Whether a **tile** appears: record it (B-06). | Admin sees it sent. | ☐ |
| N-13 | Security: new device | Notifications open. | Register a new e2e device for Me (second phone/web with Me's login). | A security tile "e2e_device_added" style text, no action. Record the exact title (B-05: channel). | – | ☐ |
| N-14 | API message (skip without key) | Notifications open. | `POST /api/sd/pub/message` to Me: outcome `error`, severity `high`, `data {"error":{"code":"ARM-500"}}`. | Tile with "from <source>", an `error` tag and `HTTP 500`, a block with the data that opens; no HTML rendering. | – | ☐ |
| N-15 | Filters | Have one high, one medium, one low, one resolved tile. Tap each chip. | – | All = every open tile (not resolved); High/Medium/Low show only theirs; Resolved shows resolved ones. Chip counts match. | – | ☐ |
| N-16 | Unread only | Toggle "Unread only". Mark one tile read. | – | Only unread shown; the read one disappears from the list at once; empty state "You are all caught up." when none. | – | ☐ |
| N-17 | Paging beyond 50 | Fill 60+ items (see data). Scroll to the end of the list. | – | The list loads more automatically; a spinner at the bottom while loading; total 60, no duplicates; in the 300 cap nothing else. | – | ☐ |
| N-18 | Mark read / unread | Open the tile menu on an unread tile: "Mark read", then "Mark unread". | – | Badge drops and rises by 1 each time, immediately. | Open the web bell: same state after a second. | ☐ |
| N-19 | Tap marks read and routes | Tap an unread DM tile. | – | Tile becomes read, the DM conversation opens. | – | ☐ |
| N-20 | Resolve | Tile menu -> Resolve on a medium tile. | – | Leaves "All", appears under "Resolved"; unread count drops if it was unread. | Web shows it resolved. | ☐ |
| N-21 | Dismiss | Swipe a tile (or menu -> Dismiss). | – | Tile removed; no trace after pull-to-refresh. | Web: gone. | ☐ |
| N-22 | Mark all read | Menu -> "Mark all read". | – | Badge 0, all tiles read. | Web: all read. | ☐ |
| N-23 | Mark all resolved | Have 3 open tiles (one unread). Menu -> "Mark all resolved". | – | At once: all tiles leave "All" and appear under "Resolved"; unread badge 0; chip counts follow the server. Offline or on an error: the tiles come back and the server's words show. | Web: all resolved. | ☐ |
| N-24 | Clear resolved | With 2 resolved tiles: menu -> "Clear resolved". | – | Resolved tiles gone; open ones stay. | Web: same. | ☐ |
| N-25 | Routing per action | Create/obtain a tile for each: open_chat, open_message, approvals, tickets (with and without ref), submissions, none (a To-do), admin_console / about_me / axpert / smart_prompt (if you can get one; else use `/debug/notifications`). Tap each. | – | open_chat -> that chat; open_message -> chat scrolled to and flashing the message (1.6 s) if it is loaded; approvals -> Approvals; tickets -> that ticket (or the Tickets list); submissions -> detail sheet today (G-09); none -> detail sheet; the four web-only types and any unknown type -> detail sheet. A To-do tile is **not** routed by its icon/category. | – | ☐ |
| N-26 | E2E item in the tile | Notifications open. | Eve sends Me an encrypted DM "secret 42". | The tile shows the **decrypted** text, not "e2e1:…". Detail sheet too. | – | ☐ |
| N-27 | E2E that cannot be read | Sign in on a new phone/device that has not synced yet (or break the key per `e2e.md`). | Eve sends an encrypted DM. | Tile says "Encrypted message" (no crash, no envelope text). | – | ☐ |
| N-28 | Muted chat stays quiet | `Quiet` is muted. | Ana writes in `Quiet`. | **No** tile in the list, **no** in-app notice, no system notification. (The server still counts it in `unread`: note the bell number, G-04.) | – | ☐ |
| N-29 | Read on the web clears the tile | Phone: unread tile for a DM. | Open that DM on the web (reads it) or mark the item read on the web bell. | Within a second the tile turns read and the badge drops, without touching the phone. | – | ☐ |
| N-30 | Removed on the web | Phone: a tile visible. | Dismiss it on the web. | Tile disappears. Then on the phone tap Resolve on another stale tile you dismissed on web: you see "No such notification." and the list refreshes (fix F2). | – | ☐ |
| N-31 | App resume after 10 minutes | Put the app in the background for 10 min (screen off). | Meanwhile Ana sends 2 DMs and creates a task (the socket may be dropped). | Open the app: within ~2 s the bell is right and the tiles are there (re-read on resume). | – | ☐ |
| N-32 | Airplane mode and back | Turn airplane mode on, wait 10 s, turn it off. | While offline Ana sends a DM. | Offline bar appears; after reconnect the DM tile arrives (re-read on connect), badge right. No error spam. | – | ☐ |
| N-33 | Offline Notifications screen | Airplane mode, open Notifications. | – | Cached tiles (this session) stay; with nothing cached an offline state with Retry; Retry after going online works. | – | ☐ |
| N-34 | Session replaced | – | Sign in as Me on **another phone/emulator** (same kind: mobile). | The first phone is signed out with a notice; pending notifications cleared; after signing in again the feed is Me's again. | – | ☐ |
| N-35 | Rate limit text | Tap Mark read/unread on one tile 40 times quickly (or hold a macro). | – | If the server answers `rate_limited` the notice shows the server's own words and the tile returns to its true state. (Skip if it never triggers.) | – | ☐ |

---

## L. Local (system) notifications

Preconditions: Me signed in, `Org A`. The notifications explainer ("Stay in the loop") appears once, 1 s after the first Home after sign-in.

| ID | Title | Phone steps | Web / other | Expected on phone | P/F |
|---|---|---|---|---|---|
| L-01 | First prompt | Fresh install or clear app data, sign in, reach Home. | – | After ~1 s the explainer sheet; "Not now" closes it and nothing asks again; Notifications screen then shows the row "Notifications are off on this phone." with **Turn on**. | ☐ |
| L-02 | Granted | Same, tap **Allow notifications**. | – | Android 13+ system dialog; tap Allow; the row disappears; settings show the app allowed. | ☐ |
| L-03 | Denied once | Fresh data, Allow -> in the dialog **Don't allow**. | – | No notifications; the row shows **Open settings** (once asked); nothing asks again. | ☐ |
| L-04 | Permanently denied | Deny twice (Android blocks further prompts). Then tap the row. | – | "Open settings" opens the system page for the app. Enable it; return to the app: the row disappears (state re-read on resume). | ☐ |
| L-05 | Foreground | Allowed. App on Chats. | Ana sends a DM. | A system notification (heads-up); **no** in-app notice card. | ☐ |
| L-06 | Background, socket alive | Press Home (app in background, <1 min). | Ana sends a DM "bg 1". | A system notification "Ana / bg 1" in the tray (channel Messages). | ☐ |
| L-07 | Tap, warm start | Tap the notification from L-06. | – | App opens the Ana DM; the item is read; the notification leaves the tray; badge down. | ☐ |
| L-08 | Collapse | Background. | Ana sends 4 DMs in a row. | One notification for Ana (replaced, number 4 on Android), not four. Different senders: one each; at 3 or more a group summary "Messages: n new". | ☐ |
| L-09 | Clearing | Background; a notification showing. | Read that DM on the web. | The notification leaves the tray by itself within a few seconds. Group summary updates. | ☐ |
| L-10 | Clearing by action | Background; a notification showing. | On the web dismiss or resolve the item. | Notification leaves the tray. | ☐ |
| L-11 | Own action | Background. | Send a DM **from the web as Me** (Me's other session) to Ana. | No notification on the phone. | ☐ |
| L-12 | Group message, setting ON (default) | Background. Notifications screen shows the switch **Notify for group messages** ON. | Ana writes in `Team` (group, low). | A system notification "Team / Ana: …" (channel Messages). Tap opens the group. | ☐ |
| L-12a | Group message, setting OFF | Switch **Notify for group messages** OFF on the Notifications screen. Background. | Ana writes in `Team`. | **No** system notification. A mention ("@me") in `Team` and a DM still notify. | ☐ |
| L-12b | Group message, foreground | Setting ON. App in the foreground. | Ana writes in `Team`. | No system notification and no in-app notice (foreground unchanged). | ☐ |
| L-12c | Group message, exceptions | Setting ON. Background. | Ana writes in muted `Quiet`; Me writes in `Team` from the web; Ana writes in `Team` while it is open on the phone (foreground, then Home). | No notification in any of the three. | ☐ |
| L-12d | Setting is per person | Switch OFF as Me, sign out, sign in as Admin, open the Notifications screen; then back to Me. | – | Admin sees ON (default); Me sees OFF again. The switch survives an app restart. | ☐ |
| L-13 | Muted | Background. | Ana writes in muted `Quiet`. | No notification. | ☐ |
| L-14 | Open conversation | Phone has Ana's DM open in the foreground, then Home. Reopen it first. | Ana sends a DM while it is open. | No in-app notice and no notification (conversation open). | ☐ |
| L-15 | E2E text | Background. | Eve sends an encrypted DM "secret 42". | Notification shows "Eve / secret 42" (decrypted on the device). If the key is not readable: "New message" and no body. Never `e2e1:…`. | ☐ |
| L-16 | Killed app | Swipe the app away from recents. | Ana sends a DM. | **Nothing** appears (no push yet, documented). Open the app: the tile and badge are right within ~2 s. | ☐ |
| L-17 | Cold start by tap | Background, a notification showing; then swipe the app away **after** (the notification stays). Tap it. | – | App starts, goes through its start; lands on the Ana DM, not on the lock/login screen. The item may stay unread for a while (G-06): note whether it turns read after the connection. | ☐ |
| L-18 | Signed-out target | Background, notification showing. Sign out inside the app first (without clearing), then tap the notification if still in the tray; if it was cleared by sign-out, that is the expected behaviour: pass. | – | Sign-out clears pending notifications. If one is tapped while logged out, the app shows login and, after signing in as the **same** person, opens the target. Signing in as a **different** person must **not** open the first person's target (G-05 fixed) when it was kept while the first person was signed in; a target kept while nobody was signed in still opens for whoever signs in next. | ☐ |
| L-19 | Channels | Settings -> app -> notifications. | – | Five channels: Messages, Approvals, Tasks, System, Security, each with its description. | ☐ |
| L-20 | Approval and ticket notification | Background. | Rhea raises a ticket to Me; Rhea submits an expense claim for Me to approve. | One notification each, channels Tasks and Approvals; tap opens the ticket / Approvals. | ☐ |
| L-21 | Shade pulled down | Pull the notification shade over the open app and have a DM arrive. | – | Record: a system notification may show while the app is visible (G-11). | ☐ |
| L-22 | Battery saver | Turn battery saver on, background 5 min, send a DM. | – | Record whether the socket survives; no crash. | ☐ |

---

## T. To-do tasks

Preconditions: Me signed in; Tasks screen = Workspace -> Tasks. Ana on the web.

| ID | Title | Phone steps | Web / other | Expected on phone | Expected on web | P/F |
|---|---|---|---|---|---|---|
| T-01 | Empty title | New task, leave title empty, Save. | – | Error under the title, nothing sent (no network call), form stays. | – | ☐ |
| T-02 | Title of 120 and 121 | Type 120 letters, Save; then 121. | – | 120 accepted; 121 -> "too long" under the field before sending. | – | ☐ |
| T-03 | Description 2000 and 2001 | Same with the description. | – | 2000 ok, 2001 error. | – | ☐ |
| T-04 | Past due date | Open the due picker. | – | Days before today are not selectable. Pick today: accepted. Set the phone clock 5 min ahead/back and repeat: today still accepted. | – | ☐ |
| T-05 | Create for myself | Title "Buy cables", priority High, due tomorrow, Save. | – | Success notice; appears in **Assigned to me** and **Created by me**, soonest-due first; "Due tomorrow". | – | ☐ |
| T-06 | Create for someone else | Same, Assignee = Ana. | Ana gets "New task from Me", opens her To-dos. | Appears only in **Created by me**. | Ana: the task, plus the bell tile and a live notice. | ☐ |
| T-07 | Wrong assignee | Assignee = a person who is not an employee (a customer/contact, or a deactivated one) if you have one. | – | The server's own text ("Tasks can only be sent to employees." / "No such employee."), form kept, typed text kept. | – | ☐ |
| T-08 | The other person receives | – | Ana creates a task for Me with due today. | Tile in the bell, in-app line "You have a new task." with Open; Open shows the task detail; list shows it first. | – | ☐ |
| T-09 | Assignee changes status | Open Ana's task assigned to Me -> Start, then Complete. | Ana watches. | Status in progress, then done; buttons follow the rules; a done task shows no Edit/Cancel. | Ana gets "Me set a task to in progress/done". | ☐ |
| T-10 | Assignee cannot edit or cancel | Open the same task as the assignee. | – | No Edit, no Cancel, no Send. Only status moves. | – | ☐ |
| T-11 | Creator edits | Edit title and priority of my own open task. | – | Saved; only changed fields go (nothing sent if you change nothing). | Ana's copy shows the new title. | ☐ |
| T-12 | Creator cancels | Cancel my own open task. | – | Status cancelled, leaves "Active", visible under Cancelled/All. | Assignee gets "set a task to cancelled". | ☐ |
| T-13 | Send to someone else | Task created by Me for Ana -> Send to -> Sam. | – | Task now with Sam; stays in Created by me. | Ana gets "gave your task to someone else"; Sam gets "New task from Me". | ☐ |
| T-14 | Finished task | Complete a task; open it as creator. | – | No Edit. A **Reopen** button; after Reopen it can be edited. | – | ☐ |
| T-15 | Rate limit | Only if you can: create 120 tasks in an hour (script on the web), then create one on the phone. | – | The server's text "Too many tasks this hour; try later." with **Retry**; the typed form stays. Mark S if not feasible. | – | ☐ |
| T-16 | Offline create | Airplane mode, Save a new task. | – | Immediately "You're offline. Connect and try again." with Retry; nothing queued. Go online, tap Retry: created **once**. | List on the web: one task. | ☐ |
| T-17 | Lost answer, no duplicate | Save a task and turn airplane mode on **right after the tap** (try 3 times; you want one where the server got it). Go online. | – | Warning "No answer from the server. Pull to refresh…", **no Retry button**. Pull to refresh: if the task is listed, it went through; if not, create again. Never two. | List: at most one. | ☐ |
| T-18 | Double tap | Fill the form, tap Save twice quickly. | – | One task. | – | ☐ |
| T-19 | Two devices | Complete the task on the phone (step 3). | Me on the web: create a task for Me (step 1); later watch it (step 4). | Phone Tasks list updates within ~1 s (event + re-read) and the bell has a tile. | The web shows the status the phone set. | ☐ |
| T-20 | Stale detail | Open a task on the phone; on the web cancel it; on the phone tap Complete. | – | Server text shown ("…cannot…"), the task re-read and shown in its true state. | – | ☐ |
| T-21 | Overdue | A task due yesterday (set via web with a past time if allowed, or leave until after midnight). | – | "Overdue by 1 day" (or "Overdue today"), shown in red/overdue style; done tasks never overdue. | – | ☐ |
| T-22 | Paging | 60 tasks (script). | – | First 50, then "loading" spinner and the rest; no duplicates. | – | ☐ |

---

## R. Approvals

Preconditions: Me is the approver (Meg's role) or has the approvals of the case; Approvals = Workspace -> Approvals ("To review", "Sent by me"; filters Pending/Accepted/Rejected/Ignored).

| ID | Title | Phone steps | Web / other | Expected on phone | Expected on web | P/F |
|---|---|---|---|---|---|---|
| R-01 | Onboarding / sign-up | Me = administrator. | Newbie scans the invite and signs up. | A card "New user awaiting approval" in To review; notice "You have a new request to review." Accept. | Newbie sees "Your registration was approved". | ☐ |
| R-02 | Sign-up declined | Same, Reject. | – | **Reject asks for a reason for a form** only; for a sign-up the sheet may not need one: record what happens. Server text if refused. | Newbie sees the decline. | ☐ |
| R-03 | Connection (associate) request | – | Someone sends Me a connection request. | Card "Connection request"; Accept connects (check Contacts). | – | ☐ |
| R-04 | Group invite | – | Ana invites Me to a group. | Card "Group invitation"; Accept adds Me. | – | ☐ |
| R-05 | Membership request | Me is the group host. | Someone asks for another connection / to join. | Card "Request for another connection"; Accept. | – | ☐ |
| R-06 | Submission (1 step) | – | Rhea submits an expense claim; Me is the approver. | Card with the summary (Amount…), "Accept/Reject/Return/Ignore". Accept. | Rhea gets "approved". | ☐ |
| R-07 | Submission, 2 steps | – | Submit the 2-step form. | Card shows "step 1 of 2" for Meg; after Meg accepts, Admin's card "step 2 of 2". | – | ☐ |
| R-08 | Reject needs a reason | Reject without typing a reason. | – | **Send is disabled** until a reason is typed. Type "No receipt", tick "may fix and send again", Send. | Rhea: "declined by <Me>: No receipt… You can fix it and send it again". | ☐ |
| R-09 | Return | Return a submission with reason "Fix date". | – | Same rule; no resubmit switch (return always allows it). | Rhea: "returned by…". | ☐ |
| R-10 | Return not offered | Open a non-submission request (sign-up, invite). | – | No "Return" button. | – | ☐ |
| R-11 | Ignore | Ignore a request. | – | Card moves to Ignored; no reason asked. | – | ☐ |
| R-12 | Answered first on the web | Phone has the card open. | Answer the same request on the web. | Within a second the card turns answered (event) and loses its buttons; if you tap Accept before it updates you see "That request has already been answered." and the list refreshes. | – | ☐ |
| R-13 | Not your request | Open a request of someone else, if visible (admin). | – | No buttons if `canRespond` is false. If you force a stale tap the server text "This request isn't yours to answer." is shown. | – | ☐ |
| R-14 | Sent by me, waiting | Me submits an expense claim. | – | "Sent by me" shows it **pending**, no buttons; after Meg answers it shows accepted and who answered. | Meg answers. | ☐ |
| R-15 | Outcome notification to requester | As R-14. | Meg answers. | Bell tile "Request approved/declined" with the reason. | – | ☐ |
| R-16 | Offline answer | Airplane mode, tap Accept. | – | "You're offline…" + Retry; nothing queued; Retry online sends once. | – | ☐ |
| R-17 | Lost answer | Tap Accept and switch airplane mode on at once. | – | Warning "No answer… Pull to refresh", **no Retry**; refresh shows the true state; never answered twice. | – | ☐ |
| R-18 | Double tap | Tap Accept twice. | – | One answer. | – | ☐ |
| R-19 | History filters | Switch Pending/Accepted/Rejected/Ignored. | – | Each list reads from the server; empty states show a picture; paging after 50. | – | ☐ |

---

## K. Tickets

Preconditions: `help_ticket` installed, Support group = pool. Me = holder (assignee) unless stated. Tickets live in Tasks -> Tickets ("With me", "Raised by me", filter by form).

| ID | Title | Phone steps | Web / other | Expected on phone | Expected on web | P/F |
|---|---|---|---|---|---|---|
| K-01 | Raised to me | On Tickets "With me". | Rhea raises a ticket assigned to Me. | Row appears (list re-read), badge number up, in-app notice "A ticket was raised to you." with Open, bell tile "#id is with you". | – | ☐ |
| K-02 | Tabs and filter | Rhea also raises a `help_task`. | – | "With me" and "Raised by me" correct; the form filter lists both forms; selecting one hides the other. | – | ☐ |
| K-03 | Notification tap | Tap the bell tile of K-01. | – | The ticket detail opens (title, status, who it is with, completion bar, actions). | – | ☐ |
| K-04 | Status update with percent | Status update, set 30%, remark "Technician called". | – | Success notice; status In progress, 30%; row stays; history gets a line. | Rhea: ticket update tile; ticket shows 30%. | ☐ |
| K-05 | Send with sendTo | Send, pick Sam, remark required. | – | Cannot send without remark or person (message before sending). After sending: toast "Sent to Sam", row slides out of "With me". | Sam: ticket is with Sam, tile "is with you". | ☐ |
| K-06 | Complete | Complete with optional remark. | – | Status Completed, 100%, goes back to the raiser, leaves "With me". | Rhea: Completed. | ☐ |
| K-07 | Close (raiser) | Me raised a ticket (Raised by me); Ana completes it. Open it as Me. | Ana completes. | **Close** is offered only from Completed; after Close the ticket is final and leaves Raised by me. | – | ☐ |
| K-08 | Return needs reason and remarks | Return with only a remark. | – | "Say why." then needs both; after sending it goes to the previous holder. | – | ☐ |
| K-09 | Drop | Drop with reason + remark. | – | Final status Dropped; row slides out; raiser told. | Rhea: Dropped. | ☐ |
| K-10 | Take it (pool) | Sign in as Sam (a Support member) on the phone. | Rhea raises a ticket with no assignee, Support group set. | Sam sees **Take it** (only while Open); tap -> ticket is with Sam, In progress. A person who is not in Support: record whether the button shows (ASSUMPTION: it may; the server then says no). | – | ☐ |
| K-11 | Required reason / remarks | Try each action leaving required fields empty. | – | Local message, no network call. | – | ☐ |
| K-12 | Same request id after airplane mode | Tap Send and switch airplane mode **on** at once; go online; tap the Retry shown. | – | Warning "No answer…" with **Retry**; Retry sends the same update; result "Sent to…" or the ticket already moved; **never two history lines** for one press. Check `status.history` (K-17) for exactly one entry. | History: one entry. | ☐ |
| K-13 | New press = new update | Do two different Status updates in a row (30%, then 60%). | – | Two history entries. | – | ☐ |
| K-14 | Stale | Open the ticket on the phone (do not act). | Admin does "Status update 50%" on the web. | Phone: tap Complete -> "This ticket was updated by someone else. Reload to see the latest.", the ticket reloads with 50%, what you typed stays; Complete again now works. | – | ☐ |
| K-15 | Forbidden | Open a ticket Me can see but not act on (e.g. only a raiser seeing a Send). | – | The action is not offered; if you force it via a stale screen: "You cannot do this on this ticket." and the ticket re-reads. | – | ☐ |
| K-16 | Waiting for approval | A ticket form with approval. | Rhea raises it. | In Raised by me: "Waiting for approval", **no actions**. After approval it moves to the holder (`ticket_assigned`). | – | ☐ |
| K-17 | History timeline | Open any ticket with updates. | – | Oldest first: who, when, from -> to, percent, remarks, reason, files. | – | ☐ |
| K-18 | Attachments | An action with attachments optional/required: add a file (needs a connection). | – | Upload progress; Send waits for uploads; failed upload shows Retry/Remove; offline -> "needs a connection". | The files open on the web. | ☐ |
| K-19 | Edit own ticket | Raised by Me, status Open. | – | Edit offered only in Open/Forwarded; in In progress it is hidden. | – | ☐ |
| K-20 | Moved to someone else | Ticket in "With me". | Admin reassigns it to Sam. | Phone: the row slides out and the list is right; if the detail is open: it updates and actions vanish; no error. | – | ☐ |
| K-21 | Admin-only action | Sign in as Admin. | – | Admin sees every action the table gives to admin on any open ticket; shows "by an administrator" in history. | – | ☐ |
| K-22 | Badge | – | – | Tickets "With me" badge equals the web's "With me" count after opening the pane (G-14: 0 before the first open). | – | ☐ |
| K-23 | Not found | Open a ticket id that was deleted/closed away (notification of an old ticket). | – | "That ticket is no longer available." | – | ☐ |
| K-24 | Offline | Airplane mode on the Tickets pane. | – | Cached rows stay; with none, offline state with Retry. Actions: "You're offline…". | – | ☐ |

---

## X. Cross-cutting

| ID | Title | Steps | Expected | P/F |
|---|---|---|---|---|
| X-01 | Organisation switch | Me belongs to Org A and Org B. In A open Notifications, Tasks, Tickets (note a ticket id). Switch to B. | Nothing from A is visible: bell 0 until re-read, Tasks/Approvals/Tickets empty or B's; open ticket with the same id in B shows B's (no flash of A's, fix F1). Lists re-read after connect. Local notifications of A are gone from the tray. | ☐ |
| X-02 | Sign out, sign in as another person | Sign out as Me, sign in as Ana. | Feed, tasks, approvals, tickets are Ana's; no notification of Me in the tray; badge right. | ☐ |
| X-03 | Large text | Settings -> Display -> font size largest; also 1.3. | Tiles, task and ticket rows, sheets (clamped at 1.3) readable, no overflow, buttons reachable; long titles ellipsis; long names (40+ letters) wrap or cut. | ☐ |
| X-04 | Language / time zone | Change the phone time zone by +5 h and the date format. | "Due today/tomorrow", overdue and "ago" follow the device; a task due "today" in the old zone is still accepted by the server. | ☐ |
| X-05 | Low-memory kill | Open Tasks, background, use "kill background process" or `adb shell am kill`, reopen. | App restarts cleanly to Home (or login); lists re-read; no crash; the notification tap path still works. | ☐ |
| X-06 | Slow network | Throttle to 2G/Slow 3G (developer options or a proxy). | Spinners shown, no double sends, timeouts end in the "No answer…" warning, never a stuck spinner. | ☐ |
| X-07 | Rapid taps | Tap resolve/dismiss/mark read/Accept/Complete quickly. | One effect per action, UI never in a half state; no crash. | ☐ |
| X-08 | Rotation | Rotate the phone. | **Not supported**: the screen stays portrait (record). | ☐ |
| X-09 | Sheets by drag | Open task detail, ticket action sheet, reason sheet, people picker. | Each closes by dragging down and by tapping outside (the reason sheet must not lose typed text silently if dismissed mid-send). | ☐ |
| X-10 | No scroll-in-scroll | Tasks (tabs inside a screen), Notifications, Approvals. | One scroll direction at a time; pull-to-refresh works; the tab swipe does not fight the list. | ☐ |
| X-11 | Loading and states | Throttle, open each screen cold. | A centred loading state, then content; empty states show their picture or the "[animation: …]" fallback; error state has Retry. | ☐ |
| X-12 | Logs are clean | `adb logcat` while doing N-26, L-15, K-04. | No message text, envelope (`e2e1:`) or token appears in the log. | ☐ |

---

## Smoke test (about 20 minutes)

Run in this order on a fresh sign-in. Any fail stops the release of this build.

| # | Case | What you prove | Min |
|---|---|---|---|
| 1 | L-02 | Notifications can be allowed (Android 13 prompt works) | 1 |
| 2 | N-01 + N-02 | Socket live: DM makes one coalescing tile and the bell badge | 2 |
| 3 | L-06 + L-07 | Background notification arrives; tap opens the right chat and reads it | 2 |
| 4 | N-29 | Read on the web clears the tile on the phone | 1 |
| 5 | N-31 | Resume after the app slept: everything is current | 2 |
| 6 | N-26 | An encrypted message is decrypted in the tile | 1 |
| 7 | T-06 + T-09 | To-do: create for another person; they receive it; assignee moves its status | 3 |
| 8 | T-17 | Lost answer on create never duplicates, no auto retry | 2 |
| 9 | R-08 + R-12 | Approval: reject needs a reason; answered first on the web is handled | 2 |
| 10 | K-04 + K-14 | Ticket: status update; stale handled with the server's text | 2 |
| 11 | K-12 | Ticket retry after airplane mode is one history entry | 2 |
| 12 | X-02 | Sign out / other person: nothing leaks | 2 |

Record at the end: device, build date, who ran it, and the list of F cases.
