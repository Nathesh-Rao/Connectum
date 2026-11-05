# End-to-end: every device that exists now gets a box (what changed, 1 November 2026)

For the mobile team, and for anyone who takes this over. Plain story first: `E2E_SIMPLE_GUIDE.md`. Exact rules: `E2E_ENCRYPTION.md`. This page lists **what was changed, why, and what a client must do.**

## The problem

A person sometimes saw, on a device that **already existed**, this grey message:

> 🔒 Sent before this browser was set up for encryption, so it can't be opened here. …

Cause: a message carries one small box (the message key, locked for one device) **per device**. The sender's app builds the boxes from a list of the recipient's devices. If that list was out of date (a phone or browser had been added a moment ago, or the app kept the list for minutes), the new device got **no box**. The server only checked that **every person had at least one box**, so it accepted the message and delivered it. Nobody was told, and that device could never read it.

## What changed

### Server (`connectum-backend`)

| File | Change |
|---|---|
| `src/security/sd_e2e.erl` | `validate_wraps/5`: a message must have a box for **every device that exists now** of every person in the conversation, the sender's own other devices included. The **sending device itself may leave its own box out.** A box for a device that no longer exists (removed, or a member who left) is refused too. Both refusals are `e2e_stale_devices`. New `require_all_devices/0` (the switch) and `stale/2`. |
| `src/http/chat_web_send.erl` | `e2e_verdict/3`: the refusal is sent as an event with extra fields (`mid`, `conv`, `users`), the way `not_associated` already carries `to` and `conv`. Used by sends and by edits. |

Unchanged on purpose: a person with no device at all is still `e2e_peer_not_ready`; `required` / `optional` / `off` modes; recovery; what is stored (nothing readable); the 250-box limit.

### The rule, case by case

