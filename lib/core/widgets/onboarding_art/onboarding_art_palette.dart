import 'dart:ui';

/// A scene's drawing recipe: the scene, its frame function and the time the
/// reduced-motion static frame uses.
class ArtScene {
  const ArtScene({
    required this.render,
    required this.staticT,
    required this.duration,
    this.info = const {},
    this.mirrorAxis,
    this.setMirrored,
  });

  /// Updates the scene to time `t` (seconds).
  final void Function(double t) render;

  /// The frame shown when the platform asks for reduced motion.
  final double staticT;

  /// A sensible length for a scrubber, in seconds (the art itself loops on).
  final double duration;

  /// Timeline facts of the port (reveal times, arrival, period) for tests.
  final Map<String, Object?> info;

  /// Set for a mirror-symmetric scene: the scene is the left half (plus
  /// whatever sits on the axis) and the painter draws it a second time flipped
  /// about x = [mirrorAxis], after [setMirrored] hid the nodes that are on the
  /// axis and must be drawn once.
  final double? mirrorAxis;
  final void Function(bool isMirrored)? setMirrored;
}

/// Every colour of the three authored animations, as authored, in one place.
/// The art data files (generated/) carry the same values as hex strings.
class OnboardingArtPalette {
  OnboardingArtPalette._();

  // ---- shield-security.html
  static const shieldCyan = Color(0xFF18ABFA);
  static const shieldBlue = Color(0xFF60AFF4);
  static const shieldDeep = Color(0xFF0049B2);
  static const shieldNode = Color(0xFF1A92EE);
  static const shieldSky = Color(0xFF96D6F6);
  static const shieldMist = Color(0xFFC5E1F7);
  static const shieldPaper = Color(0xFFFBFBFB);
  static const shieldCloud = Color(0xFFEAECF8);
  static const shieldShadow = Color(0xFFCCCADC);
  static const shieldPeriwinkle = Color(0xFFACB3F1);
  // violets of the encrypted side
  static const shieldViolet = Color(0xFF8F6DF5);
  static const shieldVioletDeep = Color(0xFF683FE1);
  static const shieldVioletMid = Color(0xFF6F47E6);
  static const shieldVioletPulse = Color(0xFF6A3FD4);

  // ---- network-icons.html
  static const networkCyan = Color(0xFF00CEF8);
  static const networkNavy = Color(0xFF013680);
  static const networkDeep = Color(0xFF0062C3);
  static const networkBlue = Color(0xFF007AD5);
  static const networkSky = Color(0xFF059CEA);
  static const networkViolet = Color(0xFF794AD3);

  // ---- buildings-switching.html
  static const buildingsBlue = Color(0xFF2E83EB);
  static const buildingsDeep = Color(0xFF0047AB);
  static const buildingsRoyal = Color(0xFF0150C6);
  static const buildingsCyan = Color(0xFF0BB6F6);
  static const buildingsSky = Color(0xFF65ACF8);
  static const buildingsMist = Color(0xFFE9F1FA);
  static const buildingsViolet = Color(0xFF9279F8);
  static const buildingsVioletDeep = Color(0xFF5D37E3);
  static const buildingsVioletMid = Color(0xFF7445EE);

  // ---- lab backdrops (preview only)
  static const previewLight = Color(0xFFEAECF8);

  // ---- app blue tokens used by the "Blue only" remap (same values as AppColors)
  static const _primaryBright = Color(0xFF0078E8);
  static const _primaryLight = Color(0xFF00B4F1);
  static const _cyanBlue = Color(0xFF00A1E8);
  static const _primaryStrong = Color(0xFF00338D);

  /// Violet to the nearest existing blue token; neighbouring shapes keep their
  /// light/dark order. Every other colour stays as authored.
  static final Map<int, Color> purpleToBlueMap = {
    shieldViolet.toARGB32(): _cyanBlue,
    shieldVioletMid.toARGB32(): _primaryBright,
    shieldVioletDeep.toARGB32(): _primaryStrong,
    shieldVioletPulse.toARGB32(): _primaryBright,
    shieldPeriwinkle.toARGB32(): shieldSky,
    networkViolet.toARGB32(): _primaryBright,
    buildingsViolet.toARGB32(): _primaryLight,
    buildingsVioletMid.toARGB32(): _primaryBright,
    buildingsVioletDeep.toARGB32(): _primaryStrong,
  };

  static Color purpleToBlue(Color c) => purpleToBlueMap[c.toARGB32()] ?? c;

  static Color authored(Color c) => c;
}
