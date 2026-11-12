# 03 · Splash and the logo loader

Source: `lib/core/widgets/logo_loader/logo_loader.dart`, `logo_data.dart` (generated), `lib/features/splash/splash_controller.dart`, `splash_view.dart`. Values are in `logo-loader/logo_polys.json` (`config`, `timeline`, `geo`) and `tokens/tokens.json` (`splash`, `logoLoaderConfig`).

## 1. What it is

The animated Connectum logo: a **static "C"** (the brand mark, 57 filled shapes) that **morphs into a closed ring** (the "O" with 8 radial gaps), **spins** while something loads, then **unwinds back into the exact "C"** and lands in its original orientation. The C is drawn from the original vector paths; during the morph every shape is redrawn as a polygon whose points move from their C position to their ring position. The loader is used on the **splash screen** only; the static C (with `AppLogo`, the PNG) is the brand mark elsewhere.

## 2. Timeline of the splash (`SplashController`)

| t | What happens | Value |
|---|---|---|
| 0 | Splash opens: the static C on the white page with the ambient backdrop (`AppAmbientVariant.splash`: blue glow disc, orbits). The route is resolved in parallel (session ready, onboarding flag, first-start deep link; each step has a timeout of 4 s, 2 s, 6 s). | |
| 400 ms | `loader.start()`: C to ring morph begins | `startDelay` = 400 ms |
| 400 ms to about 1.3 s | The morph runs at full speed: `p` goes 0 to 1 in `startMorph` = 0.9 s (velocity ramps up over `morphRamp` = 0.28 s); rotation starts at 45 deg/s and accelerates towards the loading speed | |
| then | Loading: the ring spins at an organic speed around 400 deg/s (0.5x to 1.9x, slow waves plus occasional gentle bursts), never jumping | `baseSpeed` = 400 |
| when the route is known **and** the animation has started | Wait `extraRun` more, so a fast load still shows the animation | `extraRun` = 2000 ms |
| stop | `loader.stop()`: the ring unwinds to the C. The duration is **chosen so the rotation ends exactly on a multiple of 360 deg without reversing**: between `stopMin` 0.9 s and `stopMax` 2.2 s | |
| C restored | `stopAndWait` completes; wait `endDelay` | 300 ms |
| end | Navigate (`Get.offNamed`) to chats, enterprises, authentication or onboarding | |

Total on a fast device: 400 + 2000 + stop (0.9 to 2.2 s) + 300, about 3.6 to 4.9 s; if the work takes longer than the start delay the extra run starts after the work. If the app is in the background when the splash ends, navigation waits until it resumes. The logo box on the splash is **148 x 148 dp** (`splashLogoSize`).

**Reduced motion** (system "remove animations"): no loader at all. The static C is shown for `reducedMotionDelay` = **300 ms** while the route resolves, then navigation.

## 3. Easing and motion curves (measured)

- Morph progress `p` (0 = C, 1 = ring): angle warp uses `easeInOutCubic(p / 0.82)`; radius uses `easeInOutCubic((p - 0.18) / 0.82)` (so the angle closes first, then the body grows to the ring); an extra inner **swirl** of `sin(pi * easeInOutSine(p)) * 0.42` rad twists the inside while morphing.
- Ring boundary: a mask whose outer and inner radius slide to the final radii (outer 380, inner 174.8 in the 1024 box) with a smoothstep `w = e^2 (3 - 2e)`; the 8 gaps (`segments`), each 13 units wide (`gap`), open smoothly over the second half of the radius progress. The seam where the two ends of the C meet is one of the gaps; the ends overlap by 0.075 rad (`overlap`) while closing.
- Rotation: angular velocity glides towards its target with time constant `tau` = 0.4 s and an acceleration cap of 1100 deg/s^2. Target speed = lerp(45 deg/s, `baseSpeed` x rhythm, smoothstep(p)).
- Stop: a cubic Hermite blend of `p` to 0 and of the angle to the next multiple of 360 deg, with the start velocities matched, so nothing jumps when `stop()` is called in the middle of anything (even during the morph).

## 4. How the 57 polygons morph (`logo_data.dart`, `logo_polys.json`)

The logo has **57 shapes** (`geo.count`) in a **1024 x 1024** frame (centre 512, 512). For each shape the generated data holds, per outline point `k`:

