# Pull to refresh

Every pull-to-refresh goes through `AppRefresh` (`lib/core/widgets/app_refresh.dart`): a `CustomScrollView` with `CupertinoSliverRefreshControl` (bounce, trigger 80, pinned extent 56) whose header is `AppSpinnerDouble`. The app never used Material `RefreshIndicator`, so there is no `noSpinner` variant involved. `test/core/no_raw_refresh_test.dart` fails if a refresh control or `CupertinoActivityIndicator` appears in `lib/` outside `AppRefresh` and `AppSpinner` (`test/core/raw_refresh_allowlist.txt`, starts empty).

## The spinner
- Source: `assets/icons/loader/spinner-double.svg` (not shipped as an asset, not edited). Two paths, viewBox 80x80, pivot 40,40: thick arc clockwise 0.8 s per turn, thin arc counter-clockwise 0.6 s per turn (SMIL ported by hand).
- Regenerate: `python3 tool/loader/extract_spinner.py` writes `lib/core/widgets/app_spinner/generated/spinner_double_data.dart` (paths, viewBox, pivot, direction, duration all read from the SVG). Never edit that file.
- `AppSpinnerDouble` (`lib/core/widgets/app_spinner/`): `size` (28), `color`, `progress` 0..1, `spinning`. While pulling, angle follows `progress` (one turn over a full pull, so it joins the free spin without a jump) and it scales 0.6 to 1 and fades in. While refreshing it turns from real elapsed time. Reduced motion: no ticker, static frame. The ticker belongs to `TickerMode`, so it stops under a covered route.

## Colour
`kPullRefreshColor` in `lib/core/widgets/app_spinner/pull_refresh_config.dart` is `AppColors.primaryBright`: the old refresh header, `AppSpinner` and the blue loading animation already use it. To switch to `AppColors.primary` or `AppColors.violet`, change that one line.

## New screen
Use `AppRefresh(onRefresh: ..., slivers: [...])`. Empty and error states go inside the slivers (`SliverFillRemaining`) so they stay pull-refreshable. Never build `RefreshIndicator` or `CupertinoSliverRefreshControl` elsewhere.

## Debug
`/debug/refresh` (debug only, remove before release): slow or failing fake refresh, size slider, colour switch, reduced-motion preview.
