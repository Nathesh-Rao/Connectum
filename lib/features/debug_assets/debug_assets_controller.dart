import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

import '../../core/debug/attachment_tag_vectors.dart';
import '../../core/widgets/app_state_image.dart';

class PngInfo {
  const PngInfo(this.kind, this.kb, this.width, this.height);

  final AppStateImageKind kind;
  final int kb;
  final int width;
  final int height;
}

class LottieInfo {
  const LottieInfo({
    required this.asset,
    required this.kb,
    required this.composition,
    required this.layers,
  });

  final String asset;
  final int kb;
  final LottieComposition composition;
  final int layers;

  String get name => asset.split('/').last;
  bool get isOnboarding => name.startsWith('onboarding');
}

class DebugAssetsController extends GetxController {
  static const lottieAssets = [
    'assets/lottie/onboarding_network_blue.json',
    'assets/lottie/onboarding_enterprises_blue.json',
    'assets/lottie/onboarding_security_blue.json',
    'assets/lottie/state_success_blue.json',
  ];

  final pngs = <PngInfo>[].obs;
  final lotties = <LottieInfo>[].obs;
  final reduced = <String>{}.obs;
  final measures = <String, String>{}.obs;
  final seams = <String, String>{}.obs;
  final tagResults = AttachmentTagVectors.run();

  /// The file being measured; everything else is hidden and stopped so the
  /// numbers are that animation's own.
  final measuring = RxnString();
  final firstFrames = <String, String>{}.obs;

  /// `--dart-define=ASSET_AUTORUN=1` runs every seam check and measurement in turn.
  static const isAutorun = String.fromEnvironment('ASSET_AUTORUN') == '1';
  Future<void> queue = Future.value();

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final images = <PngInfo>[];
    for (final kind in AppStateImageKind.values) {
      final data = await rootBundle.load(kind.asset);
      final image = await _decode(data);
      images.add(
        PngInfo(kind, data.lengthInBytes ~/ 1024, image.width, image.height),
      );
      image.dispose();
    }
    pngs.assignAll(images);
    final files = <LottieInfo>[];
    for (final asset in lottieAssets) {
      final data = await rootBundle.load(asset);
      final json = jsonDecode(utf8.decode(data.buffer.asUint8List())) as Map;
      files.add(
        LottieInfo(
          asset: asset,
          kb: data.lengthInBytes ~/ 1024,
          composition: await AssetLottie(asset).load(),
          layers: (json['layers'] as List).length,
        ),
      );
    }
    lotties.assignAll(files);
  }

  Future<ui.Image> _decode(ByteData data) async {
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  void toggleReduced(String name, bool value) =>
      value ? reduced.add(name) : reduced.remove(name);
}
