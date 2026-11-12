import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_success_animation.dart';
import 'debug_assets_controller.dart';

/// One Lottie file in the debug gallery: info, controls, a 5 s measurement
/// from the end of `entry` into the start of `idle`, and a loop-seam check.
class LottieTile extends StatefulWidget {
  const LottieTile({super.key, required this.info, required this.controller});

  final LottieInfo info;
  final DebugAssetsController controller;

  @override
  State<LottieTile> createState() => _LottieTileState();
}

class _LottieTileState extends State<LottieTile>
    with SingleTickerProviderStateMixin {
  static const _previewWidth = 300.0;
  static const _measureSeconds = 5;
  static const _leadSeconds = 2.5;

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: composition.duration,
  );
  final _fresh = ValueNotifier<LottieComposition?>(null);

  LottieInfo get info => widget.info;
  DebugAssetsController get c => widget.controller;
  LottieComposition get composition => info.composition;

  double get _idleStart => composition.getMarker('idle')?.start ?? 0;
  double get _idleEnd => composition.getMarker('idle')?.end ?? 1;
  double get _still =>
      composition.getMarker('static')?.start ??
      AppSuccessAnimation.holdFrame / composition.durationFrames;
  double get _secondsPerProgress =>
      composition.durationFrames / composition.frameRate;

  Duration _seconds(double progress) =>
      Duration(microseconds: (progress * _secondsPerProgress * 1e6).round());

  @override
  void initState() {
    super.initState();
    if (DebugAssetsController.isAutorun) {
      c.queue = c.queue.then((_) async {
        if (!mounted) return;
        await Scrollable.ensureVisible(context);
        if (info.isOnboarding) {
          await _measureColdSteady();
        } else {
          await _measure();
        }
      });
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _fresh.dispose();
    super.dispose();
  }

  void _play(double from) {
    _animation.stop();
    _animation.value = from;
    if (!info.isOnboarding) {
      _animation.forward(from: from);
    } else if (from < _idleStart) {
      _animation
          .animateTo(
            _idleStart,
            duration: _seconds(_idleStart - from),
            curve: Curves.linear,
          )
          .then((_) => _loopIdle());
    } else {
      _loopIdle();
    }
  }

  void _loopIdle() => _animation.repeat(
    min: _idleStart,
    max: _idleEnd,
    period: _seconds(_idleEnd - _idleStart),
  );

  Future<void> _measure() async {
    final name = info.name;
    c.measures[name] = 'Measuring...';
    c.measuring.value = name;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Scrollable.ensureVisible(context);
    final sw = Stopwatch()..start();
    final data = await rootBundle.load(info.asset);
    final fresh = await LottieComposition.fromByteData(data);
    final parseMs = sw.elapsedMilliseconds;
    final first = <FrameTiming>[];
    void onFirst(List<FrameTiming> t) => first.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(onFirst);
    _fresh.value = fresh;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.firstFrames[name] =
          'parse $parseMs ms + first frame build/paint '
          '${sw.elapsedMilliseconds - parseMs} ms';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    SchedulerBinding.instance.removeTimingsCallback(onFirst);
    final firstRaster = first.isEmpty
        ? '?'
        : (first.first.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1);
    c.firstFrames[name] = '${c.firstFrames[name]}, raster ~$firstRaster ms';
    _fresh.value = null;

    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    if (info.isOnboarding) {
      final lead = _leadSeconds / _secondsPerProgress;
      _play(math.max(0, _idleStart - lead));
    } else {
      _animation.repeat(period: composition.duration);
    }
    await Future<void>.delayed(const Duration(seconds: _measureSeconds));
    _animation.stop();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    c.measuring.value = null;
    c.measures[name] = _summarise(timings);
    debugPrint(
      'ASSET $name | ${c.firstFrames[name]} | ${c.measures[name]!.replaceAll('\n', ' | ')}',
    );
  }

  Future<void> _measureColdSteady() async {
    final name = info.name;
    c.measuring.value = name;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Scrollable.ensureVisible(context);
    final timings = <FrameTiming>[];
    void onTimings(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    _animation.stop();
    _animation.value = 0;
    _play(0);
    await Future<void>.delayed(const Duration(seconds: 15, milliseconds: 500));
    _animation.stop();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    c.measuring.value = null;
    if (timings.isEmpty) return;
    final origin = timings.first.timestampInMicroseconds(
      ui.FramePhase.buildStart,
    );
    List<FrameTiming> window(double from, double to) => [
      for (final t in timings)
        if ((t.timestampInMicroseconds(ui.FramePhase.buildStart) - origin) /
                    1e6 >=
                from &&
            (t.timestampInMicroseconds(ui.FramePhase.buildStart) - origin) /
                    1e6 <
                to)
          t,
    ];
    final cold = _windowStats(window(0, 2), 2);
    final steady = _windowStats(window(10, 15), 5);
    c.measures[name] = 'cold: $cold\nsteady: $steady';
    debugPrint('ASSET $name | cold: $cold | steady: $steady');
  }

  String _windowStats(List<FrameTiming> t, double seconds) {
    if (t.isEmpty) return 'no frames';
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final x in t) ms(x.buildDuration)];
    final raster = [for (final x in t) ms(x.rasterDuration)];
    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    double worst(List<double> v) => v.reduce(math.max);
    final over = t.where((x) => ms(x.totalSpan) > 40).length;
    return '${t.length} frames (${(t.length / seconds).toStringAsFixed(1)}/s), '
        'build ${avg(build).toStringAsFixed(1)}/${worst(build).toStringAsFixed(1)}, '
        'raster ${avg(raster).toStringAsFixed(1)}/${worst(raster).toStringAsFixed(1)}, '
        'sum ${(avg(build) + avg(raster)).toStringAsFixed(1)}, >40ms $over';
  }

  String _summarise(List<FrameTiming> timings) {
    if (timings.isEmpty) return 'No frames recorded';
    final refresh = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate;
    final budget = 1000 / refresh;
    double ms(Duration d) => d.inMicroseconds / 1000;
    final build = [for (final t in timings) ms(t.buildDuration)];
    final raster = [for (final t in timings) ms(t.rasterDuration)];
    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    double worst(List<double> v) => v.reduce(math.max);
    int over(List<double> v) => v.where((x) => x > budget).length;
    return '${timings.length} frames at ${refresh.toStringAsFixed(0)} Hz '
        '(budget ${budget.toStringAsFixed(1)} ms)\n'
        'build avg ${avg(build).toStringAsFixed(2)} / worst '
        '${worst(build).toStringAsFixed(1)} ms, over budget ${over(build)}\n'
        'raster avg ${avg(raster).toStringAsFixed(2)} / worst '
        '${worst(raster).toStringAsFixed(1)} ms, over budget ${over(raster)}';
  }

  Future<ByteData?> _render(double progress, int width, int height) async {
    final drawable = LottieDrawable(composition)..setProgress(progress);
    final recorder = ui.PictureRecorder();
    drawable.draw(
      Canvas(recorder),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      fit: BoxFit.contain,
    );
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData();
    image.dispose();
    return bytes;
  }

  String _diff(ByteData a, ByteData b) {
    var total = 0;
    var changed = 0;
    final length = a.lengthInBytes ~/ 4;
    for (var i = 0; i < length; i++) {
      var pixel = 0;
      for (var k = 0; k < 4; k++) {
        final d = (a.getUint8(i * 4 + k) - b.getUint8(i * 4 + k)).abs();
        total += d;
        pixel = math.max(pixel, d);
      }
      if (pixel > 8) changed++;
    }
    return 'mean ${(total / (length * 4)).toStringAsFixed(3)}/255, '
        '${(changed * 100 / length).toStringAsFixed(2)}% pixels differ';
  }

  Future<void> _checkSeam() async {
    final name = info.name;
    c.seams[name] = 'Rendering...';
    final w = composition.bounds.width * 2;
    final h = composition.bounds.height * 2;
    final step = 1 / composition.durationFrames;
    final start = await _render(_idleStart, w, h);
    final end = await _render(_idleEnd, w, h);
    final beforeEnd = await _render(_idleEnd - step, w, h);
    final afterStart = await _render(_idleStart + step, w, h);
    c.seams[name] =
        'idle ${(_idleStart * composition.durationFrames).round()} -> '
        '${(_idleEnd * composition.durationFrames).round()}\n'
        'seam (last vs first): ${_diff(end!, start!)}\n'
        'one frame before end vs first: ${_diff(beforeEnd!, start)}\n'
        'baseline, first vs next frame: ${_diff(afterStart!, start)}';
    debugPrint('ASSET $name seam | ${c.seams[name]!.replaceAll('\n', ' | ')}');
  }

  List<(String, double)> get _candidates {
    final frames = composition.durationFrames;
    double at(double frame) => frame / frames;
    return [
      ('static', _still),
      ('first', 0),
      ('idle start', _idleStart),
      ('idle 25%', _idleStart + (_idleEnd - _idleStart) * 0.25),
      ('idle 50%', _idleStart + (_idleEnd - _idleStart) * 0.5),
      ('idle 75%', _idleStart + (_idleEnd - _idleStart) * 0.75),
      ('mid', at(frames / 2)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final name = info.name;
    return Obx(() {
      final measuring = c.measuring.value;
      return Offstage(
        offstage: measuring != null && measuring != name,
        child: TickerMode(
          enabled: measuring == null || measuring == name,
          child: _body(name, isMeasuring: measuring == name),
        ),
      );
    });
  }

  Widget _body(String name, {required bool isMeasuring}) {
    final b = composition.bounds;
    final height = _previewWidth * b.height / b.width;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: AppText.subtitle),
          Text(
            '${info.kb} KB - ${composition.frameRate.toStringAsFixed(0)} fps - '
            '${composition.seconds.toStringAsFixed(1)} s - '
            '${b.width}x${b.height} - ${info.layers} layers',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Container(
              width: _previewWidth,
              height: height,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                color: AppColors.fill,
              ),
              child: Lottie(
                composition: composition,
                controller: c.reduced.contains(name)
                    ? AlwaysStoppedAnimation(_still)
                    : _animation,
                frameRate: FrameRate.composition,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _button('Play', () => _play(_animation.value)),
              _button('Pause', _animation.stop),
              _button('Restart', () => _play(0)),
              _button('Measure 5 s', _measure),
              if (info.isOnboarding) _button('Cold+steady', _measureColdSteady),
              if (info.isOnboarding) _button('Seam', _checkSeam),
            ],
          ),
          Obx(
            () => SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Reduced motion preview',
                style: AppText.caption,
              ),
              value: c.reduced.contains(name),
              onChanged: (v) => c.toggleReduced(name, v),
            ),
          ),
          Obx(() => _line(c.firstFrames[name])),
          Obx(() => _line(c.measures[name])),
          Obx(() => _line(c.seams[name])),
          if (info.isOnboarding && !isMeasuring) ...[
            const SizedBox(height: AppSpacing.xs),
            const Text('Still candidates', style: AppText.caption),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (label, progress) in _candidates)
                  SizedBox(
                    width: 100,
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: b.width / b.height,
                          child: Lottie(
                            composition: composition,
                            controller: AlwaysStoppedAnimation(progress),
                            frameRate: FrameRate.composition,
                          ),
                        ),
                        Text(
                          '$label (${(progress * composition.durationFrames).round()})',
                          style: AppText.caption,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          ValueListenableBuilder<LottieComposition?>(
            valueListenable: _fresh,
            builder: (context, fresh, _) => fresh == null
                ? const SizedBox.shrink()
                : SizedBox(
                    width: 1,
                    height: 1,
                    child: Lottie(composition: fresh),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _line(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(text, style: AppText.caption),
        );

  Widget _button(String label, VoidCallback onPressed) => SizedBox(
    width: 120,
    child: AppButton.secondary(label: label, onPressed: onPressed),
  );
}
