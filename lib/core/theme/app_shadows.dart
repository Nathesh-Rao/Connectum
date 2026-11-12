import 'package:flutter/painting.dart';

class AppShadows {
  AppShadows._();

  static const focusRing = [
    BoxShadow(color: Color(0x1A0078E8), spreadRadius: 3),
  ];

  static const sheet = [
    BoxShadow(
      color: Color(0x4D0B1B3B),
      blurRadius: 40,
      spreadRadius: -16,
      offset: Offset(0, -12),
    ),
  ];

  static const card = [
    BoxShadow(color: Color(0x0D071F50), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x38071F50),
      blurRadius: 18,
      spreadRadius: -14,
      offset: Offset(0, 10),
    ),
  ];

  static const fab = [
    BoxShadow(color: Color(0x33003A8C), blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x1A003A8C), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const soft = [
    BoxShadow(color: Color(0x0B003A8C), blurRadius: 22, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x04003A8C), blurRadius: 2, offset: Offset(0, 1)),
  ];
}
