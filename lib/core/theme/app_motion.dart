import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

class AppDurations {
  AppDurations._();

  static const fast = Duration(milliseconds: 190);
  static const base = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 500);
  static const page = Duration(milliseconds: 450);
  static const reduced = Duration(milliseconds: 150);
  static const stagger = Duration(milliseconds: 55);
  static const splashHold = Duration(milliseconds: 1800);
  static const copiedHold = Duration(milliseconds: 1500);
  static const spin = Duration(milliseconds: 900);
  static const stateFloat = Duration(seconds: 3);
  static const sheetResize = Duration(milliseconds: 230);
  static const scanSweep = Duration(seconds: 1);
  static const scanSuccess = Duration(milliseconds: 300);
}

class AppCurves {
  AppCurves._();

  static const out = Cubic(0.25, 0.06, 0.12, 1);
  static const easeIn = Cubic(0.4, 0, 1, 1);
  static const inOut = Cubic(0.65, 0, 0.35, 1);

  static const sheetSpring = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 32,
  );
  static const sheet = SpringCurve(sheetSpring, Duration(milliseconds: 500));
  static const pressSpring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 34,
  );
}

class AppDistances {
  AppDistances._();

  static const double rise = 12;
  static const double stateFloat = 4;
  static const double stateIntroScale = 0.94;
  static const double tab = 8;
  static const double modeShift = 24;
  static const double enter = 16;
  static const double parallax = 0.25;
  static const double pressScale = 0.97;
  static const double introScale = 1.02;
  static const double chipPopScale = 0.7;
  static const double scrimOpacity = 0.12;
}

class SpringCurve extends Curve {
  const SpringCurve(this.spring, this.settle);

  final SpringDescription spring;
  final Duration settle;

  @override
  double transformInternal(double t) {
    final seconds = settle.inMilliseconds / 1000;
    return SpringSimulation(spring, 0, 1, 0).x(t * seconds);
  }
}
