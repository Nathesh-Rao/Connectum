# Smart View for mobile: our questions to the backend team, with status after your revision 2

Hello, and thank you for revision 2 of `MOBILE_SMART_VIEW.md` (the one built from `origin/dev` `6dfeaedc`, with the 107 captures and the engine vectors). It answered most of what we asked and corrected a few things we had wrong. You asked us to re-send our numbered questions and the list of disagreements, because the attachment never reached you; this file does that, in full, so it can be read on its own.

Each item has a status:
- **ANSWERED**: your revision 2 settles it (the section is named).
- **PARTLY**: part of it is settled; what is left is written out.
- **STILL OPEN**: we need an answer. We also say what we assume until then, and what would break if the assumption is wrong.

At the end (part 3) are the new open items that revision 2 raised. If you only have a few minutes, please read part 3 first: items N1 to N10.

---

## Part 1. Our 25 questions

**1. Is there any server-side computation for filtering, sorting, grouping or aggregating a source? ANSWERED** (section 5.1.0: none exists; exact rules and test vectors given). The mobile owner is deciding whether to port the rules to the phone. No further action for you, except item N9 if a server option is ever planned.

**2. What is the cell text for each field type, and the full list of field types in `ai.enterprise`? ANSWERED** (sections 3.8 and 3.8.1, and `vectors.json`).

**3. For `records.mine`, do we continue with `next` or with `offset + rows received`? ANSWERED** (section 2.4: `next` is always `null` for `with`, `involved`, `all`; continue with `offset += rows received` while `hasMore`; only `raised` and `team` give a real `next`). This is what we already did.

**4. Is `failed` (naming the parts of the source list that could not be read) a server field? ANSWERED.** The server answers one `forms` array; `failed` is something the web builds from its separate calls. We make one call and show an error with a retry.

**5. Which code does `submission.get`, `submission.history` and `record.actions` give for a record the person may not open: `not_found` or `forbidden`? ANSWERED** (section 2.13: always `not_found`).

