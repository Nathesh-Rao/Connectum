# Assets audit (Stage 1, report only, nothing changed)

Date 2026-11-27, branch `master`. Sizes in bytes. "APK" = size inside the release APK (PNGs are stored as is, JSON/JS/text compresses).

## 1. Starting size

`flutter build apk --release --analyze-size --target-platform android-arm64 --dart-define=BASE_URL=https://connectum.app --dart-define=WS_URL=wss://connectum.app/ws` ran fine (release signing config present, never read).

| Measure | Value |
|---|---|
| app-release.apk | 78.3 MB on disk (analyzer: 75 MB compressed) |
| `flutter_assets/` inside the APK | 4,346,409 |
| of which `assets/` (ours) | 2,187,149 (icons 1,013,467, images 755,039, fonts 240,892, debug 116,908, form_logic 33,161, lottie 27,682) |
| of which `packages/pdfrx` (`pdfium.wasm` 1,977,532 + worker js 18,139) | 1,996,327 |
| `mobile-handoff/e2e-vectors.json` (declared in pubspec) | 9,973 |
| `lib/` native libs | 69,207,872 (arm64 41.5 MB, armeabi-v7a 10.8 MB, x86_64 16.9 MB) |
| `libapp.so` (Dart AOT) | 14,943,152 |
| `mlkit_barcode_models` (mobile_scanner) | 880,888 |
| classes.dex + classes2.dex | 2,302,121 |

