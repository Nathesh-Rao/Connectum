Mobile team pack (2 November 2026)

Start with docs/MOBILE_HANDOVER.md: it lists everything in reading order.

postman/   Connectum_Mobile_QR.postman_collection.json is the one for you (folder 5: what changed for the mobile app).
           Connectum.postman_collection.json + the environment: the whole platform.
json/      e2e-test-vectors.json            keys, an envelope, a late box, and the "rewrap" vectors (fixed inputs, the bytes to match, the boxes to refuse)
           e2e-attachment-vectors.json      4 real encrypted files (fixed key and iv) with their tags, and 8 blobs that must be refused
           e2e-sync-replies.json            real replies of the history-sync actions
           message-format-vectors.json      32 messages with the exact formatting result
           sample-forms/                    twelve sample forms, needs-setup/ (four more that need an API), index.json, cases.json, README.md
           form-logic/                      the form logic as served live at /form-logic/ (version 1.1.0): form-logic.bundle.js (one script),
                                            form-logic-host-shim.js (load it first), form-logic-conformance.json (run it in your engine), the four ES modules, manifest.json
docs/      the documents the handover page points at (the repository's docs/ folder is the source of truth)

The tools (tools/e2e-kit, tools/sample-forms) are in the repository.
