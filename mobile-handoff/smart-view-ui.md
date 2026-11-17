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
