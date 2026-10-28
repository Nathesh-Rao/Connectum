import 'package:flutter/painting.dart';

class AppRadius {
  AppRadius._();

  static const double xs = 8;
  static const double control = 10;
  static const double md = 12;
  static const double card = 14;
  static const double bubble = 15;
  static const double lg = 16;
  static const double sheet = 20;
  static const double pill = 999;

  static const controlAll = BorderRadius.all(Radius.circular(control));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const cardAll = BorderRadius.all(Radius.circular(card));
  static const pillAll = BorderRadius.all(Radius.circular(pill));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
}
