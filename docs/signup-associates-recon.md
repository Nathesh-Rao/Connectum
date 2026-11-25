# Sign-up, join and invite: web vs mobile (associates and affiliates)

Sources read (web repo, read-only): `docs/ASSOCIATES_AND_AFFILIATES_SPEC.md`, `docs/DEV_API_CHANGES.md` (24 Nov 2026), `JoinWizard.jsx`, `AssociatesStep.jsx`, `AssociateFields.jsx`, `AdminUsersPanel.jsx`, `tests/frontend/signupCards.test.mjs`, `sd_ident.erl` (`join`, `join_check`), `sd_users.erl` / `sd_users_claim.erl` (`check_register`, `member_category`, `affiliate_branch`), `sd_onboarding.erl`, `sd_org.erl` (`public/0`).

## 1. Web flow (JoinWizard), screen by screen

The wizard is for a signed-in identity joining one organisation (no password). Its data is `GET /api/sd/enterprise/<id>` (public): `name`, `categories[]` (names, active only), `affiliates[]` (`{name, category, branches[]}`, active only), `branches`, `departments`, `designationRules`, `onboarding{<category>:{requireApproval, requiredFields[], branchBound, welcome}}`, `employeeSignup{codeRequired}`.

| Step | Shown when | Content | Local validation | Sent to `join/check` | 
|---|---|---|---|---|
| type "Who are you here?" | always | Card "I'm an employee of X" (always). Card "I'm an associate" only if the org has categories or affiliates; its text lists up to 4 category names | none | nothing |
| employee | employee kind | employee code, or branch + department + designation | code required if `codeRequired`; else code or all three | `{isEmployee:true, employeeCode?}` |
| category | associate and org has categories | searchable list of categories (search box past 6) | "Choose what describes you." | `{isEmployee:false, category}` |
| affiliate | associate and org has affiliates | "Are you from one of our partner organisations?": search box always, row "No, I'm an individual" (only if org has categories, pre-selected by default), affiliate rows; a branch pick when the affiliate has more than one branch; otherwise the hint "Branch: NA" | with categories the affiliate is optional; without categories "Choose your affiliate."; more than one branch and none chosen: "Choose your branch." | `{isEmployee:false, category?, affiliate?, affiliateBranch?}` (branch only when the affiliate has more than one) |
| details | always | name, username, mobile, country, city, PIN, plus the category's `requiredFields` (address, gender, dob, education, skills) | name required (unless claiming), phone check, required fields "This is needed." | `{mobile?, username?}` + `final:true` + `category` (not the affiliate) |
| review | always | enterprise, you are, category, affiliate ("None (an individual)"), branch, name, e-mail, mobile | none | nothing |

Flow order for an associate: `type, [category], [affiliate], details, review`. A check answering `{ok:false, fields}` shows `fields` under the inputs and stays on the step; a failed or unreachable check (not `rate_limited`) shows the message and moves on anyway ("join decides at the end"). The last call is `POST /api/sd/join` with the payload below; an error with `details.fields` goes back to the details step and every error shows `friendly(error)` in a red alert.

`join` payload (associate): `{isEmployee:false, name?, mobile?, username?, connectBranch? (scanned), country?, city?, pin?, category, affiliate?, affiliateBranch? (only if >1 branch), <requiredFields>}`. Server: `join_check` runs `sd_users_claim:check_register` (affiliate must exist and be active: "Unknown affiliate organisation." / "That affiliate organisation is deactivated."; more than one branch needs one: "Choose the branch of the affiliate." / "That branch doesn't belong to the chosen affiliate."; with `final:true` and a category it runs `check_registration`). `join` stores the person with `category` and, when named, `affiliate`. No category sent plus an affiliate: the affiliate's category is used. A person who names an affiliate always needs approval. A person the org already has under that e-mail is linked at once (`link_existing`).

Invite and admin (web): `AssociatesStep` (Setup wizard) and the Invite tab send `users.invite {name, email, mobile?, isEmployee:false, category, affiliate?, affiliateBranch?, custom?}`; `AdminUsersPanel` sends `admin.user.update` with changed keys `category`, `affiliate`, `affiliateBranch`, `custom`. The fields shared are `AssociateFields` (category select, affiliate select with "None (an individual)", branch select) and the org's own fields from `admin.cfg.fields {kind:"associates"}`.

## 2. Mobile flow today

