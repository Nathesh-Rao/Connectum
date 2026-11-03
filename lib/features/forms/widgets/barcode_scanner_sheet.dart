import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../connect/widgets/viewfinder_overlay.dart';

/// Scans one barcode or QR code with the camera and hands back its text. The
/// code can always be typed instead.
class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  static Future<String?> show(BuildContext context, {required String title}) =>
      AppBottomSheet.show<String>(
        context,
        title: title,
        child: const BarcodeScannerSheet(),
      );

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  StreamSubscription<BarcodeCapture>? _detections;
  bool _isDone = false;
  bool _isReady = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _detections = _scanner.barcodes.listen(_onDetect);
    _scanner.addListener(_onValue);
  }

  void _onValue() {
    final value = _scanner.value;
    final error = value.error;
    if (!mounted) return;
    setState(() {
      _isReady = value.isRunning;
      _problem = error == null
          ? null
          : error.errorCode == MobileScannerErrorCode.permissionDenied
          ? 'Camera access is blocked. Allow it in Settings, or type the code.'
          : "The camera isn't available. Type the code instead.";
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isDone) return;
    for (final b in capture.barcodes) {
      final text = b.rawValue;
      if (text == null || text.isEmpty) continue;
      _isDone = true;
      Navigator.of(context).pop(text);
      return;
    }
  }

  @override
  void dispose() {
    _scanner.removeListener(_onValue);
    unawaited(_detections?.cancel());
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width - AppSpacing.md * 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: SizedBox(
        height: size.clamp(
          AppSpacing.scannerMinSize,
          AppSpacing.scannerMaxSize,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
          child: ColoredBox(
            color: AppColors.scrim,
            child: _problem != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        _problem!,
                        textAlign: TextAlign.center,
                        style: AppText.readable.copyWith(
                          color: AppColors.background,
                        ),
                      ),
                    ),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _scanner,
                        fit: BoxFit.cover,
                        placeholderBuilder: (_) => const SizedBox.shrink(),
                        errorBuilder: (_, _) => const SizedBox.shrink(),
                      ),
                      ViewfinderOverlay(isScanning: _isReady, isSuccess: false),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
