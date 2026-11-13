# 04 · Icons and assets

Everything the app loads at runtime for the areas below, found in code (`lib/core/theme/app_icons.dart`, `AppPngIcon`, `AppStateImageKind`, the widgets that name an asset, `pubspec.yaml`). All files are in `assets/` here with their **original file names**. Only the `*_blue` Lottie versions are copied (never the orange originals); the whole folder was scanned for orange or warm colours: **none found** (method in section 6).

## 1. How PNG icons are drawn

`AppPngIcon` draws a PNG as a **tinted glyph**: the file's own colours are replaced by the tint (`BlendMode.srcIn`: the tint colour with the file's alpha), so every PNG icon is a one-colour silhouette and **never shows its own colours**. All PNG icons are 512 x 512 px, 8-bit RGBA. The tint is chosen by the spot where the icon is used (table below). Selected and unselected nav icons are two different glyphs (filled and outline) tinted differently.

**On the web** reproduce it with a CSS mask, so the colour is a plain CSS value:

```css
.icon { width:22px; height:22px; background-color:var(--tint);
  -webkit-mask:url("assets/icons/bottom_nav/chat_selected.png") center / contain no-repeat;
          mask:url("assets/icons/bottom_nav/chat_selected.png") center / contain no-repeat; }
```

(`filter` hacks are not needed. An inline SVG redraw is the alternative if the PNG is ever replaced by a vector.)

## 2. File table

