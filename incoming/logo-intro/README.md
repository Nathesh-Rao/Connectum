# Logo intro for Flutter (ball → C grows out → CONNECTUM wordmark)

Files
- assets/logo.svg                        original artwork (optional – only if you also show a static logo with flutter_svg)
- lib/logo_intro/logo_intro_data.dart    generated geometry: exact original paths, wordmark letters, pre-computed growth data
- lib/logo_intro/logo_intro.dart         `LogoIntro` widget + `LogoIntroController`
- example/main.dart                      tiny demo with a Replay button

No packages needed (only `flutter/material.dart`). Copy the `lib/logo_intro/` folder into your app.

Usage
```dart
final intro = LogoIntroController();

LogoIntro(
  size: 320,                       // or omit to fill the available square
  controller: intro,               // optional – lets you call intro.replay()
  onFinished: () => goToHome(),    // fires once at the end (≈5.5 s); the final logo stays on screen
)

intro.replay();                    // restart from the beginning
```
Colours (all optional): `ink` (wordmark), `shine` (light sweep), `ball` (starting ball), `glowInner`, `glowOuter`.
Use `ink: Colors.white` on dark backgrounds. The background is transparent.
`LogoIntro.duration` gives the total length in seconds. With the system "reduce motion" setting on, it shows the finished logo immediately.
