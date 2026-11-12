# 02 · Widgets and how the sizes work

Source of truth: `lib/core/widgets/*`, `lib/core/theme/*`, `CLAUDE.md`. Numbers are in dp; at mobile **1 dp = 1 CSS px**. Everything marked *(inferred)* is my reading of the code, not a statement in the code or in CLAUDE.md. Machine-readable values: `tokens/tokens.json` and `tokens/tokens.css`.

Font families: **Plus Jakarta Sans** (`--font-sans`) is the UI font and is set as the theme font, so every text style below uses it. **Space Grotesk** (`--font-display`, weights 600 and 700 only) is used by `displayBrand` (32 / 700) and `displayBrandSm` (24 / 600), today the Agents tab title. Both are bundled in `assets/fonts/`.

---

## Part A · How the sizes were found

### A.1 Base unit and spacing scale (measured)

`AppSpacing` steps: **xxs 4, xs 8, sm 12, md 16, lg 20, xl 24, xxl 32**. That is a **4 dp base unit** and multiples 1, 2, 3, 4, 5, 6, 8 (`space(n) = 4 * n`, n in {1,2,3,4,5,6,8}). The page gutter is `page` = 24 (6 units). Layout code uses these named steps almost everywhere; the odd values below are measured from the approved prototype and are **not** on the grid (the code has them as named constants): sheet padding 22 / 10 / 30 (left-right / top / bottom), control side padding 15, button side padding 18 (compact 14), sheet field height 49, filter tab 45, row height 75. *(Why they are off-grid: inferred, they were matched to the prototype by eye; CLAUDE.md says "match spacing, radii, colours, type" to `reference/prototype`.)*

### A.2 Touch targets

- `minTapTarget` = 44, `iconButton` = 44, `composerButton` = 44, text button minimum 44 x 44, pill-bar hit row 44 (the visible pill is 28 to 34 high inside it).
- **48 dp** is used where Material asks for it: `badgedIconHit` 48, popup menu rows 48, document action 48, the action-bar expand strip hit area (48), bottom-nav items (`navItemHeight` 52, CLAUDE.md says "at least 48 dp").
- **Note:** the minimum constant in code is 44, not 48. For a pointer device the web may go below both; for touch on the web use 44 as the floor and 48 where mobile does.

### A.3 Control heights come from padding + line height (measured)

- **Field:** `minHeight` = 52 = 2 x border (1) + 2 x vertical padding + line height. The line height is fixed with a forced strut: `input` is 13 x 1.3 = 16.9 px. So `vertical padding = (minHeight - 2 - lineHeight) / 2 = (52 - 2 - 16.9) / 2 = 16.55`. Rule: `padV = (H - 2*border - fontSize*lineHeight) / 2`; the text stays vertically centred because the height comes from the constraint, not from a fixed box.
- **Buttons:** only a minimum: 52 (compact 50); the label is `button` 14 / 600 / lh 1.3 (18.2 px) centred; side padding 18. Because min-height governs, the label is centred with `align-items: center`, not with vertical padding.
- **Chat row:** `chatRowHeight` 86 = 2 x md (16) padding + title 14 x 1.5 (21) + preview 11 x 1.4 (15.4) + type label 11 x 1.6 (17.6) = 85.99. It is a minimum height.
- **Bottom nav:** 1 (border) + 10 + 52 (item) + 5 + system bottom inset.
- **Pills and tags:** fixed heights: compact pill 28, regular pill 34, tag 22, status pill 22, priority pill 20, unread badge 19.
- **Headers:** `headerHeight` 72, conversation header 65, search field 44, segment 44, chip 40.

### A.4 Radii (measured values, relations partly inferred)

