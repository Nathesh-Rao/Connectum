# Tickets and tasks: what the mobile app calls

Same calls as the web app (WebSocket `sd` actions or `POST /api/sd/<action>`, see SD_ACTIONS_REFERENCE.md). Any form whose definition has a field of type `status` is a ticket or task; the rules are in TICKETS_AND_TASKS.md. The replies below are real, captured from a running server.

## What to draw

`status.mine`, `status.get` and `submissions.list` carry, for each ticket form, `structures[<form>].status`:
`{field, assignee, completion, subject, pool, statuses:[{name, final}], editableIn:[status], actions:[{name, who, from, to, assign, percent, reason, remarks, attachments, reasons}]}`. `subject` is the name of the field a ticket is titled by (the form's first plain text field, or `null`): draw `values[status.subject]` as the title, and `<form caption> #<id>` when it is empty.

For a record: the status is `values[status.field]` (missing = the first status), who it is with is `values[status.assignee]` (missing = the person who raised it, `by`), the completion is `values[status.completion]` (0 to 100).

Offer an action when the person is one of its `who` (assignee = it is with them now, raiser = `by`, admin = an administrator), the status is in `from` (empty = any status that is not final) and the status is not final. The server decides again on every call.

Inputs per action: `reason` and `remarks` when not `none` (required when `required`; a non-empty `reasons` means choose from them), `sendTo` (a username) when `assign` is `pick`, `percent` (0 to 100) when `percent` is `set`, `files` (a list of ids of files the person uploaded, see the upload calls) when `attachments` is not `none` (required when `required`).

Offer Edit on the raiser's own ticket only while `values[status.field]` is in `editableIn` (the server refuses it otherwise). Each `status.history` record carries `files` when the update had any.

Send `expected: {status, assignee}` = what the screen showed. When someone else got there first the answer is `stale` ("This ticket was updated by someone else. Reload to see the latest."): reload and show the latest. Send the same `requestId` when retrying after a lost answer: it is the same update, not a second one.

In a conversation a ticket's form card has `form.ticket: true`; `status.get {id}` returns the ticket with its status table and `isAdmin`. The event `ticket_assigned {id, tstruct, action, by}` is pushed to the person a ticket is now with; the same news is in the notifications feed (`feed.list`, category submissions, `ref.submissionId`).

## The person's lists (the Inbox)

`status.mine {as?, limit?, offset?}` is the one call behind "tickets and tasks" in a person's inbox. It works for every form that has a status field, so a ticket form or task form an administrator adds later appears by itself; do not look at a form's name.

| `as` | What it lists |
|---|---|
| `"with"` (default) | the open tickets that are **with this person now** (what they have to do). Not those still waiting for approval, not final ones. |
| `"raised"` | the open tickets this person **raised** (what they are waiting for), the ones waiting for approval too (`status` of the record is `pending`: draw "Waiting for approval", offer no action). The newest 200 of each form. |

`limit` is 1 to 200 (default 100) and `offset` is 0 or more; anything else is put right, never an error. The reply is `{submissions, structures, total, hasMore}`: `total` is how many tickets are with the person (use it for the badge), `hasMore` says to ask again with `offset` = how many you already have ("Show more"). `raised` has no paging.

Draw each row from the record and `structures[<form>]`: the title (`subject`), the form caption, the status, who it is with, the completion, and the actions (rules above). Give the person a filter by form: the list of forms is simply the distinct `structures` in the reply.

Keep the list current: re-read it (the same call) when the live event `ticket_assigned` or `submissions_changed` arrives, and after every `status.update` the person makes. `ticket_assigned {id, tstruct, action, by}` is pushed to the person a ticket is now with, on every move and also when a ticket is **raised** to them (`action: "Raised"`) and when a ticket that waited for approval is approved. A ticket the person acted on and that leaves their list (sent on, completed, dropped) should slide out; show what was done ("Sent to @ben.") as a toast, since the row is gone.

The list is read from a per-person index the server keeps, so it costs one read however many tickets exist. `total` and the list are always checked against the records: a ticket that has moved on is never listed.

## Calls and replies

### status.update (forbidden)

```json
{
  "ok": false,
  "error": {
    "code": "forbidden",
    "message": "You cannot do this on this ticket."
  }
}
```

### status.update (ok)

```json
{
  "ok": true,
  "data": {
    "assignee": "bn4jtm",
    "byAdmin": false,
    "completion": 0,
    "record": 44,
    "status": "Forwarded",
    "ticket": 42
  }
}
```

### status.update (stale)

```json
{
  "ok": false,
  "error": {
    "code": "stale",
    "message": "This ticket was updated by someone else. Reload to see the latest."
  }
}
```

### status.history

```json
{
  "ok": true,
  "data": {
    "history": [
      {
        "by": "an4jtm",
        "id": 44,
        "ts": 1793640000000,
        "values": {
          "Action": "Send",
          "ByAdmin": "No",
          "FromStatus": "Open",
          "Remarks": "your area",
          "SentTo": "bn4jtm",
          "Ticket": "42",
          "ToStatus": "Forwarded"
        }
      },
      {
        "by": "bn4jtm",
        "id": 45,
        "ts": 1793640000000,
        "values": {
          "Action": "Status update",
          "ByAdmin": "No",
          "FromStatus": "Forwarded",
          "Percent": "40",
          "Remarks": "started",
          "Ticket": "42",
          "ToStatus": "In progress"
        }
      },
      {
        "by": "bn4jtm",
        "id": 46,
        "ts": 1793640000000,
        "values": {
          "Action": "Send",
          "ByAdmin": "No",
          "FromStatus": "In progress",
          "Remarks": "over to you",
          "SentTo": "cy4jtm",
          "Ticket": "42",
          "ToStatus": "Forwarded"
        }
      },
      {
        "by": "cy4jtm",
        "id": 47,
        "ts": 1793640000000,
        "values": {
          "Action": "Return",
          "ByAdmin": "No",
          "FromStatus": "Forwarded",
          "Reason": "Wrong team",
          "Remarks": "not mine",
          "Ticket": "42",
          "ToStatus": "Returned"
        }
      },
      {
        "by": "bn4jtm",
        "id": 48,
        "ts": 1793640000000,
        "values": {
          "Action": "Return",
          "ByAdmin": "No",
          "FromStatus": "Returned",
          "Reason": "Wrong team",
          "Remarks": "not mine either",
          "Ticket": "42",
          "ToStatus": "Returned"
        }
      },
      {
        "by": "an4jtm",
        "id": 49,
        "ts": 1793640000000,
        "values": {
          "Action": "Return",
          "ByAdmin": "No",
          "FromStatus": "Returned",
          "Reason": "Wrong team",
          "Remarks": "back to you",
          "Ticket": "42",
          "ToStatus": "Returned"
        }
      },
      {
        "by": "rs4jtm",
        "id": 50,
        "ts": 1793640000000,
        "values": {
          "Action": "Send",
          "ByAdmin": "No",
          "FromStatus": "Returned",
          "Remarks": "try again",
          "SentTo": "an4jtm",
          "Ticket": "42",
          "ToStatus": "Forwarded"
        }
      },
      {
        "by": "an4jtm",
        "id": 51,
        "ts": 1793640000000,
        "values": {
          "Action": "Complete",
          "ByAdmin": "No",
          "FromStatus": "Forwarded",
          "Percent": "100",
          "Remarks": "fixed",
          "Ticket": "42",
          "ToStatus": "Completed"
        }
      },
      {
        "by": "rs4jtm",
        "id": 52,
        "ts": 1793640000000,
        "values": {
          "Action": "Return",
          "ByAdmin": "No",
          "FromStatus": "Completed",
          "Reason": "Still broken",
          "Remarks": "no",
          "Ticket": "42",
          "ToStatus": "Returned"
        }
      },
      {
        "by": "an4jtm",
        "id": 53,
        "ts": 1793640000000,
        "values": {
          "Action": "Complete",
          "ByAdmin": "No",
          "FromStatus": "Returned",
          "Percent": "100",
          "Ticket": "42",
          "ToStatus": "Completed"
        }
      },
      {
        "by": "rs4jtm",
        "id": 54,
        "ts": 1793640000000,
        "values": {
          "Action": "Close",
          "ByAdmin": "No",
          "FromStatus": "Completed",
          "Ticket": "42",
          "ToStatus": "Closed"
        }
      }
    ]
  }
}
```

### status.mine (with me)

Shown with `limit: 2`; one record is kept here. `hasMore` is true because another is waiting.

```json
{
  "ok": true,
  "data": {
    "hasMore": true,
    "structures": {
      "help_ticket": {
        "caption": "Ticket",
        "fields": {
          "also_tell": "Also tell",
          "assignee": "Assigned to",
          "attachments": "Attachments",
          "category": "Category",
          "description": "Description",
          "done": "Completion",
          "expected_completion": "Expected completion",
          "labels": "Labels",
          "need_by": "Need by",
          "priority": "Priority",
          "state": "Status",
          "subtype": "Subtype",
          "suggested": "Suggested handler",
          "support_group": "Support group (anyone in it may take it)",
          "ticket_no": "Ticket no",
          "title": "Title"
        },
        "recordThread": true,
        "status": {
          "actions": [
            {
              "assign": "pick",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Send",
              "percent": "none",
              "push": true,
              "reason": "none",
              "reasons": [],
              "remarks": "required",
              "to": "Forwarded",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Status update",
              "percent": "set",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "In progress",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "raiser",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Complete",
              "percent": "hundred",
              "push": true,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "Completed",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Completed"
              ],
              "name": "Close",
              "percent": "none",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "Closed",
              "who": [
                "admin",
                "raiser"
              ]
            },
            {
              "assign": "previous",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Completed",
                "Returned"
              ],
              "name": "Return",
              "percent": "none",
              "push": false,
              "reason": "required",
              "reasons": [],
              "remarks": "required",
              "to": "Returned",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Drop",
              "percent": "none",
              "push": false,
              "reason": "required",
              "reasons": [],
              "remarks": "required",
              "to": "Dropped",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "self",
              "from": [
                "Open"
              ],
              "name": "Take it",
              "percent": "none",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "none",
              "to": "In progress",
              "who": [
                "pool"
              ]
            }
          ],
          "assignee": "assignee",
          "completion": "done",
          "field": "state",
          "pool": "support_group",
          "statuses": [
            {
              "final": false,
              "name": "Open"
            },
            {
              "final": false,
              "name": "Forwarded"
            },
            {
              "final": false,
              "name": "In progress"
            },
            {
              "final": false,
              "name": "Completed"
            },
            {
              "final": true,
              "name": "Closed"
            },
            {
              "final": false,
              "name": "Returned"
            },
            {
              "final": true,
              "name": "Dropped"
            }
          ],
          "subject": "title"
        }
      }
    },
    "submissions": [
      {
        "branch": "HQ",
        "by": "rhea",
        "host": null,
        "id": 38,
        "scope": "user",
        "ts": 1793665090505,
        "tstruct": "help_ticket",
        "values": {
          "assignee": "ana",
          "description": "People inside",
          "done": 0,
          "priority": "High",
          "state": "Open",
          "ticket_no": "TKT-0005",
          "title": "Lift 2 is stuck on floor 3"
        }
      }
    ],
    "total": 4
  }
}
```

### status.mine (raised by me, `as: "raised"`)

```json
{
  "ok": true,
  "data": {
    "hasMore": false,
    "structures": {
      "help_task": {
        "caption": "Task",
        "fields": {
          "assignee": "Assigned to",
          "details": "Details",
          "done": "Completion",
          "due": "Due",
          "state": "Status",
          "title": "Title"
        },
        "recordThread": true,
        "status": {
          "actions": [
            {
              "assign": "pick",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Send",
              "percent": "none",
              "push": true,
              "reason": "none",
              "reasons": [],
              "remarks": "required",
              "to": "Forwarded",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Status update",
              "percent": "set",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "In progress",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "raiser",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Complete",
              "percent": "hundred",
              "push": true,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "Completed",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Completed"
              ],
              "name": "Close",
              "percent": "none",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "Closed",
              "who": [
                "admin",
                "raiser"
              ]
            },
            {
              "assign": "previous",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Completed",
                "Returned"
              ],
              "name": "Return",
              "percent": "none",
              "push": false,
              "reason": "required",
              "reasons": [],
              "remarks": "required",
              "to": "Returned",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Drop",
              "percent": "none",
              "push": false,
              "reason": "required",
              "reasons": [],
              "remarks": "required",
              "to": "Dropped",
              "who": [
                "admin",
                "assignee"
              ]
            }
          ],
          "assignee": "assignee",
          "completion": "done",
          "field": "state",
          "pool": null,
          "statuses": [
            {
              "final": false,
              "name": "Open"
            },
            {
              "final": false,
              "name": "Forwarded"
            },
            {
              "final": false,
              "name": "In progress"
            },
            {
              "final": false,
              "name": "Completed"
            },
            {
              "final": true,
              "name": "Closed"
            },
            {
              "final": false,
              "name": "Returned"
            },
            {
              "final": true,
              "name": "Dropped"
            }
          ],
          "subject": "title"
        }
      },
      "help_ticket": {
        "caption": "Ticket",
        "fields": {
          "also_tell": "Also tell",
          "assignee": "Assigned to",
          "attachments": "Attachments",
          "category": "Category",
          "description": "Description",
          "done": "Completion",
          "expected_completion": "Expected completion",
          "labels": "Labels",
          "need_by": "Need by",
          "priority": "Priority",
          "state": "Status",
          "subtype": "Subtype",
          "suggested": "Suggested handler",
          "support_group": "Support group (anyone in it may take it)",
          "ticket_no": "Ticket no",
          "title": "Title"
        },
        "recordThread": true,
        "status": {
          "actions": [
            {
              "assign": "pick",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Send",
              "percent": "none",
              "push": true,
              "reason": "none",
              "reasons": [],
              "remarks": "required",
              "to": "Forwarded",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Status update",
              "percent": "set",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "In progress",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "raiser",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Complete",
              "percent": "hundred",
              "push": true,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "Completed",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Completed"
              ],
              "name": "Close",
              "percent": "none",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "optional",
              "to": "Closed",
              "who": [
                "admin",
                "raiser"
              ]
            },
            {
              "assign": "previous",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Completed",
                "Returned"
              ],
              "name": "Return",
              "percent": "none",
              "push": false,
              "reason": "required",
              "reasons": [],
              "remarks": "required",
              "to": "Returned",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "keep",
              "from": [
                "Open",
                "Forwarded",
                "In progress",
                "Returned"
              ],
              "name": "Drop",
              "percent": "none",
              "push": false,
              "reason": "required",
              "reasons": [],
              "remarks": "required",
              "to": "Dropped",
              "who": [
                "admin",
                "assignee"
              ]
            },
            {
              "assign": "self",
              "from": [
                "Open"
              ],
              "name": "Take it",
              "percent": "none",
              "push": false,
              "reason": "none",
              "reasons": [],
              "remarks": "none",
              "to": "In progress",
              "who": [
                "pool"
              ]
            }
          ],
          "assignee": "assignee",
          "completion": "done",
          "field": "state",
          "pool": "support_group",
          "statuses": [
            {
              "final": false,
              "name": "Open"
            },
            {
              "final": false,
              "name": "Forwarded"
            },
            {
              "final": false,
              "name": "In progress"
            },
            {
              "final": false,
              "name": "Completed"
            },
            {
              "final": true,
              "name": "Closed"
            },
            {
              "final": false,
              "name": "Returned"
            },
            {
              "final": true,
              "name": "Dropped"
            }
          ],
          "subject": "title"
        }
      }
    },
    "submissions": [
      {
        "branch": "HQ",
        "by": "rhea",
        "host": null,
        "id": 38,
        "scope": "user",
        "ts": 1793665090505,
        "tstruct": "help_ticket",
        "values": {
          "assignee": "ana",
          "description": "People inside",
          "done": 0,
          "priority": "High",
          "state": "Open",
          "ticket_no": "TKT-0005",
          "title": "Lift 2 is stuck on floor 3"
        }
      }
    ],
    "total": 5
  }
}
```
