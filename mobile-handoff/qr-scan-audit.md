# QR scan flow audit

Audit only; nothing was rebuilt. Compared with `reference/qr/QR_CODES_FOR_MOBILE.md` sections 5, 8 and 12. Code read: `connect_target_*` (confirm sheet), `connect_controller.dart` (scanner and typed code), `invite_code_controller.dart`, `connect_code.dart` (parser), `deep_link_service.dart`. Not run on a device or the server.

## Matches
- Order is lookup, then confirm, then scan; `connect.scan` runs only after the person's tap (or right after a confirmed switch). Section 8 and 12.5.
- Confirm title is `Connect with <name>?`.
- Typed or scanned text goes through one parser (`ConnectLinkParser`): 8 characters, case, spaces and dashes ignored, O→0, I/L→1, U→V, `connectum:`, `connectum://connect/` and https links accepted, `?org=` and `?branch=` kept.
- `invalid` and `forbidden` show the server's own text; the own-code error from `connect.scan` ends on the failed pane with that text.
- Needs a connection; offline keeps the link and retries.

## Differences
1. **Confirm card detail line.** Doc: `@<username> • <designation> • <department>`. App: name, then `designation, department` (no `@username`, comma not bullet).
2. **Confirm text and buttons.** Doc: `Not now` / `Connect` (busy: `Connecting…`). App: body "You will become associates and they will be told.", buttons `Yes, connect` / `No`.
3. **Result texts.** Doc: `Connected with <name>!` / `Already connected with <name>.`. App: "You're now connected with <name>" / "You and <name> are already associates". Button `Open chat` (web: `Message Now`).
4. **Error wording is the app's, not the server's, for most codes.**
   - `not_found`: app "We couldn't find that code" + own body; server "No one has that code."
   - `invalid_code`: app "That isn't a Connectum code"; server "That isn't a valid Connectum code."
   - `rate_limited`: app builds "Wait N seconds/minutes" from `details.retryAfter` (key assumed, not in the doc); server "Too many codes tried; wait a few minutes and try again."
   - `wrong_org`: on lookup the app opens its own switch/join pane (public card lookup); on scan it is shown as `not_found`. Doc text: "That code is for a different organisation. Open the organisation it belongs to first."
   - `invalid` ("That's your own code.") and `forbidden` do use the server text.
5. **Typed-code input.**
   - Hint: the Connect screen's field says "Enterprise name or ID"; doc says "Enter any 8-character Connectum code (e.g. ABCD-1234) or scan using your camera." That field also searches enterprises, which the doc does not describe.
   - Bad text: the invite sheet says "That isn't a Connectum invite. Check the code or link and try again."; doc says "That isn't a Connectum code. It has 8 letters and digits."
6. **Link host is checked.** Only `connectum.app` and the host of `BASE_URL` are accepted in an https link. A QR from a server whose public URL is another host is rejected as `wrongHost`. Doc 12.1 only requires the server's payload to be drawn, and the server's `CONNECTUM_PUBLIC_URL` can be anything.
7. **Link is rebuilt before the call.** The lookup and scan send `https://connectum.app/connect/<code>[?org][&branch]`, not the scanned text. The server extracts the code either way, so this works, but the host differs from what was scanned.
8. **Organisation code scanned by a member.** App: "You're already in <org>" with the branch as a tag. Web: "You are in <org> (<branch>)". Same meaning, other wording.
9. **Own code on lookup** is not known to be refused; the app may show the confirm card for the person's own code and only fail after `Connect`. Not verified (needs the server).

## Not checked
- Server `details` shape for `rate_limited`.
- Whether `connect.lookup` of one's own code errors.
- After a `not_found` on one's own code the doc (12.3) says to re-fetch `connect.my`; the scan flow never has the person's own code, and the QR sheet fetches fresh on every open.
