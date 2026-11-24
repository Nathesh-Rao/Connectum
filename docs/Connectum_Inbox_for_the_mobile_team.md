# Connectum Inbox: how it works (for the mobile team)

Written 24 Nov 2026 from the web app's code (branch `feat/smartview-next4`, not yet released). Where something is a web-only detail, or was not checked, it says so.
The web code is in `chat-app/features/smartView/` (`HashInboxModal.jsx` is the screen); the fuller reference is `docs/SMART_VIEW.md` and `docs/CONNECTUM_API.md`.

---

## 1. In one paragraph

The Inbox is **one list of cards** with everything that has to do with the person: the records that are with them, that were given, sent, shared or tagged to them, that they made, and their team's, plus the **approval requests** they have to answer or started, and their reminders. A person narrows it with one **filter panel**, saves what they set up as **views**, and answers approvals from the cards. The server does the finding and counting; the app draws.

## 2. The screen

Header, left to right: the title **Inbox**, the **search box** (wide, in the middle), the **Approvals** button (new), **Refresh**, the **Filter** button, the **Views** (bookmark) button, **Expand** (only when the Inbox is a card inside a conversation) and **Close**. There is no row of tabs and no list of folders any more.

| Control | What it does |
|---|---|
| Search | Narrows what is shown to the cards whose text contains the words (client side, see 8). The placeholder is "Search records". |
| **Approvals** button | Shows the approval requests in place of the list (section 6). The small number on it is how many approvals **wait for the person**. Not saved anywhere. |
| Refresh | Reads everything again (and, on the web, puts every card back to its usual size). |
| Filter | Opens the filter panel (section 4). A small number says how many lines are set. |
| Views | The saved views menu (section 7). |

The list is a **grid of cards**: 3 across on a wide screen, 2 when the area is under 760 px wide, **1 under 480 px** (phones: one column). The web draws **24 cards**, then more when the foot of the list comes into view, then reads the next page from the server.

## 3. The cards

One card = one record. The same card is used everywhere in the Inbox.

