import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Draws a widget that is not on screen to a PNG: its own render and build
/// trees, so it needs no BuildContext and does not depend on the screen.
class WidgetImage {
  WidgetImage._();

  static const _maxHeight = 4000.0;

  /// [widget] gets [width] logical pixels and its own height; the image is
  /// [width] x [pixelRatio] pixels wide.
  static Future<Uint8List> png(
    Widget widget, {
    required double width,
    required double pixelRatio,
  }) async {
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(Size(width, _maxHeight)),
      ),
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    final buildOwner = BuildOwner(focusManager: FocusManager());
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, _maxHeight)),
          child: widget,
        ),
      ),
    ).attachToRenderTree(buildOwner);
    try {
      buildOwner.buildScope(element);
      buildOwner.finalizeTree();
      pipelineOwner
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('no image data');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      renderView.dispose();
    }
  }
}
