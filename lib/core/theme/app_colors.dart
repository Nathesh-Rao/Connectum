import 'package:flutter/painting.dart';

class AppColors {
  AppColors._();

  // Brand family. [primary] is filled buttons, links and active labels (white
  // on it is 6.8:1). [primaryBright] is the logo blue for icons, dots, FAB,
  // switches and the focus ring; never small text (white on it is 4.3:1).
  static const primary = Color(0xFF0052CC);
  static const primaryBright = Color(0xFF0078E8);
  static const primaryLight = Color(0xFF00B4F1);
  static const cyanBlue = Color(0xFF00A1E8);
  static const primaryStrong = Color(0xFF00338D);
  static const violet = Color(0xFF8B5CF6);
  static const purple = Color(0xFF6A3FD4);

  // Tints of [primary] over white: soft 6 %, tint 10 %, strong 16 %, border
  // about 26 %, disabled 40 %.
  static const primarySoft = Color(0xFFF0F5FC);
  static const primaryTint = Color(0xFFE6EEFA);
  static const primaryTintStrong = Color(0xFFD6E3F7);
  static const primaryBorder = Color(0xFFBDD2F2);
  static const primaryDisabled = Color(0xFF99BAEB);

  /// Tint of [violet] over white (13 %) and its readable shade.
  static const violetTint = Color(0xFFF0EAFE);
  static const violetStrong = Color(0xFF5B21B6);

  /// Soft violet glow behind the selected bottom navigation icon (20 %).
  static const navIndicatorGlow = Color(0x338B5CF6);

  /// Every page, sheet and card is [white]; [surfaceSubtle] is the cool fill
  /// for a panel that has to read against a white page.
  static const surfaceSubtle = Color(0xFFF6F9FE);
  static const white = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const fill = Color(0xFFEDF2FA);
  static const slateLight = Color(0xFFCBD5E4);
  static const bubbleIn = Color(0xFFF0F4FA);
  static const bubbleOut = primaryTint;
  static const searchFill = Color(0xFFF1F5FB);
  static const avatarBg = Color(0xFFEDF2FA);
  static const avatarText = Color(0xFF4A5B7A);

  /// A mention in message text; [mentionMe] is a tag of the signed-in person.
  /// Both are at least 4.5:1 on the bubbles (incoming, outgoing, highlighted).
  static const mention = primary;
  static const mentionMe = primaryStrong;

  static const ink = Color(0xFF071F50);
  static const muted = Color(0xFF55658A);
  static const line = Color(0xFFE3EAF4);
  static const inputBorder = Color(0xFFCBD5E4);
  static const readOnlyInk = Color(0xFF2C3E63);

  static const cardLine = Color(0xFFE3EAF4);
  static const cardMuted = Color(0xFF5F6F94);
  static const cardChip = Color(0xFFEFF3F9);

  static const error = Color(0xFFC62A3A);

  /// Non-essential text and disabled content only.
  static const tertiary = Color(0xFF8C99B3);
  static const disabledInk = Color(0xFFA9B4C8);

  static const yesFill = Color(0xFFE3F6E9);
  static const yesDot = Color(0xFF16A34A);
  static const yesText = Color(0xFF14532D);
  static const noFill = Color(0xFFEDF1F7);
  static const noDot = Color(0xFF8C99B3);
  static const noText = Color(0xFF3E4C69);

  static const sphereHighlight = Color(0xFFC9ECFC);
  static const sphereMid = Color(0xFF5CC6F3);

  static const ambientDiscCenter = Color(0x1C0078E8);
  static const ambientDiscEdge = Color(0x050078E8);
  static const ambientOrbitOuter = Color(0x170078E8);
  static const ambientOrbitInner = Color(0x0C0078E8);

  /// The violet orbit ring of the splash and access backdrops (14 %).
  static const ambientOrbitViolet = Color(0x238B5CF6);
  static const rowChevron = Color(0xFFA3B0C7);
  static const tileCurrentBorder = primaryBorder;

  static const tilePalettes = [
    AppTilePalette(Color(0xFFEFF4FB), Color(0xFFDCE7F6), Color(0xFF4F6A94)),
    AppTilePalette(Color(0xFFF1EFFC), Color(0xFFE1DCF7), Color(0xFF6B58B0)),
    AppTilePalette(Color(0xFFECF6FB), Color(0xFFD6EAF5), Color(0xFF3F7A96)),
    AppTilePalette(Color(0xFFF0F2F8), Color(0xFFDFE3EE), Color(0xFF5B6784)),
  ];

  /// File-type tiles on document cards: background, border, label.
  static const docPdf = AppTilePalette(
    Color(0xFFFBE6E2),
    Color(0xFFF2C9C1),
    Color(0xFFA32A1A),
  );
  static const docWord = AppTilePalette(
    Color(0xFFE4EDF9),
    Color(0xFFC4D6EF),
    Color(0xFF1F4E96),
  );
  static const docExcel = AppTilePalette(
    Color(0xFFE3F3E8),
    Color(0xFFC1E0CB),
    Color(0xFF1B6B3A),
  );
  static const docSlides = AppTilePalette(
    Color(0xFFF0EAFE),
    Color(0xFFDCD0FA),
    Color(0xFF5B21B6),
  );
  static const docText = AppTilePalette(
    Color(0xFFEDF1F7),
    Color(0xFFD9E0EC),
    Color(0xFF3E4C69),
  );
  static const docArchive = AppTilePalette(
    Color(0xFFE2F3F1),
    Color(0xFFBFE2DE),
    Color(0xFF0B5651),
  );
  static const docOther = AppTilePalette(
    Color(0xFFE9ECEF),
    Color(0xFFD3D8DD),
    Color(0xFF3F4A54),
  );

  /// Name colours for the senders in a group, picked by a stable hash of the
  /// username. All read on [bubbleIn]. No blue hues: blue is for mentions.
  static const senderInks = [
    Color(0xFF7A2E9E),
    Color(0xFF0F766E),
    Color(0xFFA12B55),
    Color(0xFF2F6B4F),
    Color(0xFFA33B3B),
    Color(0xFF9A3B7B),
  ];

  static const scrim = Color(0xFF0B1B3B);
  static const sheetBackdrop = Color(0x660B1B3B);
  static const sheetHandle = Color(0xFFCBD5E4);
}

class AppTilePalette {
  const AppTilePalette(this.background, this.border, this.foreground);

  final Color background;
  final Color border;
  final Color foreground;
}
