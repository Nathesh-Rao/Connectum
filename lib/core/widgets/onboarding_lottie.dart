import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import 'app_animation_placeholder.dart';

/// The three baked onboarding files. Ranges come from the file's own markers
/// (`entry`, `idle`, `static`); the frames here are the documented fallback
/// when a marker is missing.
///
/// Playback settings per file. Measured on a moto g32 in profile mode
/// (Impeller/Vulkan) with the real onboarding screen as the deciding test:
/// a 150 ms start delay, 24 and 20 fps, filterQuality low/none, merge paths,
/// warming the next slide and the `RenderCache` modes all left the presented
/// rate at the same ~40-45 fps with the same count of frames over 40 ms, so
/// every file keeps the defaults. `drawingCommands` cut the enterprises tile's
/// per-frame cost most (about 66 to 24 ms) but held ~65 MB more native memory
/// on the real screen, over the 30 MB limit. The idle bodies are too long for
/// `raster` (50 MB cap, no gain, +13 MB native).
enum OnboardingLottieFile {
  network(
    'onboarding_network',
    'onboarding-conversations',
    792,
    197,
    594,
    startDelay: Duration.zero,
    frameRate: FrameRate.composition,
    filterQuality: null,
    renderCache: null,
  ),
  enterprises(
    'onboarding_enterprises',
    'onboarding-enterprises',
    2264,
    103,
    2160,
    startDelay: Duration.zero,
    frameRate: FrameRate.composition,
    filterQuality: null,
    renderCache: null,
  ),
  security(
    'onboarding_security',
    'onboarding-security',
    3010,
    129,
    2880,
    startDelay: Duration.zero,
    frameRate: FrameRate.composition,
    filterQuality: null,
    renderCache: null,
  );

  const OnboardingLottieFile(
    this.name,
    this.placeholder,
    this.stillFrame,
    this.entryFrames,
    this.idleFrames, {
    required this.startDelay,
    required this.frameRate,
    required this.filterQuality,
    required this.renderCache,
  });

  final String name;
  final String placeholder;
  final double stillFrame;
  final double entryFrames;
  final double idleFrames;
  final Duration startDelay;
  final FrameRate frameRate;
  final FilterQuality? filterQuality;
  final RenderCache? renderCache;

  String get asset => 'assets/lottie/$name.json';
}

/// Plays `entry` once, then loops `idle`, from frame 0 each time the slide
/// becomes active; stops when it leaves and while the app is in the
/// background. Reduced motion shows the `static` frame and runs nothing.
class OnboardingLottie extends StatefulWidget {
  const OnboardingLottie({
    super.key,
    required this.file,
    required this.isActive,
  });

  final OnboardingLottieFile file;
  final bool isActive;

  static final _compositions = <String, Future<LottieComposition>>{};

  /// Parsed once per file for the life of the app.
  static Future<LottieComposition> load(OnboardingLottieFile file) =>
      _compositions.putIfAbsent(
        file.asset,
        () => AssetLottie(file.asset).load(),
      );

  @override
  State<OnboardingLottie> createState() => _OnboardingLottieState();
}

class _OnboardingLottieState extends State<OnboardingLottie>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(vsync: this);
  final _loaded = ValueNotifier<LottieComposition?>(null);
  final _hasFailed = ValueNotifier<bool>(false);

  Timer? _startTimer;
  bool _isForeground = true;
  bool _isReduced = false;
  late double _idleStart;
  late double _idleEnd;
  late double _still;
  late Duration _idlePeriod;
  late double _secondsPerProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OnboardingLottie.load(widget.file).then(
      _onLoaded,
      onError: (Object _) {
        if (mounted) _hasFailed.value = true;
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isReduced = MediaQuery.disableAnimationsOf(context);
    if (isReduced == _isReduced) return;
    _isReduced = isReduced;
    if (_loaded.value != null) _restart();
  }

  @override
  void didUpdateWidget(OnboardingLottie old) {
    super.didUpdateWidget(old);
    if (old.isActive != widget.isActive && _loaded.value != null) _restart();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    _startTimer?.cancel();
    if (_loaded.value == null || _isReduced) return;
    if (_isForeground) {
      _run();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _loaded.dispose();
    _hasFailed.dispose();
    super.dispose();
  }

  void _onLoaded(LottieComposition c) {
    if (!mounted) return;
    final file = widget.file;
    final frames = c.durationFrames;
    double progressOf(double frame) => (frame - c.startFrame) / frames;
    final idle = c.getMarker('idle');
    final still = c.getMarker('static');
    _idleStart = idle?.start ?? progressOf(file.entryFrames);
    _idleEnd = idle?.end ?? progressOf(file.entryFrames + file.idleFrames);
    _still = still?.start ?? progressOf(file.stillFrame);
    _secondsPerProgress = frames / c.frameRate;
    _idlePeriod = _seconds(_idleEnd - _idleStart);
    _controller.duration = c.duration;
    _loaded.value = c;
    _restart();
  }

  Duration _seconds(double progress) =>
      Duration(microseconds: (progress * _secondsPerProgress * 1e6).round());

  void _restart() {
    _controller.stop();
    if (_isReduced) {
      _controller.value = _still;
      return;
    }
    _controller.value = 0;
    _startTimer?.cancel();
    if (!widget.isActive) return;
    final delay = widget.file.startDelay;
    if (delay > Duration.zero) {
      _startTimer = Timer(delay, _run);
    } else {
      _run();
    }
  }

  void _run() {
    if (_isReduced || !widget.isActive || !_isForeground) return;
    if (_controller.value < _idleStart) {
      _controller
          .animateTo(
            _idleStart,
            duration: _seconds(_idleStart - _controller.value),
            curve: Curves.linear,
          )
          .then((_) => _loop());
    } else {
      _loop();
    }
  }

  void _loop() {
    if (!mounted || !widget.isActive || !_isForeground) return;
    _controller.repeat(min: _idleStart, max: _idleEnd, period: _idlePeriod);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: _hasFailed,
        builder: (context, hasFailed, _) {
          if (hasFailed) {
            return AppAnimationPlaceholder(
              name: widget.file.placeholder,
              width: double.infinity,
              height: double.infinity,
            );
          }
          return ValueListenableBuilder<LottieComposition?>(
            valueListenable: _loaded,
            builder: (context, composition, _) => composition == null
                ? const SizedBox.expand()
                : Lottie(
                    composition: composition,
                    controller: _controller,
                    frameRate: widget.file.frameRate,
                    filterQuality: widget.file.filterQuality,
                    renderCache: widget.file.renderCache,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                  ),
          );
        },
      ),
    );
  }
}
