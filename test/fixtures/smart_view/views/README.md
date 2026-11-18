# Saved-view fixtures (Task L)

Shapes follow `chat-app/features/smartView/svViews.js` and `connectum-backend/src/forms/sd_svviews.erl` (web `origin/dev` 54a31d45699a). See `mobile-handoff/smart-view-views-web.md`.

| File | Origin |
|---|---|
| `default.json` | **verbatim** (the `__default` entry of capture `real/060-smartview-views-after-saving.json`) |
| `filtered.json` | constructed: every filter value shape (`in`, text, `between` number/date, number op, `true`, `filled`) |
| `grouped_multi_level.json` | constructed (shape of the server-made views in capture 058, two levels) |
| `columns_and_hidden.json` | constructed: `hidden` with `+key` entries for quiet columns, `order`, `widths` |
| `kpi_chart_customized.json` | constructed: a view with `kpis:false, charts:false` plus a `smartview.attrs` set-up with cards and charts |
| `shared_view.json` | constructed: a shared view as `smartview.views` returns it (`by`, `mine`, `s<ms>` id, no `to`) |

No real users or data. Column names are the sample structure `tickets`.
