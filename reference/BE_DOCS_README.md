# Docs index

| Need | Read |
|---|---|
| Starting out: names, setup, checks, conventions | [DEVELOPMENT.md](DEVELOPMENT.md) |
| Where things live in the repo | [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) |
| **Colours, the one light theme, the design pack's tokens, the guards, the report service palette** (read before any UI change) | [THEME.md](THEME.md), [UI_DESIGN.md](UI_DESIGN.md), [LIQUID_GLASS_STYLE_GUIDE.md](LIQUID_GLASS_STYLE_GUIDE.md), [../theme/README.md](../theme/README.md) |
| What is built, what is next, who owns it | [REQUIREMENTS_STATUS.md](REQUIREMENTS_STATUS.md) (tracker), [REQUIREMENTS.md](REQUIREMENTS.md) (the product document), [SPRINT.md](SPRINT.md), [STATUS.md](STATUS.md) (generated) |
| **"Scripts" in tstructs** (what to use instead of scripts: calculations, rules, conditions, fetch, approval branching; tested examples) | [TSTRUCT_STATUS_AND_SCRIPTS.md](TSTRUCT_STATUS_AND_SCRIPTS.md) |
| **People drop-downs: Show, Save, who is offered** (list people by an alias or code, save by a field that takes no duplicates, the conditions of "From another form", the rules) | [PEOPLE_DROPDOWN_SHOW_SAVE.md](PEOPLE_DROPDOWN_SHOW_SAVE.md) |
| **Record actions** (Send, Update status, the holder, who a record can be sent to, the organisation's history; what changed for mobile) | [RECORD_ACTIONS.md](RECORD_ACTIONS.md) |
| **Who sees a record and through which command, what "My workspace" is, how a session picks the organisation, what happened to records from before the record flow, which chat cards carry a record, the records probe** (for the mobile team; checked by a scenario) | [MOBILE_RECORDS_FULL.md](MOBILE_RECORDS_FULL.md) |
| **The Smart View for the mobile team: entry points, every command with its request and answer, the saved-view and set-up schema, limits, the exact web screens, behaviour and live events, what runs on the client (exact rules and test vectors), hidden fields and access, refresh strategy, tests and the scripts (`tools/smartview-capture.mjs`, `tools/smartview-vectors.mjs`, `tools/smartview-probe.mjs`, `tools/smartview-seed.mjs`)** (revision 2, 16 Nov 2026: every example is a capture from a real run, in `docs/examples/smartview/` and `docs/examples/smartview-engine/`) | [MOBILE_SMART_VIEW.md](MOBILE_SMART_VIEW.md) |
| **Setting up Claude Code on the Team plan, moving to a new account, connectors** (what carries over, the three steps, the project settings, resume text) | [CLAUDE_CODE_SETUP.md](CLAUDE_CODE_SETUP.md) |
| **Moving a node's secrets into the OCI vault** (what it is, loading, giving a node access, switching, rotating, the way back, what was tested and what not) | [VAULT.md](VAULT.md) |
| **What infra creates for the vault and the release store, the exact policies, the secret inventory, how to verify** | [INFRA_VAULT_AND_RELEASE_STORE.md](INFRA_VAULT_AND_RELEASE_STORE.md) |
| **Release checklist** (build, staging pointer, test, approve, promote, watch, rollback, image refresh; old and new versions together) | [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) |
| **Load test v5 plan** (files, end-to-end encryption, published APIs, big organisations, large groups, consumers, several organisations; the managed Redis stays filled; 1 GiB cap) | [LOAD_TEST_V5_PLAN.md](LOAD_TEST_V5_PLAN.md) |
| **Load test v5: status of the run** (what ran, retried, left in place) | [LOAD_TEST_V5_STATUS.md](LOAD_TEST_V5_STATUS.md) |
| **Load test v5 incident of 6 Nov 2026** (the test pipeline edited 24 production rows in the shared PostgreSQL; cause, evidence, restore steps) | [LOAD_TEST_V5_INCIDENT.md](LOAD_TEST_V5_INCIDENT.md) |
| **No third-party host: libraries and fonts self-hosted, the Content-Security-Policy** | [EXTERNAL_DEPENDENCIES.md](EXTERNAL_DEPENDENCIES.md), [CSP.md](CSP.md) |
| **Where the records are kept** (one Redis key per record, the move from the old hash) | [RECORD_STORAGE.md](RECORD_STORAGE.md) |
| **IndexedDB cache and de-activation** (specification, to be confirmed before it is built) | [INDEXEDDB_CACHE_SPEC.md](INDEXEDDB_CACHE_SPEC.md) |
| **Opening the app from a QR code** (the QR page, the app-link files, the provider's settings, the three mobile flows) | [MOBILE_QR.md](MOBILE_QR.md) |
| **How the web app uses the shared form logic** (what is in the bundle, what lives only in React, what mobile must build) | [FORM_LOGIC_WEB_ARCHITECTURE.md](FORM_LOGIC_WEB_ARCHITECTURE.md), [FORM_LOGIC_FOR_MOBILE.md](FORM_LOGIC_FOR_MOBILE.md) |
| **Start here for the mobile team**: every document, vector file, Postman collection and tool for the mobile app, in reading order | [MOBILE_HANDOVER.md](MOBILE_HANDOVER.md) |
| **Administrators, scoped administrators and handover** (who may do what, the scope rule, the powers, orphaned items and who is told, every command) | [ADMIN_HANDOVER.md](ADMIN_HANDOVER.md) |
| **What changed for API users, and the schema version** (`GET /api/sd/version` -> `schema`; every API-visible change, newest first) | [DEV_API_CHANGES.md](DEV_API_CHANGES.md) |
| **Earlier messages on a new device, backup and restore** (for the mobile team) | [E2E_HISTORY_SYNC_MOBILE.md](E2E_HISTORY_SYNC_MOBILE.md) |
| **Encrypted files, photos and voice notes** (for the mobile team) | [E2E_ATTACHMENTS.md](E2E_ATTACHMENTS.md) |
| **What the chat shows for messages and how the "@" list works** (for the mobile team) | [CHAT_MESSAGE_UI_FOR_MOBILE.md](CHAT_MESSAGE_UI_FOR_MOBILE.md) |
| **Message formatting, message options, save, pin and mark as unread** | [MESSAGE_FORMATTING.md](MESSAGE_FORMATTING.md), [MESSAGE_OPTIONS.md](MESSAGE_OPTIONS.md) |
| **Calendars** (the organisation's working week, holidays and leave form; a person's month; their own hours kept inside the organisation's) | [CALENDARS.md](CALENDARS.md) |
| **Form logic for the mobile app, field types and the sample forms** | [FORM_LOGIC_FOR_MOBILE.md](FORM_LOGIC_FOR_MOBILE.md), [FORM_LOGIC_ON_THE_SERVER.md](FORM_LOGIC_ON_THE_SERVER.md) (calculations and rules checked on save, and `form.evaluate`), [FORM_FIELD_TYPES.md](FORM_FIELD_TYPES.md), [sample-forms/README.md](sample-forms/README.md) |
| Wiring the frontend to the backend | [CONNECTUM_API.md](CONNECTUM_API.md) (every `/sd` action and live event), [CHAT_PROTOCOL.md](CHAT_PROTOCOL.md), [CONNECTUM_FRONTEND_INTEGRATION.md](CONNECTUM_FRONTEND_INTEGRATION.md), [CONNECTUM_HANDOFF.md](CONNECTUM_HANDOFF.md), [HASH_COMMANDS.md](HASH_COMMANDS.md), [FRONTEND_HANDOFF_HASH_COMMANDS.md](FRONTEND_HANDOFF_HASH_COMMANDS.md) |
| **The consumer system** (queues, bridges, the Erlang consumer, Axpert save, approval questions): what everything is and where it lives | [CONSUMER_SYSTEM_GUIDE.md](CONSUMER_SYSTEM_GUIDE.md), [RABBITMQ_REAL_SAMPLES.md](RABBITMQ_REAL_SAMPLES.md) (real JSON), then [RABBITMQ_CONSUMER_CONTRACT.md](RABBITMQ_CONSUMER_CONTRACT.md), [consumer-erlang/README.md](../consumer-erlang/README.md), [ONE_SCHEMA_PER_ORGANISATION.md](ONE_SCHEMA_PER_ORGANISATION.md) (one room per organisation in the database: the runbook), [APPROVALS_NOTIFICATIONS_LOGIC.md](APPROVALS_NOTIFICATIONS_LOGIC.md) |
| **Plugins** (sold separately, not part of this source): how they plug in, how to build with and without them | [PLUGINS.md](PLUGINS.md) (and `connectum-plugins/README.md` beside this folder) |
| **The data registry (who is part of which organisation) and the two clouds (shared and private)** | [REGISTRY.md](REGISTRY.md) |
| **Moving to a managed Redis** (what it must offer, the steps, the rollback) | [MANAGED_REDIS.md](MANAGED_REDIS.md) |
| Speed, load testing, scaling plan | [PERFORMANCE.md](PERFORMANCE.md), [LOAD_TEST_VM.md](LOAD_TEST_VM.md) (full VM load-test report: users, messages, connections, Redis, two devices, how to get past the limits) |
| Autonomous, supervised work (overnight runs, workers, watchdog) | [AUTONOMOUS_WORK.md](AUTONOMOUS_WORK.md), [../tools/autonomy/](../tools/autonomy/README.md) |
| CI/CD, branches, backups, e-mail | [CI_CD.md](CI_CD.md), [BRANCH_RULES.md](BRANCH_RULES.md), [BACKUPS.md](BACKUPS.md), [EMAIL_SETUP.md](EMAIL_SETUP.md) |
| Product history and notes | [NEXT_STEPS.md](NEXT_STEPS.md), [MIGRATION.md](MIGRATION.md), [DEMO_GUIDE.md](DEMO_GUIDE.md), [PROGRESS.md](PROGRESS.md), [EXTRACTION_NOTES.md](EXTRACTION_NOTES.md) |
| Original documents and images | `source-documents/` (the product `.docx` files), `assets/` (logos, reference images) |
| The form studio (`form-studio/`) | [../form-studio/docs/](../form-studio/docs/README.md) |
| The backend | [../connectum-backend/README.md](../connectum-backend/README.md) and `../connectum-backend/docs/` |
