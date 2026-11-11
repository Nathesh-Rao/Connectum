# A test environment for the mobile app's automated tests

Written 11 Nov 2026 for the mobile team's seven questions. **Read the first table first: it says, per question, what exists today and what does not.** Where something does not exist, this page says so and does not describe it as if it did. Everything below was checked in this repository; anything that depends on a setting of the dev machine that could not be read is marked **verify**.

| # | You asked for | Status |
|---|---|---|
| 1 | A staging server, isolated from production | **Partly.** The dev instance (10.0.2.113) is isolated, but it is only on the private network and has no web name or certificate yet. There is **no push at all** in the backend, so nothing about push can be isolated or tested. |
| 2 | Test accounts and a login without email or phone | **Yes, in a different form.** No fixed accounts, but every run can make fresh ones (`tools/mobile-test/seed.mjs`), and the sign-in code is returned in the API answer, so no mailbox is needed. |
| 3 | Seed data | **Partly.** An organisation, roles, a group, to-do items, the organisation's code and a person's code are seeded. Direct-chat messages, a ticket form with its actions, approvals, forwarded messages, attachments and branch QR codes are **not** seeded. |
| 4 | Reset, trigger events, relax rate limits | **No.** There is no reset endpoint and no way to inject feed items or events. Each seed run makes a new organisation instead. Rate limits are server-wide settings, not per account. |
| 5 | AI: canned answer and every error class | **Yes.** `tools/mobile-test/mock-ai-provider.mjs`, tested through the real server (23 checks). One condition on the dev machine (below). |
| 6 | End-to-end encrypted chats for automated clients | **Partly.** The mode is a server setting; a reference client and test vectors exist; there is no "make an e2e chat" flag. |
| 7 | Limits, cleanup rules, who to contact | Listed in section 7. **No automatic cleanup.** |

## 1. The test server

**What exists.** The **dev instance**: the machine `10.0.2.113` (the reference app machine, `environment: dev`). It has been its own instance since 7 Nov 2026 (`docs/ENVIRONMENTS.md`, item 3): its own Redis and PostgreSQL on the machine, and its own queue section (`dev`) on the shared RabbitMQ machine. It never touches production data. The earlier load tests and the deploy-to-dev check ran against it.

**Addresses** (private network: the office network or the VPN only; there is no internet access to it):

| What | Value |
|---|---|
| API base through nginx | `http://10.0.2.113/api/sd` |
| API base to the backend directly | `http://10.0.2.113:8080/api/sd` (what the load tests used) |
| Web socket | `ws://10.0.2.113/ws` through nginx, or `ws://10.0.2.113:8080` directly |
| `dev.connectum.app` | **does not exist yet:** infra has not given it a DNS record, a load balancer rule or a certificate |

**verify** from your own network which of the two forms answers: `GET /api/sd/version` must say `"environment":"dev"`. The address is plain `http` (there is no certificate for a private address), so the test build must allow cleartext to it.

**Push: none exists.** The backend has no push service, no device-token registration and no notification provider (`docs/PUSH_AND_LOCAL_NOTIFICATIONS_PLAN.md`, Part A: found nothing for FCM, APNs or Firebase; a search of the backend today also finds nothing). The only live channel is the open socket. So there is no push to isolate from production, and a test cannot receive one: "a notification" for the test suite means the socket event and `feed.list`.

**Real devices and CI.** Because the dev instance is private, a CI runner or a device lab must be on the VPN. If that is not possible, the same seed tool runs against a **local backend** (`docs/DEVELOPMENT.md`; start it with `CONNECTUM_DEV_OTP=1`), which is fully isolated, cheap to start fresh for each CI job, and has no network restriction.

## 2. Accounts and signing in without email or phone

**There are no fixed accounts.** Persistent test accounts would leave the same data in every run. Instead the seed tool makes **fresh accounts every time** (names start with a prefix you can pass, so two runs never clash):

