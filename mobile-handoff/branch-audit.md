# Branch audit: QR joining and the signed-in person

Audit only. No behaviour changed. Sources: the BE branch audit (summarised in the task), `reference/qr/QR_CODES_FOR_MOBILE.md`, `mobile-handoff/qr-flow.md`, `qr-scan-audit.md`. Status: **ok / gap / broken**. Evidence: **code** = read in code, **test** = covered by `test/connect/branch_link_test.dart` (new, 20 tests, all pass), **NOT verified** = needs the server or a phone.

## Summary table

| # | Item | Status | Evidence | Where | Proposed fix | Size |
|---|---|---|---|---|---|---|
| 1a | Branch from https org link `?branch=` | ok | code, test | `connect_code.dart:127` (`_branch`) | none | |
| 1b | Branch from person link `&branch=` (with `?org=`) | ok | code, test | `connect_code.dart:121-128` | none | |
| 1c | Branch from `connectum:CODE?branch=` and `connectum://connect/CODE?branch=` | ok | code, test | `connect_code.dart:101-109` | none | |
| 1d | Branch from App Links | ok | code (not run on a phone) | `deep_link_service.dart:122,128` → `receive` → same parser | confirm with `adb ... -d "https://connectum.app/connect/CODE?branch=Head%20office"` | S |
| 1e | Pasted link/code field | **fixed** | code, test | `connect_code.dart:72` (`_bare` regex) | A bare `CODE?branch=X` (no scheme/host) is rejected `notConnectLink`; full links and `connectum:` work. Accept `CODE?...` by prefixing `connectum:` | S |
| 1f | Scanner | ok | code | scanner calls `ConnectLinkParser.parse` then `receiveCode` | none | |
| 1g | Decoding (%20, `+`, accents), case kept, trim, empty ignored | ok | test | `Uri.queryParameters` + `_branch` | none | |
| 1h | Branch over 60 chars or with control characters | gap | test | `connect_code.dart:127-131` | Branch is silently dropped (code still accepted). Fine as a label; documented | |
| 1i | Space written as `+` when we rebuild the link | **fixed** | test | `ConnectCode.linkText` `connect_code.dart:24-30` | Dart writes `branch=Head+office`. Sent to `connect.lookup/scan` as the "code" text and to the GET. Server decode of `+` unknown (BE question 1). Safe fix: build the query with `%20` | S |
| 2a | Play referrer reads `connect_branch` | ok | code, test | `install_referrer.dart:111-125` | none | |
| 2b | Pending target holds code, org, branch; saved with 24 h expiry | ok | code, test (round trip, expiry) | `deep_link_service.dart:41-43,233-246,195-211` stores `linkText` + timestamp | none | |
| 2c | Branch kept across copies (DeepLinkService, resume after sign-in, switch, install) | ok | code | pending is one `ConnectCode`; `linkText` carries branch; `claimInvite` also keeps `branch` (`auth_repository.dart:286-307`) | Not exercised end to end (needs the store; only the round trip is tested) | M to cover |
| 2d | iOS clipboard `connectum:CODE?org=&branch=` | NOT verified | n/a | iOS not built | check when iOS is built | |
| 3a | Branch sent to `connect.lookup/scan` and the landing GET | ok | code | `connect_repository.dart:25` (`linkText`), `auth_repository.dart:277-281` (`branch` query) | none | |
| 3b | `branch` read from the answer | ok | code, test | `connect_card.dart:32,40` reads `enterprise.branch` | none | |
| 3c | `branchUnavailable` read | **fixed** | code, test (pins "no branch") | not parsed anywhere (`grep branchUnavailable lib` is empty) | Parse the flag (`ConnectCard.isBranchUnavailable`); show a light notice on the confirm pane (`confirm_pane.dart` `_Note`) and the connect-target pane: "This branch is no longer active. You will join the organisation." Never block. Needs BE answer 2 (where the flag sits) | S |
| 3d | Branch shown on the confirm card | ok, wording differs | code | `confirm_pane.dart:83`, `connect_target_view.dart:183` show a place tag. The web says "Join <org> (<branch>)" | optional wording change | S |
| 3e | Member already in the org: "You are in <org> (<branch>)" | gap (wording) | code | `confirm_pane.dart:131-135` says "You're already in {name}." plus the tag in the header | acceptable; or add the branch to the sentence | S |
| 3f | Person card (`connect.lookup` type person) branch | **fixed** | code | `ConnectPerson` (`connect_lookup.dart:5-30`) has no `branch` although the server sends `user.branch` | read and show it, empty = hide | S |
| 4a | Join screen exists | ok | code | `connect_controller.dart:491-529`; the only `auth.join` call. No standalone sign-up in the QR flow: the person has an account first (OTP), then joins organisations | | |
| 4b | Sends `connectBranch` | ok, with a caveat | code | `auth_repository.dart:333`, called with `found.branch` (`connect_controller.dart:504`) = the name as the **server spelled it** from the card, not the exact QR text. Fine because it is the validated name; when the branch is unavailable the card has none, so nothing is sent (same result as the server dropping it) | none | |
| 4c | Reply `active` | ok | code | `_afterJoin` `connect_controller.dart:529-549` → `ConnectOutcome.joined` | | |
| 4d | Reply `pending` / `nextStep: approval` | ok | code | same; `awaitingApprovalFrom` read as a count or text (`_approvers`, :551) and `welcome` shown | `_approvers` is private; add a test if exposed | S |
| 4e | `already` error | ok | code | `connect_controller.dart:~512`: refreshes `/me`, then shows the member pane | | |
| 4f | `rate_limited` | ok | code | wait text from `retryAfterSeconds` | | |
| 4g | `link_existing` | **missing** | code | no match in `lib` | Needs BE doc (BE question 4) | M |
| 4h | Employee-code claim (`isEmployee`, `employeeCode`, `code_required`) | **missing** | code | `isEmployee: false` hard coded (`auth_repository.dart:316,331`); `code_required` and `employeeSignup` not handled | Add an employee-code step when the org has `employeeSignup`. | L |
| 4i | Extra required fields | gap | code | `connect_controller.dart:~480-488`: a category with `requiredFields` shows "needs more details than the mobile app supports yet" and stops | Render the fields with the existing form components | L |
| 4j | Waiting-for-approval screen | ok | code | outcome pane `requestSent` with approvers; `_Member` pending text (`confirm_pane.dart:131-135`); Enterprises screen shows pending rows and polls | | |
| 4k | `pending_approval` / `rejected` at sign-in | ok | code | `api_messages.dart:26-29`; `enterprises_controller.dart:301,329`; invite steps `waiting` / `rejected` (:214-218) | `GET /me` is how a pending person finds out: `membershipStatus` (`auth_repository.dart:238`) refreshes it | |
| 5 | Branch-bound sign-up form | **missing** | code | the app has no branch field in any join/sign-up form; `branchBound` appears nowhere in `lib` | When the category is `branchBound` (from `GET /enterprise/{id}` `onboarding.<cat>.branchBound`): show a branch picker from `branches[]`, prefill from the scanned branch (case-insensitive match against active branches), required, existing branches only. Without it a `branchBound` category will be refused by the server | M |
| 6a | Signed-in person's own branch read anywhere | not applicable | code | no `branch` in profile, `/me`, identity, chat lists. `Ticket.branch` (`ticket.dart:219,354`) defaults to `''` and is not shown with `null` | nothing can crash today; any new use must treat null/empty as "no branch" | |
| 6b | Anything that groups or filters by the person's branch | ok (none) | code | no match for `.branch` use in lib outside QR/connect | | |
| 7a | Picker only changes the payload, code stays the org code | ok | code, test | `qr_models.dart:85-103` `withBranch` uses `branch.payload`; `qr_controller.dart` `copyCode` | | |
| 7b | Re-fetch on open | ok | code | `QrRepository.load` calls `connect.my` on every open; `load()` clears the chosen branch (`qr_controller.dart:53`) | | |
| 7c | Branch deactivated after the sheet opened | gap (minor) | code | list is only refreshed on open or Try again; a branch removed meanwhile still draws its payload, which the server treats as `branchUnavailable` (still joins the org) | acceptable; could re-load on app resume | S |
| 7d | Picker shown only when `branches` present, default "Whole organisation" | ok | code | `qr_view.dart:75-91` (no branches or not an admin: no picker) | | |
| 8 | Tests | ok for parsing, referrer, round trip, card, expiry; gaps below | test | `test/connect/branch_link_test.dart` | see "Tests not possible without refactor" | |

