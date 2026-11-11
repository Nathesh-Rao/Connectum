import 'package:flutter/widgets.dart';

/// The Connectum mark at a fixed width (aspect 187:194). It has a definite
/// height so that intrinsic-height layouts measure it correctly.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.width});

  static const _aspect = 194 / 187;

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * _aspect,
      child: Image.asset(
        'assets/images/connectum_logo.png',
        // 'assets/images/Connectum-C.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
