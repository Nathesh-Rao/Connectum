# Tickets and tasks

Tickets and tasks are not a special kind of form. **Any form with a field of type `status` is a ticket or a task.** Nothing in the code looks at a form's name.

## The Status field (one per form)

Add it from the field picker (Special fields → Status). It keeps where a record stands, and it is **protected**: it, the field that says who the record is with, and the completion field change **only through a status update**, never by editing the record. Even an administrator who may edit the record is refused with *"Status, Assigned to and Completion change through status updates only."* Editing the other fields works as usual and leaves the protected ones as they were.

Settings on the field (all data, all editable in the builder):

| Setting | Meaning |
|---|---|
| `assigneeField` | a Drop Down of people that says who the record is with. Chosen when the record is raised; afterwards changed by Send / Return / Complete only. Without it the record is with whoever raised it. |
| `completionField` | a Whole Number, 0–100. Starts at 0. |
| `statuses` | the list, first = where a new record starts. Shipped: Open, Forwarded, In progress, Completed, Closed (final), Returned, Dropped (final). A final status ends the record. |
| `actions` | what people can do (below). |
| `editableIn` | the statuses in which the raiser may still edit the ticket's other fields (shipped: Open, Forwarded; empty = never). In any other status the edit is refused with *"This ticket cannot be edited while it is In progress. It can be edited while it is Open and Forwarded."*. Edits by an administrator follow the same window. |

Rules: one Status field per form; the form name must leave room for the history name (`status_<name>`, at most 40 characters); names starting with `status_` are reserved; a form with a Status field cannot be deleted while it has records; a record that has been updated cannot be deleted. A person can also make a form with a Status field themselves (same rules, same history form).

## Ready-made forms

Install the **Tickets and tasks** pack (pack id `support`). The Packs tab of the Admin console is hidden in this version (`HIDDEN_TABS` in `AdminConsoleModal.jsx`), so install it with the call `admin.packs.install {pack: "support"}` as an administrator (list them with `admin.packs.list`): `help_ticket` (16 fields: ticket no, title, category, subtype, description, priority, need by, expected completion, labels, assigned to, also tell, suggested handler, support group, attachments, completion, status) and `help_task` (title, details, due, assigned to, completion, status), both with a conversation for every record and their history forms. They are made as the installing administrator's own forms, so they open in the form builder (Admin console → Structures) and can be edited there. Category and Subtype read the **Ticket Category** / **Ticket SubCategory** forms when they exist (`node scripts/create-ticket-structs.mjs`, see TICKET_SUBCATEGORY_SPEC.md); install those first. Without them Category is a plain drop-down and Subtype is text. The status and completion are never shown on the form a person fills in; they appear on the ticket as a status chip and a progress bar. The ticket's card in its conversation does not repeat them as rows either.

## Pool tickets and leavers

- **Take it:** the ticket form's `poolField` (a designation drop-down) names the group a ticket waits for. While nobody is named, anyone with that designation gets the **Take it** action (who `pool`, handover `self`): they become the person it is with. The pack's ticket form has it (Support group + Take it).
- **When the person it is with leaves**, their open tickets go to: the person the `fallbackField` names (the pack's *Suggested handler*, for example the category's default handler), then the leaver's reporting manager, then an administrator, then whoever raised it. Only active people. The history says why.

## Saved views

A ticket form's Smart View starts with six views until the person saves their own: **With me**, **Waiting on me** (with me and still at the form's first status, so not started), **Everything open**, **Open by category**, **High priority**, **Overdue** (a date filter of `today` means the day the view is opened).

## The actions table

Each action: `name`, `who` (assignee, raiser, admin), `from` (statuses; empty = any that is not final), `to`, `assign` (keep, pick, raiser, previous), `push`, `percent` (none, set, hundred), `reason` and `remarks` (none, optional, required), `attachments` (none, optional, required: files that come with the update; shipped optional on every action except Close), `reasons` (a list to choose from; empty = free text).

Shipped actions:

| Action | Who | From | Leads to | The ticket | Asks for |
|---|---|---|---|---|---|
| Send | holder | Open, Forwarded, In progress, Returned | Forwarded | goes to the person chosen | remarks (required) |
| Status update | holder | Open, Forwarded, In progress, Returned | In progress | stays | percent, remarks (optional) |
| Complete | holder | Open, Forwarded, In progress, Returned | Completed | goes back to the person who raised it, 100% | remarks (optional) |
| Close | raiser | Completed | Closed | stays | remarks (optional) |
| Return | holder | any open status, Completed | Returned | goes back to the person before (the person who raised it when it was never sent) | reason and remarks (required) |
| Drop | holder | Open, Forwarded, In progress, Returned | Dropped | stays; the raiser is told | reason and remarks (required) |

An administrator may act on any open record; the update is recorded as "by an administrator". Completion cannot go down, except after a Return.

## One status update

`status.update` is one all-or-nothing step. Checks, in order: the record exists and is not waiting for approval; the person may take the action; it is allowed from the status the record is in; reason, remarks, send-to and percent rules; the person saw the latest state (`expected: {status, assignee}`, else `stale`: *"This ticket was updated by someone else. Reload to see the latest."*). A send-to person must be active, not the sender, and in the assignee field's list (*"That person cannot be assigned this ticket."*). The same `requestId` again, from the same person, returns the first result, so a retry is harmless (anyone else repeating it is checked like a new request). Two updates at the same moment: one wins, the other gets `stale`.

An update may carry `files`: ids of files the person uploaded themselves, at most the action's limit, each checked against the action's `attachments` rule (*"This action takes no attachments."*, *"Attach a file."*). They are stored on the history record (field `Files`, added to older history forms the first time) and everyone who can see the ticket can open them.

Every update adds one record to the history form `status_<name>` (made automatically, hidden from every list, nobody can add to it or edit it), writes the new status / holder / completion on the record, posts a card into the record's conversation (when the form has "a conversation for every record") and tells people: the person it is now with ("is with you"), and the person who raised it.

Earlier handlers stay in the record's conversation (the assignee field's `keepEarlier`, on by default for that field).

## Edge cases

- A person who holds tickets is deactivated → their open tickets go to the suggested handler, then their manager, then an administrator, then whoever raised them (see Pool tickets and leavers); the history says why.
- A Status field added to a form that already has records → older records count as the first status, held by whoever they name.
- A Status field taken out → the history is kept; the records stop taking updates. Put back, they carry on.
- Statuses or actions removed from the table → records already in a removed status keep showing it and can be moved by any action that starts from "any status".

## For apps

`status.update`, `status.history`, `status.mine {as?, limit?, offset?}`, `status.get` (see TICKETS_AND_TASKS_MOBILE.md and SD_ACTIONS_REFERENCE.md). `submissions.list` and `status.mine` carry `structures[form].status` = `{field, assignee, completion, statuses, actions}`, which is all an app needs to draw the status, the completion bar and the actions a person may take. `submission.get` returns the record with `values[<status field>]`.

## In the Inbox

The Inbox's **Tasks & tickets** folder lists, for any form with a Status field, the open records **with me** and the ones **raised by me**, and each opens to the same card as in the conversation (status chip, progress bar and the actions the form allows). It is read with `status.mine` and works for every ticket or task form by itself. How it is wired, and what it costs: INBOX_TASKS_AND_TICKETS.md.

`status.mine` answers from a list the server keeps for each person (`sd:status:with:<person>`), written whenever a ticket is raised, moved or reassigned and checked on every read, so a ticket that has moved on is never listed and the cost does not grow with the number of tickets. A form that gets its Status field later is listed once, the first time it is read.
