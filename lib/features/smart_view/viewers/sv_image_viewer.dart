import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_sv.dart';
import '../../../core/theme/app_text.dart';
import '../sv_file_preview_controller.dart';

/// A picture the first bytes confirmed: pinch to zoom, double-tap toggles.
/// While zoomed the swipe between files is off.
class SvImageViewer extends StatefulWidget {
  const SvImageViewer({super.key, required this.file, required this.load});

  final File file;
  final SvFileLoad load;

  @override
  State<SvImageViewer> createState() => _SvImageViewerState();
}

class _SvImageViewerState extends State<SvImageViewer> {
  final _transform = TransformationController();
  Offset _tap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_sync);
  }

  void _sync() {
    widget.load.isZoomed.value = _transform.value.getMaxScaleOnAxis() > 1.01;
  }

  @override
  void dispose() {
    _transform.removeListener(_sync);
    widget.load.isZoomed.value = false;
    _transform.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_transform.value.getMaxScaleOnAxis() > 1.01) {
      _transform.value = Matrix4.identity();
      return;
    }
    const z = AppSv.fileDoubleTapZoom;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-_tap.dx * (z - 1), -_tap.dy * (z - 1), 0, 1)
      ..scaleByDouble(z, z, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (d) => _tap = d.localPosition,
      onDoubleTap: _toggle,
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: AppSv.fileZoomMax,
        child: Center(
          child: Image.file(
            widget.file,
            key: const ValueKey('sv-file-image'),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Text(
              "This picture can't be shown.",
              style: AppText.supporting,
            ),
          ),
        ),
      ),
    );
  }
}
