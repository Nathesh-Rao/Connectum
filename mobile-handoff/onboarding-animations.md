# Onboarding animations (native painters, PROMOTED)

## PROMOTED (real onboarding)
The real onboarding (`lib/features/onboarding/onboarding_view.dart`) now shows these painters. The "Promotion steps" and "Open it" sections below are history.
- **Slot.** `lib/core/widgets/onboarding_art_stage.dart` (`OnboardingArtStage`, the former `DebugOnboardingStage`): PageView of network / buildings / shield, full-width, band decor, `OnboardingArt` defaults (authored colours, crop window, symmetric network, tier 2, speed constants). One widget used by the real onboarding and `/debug/onboarding`. Only the page for `slide` animates; PageView builds only the visible pages and the others are muted (`isActive` false).
- **Layout.** The real view now has zero scaffold padding and wraps header, invite slot, dots, copy, buttons and footer row in the page padding (same as the debug copy), so only the art is full-bleed. Texts, buttons, Skip, invite row, banner, dots, flag and navigation are unchanged.
- **Accessibility.** The old Lottie slot had no semantic label and neither does the painter; unchanged.
- **Retired (moved, not deleted).** `backup/onboarding-lottie-v1/`: the 3 originals and 3 `_blue` Lotties, `onboarding_lottie.dart`, `onboarding_stage.dart`, with a README on how to restore. Removed from the code and (by moving the files out of `assets/lottie/`) from the bundle; `lottie` stays for the loaders and `AppSuccessAnimation`. `tool/lottie/recolor_lottie.py` keeps its `BLUE_ONLY_RULES` for a restore.
- **Debug.** `/debug/onboarding-anim` (lab) and `/debug/onboarding` (copy of the screens, finish only goes back, no flag) stay until release; both are on the before-release removal list. The guard test `main_onboarding_guard_test.dart` now checks that the main onboarding imports only the public `onboarding_art.dart` widget and no `debug_*` code, and that no release code imports `debug_*`.
- **Tests.** `test/onboarding_art/real_onboarding_test.dart` (real view on a GetMaterialApp: swipe, buttons, flag and login, widths 320/360/411/800, overflow, muted tickers, reduced motion). Goldens regenerated: `test/core/goldens/decor_onboarding_{1,2,3}_{363x745,412x915}.png`.

## What was built
The three hand-made HTML/SVG animations (`incoming/onboarding-animations/`) as native Flutter painters, shown only on debug routes. The main onboarding (Lottie) is untouched.

- A tiny SVG scene graph (`svg_scene.dart`: elements with mutable attributes, `use`, clipPath, luminance masks, blur and glow filters, dashed strokes, group opacity via saveLayer) and a path parser (`svg_path_parser.dart`, tight `getBBox` bounds, `Tf` affine transforms).
- The art data is generated from the HTML (`generated/*.dart`); each animation's `render(t)` is a line-by-line port of the HTML script (`shield_security_art.dart`, `network_icons_art.dart`, `buildings_switching_art.dart`).
- `OnboardingArt` (widget), `OnboardingArtController` (`play()` restarts the intro, `pause()`, `resume()`, `seek(t)`, `speed`), `ShieldSecurityArt` / `NetworkIconsArt` / `BuildingsSwitchingArt` wrappers.
- Transparent background (the painters draw none). Reduced motion (platform flag or `reducedMotion: true`) shows the HTML's static frame (shield `t=1.95`, network `14.5`, buildings loop start + 0.1) and creates no ticker. One ticker, stopped when the page is not active, the app is not resumed, or the route is covered.

## Open it
Debug builds only (`kDebugMode`), reachable from `/gallery` (rows `debug/onboarding`, `debug/onboarding-anim`) or by starting on them: `flutter run --dart-define=START_ROUTE=/debug/onboarding` (or `/debug/onboarding-anim`).