**6. Is `data.record` really on `submissions_changed` and `ticket_assigned`, for every reader? ANSWERED** (section 2.11: yes for a person who may read the record; none on `deleted`; none means "unknown"). It is on `dev` since 16 Nov 2026 (#822) and in no release. What we still need is a release: see N6.

**7. Is `tstructs_changed` delivered to every connected socket, mobile ones included, with `scope, name, action, by`? ANSWERED** (section 2.11, capture `104-`: everyone connected).

**8. Does the server know the `#view` command and the argument type `source`? ANSWERED** (section 1.3.1: no; `/cmds` has 22 commands and none is `view`; `/cmdcomplete` answers `none`). The phone builds the entry and the suggestions itself and never sends the line.

**9. Could you run a capture of every shape so we can compare? PARTLY.** The 107 captures are exactly what we needed. Three gaps remain: a real `api.run` with rows, a manager's `records.mine {as:"team"}` with data, and a share to a group (items N7, N8 and N9 in part 3 repeat this).

**10. Which columns of a plain source (a structure with no set-up) are filterable? STILL OPEN.** The filter panel offers "one line per filterable column", and `filter:true` lives in the set-up metadata, but a source with no set-up has no metadata. *We assume:* every column whose type is not file, json or list. *If different:* our filter list would differ from the web's for the same structure. A one-line answer (or the function name) is enough.

**11. Is there a cheap read of one record in the shape of a Smart View row (with `labels`, `canEdit`)? PARTLY.** Your table in section 2.1 says `submission.get {id}` reads one record as the person may read it. We have not seen its answer next to a `submissions.list` row. *We assume:* its fields are enough to rebuild the row, but without `canEdit`, `files` and `labels` (a `records.mine`-style row). *If different:* the row patch after an `updated` event would lose edit rights until the next full read. Please confirm, or add a capture of `submission.get` on a record with files and labels, next to the same record in `submissions.list`.

**12. How many pages should a phone read (the web reads up to 20 pages of 500)? PARTLY.** Section 4.5.1 suggests a first page of about 200, continuing while the person scrolls or immediately if they sort, filter, group or search. *We assume:* we follow that, with the 20-page cap kept as the upper limit. *If different:* only memory use on small phones.

**13. Are overdue or due-date rules planned for Smart View? ANSWERED** (sections 3.7 and 5.1: none, not in the engine).

**14. Is a batch `record.actions` planned? ANSWERED** (section 4.5.1: not built; whether it is planned is for the BE owner, N5 covers it).

**15. Will two devices ever stop overwriting each other's saved views? ANSWERED for today** (section 2.8.1: no revision check; the safe client behaviour). **Whether a fix is planned is N3.**

**16. May an administrator delete someone else's record through `submissions.delete`? ANSWERED** (section 2.4.2 and capture `044-`: no, `forbidden`).

**17. How does a phone fetch a file shown in a row (`GET /api/sd/files/<id>`)? STILL OPEN.** Section 4.8 says the type is "sniffed from the first bytes", but we need: how the request is authenticated for a mobile client (a bearer token in a header?), what `Content-Type` and size limit the answer has, whether a range or a thumbnail is available, and which of the file ids in `files` the route accepts. *We assume:* a bearer token, bytes sniffed by us, no range. *If different:* previews of attachments in rows break or are slow. We build this late, so it is not urgent.

**18. Is the spreadsheet open and save (`smartview.sheet.*`) meant for mobile? PARTLY.** The commands are captured (`097-`, `098-`). The web reads the `.xlsx`/`.csv` in the browser, so a phone would need its own reader. *We assume:* not built on mobile. Please tell us if that is wrong.

**19. Please give a real `api.list` / `api.run` answer with parameters. STILL OPEN.** Only the "no API" and "API does not exist" refusals were captured. We need an answer with rows, a `columns` list, `total`, `truncated`, `cacheSec`, `refreshedAt`, `via`, an API with parameters (with and without defaults), and a `put` API (we assume it is never offered). *We assume:* the shape in section 2.6. *If different:* API sources cannot be built correctly. See N7.

**20. Should mobile ignore the Inbox-only source kinds (`work`, `approvals`, `reminders`)? ANSWERED by us.** We already have Tasks, Approvals and Notifications on the phone, so we ignore them. No answer needed unless you disagree.

**21. What exactly is the wording of the Overview totals? STILL OPEN.** Section 3.5 describes the Overview pane from the code, and the screen was not rendered. *We assume:* we build the Overview last, from the code description. See N10.

**22. Which people hold `smartview.configure`, and does `perm.mine` list it? PARTLY.** Section 7.3 says administrators always, and anyone an administrator grants it to (people, roles, designations). We still do not know whether `perm.mine` lists the permission. *We assume:* not needed, because the phone has no "Customize". *If different:* nothing breaks.

**23. Hidden fields: does `submissions.list` remove them, and can an ordinary person read the admin definition? ANSWERED** (section 5.4: no, the values are sent to every reader; the definition and its default are sent to anyone who can open the form). The decision whether this is intended is N1.

**24. Is a deep link or push for `#view` planned? ANSWERED** (section 1.3, E9: none exists). We keep the screens parameterised so a link could be added later.

**25. Are `ts` values epoch milliseconds, and should the phone format them in the device time zone like the web? ANSWERED** (section 3.8: yes, device time zone; the vectors were produced in time zone Asia/Calcutta and locale en-GB, which we note when we pin our tests).

---

## Part 2. Our 15 discrepancies

These are places where your document and the information we had, or the document and itself, disagreed.

**D1. `records.mine` continuation:** the first revision said "continue with `next`", while the earlier answers said `with` and `involved` give `next: null`. **ANSWERED** (section 2.4: the earlier answers were right).

**D2. Do events carry a status?** Your document said `data.record` is on `submissions_changed` and `ticket_assigned`; an older mobile document said no event carries status. **ANSWERED** (section 2.11: yes on `dev` since 16 Nov 2026, in no release; the older statement was true of released servers). The release question is N6.

**D3. `records.mine as:"team"`:** your document describes it (with `reports` and `team:{members, via}`), an older answer did not mention it. **PARTLY.** Documented and captured for a person with no reports (`025-`), but never with data (N8).

**D4. `records.summary`:** named as built in section 5.2, and nothing in our older material mentioned it. **ANSWERED** (captures `037-`, `038-`; dev only, #822).

**D5. The argument type `source`** is not in the server's list of argument types. **ANSWERED** (section 1.3.1: it exists only in the web client).

**D6. `#view` suggestions without `/cmdcomplete`:** every other `#` command gets suggestions from the server. **ANSWERED** (capture `101-`: the server answers `none` for `#view`).

**D7. `ai.enterprise` and `failed`:** the text said four parts can fail and be named in `failed`, while the example shows one `forms` array. **ANSWERED** (same as question 4).

**D8. Offline wording:** one section says there is no offline cache or banner, another says an IndexedDB cache is "specified, not built" with an unclear status. **PARTLY.** The two statements agree, but the status of the cache specification is still `[UNSURE]` in your document; we assume the web has no cache we could mirror. Only a note for you if that is wrong.

**D9. Hover titles and right-click:** your document says Smart View has no right-click menu and also mentions hover titles. **ANSWERED** (they do not conflict; on a phone we use tap and long-press).

**D10. Stale lines in the web's own `SMART_VIEW.md`:** the hidden-field paragraph (line 37 against line 100), "Share with everyone" in the menu, "no button that adds a record", a comment naming `smartview.history`, column width 64-800 against 48-1200, and "up to 3,000 rows, pages of 500". **PARTLY.** Section 7.4 lists them and says the code wins. They are open in the document itself ("not changed by this task"); we follow the code as you describe it.

**D11. An older plan we had** (from a PDF and an unmerged branch) assumed 3,000 rows, no realtime events, no record editing, and `datasource`/`list` sources. **ANSWERED** (10,000 rows and 20 pages, events exist, Add/Edit/Delete exist, those two sources are switched off). Nothing for you to do.

**D12. The JSON examples in revision 1 were not valid JSON** (they had `//` comments inside). **ANSWERED** (revision 2 pastes real captures).

**D13. `smartview.attrs` and `smartview.views` requests were given only as prose** (`{kind,name}`). **ANSWERED** (real captures `049-` to `066-`).

**D14. "Whoever may open a record may read it", against two known gaps in an earlier answer:** (a) an approver of an open stage or a notified person opens the record but `record.actions` answers `not_found` and the record is in no list; (b) a person with form-wide visibility lists the record but `submission.get` is refused. A Smart View row can therefore show a record that the record read refuses. **STILL OPEN.** Revision 2 does not say whether these were fixed. *We assume:* not fixed; the phone opens the record read-only and shows a plain message when a read is refused. *If fixed:* nothing changes for us. Please say if they were fixed and in which release.

**D15. A manager's `team` row:** your document says read-only; whether the person can edit or open it anywhere is unclear. **PARTLY.** Section 2.4.2 says a received record is not editable, and `team` rows are read-only. Without a capture with data (N8) we cannot confirm the row's fields. *We assume:* the same fields as a `with` row plus `team:{members, via}`.

---

## Part 3. New open items from revision 2

Please answer these first. N1 to N5 need a decision from the backend owner, not just a reading of the code.

**N1. Hidden fields are sent to everyone who may read the record (section 5.4). Is that intended? STILL OPEN, a decision for the BE owner.** Their values come in `submissions.list` rows, in `records.mine` rows (by the code), and with the field's `default` in `tstruct.user.get` for any colleague who can open the form; only `ai.enterprise` leaves them out. The three options in your document are: keep it and document "hidden is not secret"; strip hidden values for people other than the owner and administrators (a breaking change that touches `values`, `tstruct.user.get`, `records.*`, e-mails and published APIs); or make "Show hidden fields" the creator's only again. *Meanwhile the phone:* draws the same fields as the web, never draws hidden ones, never logs or stores them, and never calls them secret. It builds "Show hidden fields" last, or not at all, until you decide.

**N2. Please fix `records.mine {as:"raised"}` (section 2.4.1). STILL OPEN.** With `limit: 2` the author of four records got two rows and `hasMore:false`, so two records could never be reached. *Meanwhile the phone:* always asks `raised` with `limit: 200`. Could you tell us when it is fixed and in which release, so we know when we can stop doing this (it is harmless to keep)? One more point: if a person has more than 200 raised records in one chunk, we cannot tell whether `limit: 200` is enough; is the "chunk is at most 200 entries" statement of section 2.4.1 exact?

**N3. Please add a revision check to saved views (`rev` echoed on `smartview.views.save`, with a `stale` error, as `record.status` already has). STILL OPEN, a decision for the BE owner.** Today two devices overwrite each other silently (captures `061-` to `063-`). *Meanwhile the phone:* reads the list immediately before every save, merges by view id, sends the merged whole list, warns when the list changed in the meantime, and uses UUID-like ids. A race of a few seconds remains. Is a `rev` planned, and when?

**N4. Please add `canEdit` (and `canDelete`, or an `actions` list) to `records.mine` rows and to `submissions.list` rows. STILL OPEN.** Today `canEdit` exists only on `submissions.list` rows, `canDelete` nowhere, and the delete rule is computed by the client (author, or owner of the structure). *Meanwhile the phone:* treats a received record as not editable and not deletable, offers only the workflow items that `record.actions` enables, and applies the web's own delete rule for records from `submissions.list`, the server re-checking. Is this planned?

**N5. Server-side options we would use if they existed: a "changed since" read on `submissions.list`, a batch `record.actions`, a batch `submission.get`, and filter/sort/group/aggregate. STILL OPEN.** Your document says none exists. We ask only whether any is planned, because the answer changes how much we build on the phone.

**N6. Which release will carry `data.record` and `records.summary` (#822, on dev since 16 Nov 2026)? STILL OPEN.** The phone can patch one row without any read as soon as an environment we test against has it; until then it uses `submission.get` for one event and a quiet re-read for a reconnect. Is `data.record` also sent to a person who only sees the record as a manager or through `with`? (Section 2.11 says "for a person who may read the record"; we want to be sure that includes those.)

**N7. Please capture a real `api.run` and `api.list` with rows (see question 19). STILL OPEN.**

**N8. Please capture a manager's `records.mine {as:"team"}` with data. STILL OPEN.** We want the row fields, `reports`, `team:{members, via}`, and a real `next` across two pages.

**N9. Please capture a share to a **group**, and what a member of that group then receives from `smartview.views`. STILL OPEN.** (A share to a person who cannot open the source is captured, `087-`; a group is not.)

**N10. Screenshots or a rendered description of the web screens. STILL OPEN.** Your document says the screens were not rendered, so every UI string and the phone-card layout come from the code and CSS. We would like screenshots (or a list of the visible texts as the browser shows them) of: the source picker, the table in card mode at 375 px width, the filter panel, the Columns dialog, the share dialog, an empty state and an error state. Your `SHOTS=<folder>` end-to-end script is the way you mentioned. It would let us match wording and layout by eye rather than by reading code.

Thank you again. None of these block the first phase we are building (opening a structure's records from `#view`); N1, N3 and N4 shape later phases and what we promise users.