## Tests added

`test/connect/branch_link_test.dart` (20 tests): branch from https org link, person link, both custom schemes; `%20`, `+`, accents; case kept; trim; empty ignored; too long and control characters; bare typed code; `linkText` round trip with spaces, accents, `&`, `+`, `/`; space written as `+`; referrer with `connect_branch`, org-only branch, fully encoded referrer, empty branch, claim token; pending round trip, 24 h expiry, `stepFor`; card branch read, empty branch, `branchUnavailable` (pins today's behaviour: no branch, no flag).

Tests not possible without a refactor (no code changed): the `_approvers` / `_afterJoin` reply handling (private, tied to `ConnectController` and the store), `DeepLinkService.startWith` storing in secure storage (needs a `SessionStore` fake), and the join-error branches (`already`, `rate_limited`).

## Fixed (small branch fixes)

1i: links and the landing GET are built with `%20` (`ConnectLinkParser.link` / `query`). 3c: `branchUnavailable` is read (top level or inside `enterprise`/`user`), shown once per lookup through `AppNotices`, and the branch is dropped from later calls in the flow. 1e: bare `CODE?branch=X`, `CODE?org=Y&branch=X`, `CODE?org=Y` are accepted. 3f: the person card shows "@username - designation - department - branch". Tests in `test/connect/branch_link_test.dart`.

## What is missing for "join with branch" end to end

1. `branchUnavailable` is not read, so no notice (3c).
2. `branchBound` categories: no branch picker or prefill, so joining such a category cannot be completed in the app (5).
3. Employee-code claim and `link_existing` are not handled (4g, 4h); categories with required fields are refused (4i).
4. Person card does not show the person's branch (3f).
5. `+` in the rebuilt link (1i) is an unconfirmed risk for names with spaces, the most common case ("Head office").
6. Wording differs from the web ("Join <org> (<branch>)", "You are in <org> (<branch>)") (3d, 3e).

Order of work: 1i (S), 3c (S), 3f (S), 1e (S), 5 (M), 4h (L), 4i (L), 4g (needs BE).

## Questions for the BE

1. Does the server decode `+` as a space in `branch=` for `connect.lookup/scan`, the landing GET and `/join` `connectBranch`? Our rebuilt link uses `+`; the web's links use `%20`.
2. Where does `branchUnavailable` sit in the answer: top level, or inside `enterprise`? (The handoff docs only show `enterprise.branch`.)
3. Does a person card (`connect.lookup` type person) carry `branchUnavailable` too, or only the organisation card?
4. What is `link_existing` in the join reply, and when does it appear? It is not in `mobile-handoff/` or the Postman collection.
5. A person joined without a branch (not `branchBound`, branch not a required field): is the missing `branch` in `/me` and `user` objects `null`, absent or `""`? Which screens on the web show nothing then?
6. When a branch is deactivated after a person joined, does their stored `branch` stay, change to null, or the old name? Same for deletion.
7. Do branch QR codes expire (asked before in `qr-flow.md`)? The 24 h expiry is only our pending-link rule.
8. For the Play referrer: is `connect_branch` percent-encoded once (as `Head%20office`) or twice?

## Checks run

`flutter test`: 434 passed. `flutter analyze` on `lib` and `test/connect`: 2 existing infos in `lib/data/models/form_entry.dart:97,252` (not touched). No commit, nothing run on a phone or the server.
