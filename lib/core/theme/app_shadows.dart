import 'package:flutter/painting.dart';

class AppShadows {
  AppShadows._();

  static const focusRing = [
    BoxShadow(color: Color(0x1AF66510), spreadRadius: 3),
  ];

  static const sheet = [
    BoxShadow(
      color: Color(0x4D28211D),
      blurRadius: 40,
      spreadRadius: -16,
      offset: Offset(0, -12),
    ),
  ];

  static const card = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x38000000),
      blurRadius: 18,
      spreadRadius: -14,
      offset: Offset(0, 10),
    ),
  ];

  static const fab = [
    BoxShadow(color: Color(0x33653D16), blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x1A653D16), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const soft = [
    BoxShadow(color: Color(0x0B653D16), blurRadius: 22, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x04653D16), blurRadius: 2, offset: Offset(0, 1)),
  ];
}
