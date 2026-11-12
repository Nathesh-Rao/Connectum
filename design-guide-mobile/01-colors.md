# 01 · Colours

Every value here is read from `lib/core/theme/app_colors.dart`, `app_tones.dart`, `app_chart_colors.dart`, `app_shadows.dart` and `lib/core/utils/avatar_palette.dart` and generated into `tokens/tokens.json` and `tokens/tokens.css` (`--color-*`, `--tone-*`, `--chart-*`, `--shadow-*`). If this page and `tokens.json` ever disagree, `tokens.json` wins (regenerate with `tool/design_guide`). Contrast ratios are computed by the app's own `AvatarPalette.contrast` (WCAG).

## 1. The idea in five lines

- One light theme. No dark mode. The page, sheets, dialogs and cards are pure white `#FFFFFF`.
- Brand blue comes in two roles: `primary` #0052CC for anything that carries text or a fill with white on it, and `primaryBright` #0078E8 (the logo blue) for icons, dots, switches, sliders and the focus ring.
- Greys are cool and navy-tinted (`ink` #071F50, `muted` #55658A, `line` #E3EAF4). No warm greys and no orange anywhere.
- Violet / purple is the secondary accent (AI, bottom-nav selection, loading, Medium priority), never a button colour.
- Text on a tint uses the strong shade of the same hue.

## 2. Rules that matter

1. **`primary` for fills, links and text.** White on `primary` is 6.82:1; `primary` on white is 6.82:1.
2. **`primaryBright` for non-text only** (icons, dots, switches, focus ring, spinner). White on it is 4.33:1, under the 4.5:1 text minimum. As icon on white it is 4.33:1 (3:1 is the icon minimum the test enforces; on `primaryTint` it is 3.7:1).
3. **Strong shades for text on tints.** `primaryStrong` on `primarySoft` / `primaryTint` / `primaryTintStrong` is 10.32 / 9.67 / 8.71:1. Every tone's `strong` reads at least 4.5:1 on its own `tint` and `tintStrong` (enforced by `test/core/color_contrast_test.dart`).
4. **`muted` is the secondary text colour** (5.81:1 on white, 5.17:1 on `fill`, 5.26:1 on `bubbleIn`). `tertiary` and `disabledInk` are for non-essential or disabled content only.
5. **Primary buttons are never flat.** `primary` is only the base under the bubble surface (see 02-widgets.md); a disabled one is the flat `primaryDisabled`.
6. **White text on `purple`** 6.41:1, on `error` 5.54:1, on `primaryStrong` 11.3:1.

## 3. How white cards are separated

The scaffold is pure white and so are cards, sheets and popups, so separation comes from one of two things, never from a grey page:

- **Hairline border** (`line` `#E3EAF4`; inside form cards `cardLine` `#E3EAF4`), 1 dp. Used by list rows (bottom border), popup menus, notice cards, the bottom bar (top border), the conversation header.
- **Navy-tinted shadow**: `card` for form and ticket cards (with a `cardLine` border as well), `soft` for popups and notices, `fab` for the FAB, `sheet` for sheets.
- **`surfaceSubtle`** `#F6F9FE` (with a `line` border) is the one cool fill for a panel that must read against white; today only the profile identity card uses it. `primarySoft` / `fill` / `searchFill` are the other quiet fills (rows being pressed, search fields, neutral pills).

## 4. Brand

| Token | Hex | Role | Used in | Do not use for |
|---|---|---|---|---|
| `primary` | `#0052CC` | Filled button base, links, active labels, mention text. | Primary button base (under the bubble discs), text links, selected accent pill fill, unread count default, sent form-card strip, notice action text. | Icons, dots, switches, focus ring (use `primaryBright`). Never as a flat button fill: primary buttons carry the bubble surface. |
| `primaryBright` | `#0078E8` | The logo blue. Icons, dots, switches, sliders, progress, caret, focus border and ring. | Focus border of fields, text cursor, spinner and pull-to-refresh, progress bar, filter-tab underline, nav unread dot, chart series 1, workspace-row icon, blue notification tone solid, switch track. | Text of any size (white on it is only 4.33:1, below 4.5:1). Not for button fills. |
| `primaryLight` | `#00B4F1` | Highlight disc of the bubble surface. | Only the lightest discs of `kBubbles*` in `app_bubble_surface.dart`. | Anything else: not a UI colour. |
| `cyanBlue` | `#00A1E8` | Cool highlight disc of the bubble surface. | Only the cyan discs of `kBubbles*`. | Anything else: not a UI colour. |
| `primaryStrong` | `#00338D` | Dark brand shade for text on tints and for pressed states. | Label colour on `primaryTint` and `primarySoft` (tags, text buttons, filter tabs, forwarded banner, action buttons), `mentionMe`, darkest bubble discs, button pressed overlay (28 %). | Large fills (it reads as navy, not brand blue). |
| `violet` | `#8B5CF6` | Secondary brand: the AI and "attention" colour. | AI surfaces (AI sheet, AI header button), warning notice icon, `ColorScheme.secondary`, bottom-nav glow, Medium priority tone, violet pill kind. | Buttons, onboarding, links, small text (white on it is under 4.5:1: use `purple` for text or fills with white). |
| `purple` | `#6A3FD4` | Deeper violet that carries white text. | Bottom-nav selected icon and label, selected violet pill fill, tone `purple` (Submissions, Tickets, Signatures notification categories). | Buttons, onboarding. |

## 5. Tints of the brand

| Token | Hex | Role | Used in | Do not use for |
|---|---|---|---|---|
| `primarySoft` | `#F0F5FC` | 6 % tint of primary over white. Quiet panel / row highlight. | List rows, invite card, form panels, workspace-row avatar fill. | Text. |
| `primaryTint` | `#E6EEFA` | 10 % tint. Chip / bubble / badge fill. | Outgoing bubble (`bubbleOut`), count badges, selected row flash, progress track, enterprise tile, action-bar soft fill. | Text. |
| `primaryTintStrong` | `#D6E3F7` | 16 % tint. Highlighted bubble, borders of soft panels. | Message highlight flash, workspace-row border, onboarding stage borders. | Text. |
| `primaryBorder` | `#BDD2F2` | About 26 % tint. Border of a "current" tile or notification bell. | `tileCurrentBorder`, notification bell, onboarding stage. | Text; hairlines on neutral cards (use `line`). |
| `tileCurrentBorder` | `#BDD2F2` | Border of the current / selected tile (= primaryBorder). | Enterprise tile of the current organisation, document card. | Hairlines. |
| `primaryDisabled` | `#99BAEB` | 40 % tint. Disabled primary button fill. | Disabled `AppBubbleSurface` (flat, no discs). | Anything but a disabled filled primary. |
| `violetTint` | `#F0EAFE` | 13 % tint of violet. | Nav selected circle, violet pill unselected fill, AI header button. | Text. |
| `violetStrong` | `#5B21B6` | Readable violet on `violetTint`. | Violet pill label, violet tone strong. | Fills. |
| `navIndicatorGlow` | `#8B5CF6 @ 20%` | Violet glow behind the selected nav icon. | Box shadow (blur 10) of the nav selection circle. | Anything else. |

Tints are the solid over white: soft 6 %, tint 10 %, strong 16 %, border about 26 %, disabled 40 % (comment in `app_colors.dart`).

## 6. Neutrals and surfaces

| Token | Hex | Role | Used in | Do not use for |
|---|---|---|---|---|
| `white` | `#FFFFFF` | Page, sheet, card, field and popup background. | Scaffold, sheets, dialogs, cards, fields, bottom bar. | Text on light surfaces (it is the text colour on filled colours only). |
| `surface` | `#FFFFFF` | Alias of white. | Tab bars, forms. | Introducing a second surface colour. |
| `surfaceSubtle` | `#F6F9FE` | Cool panel fill that has to read against white. | Profile identity card. | Page background (the page is pure white). |
| `fill` | `#EDF2FA` | Pressed row / chip / skeleton neutral. | Neutral pill kind, popup row pressed, upload bubble, image placeholder. | Cards (use white + hairline). |
| `searchFill` | `#F1F5FB` | Search field fill. | Chats, submissions, group picker search fields. | Other inputs (they are white with `inputBorder`). |
| `bubbleIn` | `#F0F4FA` | Incoming message bubble. | Incoming bubbles, composer field, reaction chips, workspace welcome. | Cards. |
| `bubbleOut` | `#E6EEFA` | Outgoing message bubble (= `primaryTint`). | Outgoing bubbles. | Anything but bubbles. |
| `ink` | `#071F50` | Primary text, dark strip. | Titles, body, dark received form-card strip, icon buttons. | Large backgrounds. |
| `muted` | `#55658A` | Secondary text, secondary icons. | Captions, timestamps, previews, unselected nav, hint text. | Disabled content (use `disabledInk`). |
| `line` | `#E3EAF4` | Hairline: dividers, card borders, bottom-bar top border. | Row dividers, header bottom border, popup border, notice border. | Input borders (use `inputBorder`). |
| `inputBorder` | `#CBD5E4` | Border of fields and outlined buttons. | AppTextField default border, secondary button border. | Dividers. |
| `slateLight` | `#CBD5E4` | Disabled text button, sheet handle. | Disabled text buttons, scanner chrome. | Text that has to be read. |
| `cardLine` | `#E3EAF4` | Hairline inside form cards. | Form card border and field dividers, action bar divider. | Outside cards. |
| `cardMuted` | `#5F6F94` | Muted text inside cards. | Form card time, notes, footer. | Outside cards. |
| `cardChip` | `#EFF3F9` | Chip fill inside cards. | Action-bar expand strip, composer chip. | Elsewhere. |
| `readOnlyInk` | `#2C3E63` | Read-only field value. | Read-only form field row. | Editable fields. |
| `tertiary` | `#8C99B3` | Non-essential text only. (Unused in the app today.) | Nothing at the moment. | Anything that must be read (about 3:1). |
| `disabledInk` | `#A9B4C8` | Disabled content. | Disabled popup menu rows. | Enabled text. |
| `rowChevron` | `#A3B0C7` | Row chevron. | Settings, picker and list rows. | Text. |
| `avatarBg` | `#EDF2FA` | Neutral avatar and skeleton fill. | Avatar without kind, skeleton blocks, notice icon tile. | Palette avatars (they compute their own). |
| `avatarText` | `#4A5B7A` | Neutral avatar initials. | Avatar without kind. | Anything else. |
| `scrim` | `#0B1B3B` | Full-screen dark scrim (image viewer, scanner). | Attachment viewer, scanner, route transitions. | Sheets (use `sheetBackdrop`). |
| `sheetBackdrop` | `#0B1B3B @ 40%` | Bottom-sheet barrier, 40 % of scrim colour. | Bottom sheets and dialogs. | Elsewhere. |
| `sheetHandle` | `#CBD5E4` | Grab handle of sheets. | 4 x 34 handle. | Elsewhere. |

## 7. Semantic

| Token | Hex | Role | Used in | Do not use for |
|---|---|---|---|---|
| `error` | `#C62A3A` | Errors, destructive actions, failed state. | Error text, danger button label and border, failed message mark, destructive menu row. | Brand accents. White on it is 5.54:1, text on white 5.54:1. |
| `yesFill` | `#E3F6E9` | Green tint for "yes / done". | Status pill, success pill, done tag. | Text. |
| `yesDot` | `#16A34A` | Green dot / success icon. | Presence online dot, success notice icon, copied label. | Small text on white (use `yesText`). |
| `yesText` | `#14532D` | Dark green text on `yesFill`. | Status pill, encrypted lock icon in bubbles. | Fills. |
| `noFill` | `#EDF1F7` | Neutral grey tint for "no / calm". | Status pill, calm pill, neutral tag. | Text. |
| `noDot` | `#8C99B3` | Neutral dot / muted unread badge fill. | Offline dot, muted unread count, typing dots. | Text. |
| `noText` | `#3E4C69` | Dark grey text on `noFill`. | Neutral pill and tag labels. | Fills. |

## 8. Bubbles and mentions

Bubble fills are in the neutrals table (`bubbleIn`, `bubbleOut`, highlight flash `primaryTintStrong`).

| Token | Hex | Role | Used in | Do not use for |
|---|---|---|---|---|
| `mention` | `#0052CC` | A mention in message text (= primary). | Mention text in bubbles. | Anything else. |
| `mentionMe` | `#00338D` | A mention of the signed-in person (= primaryStrong). | Mention text, underlined. | Anything else. |

Both mention colours read at least 4.5:1 on incoming, outgoing and highlighted bubbles (6.18 / 5.84 / 10.24:1 on the first two bubbles).

### Sender name colours (group bubbles)

`senderInks`, picked by a hash of the sender (algorithm in section 14): `#7A2E9E`, `#0F766E`, `#A12B55`, `#2F6B4F`, `#A33B3B`, `#9A3B7B`. All read on `bubbleIn`; no blue hues, because blue is for mentions.

## 9. Decorative (backdrop and splash)

| Token | Hex | Role | Used in | Do not use for |
|---|---|---|---|---|
| `sphereHighlight` | `#C9ECFC` | Highlight of decorative spheres. | Ambient backdrop, card circles. | UI. |
| `sphereMid` | `#5CC6F3` | Mid tone of decorative spheres. | Ambient backdrop, card circles. | UI. |
| `ambientDiscCenter` | `#0078E8 @ 11%` | Brand-blue glow disc, centre (11 %). | Ambient backdrop. | UI. |
| `ambientDiscEdge` | `#0078E8 @ 2%` | Brand-blue glow disc, edge (2 %). | Ambient backdrop. | UI. |
| `ambientOrbitOuter` | `#0078E8 @ 9%` | Outer orbit ring (9 %). | Card circles. | UI. |
| `ambientOrbitInner` | `#0078E8 @ 5%` | Inner orbit ring (5 %). | Ambient backdrop, card circles. | UI. |
| `ambientOrbitViolet` | `#8B5CF6 @ 14%` | Violet orbit ring of splash/access (14 %). | Ambient backdrop. | UI. |

## 10. Shadows (navy-tinted)

All shadow colours are navy (`071F50`, `0B1B3B`, `003A8C`), never black.

| Token | Layers (offset x y, blur, spread, colour) | CSS |
|---|---|---|
| `card` | 0 1, blur 2, spread 0, `#071F50` @ 5.1%<br>0 10, blur 18, spread -14, `#071F50` @ 22% | `0px 1px 2px 0px rgba(7, 31, 80, 0.051), 0px 10px 18px -14px rgba(7, 31, 80, 0.220)` |
| `soft` | 0 8, blur 22, spread 0, `#003A8C` @ 4.3%<br>0 1, blur 2, spread 0, `#003A8C` @ 1.6% | `0px 8px 22px 0px rgba(0, 58, 140, 0.043), 0px 1px 2px 0px rgba(0, 58, 140, 0.016)` |
| `fab` | 0 6, blur 16, spread 0, `#003A8C` @ 20%<br>0 1, blur 3, spread 0, `#003A8C` @ 10.2% | `0px 6px 16px 0px rgba(0, 58, 140, 0.200), 0px 1px 3px 0px rgba(0, 58, 140, 0.102)` |
| `sheet` | 0 -12, blur 40, spread -16, `#0B1B3B` @ 30.2% | `0px -12px 40px -16px rgba(11, 27, 59, 0.302)` |
| `focusRing` | 0 0, blur 0, spread 3, `#0078E8` @ 10.2% | `0px 0px 0px 3px rgba(0, 120, 232, 0.102)` |

Flutter `blurRadius` maps to CSS blur radius one to one; `spreadRadius` is CSS spread.

## 11. Where purple and violet are used, and where not

**Used:** bottom-nav selected icon and label (`purple`) on a `violetTint` circle with a violet glow; the violet pill kind (selected = `purple` fill); AI surfaces (AI sheet, AI header button: `violet`/`violetTint`); the warning notice icon (`violet`); Medium priority pill (tone `violet`); the Submissions / Tickets / Signatures notification categories (tone `purple`); the violet orbit ring of the splash and access backdrop; loading animations (the `*_blue` Lottie files keep their violet accents; the logo loader mixes blue and violet, see 03).

**Not used:** buttons (primary buttons are blue with the bubble surface), links, onboarding copy and CTAs, text on white other than the selected nav label, success or error (green / red).

## 12. Notification category tones, icons and priority pills

Tone shades (`AppTone`): the tint is the solid at 13 % over white, `tintStrong` at 20 %; `strong` is the readable text/icon shade.

| Tone | solid | strong | tint (13 %) | tintStrong (20 %) |
|---|---|---|---|---|
| `red` | `#C62828` | `#8E1B1B` | `#F8E3E3` | `#F4D4D4` |
| `green` | `#15803D` | `#115E2D` | `#E1EEE6` | `#D0E6D8` |
| `blue` | `#0078E8` | `#00338D` | `#DEEDFC` | `#CCE4FA` |
| `violet` | `#8B5CF6` | `#5B21B6` | `#F0EAFE` | `#E8DEFD` |
| `purple` | `#6A3FD4` | `#4A2897` | `#ECE6F9` | `#E1D9F6` |
| `teal` | `#0F766E` | `#0B5651` | `#E0EDEC` | `#CFE4E2` |
| `indigo` | `#00338D` | `#001F5C` | `#DEE4F0` | `#CCD6E8` |
| `primary` | `#0078E8` | `#00338D` | `#DEEDFC` | `#CCE4FA` |
| `slate` | `#475569` | `#334155` | `#E7E9EC` | `#DADDE1` |

Notification rules (`lib/features/notifications/notification_style.dart`). The first rule that matches wins. Lookup order: group-message special case; then the item's `actionType`, `icon`, `category` against the `types`; then keywords against `title + " " + message` (lower case, start of a word; the message of an end-to-end item is not read); else the slate bell.

| # | Material icon | Tone | Category pill | `types` (actionType, icon, category) | Keywords (start of a word, title + message) |
|---|---|---|---|---|---|
| 0 | `groups_rounded` | `indigo` (`#00338D`) | Messages | group-message items | (special case, checked first) |
| 1 | `error_rounded` | `red` (`#C62828`) | General | — | `rejected`, `failed`, `error` |
| 2 | `check_circle_rounded` | `green` (`#15803D`) | General | — | `verified`, `success`, `completed`, `approved` |
| 3 | `assignment_rounded` | `purple` (`#6A3FD4`) | Submissions | `submissions`, `submission` | `submission`, `submitted` |
| 4 | `confirmation_number_rounded` | `purple` (`#6A3FD4`) | Tickets | `tickets`, `ticket`, `status`, `confirmation_number` | `ticket` |
| 5 | `draw_rounded` | `purple` (`#6A3FD4`) | Signatures | — | `signed`, `sign`, `signature` |
| 6 | `fact_check_rounded` | `blue` (`#0078E8`) | Approvals | `approvals`, `approval`, `request`, `fact_check` | `approval`, `approve`, `request` |
| 7 | `task_alt_rounded` | `teal` (`#0F766E`) | Tasks | `tasks`, `task`, `task_alt` | `task`, `to-do`, `todo` |
| 8 | `alternate_email_rounded` | `blue` (`#0078E8`) | Mentions | `mention`, `alternate_email` | `mention` |
| 9 | `chat_bubble_rounded` | `indigo` (`#00338D`) | Messages | `open_chat`, `open_message`, `messages`, `message`, `chat`, `group` | `message`, `chat` |
| 10 | `alarm_rounded` | `red` (`#C62828`) | Reminders | `reminders`, `reminder`, `alarm` | `reminder`, `due`, `deadline`, `closing`, `expire` |
| 11 | `campaign_rounded` | `indigo` (`#00338D`) | Announcements | `broadcast`, `campaign` | `broadcast`, `announcement` |
| 12 | `person_add_rounded` | `blue` (`#0078E8`) | Team | — | `added`, `joined`, `invite` |
| 13 | `mic_rounded` | `teal` (`#0F766E`) | Recordings | — | `recording`, `upload` |
| 14 | `shield_rounded` | `red` (`#C62828`) | Security | `security`, `lock` | `login`, `security` |
| 15 | `api_rounded` | `slate` (`#475569`) | API | `api` | — |
| 16 | `settings_rounded` | `slate` (`#475569`) | System | `system` | — |
| fallback | `notifications_rounded` | `slate` (`#475569`) | General | — | — |

Tile anatomy: 44 dp circle filled with the tone's `tint` (75 % opacity once read), 22 dp icon in the tone's `solid`; unread dot (8 dp) in `solid`; swipe background = `tintStrong` with "Dismiss" and a close icon in `strong`; the action label uses `strong`.

Priority pill (`feed_priority_pill.dart`): 20 dp high, 8 dp horizontal padding, fully round, fill = tone `tint`, label = `label` style (11 / 600) in tone `strong`. Low (the default) shows nothing.

| Priority value | Label | Tone | Pill fill (tint) | Label colour (strong) |
|---|---|---|---|---|
| `high` | High | red | `#F8E3E3` | `#8E1B1B` |
| `medium` | Medium | violet | `#F0EAFE` | `#5B21B6` |
| `resolved` | Resolved | green | `#E1EEE6` | `#115E2D` |
| `low` | (no pill: the default shows nothing) | — | — | — |

### Ticket action tones (`ticket_action_style.dart`)

The first rule with a keyword contained in the action's lower-cased name wins, so a specific word (reassign) sits above the general one it contains (assign). Icon and label use the tone's `strong`, the button fill uses its `tint`.

| # | Keywords (contained in the lower-cased action name) | Material icon | Tone |
|---|---|---|---|
| 1 | `reassign` | `swap_horiz` | `slate` (`#475569`) |
| 2 | `reopen` | `restart_alt` | `blue` (`#0078E8`) |
| 3 | `escalate` | `trending_up` | `violet` (`#8B5CF6`) |
| 4 | `approve` | `thumb_up_alt_outlined` | `green` (`#15803D`) |
| 5 | `hold`, `pause` | `pause_circle_outline` | `slate` (`#475569`) |
| 6 | `complete`, `done`, `close`, `resolve` | `check_circle_outline` | `green` (`#15803D`) |
| 7 | `return`, `reject`, `revert` | `undo` | `violet` (`#8B5CF6`) |
| 8 | `drop`, `cancel`, `delete`, `withdraw` | `remove_circle_outline` | `red` (`#C62828`) |
| 9 | `send`, `assign`, `forward` | `send_outlined` | `blue` (`#0078E8`) |
| 10 | `update` | `published_with_changes` | `slate` (`#475569`) |
| fallback | any other | `arrow_forward` | `slate` (`#475569`) |

## 13. Chart series, document and tile palettes

Series order (the brand blue leads; each reads at least 3:1 on white and on `surfaceSubtle`):

| Order | Name | Hex |
|---|---|---|
| 1 | blue | `#0078E8` |
| 2 | violet | `#8465F0` |
| 3 | cyan | `#0892C8` |
| 4 | indigo | `#00338D` |
| 5 | teal | `#0E8A80` |
| 6 | rose | `#D6336C` |
| 7 | slate | `#64748B` |
| grid | grid lines | `#E3EAF4` |
| baseline | axis baseline | `#B9C4D8` |

File-type tiles on document cards (background / border / label):

| Palette | Background | Border | Label |
|---|---|---|---|
| `docPdf` | `#FBE6E2` | `#F2C9C1` | `#A32A1A` |
| `docWord` | `#E4EDF9` | `#C4D6EF` | `#1F4E96` |
| `docExcel` | `#E3F3E8` | `#C1E0CB` | `#1B6B3A` |
| `docSlides` | `#F0EAFE` | `#DCD0FA` | `#5B21B6` |
| `docText` | `#EDF1F7` | `#D9E0EC` | `#3E4C69` |
| `docArchive` | `#E2F3F1` | `#BFE2DE` | `#0B5651` |
| `docOther` | `#E9ECEF` | `#D3D8DD` | `#3F4A54` |

Enterprise tile palettes (picked by index modulo 4):

| # | Background | Border | Foreground |
|---|---|---|---|
| 0 | `#EFF4FB` | `#DCE7F6` | `#4F6A94` |
| 1 | `#F1EFFC` | `#E1DCF7` | `#6B58B0` |
| 2 | `#ECF6FB` | `#D6EAF5` | `#3F7A96` |
| 3 | `#F0F2F8` | `#DFE3EE` | `#5B6784` |

## 14. Avatar and chat-tile leading colour (must be reproduced exactly)

> **Finding (portability).** The hash is plain integer arithmetic over code points and is portable. It does **not** use `String.hashCode`. It does, however, call Dart's `toLowerCase()` / `toUpperCase()`, and Dart maps **one code point at a time** (simple mappings): no final sigma, no `ß` to `SS`, `İ` to a single `i`. JavaScript's `toLowerCase()` uses the full Unicode mappings, so a naive port picks a different palette index for names containing `İ`, a final `Σ`, and similar. My first, naive TS port failed 12 of 433 checks for exactly that reason. The portable equivalent is in `tokens/avatar-color.ts`: it does not call JS case functions, it reads `tokens/dart-case-map.json` (Dart's own table, generated by running Dart over every code point). With it, all 130+ vectors pass. **Decision for you:** keep the table (exact, 100 % match, recommended) or accept the naive JS port (identical for ASCII, Latin, Cyrillic, CJK, Arabic, Indic; wrong only for the handful of special-casing characters). The app is unchanged.

### 14.1 Which tile uses which leading widget

The chat tile, the conversation header and the chat-info page all call `conversationAvatarFor(conversation)` (`lib/core/widgets/conversation_avatar.dart`), so they cannot drift.

| Tile type | How it is recognised | Leading widget | Seed string (the key) |
|---|---|---|---|
| Direct | `kind == dm` (convId `dm:<username>`) | Circle, first letter | `Conversation.title` = **the peer's username, lower-cased** (not the display name) |
| Team (host) | `kind == host` (`host:<name>`) | Rounded square + `group.png` | `title` (the host name) |
| Group | `kind == group`, name not `rec-*` / `care-*` | Rounded square + `group.png` | `title`: the server's thread title when there is one, else the tidied group name (`rec`/`care` rules below) |
| Thread (record) | group name matches `^rec-(.+)-(\d+)$` (case-insensitive) | Rounded square + `ticket.png` | `title`: the record's title from the server (it can be renamed, which changes the colour), else "Ticket #12" made from the name |
| Ticket thread | a record thread of the `ticket` structure (`rec-ticket-12`) | same as Thread | same |
| Care thread | group name matches `^care-[A-Za-z0-9._-]+$` **and** the title is not empty and not equal to the group name | Circle, first letter (a person) | `title` = the person's name from `org.name` |
| Care thread without a name | same pattern, title empty or equal to the group name | Rounded square + `group.png` | `title` (empty gives the neutral colours) |
| Global room | convId `global` | Rounded square + `group.png` | `"Global"` |
| System / bot | **no dedicated avatar exists in the code** (the AI tab uses the robot Lottie and a violet header button; there is no bot conversation tile) | — | — |
| "Me" (profile card) | `AppAvatar(isAccent: true)` | Circle, solid `primary` `#0052CC`, white initials in the `title` style (21 / 700), **not** from the palette | the display name; initials rule 14.6 |
| Workspace row (chat list) | local row | 44 dp circle, fill `primarySoft`, border `primaryTintStrong`, `work_space.png` 22 dp in `primaryBright` | none (fixed) |
| Avatar without a kind (people in sheets, pickers, members of tasks, workspace screen "MW") | `AppAvatar(name:)` | Circle (square with radius 10 when `isSquare`), fill `avatarBg` `#EDF2FA`, initials in `avatarText` `#4A5B7A` (12 / 600) | none; initials rule 14.6 |

The seed is always the **string the app shows as the title**, trimmed and lower-cased only inside the hash. The web must feed the same title string, otherwise the colour differs.

### 14.2 The algorithm, step by step

`AvatarPalette.indexOf(name)`:

1. `key = name.trim().toLowerCase()` (Dart: trims Unicode White_Space + U+FEFF, case-maps one code point at a time).
2. `runes = key as a list of Unicode code points` (not UTF-16 units: an emoji is one rune).
3. If `runes` is empty: index is **-1** (neutral colours).
4. `index = (runes.first * 31 + runes.last * 17 + runes.length * 13) mod 12`.

Worked example, `Priya Sharma`: key `priya sharma`, first `p` = 112, last `a` = 97, length 12: 112·31 + 97·17 + 12·13 = 3472 + 1649 + 156 = 5277; 5277 mod 12 = 9 → `rose`. (Vector: index 9, foreground `#B31952`, background `#FBE4ED`.)

Values never exceed about 34 million, so 32-bit or double arithmetic gives the same result as Dart's 64-bit ints.

### 14.3 The palette (12 entries, same order as the index)

| Index | Name | Hue° | Fg S / L | Foreground | Background | Fg on bg | White on fg |
|---|---|---|---|---|---|---|---|
| 0 | teal | 178 | 0.45 / 0.32 | `#2D7674` | `#E4FBFA` | 4.92:1 | 5.31:1 |
| 1 | cyan | 195 | 0.85 / 0.3 | `#0B6D8E` | `#E4F5FB` | 5.22:1 | 5.85:1 |
| 2 | sky blue | 207 | 0.85 / 0.32 | `#0C5997` | `#E4F1FB` | 6.32:1 | 7.26:1 |
| 3 | blue | 218 | 0.85 / 0.36 | `#0E47AA` | `#E4EDFB` | 7.12:1 | 8.4:1 |
| 4 | cobalt | 228 | 0.75 / 0.38 | `#1835AA` | `#E4E9FB` | 8.15:1 | 9.87:1 |
| 5 | indigo | 244 | 0.6 / 0.4 | `#3129A3` | `#E6E4FB` | 8.53:1 | 10.62:1 |
| 6 | violet | 262 | 0.6 / 0.4 | `#5629A3` | `#EDE4FB` | 7.62:1 | 9.37:1 |
| 7 | purple | 276 | 0.6 / 0.4 | `#7229A3` | `#F2E4FB` | 6.74:1 | 8.2:1 |
| 8 | plum | 296 | 0.55 / 0.4 | `#972E9E` | `#FAE4FB` | 5.49:1 | 6.56:1 |
| 9 | rose | 338 | 0.75 / 0.4 | `#B31952` | `#FBE4ED` | 5.48:1 | 6.61:1 |
| 10 | slate | 215 | 0.25 / 0.38 | `#495D79` | `#E4EEFB` | 5.73:1 | 6.72:1 |
| 11 | ocean | 200 | 0.9 / 0.3 | `#086391` | `#E4F4FB` | 5.82:1 | 6.55:1 |

- **Foreground** = HSL(hue, S, L) with the S and L of the row; **background** = HSL(hue, S = 0.75, L = 0.94) for every row. HSL to RGB follows Flutter's `HSLColor.toColor()` (chroma = (1 − |2L − 1|)·S; each channel rounded half-up to 0..255); `hslToHex` in `avatar-color.ts` is that function.
- **Neutral (index -1, empty name):** foreground `#4A5B7A`, background `#EDF2FA`.
- **Contrast rule** (tests in `test/core/avatar_palette_test.dart` and `color_contrast_test.dart`): every foreground reads at least 4.5:1 on its own background **and** white reads at least 4.5:1 on every foreground; foreground lightness stays within 0.30 to 0.40. No red hue (red is the error colour) and nothing between about 10° and 55° (the warm range). Changing a row means re-checking both ratios.
- With 12 buckets, collisions are normal: `Anna`, `Aida`, `Alia` (same first letter, last letter and length) all give index 4.

### 14.4 What each widget draws from the colours

- **Person (circle):** background = palette background; the letter (rule 14.5) in the palette foreground, `readableStrong` (12 / 600, line height 1), font size = 0.4 × avatar size, centred. 44 dp by default.
- **Group / ticket (rounded square):** background = palette background, corner radius 10 dp (`AppRadius.control`), icon `group.png` or `ticket.png` tinted with the palette foreground at 0.5 × the avatar size (22 dp at 44).
- **Chat-tile accents:** the unread count badge fill and the time label of an unread, un-muted row use the **foreground** colour of the same seed; for index -1 they use `primaryBright`. A muted row's badge is `noDot` grey.
- **Presence dot** (direct chats only): 9 dp circle, `yesDot` online / `noDot` offline, white 2 dp ring, offset -1, -1 from the bottom right.
- **Sender name in a group bubble:** not the palette. `senderInks[h mod 6]` with `h = 0; for each UTF-16 unit u of sender.toLowerCase(): h = (h·31 + u) & 0x7fffffff`. The sender string is **not trimmed** (so `"  PRIYA SHARMA  "` and `"Priya Sharma"` get different inks), and it hashes UTF-16 code units, not code points.

### 14.5 Letter of a person tile

`trim()` (no lower-casing); take the code points; the first code point that matches `^[\p{L}\p{N}]` (a letter or digit), else the first code point; upper-case it (Dart simple mapping); empty gives `?`. So `#general` gives `G`, `😀 party` gives `P`, `李雷` gives `李`, `ǅungla` gives `Ǆ`.

### 14.6 Initials (avatars without a kind, and the "me" accent avatar)

`trim()`, split on `\s+`, keep the words that start with a letter or digit (word start tested on its first code point), take the first two, take the **first UTF-16 unit** of each, upper-case, join. No word left gives `?`. So `Ana Lopez` gives `AL`, `#general` gives `?`, `😀` gives `?`, `Иван Петров` gives `ИП`.

> **App bug found (not changed):** for a word starting with an astral letter (for example `𠀀`, CJK extension B) the first UTF-16 unit is a lone surrogate and Flutter throws "string is not well-formed UTF-16" while drawing the avatar. The vector for `𠀀𠀁` records `plainInitialsRenderError: true`. The TS keeps the same quirk so the vectors match; the web should decide whether to use the first code point instead.

### 14.7 `conversationAvatarFor` / `ConversationAvatarSpec` outputs (from the real code)

| convId | kind | title (seed) | avatar | seed index | fg | bg | note |
|---|---|---|---|---|---|---|---|
| `dm:priya.sharma` | dm | `priya.sharma` | person | 9 | `#B31952` | `#FBE4ED` | direct: title is the peer username, lower case |
| `dm:arjun` | dm | `arjun` | person | 10 | `#495D79` | `#E4EEFB` | direct |
| `dm:zoë` | dm | `zoë` | person | 4 | `#1835AA` | `#E4E9FB` | direct, non-ASCII username |
| `group:Sales Team` | group | `Sales Team` | group | 4 | `#1835AA` | `#E4E9FB` | group |
| `group:Engineering` | group | `Engineering` | group | 9 | `#B31952` | `#FBE4ED` | group |
| `group:rec-ticket-12` | group | `Ticket #12` | ticket | 4 | `#1835AA` | `#E4E9FB` | ticket thread, made title |
| `group:rec-ticket-12` | group | `Printer on fire` | ticket | 8 | `#972E9E` | `#FAE4FB` | ticket thread, renamed by the server |
| `group:rec-leave-request-7` | group | `Leave Request #7` | ticket | 3 | `#0E47AA` | `#E4EDFB` | record thread of another structure |
| `group:care-ana.lopez` | group | `Ana Lopez` | person | 2 | `#0C5997` | `#E4F1FB` | care thread with the person name |
| `group:care-ana.lopez` | group | `care-ana.lopez` | group | 9 | `#B31952` | `#FBE4ED` | care thread, title equals the group name: group tile |
| `group:care-ana.lopez` | group | `` | group | -1 | `#4A5B7A` | `#EDF2FA` | care thread, empty title: group tile, neutral colours |
| `host:Support` | host | `Support` | group | 0 | `#2D7674` | `#E4FBFA` | team (host) |
| `global` | global | `Global` | group | 7 | `#7229A3` | `#F2E4FB` | everyone room |

### 14.8 Files

- `tokens/avatar-color.ts`: the reference implementation (`paletteIndex`, `avatarColors`, `personLetter`, `plainInitials`, `senderInk`, `conversationAvatar`).
- `tokens/dart-case-map.json`: Dart's case-mapping table the TS reads.
- `tokens/avatar-color-vectors.json`: 60 names, 13 conversations and 57 senders with expected outputs, produced by running the real Dart widgets (`AppAvatar`, `conversationAvatarFor`, `MessageBubble`).
- `tokens/avatar-color.test.ts`: `node --experimental-strip-types tokens/avatar-color.test.ts` (Node 22.6+).
- App side: `test/core/avatar_color_vectors_test.dart` regenerates the vectors in memory and fails when they differ from the file; regenerate with `flutter test tool/design_guide/generate.dart`.

## 15. Contrast numbers

Computed from the real colours (`AvatarPalette.contrast`):

| Pair | Foreground | Background | Ratio |
|---|---|---|---|
| ink on white | `#071F50` | `#FFFFFF` | 15.9:1 |
| muted on white | `#55658A` | `#FFFFFF` | 5.81:1 |
| muted on surfaceSubtle | `#55658A` | `#F6F9FE` | 5.51:1 |
| muted on fill | `#55658A` | `#EDF2FA` | 5.17:1 |
| muted on bubbleIn | `#55658A` | `#F0F4FA` | 5.26:1 |
| cardMuted on white | `#5F6F94` | `#FFFFFF` | 5.01:1 |
| primary on white | `#0052CC` | `#FFFFFF` | 6.82:1 |
| primary on surfaceSubtle | `#0052CC` | `#F6F9FE` | 6.46:1 |
| error on white | `#C62A3A` | `#FFFFFF` | 5.54:1 |
| white on primary | `#FFFFFF` | `#0052CC` | 6.82:1 |
| white on primaryBright | `#FFFFFF` | `#0078E8` | 4.33:1 |
| white on purple | `#FFFFFF` | `#6A3FD4` | 6.41:1 |
| white on error | `#FFFFFF` | `#C62A3A` | 5.54:1 |
| white on primaryStrong | `#FFFFFF` | `#00338D` | 11.3:1 |
| primaryStrong on primarySoft | `#00338D` | `#F0F5FC` | 10.32:1 |
| primaryStrong on primaryTint | `#00338D` | `#E6EEFA` | 9.67:1 |
| primaryStrong on primaryTintStrong | `#00338D` | `#D6E3F7` | 8.71:1 |
| primary on primaryTintStrong | `#0052CC` | `#D6E3F7` | 5.26:1 |
| violetStrong on violetTint | `#5B21B6` | `#F0EAFE` | 7.66:1 |
| purple on white | `#6A3FD4` | `#FFFFFF` | 6.41:1 |
| purple on violetTint | `#6A3FD4` | `#F0EAFE` | 5.47:1 |
| yesText on yesFill | `#14532D` | `#E3F6E9` | 8.08:1 |
| noText on noFill | `#3E4C69` | `#EDF1F7` | 7.58:1 |
| primaryBright on white (icons) | `#0078E8` | `#FFFFFF` | 4.33:1 |
| primaryBright on surfaceSubtle (icons) | `#0078E8` | `#F6F9FE` | 4.1:1 |
| primaryBright on primaryTint (icons) | `#0078E8` | `#E6EEFA` | 3.7:1 |
| mention on bubbleIn | `#0052CC` | `#F0F4FA` | 6.18:1 |
| mention on bubbleOut | `#0052CC` | `#E6EEFA` | 5.84:1 |
| mentionMe on bubbleIn | `#00338D` | `#F0F4FA` | 10.24:1 |
| avatarText on avatarBg | `#4A5B7A` | `#EDF2FA` | 6.09:1 |
| white on bubble surface, lightest wide stack | `#FFFFFF` | `#005ACF` | 6.25:1 |
