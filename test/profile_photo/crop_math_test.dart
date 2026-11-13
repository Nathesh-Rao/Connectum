import 'dart:math' as math;
import 'dart:ui';

import 'package:connectum/features/profile_photo/crop_math.dart';
import 'package:flutter_test/flutter_test.dart';

CropState _state({
  double w = 200,
  double h = 100,
  double box = 100,
  int turns = 0,
  double straighten = 0,
  double zoom = 1,
  Offset offset = Offset.zero,
}) => CropState(
  imageW: w,
  imageH: h,
  box: box,
  quarterTurns: turns,
  straighten: straighten,
  zoom: zoom,
  offset: offset,
);

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 1e-6));
  expect(actual.top, closeTo(expected.top, 1e-6));
  expect(actual.width, closeTo(expected.width, 1e-6));
  expect(actual.height, closeTo(expected.height, 1e-6));
}

/// Every corner of the frame lies inside the picture.
void _expectCovered(CropState s) {
  for (final c in s.sourceCorners) {
    expect(c.dx, inInclusiveRange(-1e-6, s.imageW + 1e-6));
    expect(c.dy, inInclusiveRange(-1e-6, s.imageH + 1e-6));
  }
}

void main() {
  group('start view', () {
    test('smallest size, middle of the picture', () {
      final s = _state();
      expect(s.scale, 1);
      _expectRect(s.sourceRect, const Rect.fromLTWH(50, 0, 100, 100));
    });

    test('a portrait picture is cut from the middle too', () {
      final s = _state(w: 100, h: 300);
      _expectRect(s.sourceRect, const Rect.fromLTWH(0, 100, 100, 100));
    });
  });

  group('pan', () {
    test('dragging right shows the part to the left', () {
      final s = _state().panned(const Offset(20, 0));
      _expectRect(s.sourceRect, const Rect.fromLTWH(30, 0, 100, 100));
    });

    test('never shows an empty edge', () {
      final s = _state().panned(const Offset(5000, 5000));
      _expectRect(s.sourceRect, const Rect.fromLTWH(0, 0, 100, 100));
      _expectCovered(s);
      final other = _state().panned(const Offset(-5000, -5000));
      _expectRect(other.sourceRect, const Rect.fromLTWH(100, 0, 100, 100));
    });
  });

  group('zoom', () {
    test('2x keeps the middle and halves the part kept', () {
      final s = _state().zoomedAround(2);
      _expectRect(s.sourceRect, const Rect.fromLTWH(75, 25, 50, 50));
    });

    test('around a point keeps that point of the picture still', () {
      const focal = Offset(30, -20);
      final before = _state();
      final s = before.zoomedAround(3, focal);
      // the source point under the focal is the same before and after
      Offset under(CropState c) {
        final r = c.sourceRect;
        final k = c.box / r.width;
        return Offset(r.center.dx + focal.dx / k, r.center.dy + focal.dy / k);
      }

      expect(under(s).dx, closeTo(under(before).dx, 1e-6));
      expect(under(s).dy, closeTo(under(before).dy, 1e-6));
    });

    test('is clamped between 1x and 4x', () {
      expect(_state().zoomedAround(0.2).zoom, 1);
      expect(_state().zoomedAround(99).zoom, CropState.maxZoom);
      _expectRect(
        _state().zoomedAround(99).sourceRect,
        const Rect.fromLTWH(87.5, 37.5, 25, 25),
      );
    });

    test('a pinch at the edge still covers the frame', () {
      final s = _state()
          .zoomedAround(4, const Offset(50, 50))
          .panned(const Offset(900, 900));
      _expectCovered(s);
    });
  });

  group('rotation', () {
    test('a quarter turn right keeps the middle and the size', () {
      final s = _state().rotated(1);
      _expectRect(s.sourceRect, const Rect.fromLTWH(50, 0, 100, 100));
      expect(s.angle, closeTo(math.pi / 2, 1e-9));
    });

    test('a quarter turn moves the dragged part about the frame centre', () {
      // drag to show the left end, turn right: the frame now looks at the same
      // part of the picture, turned
      final dragged = _state().panned(const Offset(500, 0));
      _expectRect(dragged.sourceRect, const Rect.fromLTWH(0, 0, 100, 100));
      final turned = dragged.rotated(1);
      _expectRect(turned.sourceRect, const Rect.fromLTWH(0, 0, 100, 100));
    });

    test('four quarter turns come back', () {
      var s = _state().panned(const Offset(40, 0));
      for (var i = 0; i < 4; i++) {
        s = s.rotated(1);
      }
      expect(s.quarterTurns, 0);
      _expectRect(s.sourceRect, const Rect.fromLTWH(10, 0, 100, 100));
    });

    test('left from the start is three quarters', () {
      expect(_state().rotated(-1).quarterTurns, 3);
    });

    test('a portrait picture turned a quarter is cut on its long axis', () {
      final s = _state(w: 100, h: 300).rotated(1).panned(const Offset(0, 5000));
      _expectCovered(s);
    });
  });

  group('straighten', () {
    test('45 degrees needs the picture sqrt(2) larger to cover', () {
      final s = _state(w: 200, h: 200).withStraighten(math.pi / 4);
      expect(s.scale, closeTo(math.sqrt2 * 0.5, 1e-9));
      _expectCovered(s);
    });

    test('the corners always lie inside, at any angle and offset', () {
      for (final deg in [-45.0, -30.0, -7.5, 0.0, 12.0, 45.0]) {
        for (final zoom in [1.0, 2.5, 4.0]) {
          final s = _state(w: 300, h: 180)
              .withStraighten(deg * math.pi / 180)
              .zoomedAround(zoom)
              .panned(const Offset(777, -999));
          _expectCovered(s);
        }
      }
    });

    test('is clamped to 45 degrees', () {
      expect(
        _state().withStraighten(math.pi).straighten,
        closeTo(math.pi / 4, 1e-12),
      );
    });

    test('keeps the picture point under the frame centre', () {
      final before = _state().panned(const Offset(30, 0)).zoomedAround(2);
      final after = before.withStraighten(0.2);
      expect(
        after.sourceRect.center.dx,
        closeTo(before.sourceRect.center.dx, 1e-6),
      );
      expect(
        after.sourceRect.center.dy,
        closeTo(before.sourceRect.center.dy, 1e-6),
      );
    });

    test(
      'the frame turns against the picture: corners are a rotated square',
      () {
        final s = _state(w: 400, h: 400).withStraighten(math.pi / 6);
        final c = s.sourceCorners;
        final side = (c[1] - c[0]).distance;
        expect(side, closeTo(s.box / s.scale, 1e-6));
        expect((c[2] - c[1]).distance, closeTo(side, 1e-6));
        final turn = math.atan2(c[1].dy - c[0].dy, c[1].dx - c[0].dx);
        expect(turn, closeTo(-math.pi / 6, 1e-9));
      },
    );
  });

  group('reset and resize', () {
    test('reset gives the start view', () {
      final s = _state()
          .rotated(1)
          .withStraighten(0.3)
          .zoomedAround(3)
          .panned(const Offset(20, 20));
      expect(s.isUntouched, isFalse);
      expect(s.reset().isUntouched, isTrue);
      expect(_state().isUntouched, isTrue);
    });

    test('a new frame size keeps the same part of the picture', () {
      final s = _state().panned(const Offset(20, 0)).zoomedAround(2);
      final bigger = s.withBox(200);
      _expectRect(bigger.sourceRect, s.sourceRect);
    });
  });
}
