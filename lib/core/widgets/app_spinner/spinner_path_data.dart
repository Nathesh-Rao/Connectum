/// One animated path of the spinner SVG: its `d`, the rotation pivot, the
/// direction (1 clockwise, -1 counter-clockwise) and seconds per full turn.
class SpinnerPathData {
  const SpinnerPathData({
    required this.d,
    required this.pivotX,
    required this.pivotY,
    required this.direction,
    required this.durationSeconds,
  });

  final String d;
  final double pivotX;
  final double pivotY;
  final int direction;
  final double durationSeconds;
}