| The envelope | Before | Now |
|---|---|---|
| a box for every current device | accepted | accepted |
| misses a **device** of a person that has other devices boxed | **accepted** (the bug) | refused: `e2e_stale_devices` |
| misses the sender's **own other device** | **accepted** | refused: `e2e_stale_devices` |
| misses **the sending device's own box** | accepted | accepted (it holds the message) |
| a box for a device that was **removed**, or never existed | refused: `bad_envelope` | refused: `e2e_stale_devices` (the sender's list is old) |
| nobody of a person boxed | refused: `bad_envelope` | refused: `e2e_stale_devices` |
| a person with **no device** | `e2e_peer_not_ready` | `e2e_peer_not_ready` |
| nothing stored or delivered on a refusal | yes | yes |

### The event

```json
{ "type": "error", "code": "e2e_stale_devices",
  "text": "Somebody's devices changed while this message was being written. Send it again.",
  "mid": "<the mid of the envelope that was refused>", "conv": "dm:ann|bob", "users": ["bob"] }
```

`users` are the people whose lists to look up again (the ones that were missed; all people of the conversation when a box was for an unknown device). The chat connection has **no request ids**, so `mid` (which the client put in its envelope) is the only reliable way to know which message was refused.

### Web app (`chat-app`)

| File | Change |
|---|---|
| `services/e2eRetry.js` (new) | `StaleRetry`: remembers each encrypted message by `mid` for 30 s; on `e2e_stale_devices` for a known `mid` it forgets that person's devices and resends **by itself**, at most twice; otherwise the refusal is shown like any other error. `midOf()` reads a `mid` out of an envelope. |
| `services/connectumSocket.js` | `sendProtected` takes a `tries` count and remembers each envelope; the incoming event path hands a refusal to `StaleRetry` before showing it. |

The web app already asked for a fresh list of devices for every message (`#plan` uses `fresh: true`), so for the browser the problem was only a short race; the retry closes it. The **receiver** needs no list of its own devices to read: it needs its own box, and the sender's signing key (which it looks up once when it meets an unknown sender device, `#signKeyFor`). That already worked.

### Tests

| What | Where | Result |
|---|---|---|
| 15 new checks: stale list refused with the right code and fields; nothing stored or delivered; a fresh list works and both the old and the new device read it; the sender's own other device; the sending device may omit itself; removed and never-existing devices; a group member's new device | `test/connectum_e2e_test.mjs`, section "Every device that exists now gets a box" | 157/157 |
| The switch at 0 puts the old rule back (6 checks) | `test/connectum_e2e_legacy_wraps_test.mjs` (new suite, registered in `run_all.mjs`) | 6/6 |
| `StaleRetry` and `midOf` (10 tests) | `tests/frontend/e2eRetry.test.mjs` | 10/10 |
| Proof the new checks test the change: with the server change removed, **10 of them fail**, and one shows the bug itself (the message is delivered and Bob's new device gets `not_for_this_device`) | | |

## What a client (the Flutter app) must do

1. Right before encrypting **each** message: `e2e.devices` (direct chat) or `e2e.group_devices` (group). Do not reuse a list kept for minutes. Wrap for **every** device in the answer, the sender's own other devices included.
2. When the server answers `e2e_stale_devices`: forget the devices of `users`, look them up again, build a **new** envelope (new `mid`) from the same text, send again. Do it silently. Limit the tries (the web app: 2), then show the error.
3. Match the refusal to the message by `mid`.

The mobile team's own document was reviewed against the code, with answers to their questions and the two changes the app needs: **`E2E_MOBILE_REVIEW.md`**. A checker for a single envelope, reference messages and the byte-level recipe are in `E2E_MOBILE_KIT.md` and `tools/e2e-kit/`. The mobile Postman collection (`docs/postman/Connectum_Mobile_QR.postman_collection.json`, folder 5, change 7) has the event shape.

## Rollout, and the way back

* The rule is **on by default**. Nothing needs to be set.
* **What an old mobile build sees:** a send made with a stale device list now fails with the text above instead of being silently unreadable on the new device. After its cache refreshes (or the app restarts) sends work again. Until the app retries by itself, the person has to send again by hand.
* **The way back:** set `CONNECTUM_E2E_REQUIRE_ALL_DEVICES=0` in `/etc/connectum-backend.env` on the server and restart `connectum-backend`. The old rule (one box per person) returns at once; the suite `connectum_e2e_legacy_wraps_test` proves it. Remove the line to turn the rule back on.

## After the mobile release: what to check

No restart is needed for the rule itself: it is already live (the deploy restarted the backend). A restart is only needed if `CONNECTUM_E2E_REQUIRE_ALL_DEVICES` is changed in `/etc/connectum-backend.env`. When the mobile team says their release is out:

1. **Real devices, the case that used to fail.** Sign in on the new phone build and on a browser. Open the browser's lock dialog, remove that browser's device, sign in again so it registers as a new device, and within a minute send a message to it **from the phone**. Expected: the browser shows the message, not "Sent before this browser was set up". Repeat from the browser to the phone.
2. **The retry path.** Same as 1, but send from the phone **immediately** after the browser registered (inside the phone's 5-minute window). Expected: the message still arrives and nothing is shown to the person. If the phone shows "Not sent", its handling of `e2e_stale_devices` is not in the release.
3. **The log.** After a day of use, count refusals and who they come from:
   ```
   sudo journalctl -u connectum-backend --since "1 day ago" | grep "e2e stale devices refused" | sed 's/.*from=\([^ ]*\).*/\1/' | sort | uniq -c | sort -rn
   ```
   A few right after a device is added are normal (they are retried). A steady stream from one person means that client is not refreshing; look at that client.
4. **If anything goes wrong:** set `CONNECTUM_E2E_REQUIRE_ALL_DEVICES=0` in `/etc/connectum-backend.env`, `sudo systemctl restart connectum-backend`. The old rule is back at once.

## Things this does not fix, and open points

* **Messages sent before this change** that lack a box for a device stay unreadable on that device. Nothing can add the box afterwards (the message key is not stored anywhere the server could use).
* **A genuinely new device** (first sign-in, cleared browser data, a private window) cannot read the past by itself. **Since 1 November 2026 a device the person already uses can hand the past on** ("History for a new device" in `E2E_ENCRYPTION.md`; what the mobile app must build: `E2E_HISTORY_SYNC_MOBILE.md`). A person whose **only** device is lost gets the past back with the **recovery code and its backup** (done; `E2E_ENCRYPTION.md` section 6a, `E2E_SIMPLE_GUIDE.md`).
* **Group chats and the mobile app.** The mobile team keeps group end-to-end out for now. The rule applies to every envelope, groups too (the web app already looks group devices up for each message). Be aware of one thing that is **not** changed here: if a person's phone is registered for end-to-end, a web user's encrypted group message is wrapped for that phone as well, and the phone cannot open it until it supports groups. Decide whether the app should keep its device unregistered until then.
* **A stricter format check** (exact sizes for `sig`, `ek`, `iv`; a signature in DER form instead of 64 raw bytes) is **not** enforced by the server, which only checks maximum sizes. A client that signs in DER form would be accepted by the server and unreadable by the web app (`bad_signature`). `tools/e2e-kit/e2e-check.mjs` finds that. Enforcing it would break any client that gets it wrong the same way on both sides, so it needs agreement first.

## Files changed

```
connectum-backend/src/security/sd_e2e.erl
connectum-backend/src/http/chat_web_send.erl
connectum-backend/test/connectum_e2e_test.mjs
connectum-backend/test/connectum_e2e_legacy_wraps_test.mjs        (new)
connectum-backend/test/run_all.mjs                                 (registers the new suite)
chat-app/services/e2eRetry.js                                      (new)
chat-app/services/connectumSocket.js
tests/frontend/e2eRetry.test.mjs                                   (new)
tools/postman/mobile-changes.mjs, docs/postman/Connectum_Mobile_QR.postman_collection.json
docs/E2E_ENCRYPTION.md, docs/E2E_SIMPLE_GUIDE.md, docs/E2E_MOBILE_KIT.md, docs/E2E_MOBILE_REVIEW.md (new), docs/E2E_FRESH_DEVICES_CHANGE.md (this page)
```

## Added later the same day

Device alerts (the account owner is told when a device is added; a contact's app tells the person once) and a report-only Content-Security-Policy. Neither needs anything from the mobile app (the history feature that followed does, see `E2E_HISTORY_SYNC_MOBILE.md`); see "Alerts when a device is added" in `E2E_ENCRYPTION.md`, `E2E_MOBILE_REVIEW.md` (last section) and `CSP.md`.

```
connectum-backend/src/forms/sd_feed.erl                      security_text(e2e_device_added, Extra)
connectum-backend/src/security/sd_e2e.erl                    alert_new_device/3; the stale-refusal log line
connectum-backend/src/security/sd_csp.erl                    (new) reads and logs a browser's report
connectum-backend/src/http/sd_http.erl                       POST /api/sd/csp-report
connectum-backend/test/sd_csp_tests.erl, connectum_csp_report_test.mjs   (new)
chat-app/features/connectumChat/e2e/e2eClient.js, e2eStore.js, services/connectumSocket.js, chatEvents/   the contact notice
nginx/csp-report-only.conf, scripts/ops/add-csp-report-only.sh, docs/CSP.md   (new)
tests/frontend/csp.test.mjs, cspOps.test.mjs, tools/ui-audit/csp-violations.e2e.mjs   (new)
```