- `r[k]`: distance from the logo centre in the C state,
- `a[k]`: angle relative to the **opening of the C** (radians; the opening direction is `phiC` = 0.02911 rad and its half-width `g0` = 0.32495 rad),
- `rf[k]`: radius of the point in the finished ring.

Each frame, for every point: `rr = r + (rf - r) * eR`; `ang = phiC + angWarp(a, eA) + swirl * (1 - rr / rOut)`; `x = 512 + rr cos(ang)`, `y = 512 + rr sin(ang)`. `angWarp` stretches the body towards the opening so both ends meet: with `m = |a|` and `mEnd = g0 (1 - e) - overlap * e`, points with `m >= g0` move by `(mEnd - g0) * (1 - u)^tailBias` (`u = (m - g0) / (pi - g0)`, `tailBias` = 1.5) and points inside the opening scale by `mEnd / g0`; the sign of `a` is kept. The polygons are then clipped by the ring mask, rotated by `theta` about the centre, and filled with the shape's own colour. At `p = 0` the original paths (`originalPaths`, SVG path data) are drawn exactly; at `p >= 1` the polygons are cached and only the rotation changes. The exact algorithm is the JS in `logo-loader-demo.html`.

Note: the SVG file in `assets/logo/` uses a 352 x 366 viewBox; the loader data uses its own 1024 frame (the same artwork, centred).

## 5. Colours per polygon

Eight values (counts of shapes): `#0078E8` (13, brand bright blue), `#00B4F1` (13, light cyan-blue), `#0052CC` (9, primary), `#6A3FD4` (8, purple), `#00338D` (6, strong navy blue), `#8B5CF6` (5, violet), `#071F50` (2, ink navy), `#6421E8` (1, a violet that is **not** in `AppColors`; it comes from the original artwork). Each shape keeps the same colour in every state. The background is white; there is no stroke.

## 6. The static C and where else the logo appears

`AppLogo` draws `connectum_logo_blue.png` (1408 x 1464, aspect 1408:1464) at a width: **66** (authentication hero), **54** (verification), **26** (onboarding header; 29 on the enterprises header), **16** (QR share card footer). The conversation controller also uses the PNG as an image. The vector source is `assets/logo/connectum_logo_blue.svg` (57 paths, `#0078E8` and the other blues/violets). The legacy orange logo files in the app repo (`connectum_logo.png`, `Connectum-C.png`) are **not** part of this guide.

## 7. Reference demo and how to use it

- `logo-loader/logo_polys.json`: generated data (`geo`, `config`, `timeline`, `colors`, `originalPaths` as SVG path strings, `polys`).
- `logo-loader/logo-loader-demo.html`: one self-contained file (vanilla JS and SVG, no libraries; the JSON is embedded, so it opens from disk). Buttons: **Play splash sequence** (the exact timeline of section 2, with a "simulated work" field), **Start / Stop loader**, a reduced-motion checkbox (also initialised from `prefers-reduced-motion`), a size field. Query parameters used for checking: `?still=<p>,<theta>` draws one frame, `?bare` hides the page chrome, `?autostart` starts the loader. Regenerate with `flutter test tool/design_guide/generate.dart`.
- **Where it fits:** a splash or first-paint screen, a full-page loading state, a long wait (more than a second or two). The **web team decides where**; it is a brand moment, not a button spinner.
- **Small-loader alternatives:** `assets/lottie/loading_blue.json` (full pages and big panes: 64 dp medium, 120 dp large, loops, still frame with reduced motion) and `assets/lottie/qr_loading_blue.json` (QR loading, 140 dp). Inline loading on buttons and rows is the 16 to 32 dp activity indicator, not these.

### Verification status (honest)

- **Run and checked:** the demo was rendered in headless Chrome at three states (`p` = 0, 0.5, and 1 with a 40 deg rotation) and compared pixel by pixel with the real Flutter `LogoLoader` painter rendered from the app's own widget at the same state: mean difference 0.03 to 0.61 of 255 per pixel, at most 0.25 % of pixels differing by more than 64 (edge anti-aliasing). The controller (start, loading, stop, land on the C) was run in Node 200 times with random seeds: every run stopped in 0.92 to 2.22 s and ended exactly on `p = 0`, `theta = 0`.
- **Not verified:** the live `requestAnimationFrame` loop and the splash buttons in a real browser session (headless capture of a running animation timed out), and the "reduced motion" checkbox path. The timeline code is a direct transcription of `SplashController.run`.