| File (in `assets/`) | Used for | Size in the app | Tint token and hex | Notes |
|---|---|---|---|---|
| `icons/home/work_space.png` | "My Work Space" row at the top of the chat list | 22 dp, centred in a 44 dp circle (fill `primarySoft` `#F0F5FC`, border `primaryTintStrong` `#D6E3F7`) | `primaryBright` `#0078E8` | Local row, never archived, always first |
| `icons/home/new_chat.png` | The new-chat FAB (circle FAB, 56 dp) | 24 dp | `white` `#FFFFFF` | Over the bubble surface |
| `icons/home/group.png` | Group, team and "Everyone" tile: chat tile, conversation header, chat-info page | 0.5 x avatar size (22 dp at 44) in a rounded square (radius 10) | the palette **foreground** of the tile's title, e.g. `#B31952` (01-colors.md section 14); background is the palette background | Care thread without a person name also uses it |
| `icons/home/ticket.png` | Record thread (ticket) tile: same three places | 0.5 x avatar size | palette foreground of the title | |
| `icons/bottom_nav/chat_selected.png` | Chats tab, selected | 22 dp in a 28 dp box on a 28 dp `violetTint` circle | `purple` `#6A3FD4` | Label "Chats", an unread dot (5 dp `primaryBright`) can sit at the top right |
| `icons/bottom_nav/chat_unselected.png` | Chats tab | 22 dp | `muted` `#55658A` | |
| `icons/bottom_nav/ai_selected.png` | Agents tab, selected | 22 dp | `purple` | Label "Agents" |
| `icons/bottom_nav/ai_unselected.png` | Agents tab | 22 dp | `muted` | |
| `icons/bottom_nav/submissions_selected.png` | Submissions tab, selected | 22 dp | `purple` | Label "Submits" |
| `icons/bottom_nav/submissions_unselected.png` | Submissions tab | 22 dp | `muted` | |
| `icons/bottom_nav/profile_selected.png` | Profile tab, selected | 22 dp | `purple` | Label "Profile" |
| `icons/bottom_nav/profile_unselected.png` | Profile tab | 22 dp | `muted` | |
| `states/empty_chats.png` | Empty Chats | 160 dp | **not tinted** (picture in its own cool greys) | `AppStateImageKind.emptyChats` |
| `states/empty_enterprises.png` | Empty organisation list | 160 dp | not tinted | |
| `states/empty_generic.png` | Default empty state | 160 dp | not tinted | |
| `states/no_results.png` | Search with no results | 160 dp | not tinted | |
| `states/offline.png` | Offline state (connection-only screens) | 160 dp | not tinted | |
| `states/error.png` | Error with retry | 160 dp | not tinted | |
| `states/locked.png` | Locked state | 160 x 0.85 dp | not tinted | The file fills its canvas, so it is drawn at 0.85 |
| `lottie/loading_blue.json` | Full-page and big-pane loading (`AppLoading`) | 64 dp (medium), 120 dp (large) | own colours (`#0078E8`, `#6A3FD4`, `#8B5CF6`, `#071F50`) | Loops; reduced motion shows a still frame |
| `lottie/qr_loading_blue.json` | QR sheet loading (`AppQrLoading`) | 140 dp | own colours (blue, violet, `#212D40`) | Loops |
| `lottie/state_success_blue.json` | Success check (`AppSuccessAnimation`) | 120 dp | own colours (`#0078E8`, `#BDD2F2`, `#C9ECFC`) | Plays once and holds frame 49 (before the file's fade-out) |
| Onboarding slides 1 to 3 (no files) | Native painters, `lib/core/widgets/onboarding_art/`, shown by `OnboardingArtStage` | full screen width (capped 600 dp, centred), aspect ratio kept, height from the layout | authored artwork colours (violet and blue, transparent background; not tinted) | Intro once, then a seamless loop; speed 1.25 x the authored timing (`kShieldSpeed`, `kNetworkSpeed`, `kBuildingsSpeed`); reduced motion shows one still frame. Crop windows (viewBox part shown): network symmetric layout (`networkSymContentBounds` in `generated/content_bounds_data.dart`, ratio 1.544), buildings `62.0 88.4 to 1475.4 899.0` (ratio 1.744), shield the whole viewBox (ratio 2.0). Page 1 network, page 2 buildings, page 3 shield. Source: `incoming/onboarding-animations/` (HTML/SVG). The old Lottie files are in `backup/onboarding-lottie-v1/` |
| `lottie/robot.json` | Agents tab hero (`AiAgentsView`) | up to 420 dp square | own colours (periwinkle `#7E8AFF` and greys) | **No `_blue` variant exists**; it is not orange, so it is copied as is. Loops; still frame with reduced motion |
| `logo/connectum_logo_blue.png` | `AppLogo` (auth hero 66, verification 54, header 26, QR footer 16 dp wide) | 1408 x 1464 px, aspect 1408:1464 | not tinted | Source of the app icon too |
| `logo/connectum_logo_blue.svg` | Vector source of the brand mark | 352 x 366 viewBox, 57 paths | not tinted | From `design/brand/connectum_logo_blue.svg` |
| `fonts/PlusJakartaSans-{Regular,Medium,SemiBold,Bold,ExtraBold}.ttf` | The UI font (weights 400, 500, 600, 700, 800) | | | See `fonts/FONTS-NOTE.md` for the licence situation |
| `fonts/SpaceGrotesk-{SemiBold,Bold}.ttf` | Display brand text (600, 700) | | | CLAUDE.md: SIL OFL, source fonts.google.com/specimen/Space+Grotesk |

(`logo-loader/logo_polys.json` and the demo are described in 03-splash-logo-loader.md.)

## 3. Notification category icons (Material, no files)

Notification tiles use **Material Rounded icon names**, chosen by rule (full ordered table with tones and keywords: 01-colors.md section 12). In order: `error_rounded` (rejected, failed, error), `check_circle_rounded` (verified, success, completed, approved), `assignment_rounded` (Submissions), `confirmation_number_rounded` (Tickets), `draw_rounded` (Signatures), `fact_check_rounded` (Approvals), `task_alt_rounded` (Tasks), `alternate_email_rounded` (Mentions), `chat_bubble_rounded` (Messages), `alarm_rounded` (Reminders), `campaign_rounded` (Announcements), `person_add_rounded` (Team), `mic_rounded` (Recordings), `shield_rounded` (Security), `api_rounded` (API), `settings_rounded` (System), `groups_rounded` (group messages), fallback `notifications_rounded`. Size 22 in a 44 circle, colour = the tone's `solid`. On the web use Material Symbols (Rounded, filled) with the same names.

## 4. Action icons (ticket actions, Material outlined, no files)

By keyword in the action name (full table: 01-colors.md section 12): `swap_horiz` (reassign), `restart_alt` (reopen), `trending_up` (escalate), `thumb_up_alt_outlined` (approve), `pause_circle_outline` (hold, pause), `check_circle_outline` (complete, done, close, resolve), `undo` (return, reject, revert), `remove_circle_outline` (drop, cancel, delete, withdraw), `send_outlined` (send, assign, forward), `published_with_changes` (update), fallback `arrow_forward`. Size 18, colour = the tone's `strong`, on the tone's `tint` button.

## 5. Other glyphs

Everything else is Material icons at fixed sizes (13 inline, 18 buttons, 20 menus, 22 app bar and nav, 24 FAB): search, close, chevron_right (`rowChevron`), push_pin and volume_off (13, `muted`), lock (14, `yesText`), schedule (clock), error_outline, description_outlined, shortcut (forward banner), more_horiz and more_vert menus, broken_image_outlined, check.

## 6. Orange scan (done)

Method: every copied JSON, SVG and PNG was decoded and every colour classified by HSV: orange / amber / yellow = hue 10 to 70 deg with saturation over 0.2 and value over 0.15; red = hue under 10 or over 340. Lottie files: every `c` fill/stroke colour and gradient stop (static and keyframed). PNGs: every opaque pixel (sampled every 3rd). **Result for the whole `assets/` folder: 0 warm and 0 red colours.** The original orange Lottie files and the legacy orange PNG logos exist in the app repo and were deliberately not copied.

## 7. Not copied, and not found

- **Present in the app repo but not referenced by any code** (not copied): `icons/home/new_chat_thin.png`, `icons/home/ticket1.png` to `ticket6.png`, `images/states/coming_soon.png` (no `AppStateImageKind` for it).
- **Orange originals (not copied):** `loading.json`, `qr_loading.json`, `state_success.json`, (`onboarding_*.json` were moved to `backup/onboarding-lottie-v1/` when the onboarding became native painters); legacy PNG logos `images/connectum_logo.png`, `images/Connectum-C.png`.
- **Not found:** font licence files (no OFL text is in the repo; see `fonts/FONTS-NOTE.md`); sources and licences of the Lottie files and state pictures (the `credits.md` tables are empty); any asset in `assets/icons/chat/` or `assets/icons/notification/` (both folders are empty; notifications use Material icons); a voice-message icon or asset (voice messages are not in the app).
