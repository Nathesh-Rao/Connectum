/// Positions and sizes of the ambient backdrop shapes, measured on the
/// prototype's 390x844 frame. Horizontal values are proportions of the screen
/// width, vertical values are proportions of the content height (the area
/// under the status bar), so the backdrop follows other phone sizes.
class AppAmbientShape {
  const AppAmbientShape(this.x, this.y, this.size, {this.opacity = 1});

  final double x;
  final double y;
  final double size;
  final double opacity;
}

class AppAmbient {
  AppAmbient._();

  static const _w = 390.0;
  static const _h = 772.0;

  // Authentication and verification.
  static const accessDisc = AppAmbientShape(285 / _w, -67 / _h, 280 / _w);
  static const accessOrbit = AppAmbientShape(-203 / _w, 35 / _h, 276 / _w);
  static const accessOrbitInner = AppAmbientShape(-203 / _w, 35 / _h, 240 / _w);
  static const accessSpheres = [
    AppAmbientShape(343 / _w, 100 / _h, 18 / _w),
    AppAmbientShape(36 / _w, 190 / _h, 10 / _w, opacity: 0.6),
    AppAmbientShape(317 / _w, 219 / _h, 6 / _w, opacity: 0.5),
  ];

  // Splash.
  static const splashDisc = AppAmbientShape(
    220 / _w,
    -180 / _h,
    400 / _w,
    opacity: 0.6,
  );
  static const splashOrbit = AppAmbientShape(
    -120 / _w,
    572 / _h,
    400 / _w,
    opacity: 0.5,
  );
  static const splashOrbitInner = AppAmbientShape(
    -120 / _w,
    572 / _h,
    364 / _w,
    opacity: 0.5,
  );

  // Onboarding glow band: the stage (340x270) plus 16 above and 17 below,
  // full width. Sphere x is a proportion of the width, y and size are dp.
  static const onboardingBandTop = 16.0;
  static const onboardingBandBottom = 17.0;
  static const onboardingSpheres = [
    [
      OnboardingSphere(274 / _w, 5, 63),
      OnboardingSphere(-18 / _w, 202, 32),
      OnboardingSphere(138 / _w, 30, 22),
      OnboardingSphere(354 / _w, 238, 16),
    ],
    [OnboardingSphere(198 / _w, 24, 54)],
    [OnboardingSphere(144 / _w, 16, 58)],
  ];
}

class OnboardingSphere {
  const OnboardingSphere(this.x, this.y, this.size);

  final double x;
  final double y;
  final double size;
}