Raw bytes of everything declared under `flutter: assets:` and `fonts:` (before APK compression): **3,510,058**
(images/*.png 389,518; states 365,639; icons/home 190,654; bottom_nav 199,255; chat 65,243; agile 558,315; lottie 317,510; `assets/debug` json 294,854 + avatars 4,086; form_logic 598,856; e2e-vectors 36,180; fonts 489,948).

Note: `--target-platform android-arm64` still packs armeabi-v7a and x86_64 `.so` files (plugin prebuilt libs: libbarhopper, libpdfium, quickjs, sqlite3, webcrypto). The assets are a small part (about 4.3 MB) of a 75 MB APK; the native libs dominate.

## 2. Inventory of what ships

Declared in `pubspec.yaml`:

| Entry | Files shipped | Raw bytes |
|---|---|---|
| `assets/images/connectum_logo_blue.png` (also covered by the next line, declared twice) | 1 | 146,638 |
| `assets/images/` (not recursive) | 4 png | 389,518 |
| `assets/images/states/` | 8 png + credits.md | 365,639 |
| `assets/icons/home/` | 11 png | 190,654 |
| `assets/icons/bottom_nav/` | 12 png | 199,255 |
| `assets/icons/chat/` | 5 png | 65,243 |
| `assets/icons/agile/agile_logo.png` | 1 | 558,315 |
| `assets/lottie/` | 7 json + credits.md | 317,510 |
| `mobile-handoff/e2e-vectors.json` | 1 | 36,180 |
| `assets/debug/e2e-attachment-vectors.json`, `e2e-rewrap-vectors.json` | 2 | 294,854 |
| `assets/debug/avatars/` | 4 png | 4,086 |
| `assets/form_logic/` (6 files listed one by one) | 6 | 598,856 |
| fonts (7 files, 2 families) | 7 | 489,948 |
| `uses-material-design: true` | MaterialIcons-Regular.otf | 23,001 in APK |
| package-provided | `pdfrx` pdfium.wasm + worker js, 1,996,327 in APK; `mobile_scanner` mlkit models 880,888 (not flutter_assets) | |

Declared but nothing missing: every declared path exists. No generated asset class (no flutter_gen). `assets/icons/notification/` does not exist.

**Not declared, do not ship:** `assets/icons/loader/spinner-double.svg` (3,231; source for `tool/loader/extract_spinner.py` and `test/core/app_spinner_double_test.dart`; keep). `.DS_Store` files. Everything else under `assets/` is declared. There are no animated SVGs, onboarding images or sound files in `assets/` (onboarding is native painters; old Lottie onboarding is in `backup/`).

## 3. USED (referenced by full path or constant)

| File | Referenced by | Raw |
|---|---|---|
| `assets/images/connectum_logo_blue.png` | `app_logo.dart`, `app_qr_share_card.dart`, `conversation_controller.dart:1429`; source for `tool/icons`, `tool/splash` | 146,638 |
| `assets/icons/agile/agile_logo.png` | `app_agile_footer.dart` (`logoAsset`) | 558,315 |
| `assets/icons/home/new_chat.png`, `work_space.png`, `group.png`, `ticket.png` | `AppIcons.home.*` in `app_icons.dart` (all four used in lib) | 13,455 / 27,153 / 16,837 / 16,781 |
| `assets/icons/bottom_nav/*` (12 files: chat, ai, submissions, profile, smart_view, inbox x selected/unselected) | `AppIcons.bottomNav.*`; profile pair is used by `app_bottom_nav.dart` and `test/core/app_bottom_nav_test.dart` | 199,255 |
| `assets/icons/chat/add_forms.png`, `attachements.png` | `conversation_composer.dart:195,362`, asserted by `test/conversation/composer_source_test.dart` | 17,015 / 14,786 |
| `assets/lottie/loading_blue.json` | `app_loading.dart` | 109,074 |
| `assets/lottie/qr_loading_blue.json` | `app_qr_loading.dart` | 33,555 |
| `assets/lottie/state_success_blue.json` | `app_success_animation.dart` | 6,241 |
| `assets/lottie/robot.json` | `ai_agents_view.dart:12` | 20,364 |
| `assets/form_logic/form-logic-host-shim.js`, `form-logic.bundle.js`, `form-logic-conformance.json`, `manifest.json`, `parity_vectors.json` | `form_logic_assets.dart` (`loadVerified`, called by `form_logic_service.dart` in production, manifest hash-verifies the three loaded files). Never touch | 9,696 / 55,911 / 497,574 / 2,176 / 9,422 |
| fonts, see section 7 | `AppText`, `AppTheme` | |

## 4. DYNAMIC (string-built references)

Only two patterns exist in the app (searched `assets/...$`, `'assets/' +`, `rootBundle`, `AssetManifest`, `AssetImage`, `Lottie.asset`, `AssetLottie`):

| Pattern | Where | Reaches (all stay) |
|---|---|---|
| `'assets/images/states/$file.png'` | `app_state_image.dart:26`, `file` from `AppStateImageKind` | `empty_chats`, `empty_enterprises`, `empty_generic`, `no_results`, `offline`, `error`, `locked` (7 PNGs). `coming_soon.png` is not in the enum, so it is not reached |
| `url.startsWith('asset:')` -> `AssetImage(url.substring(6))` | `lib/core/widgets/avatar_image.dart:37` | any path given as `asset:<path>`. Strings found: `assets/debug/avatars/demo_1/2/3.png` (`seed_ui.dart`, `avatar_samples.dart`), `missing.png` and `not-there.png` (test, intentionally absent). `demo_4.png` appears nowhere |
| `rootBundle.load('$_dir$name')` | `form_logic_assets.dart` (`_dir = assets/form_logic/`, names from the manifest) | the form_logic files (never touch) |
| `rootBundle.loadString(...)` fixed paths | `debug_e2e_controller.dart` (3 vectors files), `sample_forms.dart` (`sample_cases.json`) | see section 6 |

Tests that read from disk (not the bundle): fonts via `File('assets/fonts/$family-$w.ttf')`; `test/core/decor_golden_test.dart` lists `assets/lottie/*.json`, loads `${name}_blue.json` and checks the files `lib` references for warm colours; `tool/lottie/recolor_lottie.py` globs `assets/lottie/*.json` (non `_blue` ones are its inputs).

## 5. NATIVE (not Flutter assets, never touched)

Android `res/`: `mipmap-*` launcher icons (`ic_launcher`, `ic_launcher_round`), `drawable-*/ic_launcher_foreground.png`, `ic_launcher_monochrome.png`, `splash_icon.png`, `splash_logo.png`, `drawable/ic_stat_notification.xml` (kept by `res/raw/keep.xml`), `launch_background.xml`, `xml/` backup and network configs, `values*`. iOS `Assets.xcassets/AppIcon.appiconset` and `LaunchImage.imageset`. Config: `flutter_launcher_icons:` in pubspec reads `branding/icon/*`. Native splash is made by `tool/splash/make_splash.py` from `assets/images/connectum_logo_blue.png` (a Flutter asset used as a script input, listed in USED).

## 6. TEST / DEBUG ONLY (keep; they ship in release)

Flutter cannot bundle an asset for debug only (also noted in CLAUDE.md "Before release"). A release build can only exclude them by removing the pubspec entry, which breaks the debug route (guarded by `kReleaseMode`, Task S) or by moving them to a Flutter `flavors:` asset entry (not used). The code that loads them is not reachable in release.

| File | Used only by | Raw | In APK |
|---|---|---|---|
| `assets/debug/e2e-attachment-vectors.json` | `/debug/e2e` | 273,110 | 108,850 |
| `assets/debug/e2e-rewrap-vectors.json` | `/debug/e2e`, `hand_on_vectors.dart` | 21,744 | 3,972 |
| `mobile-handoff/e2e-vectors.json` | `/debug/e2e` | 36,180 | 9,973 |
| `assets/debug/avatars/demo_1..3.png` | `seed_ui.dart` (SEED_UI), `/gallery` avatar samples | 3,124 | 3,124 |
| `assets/form_logic/sample_cases.json` | `SampleForms` (`/debug/formlogic`, `/debug/forms`) | 24,077 | 3,389 |
| `assets/lottie/state_success_blue.json` | production (success check); also `/debug/assets` | n/a (USED) | |
| `assets/icons/loader/spinner-double.svg` | test + generator, not shipped | | 0 |

Total shipped debug-only: about 134,000 in the APK (about 360,000 raw). Removing the `/debug/e2e` route (already on the CLAUDE.md before-release list) takes the first three out.

## 7. Fonts

| Family | Weight | File | Raw | Used? |
|---|---|---|---|---|
| PlusJakartaSans | 400 | Regular | 63,336 | Yes (31 `FontWeight.w400` + AppText styles) |
| PlusJakartaSans | 500 | Medium | 63,404 | Yes (24) |
| PlusJakartaSans | 600 | SemiBold | 63,412 | Yes (53) |
| PlusJakartaSans | 700 | Bold | 63,336 | Yes (33) |
| PlusJakartaSans | 800 | ExtraBold | 63,372 | Yes, one place: `document_card.dart:143` `FontWeight.w800` (candidate only if that one style is changed to w700, not an unused file) |
| SpaceGrotesk | 600 | SemiBold | 86,572 | Yes: `AppText.displayBrandSm` (display family) |
| SpaceGrotesk | 700 | Bold | 86,516 | Yes: `AppText.displayBrand` |

`AppTheme` and `AppText.fontFamily` = PlusJakartaSans; `displayFontFamily` = SpaceGrotesk (two styles). `app_sv.dart` uses `_font = AppText.fontFamily` and `'monospace'` (system). No `FontWeight.bold/w300/w900` anywhere in lib. **No unused font file.** Tests load the same files from disk.

## 8. UNUSED CANDIDATES

Method for each: searched the whole repo (excluding `build/`, `.dart_tool/`, `.git/`, `assets/`) for the file name, then the name without extension, plus partial path, in `lib test tool android ios pubspec.yaml integration_test docs mobile-handoff design-guide-mobile reference CLAUDE.md README.md branding incoming backup`, and checked interpolation patterns (section 4) and `git log -S`. "Docs only" means the only hits are `design-guide-mobile/04-icons-and-assets.md` (which itself says they are "not referenced by any code") or `03-splash-logo-loader.md`.

| File | Raw | In APK | Evidence |
|---|---|---|---|
| `assets/icons/home/new_chat_thin.png` | 16,703 | 16,703 | name and stem: docs only. Not in `app_icons.dart`. `git log -S new_chat_thin -- lib test pubspec.yaml tool`: nothing |
| `assets/icons/home/ticket1.png` | 15,017 | 15,017 | name `ticket1`: docs only; `git log -S ticket1`: nothing. Stem `ticket` matches only `ticket.png` and unrelated words |
| `assets/icons/home/ticket2.png` .. `ticket5.png` | 15,097 / 23,084 / 12,215 / 18,183 | same | no hit anywhere (ticket6 only in docs); no `ticket$n` interpolation; git log nothing |
| `assets/icons/home/ticket6.png` | 16,129 | 16,129 | docs only; git log nothing |
| `assets/icons/chat/add_forms2.png`, `add_forms3.png`, `add_forms4.png` | 15,872 / 8,803 / 8,767 | same | no hit anywhere; composer uses only `add_forms.png` (also pinned by `composer_source_test.dart`); git log nothing |
| `assets/images/states/coming_soon.png` | 76,405 | 76,405 | docs only; no `AppStateImageKind` for it (the "coming soon" in `ai_agents_view.dart` is a widget, not this file); last mention in git history was the initial import commit 991c38e / "Before blue logo" b9f3c58 |
| `assets/images/512_blue_logo.png` | 49,864 | 49,864 | no hit anywhere, case-insensitive too; git log nothing |
| `assets/images/Connectum-C.png` | 178,559 | 178,559 | docs only (listed there as a legacy PNG logo, "not copied"); only older commits (b9f3c58, 8fb8740, 8800cd5 backup) mention it; current lib/tool/test do not |
| `assets/images/connectum_logo.png` | 14,457 | 14,457 | docs only (legacy). Stem `connectum_logo` only matches `connectum_logo_blue`. Old commits (058b381, 22ee74c) used it; none now |
| `assets/lottie/loading.json`, `qr_loading.json`, `state_success.json` (orange originals) | 108,698 / 33,231 / 6,116 | 8,835 / 2,613 / 1,065 | no runtime reference; code loads the `_blue` copies. **Caution:** they are the inputs of `tool/lottie/recolor_lottie.py` (globs `assets/lottie/*.json`) and `decor_golden_test.dart` globs the folder; moving them is safe for tests (`_blue` files are the ones loaded) but the recolor script would then have nothing to regenerate from. Keep unless you accept that |
| `assets/debug/avatars/demo_4.png` | 962 | 962 | no hit anywhere; no `demo_$i` loop; `asset:` strings use demo_1..3 only. Debug folder |
| `assets/images/states/credits.md`, `assets/lottie/credits.md` | 232 / 231 | 114 / 165 | packaged by the folder declaration; not loaded by any code (basename hits: docs only); empty source/licence tables |

Totals if every row were moved: 618,625 raw, 482,909 in the APK. Without the lottie originals, demo_4 and credits: 469,155 raw / 469,155 in the APK (PNGs are not compressed). **That is about 0.6% of the APK; the assets are not where the size is.**

Not candidates (looked at, kept): `assets/images/connectum_logo_blue.png` (declared twice in pubspec; the single-file line is redundant with `assets/images/`, harmless), `assets/icons/loader/spinner-double.svg` (not shipped), `spinner` generator inputs, all form_logic files.

## 9. 15 largest asset files

| # | File | Raw | Could it be smaller? |
|---|---|---|---|
| 1 | `assets/icons/agile/agile_logo.png` | 558,315 | 932x932 RGBA PNG shown at height 15 logical px (`AppSpacing.agileLogoHeight`). A 128-256 px version (or WebP) would be a few KB. Largest single saving (about 540 KB) |
| 2 | `assets/form_logic/form-logic-conformance.json` | 497,574 | compresses to 9,247 in the APK; hash-pinned by `manifest.json`, do not change |
| 3 | `assets/debug/e2e-attachment-vectors.json` | 273,110 | 108,850 in the APK; debug only |
| 4 | `assets/images/Connectum-C.png` | 178,559 | unused candidate |
| 5 | `assets/images/connectum_logo_blue.png` | 146,638 | 1408x1464; shown at 26-66 px wide and in the QR share card (check export size). Also the script source for icons/splash; a 512 px copy or WebP would be about 30 KB |
| 6 | `assets/lottie/loading_blue.json` | 109,074 | 8,855 in the APK, fine |
| 7 | `assets/lottie/loading.json` | 108,698 | unused candidate (original) |
| 8-9 | `SpaceGrotesk-SemiBold.ttf` / `Bold.ttf` | 86,572 / 86,516 | TTFs at 43 KB in APK; could be subset to Latin |
| 10 | `assets/images/states/coming_soon.png` | 76,405 | unused candidate |
| 11-15 | `PlusJakartaSans-SemiBold / Medium / ExtraBold / Regular / Bold` | about 63,400 each | already about 31 KB in the APK; subsetting possible |
| next | `states/empty_chats.png` 59,195; `offline.png` 50,988; `512_blue_logo.png` 49,864; `error.png` 44,685 | | all 512x512 RGBA, shown at 160 px (`AppSpacing.stateImage`, decoded with `ResizeImage`, so memory is fine); at 256x256 or WebP each would be 10-25 KB. `cwebp` is installed (`/opt/homebrew/bin/cwebp`), `pngquant` is not |

No SVG with an embedded bitmap (`spinner-double.svg` has 0 `data:image`).

## 10. Packages with no import

Checked every `dependencies:` entry with `grep package:<name>/` in lib, test, tool: **all 30 are imported in `lib/`** (smallest: connectivity_plus, mime, open_filex, qr_flutter, flutter_local_notifications, pdfrx, video_player, xml, url_launcher, palette_generator, tutorial_coach_mark: 1 file each). No removal candidate. Dev: `flutter_lints` (analysis_options), `sqflite_common_ffi` (2 tests), `flutter_launcher_icons` (CLI via pubspec config) all in use. `path`, `get`, `dio` etc. all imported.
Heavy but used: `pdfrx` (wasm 1.98 MB + libpdfium 3 ABIs 13 MB), `mobile_scanner` (libbarhopper 14 MB across ABIs, models 0.9 MB), `webcrypto`, `quickjs_engine`.

## 11. Build flags for Play

| Flag | Status |
|---|---|
| R8 minify / `shrinkResources` | Not set in `android/app/build.gradle.kts` (release block only sets signing); no `proguard-rules.pro`. Relies on the Flutter Gradle plugin defaults for release (classes.dex is 2.3 MB, so shrinking looks active); not confirmed explicitly |
| `--split-per-abi` | Not used. The documented release build is `flutter build appbundle`, which Play splits per ABI itself. The APK I measured holds arm64, armeabi-v7a and x86_64 native libs (no `abiFilters`/`splits`) |
| `--obfuscate --split-debug-info` | Not used (`mobile-handoff/crashlytics.md`: "Release is built without `--obfuscate`"). Would shrink `libapp.so` (14.9 MB) a little; needs symbol upload to Crashlytics |
| `dart run pdfrx:remove_wasm_modules` | Not used (no reference anywhere). `pdfium.wasm` is 1,977,532 in the APK and is not needed on Android; this is the largest asset-type win (about 2 MB). Run before the Play bundle, restore after (`flutter pub get`); check pdfrx docs for the exact undo |
| Dart tree-shaking of icons | Flutter default (MaterialIcons 23 KB) |

## 12. Summary of what could shrink the release build (for later, not done)

1. `pdfrx:remove_wasm_modules`: about 2.0 MB (package asset, no code risk on Android).
2. Downscale `agile_logo.png`: about 0.5 MB.
3. Unused candidates above: about 0.47 MB (0.62 MB with the Lottie originals).
4. Downscale `connectum_logo_blue.png` and the state PNGs: about 0.3-0.5 MB.
5. Remove debug routes' vectors before release: about 0.13 MB.
6. Native libs (about 69 MB): ABI filtering or an AAB is the real lever.