- `/debug/onboarding`: copy of the onboarding. Pages: conversations -> network, enterprises -> buildings, security -> shield. Finish and Skip only go back: nothing is stored, login is never opened. The invite row is kept but does nothing.
- `/debug/onboarding-anim`: lab. Play/pause, replay, time slider, speed 0.25x/0.5x/1x, "Authored colours / Blue only", white/light/dark backdrop.

## File map
- `tool/onboarding_anim/extract_art.py`: generator.
- `lib/core/widgets/onboarding_art/`: `svg_path_parser.dart`, `svg_scene.dart`, `onboarding_art_math.dart`, `onboarding_art_palette.dart`, `onboarding_art.dart`, the three `*_art.dart`, `generated/`.
- `lib/features/debug_onboarding/`, `lib/features/debug_onboarding_anim/`.
- Registration: `app_routes.dart` (`debugOnboarding`, `debugOnboardingAnim`), `app_pages.dart` (4 imports, 2 `if (kDebugMode)` pages), `gallery_view.dart` (2 rows), `test/core/color_allowlist.txt` (4 lines).
- Tests: `test/onboarding_art/`, goldens in `test/goldens/onboarding_art/`.

## Regenerate
`python3 tool/onboarding_anim/extract_art.py` (reads `incoming/onboarding-animations/`, writes `generated/`, prints counts and colours). A test fails if the generated files are stale.
Goldens: `flutter test --update-goldens test/onboarding_art/golden_test.dart`.

