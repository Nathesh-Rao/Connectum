# Smart View UI shell (Task A)

## Plan

1. Tabs: Chats, Agents, Submits, Smart view, Inbox (indices 0 to 4; existing indices keep their place). Profile leaves the bar; `/profile` becomes a pushed screen with a back button.
2. `AppProfileAvatar` (30 dp, the bell's circle size, in a 48 dp tap box) sits after the bell in `ChatsHeader`, the only top bar with the bell. Letter first, picture crossfades in (`AppAvatar.picture`, `PeopleAvatars.urlOf`).
3. Inbox is a static placeholder (`features/inbox`): pill row, "Search mail" field, caption, inactive button, refresh icon, empty state. No repository, no network.
4. `SmartViewController` is created by `HomeShellBinding`, not per route; it holds the sources list, the current view and the drawer state. The route `/smart-view/:name` goes; `HomeShellController.openSmartView(SmartViewEntry)` selects the tab and applies the entry.
5. Entry object `SmartViewEntry`: `.tab()`, `.drawer()` (`#view`), `.named(name)` (`#view <name>`). `CommandRunner` keeps its matching (`SvSources.find`) and only navigates through a callback.
6. The tab shows the last opened view, else opens the drawer with the choose state.
7. Back: `PopScope` closes the drawer first (only while the tab is active; leaving the tab closes the drawer).
8. Drawer: kf_drawer prototype at `/debug/smartdrawer` first (judgement below); the shipped drawer is the same behaviour either way.
9. Repository, paging and cards are not touched.
10. Tests on fakes with bounded pumps, goldens for Inbox, drawer, top bar; then analyze, test, `flutter build apk --debug`.

## Progress log

- Inventory read: shell (`home_shell_*`), `AppBottomNav`, `ChatsHeader` + `AppNotificationBell`, Profile, Smart View screen/controller/binding/picker, `CommandRunner._openSmartView`. Bottom-nav PNGs for smart_view and inbox exist and `assets/icons/bottom_nav/` is declared in pubspec as a folder. Nav icons are tinted with `AppColors.purple` / `AppColors.muted` for selected and unselected (all tabs, same `*_selected.png` tinted too), so the new tabs do the same.
- Only the Chats header shows the bell, so the avatar goes there.
- `SvSource` has no record count and the repository does not expose one, so the drawer shows no per-row count (the STRUCTURES title carries the list count).

- Built: tabs Chats, Agents, Submits, Smart view, Inbox; `AppProfileAvatar` in `ChatsHeader`; `/profile` is a pushed route with a back button; `SmartViewController` lives with the home (`SmartViewBinding` called by `HomeShellBinding`); `HomeShellController.openSmartView(SmartViewEntry)`; `CommandRunner` only calls it (matching untouched, `#view` with no name no longer reads the list); `SmartViewPicker` and the `/smart-view/:name` route are gone; `AppDrawerShell` + `SmartViewDrawer`; Inbox sample.
- Tests: `test/smart_view/smart_view_tab_test.dart`, `test/inbox/`, `test/home_shell/`, `test/chats/chats_header_test.dart`; goldens `sv_drawer_open`, `inbox_placeholder`, `header_avatar_letter`, `header_avatar_picture`. The three list-state goldens and the Smart View screen test were redone for the menu header and the tab.
- Nothing in the repository, paging or card code changed.

## kf_drawer 2.1.0 verdict

Prototype built at `/debug/smartdrawer`, probed with a widget test (fake-free, no network), then removed from pubspec. **Not shipped.**

1. Open/close from code: yes (`KFDrawerController.open/close`, `onDrawerChanged`).
2. Smart View page as the body without page swapping: only half. `content` is ignored as soon as a `KFDrawerController` is attached (the controller's `page` wins), so the body has to be handed over as the controller's page; the whole design is a page-swapping menu (`KFDrawerItem`s). Our drawer (Find field, scrolling list, highlighted pill, loading/empty/error states) would have to be squeezed into the `header` slot.
3. Animation: slide plus scale plus a translucent shadow layer exist, but the shape is fixed by the package: a 32 dp radius, an `easeInOutBack` scale curve (bounce), a hard-coded `Colors.white` body and a white shadow panel. Tokens cannot drive it.
4. Conflicts: **fails.** The edge drag is a raw `Listener` (no gesture arena) that starts only at x <= 8 dp, inside Android's back-gesture zone, and it knows nothing about `systemGestureInsets` (probe: a drag from x=4 opened it, from x=40 did not). With `disableContentTap` (default) an open drawer cannot be swiped closed, only tapped. The system back does not close it (probe: still open after `handlePopRoute`). It measures against the full screen width, not the area it sits in.

Shipped instead: `SmartDrawerShell` (AnimationController + our widgets): slide + subtle scale/shadow of the body, controller-driven from code, header menu button, edge swipe that starts after the system gesture inset, swipe or tap to close, back closes it first. `/debug/smartdrawer` stays as a sandbox for it.

## TODO (not built, left out of the drawer on purpose)

- "Open an Excel or CSV file"
- APIS section
- Overview
- Cards/Table switch, filter, speed dial (later tasks)
- Per-view record count in the drawer rows (needs a repository field)

## Verification

- `flutter analyze`: no errors or warnings (13 infos, all older code).
- `flutter test`: 1820 passed, 3 skipped, 0 failed.
- `flutter build apk --debug`: built, not installed or run.

# Task B: data presentation (cards, table, switch)

## Plan

1. `SmartViewColumns` (`lib/data/smart_view/sv_columns.dart`): one pure source for cards and table. Columns: No., key field, By, Submitted, Status (record state word), the status field, then own fields; meta marked `isMeta`. Types come from the repo's own field types (`SvCell` text rules reused; unknown types print as safe raw text). Blank is `—`. Hidden fields are not in the source list, so they are never columns or cells.
2. `SmartViewCard` replaces `SvRecordCard`: title + status pill, quiet meta row (No., by, when, linked status pill), icon/label/value rows, first 6 own fields, "Show all (N)" / "Show less" with `AppAnimatedSize` 230 ms. Expanded ids live in `SmartViewController.expanded`. No buttons, progress bar, menu or long press; tap still opens the record as before.
3. `SmartViewModeSwitch` (96x34, violet thumb, 220 ms easeOutCubic) left of the row under the header; the right side is empty. `AnimatedSwitcher` 240 ms fade + 2 % slide; `PageStorageKey` keeps each list's scroll offset.
4. Choice kept in `SmartViewPrefs` (the app has no plain preference store and no package may be added, so it uses the same `flutter_secure_storage` as the session). Loaded in `main` before `runApp`; read synchronously by the controller.
5. Table: `SmartViewTable` (native). Widths measured with `TextPainter` over the header and every loaded cell, capped at 60 % of the width, then wrapped (row heights measured too); cached by source, row count, ids, versions, width, text scale. Sticky header, hairline rows, `SmartViewStatusPill` for status cells, shared pull to refresh (`AppRefresh`, new optional `wrapSpinner` keeps the spinner on screen in a wide list) and the same footer.
6. Syncfusion gate decided from the package source (see below).
7. Demo: Leave request gets To, Start time, Balance, Manager, Notes (long, empty and short values), Cover arranged. `/debug/smarttable` shows the table on 120 sample rows.

## Table engine gate (syncfusion_flutter_datagrid)

Evidence (package source in the pub cache, version **35.1.46**, which is what `^35` resolves to; the project was not touched, `dart pub cache add` only downloaded it):
- `syncfusion_flutter_core` and `syncfusion_flutter_datagrid` 35.1.46 contain **no** licence validation, no trial banner, no watermark, no `registerLicense` / `SyncfusionLicense` (searched `licen`, `trial`, `banner`, `watermark`, `evaluation`). Only 29.1.38 of core still has `license.dart`. So step 5b (register a key from `SYNCFUSION_KEY`) cannot be written against this version, and no banner is expected.
- Its pubspec pulls `intl` and needs Flutter >= 3.35.1 (we have 3.38.4); CLAUDE.md says `intl` is not used.
- Terms: Community Licence (under 1 million USD revenue and under 5 developers) or a commercial licence; "under no circumstances can you use this product without" one of them. Whether the company qualifies is the owner's to confirm.

Verdict: **not shipped, package not added.** I could not run anything on a phone, so I could not check the width/wrap rules (a column capped at 60 % must wrap, rows must grow) or smooth scrolling of 120 x 15 cells on a device. The native table meets the rules by construction and is tested; the licence question stays open. The Syncfusion path is therefore not prototyped; `SmartViewTable` takes rows, source, refresh and footer only, so it could be swapped.

## Progress log

- Built all of the above. Removed `sv_record_card.dart` and its golden `sv_card.png`; removed the old card's long-press menu from the screen (the controller's `openRecordMenu` / `detailOf` stay, unused by Smart View now).
- Not done: frozen first column (the native table scrolls whole rows sideways; a frozen column needs a split layout with synced row heights), the switch on `/debug/smartview` (that screen only launches the tab), `SYNCFUSION_KEY` plumbing and its CLAUDE.md line (no package).
- Tests: `test/smart_view/smart_view_presentation_test.dart` (columns, card, switch, prefs, table), a "cards and table" group in `smart_view_screen_test.dart`. Goldens added: `sv_card_new_short`, `sv_card_new_expanded`, `sv_cards_list`, `sv_table`, `sv_switch_cards`, `sv_switch_table`. Regenerated: `sv_list_loaded`, `sv_drawer_open` (the list behind it now has the switch and the new cards). Removed: `sv_card`. Goldens use the test font and icon boxes, as the older ones do.
- `flutter analyze`: no new issues (infos are older code). `flutter test`: 1838 passed, 3 skipped. `flutter build apk --debug`: built, not installed.

# Task C: client engine, filter UI, sort, search by field

## Plan

1. Vectors: `test/fixtures/smart_view/engine/vectors.json` (also `reference/smart-view/engine/`), 144 runnable cases. Engine in `lib/data/smart_view/engine/` (`SvValues`: toTime, toNum, plain, inferType, isMeasure; `SvEngine`: filter incl. search and scope, sort, group, aggregate, chipText, controlFor, rangeFor), pure Dart, positions in, positions out.
2. `SvEngineInput` (`sv_query.dart`) turns `SmartViewColumns` + rows into an `EngineTable` (declared types; hidden fields are never columns) and returns `SvRow`s, so Cards and Table draw one list. `SmartViewQuery` is per view in the controller (`_queries`), restored on `show()`, cached by (row identities, query).
3. UI: `SvControls` (switch left; Search, Filter + badge, Sort right; search overlays the row, 220 ms), `SvFilterSheet` (draggable, draft until Apply, live "N of M"), `SvSortSheet`, `SvChipsStrip`, `SvNoMatch`, `SvLoadNote`, table header tap = asc, desc, none. Debug: `/debug/smartquery`.
4. Sync engine: 5,000 rows filter + sort measured in the VM (JIT, debug) at about 15 ms median, so no isolate; the input table is built once per data version.

## Progress log

- Done: engine, vectors runner, edge and perf tests, query state, controls, sheets, chips, no-match, load note, header sort, demo variety (Leave request: 5 stages, dates Sep 2026 to Feb 2027, empty cells), `/debug/smartquery`, goldens (`sv_filter_sheet`, `sv_controls_chips`, `sv_search_expanded`, `sv_no_match`; `sv_cards_list`, `sv_list_loaded`, `sv_drawer_open` regenerated for the new row).
- Doc vs vectors: (1) the `group` "date column" vector lists group lines only, no rows, though the doc says rows sit under groups; the runner compares groups only for that case. (2) Text sort: the doc says ICU `localeCompare`; the port is locale-free (Latin accents sort with their base letter, digits before letters, numeric runs by value); other scripts and punctuation may order differently. (3) `controlFor` gives `choice` for text columns (vector) while the web panel types text; on mobile text columns are typed, status/select are chips (owner spec). (4) The vectors were made in Asia/Calcutta: local-time `toTime` cases are checked as wall clock so the run does not depend on the zone.
- Not ported (no UI yet or covered elsewhere): `plainFromHtml`, `csv`, `captureView`, `definedCards/Charts`, `formatCell`/`structureCells*` (display, already tested through `SvCell`). Group and aggregate are implemented and vector-tested; their UI is Task D.
- Paging: the repository reads every page up to its cap by itself, so "Load more" only starts the existing quiet re-read when none runs (it is a spinner while pages are still coming); nothing past the 20-page cap can be loaded.
- Chips: each chip fades/scales in; removing one chip is instant (the strip collapses with animation only when the last goes).

# Task D: polish, speed dial, KPI, charts

## Plan

1. `HomeTab` enum (chats, smartView, inbox, agents, submits) replaces every tab index; bar order Chats, Smart view, Inbox, Agents, Submits.
2. Profile avatar 38 dp, 2 dp violet 35 % ring + 2 dp white gap, 12 dp from the edge, 10 dp from the bell.
3-7. Card v2 (vertical pairs), table gradients/banding, tinted 40 dp control buttons, filter/sort sheets, history comments (no container, 4 lines, See more/less, open state kept in `HistoryQuote.openKeys`).
8. `AppSpeedDial` (native) replaces the Add FAB on the tab: Add record (only when `canAdd`), KPI, Charts; one option = direct button.
9. `lib/data/smart_view/engine/sv_insights.dart`: `definedCards` / `definedChart` ported (vectors), default KPI = the web's auto cards (Rows, top 3 status values, 2 totals with avg), charts grouped by status/select/yes-no/date (month or day), 24 + Others. Sheets `SvKpiSheet`, `SvChartsSheet`, painters in `sv_chart_view.dart`. Tokens: `lib/core/theme/app_sv.dart`.
10. `/debug/smartinsights`; demo Leave request already has a status, two numbers and dates over six months.

## Progress log

- All ten items built. Not ported (no UI): `plainFromHtml`, `csv`, `captureView`. Charts and KPIs read the engine's filtered positions (`SvEngineInput.positions`, memoised in `SmartViewController.insightRows`, computed only when a sheet asks).
- Tests: `smart_view_insights_test.dart`, `history_comment_test.dart`, additions in `bottom_nav_test`, `chats_header_test`, `smart_view_query_test`, vectors for `definedCards` / `definedChart`.

# Task D2: polish round 2

## Plan

1. Card: drop the field icon circles; key above value starts at the card padding (`sv_col_icon.dart` stays for table/sheets).
2. Speed dial: closed = `Icons.grid_view_rounded`, open = `Icons.close` (AnimatedSwitcher 230 ms fade + turn); "Add record" keeps `+`.
3. Add filter = `AppButton.primary` (no filters) / `AppButton.secondary` (filters), no gradient; `heroGradient`/`heroShadow` removed; gradient audit (line chart area fade replaced by a solid 10 % tint).
4. KPI tiles: `_UniformGrid` render object, all tiles half width x the tallest tile's height.
5. Drawer: one 16 dp inset; row label x == Find search icon x (field side padding + border).
6. `SmartViewCountChip` ("Total 120" / "Showing 3 of 120").
7. History comment: solid `Icons.chat_bubble` 18 dp, muted, no circle.
8. Search field, scope chip, close button and drawer Find use the standard `AppTextField` border (`inputBorder`, 1 dp, `controlAll`, focus ring).

## Progress log

- All eight built; tests added in `smart_view_presentation/tab/query/insights`, `smart_view_count_chip_test`, `history_comment_test`; affected goldens regenerated.

# Task D3: card from the owner's mock-up, flat table, history marker

## Plan

1. Card = copy of `incoming/sv-card-mockup.png` (supersedes D2 items 1 and 7): header (position circle, title, record pill) on `SvCardHeaderArt` (lavender hill + faint blue wash, painter only, path cached by size), body rows split 50/50 (icon + key | value), hairlines, fold after 6.
2. Table: flat colours only: solid primary header with white text, rows white / primary at 4.3 %.
3. History comment: 8 dp solid dot (`cardMuted`), 10 dp gap, no icon.
4. Position is `i + 1` of the list as shown (`SmartViewView`), so it follows filter and sort.

## Sampled colours (mock-up, 1926 x 1058)

| Sample | Hex | Token |
|---|---|---|
| card surface (centre) | FDFDFE | `AppColors.white` |
| border left / top | E7EBF9 / D4DBF7 | `AppSv.cardBorder` E3E8F8 (new value) |
| lavender peak (top right) | E2DDF9 | `AppSv.cardWash` (new) |
| lavender mid-fade / inside wave | F6F4FC | same wash at alpha 0.8 to 0.09 |
| left blue wash / number circle | D6E1FA | `AppSv.numberFill` = `primaryTintStrong` D6E3F7; `cardBlueWash` (new) for the wash |
| divider | F0F1FB / EEF1FC | `AppSv.hairline` EEF2F8 |
| title, value, number text (darkest) | 010641 to 08145C | `AppSv.cardInk` 0B1456 (new; `AppColors.ink` is too teal) |
| key text, icons | 5D6A8E, 556385 | `AppColors.cardMuted` |
| status pill fill / text | E4E6EE / 13223F | existing slate tone of `SmartViewStatusPill` |

## Progress log

- Done: items 1 to 3 and tests. Layers icon is the Material `layers_outlined` (the card icons are Material line icons via `SvColIcon`, not `AppIcons`, which holds PNG paths); `SvColIcon` status/select now use it too (table sort sheet, filter sheet).
- Differences from the mock-up: the mock-up's proportions (title 20 sp in a 72 dp header) were followed from the task text, not scaled from pixels; the wave is an approximation (two cubics) of the mock-up's hill, and the wash alpha is a gradient, so the edge is a little softer; the status pill keeps the app's dot size and neutral slate for unknown words.
- Table tokens: `svTableHeaderFill` is `AppSv.tableHeaderFill`, `AppSv.tableRowAlt` (4.3 %), `AppSv.tableRowPressed` (8 %, unused: rows have no pressed state); the old gradient tokens are removed.

## D4: card proportions and header art

- The mock-up's pixels had been used as dp, so the card was about 470 dp for 4 rows. Tokens re-scaled in `AppSv`: radius 18, pad 16, header 56, number circle 30, rows min 40 / pad 9, icons 16, title 16 sp, key 13, value 13.5, shadow blur 10 y 2 at 5 %.
- `SmartViewStatusPill` has `isCompact` (11.5 sp, dot 6, padding 10 x 4), used in cards and the table.
- `SvCardHeaderArt`: the wave is gone; one violet gradient (11 % to 0) inside the 56 dp header band plus a faint 8 % glow at the top right, clipped to the band.
- Cards list and table keep `AppSv.dialClearance` (fab + margin + 16) plus the safe area at the bottom so the last item clears the speed dial.
- Log: done; 4-row card about 229 dp at 360 dp wide; goldens regenerated.

## Task E: Overview page and table cells without wrapping

- Plan: the Overview is the landing page of the tab (`SvOverviewBody`, data in `SvOverviewModel`, pure numbers in `lib/data/smart_view/overview/sv_overview.dart`); every way into the tab resets the open view, queries and Overview numbers; `#view <name>` opens that view; the old "last opened view" restore is gone.
- Data: no new BE call. One `submissions.list` page (500 newest, own records) per structure through the repository gate (`readForOverview`: 6 per 10 s, 300 ms apart), one structure at a time in list order; the count is the page's `total`. Worst case N structures, one page each: about `ceil(N/6) * 10 s` (the first 6 in under 2 s).
- Numbers: Structures = list length; Records = sum of `total`; This week = records from Monday 00:00 (device zone, the web's "This week" preset); Waiting for approval = loaded records with `status: pending`, tile only when a structure has its own status flow; bars = last 7 local days, today last; mix = status field value, else approval words; footer `Last entry N min / h / d ago`.
- KPI values show "…" until every card is read or failed; a failed or partial card adds "Based on loaded records".
- Navigation: tab/`#view` -> Overview (drawer closed/open); re-tap on a view -> Overview, on the Overview -> scroll to top; back: drawer, then view -> Overview; controls row and speed dial exist only on a view; drawer has its own Overview row above STRUCTURES (Find filters structures only).
- Table: nothing wraps; text over 10 words or over 60 % of the width is cut with "…" and "View more" (violet); "View more" or long press opens the Details sheet (`SvCellDetailsSheet`: label, selectable full value, Copy); column width = widest cut cell; rows have one fixed height.
- Debug: `/debug/smartoverview` (fake source), DEMO_MODE Leave request rows are spread over a month.
- Log: done; goldens sv_overview_loaded / loading / empty, sv_drawer_open, sv_table, sv_cell_details_sheet.

## Task G: Smart View bug fixes

- Bug 1: `SmartViewController.open` pushed the ticket or submission detail route, and `submission_detail_view` reads local SQLite ("This submission is not saved on this phone."); Smart View rows are memory only. `open` is gone: a card tap and a table row tap show `SvRecordSheet` ("Record details", `sv_record_sheet.dart`, built from `SmartViewColumns.cardOf(row)`, so hidden fields never appear; lines are the card's `SvPair`s, nothing folded, read only). "View more" / long press on a cell still opens its own `SvCellDetailsSheet`. No edit/delete path existed from memory, none added. No other Smart View path reaches a route except Add (form route, server).
- Bug 2: could not reproduce at controller, draft or widget level (Apply replaces, chips and rows read `query`, editors commit on change). Hardened: `shownRows` / `insightRows` caches compare (data version, query) by value, not a 32-bit hash; `setConditions` keeps an unmodifiable copy so a caller's later list edit cannot alias the stored query.
- Tests: `smart_view_filter_flow_test.dart`, `smart_view_record_sheet_test.dart`; navigation and screen tests now expect the sheet.
- Log: done.

## Task H: Smart View file preview + download

- Plan: file ids and details come from the row's `files[field]` (`SvFile`, kind from mime then extension, SVG never an image); `SmartViewColumns.cellOf` fills `SvCellValue.files` for file columns only, so a hidden field never gives files. Cards and the record sheet show up to 3 chips + "+N more", the table one chip + "+N" (`sv_file_chips.dart`), all >= 44 dp hit areas.
- Download: `GET /api/sd/files/<24 hex id>` with `Authorization: Bearer` (`mobile-handoff/attachments.md` section 2.4); the body is bytes as `application/octet-stream`, so a picture is drawn only when its first bytes are PNG/JPEG/GIF/WebP. `SvFileRepository` (dio of `AttachmentRepository`) writes `<id>_<size>.<ext>` in the temp folder, 100 MB, least recently opened out, cleared on sign out / organisation change (`ever(store.current)`); never SQLite. A 401 calls `ApiClient.reportUnauthorized` (the app's session-ended path).
- Viewer: `SvFilePreviewDialog` (220 ms fade + scale), PageView per record, zoomable pictures, text first 200 KB as plain text, every other type a file card with Download / Open with / Share (`AttachmentCache.open` / `share`, existing). No PDF, video, audio or office viewer exists and no package was added.
- Download saves to the app's `Downloads` folder (documents directory) as `name (1).ext` when taken, then a notice with Open. Not the public Downloads folder: that needs a package (see report).
- Open BE question (our Q17, still open): content type is always octet-stream, size limit, range, and whether a Smart View row's file ids (received records have no `files` map) are all accepted by the route.
- Demo: DEMO_MODE Leave request has an `Attachments` field (image, text, 256 KB csv, pdf, long-named xlsx, zip, one failing scan) served by `SeedSmartFiles.fetcher` with simulated progress; `/debug/smartfiles` shows chips, table and viewer.
- Log: done; tests `test/smart_view/sv_files_test.dart`; goldens sv_file_chips, sv_file_dialog_image / text / other / error, sv_table_files.

## Task K: Smart View files, inline tiles and in-app viewers
- Plan: cards and the record sheet draw full-width `SvFileTile`s (equal width and height); a card shows 3, "+N more" opens the rest in place (AnimatedSize 220 ms), then "Show less"; the fold is kept per record id in `SmartViewController.filesExpanded` (cleared with `expanded`). The record sheet passes no toggle, so every file shows. The table is unchanged.
- Preview: `SvFilePreviewDialog` is a centred dialog (16 dp insets, 20 dp radius, 78% height, 40% scrim) whose card animates to full screen in 240 ms (`SvFilePreviewController.isFull`, Back leaves full screen first). Header: type circle, name, "KIND · size · 2 of 5", full-screen, ⋮ (Download, Open with…, Share, Wrap lines for text), close. Footer: Download, Open with…. Swipe is off while a picture or PDF is zoomed (`SvFileLoad.isZoomed`).
- Viewers (`lib/features/smart_view/viewers/`, picked by `SvFile.viewer`): image (zoom), PDF (`pdfrx`, page pill + go to page, `SvPdfChrome`), video and audio (`video_player` behind `SvMediaPlayer`, tests subclass it), csv/tsv table (500 x 50, tabs when several sheets), docx/pptx text via `archive` (regex on the XML, plain text), zip listing, text/JSON (200 KB, pretty JSON, wrap, copy). Pure parsers in `lib/data/smart_view/preview/sv_preview_parsers.dart`; parsing runs in `compute` over 256 KB; sheet/docx/pptx/zip over 15 MB are not parsed (file card). `SvViewers` lets tests replace the PDF and media viewers.
- Packages: pdfrx 2.2.24 (MIT), video_player 2.11.1 (BSD), archive 4.7.1 (MIT). `excel` could not be added: every version needs archive ^3 and `lottie` needs ^4, so .xlsx/.xls use Open with… (no workaround). minSdk stays Flutter's 24 (video_player_android 24, pdfium 21).
- Demo: `SeedSmartFiles` makes every sample in code (valid 5-page PDF, a protected-like PDF, docx, pptx, zip, json, bin, a 2 s WAV for audio, csv, png as jpg); there is no mp4 (no valid tiny video can be made offline), so video is tested with a fake player.
- Log: done; tests `test/smart_view/sv_file_viewers_test.dart` and `sv_files_test.dart`.

## Task L: web views, columns, group, hidden fields, customize (recon, no code)
- Docs: `mobile-handoff/smart-view-views-web.md` (read from web `origin/dev` 54a31d45699a, 2026-11-18); questions in `mobile-handoff/smart-view-views-be-questions.md`; fixtures `test/fixtures/smart_view/views/` (README says which are verbatim).
- A saved view holds only: id, name, search, filters, sort, groupBy[], hidden[] (quiet columns turned on as "+key"), order[], widths{}, kpis, charts. Wrap, record heights, "Show hidden fields" and collapsed groups are never stored.
- Views are one whole list per person and source (`smartview.views` / `smartview.views.save`), no revision: two devices overwrite each other.
- Hidden-field values already arrive in `submissions.list`; the web hides them behind a per-session switch in Columns. Owner decision pending.
- The vectors file is stale for structure column order (key first, internal `#`, quiet columns); BE sync needed.

## Task I: saved views (tabs), group by, columns
- Spec: `smart-view-views-web.md` + `smart-view-views-be-questions.md` (Task L). A view = id, name, search, filters, sort, groupBy[] (max 5), hidden[], order[], widths, kpis, charts; the server drops other keys. No `mode`, no per-group aggregate key: the header shows count + total of the first number column (the web's rule). Whole list per person and source (`smartview.views` / `.views.save`), no revision, Default View = entry `__default`.
- Plan: `SvSavedView` (unknown keys kept, widths/kpis/charts untouched, hidden-field names dropped on apply) + `SvViewState` (working state, equality = "changed"); `SvSavedViewsRepository(call:)` goes through `SmartViewRepository.gated` (same pacing); `SeedSavedViews` is the fake.
- Save: read the list again, merge ONE change by id, write; target changed remotely -> "Overwrite / Reload"; failed read -> nothing written. 20 named views, name 1-40, "Default View" refused as a name.
- UI: tab strip under the controls (Default, saved, shared read-only, "+"), "Unsaved changes" pill (Save / Reset; Default View has Reset only), long press = Rename / Duplicate / Delete, ⋮ in the controls row = Save, Save as new, Create, Remove, Columns, Group.
- Group by: any number of levels up to 5 (numbered badges); headers with count and total; collapse kept per view (chevron animates, rows drop out at once). Columns: search, Select all, drag to reorder, Reset / Apply.
- Not done: Customize (KPI/chart definitions, `smartview.attrs*`), "No KPI / No charts" captions (need those definitions), wrap and size reset (mobile table never wraps), hidden-fields switch (owner/BE question 1), Set as default (the web has none; Default is saved only from the web).
- Debug: `/debug/smartviews` (Leave request demo: Pending only, By status with two levels, Compact; the first save of a re-read finds "Pending only" renamed elsewhere). DEMO_MODE uses the same fake.
- Log: done; tests `test/smart_view/sv_saved_views_test.dart`, goldens sv_view_tabs, sv_save_view_sheet, sv_grouped_cards, sv_grouped_table, sv_columns_sheet, sv_group_by_sheet.

## Regression M (commands and ticket tiles)
Audit against `commands.md` (built 16 Nov, before Smart View) and the code: the `#` handler table is unchanged except for the added `view` row; `test/commands/command_destinations_test.dart` now pins every command's mode.
| Command | What the user sees | Handler |
|---|---|---|
| `#tstruct-add <name>` (`#create`, `#ts-add`) | the fill-in form (`/form`), nothing posted unless "Also post this to the chat" is ticked; auto-send and the card follow the save | `CommandMode.form` -> `SubmissionRepository.openStructure` -> `AppRoutes.form` |
| `#tstruct [name]` (`#ts`, `#struct`) | My Submissions tab filtered to that form; its detail has Edit/Delete | `CommandMode.records` -> `HomeShellController.openSubmissionsOf` |
| `#view` (`#smartview`, `#list`) | Smart View tab (the only intended change) | `CommandMode.smartView` |
`#tstruct` going to the Submissions tab IS the documented behaviour; no code path for it changed. What did change: the bottom bar (Profile tab replaced, `HomeTab` order chats, smartView, inbox, agents, submits), so Submits is now the last tab. Not restored: awaiting the owner's answer on what `#tstruct <name>` should open.
Ticket tile: `WorkspaceController.open` sent only a RECEIVED record to the ticket screen and my own records to the submission (documented "as before" in `records-and-tickets.md`, Work Space section). Fix: one pure rule, `CardDestination.of` (`features/tickets/models/card_destination.dart`, built on `RecordCardRule`), used by Work Space tiles and chat cards; notifications already open `ticketOf(id)`. Tests: `test/tickets/card_destination_test.dart`.

## Task P: `#tstruct` / `#tstruct-add` typing flow, web vs mobile
Web step → mobile step → result (`mobile-handoff/tstruct-commands-web.md`, Task P).
- `#` → command menu → `CommandPrompt._toNames`, catalogue list → SAME.
- Pick the command row → box `#tstruct ` with the space (`pickCommand`) → SAME.
- Type `#tstruct` (no space) → command menu, no names (the same for `#tstruct-add`) → SAME.
- Type `#tstruct ` / `#tstruct le` → web asks `/cmdcomplete` after 150 ms and lists the structures; mobile skipped the request: the server sends the argument as type `text`, and `_readArgument` took a last `text` argument for free text, so the list stayed empty and the person could only send a bare or hand-typed name → DIFFERENT, fixed (`command_prompt.dart`, `#tstruct` and `#tstruct-add` always ask the server).
- Pick a name → replaces the word, no trailing space → SAME (Task N).
- Send → `#tstruct <name>` opens the records screen (`HashKind.records` → `AppRoutes.structRecords`), `#tstruct-add <name>` the form (`AppRoutes.form`) → SAME (`command_runner_test.dart`).
- Bare send → usage tip "Please provide the struct name, e.g. ..." → SAME.
- Enter while the command menu is open picks the row on the web; mobile has no Enter-picks-row, its Send sends the line → SAME as the web's Send button.
Test: `test/commands/tstruct_typing_flow_test.dart` (fails before the fix at `#tstruct `).
