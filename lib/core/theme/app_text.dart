import 'package:flutter/painting.dart';

import 'app_colors.dart';

class AppText {
  AppText._();

  static const fontFamily = 'PlusJakartaSans';

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
    fontWeight: FontWeight.w700,
    height: heightHeading,
    letterSpacing: -1,
    color: AppColors.ink,
  );

  static const heading = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeHeading,
    fontWeight: FontWeight.w700,
    height: heightHeading,
    letterSpacing: -1,
    color: AppColors.ink,
  );

  static const title = TextStyle(
    fontFamily: fontFamily,
    fontSize: sizeTitle,
    fontWeight: FontWeight.w700,
    height: heightHeading,
    letterSpacing: -0.5,
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
    color: AppColors.background,
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
}