## Colours
Default is the authored colours. The shield uses violet on the encrypted side (#8F6DF5, #683FE1, #6F47E6, #6A3FD4, plus #ACB3F1 periwinkle); network #794AD3; buildings #9279F8, #5D37E3, #7445EE. "Blue only" (`OnboardingArtPalette.purpleToBlue`) maps them to AppColors blues (cyanBlue, primaryBright, primaryStrong, primaryLight; #ACB3F1 to the art's own #96D6F6). All raw hex lives in the palette and generated files, allowlisted as "authored artwork colours".

## Promotion steps (when approved)
1. In `lib/features/onboarding/onboarding_view.dart` replace `OnboardingLottie(file: OnboardingLottieFile.values[i], isActive: ...)` with `OnboardingArt(kind: [network, buildings, shield][i], isActive: c.page.value == i, blueOnly: <decision>)`. Keep `OnboardingStage`.
2. Then `OnboardingLottie`, `OnboardingLottieFile` and `assets/lottie/onboarding_*_blue.json` (and their `pubspec.yaml` entries) are unused for onboarding; keep `lottie` for `AppSuccessAnimation`. Update the CLAUDE.md Lottie line.
3. Delete `lib/features/debug_onboarding/`, `lib/features/debug_onboarding_anim/`, the two routes, imports, gallery rows, and the guard test `main_onboarding_guard_test.dart`.
4. Retest: `test/onboarding_art`, the colour scan, the onboarding flow on a phone (profile build, frame rate on the moto g32 against the Lottie), reduced motion, app pause/resume.

## Not reproduced exactly
- Blur and glow filters use `ImageFilter.blur` on a layer (sigma scaled by the canvas scale), the browser's feGaussianBlur box approximation may differ slightly.
- `getTotalLength` / `getPointAtLength` (buildings particle) use `PathMetrics` of the same polyline.
- The shield HTML says 64 original paths; only 46 carry an id `p<n>` (the rest were merged or dropped), the test asserts 46.

## Fixes pass 2 (phone test: too slow, only 5 people in the network)
**Slow.** `OnboardingArtState._onTick` capped every frame's time step at 0.1 s (`clamp(0.0, 0.1)`), so any frame longer than 100 ms (blur and glow layers on a phone) advanced the animation by only 0.1 s: slow motion. Now `t = base + (ticker elapsed - base elapsed) * speed` (real elapsed seconds, frame-rate independent; a dropped frame skips ahead). The base is re-taken on play, seek, resume, speed change and when the route is covered (TickerMode), so pause/resume never jumps. The lab and the debug onboarding both default to 1x. The numbers in each port were diffed against the HTML scripts (all literals): no constant differs, the HTML has no global speed.

**Frame cost.** saveLayer calls per frame (`SvgRenderer.layerCount`), network at t=14.5 / buildings at t=8 / shield at t=6:
before 121 / 18 / 2, after 63 / 2 / 0. Done by: stroke-only lines fold opacity into the stroke alpha (they were wrongly treated as fill+stroke: 49 layers in the network), a blur-only filter with opacity uses one layer, masks whose children are all opaque white fills become a clip path (no layer; buildings node/bubble masks, shield data-bar mask), cached Paint and blur-filter objects. Dashed and black-cut-out masks keep the luminance mask. The 40 background people still use one small layer each (their group opacity).

**Missing people.** Root cause: layer bounds of an element with its own transform were computed with that transform included, then the canvas transform was applied again, so the layer sat in the wrong place and clipped the content away. The 5 primary avatars have near-identity transforms and survived; the 40 background people (scaled 0.22 to 0.58, moved far) were clipped. Generic fix in `svg_scene.dart` (`_layerBounds` uses local bounds). The generator was not at fault.
- HTML: 45 nodes = 5 primary + 40 people (10 / 16 / 14 at levels 1 / 2 / 3), 36 electron segments, 4 lateral links. Ours: same (tested against the HTML script's own output, fixture `test/onboarding_art/fixtures/js_truth.json`, made by `node tool/onboarding_anim/js_truth.js`).
- People are all revealed by t = 6.84 s (first t0 4.1 s); all are visible from about 7.5 s to the outro at 15.6 s.

**Coverage.** `extract_art.py` now reads its own generated files back and compares them with the HTML: drawable elements after resolving `use` (display none excluded) and the drawables of referenced clipPaths and masks, and the id lists; it exits 1 listing the missing ids. Result: shield 59 + 3, network 34 + 32, buildings 186 + 21 (scene + referenced), all equal. It also lists the elements the script creates (call sites). Script-created elements and their ports: shield 5 ring circles, 25 glyph groups (12 zeros as ellipse, 13 ones as path) built in `_ShieldFrame._build`; network 297 circles, 70 ellipses, 55 groups, 55 lines, 35 paths, 40 uses built in `_NetworkFrame` (same creation order); buildings creates none. Tests compare the created counts with the script's.

**Other elements checked.** Buildings and shield: every building, node, bubble, shield, node, message and encrypted tile is drawn (pixel test) at the time the script shows it; timelines (buildings loop start 4.1217 s, period 10.3232 s, node and hit times; shield arrival 0.656 s) equal the script. Nothing else was missing or late.

**FPS readout.** The lab shows `fps`, build and raster ms, average and worst over the last 120 frames (SchedulerBinding timings). It is on the lab screen only. Debug builds: expect fps near the display rate (60 or 90), raster avg a few ms, worst under about 16 ms; if raster is high while build is low, the layers are the cost.

**Regenerate the fixture:** `node tool/onboarding_anim/js_truth.js` (node only needed for this).

## Full-bleed layout (debug copy only)
Each animation fills the screen width edge to edge, aspect ratio kept (never stretched).
- **Crop windows.** The art has empty margin inside its viewBox, so the painter shows a crop: the measured content bounds plus a 2 percent margin (of the content width), never beyond the original viewBox (the HTML clips there; nothing is lost and nothing new appears). Bounds are the union of every drawn element over the whole timeline (stroke, blur radius, springs, particles, packets, ripples), measured by `flutter test tool/onboarding_anim/measure_bounds_test.dart`, which writes `generated/content_bounds_data.dart`.

| Animation | viewBox | content bounds | crop window | ratio |
|---|---|---|---|---|
| network | -430 -290 2400x1600 | -388.0 -227.5 to 1838.9 1212.3 | -430 -272.0 to 1883.4 1256.8 | 1.513 |
| buildings | 0 0 1536x1024 | 89.2 115.6 to 1448.2 871.8 | 62.0 88.4 to 1475.4 899.0 | 1.744 |
| shield | 0 0 1774x887 | 0 10.3 to 1774 887 | same as the viewBox | 2.000 |

  The shield gains nothing: its data bar runs across the whole viewBox width and its outer ring touches the bottom edge. The network's edges are set by the ripples of the outermost background people; the buildings' left and right by the ground strip. `crop_window_test.dart` samples the whole timeline (intro plus several loops) and fails with the element id and time if anything leaves the window.
- **Stage.** `lib/features/debug_onboarding/debug_onboarding_stage.dart` (copy of the main stage, same glow band) gives the pages the full screen width, side safe-area insets included (zero in portrait); the art is capped at 600 dp and centred on tablets. The scaffold padding is zero and the header, dots, copy and buttons are wrapped in the page padding again, so only the art is full-bleed. The CustomPaint box clip is kept, so glows never spill outside the art box. The art slot keeps the vertical space the layout gives it; the art is centred in it and shrinks, aspect kept, if the slot is short (320x568: slot 146 dp, art 221 dp wide, not edge to edge).
- **Lab switch.** "Full width crop / Original viewBox" (default crop) on `/debug/onboarding-anim` only: `OnboardingArt(window: OnboardingArtWindow.crop | original)`.
- **320x568.** The screen already overflows by 34 dp there with the main `OnboardingStage` and page padding (fixed 136 dp copy box, buttons, gaps); measured the same with both stages. 360x640 has no overflow.

### Promote the crop into the main onboarding
`OnboardingArt` crops by default. In `onboarding_view.dart`, after swapping `OnboardingLottie` for `OnboardingArt` (steps above), also replace `OnboardingStage` by a stage like `DebugOnboardingStage` (zero scaffold padding, `_pad` on everything else, art capped at 600 dp), or keep `OnboardingStage` and accept the 340 dp box. Then retest the layout tests (`full_bleed_layout_test.dart`) against the main view.

## Five persons and speed
**Network shows five persons (design decision, not a bug).** `kNetworkVisiblePersons` in `network_icons_art.dart` is the one list: `['c', 'top', 'tr', 'br', 'bl']`, the five persons that appear first in the HTML timeline (centre 0.0 s, top 1.8 s, tr 2.0 s, br 2.2 s, bl 2.4 s; `l` follows at 2.6 s). Note: the six outer-plus-centre avatars all come before any background person, so "first five" drops the left avatar (`l`): the left arm is now empty. To keep it, add `'l'` to the list (the chat link `ch` then comes back too, it joins `l` and `top`); add `'background'` to bring the 40 small people back.
Removed with a person: its avatar, icon badge, masked link graphics, comet, node ripple, spawn flash/ripples/dots, icon glow/rings/stars, flow dots and electrons; with the list's others gone also the chat link `ch` (its comet, node ripple, electron), the 40 background people with their lines, dots, heads and ripples, the 4 lateral links, and all electron legs through the crowd (only the first leg on a kept link stays: 7 electrons instead of 36 segments). Nothing orphaned is drawn (tests walk the whole loop). The generator coverage check is about the HTML versus the generated data, so it is unchanged; the removal is in the painter.
**Loop.** The idle stretch (about 2.4 s between the intro end at 4.49 s and the first electron at 6.9 s) is trimmed by `kNetworkIdleTrim` (2.0 s): events after it move earlier, the idle motions run on real time so nothing jumps. The outro keeps the HTML's gap after the last effect. Old loop 16.8 s (outro at 15.6 s), new loop 13.441 s script time (outro at 12.241 s). The loop is seamless: empty at the end (scene faded out) and at the start. With all six people plus `background` and trim 0 the painter reproduces the HTML exactly (16.8 s, tested). The crop window was re-measured for the reduced content: content -> `40.3 7.6 to 1434.4 1064.9` (58% x 66% of the viewBox, ratio 1.319), so the network now fills the width with a bigger drawing.

**Speed.** `lib/core/widgets/onboarding_art/onboarding_art_speed.dart`: `kShieldSpeed`, `kNetworkSpeed`, `kBuildingsSpeed`, each 1.25 (1.0 = the HTML). Applied in one place, `OnboardingArtController.advance`: `t = base + (real elapsed - base elapsed) * speed`; no curve, delay or spring constant is touched. Intro and loop speed up equally; loop in real seconds = script period / speed (shield cycle 3.9 s -> 3.12 s; network 13.441 s -> 10.75 s; buildings 10.323 s -> 8.26 s). Reduced motion shows the script-time still frame. Dropped frames skip ahead (300 ms at 1.25x = 0.375 s of script time).
**Lab.** The selector is multiples of the HTML speed: 0.5x, 1x (the authored HTML), 1.25x (default = the constants), 1.5x, 2x, with the effective speed per animation shown and a Default button; the debug onboarding uses the constants.
**Promote.** Keep `onboarding_art_speed.dart` next to `OnboardingArt` (it reads `OnboardingArtKind.speed`); to change the speed edit the constants only. To change the persons edit `kNetworkVisiblePersons` / `kNetworkIdleTrim`.

## Network tiers (supersedes the five-person list above)
The 5-person version felt too zoomed in with too few connections, so one more tier was added. The lists live in one file, `lib/core/widgets/onboarding_art/network_tiers.dart`: `kNetworkTier1Persons` (`c top tr br bl`, unchanged: same reveal times and motion), `kNetworkTier2Persons` and `kNetworkVisiblePersons = tier1 + tier2` (edit either tier there; `kNetworkIdleTrim` is there too).

**The HTML graph.** 6 hub avatars (`c` centre, `top tr br bl l`); the centre links to the five outer ones, and a chat link `ch` joins `l` and `top`. A generated tree hangs off the outer ones: 10 people one hop out (2 per outer person), 16 two hops, 14 three hops. Lateral links join neighbouring branches (4 exist: top-1/tr-1, tr-0/br-1, bl-1/l-0, l-1/top-0). Electrons run along the hub links and outwards through the tree.
**Tier 2** = the people one hop from tier 1: `top-0 top-1 tr-0 tr-1 br-0 br-1 bl-0 bl-1` (8). Left out: `l-0`, `l-1` (they hang off the hidden `l` and would dangle). Each has its icon, ring, link to its hub (same stroke, dash, colours), dot, head and ripple, and the electrons that run into it; the two lateral links between kept people stay (top-1/tr-1 and tr-0/br-1), the two toward `l` are trimmed. Reveal: the HTML's own times (4.10 to 4.54 s, links draw from t0 and arrive as the icon pops in at +0.38 s), which is after tier 1 is established (the hubs have popped in by 3.1 s); lateral links start at 5.0 and 5.12 s. A person shows only when its parent shows; ids are `<parent>-<n>`; adding `background` brings the whole tree back.
**Loop.** Old HTML 16.8 s, tier 1 alone 13.441 s, now 14.881 s (outro at 13.681 s): the last reveal is done at 5.82 s and the first electron follows at 6.45 s (`kNetworkIdleTrim` 1.0 s). Seamless: empty at the end and at the start. The speed constant `kNetworkSpeed` (1.25) still applies in the controller: 14.881 s script time = 11.9 s real.
**Crop window.** Content bounds (union over the whole loop, glows, pulses, particles, overshoot, inside the viewBox): tier 1 only `40.3 7.6 to 1434.4 1064.9` (ratio 1.319); tier 1 + 2 `-141.6 -13.2 to 1595.9 1212.3` (72.4% x 76.6% of the viewBox, ratio 1.418). Window = bounds + 2 percent, never beyond the viewBox. Re-measure with `flutter test tool/onboarding_anim/measure_bounds_test.dart` after changing a list; `crop_window_test.dart` fails with the element id and time if anything leaves it.
**Lab.** "Tier 2 persons: on/off" (default on) next to the other switches; off shows tier 1 alone inside the same (larger) window, for comparison.
**Balance.** With `l` and its two people hidden the web is empty top-left and left (the left hub `l` is gone, so are its people): the picture is heavier on the right and bottom. Not rearranged; add `'l'`, `'l-0'`, `'l-1'` to the lists to fill it (the chat link `ch` and the two lateral links toward `l` come back with them).
The generator's coverage check is about the HTML versus the generated data, so the intentionally hidden persons are not "missing" there; hiding happens in the painter.

## Network: symmetric layout (default)
The network is mirror-symmetric about a vertical axis through the exact centre of the animation box: split it down the middle and the left half is the exact mirror of the right half at every moment. Main onboarding untouched; debug routes only. The lab switch "Symmetric layout: on/off" (default on, `/debug/onboarding-anim`) compares with the previous layout (`OnboardingArt(networkSymmetric:)`, `OnboardingArtKind.bind(symmetric:)`; `bind` defaults to the old layout, the widget to the new one).

**How it works.** Only the LEFT half is built (`network_symmetric_frame.dart`, `_SymFrame`): the hub on the axis, two mid persons, their four small people, links and effects. `OnboardingArtPainter` draws the scene, then draws it again flipped about the axis (`ArtScene.mirrorAxis`, `setMirrored`) with the hub-owned nodes hidden (the hub is drawn once). So partners start at the same time and move the same way by construction (same element, no stagger, same idle phase), electrons and particles on mirrored lines run mirrored, every connector is mirrored with its person and draws outward from the hub on both sides. The hub art was a few units off the axis and not exactly symmetric: it is moved onto the axis and rebuilt from its left half plus the mirror of it (`_centreHub`, one path); its spawn burst (14 dots) takes its second half as the mirror of the first.
**Replaced, not redrawn.** The people, their drawings, the badge drawings and the colours are the authored ones. Replaced because they were baked at fixed spots: the baked hub links (`mk_*` masks) by straight lines of the same colours with the same node dot, draw-in, comet and flow dots; the authored hub avatars `top tr br bl l` and their badges by copies (`use #s_<person>`, a fresh badge rect with the same mask) placed by the config. Gone: `top`, `l`, the chat link, the lateral links (no cross-axis lines), the 40 background people.

### Config (`network_tiers.dart`, same file as the tier lists)
Edit the LEFT lists only; the right half is generated.
- `kNetworkAxisX` 770 (the hub's x). `kNetworkLeftTier1Persons` `['ul','ll']`, `kNetworkLeftTier2Persons` `['ul-0','ul-1','ll-0','ll-1']`.
- `kNetworkMirrorPairs` (generated): `ul` -> `ur`, `ll` -> `lr`, `ul-0` -> `ur-0` ... (`networkMirrorId`). `kNetworkSymTier1Persons` / `kNetworkSymTier2Persons` / `kNetworkSymVisiblePersons` are generated from the left lists (hub + left + mirrors). Removing an id from a left list removes its mirror too (tested).
- Positions: `kNetworkRowDx` (distance from the axis, upper 433, lower 439: the average of the old left and right distances), `kNetworkRowY` (480, 916), `kNetworkMidRow` (`ul`/`ur` upper, `ll`/`lr` lower), `kNetworkRowStart` (1.4 s, 1.8 s), small people at `kNetworkKidLength` 300 and `kNetworkKidSpread` 0.6 rad from their mid person, away from the hub (the HTML's own growth rule).
- `kNetworkPersonByPair` (`upper: tr` violet, `lower: br` blue): the drawing of a pair. `kNetworkKidArtByPair` (`upper: [l, tr]`, `lower: [br, bl]`): small people alternate blue / violet, same on both halves.
- **`kNetworkBadgeByPair`** `{'upper': 'chat', 'lower': 'check'}`: swap to `layers` / `calendar` / each other; `kNetworkBadgeArt` maps the names to the art (`top`, `tr`, `br`, `bl`). Both persons of a pair share it; it sits on the outer side, at the offset the authored badge has from its person.
- `kNetworkFlipBadgeGlyphs` (default true = exact mirror): the tick and the chat tail point the other way on the right half. Set false to keep the glyphs reading the right way round; then the two halves differ by those two glyphs and the pixel-symmetry tests will report them.
- Crop window: `networkSymContentBounds` in `generated/content_bounds_data.dart` (written by `flutter test tool/onboarding_anim/measure_bounds_test.dart`, re-run it after editing positions or lists): the union of every drawn element and its mirror over the loop, symmetric about the axis (grown on the smaller side), centred vertically on the revealed picture, plus the 2 percent margin; ratio 1.544 (old 1.418). `networkSymSteadyCentreY` is the vertical centre.
- Loop length unchanged (14.881 s, outro 13.681 s, `outGap`), speed constant unchanged.

### Debug stage decor
The glass orbs and the two soft glows are painted by the debug stage (`debug_onboarding_stage.dart`, a copy; the main stage and `AppAmbient` are untouched). On the network page they are now mirrored pairs about the screen centre (`DebugOnboardingStage.networkOrbs`, `networkOrbRects`): the half-cut orb at the left edge is moved inside, the glows at (0.9, 0.06) and (0.04, 0.94) have mirrors at (0.1, 0.06) and (0.96, 0.94). Tested: no orb or its 19 dp glow touches a screen edge at 320 to 600 dp.

### Result (measured)
- Pixel symmetry (`network_symmetry_test.dart`): the frame is rendered the way the painter draws it, flipped and compared at 16 named times (intro, each reveal step, tier 2 revealed, electrons on both link kinds, idle bobbing, a ripple peak, loop start, mid, outro, end) and every 0.37 s over two loops. Skia's anti-aliasing is not exactly mirror-symmetric, so: no pixel may differ by more than 170 of 255 (a real 1 px shift gives about 255; measured max 160) and at most 800 pixels (0.09 percent of 1200x780) may differ by more than 48. On failure the test prints t and the box of the differing pixels.
- Centring: content (alpha > 24) at the revealed time is centred on the axis within 1 dp (3.3 px of a 1200 px frame at 360 dp) with equal left and right margins; vertical space above equals below within 3 percent of the height.
- Vertical slot (revealed drawing, `/debug/onboarding`): 360x780: slot 284 dp, art 238 dp, empty 33.4 above and 33.4 below. 411x900: 57.1 / 57.1. 360x640: the slot (193 dp) limits the art, 292 dp wide (not edge to edge), 8.3 / 8.3. 320x568: the slot is short, so the art shrinks (221 dp wide, not edge to edge), 6.3 / 6.3. The art is centred in its slot in all four; text, buttons and indicators are not touched.
- Goldens regenerated (network only): `network_t1.5` (intro), `t3.6` (tier 1 shown), `t4.7` (tier 2 coming in), `t6.0`, `t9.0` (everything shown), `t14.5` (loop end), `network_original_t9.0`. Before: hub slightly right of centre, 4 mid persons at different heights and distances, 8 small people unevenly spread (3 left, 4 right), empty left. After: hub on the axis, 2 mirrored mid pairs, 4 mirrored small pairs, same left and right margins.

## Progress
- analysis of the three HTML files: done
- generator tool (tool/onboarding_anim/extract_art.py + generated/): done
- path parser + Tf: done
- palette (authored colours, purpleToBlue): done
- scene renderer (svg_scene.dart): done
- 3 painters (shield, network, buildings) + OnboardingArt widget/controller: done
- debug onboarding copy (/debug/onboarding): done
- lab screen (/debug/onboarding-anim): done
- route registration: done
- tests written (parser, generator, painters, goldens, widgets, routes, guard): done
- widget test fix (debug onboarding overflow in test viewport): done
- colour scan allowlist: done
- docs body + CLAUDE.md line: done
- analyze / test (1352 pass) / apk build --debug: done
- fixes pass 2 (speed, missing icons, coverage, FPS readout): done, see "Fixes pass 2"
- full-bleed layout + crop windows + lab switch: done, see "Full-bleed layout"
- network shows 5 persons + speed constants: done, see "Five persons and speed"
- network tier 2 (one more layer of people): done, see "Network tiers"
- network symmetric layout (mirror about the axis, pairs, badge map, orbs): done, see "Network: symmetric layout"
