# LogoIntro

`logo_intro.dart` and `logo_intro_data.dart` come from the design tool. The geometry (57 C parts, wordmark letters, growth data) is generated there and must not be edited by hand. To update, replace both files and re-apply the app changes (token colours, `speed`, `finishAt`, `timeOverride`, `blurLetters`, `glowFinal`, reduced motion).

TUNE constants:
- `IntroTiming` in `logo_intro.dart`: pop, grow0, grow, stagger, letter, glint, tail (seconds, authored timeline).
- Lockup layout `kIconScale`, `kTextScale`, `kGapScale` (a local change on top of the design tool's output; re-apply after a replace) in `_IntroPainter`.
- Camera (scale 1.9 to 0.92, centres), thumps, letter reveal, glint and glow maths: `_IntroPainter` in `logo_intro.dart`.
- Splash: `kSplashUsesLogoIntro`, `kSplashIntroSpeed`, `kSplashFinishAt`, `kSplashHold`, `kSplashLogoSize` in `lib/features/splash/splash_controller.dart`.

Debug page: `/debug/logo-intro`.
