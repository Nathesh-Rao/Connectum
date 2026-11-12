# Connectum mobile design guide (for the web team)

What the mobile app looks like and how it is built, taken from the real code (tokens, widgets, assets) of `connectum_mobile`. Documentation, generated data files and copied assets only; nothing here changes the app. Anything not read from code or `CLAUDE.md` is marked *(inferred)*.

## Reading order

1. `01-colors.md`: every colour token with role and "do not use for", contrast numbers, shadows, tones, charts and the exact **avatar / chat-tile colour** rules.
2. `02-widgets.md`: how the sizes were found (formulas for the web to recompute), the bubble surface recipe, every widget with states, tokens and reasons, do/don't.
3. `03-splash-logo-loader.md`: the animated logo (timeline, morph maths, colours, demo).
4. `04-icons-and-assets.md`: every icon, Lottie, picture and font with size, tint and web reproduction.

## Files

| Path | What |
|---|---|
| `tokens/tokens.json`, `tokens/tokens.css` | Generated: colours, tones, spacing, radius, text styles, shadows, motion, bubble surface, avatar palette, contrast table, notification and action rules. CSS variables are `--color-*`, `--tone-*`, `--chart-*`, `--space-*`, `--radius-*`, `--text-*`, `--shadow-*`, `--duration-*`, `--ease-*`. |
| `tokens/avatar-color.ts`, `avatar-color.test.ts`, `avatar-color-vectors.json`, `dart-case-map.json` | Reference implementation of the avatar colour rules, 130 test vectors produced by the real Dart code, Dart's case-mapping table. Run: `node --experimental-strip-types tokens/avatar-color.test.ts` (Node 22.6+). |
| `logo-loader/logo_polys.json`, `logo-loader/logo-loader-demo.html` | Generated logo data and a self-contained vanilla JS/SVG demo of the loader and the splash timeline. |
| `assets/` | Copied icons, state pictures, `*_blue` Lottie files, logo, fonts (`FONTS-NOTE.md` about licences). |
| `../tool/design_guide/` | The generator (`flutter test tool/design_guide/generate.dart`); `../test/core/avatar_color_vectors_test.dart` fails if the vectors drift from the code. |

## How to use it

Start from `tokens.css` (copy the `:root` block) or `tokens.json`; implement components from `02-widgets.md`; port `avatar-color.ts` as is and run its test against the vectors; take assets from `assets/`. After a palette change in the app, regenerate (one command) and re-read the diff.

## How the sizes are meant to be adapted

Sizes are in dp and 1 dp = 1 CSS px at mobile. Colours, radius proportions, state behaviour, type ratios and motion timing must stay identical. Absolute widths and heights, density and breakpoints may change on desktop: recompute control padding from `padV = (H - 2 - fontSize * lineHeight) / 2`, keep pills at `radius = height / 2`, and add hover states (mobile has none). The full "must stay identical" and "may adapt" lists are in `02-widgets.md` part A.9.
