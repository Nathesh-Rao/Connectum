# be_sync

Copies the backend docs from `origin/dev` of the web repo into `reference/`.

```
tool/be_sync/sync_be_docs.sh --dry-run   # fetch, report, change nothing
tool/be_sync/sync_be_docs.sh             # apply
```

- Web repo: `~/Development/Axi-apps` (override with `WEB_REPO`). Only read-only git: `fetch origin dev`, `log`, `diff`, `show`, `ls-tree`, `rev-parse`, `merge-base`, `cat-file`. Nothing is checked out, pulled or written there.
- State: `reference/.be-sync-state` (`sha=`, `date=` of the last synced `origin/dev`). Without it the first run compares files by content only.
- Reports: commits and files since the last sync under `connectum/docs`, `connectum/tools/mobile-test`, `connectum/tools/sample-forms` and the command/HTTP handlers (`sd_cmd*.erl`, `chat_cmds.erl`, `chat_web_listener.erl`).
- Copies: only files already under `reference/` whose name matches a top-level `connectum/docs/` file (`reference/test-env/tools/*` come from `connectum/tools/mobile-test/`), plus new `MOBILE*`, `PRIVATE_AI*`, `LOGIN*` docs into `reference/`. Other new docs are listed, never copied. `reference/backend-pack/`, `prototype/` and `screenshots/` are never touched.
- `DEV_BASE_URL=http://10.0.2.113` (optional): calls `/api/sd/version` and says whether the docs match, are AHEAD of or BEHIND the deployed dev release. Unreachable: says so and continues.
- Docs copied here may describe changes that the app does not follow yet: read the diff before relying on a copy.
