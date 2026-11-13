import 'dart:math' as math;
import 'dart:ui';

/// What the person has set on the crop screen, and the maths from it to the
/// part of the picture that is kept. Pure numbers: no widgets, so it is tested
/// directly.
///
/// The frame is a square of [box] screen pixels. The picture ([imageW] x
/// [imageH] source pixels) sits under it, turned by [angle] and drawn at
/// [scale] screen pixels per source pixel. [offset] is where the picture's
/// centre is, relative to the frame centre, measured along the picture's own
/// axes. Keeping it in the picture's axes makes every rotation turn about the
/// frame centre, and makes covering the frame one clamp per axis.
class CropState {
  const CropState({
    required this.imageW,
    required this.imageH,
    required this.box,
    this.quarterTurns = 0,
    this.straighten = 0,
    this.zoom = 1,
    this.offset = Offset.zero,
  });

  /// How far one can zoom in, as a multiple of the smallest size that still
  /// covers the frame (the web's `MAX_ZOOM`).
  static const maxZoom = 4.0;

  /// The fine rotation range, in radians (45 degrees either way).
  static const maxStraighten = math.pi / 4;

  final double imageW;
  final double imageH;
  final double box;
  final int quarterTurns;
  final double straighten;
  final double zoom;
  final Offset offset;

  /// The full turn of the picture under the frame, in radians.
  double get angle => quarterTurns * math.pi / 2 + straighten;

  /// The smallest scale at which the turned picture still covers the frame.
  double get minScale =>
      box * (math.cos(angle).abs() + math.sin(angle).abs()) / _shortSide;

  double get _shortSide => math.min(imageW, imageH);

  double get scale => minScale * zoom;

  /// Where the picture's centre is on screen, relative to the frame centre.
  Offset get center => _turn(offset, angle);

  bool get isUntouched =>
      quarterTurns % 4 == 0 &&
      straighten == 0 &&
      zoom == 1 &&
      offset == Offset.zero;

  /// The same state with the picture pushed back inside whatever the frame
  /// needs covered, and the zoom and straighten kept in range.
  CropState clamped() {
    final z = zoom.clamp(1.0, maxZoom);
    final turn = straighten.clamp(-maxStraighten, maxStraighten);
    final base = _copy(zoom: z, straighten: turn);
    final reach =
        box / 2 * (math.cos(base.angle).abs() + math.sin(base.angle).abs());
    final s = base.scale;
    final maxX = math.max(0.0, imageW * s / 2 - reach);
    final maxY = math.max(0.0, imageH * s / 2 - reach);
    return base._copy(
      offset: Offset(
        offset.dx.clamp(-maxX, maxX),
        offset.dy.clamp(-maxY, maxY),
      ),
    );
  }

  /// The first view: the smallest size, the middle of the picture.
  CropState reset() =>
      _copy(quarterTurns: 0, straighten: 0, zoom: 1, offset: Offset.zero);

  /// Turns the picture a quarter turn ([direction] -1 left, 1 right) about the
  /// frame centre.
  CropState rotated(int direction) =>
      _copy(quarterTurns: (quarterTurns + direction) % 4).clamped();

  /// Sets the fine rotation. The picture point under the frame centre stays
  /// there, so the offset follows the scale change.
  CropState withStraighten(double radians) {
    final next = _copy(
      straighten: radians.clamp(-maxStraighten, maxStraighten),
    );
    final ratio = next.scale / scale;
    return next._copy(offset: offset * ratio).clamped();
  }

  /// Moves the picture by a finger drag of [delta] screen pixels.
  CropState panned(Offset delta) =>
      _copy(offset: offset + _turn(delta, -angle)).clamped();

  /// Zooms to [nextZoom] keeping the picture point under [focal] (relative to
  /// the frame centre) where it is, like a pinch.
  CropState zoomedAround(double nextZoom, [Offset focal = Offset.zero]) {
    final z = nextZoom.clamp(1.0, maxZoom);
    final next = _copy(zoom: z);
    final under = _turn(focal - center, -angle);
    final moved = under * (next.scale / scale);
    return next._copy(offset: _turn(focal, -angle) - moved).clamped();
  }

  /// The four corners of the frame in source pixels: exact for any angle.
  List<Offset> get sourceCorners {
    final half = box / 2;
    final middle = Offset(imageW / 2, imageH / 2) - offset / scale;
    return [
      for (final p in [
        Offset(-half, -half),
        Offset(half, -half),
        Offset(half, half),
        Offset(-half, half),
      ])
        middle + _turn(p, -angle) / scale,
    ];
  }

  /// The box around [sourceCorners]. For a picture turned a whole number of
  /// quarter turns it is exactly the part kept.
  Rect get sourceRect {
    final corners = sourceCorners;
    var left = corners.first.dx, right = left;
    var top = corners.first.dy, bottom = top;
    for (final c in corners) {
      left = math.min(left, c.dx);
      right = math.max(right, c.dx);
      top = math.min(top, c.dy);
      bottom = math.max(bottom, c.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// A new frame size (the screen turned or resized): the same view, scaled.
  CropState withBox(double next) {
    if (next == box) return this;
    final ratio = next / box;
    return CropState(
      imageW: imageW,
      imageH: imageH,
      box: next,
      quarterTurns: quarterTurns,
      straighten: straighten,
      zoom: zoom,
      offset: offset * ratio,
    ).clamped();
  }

  CropState _copy({
    int? quarterTurns,
    double? straighten,
    double? zoom,
    Offset? offset,
  }) => CropState(
    imageW: imageW,
    imageH: imageH,
    box: box,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    straighten: straighten ?? this.straighten,
    zoom: zoom ?? this.zoom,
    offset: offset ?? this.offset,
  );

  static Offset _turn(Offset v, double radians) {
    final c = math.cos(radians), s = math.sin(radians);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }
}
