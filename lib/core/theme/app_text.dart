import 'package:flutter/painting.dart';

import 'app_colors.dart';

class AppText {
  AppText._();

  static const fontFamily = 'PlusJakartaSans';
  static const displayFontFamily = 'SpaceGrotesk';

  static const double sizeDisplay = 30;
  static const double sizeHeading = 26;
  static const double sizeTitle = 21;
  static const double sizeSubtitle = 17;
  static const double sizeButton = 14;
  static const double sizeBody = 13;
  static const double sizeReadable = 12;
  static const double sizeCaption = 11;

  static const double heightHeading = 1.2;
  static const double heightBody = 1.6;
  static const double heightControl = 1.3;

  static const display = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeDisplay,
    fontWeight: FontWeight.w600,
    height: heightHeading,
    letterSpacing: -1.2,
    color: AppColors.ink,
  );

  static const displayBrand = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.1,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static const displayBrandSm = TextStyle(
    fontFamily: displayFontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static const heading = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeHeading,
    fontWeight: FontWeight.w600,
    height: heightHeading,
    letterSpacing: -1,
    color: AppColors.ink,
  );

  static const title = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeTitle,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -1,
    color: AppColors.ink,
  );

  static const subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeSubtitle,
    fontWeight: FontWeight.w600,
    height: heightHeading,
    letterSpacing: -0.4,
    color: AppColors.ink,
  );

  static const button = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeButton,
    fontWeight: FontWeight.w600,
    height: heightControl,
    color: AppColors.white,
  );

  static const input = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeBody,
    fontWeight: FontWeight.w400,
    height: heightControl,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeBody,
    fontWeight: FontWeight.w400,
    height: heightBody,
    color: AppColors.ink,
  );

  static const bodyStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeBody,
    fontWeight: FontWeight.w600,
    height: heightBody,
    color: AppColors.ink,
  );

  static const supporting = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeButton,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.muted,
  );

  static const readable = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w400,
    height: heightBody,
    color: AppColors.muted,
  );

  static const readableStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w600,
    height: heightBody,
    color: AppColors.ink,
  );

  static const message = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: AppColors.ink,
  );

  static const label = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w600,
    height: heightBody,
    color: AppColors.muted,
  );

  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w400,
    height: heightBody,
    color: AppColors.muted,
  );

  static const error = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w400,
    height: heightBody,
    color: AppColors.error,
  );

  static const hero = TextStyle(
    fontFamily: fontFamily,
    fontSize: 29,
    fontWeight: FontWeight.w600,
    height: heightHeading,
    letterSpacing: -1,
    color: AppColors.ink,
  );

  static const heroSlide = TextStyle(
    fontFamily: fontFamily,
    fontSize: 29,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -1.1,
    color: AppColors.ink,
  );

  static const wordmark = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.5,
    letterSpacing: -0.6,
    color: AppColors.ink,
  );

  static const wordmarkLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.5,
    letterSpacing: -0.6,
    color: AppColors.ink,
  );

  static const fieldLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w600,
    height: heightHeading + 0.3,
    color: AppColors.ink,
  );

  static const buttonSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w600,
    height: heightControl,
    color: AppColors.white,
  );

  static const kicker = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w600,
    height: 1.5,
    letterSpacing: 1.5,
    color: AppColors.muted,
  );

  static const eyebrow = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 1.1,
    color: AppColors.muted,
  );

  static const digit = TextStyle(
    fontFamily: fontFamily,
    fontSize: 23,
    fontWeight: FontWeight.w500,
    height: heightBody - 0.1,
    color: AppColors.ink,
  );

  static const rowTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );

  /// The count inside the notification bell's accent circle.
  static const bellCount = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.white,
  );

  /// Label of the compact pill (Chats filters).
  static const pillCompact = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: heightBody,
    color: AppColors.ink,
  );

  static const rowCaption = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.1,
    color: AppColors.muted,
  );

  static const idValue = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.5,
    color: AppColors.ink,
  );

  static const rowLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.ink,
  );

  static const segment = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.muted,
  );

  static const heroCopy = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w400,
    height: 1.8,
    color: AppColors.muted,
  );

  static const heroCopyStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeReadable,
    fontWeight: FontWeight.w600,
    height: 1.8,
    color: AppColors.ink,
  );

  static const slideCopy = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeBody,
    fontWeight: FontWeight.w400,
    height: 1.8,
    color: AppColors.muted,
  );

  static const leadingGlyph = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeSubtitle,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.muted,
  );

  static const segmentSelected = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w700,
    height: 1.5,
    color: AppColors.primary,
  );

  static const action = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.primaryStrong,
  );

  static const copiedLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeCaption,
    fontWeight: FontWeight.w600,
    height: 1.5,
    color: AppColors.yesDot,
  );
}
