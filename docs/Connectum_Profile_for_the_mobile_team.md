# Connectum: Profile section, hand-off for the mobile team

Written 27 Nov 2026 from the code and docs of `origin/dev` (checked against `origin/main`, latest tag `v0.2.77`). Paths are relative to `connectum/`. Everything here is from code or docs; what could not be confirmed is in the last section.

Reference screens (web): `chat-app/features/connectumChat/components/modals/ProfileModal.jsx` (own profile, 3 tabs), `.../UserProfileViewModal.jsx` (someone else's profile), `.../PersonHoverCard.jsx` (hover card, desktop only), styles `.../modals/profileStatus.css`, helpers `utils/presence.js`, `utils/profileDraft.js`, `utils/regenerateQr.js`. Related mobile contract (read it, not repeated here): `docs/MOBILE_CHAT_HEADER_PICTURES_SEARCH.md` (chat header, pictures, Shared tab, search). QR landing and `connect.*`: `docs/MOBILE_QR.md`. Presence change note: `docs/DEV_API_CHANGES.md:27-29`.

Release state: presence field, `/setpresence`, "Regenerate QR code" wording and Escape-asks-before-discarding are in **v0.2.75, v0.2.76 and v0.2.77** (checked by grepping each tag) and not in v0.2.74. "A person's circle opens their profile" and the new chat header are **on dev only** (not in v0.2.77).

---

## 1. Purpose and entry points

The profile is where a signed-in person sets how they look to others (picture, presence dot, status message), edits private personal details, and shows or regenerates their personal Connectum QR code.

| Entry | What opens | Source |
|---|---|---|
| Click picture or name in the left chats panel (title "Your profile and photo") | own profile (`ProfileModal`) | `components/WorkspaceChatsSlider.jsx:204-210`, event in `utils/ownProfile.js:2-3`, handled `ConnectumChatScreen.jsx:147-150` |
| `#profile` with no name, or with your own username | own profile; also calls `me` (the answer is not used by the modal) | `chatActions/openUserProfile.js:9-15`, `chatActions/routeHashCommand.js:172-173` |
| `#profile <username>` | other person's read-only profile (`UserProfileViewModal`) | `openUserProfile.js:16-29` |
| Tap a person's circle beside a message or in a list; hover card (mouse only) with buttons "Message" and "View profile" | other person's profile, or the own one if it is you | `components/PersonHoverCard.jsx:63-67,125-132`; dev only (#1040) |
| Phone bottom bar, Profile tab | **not** the profile modal: a sheet titled "Profile" with the pill's other keys, "Settings" and "Sign out" | `components/ProfileSheet.jsx:42-62` |

Chat header (picture, Chat / Shared tabs, search; #1041, #1043) is described in `docs/MOBILE_CHAT_HEADER_PICTURES_SEARCH.md` section 1. That doc says: on mobile a tap on a person's circle opens their profile with no new call, "you already hold their name, designation, status, presence" (line 12); the hover card is a desktop habit and needs no mobile equivalent.

Other person's profile (`UserProfileViewModal.jsx`): title "Profile", subtitle "Enterprise directory details & credentials"; picture (tap opens it larger), name (`name`, else `username`, else "Colleague"), `@username`, designation badge (`designation`, else `role`, else "Connectum member"); card "Status Message" (`status`, else "Active on Connectum"); card "Enterprise Department" (`department`, else "Connectum member", then ` • `, `branch`, else the literal "Bangalore HQ"); card "Contact Coordinates" only when `email` or `mobile` is known; buttons "Close" and "Send Direct Message" (lines 11-14,56-114). It does not render presence. The data comes from already loaded lists plus the last `profile` event (`openUserProfile.js:16-28`); no server call is made for it.

## 2. Screen anatomy, own profile (`ProfileModal.jsx`)

Window: title "Your Profile", subtitle "Profile status, details and your Connectum QR", close button "x" (aria-label "Close modal") (lines 228-244). Width max 520 px, 92 vw. Tabs (role tablist, aria-label "Profile sections"), in order: **Status**, **Details**, **My QR Code** (lines 19-23, 247-253). Default tab is Status.

**Header card (shown above every tab)** (lines 257-290):
- Picture 72 px (initials letter in a coloured circle when no picture; colours come from the name). With a picture, tapping it opens it larger. Without one, the circle is a button (title "Add a photo").
- Name (`me.name`, else `username`), then `@username` and, if present, ` • designation` (else ` • role`). Name, username and designation are read-only here; there is no edit control for them.
- Presence pill: dot plus the label of the current presence (title "How your presence shows to others").
- Role tags from `profile.get` `roles` (read-only), shown after the details load.
- Buttons: "Remove" (only with a picture, red), and "Add photo" / "Change" / "Uploading..." (busy, disabled).
- An error line (role alert) under the card for picture errors.

**Footer** (lines 524-538): "Close"; on the Status tab also "Save Status", and a left-aligned "Unsaved changes" note when the presence or the status message differs from what is saved. The Details and My QR Code tabs have no footer Save.

**Save / Close / Escape**
- "Save Status" always enabled. It sends only changed parts (section 3), closes the window and toasts "Profile updated successfully" (`ChatModals.jsx:309-334`). It saves status and presence only; the Details tab has its own button.
- Pressing Enter in the status box saves when something changed (line 326).
- "Close" and the "x" close at once and discard unsaved status/presence/details with no question (lines 241, 526).
- **Escape** closes, but first asks if anything is unsaved (status, presence, or any of address, gender, dob, education, skills): dialog "Discard your changes?" / "What you changed in your profile has not been saved." / buttons "Discard" (danger) and cancel (lines 219-223, `utils/profileDraft.js:2-5`). The picture is not part of this check because it is saved at once.
- Tab switches keep the unsaved text of the other tabs (state lives in the modal).

**Phone width** (`profileStatus.css:63-69`, breakpoint 640 px): the header card wraps and its buttons move to their own full-width row, right-aligned; panel padding 16; tabs stop stretching and scroll sideways. Touch rule for the product: 44 x 44 px hit areas at 640 px and below (`docs/UI_DESIGN.md:190`, `docs/THEME.md:116`). The CSS gives the chips and picture buttons a visible height of 36 px; whether an invisible 44 px area is added in `touchTargets.css` was not checked. Mobile should simply use 44 pt targets.

**Tokens and colours** (named, not copied): card `--color-white`, hairlines from `--connectum-text-main` at low opacity, accent `--color-primary`, muted text `--connectum-text-muted`, danger `--tone-red-solid` (`profileStatus.css:5-7`). One light theme only; no dark mode (`docs/THEME.md`). Presence dot colours below.

### Status tab (lines 293-346)
Three blocks, in this order:
1. **Presence**, helper text "The dot next to your name. It stays until you change it." Five chips (role group, `aria-pressed`): Available, Busy, In a meeting, Away, Do not disturb. The chosen one shows a check mark and a coloured dot. Choosing a chip changes presence only.
2. **Status message**, helper "Shows under your name in the chats panel." Text box with placeholder "What's on your mind?", pencil icon, hard limit 140 characters, counter "n/140" (bold from 130), clear button (aria-label "Clear status") when not empty. Control characters (0x00-0x1F, 0x7F) are removed as the person types; text is cut at 140. Typing changes the message only.
3. **Preview**, a row like the chats list: 44 px picture with the presence dot, name, and the message or the italic "No status message".

### Details tab
See section 4. My QR Code tab: section 5.

## 3. STATUS in detail: presence and message are two fields

Added 26 Nov 2026 (BUG-017, PR #1023, released in v0.2.75). Before it, the presence label was written into the status text. Now:

| | Presence | Status message |
|---|---|---|
| Wire values | `available`, `busy`, `meeting`, `away`, `dnd` (lower case, exactly) | free text, trimmed, max 140 chars, no control characters |
| Labels | Available, Busy, In a meeting, Away, Do not disturb | (the text) |
| Set with | `/setpresence <value>` | `/setstatus <text>` |
| Cleared by | cannot be cleared; stays until changed, not reset on sign-out, no automatic away | bare `/setstatus` (or only spaces) clears it; everyone then gets `status: null` |
| Error | `{"type":"error","cmd":"setpresence","code":"invalid_presence","text":"Presence must be one of: available, busy, meeting, away, dnd"}` for any other word, bare command, extra words, control characters; nothing changes | `{"type":"error","cmd":"setstatus","code":"invalid_status","text":"Status is too long or has invalid characters (max 140 characters)"}` |
| Success | `{"type":"ack","cmd":"setpresence","ok":true}` then a `profile` event to everyone | `{"type":"ack","cmd":"setstatus","ok":true}` then a `profile` event |

Sources: `docs/CHAT_PROTOCOL.md:128-132`, `connectum-backend/src/http/chat_web.erl:917-952`, `docs/DEV_API_CHANGES.md:27-29`, labels `utils/presence.js:3-10`, sending `chat-app/services/connectumSocket.js:615-628`. Sent as plain WebSocket text lines, for example `/setpresence meeting`, `/setstatus In the office until 5`. The status string is trimmed and cut to 140 by the web before sending (`connectumSocket.js:616-618`).

**`profile` event** (`chat_web_send.erl:308-311`, `docs/CHAT_PROTOCOL.md:199`):
```json
{"type":"profile","user":"alice","avatar":"/uploads/<name>","status":"In the office","presence":"busy"}
```
`avatar`, `status`, `presence` are each a string or `null`. It fires: when a person changes picture, status or presence (to everyone online; in strict mode only to the person and those connected with them, `chat_web.erl:508-513`); on connect, for yourself and for known people (online, DM partners, connections), capped at 300 profiles (`chat_web.erl:366-378`, `MAX_INITIAL_PROFILES` line 365); and as the answer to `/getprofile <username>` (`chat_web.erl:953-955`). `presence` is `null` when the person never chose one.

**Showing presence (client rule, `utils/presence.js:25-27`)**: use `presence` if it is one of the five words; otherwise derive it from the status text, never writing the derived value back: text containing "do not disturb" or equal to "dnd" -> dnd; contains "meeting" -> meeting; "busy" -> busy; "away" or "offline" -> away; empty or anything else -> available (lines 15-23). `DEV_API_CHANGES.md:29` asks the app to do the same and to stop writing a preset's label into the status text.

**Web handling of the event** (`chatEvents/workspace.js:155-188`): for others it stores avatar, status, presence (null when absent). For yourself, a missing `presence` keeps the one you have; a `null` status clears your status (also on another device).

**What is sent on Save** (`ChatModals.jsx:309-334`): status is sent only if it differs from the saved one; presence only if the person changed it (`presence !== presenceOf(currentUser)`). So a person who never chose a presence and saves does not write a presence. Order: `/setstatus` first, then `/setpresence`. The picture is re-sent with `/setavatar` when there is one.

**Dot colours** (`styles/07-topbar-and-sliders.css:8-30`, `components/avatarTools.css:77-82`, `profileStatus.css:72-73`):

| Presence | Dot | Online ring in the list |
|---|---|---|
| available | the app's default online dot (green per the CSS comment) | `--tone-green-solid` |
| busy | `--color-error` | `--tone-red-solid` |
| meeting | `--color-primary` | `--color-primary` |
| away | `--tone-violet-solid` | `--tone-violet-solid` |
| dnd | `--color-error` (same as busy) | `--tone-red-solid` |

**Where it shows**: other people's rows in the chats list show a ring and dot **only while the person is online**, coloured from their presence (`WorkspaceChatsSlider.jsx:377-383`); the hover card likewise only for online people (`PersonHoverCard.jsx:99-115`). Your own row in the left panel always shows your dot (title: your status text, else "Active", line 207). In the profile, your dot is always shown.

## 4. Details tab

Private note at top: "Personal details are private to you and organization administrators." (line 352). Load: `profile.get` when the window opens; save: `profile.update`. Both are normal `{action, data}` calls, level user (any signed-in person, own record only) (`sd_cmds.erl:195`, `sd_cmds_people.erl:295-304`).

| Field (label) | Control | Key | Web limit | Server rule (`sd_users.erl:819-823`, `sd_users_employee.erl:428-515`) |
|---|---|---|---|---|
| Gender | select: "Select gender..." (empty), Male, Female, Other, Prefer not to say | `gender`: `male`, `female`, `other`, `prefer_not_to_say` | list | same four values; null or "" clears; else `invalid` "gender must be one of: male, female, other, prefer_not_to_say." |
| Date of Birth | date picker, max today | `dob` `YYYY-MM-DD` | no future date | real date, 1900 to today; `invalid` "dob must look like 2001-04-23." / "dob must be a real date between 1900 and today."; null or "" clears |
| Residential Address / City | text, placeholder "Street, City, Postal Code" | `address` | 200 chars | max **200 bytes**; `invalid` "address is too long (max 200)." |
| Education / Degrees | text, placeholder "e.g. B.Tech Computer Science, MBA" | `education` | 150 chars | max **120 bytes**; `invalid` "education is too long (max 120)." (web allows more than the server) |
| Skills & Competencies (comma separated) | text, placeholder "e.g. React, Erlang, Product Management, UI/UX" | `skills` (list of text) | 300 chars | at most 30 skills, each 40 bytes or fewer, duplicates ignored (case-blind), blanks dropped; `invalid` "At most 30 skills." / "Each skill must be 40 characters or fewer." |

Control characters are stripped and text is trimmed server-side. Also accepted by `profile.update` but not shown in the web profile: `state` (max 80), `city`, `country`, `pin` (`sd_users_employee.erl:517-523`; limits for these three not read). Read-only here and shown elsewhere: `roles` (header tags), name, `username`, designation. Nothing else can be changed through `profile.update` (anything else is ignored; no recognised key gives `invalid` "Nothing to change. Send any of: address, gender, dob, education, skills, city, country, pin.").

**Request** `profile.update {address?, gender?, dob?, education?, skills?}` -> `{ok:true, data:{profile:{...full own record, incl. hasReports}}}` or `{ok:false, error:{code, message}}` (errors above use code `invalid`, HTTP 400, `docs/CONNECTUM_API.md:670`). Button "Save Details" (busy: "Saving..."). Success toast: "Personal details saved successfully." Failure toast (error style): the server's `message`, else "Failed to save details" (lines 112-133). `profile.get` -> `{profile:{address, gender, dob, education, skills (list), roles (list), ...}}`; the web joins skills with ", ".

**Behaviour to copy or fix**: the web sends an empty field as *omitted* (`value || undefined`, lines 120-124), and the server only changes keys that are present. So clearing a field in the web UI does **not** clear it on the server; to clear, send `null` or `""` (`sd_users_employee.erl:437,450-451,468`). If every field is empty the call fails with "Nothing to change..." and the web shows that as a toast. A failed `profile.get` is silent (fields stay empty).

## 5. My QR Code tab

Loads `connect.my {}` the first time the tab is opened (lines 106-110); while loading it shows "Generating your Connectum QR...". Text: "Colleagues and partners can scan this QR or enter your Connectum code to connect with you instantly."

- **QR image**: drawn on the device from `data.person.payload` (fallback `connectum:<code>`), 240 px source shown at 170 x 170, ink on white with a quiet zone, alt "Connectum QR" (lines 89-98, 454). The payload is a link `{PUBLIC_URL}/connect/{CODE}?org={ENTERPRISE_CODE}` (or `connectum:{CODE}` when the server has no public URL): `docs/MOBILE_QR.md:12-20`, built in `sd_connect.erl:152-155,262-266`.
- **Code** in a dashed pill: `person.display` (shown `XXXX-XXXX`, 8 characters of Crockford base32), else `person.code`. Button (title "Copy code") copies `person.code` (no dash) and the icon turns into a check for 2 seconds; no toast (lines 147-152).
- **"Download QR"** saves the PNG as `Connectum_QR_<username>.png` (line 141).
- **"Regenerate QR code"** (button title "Make a new QR code and Connectum code. The old one stops working."): `utils/regenerateQr.js:7-30`. Confirm dialog title "Regenerate your QR code?", text "Your current QR code and Connectum code will stop working. Anyone who saved or printed it will need the new one.", buttons "Regenerate" (danger) and cancel. Then `connect.rotate {}`; button disabled while it runs. Success toast "Your QR code has been regenerated." and the tab reloads `connect.my`; failure toast (error style) is the server message, else "Could not regenerate the QR code." The old code stops working at once; the audit trail records it (`sd_connect.erl:92-99`, `docs/MOBILE_QR.md:73`). The action name stays `connect.rotate`; only the words changed (was "Rotate").
- `connect.my` answer: `{person:{code, display, payload, url, name, username}, enterprise:{...card...}}`; administrators also get `branches` (`sd_cmds_people.erl:423-433`). `connect.rotate` answers `{person:{..., code:<new>}}`. `connect.my` is never rate limited (`docs/CONNECTUM_API.md:857-858`).
- If `connect.my` fails the web shows no message (error only to the console).

**How someone else uses the code** (summary of `docs/MOBILE_QR.md` section 4): `connect.lookup {code}` shows who it is without connecting; `connect.scan {code}` connects (a personal code makes the two of you associates at once and the owner is told). `code` may be the whole link, `connectum:CODE`, or the bare code (any case, dashes and spaces ignored). Errors: `wrong_org`, `invalid_code`, `not_found`, `rate_limited` (60 tries per 10 minutes per person for lookup and scan together). A person's code only works while it is that person's current one.

## 6. Picture (avatar)

- Choose: file input, accepts PNG, JPEG, GIF, WebP. Checked before upload: type (empty type allowed) else "Invalid image type. Supported formats are PNG, JPEG, GIF and WebP."; size over 8 MB else "File too large. Maximum avatar size is 8 MB." (`ProfileModal.jsx:155-164`).
- Crop: window "Adjust your photo" (round window, drag to move, pinch/wheel/slider to zoom, buttons "Cancel" and "Save photo"/"Saving..."); output is a 512 x 512 JPEG (`AvatarCropper.jsx:8,159-202`).
- Upload: `POST /upload`, multipart, one part named `file`, header `Authorization: Bearer <session token>` -> `{"url":"/uploads/<random-name>"}` (`services/connectumApi.js:110-150`). The server accepts png/jpeg/gif/webp (and voice notes), max 8 MB, content type checked against the real bytes; 20 uploads per 60 s per signed-in person (`docs/CHAT_PROTOCOL.md:279-291`). Errors by status: 400 (server text), 413 "File too large. Maximum size is 8 MB.", 415 "Not a supported image type or file byte mismatch.", 429 "Upload rate limit exceeded. Please wait a moment." The picture is stored when the upload finishes, then applied at once.
- Apply: `/setavatar <url>`; only an `/uploads/...` path or an `https://...` link, max 300 characters, no spaces or control characters; else `{"type":"error","cmd":"setavatar","code":"invalid_avatar",...}` (`chat_web.erl:901-912`, `connectumSocket.js:601-609`). A `profile` event follows. The web does this immediately after upload, **not** on "Save Status".
- Remove: button "Remove" (no confirmation) -> `/removeavatar` -> `profile` event with `avatar: null` (`chat_web.erl:913-916`).
- Serving: `GET /uploads/<name>` (supports Range). Picture addresses arrive in `profile` events, in `conversations` (`avatar`) and elsewhere (`docs/CHAT_PROTOCOL.md:196`). Cache headers were not checked. The web keeps a set of picture addresses that failed to load and does not retry them (`Avatar.jsx:6-14`).
- Appears in: header card and preview in the profile, chats list rows, left panel, hover card, other person's profile; a person without a picture shows one letter in a circle coloured from the name.

## 7. Server contract summary

All `sd` calls: WebSocket `/sd <action> <json>` with a `reqId` echoed in the reply, or HTTP; answers `{ok, data}` or `{ok:false, error:{code, message}}` (`docs/CONNECTUM_API.md:100-131`). Every signed-in person may call all rows below, for their own record only. WebSocket slash commands: 30 per 10 s per connection by default (`chat_web_send.erl:459-472`, error `rate_limited` "Too many commands -- slow down", `CHAT_PROTOCOL.md:132`). No separate limit for `profile.get/update` or `connect.my/rotate` was found.

| Name | Kind | Request | Response / event | Errors |
|---|---|---|---|---|
| `/setpresence <word>` | WS command | one of available, busy, meeting, away, dnd | `ack` + `profile` event | `invalid_presence`, `rate_limited` |
| `/setstatus <text>` | WS command | text up to 140, none = clear | `ack` + `profile` | `invalid_status`, `rate_limited` |
| `/setavatar <url>` | WS command | `/uploads/...` or `https://...`, max 300 | `ack` + `profile` | `invalid_avatar`, `rate_limited` |
| `/removeavatar` | WS command | none | `ack` + `profile` (avatar null) | `rate_limited` |
| `/getprofile <username>` | WS command | username | `profile` event for that person | not read |
| `profile` | event | n/a | `{type, user, avatar, status, presence}` (see section 3) | n/a |
| `POST /upload` | HTTP | multipart `file`, Bearer token | `{url}` | 400, 413, 415, 429 |
| `profile.get` | sd action | `{}` | `{profile}` | `unauthenticated` |
| `profile.update` | sd action | any of address, gender, dob, education, skills (+ state, city, country, pin) | `{profile}` | `invalid` (400) with the messages in section 4 |
| `connect.my` | sd action | `{}` | `{person, enterprise, branches?}` | |
| `connect.rotate` | sd action | `{}` | `{person:{..., code}}` | |
| `connect.lookup`, `connect.scan` | sd action | `{code}` | see `MOBILE_QR.md` section 4 | `wrong_org`, `invalid_code`, `not_found`, `rate_limited` |
| `me` | sd action | `{}` | `{authenticated, user, org, ...}`; `user` is the full own record | |

`profile` events are also what keeps two devices in step (a status or picture changed on one device arrives on the other).

## 8. Behaviour rules and edge cases to test

- Save with nothing changed: window closes, toast shows, nothing is sent except the picture re-send.
- Presence only: choose Busy, Save -> only `/setpresence busy` is sent; status untouched.
- Status only: edit message, Save -> only `/setstatus`; presence untouched.
- Never chosen presence (`presence: null`) and status "In a meeting" -> shows In a meeting; Save without touching chips writes no presence.
- Choose the same presence that is derived from the text, Save -> no `/setpresence` sent (web compares to the derived value).
- Status of exactly 140 characters accepted; 141 cut at 140; counter bold from 130.
- Status with emoji or non-Latin text: web counts UTF-16 units (`slice(0,140)`); the server counts characters (`length(Status)` on the decoded string). Test an emoji at the boundary; behaviour is not confirmed.
- Status starting with "/": sent as `/setstatus /text`; not tested in code. Test it.
- Empty status after trim: sends bare `/setstatus`, cleared on all devices; other people then show their default label.
- Control characters or Enter/newline pasted into the status are removed.
- Double tap on Save or on "Regenerate": the web disables Regenerate while busy; Save has no busy state (closes at once).
- Two devices: change presence on one; the other gets a `profile` event; a `null` status clears the status on the other.
- Offline or socket closed while saving: the web `send` fails silently (not confirmed); make the app say so and keep the draft.
- Signed out or session expired mid-edit: `session_expired` event closes the socket (`CHAT_PROTOCOL.md:62-63`); keep or drop the draft by your own rule.
- Picture: 9 MB file, a PDF, a mislabelled image (415), 21 uploads in a minute (429), remove then add again, picture that later 404s.
- Details: education 121+ bytes (server refuses though web allows 150), address of non-Latin characters near 200 (bytes, not characters), 31 skills, a 41-byte skill, dob in the future, clearing a field (must send null or "" to clear).
- Long name or designation: the web cuts with an ellipsis in the header card.
- Regenerate: old code scanned afterwards -> `not_found`; cancel in the dialog changes nothing; failure shows the server's message.

## 9. What changed recently that affects mobile

| Date | Change | Release |
|---|---|---|
| 26 Nov 2026 | Presence is its own field and command (`/setpresence`, `invalid_presence`, `presence` on every `profile` event); status message and presence are separate (#1023) | v0.2.75 (also v0.2.76, v0.2.77) |
| 26 Nov 2026 | "Rotate" is now "Regenerate QR code" (words only; `connect.rotate` unchanged) (#1023) | v0.2.75 |
| 26 Nov 2026 | Escape in the profile asks before discarding (small-screen fixes commit `7185eb10`) | present in v0.2.75 and later |
| 27 Nov 2026 | Tap a person's circle opens their profile, hover card (#1040); chat header with picture and Chat / Shared tabs, search (#1041); mobile contract doc (#1043) | **dev only**, not in v0.2.77 |
| 27 Nov 2026 | Release v0.2.77 (org logo and others; no profile change) | v0.2.77 |

## 10. How to try it

Per `docs/ENVIRONMENTS.md:82` the dev instance is `connectum.axi-global.com` (the older name `dev.connectum.app` is described as retired); `GET /api/sd/version` should say `"environment":"dev"` (`docs/MOBILE_TEST_ENVIRONMENT.md`). Test accounts: see `docs/MOBILE_TEST_ENVIRONMENT.md` (seed script; no credentials are written here). Compare against the web app at that address: open the left panel's picture or name for the three tabs; use a second account to watch presence dots, the status line and the other person's profile (`#profile <username>`). The chat-header and circle-tap parts exist on dev only. Reference postman collection for the codes: `docs/postman/Connectum_Mobile_QR.postman_collection.json`.

## 11. Not confirmed

- Whether the production `/uploads/` files carry cache headers; whether pictures are served from the app or a bucket for profile pictures (the group-picture doc says an Oracle files bucket, line 17 of the header doc).
- Whether `/getprofile` has its own error codes or limits.
- Whether the web shows anything when a WebSocket command is refused (`invalid_presence`, `invalid_status`, `invalid_avatar`, `rate_limited`): no handler was found in the profile code, so the web appears to ignore the refusal.
- Behaviour of `send` when the socket is closed (silent failure assumed from the code shape, not read).
- Limits for `profile.update` `city`, `country`, `pin`.
- Emoji and non-Latin counting at 140 (client counts UTF-16 units, server `length` of its decoded string).
- Whether a status starting with "/" survives the round trip.
- Whether an invisible 44 px hit area exists for the profile buttons (`touchTargets.css` not read).
- `ProfileModal.jsx:221` calls `confirmDialog` without importing it in that file; it works through the global `window.connectumDialog` registration only if something else sets the bare name. Does not affect mobile, but the web Escape path was not run.
- Whether the Settings row in the phone Profile sheet leads to the profile modal.
- Conflict between "dev environment" statements: `CLAUDE.md` says `dev.connectum.app` while `docs/ENVIRONMENTS.md:82` says it is retired; the current address should be confirmed.

## 12. Open questions for the web team

1. Should clearing a Details field clear it on the server? (Web today sends nothing for an empty field; the server can clear with null or "".) What should mobile do?
2. Education limit: server 120 bytes, web 150 characters. Which is intended? Same question for address (200 bytes vs 200 characters).
3. Should Close and the "x" ask before discarding, as Escape does?
4. Should `invalid_presence`, `invalid_status` and `invalid_avatar` be shown to the person? What text?
5. Is there a server-side limit on how often a person may change presence or status beyond the 30 commands per 10 s?
6. Should the other person's profile show presence and `designation` the same way as the hover card; and what replaces the hard-coded "Bangalore HQ" / "Connectum member" fallbacks (mobile should not copy them)?
7. Which date and time format and which language rules apply to `dob` display on the phone (the API uses `YYYY-MM-DD`)?
8. Will name, designation or username ever be editable from the profile, or is that admin-only?
