import 'package:flutter/painting.dart';

class AppColors {
  AppColors._();

  static const accent = Color(0xFFF66510);
  static const accentHover = Color(0xFFFF792D);
  static const accentTint = Color(0xFFFFF0E6);
  static const accentSoft = Color(0xFFFFF7F1);
  static const accentInk = Color(0xFF9B3B00);
  static const accentDisabled = Color(0xFFF8B58C);

  static const ivory = Color(0xFFFFF8F1);
  static const peach = Color(0xFFFFE5D2);
  static const apricot = Color(0xFFFFD0B0);
  static const sand = Color(0xFFF5E7D8);
  static const olive = Color(0xFF7E8965);
  static const taupe = Color(0xFFD8D0C5);

  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFCFA);
  static const sage = Color(0xFFF1EFEC);
  static const bubbleIn = Color(0xFFF5F3F1);
  static const searchFill = Color(0xFFF7F6F5);
  static const avatarBg = Color(0xFFF1EEEB);
  static const avatarText = Color(0xFF675E56);

  static const ink = Color(0xFF282522);
  static const muted = Color(0xFF716B66);
  static const line = Color(0xFFEEEBE8);
  static const inputBorder = Color(0xFFDED9D5);

  static const cardLine = Color(0xFFECECEB);
  static const cardMuted = Color(0xFF7D7D7B);
  static const cardChip = Color(0xFFF3F3F2);

  static const error = Color(0xFFB5351D);

  static const yesFill = Color(0xFFE3F6E9);
  static const yesDot = Color(0xFF16A34A);
  static const yesText = Color(0xFF14532D);
  static const noFill = Color(0xFFEFEFEE);
  static const noDot = Color(0xFF9A9A98);
  static const noText = Color(0xFF4A4A48);

  static const sphereHighlight = Color(0xFFFFDBB9);
  static const sphereMid = Color(0xFFFFA363);
  static const ambientDiscCenter = Color(0x1CF66510);
  static const ambientDiscEdge = Color(0x05F66510);
  static const ambientOrbitOuter = Color(0x17F66510);
  static const ambientOrbitInner = Color(0x0CF66510);
  static const rowChevron = Color(0xFFA1998D);
  static const tileCurrentBorder = Color(0xFFF8C8AA);

  static const tilePalettes = [
    AppTilePalette(Color(0xFFF5F1ED), Color(0xFFE9E2DA), Color(0xFF8A7260)),
    AppTilePalette(Color(0xFFF8F1ED), Color(0xFFEDE2DC), Color(0xFF99745F)),
    AppTilePalette(Color(0xFFF3F2EF), Color(0xFFE7E5DE), Color(0xFF80775F)),
    AppTilePalette(Color(0xFFF7F2ED), Color(0xFFEAE1D8), Color(0xFF967552)),
  ];

  /// Name colours for the senders in a group, picked by a stable hash of the
  /// username. All read on [bubbleIn].
  static const senderInks = [
    accentInk,
    Color(0xFF5F6B47),
    Color(0xFF7A5C2E),
    Color(0xFF8A4B5F),
    Color(0xFF3F6B73),
    Color(0xFF5B5A8F),
  ];

  static const scrim = Color(0xFF28211D);
  static const sheetBackdrop = Color(0x6628211D);
  static const sheetHandle = Color(0xFFD8D0C5);
}

class AppTilePalette {
  const AppTilePalette(this.background, this.border, this.foreground);

  final Color background;
  final Color border;
  final Color foreground;
}
