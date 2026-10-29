import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_animation_placeholder.dart';

/// Every state picture, with its file and display scale. The only place that
/// maps a state to a file.
enum AppStateImageKind {
  emptyChats('empty_chats'),
  emptyEnterprises('empty_enterprises'),
  emptyGeneric('empty_generic'),
  noResults('no_results'),
  offline('offline'),
  error('error'),
  locked('locked', scale: 0.85),
  comingSoon('coming_soon'),
  aiWelcome('ai_welcome');

  const AppStateImageKind(this.file, {this.scale = 1});

  final String file;

  /// Some pictures fill their canvas edge to edge and look bigger than the
  /// rest at the same width.
  final double scale;

  String get asset => 'assets/images/states/$file.png';
}

class AppStateImage extends StatefulWidget {
  const AppStateImage({
    super.key,
    required this.kind,
    this.size = AppSpacing.stateImage,
    this.isAnimated = true,
  });

  final AppStateImageKind kind;
  final double size;
  final bool isAnimated;

  static ImageProvider _provider(
    AppStateImageKind kind,
    double size,
    double pixelRatio,
  ) => ResizeImage(
    AssetImage(kind.asset),
    width: (size * kind.scale * pixelRatio).round(),
  );

  /// Decodes the pictures a screen may show before they are needed.
  static void precache(
    BuildContext context,
    List<AppStateImageKind> kinds, {
    double size = AppSpacing.stateImage,
  }) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    for (final kind in kinds) {
      precacheImage(_provider(kind, size, ratio), context, onError: (_, _) {});
    }
  }

  @override
  State<AppStateImage> createState() => _AppStateImageState();
}

class _AppStateImageState extends State<AppStateImage>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: AppDurations.slow,
  );
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: AppDurations.stateFloat,
  );
  late final Animation<double> _introCurve = CurvedAnimation(
    parent: _intro,
    curve: AppCurves.out,
  );
  late final Animation<double> _floatCurve = CurvedAnimation(
    parent: _float,
    curve: Curves.easeInOut,
  );
  bool? _isStatic;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isStatic =
        !widget.isAnimated || MediaQuery.disableAnimationsOf(context);
    if (isStatic == _isStatic) return;
    _isStatic = isStatic;
    if (isStatic) {
      _float.stop();
      _intro.value = 1;
    } else {
      _intro.forward().whenCompleteOrCancel(() {
        if (mounted && _isStatic == false) _float.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final size = widget.size;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_introCurve, _floatCurve]),
          builder: (context, child) {
            final intro = _introCurve.value;
            final lift = -AppDistances.stateFloat * _floatCurve.value;
            return Opacity(
              opacity: intro,
              child: Transform.translate(
                offset: Offset(0, lift),
                child: Transform.scale(
                  scale:
                      AppDistances.stateIntroScale +
                      (1 - AppDistances.stateIntroScale) * intro,
                  child: child,
                ),
              ),
            );
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Image(
                image: AppStateImage._provider(kind, size, ratio),
                width: size * kind.scale,
                height: size * kind.scale,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stack) =>
                    AppAnimationPlaceholder(
                      name: kind.file.replaceAll('_', '-'),
                      width: size,
                      height: size * 0.75,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