- **Band** (tinted, fixed height): at the left the **person the card is about** (round picture, small name under it; "You" for the person's own; the person is who the record is with now, else who raised it); then the **title** (the form's name, one line, "..." when long) and under it `#<id> · <date>, <time>`; at the right the **status chip** (the record's own status, e.g. Open, Approved; or "Pending" while it waits for approval), a small **priority dot** and the **three-dot menu**.
- **Body**: the record's answers as `name  value` rows (an empty value is left out; the answers scroll inside the card, so every card has the same height).
- **Three-dot menu**: **Send**, **Update status**, **History** (and nothing else the person may not do: the server's `record.actions` says what is allowed). A record that belongs to a report is **read only**: show no action buttons.
- A tap on the card opens the record.

**What the colour says** (the band; computed from the record itself, so it works for every form):

| State | Colour | When |
|---|---|---|
| completed | green | at a final status (Done, Completed, Closed, Approved...) |
| rejected | red | declined, or its status says it went wrong (Rejected, Declined, Blocked, Failed, Overdue, Cancelled) |
| waiting | violet | it waits for an approval that has not answered |
| pending | yellow | it is with the person (or their team): it waits for them to act. **This is the one yellow in the app (the owner's exception, 20 Nov 2026)** |
| assigned | blue | it is open and with someone else |

The **priority dot** (high red, medium teal, low grey) comes from a field named or captioned Priority, Severity, Urgency, Importance, Criticality or Risk, read as words ("High", "high priority" and "HIGH" are the same).
The card's outline is the app's blue. Cards that are not records (approvals, reminders) use the same layout with a tag instead of the record status.
*Web only:* a card can be dragged wider/taller from its edges and its sizes are kept per card in the browser; Refresh resets them. The phone does not need this.

## 4. The filter panel

Open it from the Filter button. **Nothing changes until Apply**; **Clear** puts everything back; Escape or a tap outside closes it. The header says how many lines are set ("2 set"). Lines:

### 4.1 Where

**Search in** is a **multi-select**. Nothing chosen = **All records**. Entries:

| Entry | What it shows | How it is read |
|---|---|---|
| Me | the person's own records: with them, given, shared or tagged to them, or made by them | server: `scope:["me"]` |
| My Team | the records of their direct reports (the server's team rule) | server: `scope:["team"]` |
| Requests | records **raised by the person and by their team** (unless "Created by" says who) | server: `createdBy:["me", ...reports]` (at most 50 names) |
| Approvals | **every** request of the approval flows, whatever its answer | from `req.list` (section 6) |
| Pending my approvals | the requests that wait for the person | from `req.list` |
| Approved | requests that were approved | from `req.list` |
| Rejected | requests that were declined | from `req.list` |
| Completed | closed records (the form's final status) | server: `status:"closed"` |
| Reminders | the person's reminders | from the reminders list |
| Escalations | open records of a form with a status, with the person or their reports, that have **waited more than 3 days** since they were last touched, or whose due date (a date field named or captioned due, deadline or expiry) has passed; plus approvals waiting for the person longer than 3 days | server: `escalated:{days:3}` |
| Timeline | the same records shown **one heading per day** | stands **alone**: choosing it clears the others, choosing another entry clears it |

With **several entries** the result is the **union**: a record is listed once if any entry holds it (the server answers one list). The approvals and reminders among the entries are drawn under the records. If the choice has only approvals and reminders, no records are asked for.
Approvals, Pending my approvals, Approved and Rejected are **not** records: they come from the app's list of requests.

### 4.2 Form

A **multi-select** of forms. It offers **only the forms that have a record under the entries of Search in and the other lines**, with the count: "Leave request (2)". It changes as the other lines change; a form that loses its records is let go from the choice. While the server counts, show "Counting the forms..." (never the full list for a moment). If counting fails, offer every form.
The count is the number of the result: ticking a form brings in all its records the person may read, and the count already includes them.

### 4.3 People

Four multi-selects, each with **Me** (only when "me" is among them) and the people on the records: **Created by** (who made it), **Sent by** (who sent it on), **Sent to** (who it was sent or shared to), **Tagged to** (who the record names in its fields of people: assigned to, raised to, watcher...). Each list shows **only people who are on the records** under the other lines (including the forms ticked) and leaves out **its own** line, so a person can still switch to somebody else. A person chosen who has no record any more is let go.

### 4.4 Details

**Date**: from and to (local days). **Sort**: Latest, Oldest, Ascending (A to Z), Descending (Z to A), **Open only**, **Closed only** (the last two cut by status; Completed in Search in wins over Open only).

### 4.5 Advanced filter (fold)

**Blocks** (up to **10**): each block = one or several forms + people (created by / sent by / sent to) + **conditions** on the form's fields (up to **20**, joined with And/Or, read from the left; conditions only for a block of **one** form). A record is listed when **any** block holds it. Operators by field kind: text `contains, eq, ne, starts, ends, empty, notempty`; number `eq ne gt gte lt lte between empty notempty`; date `eq lt gt lte gte between empty notempty`; yes/no. An empty block says nothing and is not sent.

## 5. The calls

All are WebSocket `/sd` commands; replies are `{ok:true, data}` or `{ok:false, error:{code, message}}`. **Limit: 30 commands per 10 seconds per connection** (`rate_limited`, with the same `reqId`): never read pages in parallel, retry after a growing pause.

### 5.1 `records.query` (the list)

```
records.query {
  forms?: [name],                          // only these forms
  groups?: [ {form?, createdBy?, sentBy?, sentTo?, conditions?} ],   // the advanced blocks, up to 10
  createdBy?, sentBy?, sentTo?, taggedTo?: [user name | "me"],       // for every record (up to 50 each)
  from?, to?: "2026-11-23",                // days, local
  status?: "open" | "closed",
  attachments?: true,                      // only records that hold a file (the web panel no longer offers it)
  scope?: ["me"] | ["team"],
  members?: [user name],                   // with scope team
  escalated?: {days},                      // 1..365, default 3
  team?: {members?, linked?},              // see the Smart View document, section 7
  views?: [ {scope?, createdBy?, status?, escalated?} ],   // up to 8: the Search in entries; a record is listed when ANY view holds it
  facets?: true,                           // add the lists of section 4.2 and 4.3
  withDetails?: true,                      // add files, labels, canEdit to each record
  limit?: 1..200 (100), offset?: n
}
-> { submissions:[...], structures:{...}, total, hasMore, capped,
     formCounts: {form: n}, people: {createdBy, sentBy, sentTo, taggedTo} }   // the last two only with facets
```
- **Exact** over every record the person has to do with: what is with them, given, tagged or shared to them, made by them, and their team's; **each of those lists is read up to 1000 records** (`capped: true` says one was longer).
- A form named in `forms` (or a block) brings **all its records the person may read** (not only the ones linked to them), when both Me and My Team are looked at.
- Newest first. Every part of the request is checked: a wrong shape gives `error.code = "invalid"` and nothing is run.
- `facets:true, limit:1` is the call for the panel's lists: `formCounts` = how many records each form has under every part of the filter **except the forms and blocks**; `people.*` = user names (the caller as `"me"`, up to 200) on those records under every other line, each list leaving out its own line. With several `views` a record counts once.

### 5.2 Other calls

| Call | Use |
|---|---|
| `records.counts {cap?, fresh?}` | `{me, team, all, reports, cap}`: exact counts of the lists (a view with more than `cap` answers `cap+1`, shown "1000+"). `reports` = how many direct reports the person has (0: no My Team). Kept 3 s per person unless `fresh:true` |
| `records.people` | `{team, sentBy, sentTo}` user names for the people lists when the facets are not used (up to 200 each); `team` = the person's direct reports |
| `records.mine {as: "with"\|"raised"\|"involved"\|"team", limit, offset, done?}` | the older lists the Inbox is built from (with me, raised by me, given to me, my team's open/finished) |
| `people.cards {usernames:[...]}` (up to 60) | `{people:{<user>:{name, designation, role, avatar}}}`: names and pictures for the cards. `avatar` is null when there is none |
| `req.list {status?, limit?, offset?}` | the approval requests (section 6) |
| `req.respond {id, action:"accept"\|"reject"\|"ignore", reason?, allowResubmit?}` | answer a request |
| `record.actions`, `record.send`, `submission.history {id}` | what the three-dot menu does |

## 6. Approvals: the flow that already exists

**Where they come from.** The app keeps **one list of requests** (`req.list`, mapped once and shared by the Approvals dialog, My Workspace cards and the Inbox), so every place agrees. After any answer the list is read again and every card follows. Each request has: `id`, `type`, `status`, `direction` (`incoming` = waits on the person, `outgoing` = the person started it), `canRespond`, who it is from, a caption, and for forms: `tstruct`, `submissionId`, `summary` (the answers), `stage` and `stages` ("Step 1 of 2").

**Kinds** (what the card says): **Sign-up** (`onboarding`, listed only while pending), **Connection request** (`membership`, `associate`), **Introduction** (`handover`), **Group invitation** (`group_invite`), **Transfer** (`host_transfer`), **Form** (`submission`: a record that needs approval, in one or several steps; anything else is "Request").

**States** the Inbox uses:

| State | Meaning |
|---|---|
| Pending, **waiting for you** | status pending **and** `canRespond:true` (the server says this person may answer). The card has **Approve** and **Decline** (and **Return** for a form) |
| Pending, waiting for somebody else | status pending and `canRespond:false` (a request the person sent): no buttons, tag "Waiting for approval" |
| Approved | status `accepted` or `approved` |
| Rejected | status `rejected` (tag "Declined") |
| Closed | anything else (ignored, withdrawn) |

**The number on the Approvals button** = the requests that are pending **and** can be answered by the person (the Inbox's existing count of approvals waiting for them). It shows nothing when it is 0. It can differ from the banner "N requests waiting for your decision" in My Workspace (6 against 3 was seen on the dev data); the reason was **not checked**, so do not use the banner's number for this button.

**Answering.**
- **Approve** = `req.respond {id, action:"accept"}`.
- **Decline** = `req.respond {id, action:"reject"}`. A form that needs a reason (`declineNeedsReason`) first asks for one: the reason is text up to **500 characters**, shown to the submitter, and the approver may also allow a resubmission (`allowResubmit:true`, default false). The card then opens the Approvals dialog for the box instead of declining at once.
- **Return** (forms only) is also done in the Approvals dialog. *Not checked here: the exact call it uses; ask the web owner before building it.*
- A card slides out when answered, then the lists are read again so the server has the last word. A failed answer shows the server's words.

**Who can answer** is the server's decision: holding `approve.<type>` (`onboarding`, `membership`, `submission`, `wizard`) lets a person answer every request of that type and see the waiting ones; routing by manager, designation or category also applies. The app only reads `canRespond`.

**The Approvals button.** Press it: the list is replaced by **all the person's approval requests, in every state, newest first, as the Inbox's approval cards** (band with the person's picture or the kind's icon, the title, the date, the tag; the details as rows; the buttons). A small dropdown narrows to **All / Pending / Approved / Rejected / Closed**, each with its count; the search box narrows by text. Empty: "There are no approvals." (or "No approvals are like that."). Press the button again to return to the Inbox as it was. **Nothing is saved**: it is not part of a view, and applying the filter, clearing it or opening a view closes it. The filter's own Approvals entries (4.1) stay as they were; the button is a quick separate way in.

## 7. Saved views

A **view** is the whole set-up of the Inbox: Search in, forms, people, dates, sort, advanced blocks, approval answers. Kept **on the server per person**, so any device opens the same.

- `inbox.views.get {}` -> `{views:[{name, view, savedTs}], default}`
- `inbox.views.save {name, view, default?}` -> `{views, default}` (a name that exists is replaced; `default:true` makes it the one the Inbox opens on)
- `inbox.views.delete {name}`, `inbox.views.default {name|null}`
- Limits: up to **20** views, name up to **60** characters, a view up to **20,000** bytes, only the known keys are kept (`folder, lens, kinds, dataForms, approvalPick, scopePick, wheres, teamMembers, blocks, filters, sort, timing`); anything else is dropped; a wrong shape is `invalid`. An older single saved view becomes "My view".
- Behaviour: **Default View** is always first and is what the Inbox opens on (unless it was opened on purpose in a folder); **Save view** updates the open one, **Save as new view** keeps a copy under a new name, **Create view** starts a plain list, **Remove view** asks first. Leaving with a change not saved asks **Save your changes?** (Save / Discard / Cancel). The name "Default View" is reserved.
- Several Search in entries are stored as `wheres` (a list of entry ids; a single entry is the view's `folder`). Unknown values are ignored on reading, so a view from a newer or older app never breaks.

## 8. Search

The search box is **client side**: it looks in the text of the cards **already read**. To make that fair, the web reads more pages while words are typed, up to **5,000** records. A word that appears only in a record beyond that is not found. (A server-side text search is **not built**; if the mobile app needs it, ask for it.)

## 9. Live updates

The Inbox reads again, quietly, when one of these arrives (and after a reconnect): `submissions_changed {id, tstruct, action, by, record?}`, `submission_approved`, `submission_rejected`, `ticket_assigned`; `resync` has no `tstruct`: read everything. Reading again means: `records.query` (current view), `records.counts`, `records.people`, `req.list`, reminders. Debounce them.

## 10. Edge cases the mobile app must handle

| Case | What to do |
|---|---|
| Rate limited | retry with a growing pause; one read at a time |
| Nothing matches | "No records match the filter." (when anything is set); "No records yet." when nothing is set |
| The read fails | an error line with "Use Refresh to try again", and keep the list that was on screen |
| A list is longer than 1000 | `capped`: counts say "1000+" |
| Facets still loading | "Counting the forms..." |
| A chosen form/person no longer has records | drop it from the choice |
| Timeline with another entry | Timeline wins only when chosen last; otherwise it is cleared |
| A person with no reports | no My Team entry; `reports` is 0 |
| A saved view with an unknown entry | ignore that part |
| Two answers arrive out of order | keep the newest ask's answer only |
| A card of a report's record | read only, no buttons |
| A name not shown yet | show the user name until `people.cards` answers, then the name |
| A very long title/value | cut with "..." / wrap inside the card; never push the layout |

## 11. What changed in this version

- One filter panel replaced the pills and tabs; **Search in is a multi-select** and now has **Requests, Approvals, Approved, Rejected, Completed**.
- **Form and People lists are dynamic** (facets), and **Tagged to** was added to People.
- **Named saved views** (`inbox.views.*`) like the Smart View's.
- A separate **Approvals button** with the number of approvals waiting for the person.
- **Refresh** resets the cards' sizes (web).
- The Attachments line was removed from the panel.

## 12. Checklist to test on the phone

1. Open the Inbox: cards in one column, newest first; the Approvals button shows the right number.
2. Search in: choose Me, then add Requests: the list is the union; clear it.
3. Form list: choose Approvals alone: only forms that have approvals appear, with counts that add up to the number of cards.
4. Pick a form: the People lists narrow. Pick a person: the Form list narrows. Pick a date range with nothing: "No records match the filter."
5. Tagged to: pick a person; the cards are the records that name them.
6. Approvals button: all states, the dropdown narrows, Approve/Decline works on a waiting one and the card leaves; press again: back to the Inbox. Applying a filter closes it.
7. Save a view, change something, close: "Save your changes?" appears. Delete the view.
8. A manager: My Team shows the reports' records read only. A person with no reports: no My Team.
9. Change a record on the web: the phone updates quietly.
10. Turn the network off and on: everything is read again.