```
node tools/mobile-test/seed.mjs http://10.0.2.113:8080 --prefix mt1
```
(needs Node 22 and the repo; through `ssh -f -N -L 8181:127.0.0.1:8080 connectum-dev` the address is `http://127.0.0.1:8181`.) It prints JSON with the usernames, emails, the organisation's Connectum ID and the first member's personal code. Roles it makes:

| You asked for | The seed makes |
|---|---|
| an organisation admin | `<prefix>admin` |
| two normal members | `<prefix>owner` ("Olivia Owner", Ops) and `<prefix>assignee` ("Arun Assignee", Sales) |
| an owner of a ticket and an assignee | the same two members: the owner creates a to-do and **sends** it to the assignee. A **ticket** needs a ticket form, which is not seeded (section 3). |
| a user outside the organisation | `<prefix>outside`, an account in a different organisation |

**Signing in with no mailbox.** The dev instance runs with `CONNECTUM_DEV_OTP=1`: every "send a code" answer contains the code as `devOtp`. The sequence (details: `docs/CONNECTUM_API.md` section 3 and `docs/MULTI_ENTERPRISE.md`):

1. `POST /api/sd/login/start {email}` → `{sent, devOtp}`
2. `POST /api/sd/login/verify {email, otp: devOtp}` → an **account token** and the list of organisations
3. `POST /api/sd/enter {enterprise}` with the account token → the **enterprise session token**
4. Open the web socket with that token.

The emails are `<username>@test.co`. **There is no fixed code** (a fixed OTP is not supported: the code is random and returned); this path replaces it and works for any account. **It only exists where `CONNECTUM_DEV_OTP=1`, so it can never be used against production.**

**One thing that surprises parallel tests:** a person has **one active session per client kind** (web or mobile): signing in again as the same person on the same kind ends the first session (`sd_auth`). Use a different account for each parallel test, or sign in once and share the session.

## 3. Seed data

**Made by `tools/mobile-test/seed.mjs`** (all of it was run against a real backend before this page was written):
- an organisation `Mobile Test <prefix>` with branch HQ, departments Ops and Sales, designation Analyst; its **Connectum ID** is printed (for join and scan tests);
- the four people above; the first member's **personal code** (from `connect.my`), printed;
- a group `<prefix> team` (the administrator and both members);
- two to-do items: one the owner keeps (`task.create`), one the owner **sent** to the assignee (`task.send`).

**Not made, and where to get it:**