- Account creation (`AuthenticationController._register`): `POST /register/start {username, email, mobile?, country?, state?, city?}` then `/register/verify`. No category or affiliate is sent. The web's `register/start` is the same call; the category/affiliate choice lives in join, not here.
- Join: only in the "Join another enterprise" sheet (`ConnectController`, `ConfirmPane._JoinForm`), reached by scanning or typing a code, or by a link. One screen: category chips from the connect card (`GET /connect/<code>`), a "Join X" button.
- Send: `GET /enterprise/<id>` only to read `onboarding[category].requiredFields`; if not empty the sheet says "Joining as X needs more details than the mobile app supports yet." and stops. Then `POST /join/check {enterprise, isEmployee:false, category}`: if `fields` is not empty its first value is shown; then `POST /join {enterprise, isEmployee:false, category, connectBranch?}`. Errors: `already` refreshes memberships, `rate_limited` shows a wait, others show `ApiMessages.of(e)` as red text under the chips.
- Result: `pending` or `nextStep:approval` shows "request sent", otherwise "joined" (`DonePane`).
- There is no employee path, no affiliate, no details step, no invite form, no admin editing.

## 3. Differences

| # | Web | Mobile | Plan |
|---|---|---|---|
| 1 | Step "type" with an Associate card | none, straight to category chips | build: Associate card step |
| 2 | Employee card, employee code step | none | not in this task (medium); Employee card is not shown |
| 3 | Category step (searchable list, "Choose what describes you.") | chips, no message | build: step with the same rule and text |
| 4 | Optional affiliate step, "No, I'm an individual" default, search, branch step, "Branch: NA" | none, `affiliate` never sent | build |
| 5 | Check after each step with the partial body | one check at the end, category only | build: check after the category step and after the affiliate step with the web's partial bodies |
| 6 | `join` sends `category` plus `affiliate` and `affiliateBranch` | `category` only | build |
| 7 | Server `fields` shown under the input | first value shown as one line | build: shown under the right step, fields `category`, `affiliate`, `affiliateBranch` |
| 8 | Unreachable check does not block | any check error shows and stops | build: same as web (not for `rate_limited`, not for `unauthenticated`) |
| 9 | Details step (name, username, mobile, country, city, PIN, requiredFields) | none; account values are used; refuses when `requiredFields` is not empty | keep the old refusal (large to port) |
| 10 | Review step | none | build: review of category, affiliate, branch before sending |
| 11 | Progress "Step i of n" | none | build |
| 12 | `final:true` on the details check | never | not sent (a branch-bound category would be refused because mobile has no branch pick; the join itself still checks) |

## 4. Where mobile sends these commands

- `register`: `AuthRepository.startRegister` (`/register/start`), `verifyRegister`. No category or affiliate: nothing to change.
- `join/check`: `AuthRepository.joinCheck` (called only from `ConnectController.join`).
- `join`: `AuthRepository.join` (called only from `ConnectController.join`; `SeedConnect.join` is the demo).
- `users.invite`: not sent anywhere in mobile.
- `admin.user.update`: not sent anywhere in mobile.
- `admin.cfg.fields`: not sent anywhere in mobile.

## 5. Web features of this notice that mobile lacks

| Feature | Size | What it takes |
|---|---|---|
| `users.invite` with `category`, `affiliate`, `affiliateBranch`, `custom` (Invite tab, Setup > Associates add form) | medium | an admin screen with the shared fields (category list, affiliate list, branch), name/e-mail/mobile, a send with the 30 s timeout, the organisation's lists from `admin.cfg.list`, permission gating by `perm.mine` |
| `admin.user.update` editing `category`, `affiliate`, `affiliateBranch` (empty affiliate = individual) | medium | a people list and an edit screen (mobile has no admin people list now), changed keys only, scope rules |
| Custom fields for outside people (`admin.cfg.fields {kind:"associates"}`, sent as `custom`) | medium | a renderer for the org's field definitions (a form field row set exists for forms and could be reused) plus validation |
| Setup > Associates step, `admin.setup.status` tenth step `associates` | large | the whole Setup wizard does not exist on mobile |
| Affiliate `contactName` / `contactEmail` and the `contactInvite` reply (`admin.cfg.save` kind affiliates) | medium | an affiliates admin screen; mobile has no org setup screens |
| `org_associate` structure and `#import` columns | small on mobile | no mobile work: server and web builder; the records are admin-only |
| `admin.perm.grant` `affiliates` rule, `perm.mine` change | none | `perm.mine` is already read as a set of names; only a permissions admin grid would be new (large, not planned) |
| Employee card and code claim in the join wizard | medium | code step, branch/department/designation pickers, details step |
| Details step with `requiredFields` for associates | medium | name, username, mobile, country, city, PIN, address, gender, dob, education, skills inputs |
| Welcome mails with store icons and tutorial link | none | server only |

Not built in this task: every admin item above.
