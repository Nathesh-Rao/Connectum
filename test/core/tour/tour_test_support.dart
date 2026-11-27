import 'dart:io';

import 'package:connectum/core/tour/tour_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A store that lives in memory. The intro dialog of user `u1` counts
/// as seen unless [hasIntro] is true, so other tests never meet the dialog.
TourStore memoryStore([Map<String, String>? data, bool hasIntro = false]) {
  final map = data ?? <String, String>{};
  if (!hasIntro) map.putIfAbsent(TourStore.introKeyOf('u1'), () => '1');
  return TourStore(
    read: (k) async => map[k],
    write: (k, v) async => map[k] = v,
    delete: (k) async => map.remove(k),
  );
}

/// Three boxes with keys, in a screen with animations off (no pulse).
class TourHarness extends StatelessWidget {
  const TourHarness({
    super.key,
    required this.keys,
    this.shown = 3,
    this.scale = 1.0,
    this.width = 400.0,
  });

  final List<GlobalKey> keys;
  final int shown;
  final double scale;
  final double width;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 60),
            for (var i = 0; i < shown; i++)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  key: keys[i],
                  height: 50,
                  width: width - 16,
                  child: const ColoredBox(color: Colors.blue),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lets the overlay insert, focus and fade its card in.
Future<void> pumpTour(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// The test font is very wide, so a card is far taller than on a phone: a
/// tall screen keeps its buttons on screen.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The app font, so text is as wide as on a phone (the test font is not).
Future<void> loadAppFont() async {
  final loader = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}
