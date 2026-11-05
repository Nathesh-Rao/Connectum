# Mobile team pack: form logic 1.3.0

Built 4 November 2026 from `main`. Replaces the 1.1.0 pack.

- `form-logic/` : the published files, byte for byte, with `manifest.json` (version 1.3.0, sha256 of every file and of the whole). Load `form-logic-host-shim.js`, then `form-logic.bundle.js`, then run `ConnectumFormLogic.runConformance(<form-logic-conformance.json>)`: `failures` must be empty (84 expression cases and 63 condition cases).
- `docs/FORM_LOGIC_FOR_MOBILE.md` : what to fetch, what the engine needs, what the server checks.
- `docs/FORM_LOGIC_WEB_ARCHITECTURE.md` : how the web app uses these files, what lives only in React, what the bundle lacks.
- `docs/FORM_FIELD_TYPES.md`, `docs/MOBILE_HANDOVER.md` : field types, and the reading order for the mobile app.
- `sample-forms/` : sample form definitions, the expected cases, and a stand-in API.

Changes since 1.1.0: 1.2.0 added `condition.js` (`evalCondition`, `isEmpty`) to the bundle and 63 condition cases to the conformance file; 1.3.0 reads the signed-in person's details as `login_<name>` (the old `global_<name>` still works). An app on 1.1.0 does not know `login_`.
