import 'package:flutter/painting.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text.dart';
import 'app_tones.dart';

/// Tokens of the Smart View screens (cards, table, controls, sheets, speed
/// dial, KPIs, charts).
class AppSv {
  AppSv._();

  static const _font = AppText.fontFamily;

  // Card (phone scale)
  static const double cardRadius = 18;
  static const double cardPad = 16;
  static const double cardGap = 12;
  static const double headerHeight = 56;
  static const double numberCircle = 30;
  static const double numberGap = 12;
  static const double rowMin = 40;
  static const double rowPadY = 9;
  static const double rowIcon = 16;
  static const double rowIconGap = 10;
  static const cardBorder = Color(0xFFE3E8F8);
  static const cardShadow = [
    BoxShadow(color: Color(0x0D243C8C), blurRadius: 10, offset: Offset(0, 2)),
  ];
  static const hairline = Color(0xFFEEF2F8);
  static const cardInk = Color(0xFF0B1456);
  static const numberFill = AppColors.primaryTintStrong;
  static const svDecoPaleBlue = Color(0xFFEAF3FF);
  static const svDecoSoftBlue = Color(0xFFDCEAFF);
  static const svDecoPaleLavender = Color(0xFFF0E9FF);
  static const svDecoWhite = Color(0xFFFFFFFF);
  static const double svDecoWaveAlpha = 0.4;
  static const double svDecoWaveOffset = 7;
  static const double svDecoMaxDepth = 64;
  static const double headerPillMax = 150;
  static const double pillDot = 6;
  static const double pillPadX = 10;
  static const double pillPadY = 4;
  static const pillText = TextStyle(
    fontFamily: _font,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static const showAll = TextStyle(
    fontFamily: _font,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.cardMuted,
  );
  static const numberText = TextStyle(
    fontFamily: _font,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: cardInk,
  );
  static const numberTextSmall = TextStyle(
    fontFamily: _font,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: cardInk,
  );
  static const cardTitle = TextStyle(
    fontFamily: _font,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: cardInk,
  );
  static const fieldKey = TextStyle(
    fontFamily: _font,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.cardMuted,
  );
  static const fieldValue = TextStyle(
    fontFamily: _font,
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: cardInk,
  );
  static const fieldValueEmpty = TextStyle(
    fontFamily: _font,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.tertiary,
  );

  /// The tone of a field type's icon circle.
  static AppTone toneOfType(String kind) => switch (kind) {
    'date' || 'time' || 'datetime' => AppTones.blue,
    'number' => AppTones.teal,
    'status' || 'select' => AppTones.violet,
    'email' || 'phone' || 'url' => AppTones.indigo,
    'checkbox' => AppTones.green,
    'person' => AppTones.purple,
    _ => AppTones.slate,
  };

  // Table
  static const double tableRowMin = 52;
  static const double tableCellPadX = 14;
  static const tableHeaderFill = AppColors.primary;
  static const double tableTopGap = 20;
  static const tableRowAlt = Color(0x0B0052CC);
  static const tableRowPressed = Color(0x140052CC);
  static const tableHead = TextStyle(
    fontFamily: _font,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: AppColors.white,
  );
  static const tableCell = TextStyle(
    fontFamily: _font,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.ink,
  );
  static const tableCellNo = TextStyle(
    fontFamily: _font,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.ink,
  );

  /// The "View more" link in a table cell.
  static const double tableMoreGap = 6;
  static const tableMore = TextStyle(
    fontFamily: _font,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.violetStrong,
  );
  static const int tableMaxWords = 10;
  static const double tableMaxWidthShare = 0.6;

  // Overview
  static const double ovTileRadius = 16;
  static const double ovIconCircle = 36;
  static const double ovCardIcon = 36;
  static const double ovCardIconRadius = 10;
  static const double ovPad = 16;
  static const double ovGap = 12;
  static const double ovSlide = 12;
  static const double ovBarWidth = 6;
  static const double ovBarGap = 4;
  static const double ovBarMax = 36;
  static const double ovBarDash = 3;
  static const double ovBarRestAlpha = 0.25;
  static const double ovMixHeight = 8;
  static const double ovMixGap = 3;
  static const double ovMixRadius = 3;
  static const double ovPressScale = 0.98;
  static const double ovSkeletonLow = 0.45;
  static const int ovLegendMax = 3;
  static const ovStagger = Duration(milliseconds: 60);
  static const ovEnter = Duration(milliseconds: 280);
  static const ovCount = Duration(milliseconds: 500);
  static const ovPress = Duration(milliseconds: 120);
  static const ovPulse = Duration(milliseconds: 900);
  static const ovSwitch = Duration(milliseconds: 220);
  static const ovLabel = TextStyle(
    fontFamily: _font,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.cardMuted,
  );
  static const ovValue = TextStyle(
    fontFamily: _font,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.ink,
  );
  static const ovName = TextStyle(
    fontFamily: _font,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: cardInk,
  );
  static const ovBig = TextStyle(
    fontFamily: _font,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.1,
    color: cardInk,
  );
  static const ovLegend = TextStyle(
    fontFamily: _font,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.cardMuted,
  );
  static const ovLegendCount = TextStyle(
    fontFamily: _font,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: cardInk,
  );

  // Controls row
  static const double controlButton = 40;
  static const double controlGap = 10;
  static const double controlRest = 0.11;
  static const double controlPressed = 0.18;
  static const double controlActive = 0.20;
  static const double controlDot = 8;
  static const double controlPressScale = 0.94;
  static const searchTone = AppTones.blue;
  static const filterTone = AppTones.violet;
  static const sortTone = AppTones.teal;

  // Saved views
  static const double viewTabHeight = 36;
  static const double viewTabGap = 8;
  static const double groupHeaderHeight = 48;
  static const double groupIndentBase = 14;
  static const double groupIndentStep = 22;
  static const double orderBadge = 20;

  // Sheets
  static const double sheetIconCircle = 36;
  static const double sheetRowHeight = 56;
  static const double emptyCircle = 56;
  static const double removeCircle = 28;
  static const filterCardFill = Color(0xFFF6F8FC);
  static const sortIconFill = Color(0xFFEEF2F9);

  // History comment
  static const double commentDot = 8;
  static const double commentDotGap = 10;
  static const commentText = TextStyle(
    fontFamily: _font,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.ink,
  );
  static const commentMore = TextStyle(
    fontFamily: _font,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.violetStrong,
  );

  // Speed dial
  /// Room kept under a list so its last item scrolls clear of the button.
  static const double dialClearance =
      AppSpacing.fab + AppSpacing.fabMargin + 16;
  static const double dialOption = 48;
  static const double dialGap = 14;
  static const double dialStagger = 60;
  static const dialScrim = Color(0x1F0B1B3B);
  static const dialLabel = TextStyle(
    fontFamily: _font,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );
  static const dialShadow = [
    BoxShadow(color: Color(0x1F0B1B3B), blurRadius: 12, offset: Offset(0, 3)),
  ];

  // KPI
  static const kpiCount = Duration(milliseconds: 400);
  static const kpiStagger = Duration(milliseconds: 50);
  static const chartDraw = Duration(milliseconds: 450);
  static const double kpiIconCircle = 32;
  static const kpiLabel = TextStyle(
    fontFamily: _font,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.cardMuted,
  );
  static const kpiValue = TextStyle(
    fontFamily: _font,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.ink,
  );
  static const kpiSub = TextStyle(
    fontFamily: _font,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.tertiary,
  );

  // Charts: eight colours, assigned by the category's position in the sorted
  // list of its values, never random.
  static const chartPalette = [
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFEC4899),
    Color(0xFF22C55E),
    Color(0xFF06B6D4),
    Color(0xFFD946EF),
  ];
  static const chartOthers = Color(0xFFB4BED0);
  static const chartGrid = Color(0xFFE8EDF5);
  static const chartLabel = TextStyle(
    fontFamily: _font,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.cardMuted,
  );
  static const chartValue = TextStyle(
    fontFamily: _font,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
  static const chartCenter = TextStyle(
    fontFamily: _font,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  // ---- files (chips and the viewer) ----------------------------------------
  static const double fileChipHeight = 30;
  static const double fileChipRadius = 8;
  static const double fileChipIcon = 16;
  static const double fileTileHeight = 34;
  static const double fileChipMaxWidth = 200;
  static const double fileChipGap = 6;
  static const double fileMinHit = 44;
  static const int fileChipMaxName = 26;
  static const int fileChipsMax = 3;
  static const fileChipName = TextStyle(
    fontFamily: _font,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: cardInk,
  );
  static const fileChipSize = TextStyle(
    fontFamily: _font,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.cardMuted,
  );
  static const double fileBarHeight = 56;
  static const double fileDialogInset = 16;
  static const double fileDialogRadius = 20;
  static const double fileDialogHeight = 0.78;
  static const fileDialogShadow = [
    BoxShadow(color: Color(0x290B1B3B), blurRadius: 32, offset: Offset(0, 12)),
  ];
  static const double fileHeaderCircle = 36;
  static const double fileHeaderIcon = 18;
  static const double fileScrim = 0.4;
  static const double fileDot = 6;
  static const double fileSheetCell = 140;
  static const double fileSheetRow = 36;
  static const double fileSheetTab = 32;
  static const double fileCircle = 96;
  static const double fileCircleIcon = 44;
  static const double fileRing = 72;
  static const double fileRingStroke = 5;
  static const double fileZoomMax = 5;
  static const double fileDoubleTapZoom = 2.5;
  static const double fileOpenScale = 0.96;
  static const double fileTextPad = 16;
  static const fileMono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.45,
    color: cardInk,
  );
  static const fileTitle = TextStyle(
    fontFamily: _font,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.ink,
  );
}