`xs` 8 (search field, small blocks) - `control` 10 (fields, buttons, square avatars, action buttons) - `tile` 11 - `md` 12 (attachments, avatar-size tiles) - `card` 14 (cards, notices) - `bubble` 15 (message bubbles; the last bubble of a run gets `bubbleTail` 4 on the sender's lower corner) - `lg` 16 (popup menus) - `sheet` 20 (top corners of sheets) - `pill` 999 (anything fully round) - small: `cell` 8, `segment` 7, `badge` 4.

Relations *(inferred)*: a control's radius is roughly 0.19 x its height at 52 dp (10/52) and 0.23 x at the 44 dp square avatar (10/44), so it is a **fixed 10 dp for every control from 36 to 52 dp high rather than a ratio**; pills use `radius = height / 2` (999 is "always full"); cards 14 and sheets 20 are fixed steps. Nested radius = outer radius - border width (the form card clips its content at 14 - 1 = 13).

### A.5 Type scale and line heights (measured)

Sizes: caption/label **11**, readable **12**, body **13**, button/supporting **14**, subtitle **17**, title **21**, heading **26**, hero 29, display **30** (brand display 32). Steps are about 1.08 between 11 and 14, then about 1.2 (17, 21, 26) *(inferred: a tight small scale and a minor-third heading scale)*. CLAUDE.md minimums: 11 for labels and captions, 12 for readable text.

Line height by role: body and captions **1.6** (messages 1.6), controls and inputs **1.3**, headings and subtitles **1.2**, title 1.3, rows 1.4 to 1.5, hero copy and slide copy 1.8. Letter spacing is **negative on large type**: display -1.2 (-4 %), heading -1, title -1, hero -1, subtitle -0.4, row title -0.3, brand display -0.5; zero for body; **positive on tiny caps** (kicker 1.5, eyebrow 1.1). Rule *(inferred)*: `letterSpacing = -0.04 x size` for sizes 21 and up, fading to zero by 13.

### A.6 Icon sizes against text, avatar sizes (measured)

Inline icons 13 to 14 (next to 11 to 12 text), buttons 18 (14 px label), popup menu 20, app bar and bottom nav 22 (28 dp box), FAB 24, feed icon 22 in a 44 circle, state pictures 160 (96 small, 40 in a row). Rule: **glyph = 0.5 x its container** for avatar and feed tiles (22 in 44), **letter = 0.4 x avatar size**. Avatars: 44 (`avatar`), 36 (`avatarSmall`), 43 (`tileSize`), 72 (profile card), 32 in compact sheets.

### A.7 Motion (measured)

Durations (`AppDurations`): fast 190 ms (field focus, pills, small fades), fab 200 ms, base 320 ms (card open, notices), page 450 ms, slow 500 ms (sheet, state picture intro), reduced 150 ms, stagger 55 ms, spin 900 ms (loading spinner turn), chart grow 400 ms. Curves: `out` = `cubic-bezier(0.25, 0.06, 0.12, 1.0)` (default for UI), `easeIn` = `cubic-bezier(0.4, 0.0, 1.0, 1.0)`, `inOut` = `cubic-bezier(0.65, 0.0, 0.35, 1.0)`. Sheets use a spring (mass 1, stiffness 300, damping 32, settle 500 ms); press feedback uses a spring (mass 1, stiffness 420, damping 34) to scale **0.97**. With "reduce motion" the animations switch off or shorten (nav, popup 150 ms, state pictures, splash).

### A.8 dp to CSS conversion

| dp | CSS px | rem at 16 px root | Where |
|---|---|---|---|
| 4 | 4px | 0.25rem | xxs, bubble run gap 2 is half |
| 8 | 8px | 0.5rem | xs, small gaps |
| 12 | 12px | 0.75rem | sm |
| 16 | 16px | 1rem | md, card padding |
| 24 | 24px | 1.5rem | xl, page gutter |
| 44 | 44px | 2.75rem | min tap target, avatar |
| 48 | 48px | 3rem | large tap target |
| 52 | 52px | 3.25rem | field and button height |
| 11 / 12 / 13 / 14 | same px | 0.6875 / 0.75 / 0.8125 / 0.875rem | text |

Text: Flutter scales text with the user's text scale (popups and fixed sheets clamp it to 1.3); on the web use `rem` for text and let the browser setting scale it. Letter spacing in dp is `px`. Line heights are unitless in CSS (`line-height: 1.6`).

### A.9 What must stay identical, what the web may adapt

**Must stay identical:** every colour and its role (01-colors.md) including the avatar rules; the radius steps and the pill rule; the state behaviour (focus ring, error border and text, disabled, pressed, selected); the type ratios (sizes, weights, line-height ratios, negative tracking on headings); the motion timings and curves; the bubble surface on filled primary buttons and the FAB; white page + hairline / shadow separation; white-on-`primary` and never small text on `primaryBright`.

**The web may adapt:** absolute widths and heights (a 52 px button is large on a pointer; 40 px is fine), density (smaller gutters on desktop, `padV` recomputed from the formula in A.3), breakpoints and multi-column layouts, hover states and cursor styles (mobile has none: use `fill` as the hover fill and keep the pressed state as the 0.97 scale or the `primaryStrong` 28 % overlay), keyboard focus rings (use the focus-ring shadow), scroll behaviour, tap targets for pointer (44 floor is a touch rule), sheet-to-dialog conversion on wide screens.

**Measured vs inferred:** token values are measured (read from code). The reasons given for off-grid numbers, the radius relations in A.4 and the type-scale ratios in A.5 are inferred.

---

## Part B · The primary button "bubble surface"

A filled primary button (and the FAB) is `primary` `#0052CC` with separate glossy round **discs** painted over it, clipped to the button's rounded rectangle, plus a 1 px top highlight. Static: painted once per size and state, no animation. Source: `lib/core/widgets/app_bubble_surface.dart`.

**Disc layout** (paint order = row order). `dx`, `dy` are the disc centre as a fraction of the button **width** and **height**; `diameter` is a multiple of the button **height**; every disc is clipped by the button, so discs may hang over the edges.

Width class is chosen from the button's **rendered width**: wide from 280 px, medium from 160 px, else narrow. The extended FAB uses the narrow set; the circle FAB (about square, width / height under 1.3) uses its own set.

**Wide (>= 280 px), 7 discs**

| # | dx (x width) | dy (x height) | diameter (x height) | colour | opacity |
|---|---|---|---|---|---|
| 1 | 0.02 | 0.85 | 1.1 | `#00338D` | 0.3 |
| 2 | 0.08 | 0.2 | 0.8 | `#0078E8` | 0.24 |
| 3 | 0.17 | 0.72 | 0.55 | `#00A1E8` | 0.16 |
| 4 | 0.5 | 0.85 | 0.45 | `#00B4F1` | 0.08 |
| 5 | 0.84 | 0.15 | 1 | `#00338D` | 0.28 |
| 6 | 0.92 | 0.8 | 0.75 | `#0078E8` | 0.26 |
| 7 | 0.76 | 0.62 | 0.5 | `#00B4F1` | 0.14 |

**Medium (160 to 280 px), 5 discs**

| # | dx (x width) | dy (x height) | diameter (x height) | colour | opacity |
|---|---|---|---|---|---|
| 1 | 0.03 | 0.85 | 1.1 | `#00338D` | 0.3 |
| 2 | 0.1 | 0.2 | 0.75 | `#0078E8` | 0.24 |
| 3 | 0.52 | 0.92 | 0.45 | `#00B4F1` | 0.08 |
| 4 | 0.92 | 0.15 | 1 | `#00338D` | 0.28 |
| 5 | 0.9 | 0.85 | 0.7 | `#00A1E8` | 0.18 |

**Narrow (< 160 px) and the extended FAB, 3 discs**

| # | dx (x width) | dy (x height) | diameter (x height) | colour | opacity |
|---|---|---|---|---|---|
| 1 | 0 | 0.8 | 1 | `#00338D` | 0.3 |
| 2 | 0.12 | 0.15 | 0.5 | `#00A1E8` | 0.16 |
| 3 | 1 | 0.2 | 0.95 | `#0078E8` | 0.26 |

**Circle FAB, 3 discs**

| # | dx (x width) | dy (x height) | diameter (x height) | colour | opacity |
|---|---|---|---|---|---|
| 1 | 0.15 | 0.85 | 0.9 | `#00338D` | 0.3 |
| 2 | 0.85 | 0.15 | 0.85 | `#0078E8` | 0.26 |
| 3 | 0.8 | 0.9 | 0.5 | `#00A1E8` | 0.16 |

**Per-disc gloss:** each disc is a radial gradient from its colour at its opacity (centre of the gradient at alignment (-0.35, -0.4) of the disc's own square, i.e. at 32.5 % / 30 % of it, radius 0.95 x the disc diameter) fading to 0.35 x that opacity at the radius, and staying at that value beyond it. Global opacity multiplier 1.

**Top inner highlight:** a 1 px line along the inside of the rounded edge (the outline deflated by 0.5 px), a vertical gradient from white at 12 % at the top to 0 % at 35 % of the height.

**Pressed:** `#00338D` at 28 % over the whole surface, plus the 0.97 scale spring. **Disabled:** flat `#99BAEB`, no discs, no shadow. **Label band:** the middle 40 % x 40 % must stay calm; the contrast test checks white on the lightest stack that can reach it: 6.25:1 on a 320 x 52 button.

### Web recipe (CSS, one element + one child per disc)

```html
<button class="btn-primary" style="--h:52px">
  <i style="--dx:.02;--dy:.85;--d:1.10;--c:0,51,141;--o:.30"></i>
  <!-- one <i> per disc of the set for the button width -->
  <span class="label">Continue</span>
</button>
```

```css
.btn-primary { position:relative; overflow:hidden; min-height:var(--h); padding:0 18px;
  border:0; border-radius:10px; background:#0052cc; color:#fff; font:600 14px/1.3 var(--font-sans); }
.btn-primary > i { position:absolute; border-radius:50%; pointer-events:none;
  width:calc(var(--d) * var(--h)); height:calc(var(--d) * var(--h));
  left:calc(var(--dx) * 100% - var(--d) * var(--h) / 2);
  top:calc(var(--dy) * 100% - var(--d) * var(--h) / 2);
  background:radial-gradient(circle calc(.95 * var(--d) * var(--h)) at 32.5% 30%,
    rgba(var(--c), var(--o)) 0, rgba(var(--c), calc(var(--o) * 0.35)) 100%); }
.btn-primary::after { content:""; position:absolute; inset:0; border-radius:inherit; pointer-events:none;
  border:1px solid transparent; /* top highlight */
  background:linear-gradient(rgba(255,255,255,0.12), rgba(255,255,255,0) 35%) border-box;
  -webkit-mask:linear-gradient(#000 0 0) padding-box exclude, linear-gradient(#000 0 0);
  -webkit-mask-composite:xor; mask-composite:exclude; }
.btn-primary .label { position:relative; z-index:1; }
.btn-primary:active { transform:scale(.97); box-shadow:inset 0 0 0 999px rgba(0,51,141,0.28); }
.btn-primary:disabled { background:#99BAEB; }
.btn-primary:disabled > i { display:none; }
```

`--c` is the disc colour as `r,g,b` (from the table: `primaryStrong` 0,51,141; `primaryBright` 0,120,232; `primaryLight` 0,180,241; `cyanBlue` 0,161,232). Choose the disc set in JS from the element's width (`ResizeObserver`), or fix one set per button class.

### Web recipe (inline SVG, exact)

```js
// discs: one of the four sets of tokens.json -> bubbleSurface.sets
function bubbleSvg(W, H, radius, discs, base = "#0052CC") {
  const defs = discs.map((d, i) => `<radialGradient id="g${i}" cx="0.325" cy="0.3" r="0.95">
      <stop offset="0" stop-color="${d.color}" stop-opacity="${d.opacity}"/>
      <stop offset="1" stop-color="${d.color}" stop-opacity="${d.opacity * 0.35}"/></radialGradient>`).join("");
  const circles = discs.map((d, i) => {
    const r = d.diameter * H / 2;
    return `<circle cx="${d.dx * W}" cy="${d.dy * H}" r="${r}" fill="url(#g${i})"/>`;
  }).join("");
  return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs>${defs}
    <clipPath id="c"><rect width="${W}" height="${H}" rx="${radius}"/></clipPath></defs>
    <g clip-path="url(#c)"><rect width="${W}" height="${H}" fill="${base}"/>${circles}</g></svg>`;
}
```

(`objectBoundingBox` gradient units make `r="0.95"` equal to 0.95 x the circle's diameter, as in the app. Give each button's gradients unique ids.)

---

## Part C · Widgets

For every widget: purpose, anatomy, states, tokens, reason, accessibility.

### C.1 AppTextField (`app_text_field.dart`)

- **Purpose:** the only text field. Anatomy (top to bottom): optional label (`fieldLabel` 12 / 600 / lh 1.5 (18 px), `ink`), 8 gap, the box, then helper or error text 8 below.
- **Box:** min height 52, radius 10, border 1 `inputBorder`, fill `white`, side padding 15, vertical padding from A.3 (16.55), text `input` 13 / 400 / lh 1.3 (16.9 px), hint in `muted`, caret `primaryBright`. Leading icon: left padding 15, 12 gap to the text. Suffix is constrained to height 50 so it can never grow the field.
- **Default:** border `inputBorder`. **Focus:** border `primaryBright` + 3 px ring `rgba(0,120,232,.10)` (`focusRing`), animated 190 ms with the `out` curve; no ring when the parent shows the focus (`hasFocusRing: false`). **Filled:** same as default (no change). **Error:** border `error`, no ring, message in `error` style (11 / 400, `error`) 8 below, the space animates open (190 ms). **Helper:** `caption` (11 / 400 / lh 1.6 (17.6 px), `muted`). **Disabled:** no custom styling in the widget (Flutter's default disabled text; border and fill unchanged) *(inferred)*; web: use `disabledInk` text and keep the border.
- **Counter:** not drawn. `maxLength` is enforced and the counter text is blank (`counterText: ''`), so there is no counter in the design.
- **Password:** `obscureText`; the show/hide toggle is the caller's `suffix`. **Multi-line:** `minLines` / `maxLines`, same min height, same vertical padding, top-aligned growth.
- **Search field (Chats, Submissions):** height 44, fill `searchFill`, border transparent (focus still shows the `primaryBright` border and ring), radius 8, leading search icon 18 in `muted`, hint "Search people, teams, messages"; clear button appears as suffix when the query is not empty.
- **Reason:** height from the constraint plus a forced strut line height keeps text centred on every platform; the 1 px border is subtracted so the outer height is exactly 52.
- **Accessibility:** 52 high (above any tap minimum), 4.5:1 text on white, the focus state is a colour change plus ring (not colour alone), error message is text.

### C.2 Buttons (`app_button.dart`)

All share: `button` 14 / 600 / lh 1.3 (18.2 px) (compact `buttonSmall` 12 / 600 / lh 1.3 (15.6 px)), side padding 18 (compact 14), radius 10, icon 18 with 12 gap to the label. Pressing scales to 0.97 with a spring (pointer down; released if the finger moves past the touch slop).

| Variant | Size | Fill / border / label | States |
|---|---|---|---|
| **Filled primary** (`AppButton.primary`) | min height 52, compact 50 | bubble surface on `primary`, no border, white label | pressed: `primaryStrong` 28 % overlay + 0.97 scale; disabled: flat `primaryDisabled`; loading: white spinner (20 dp) replaces the label, button stays the same size and counts as enabled for the look |
| **Outlined / secondary** (`AppButton.secondary`) | same | `white` fill, 1 px `inputBorder`, label `ink` | loading: `primary` spinner; **destructive** (`isDanger`): label, icon and border `error` |
| **Text** (`AppButton.text`) | min 44 x 44 | no fill, label `action` (11 / 500 / lh 1.5 (16.5 px)) in `muted` / `ink` / `primaryStrong` by tone | disabled: `slateLight`; loading: the leading icon spins (900 ms per turn) |
| **Icon** (`AppButton.icon`) | 44 x 44 | glyph 22 in `ink` (`muted` when disabled) | requires a semantic label |
| **Tinted** | (no standalone widget) | used inside the action bar: `tint` fill, `strong` label, see C.9 | |

Primary buttons put the label on the left and the icon on the right when full width (the prototype), sheets centre them (`isCentered`). **Reason:** 52 is the field height so a field and its button align in a form. **Accessibility:** white on `primary` 6.82:1; semantics `button`, `enabled`.

### C.3 FAB (`app_fab.dart`)

Circle 56 x 56 (`fab`), full radius, bubble surface (circle disc set), shadow `fab`, white icon 24 (e.g. `new_chat.png`). **Extended:** same height, side padding 16, 8 gap, label `button` in white, narrow disc set. Pressed overlay as buttons. The chat-list FAB hides on scroll: slides down 24 dp, scales to 0.8 and fades in 200 ms; it reappears on scroll up (threshold 12 dp). Margin 16.

### C.4 Pills, AppPillBar, chips, filters

- **AppPill** (`app_pill_bar.dart`): fully round; **regular** 34 high (tap row 44), side padding 12, label `readableStrong` (12 / 600 / lh 1.6 (19.2 px)); **compact** 28 high, side padding 10, label `pillCompact` (12 / 600 / lh 1.6 (19.2 px)), gap between pills 6 (regular 8); count after the label (4+2 / 4 gap, caption 11 / 700, "99+" above 99).
- **Unselected:** fill = kind `tint`, label = kind `ink`. **Selected:** fill = kind `fill`, label white. Kinds (tint, ink, fill): `neutral` (`fill`, `ink`, `ink`), `accent` (`primaryTint`, `primaryStrong`, `primary`), `violet` (`violetTint`, `violetStrong`, `purple`), `success` (`yesFill`, `yesText`, `yesDot`), `calm` (`noFill`, `noText`, `muted`). Colour animates 190 ms.
- **Single select:** `selected` index; **multi select** (`AppPillBar.multi`): a set of ids; an optional "exclusive" pill (such as All) replaces the others, and an empty set falls back to it. One horizontal scrolling row with bounce.
- **AppFilterChips / AppFilterTabs:** text filters with a 2 px `primaryBright` underline under the selected one, selected label `primaryStrong` 11 / 700, unselected `muted` 11 / 400, gap 24, row height 45, bottom hairline `line`; tabs show a count badge (`primaryTint` fill, radius 4, `primaryStrong` text).
- **Status pill** (Yes / No): 22 high, 7 dp dot + 6 gap + label `readableStrong`; yes = `yesFill` / `yesDot` / `yesText`, no = `noFill` / `noDot` / `noText`. **Tag** (22 high, side padding 8, optional 13 icon): accent / neutral / done tones with the same pairs.
- **Unread badge:** min 19 x 19, round, side padding 5, caption 11 / 700 white on the tile's accent (grey `noDot` when muted); pops in with scale 0.6 to 1 over 190 ms.

### C.5 Cards

- **AppFormCard** (`app_form_card.dart`): width 92 % of the list, radius 14, 1 px `cardLine` border, shadow `card`, white fill; content clipped at 13. Top **strip** 38 high, side padding 12: `primary` for a sent (mine) card, `ink` for received; label `label` 11 / 600 white; optional pencil (38 x 38). Below: title block, then a hairline and the fields in two columns (first 8 fields; "+N more" row expands with an animated height 320 ms). Footer: time `caption` in `cardMuted`, status mark for mine, a clock icon while waiting, a one-line note or error. Pressed: scale 0.985 (190 ms). Flash (just edited): fill `primaryTint` for 1 s. Enter animation: small spring from the right (sent) or left (received), 28 dp.
- **Bottom strip with actions:** the actions sit under the fields in `AppFormCardActionArea`; the expand bar is a hairline + tinted strip (`cardChip`) with a centred chevron and the time at the right (see C.9).
- **Ticket / task cards:** the same widget; tickets add the action bar; "waiting for approval" and similar statuses are `AppTag`s.
- **Document card** (attachment): 240 wide, white, radius 12, 1 px `cardLine`, padding 8; a 44 dp file tile (radius 10) coloured by the file-type palette (01-colors.md section 13), name `readableStrong`, size `caption`.
- **Notice card** (toast): white, radius 14, 1 px `line`, shadow `soft`; 36 dp icon tile (`avatarBg`, radius 12) with a variant icon (info `muted`, success `yesDot`, warning `violet`, error `error`); title `bodyStrong`, message `readable`, optional action text `readableStrong` in `primary`; 44 dp close. Slides 16 dp and fades in 320 ms (out 190 ms); auto-hide after 4 s (info, success), 6 s (warning), 8 s (error), never when persistent; swipe to dismiss; one at a time at the top below the status bar, side margin 24.

### C.6 List tiles (chat tile, `conversation_tile.dart`)

Row: leading avatar 44 (01-colors.md section 14), 16 gap, text column, min height 86, vertical padding 16, 1 px `line` bottom border. Text column: line 1 title `rowTitle` (14 / 600 / lh 1.5 (21 px) / ls -0.3; weight 700 when unread, 600 otherwise), optional pin and mute icons 13 in `muted`, 8 gap, time `caption` (unread and not muted: the tile accent colour, weight 600; else `muted`). Line 2: preview `rowCaption` (11 / 400 / lh 1.4 (15.4 px) / ls 0.1) one line, with a leading 14 glyph for failed (`error`), pending (clock), form, encrypted; unread badge at the right. Line 3: type label `caption` (Direct message, Group, Team, Everyone). Pressed: the whole row fills `primaryTint` (190 ms). Long press opens the row's actions (there is no selection mode and no checkbox in the chat list). The pinned **workspace row** is above the list: avatar circle + chevron `rowChevron`.

### C.7 Bottom navigation (`app_bottom_nav.dart`)

White bar, 1 px `line` top border, side padding 4, top 10, items 52 high, bottom 5 + system inset. Each item: 4 gap, 28 box with a 22 PNG icon, 4 gap, label `label` 11 (height 1.2). **Selected:** icon and label `purple`, label weight 600, a 28 `violetTint` circle with a `navIndicatorGlow` shadow (blur 10) fades in behind the icon (220 ms), icon scales 0.9 to 1 (190 ms); **unselected:** `muted`, weight 400, the unselected PNG glyph. Unread dot: 5 dp `primaryBright` at the icon's top right. Pressed: scale 0.97. Labels: Chats, Agents, Submits, Profile.

### C.8 App bar, sheets, dialogs, popup menu

- **Header** (`AppScaffold` pages): white, height 72 on main pages and 65 for a conversation (back button, avatar, title `bodyStrong`, subtitle `caption`, 1 px `line` bottom border). Status bar transparent with dark icons. Pages are packed to the viewport and only scroll when the keyboard covers content.
- **Bottom sheet** (`AppBottomSheet`): white, top radius 20, barrier `sheetBackdrop` (40 % `scrim`), handle **34 x 4** `sheetHandle`, radius 4; padding 22 sides, 10 top, 30 + inset bottom; handle then 20 gap then header (title `title` 21 / 700 / lh 1.3 (27.3 px) / ls -1, 44 close icon) then 12 gap then content; max height 90 % of the screen (fixed sheet 88 %). Enter: spring, 500 ms; exit: 320 ms with `out`. No elevation shadow is drawn by the widget (the `sheet` shadow token exists for the prototype).
- **Dialogs:** white (theme), same radius family as cards *(inferred: no custom dialog shape in the theme)*.
- **Popup menu** (`AppPopupMenu`): card under the three-dots button, aligned to the right edge (margin 16), max width 280, radius 16, 1 px `line`, shadow `soft`, vertical padding 8; rows min 48 high, side padding 16, 20 icon in `muted`, 12 gap, label `body`; danger rows `error`; disabled `disabledInk`; switch rows toggle in place (thumb white, track `primaryBright`); dividers inset 16. Opens with fade + scale 0.9 to 1 from the top right, 150 ms.

### C.9 Action bar (`app_action_bar.dart`)

Buttons 44 high (`AppActionBar.buttonHeight`), radius 10, 18 icon + 4 gap + label `buttonSmall` one line, side padding 8; gap between buttons 8. **First action = primary soft:** fill `blue.tint` `#DEEDFC`, label and icon `primaryStrong`, border 1 px `primary` at 35 %. **Others:** fill = their tone's `tint`, content = tone `strong` (01-colors.md section 12). Disabled: 50 % opacity. On a card, the first 2 show; the rest fold behind a 40 dp bar (48 dp hit) with a centred chevron and, in a card, the time at the right; opening reveals a two-column grid of tinted buttons (an odd last one spans both) with a 190 ms height animation. `kSolidPrimaryAction` (false) would make the first action a solid bubble-surface button.

### C.10 Switches, sliders, progress

Material 3 components themed in `AppTheme`: switch thumb white, selected track `primaryBright`; slider active track and thumb `primaryBright`; linear progress `primaryBright` on a `primaryTint` track (3 high in `AppProgressBar`, `line` track, round, 190 ms animation); text selection colour `primaryBright` at 25 %. Spinner (`AppSpinner`): iOS-style activity indicator, sizes 16 / 20 / 24 / 32, `primaryBright` unless told otherwise.

### C.11 Avatars and icon tiles

See 01-colors.md section 14 for colour. Sizes 44 / 36 / 72 / 32; letter 0.4 x size, glyph 0.5 x size; person = circle, group and ticket = rounded square radius 10; presence dot 9 with a 2 px white ring at (-1, -1) from the bottom right.

### C.12 Message bubbles (`message_bubble.dart`)

Max width 88 % of the list; padding 14 x 12; radius 15 on all corners, 4 on the sender's lower corner for the last bubble of a run; gap between runs 8, inside a run 2. Text `message` (12 / 400 / lh 1.6 (19.2 px)). **Incoming:** `bubbleIn`, left; shows the sender name (`label`, `senderInks`) above the first bubble of a run in groups and teams. **Outgoing:** `bubbleOut` (= `primaryTint`), right. **Highlight flash** (jumped to from a quote): `primaryTintStrong`, 190 ms. **Meta row** (bottom right): optional lock icon 14 in `yesText` (end-to-end), time `caption` with " • edited", status mark for mine. **Failed:** the line "Not sent. Tap to retry" in `error` (11 / 400) above the meta row, tap retries.
- **Reply quote:** above the body, a 2 px `primaryBright` left bar with name in `label` `primaryStrong` and the quoted text in `caption`. **Forwarded:** a banner row: 14 `shortcut` icon + "Forwarded by name" (12 / 600 `primaryStrong`), optional " • from author" (bold). **Mention:** text in `mention` (me: `mentionMe`, underlined). **Image:** 240 x 180, radius 12, `fill` placeholder, broken-image glyph on error, tap opens the viewer on a `scrim` background. **File:** the document card of C.5 (240 wide). **Voice message:** *not implemented in the app today; nothing to match.* **Reactions:** chips under the bubble. **Typing:** three dots (`noDot`).
- Entry animation for a fresh message: slides up 8 dp while fading in over 320 ms (`_Entrance`).

### C.13 Notification tiles (`feed_tile.dart`)

Row: 44 circle (tone `tint`, 22 icon in the tone `solid`; 75 % opacity once read), 12 gap, text column: optional 8 dp unread dot in the tone colour + 4 gap, title `readableStrong` (max 2 lines; weight 500 when read), message `readable` (max 3 lines), 4 gap, a wrap row of time `caption`, **priority pill** (20 high, tone tint, `label` in strong), a **count badge** (`primaryTint`, `primaryStrong` caption). Optional action as a text button in the tone's strong colour. Three-dot menu at the right (icon 20 in `muted`). **Swipe background:** the tone's `tintStrong`, right aligned, padding 24, "Dismiss" `readableStrong` + close icon in the tone's `strong`.

### C.14 Charts (`app_chart/`)

Series colours in order (01-colors.md section 13), plot height 200, donut height 200, bar rows 28 high (max 12 bars, minimum bar 12, gap 3), grid lines 1 px `grid`, baseline 1.2 px `baseline`, line series stroke 2.2, bar corners 4 on the free end, donut ring stroke 14 (18 when selected), legend swatch with `caption` text, card container radius 14. Grow-in 400 ms. Text in the chart is `caption` 11 (line height 1.2).

### C.15 Loading, empty, error, offline, success; pull to refresh

- **`AppStateView`** wraps every list or screen: `content`, `loading` (skeleton rows or the large loading Lottie 120 dp), `empty`, `error` (with Retry), `offline` (connection-only screens), `noResults`, `locked`. Message block centred, padding 24: picture 160 dp, 20 gap, title `subtitle` (17 / 600 / lh 1.2 (20.4 px) / ls -0.4), 8 gap, message `readable`, 24 gap, then a compact primary button (width 200) or a secondary "Retry" button (width 160). Defaults: empty "Nothing here yet"; error "Could not load / Something went wrong."; offline "You are offline / Check your connection and try again."
- **State pictures** are PNGs shown by `AppStateImage` (512 px source, 160 dp, `locked` at 0.85 scale): intro 500 ms (fade, scale 0.94 to 1), then a gentle float of 4 dp every 3 s; still with reduced motion. Cached-first screens never show the offline picture (they show the dark offline bar: 28 dp, `ink`, white `readable` text).
- **Success:** `state_success_blue.json`, 120 dp, plays once and holds frame 49 (reduced motion: shows that frame).
- **Skeleton:** `avatarBg` blocks (radius 8, or circles) pulsing on the 900 ms cycle.
- **Pull to refresh:** iOS-style bounce on both platforms; header grows with the pull, triggers at 80 dp and stays pinned at 56 dp while loading; `primaryBright` activity indicator (radius 16).

---

## Part D · Do and don't

**Do:** keep the page pure white and separate cards with a hairline or a navy shadow; use `primary` for fills and text, `primaryBright` for icons and focus; use the strong shade for text on a tint; keep the bubble surface on every filled primary button and the FAB; keep the field label, helper and error text sizes; keep the focus ring on every field; use the tone's `strong` for text on `tint`; compute control padding from `(H - 2 - lineHeight) / 2`; respect reduced motion.

**Don't:** use orange or yellow anywhere; use warm greys (all greys here are cool and navy-tinted); put small text on `primaryBright` (4.33:1); make a flat blue primary button; use purple or violet for a button or onboarding; use black shadows; add a dark theme; use a raw text input or a second field style; give pills a radius other than full; hardcode colours, sizes or durations in components (use the tokens).
