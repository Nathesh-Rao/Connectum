import 'package:flutter/painting.dart';

import 'app_colors.dart';
import 'app_tones.dart';

/// Tokens of the Inbox shell: the round tonal header buttons, the sliding tab
/// bar, the search pill, the view chip and the filter sheet's section cards.
class AppInbox {
  AppInbox._();

  // Header buttons: a round tonal disc inside a 44 dp tap target.
  static const double hit = 44;
  static const double disc = 38;
  static const double discIcon = 20;
  static const discFill = AppColors.primaryTint;
  static const discInk = AppColors.primaryStrong;
  static const discActiveFill = AppColors.primary;
  static const discActiveInk = AppColors.white;

  // The two header buttons keep their own tones.
  static const searchTone = AppTones.blue;
  static const filterTone = AppTones.violet;

  // The search's close button: a solid disc outside the field.
  static const closeFill = AppColors.primary;
  static const closeInk = AppColors.white;
  static const double closeDisc = 40;

  // The tabs' count pills, one tone each (never the same grey).
  static const recordsCountTone = AppTones.primary;
  static const approvalsCountTone = AppTones.purple;
  static const emptyCountTone = AppTones.slate;

  // Search pill.
  static const double searchHeight = 44;
  static const searchFill = AppColors.searchFill;
  static const searchRing = AppColors.primaryBorder;

  // Tab bar.
  static const double tabTrackPad = 4;
  static const double tabHeight = 44;
  static const double tabIcon = 18;
  static const trackFill = AppColors.fill;
  static const thumbFill = AppColors.white;
  static const tabInk = AppColors.ink;
  static const tabMuted = AppColors.muted;
  static const thumbShadow = [
    BoxShadow(color: Color(0x24071F50), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0F071F50), blurRadius: 1, offset: Offset(0, 0)),
  ];

  // View chip.
  static const double viewChipHeight = 32;
  static const double viewChipMinWidth = 80;
  static const double titleMaxScale = 1.15;
  static const viewChipFill = AppColors.surfaceSubtle;
  static const viewChipBorder = AppColors.primaryBorder;
  static const changedDot = AppColors.violet;

  // Filter and views panels.
  static const double cardRadius = 18;
  static const double sectionIcon = 32;
  static const cardFill = AppColors.surfaceSubtle;
  static const cardBorder = AppColors.line;
  static const chipSelectedFill = AppColors.primary;
  static const chipSelectedInk = AppColors.white;
  static const chipFill = AppColors.white;
  static const chipBorder = AppColors.inputBorder;

  static const whereTone = AppTones.indigo;
  static const peopleTone = AppTones.violet;
  static const detailsTone = AppTones.teal;

  // The filter popup.
  static const double popupRadius = 24;
  static const double popupMaxWidth = 440;
  static const popupBorder = AppColors.primaryBorder;
  static const removableFill = AppColors.primaryTint;
  static const removableInk = AppColors.primaryStrong;
  static const advancedTone = AppTones.slate;
}