| Item | State and what to use |
|---|---|
| Forms in general (calculations, rules, conditions, cascading drop downs, a grid with a total, file, dates) | **Available, separately:** `tools/sample-forms/load.mjs` loads the sample forms of `docs/sample-forms/` into a test organisation (an administrator's session; `docs/sample-forms/README.md`). Not the ticket forms. |
| Direct chats with messages | Not seeded. Messages go over the socket; the backend suites do this (`connectum-backend/test/lib/harness.mjs`, `Client`). |
| A ticket form with its structure and actions (Send, Status update, Complete, Return, Drop) | Not seeded. The ticket forms are **Ticket Category** and **Ticket SubCategory**, made by `scripts/create-ticket-structs.mjs` (needs a session token and a server with `form.inherit`); the actions and the screens they need are in `docs/TICKETS_AND_TASKS_MOBILE.md` and `docs/TASKS_AND_ACTIONS_FOR_MOBILE.md`. **To add:** seeding these is a piece of work we have not done; say if you want it. |
| Approvals | Not seeded. A form with an approval chain is made with `admin.tstruct.save` (`approval: {enabled: true, ...}`); approvals are answered with `req.respond`. The suites show the recipe (`connectum-backend/test/connectum_putapi_test.mjs`, `connectum_work_test.mjs`). |
| Forwarded messages, attachments | Not seeded. Attachments need a **file storage profile** on the instance; whether the dev instance has one was not verified. |
| QR and branch codes | The organisation's Connectum ID and the person's code are printed by the seed. A QR opens `https://<host>/connect/<code>` (`docs/MOBILE_QR.md`; Postman collection `docs/postman/Connectum_Mobile_QR.postman_collection.json`). Branch-specific join codes are not seeded. |
| To-do items beyond the two above, notifications of each priority and category | Not seeded; see section 4. |

## 4. Reset, triggering events, rate limits

- **Reset or re-seed: there is no endpoint, command or script that wipes test data.** Every run of the seed tool makes a **new organisation** instead, so runs never depend on each other. Old test organisations stay on the instance. A real wipe of the dev instance is an operations task (`docs/ENVIRONMENTS.md`, item 3: fresh settings and a `FLUSHALL` on the machine) and needs Arjun.
- **Trigger server-side events: there is no injection endpoint.** Events come from real actions done by a second signed-in test person, which is how the suites do it: a feed item or notification is the result of an action by someone else (a to-do sent, a request raised, a message received), and a **ticket status change** is a ticket action by the assignee. There is no way to create "a notification of each priority and category" on demand: the feed kinds are made by the features that raise them (`docs/WORKSPACE_FEED_MOBILE.md` lists them).
- **Simulate a socket disconnect:** from the client, close the socket. To drop every connection from the server side, restart the backend (`ssh connectum-dev sudo systemctl restart connectum-backend`, as `tools/ci/e2e-env.mjs` does with `E2E_RESTART`): it is back within a few seconds, and the first screens of an organisation can take up to about 30 s to warm up (measured on dev).
- **Rate limits:** the per-person command limit is **30 commands per 10 seconds** by default, a **server-wide** setting (`CHAT_RATE_LIMIT_MAX` on the backend: the suites run it at 100000). **There is no per-account relaxation.** On the dev instance the value is **verify**: ask Arjun to raise it if your suite sends commands faster than that. In front of the backend, nginx limits sign-in to 30 a minute per address (plus a burst of 30), and creating many organisations from one address is slowed (after about an hour of setups the dev backend answered "Too many attempts; try later" and cleared in about 85 minutes): seed once per run, not once per test.

## 5. AI: a canned answer and every error class

`tools/mobile-test/mock-ai-provider.mjs` is an OpenAI-compatible stand-in provider. It answers a canned summary, or any error class when a marker is in the **last user message**. It is tested through the real server with the real error classifier: `connectum-backend/test/connectum_mock_ai_provider_test.mjs` (23 checks).

```
node tools/mobile-test/mock-ai-provider.mjs --port 9777 --key some-test-key
```
Make the agent (Admin console > AI agents, or `admin.ai.save` as the administrator): `provider: "custom"`, `baseUrl: "http://<where the mock runs>:9777"`, `key: some-test-key` (8 to 400 characters), any `model`, an alias such as `mock`. The server calls `<baseUrl>/chat/completions`.

**Condition on the dev machine (verify):** the mock runs at a private address, and the server refuses a private address for an AI provider unless it runs with `CONNECTUM_API_ALLOW_PRIVATE=1` (the production template sets it; the dev instance's value was not read). If it is not set, ask Arjun to set it, or run the mock on a public address.

| To get | Do this | The app should show (class) |
|---|---|---|
| The canned answer | any question; or `[mock:ok]` | the summary text |
| A slow answer | `[mock:slow]` (5 s) | a busy state, then the text |
| An empty answer | `[mock:empty]` | "could not answer" |
| Key refused | `[mock:bad_key]` (HTTP 401) | `bad_key` |
| No credit | `[mock:no_credit]` (402) | `no_credit` |
| Provider limit | `[mock:rate]` (429) | `rate` |
| Model not available | `[mock:model]` (404) | `model` |
| Too much data (provider) | `[mock:too_large]` (413) | `too_large` |
| Provider down | `[mock:busy]` (503) | `busy` |
| Request refused | `[mock:bad]` (400) | `bad` |
| Timeout | `[mock:timeout]` (the server gives up at 20 s) | `timeout` (server code `upstream_timeout`) |
| Cannot reach the provider | stop the mock | `network` (server code `upstream_unavailable`) |

Errors of Connectum's own server, which need no mock:

| Server code | How to cause it |
|---|---|
| `no_agent` | a test organisation with no agent, or none the person may use |
| `no_access` | disable the agent (or remove the person's permission) after the app has cached the list |
| `not_found` | delete the agent after the app has cached the list |
| `too_large` | send more than 200 KB |
| `rate_limited` | the 31st call by one person inside a minute (per-person limit); the per-agent limit is 600 a minute across people |
| "no key" | **cannot be caused**: saving an agent requires a key (8 to 400 characters), so an agent without one does not exist |
| `key_unreadable` | not reproducible in a test (the stored key cannot be read only if the server's storage key changed) |

The classes and the words the web shows for each are in `chat-app/features/connectumChat/services/assistantErrors.js` and are described in `docs/MOBILE_AI_IN_CHAT_FOLLOWUP.md` section 3.5.

## 6. End-to-end encrypted chats

- **Whether a chat is encrypted is a server mode**, `CONNECTUM_E2E`: `off` (default; envelopes refused), `optional` (apps with E2E encrypt automatically; plain text still accepted; if the other person has no device yet, plain text is sent), `required` (direct and group chat accept only envelopes) (`docs/E2E_ENCRYPTION.md` section 5). **There is no flag to create an e2e chat:** with the mode on, a chat is encrypted once the people in it have registered devices. The dev instance's mode was not read: **verify**, and if it is `off`, Arjun has to set it to `optional` or `required` for these tests.
- **How a client sets up keys:** `e2e.register {id, ecdh, sign, label, proof}` registers a device (the proof is a signature over `connectum-e2e-register|user|id|ecdh|sign`), and `e2e.recovery.set {...}` switches recovery on; both are in the action table of `docs/E2E_ENCRYPTION.md` (section 8). An automated client holds the keys in its own test store; there is nothing to set up on the server beforehand.
- **References for a Flutter client:** `docs/E2E_MOBILE_KIT.md` (test vectors with the private keys of two throwaway devices in `docs/e2e-test-vectors.json`, and `tools/e2e-kit/e2e-check.mjs`, which opens an envelope and says which step fails); `docs/E2E_HISTORY_SYNC_MOBILE.md` and `tools/e2e-kit/new-device.mjs` for the second-device flow. The web's own client (`chat-app/features/connectumChat/e2e/e2eClient.js`) is driven in the backend suites as a test device (`connectum-backend/test/lib/e2e_peer.mjs`), which is the executable reference.
- **Not provided:** a ready-made encrypted chat with test users. Making one means two seeded people each registering a device through a client, then sending a message; the kit shows the exact steps and bytes.

## 7. Limits, cleanup and who to contact

| What | Value |
|---|---|
| Commands per person | 30 per 10 s (server setting `CHAT_RATE_LIMIT_MAX`) |
| Sign-in (nginx) | 30 per minute per address, burst 30 |
| Organisation set-ups from one address | slowed after many (see section 4); seed once per run |
| Upload size | up to 27 MB on `/upload` through nginx |
| AI | 30 calls a minute per person, 600 a minute per agent, 200 KB in, 2 MB out, 20 s per provider call, 12 agents per organisation |
| End-to-end sync | `e2e.sync.put`: 1 to 500 boxes per call, 400 calls per 10 min per person; `e2e.sync.page`: 600 per 10 min |
| Sessions | 15 days; one active session per client kind per person |
| The dev machine | one backend on one machine (10.9 GB memory). It is shared with the backend team's own load tests: **never run a load test or more than a few dozen simulated people against it** |

**Cleanup rules.** There are **none automatic**: test organisations stay until the instance is re-provisioned. Please **start every name with your prefix** (`--prefix`), so they can be found, and tell Arjun when you are done with a batch. Do not delete anything that does not carry your prefix. Never point a test at `connectum.app`: production must not be used (and it rejects the sign-in-code path anyway).

**Who to contact.** For the data, the seed tool, the mock provider and the settings in this page: **Arjun** (message Arjun directly). For the machine, the network, VPN access, the web name `dev.connectum.app` and the load balancer: **the infra team**.
