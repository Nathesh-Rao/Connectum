import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import 'crop_math.dart';
import 'photo_renderer.dart';

/// The crop screen's state: the picture, the frame size and the view the
/// person has set. The maths is in [CropState]; this only feeds it gestures.
class ProfilePhotoCropController extends GetxController {
  ProfilePhotoCropController({required this.bytes, this.isDebug = false});

  /// The picture chosen, as the file bytes.
  final Uint8List bytes;

  /// Shows the numbers under the controls (the debug page).
  final bool isDebug;

  final photo = Rxn<DecodedPhoto>();
  final crop = Rxn<CropState>();
  final isLoading = true.obs;
  final hasLoadFailed = false.obs;
  final isRendering = false.obs;

  /// True while a finger is on the picture: the thirds grid shows.
  final isMoving = false.obs;

  double _box = 0;
  double _startZoom = 1;
  Offset _lastFocal = Offset.zero;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    photo.value?.image.dispose();
    super.onClose();
  }

  Future<void> load() async {
    isLoading.value = true;
    hasLoadFailed.value = false;
    try {
      photo.value = await PhotoRenderer.decode(
        bytes,
        PhotoRenderer.previewSide,
      );
      _start();
    } catch (_) {
      hasLoadFailed.value = true;
    } finally {
      isLoading.value = false;
    }
  }

  /// The view reports the frame's side once it is laid out (and again when it
  /// changes).
  void setBox(double side) {
    if (side <= 0 || side == _box) return;
    _box = side;
    final current = crop.value;
    if (current != null) {
      crop.value = current.withBox(side);
    } else {
      _start();
    }
  }

  void _start() {
    final p = photo.value;
    if (p == null || _box <= 0) return;
    crop.value = CropState(
      imageW: p.sourceW.toDouble(),
      imageH: p.sourceH.toDouble(),
      box: _box,
    );
  }

  bool get canReset => !(crop.value?.isUntouched ?? true);

  void onScaleStart(ScaleStartDetails d) {
    final c = crop.value;
    if (c == null) return;
    _startZoom = c.zoom;
    _lastFocal = d.localFocalPoint;
    isMoving.value = true;
  }

  void onScaleUpdate(ScaleUpdateDetails d) {
    final c = crop.value;
    if (c == null) return;
    final middle = Offset(_box / 2, _box / 2);
    final next = c.zoomedAround(
      _startZoom * d.scale,
      d.localFocalPoint - middle,
    );
    crop.value = next.panned(d.localFocalPoint - _lastFocal);
    _lastFocal = d.localFocalPoint;
  }

  void onScaleEnd(ScaleEndDetails d) => isMoving.value = false;

  void rotate(int direction) {
    final c = crop.value;
    if (c != null) crop.value = c.rotated(direction);
  }

  void setStraighten(double degrees) {
    final c = crop.value;
    if (c != null) crop.value = c.withStraighten(degrees * math.pi / 180);
  }

  double get straightenDegrees => (crop.value?.straighten ?? 0) * 180 / math.pi;

  /// The zoom slider's value, 0 to 1.
  double get zoomSlider =>
      ((crop.value?.zoom ?? 1) - 1) / (CropState.maxZoom - 1);

  void setZoomSlider(double t) {
    final c = crop.value;
    if (c != null) crop.value = c.zoomedAround(1 + t * (CropState.maxZoom - 1));
  }

  void nudgeZoom(double direction) =>
      setZoomSlider((zoomSlider + direction * 0.12).clamp(0.0, 1.0));

  void reset() {
    final c = crop.value;
    if (c != null) crop.value = c.reset();
  }

  void cancel() {
    if (!isRendering.value) Get.back<Uint8List>();
  }

  /// Cuts the part under the frame out of the full-size picture and hands the
  /// PNG back to whoever opened the screen.
  Future<void> done() async {
    final c = crop.value;
    if (c == null || isRendering.value) return;
    isRendering.value = true;
    ui.Image? full;
    try {
      final decoded = await PhotoRenderer.decode(
        bytes,
        PhotoRenderer.sourceSide,
      );
      full = decoded.image;
      final out = await PhotoRenderer.render(full, c);
      Get.back<Uint8List>(result: out);
    } catch (_) {
      AppNotices.show(
        "This photo couldn't be prepared. Try another one.",
        variant: AppNoticeVariant.error,
      );
    } finally {
      full?.dispose();
      isRendering.value = false;
    }
  }
}
