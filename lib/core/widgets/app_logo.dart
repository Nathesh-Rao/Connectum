import 'package:flutter/widgets.dart';

/// The Connectum mark at a fixed width (aspect 1408:1464). It has a definite
/// height so that intrinsic-height layouts measure it correctly.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.width});

  static const _aspect = 1464 / 1408;

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * _aspect,
      child: Image.asset(
        'assets/images/connectum_logo_blue.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
