import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'buildings_switching_art.dart';
import 'generated/content_bounds_data.dart';
import 'network_tiers.dart';
import 'onboarding_art_speed.dart';
import 'network_icons_art.dart';
import 'onboarding_art_palette.dart';
import 'shield_security_art.dart';
import 'svg_scene.dart';

/// Which part of the artwork is shown: the measured content (full width, no
/// empty margin) or the original viewBox of the HTML.
enum OnboardingArtWindow { crop, original }

/// The three authored onboarding animations.
enum OnboardingArtKind {
  network,
  buildings,
  shield;

  /// How fast this animation plays, as a multiple of the HTML (see
  /// onboarding_art_speed.dart).
  double get speed => switch (this) {
    network => kNetworkSpeed,
    buildings => kBuildingsSpeed,
    shield => kShieldSpeed,
  };

  /// Margin around the measured content, as a share of its width.
  static const cropMargin = 0.02;

  /// Union of every drawn element over the whole timeline (measured by
  /// tool/onboarding_anim/measure_bounds_test.dart), inside the viewBox.
  Rect get contentBounds => switch (this) {
    network => networkContentBounds,
    buildings => buildingsContentBounds,
    shield => shieldContentBounds,
  };

  /// The crop window: the content plus the margin, never beyond the viewBox
  /// (the HTML clips there, so nothing is lost and nothing new appears).
  ///
  /// [symmetric] is the network's mirror-symmetric layout: its bounds are
  /// symmetric about the axis (and about the steady picture's vertical
  /// centre), so the window is too.
  Rect cropWindow(Rect viewBox, {bool symmetric = false}) {
    final b = symmetric && this == network ? networkSymContentBounds : contentBounds;
    return b.inflate(b.width * cropMargin).intersect(viewBox);
  }

  /// The network's symmetric layout with an edited list of ids (tests).
  ArtScene bindWith(SvgScene scene, List<String> visible) =>
      NetworkIcons.bindSymmetric(scene, visible: visible);

  SvgScene build(Color Function(Color) remap) => switch (this) {
    network => NetworkIcons.build(remap),
    buildings => BuildingsSwitching.build(remap),
    shield => ShieldSecurity.build(remap),
  };

  /// [tier2] and [symmetric] only matter for the network: tier2 false shows
  /// tier 1 alone (lab); [symmetric] is the mirror-symmetric layout. The
  /// default is the old layout (the widget passes its own switch).
  ArtScene bind(SvgScene scene, {bool tier2 = true, bool symmetric = false}) =>
      switch (this) {
    network => symmetric
        ? NetworkIcons.bindSymmetric(
            scene,
            visible: tier2 ? kNetworkSymVisiblePersons : kNetworkSymTier1Persons,
          )
        : NetworkIcons.bind(
            scene,
            visible: tier2 ? kNetworkVisiblePersons : kNetworkTier1Persons,
          ),
    buildings => BuildingsSwitching.bind(scene),
    shield => ShieldSecurity.bind(scene),
  };
}

/// Drives an [OnboardingArt]: play (restart the intro), pause, resume, seek
/// and speed. The time is one number in seconds that the painter reads, and
/// [advance] is the one place that turns real elapsed time into it:
/// `t = base + (elapsed - baseElapsed) * speed`.
class OnboardingArtController extends ChangeNotifier {
  final time = ValueNotifier<double>(0);
  bool _isPlaying = true;
  double? _override;
  double duration = 1;

  /// The art's own speed (its constant), set by the widget. A controller that
  /// is not attached to a widget plays at 1x.
  double baseSpeed = 1;

  /// Bumped whenever the time is moved or the speed changes, so the running
  /// clock re-bases instead of jumping.
  int epoch = 0;

  // the running clock
  double _baseT = 0;
  Duration _baseElapsed = Duration.zero;
  int _clockEpoch = -1;

  bool get isPlaying => _isPlaying;

  /// The speed in use: the override if one was set, else the art's constant.
  double get speed => _override ?? baseSpeed;

  bool get isDefaultSpeed => _override == null;

  /// Sets an absolute multiple of the HTML speed (lab selector).
  set speed(double v) {
    _override = v;
    epoch++;
    notifyListeners();
  }

  /// Back to the art's own constant.
  void useDefaultSpeed() {
    _override = null;
    epoch++;
    notifyListeners();
  }

  /// A ticker start: the next [advance] takes its base from the current time.
  void restartClock() => _clockEpoch = -1;

  /// Sets the time for a ticker callback at [elapsed] and returns it. Real
  /// elapsed seconds times the speed: a dropped frame skips ahead.
  double advance(Duration elapsed) {
    if (_clockEpoch != epoch) {
      _clockEpoch = epoch;
      _baseT = time.value;
      _baseElapsed = elapsed;
    }
    final seconds = (elapsed - _baseElapsed).inMicroseconds / 1e6;
    return time.value = _baseT + seconds * speed;
  }

  /// Restarts the intro from t = 0 and plays.
  void play() {
    time.value = 0;
    epoch++;
    _isPlaying = true;
    notifyListeners();
  }

  void pause() {
    _isPlaying = false;
    notifyListeners();
  }

  void resume() {
    epoch++;
    _isPlaying = true;
    notifyListeners();
  }

  /// Shows the frame at [t] seconds and pauses.
  void seek(double t) {
    time.value = t < 0 ? 0 : t;
    epoch++;
    _isPlaying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    time.dispose();
    super.dispose();
  }
}

/// A pure function of `t`: the scene is updated to the time, then drawn.
class OnboardingArtPainter extends CustomPainter {
  OnboardingArtPainter({
    required this.scene,
    required this.art,
    required this.renderer,
    required this.time,
    required this.window,
  }) : super(repaint: time);

  final SvgScene scene;
  final ArtScene art;
  final SvgRenderer renderer;
  final ValueListenable<double> time;

  /// The scene rectangle that fills the paint box.
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final vb = window;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / vb.width, size.height / vb.height);
    canvas.translate(-vb.left, -vb.top);
    art.render(time.value);
    renderer.paint(canvas);
    final axis = art.mirrorAxis;
    if (axis != null) {
      // the same half again, flipped about the axis, without the hub
      art.setMirrored?.call(true);
      canvas.translate(2 * axis, 0);
      canvas.scale(-1, 1);
      renderer.paint(canvas);
      art.setMirrored?.call(false);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OnboardingArtPainter old) =>
      old.scene != scene || old.time != time || old.window != window;
}

/// One onboarding animation on a transparent background, scaled to fit the
/// slot. It runs one ticker, only while [isActive], the app is resumed, the
/// route is the current one and motion is allowed.
class OnboardingArt extends StatefulWidget {
  const OnboardingArt({
    super.key,
    required this.kind,
    this.controller,
    this.autoplay = true,
    this.loop = true,
    this.reducedMotion,
    this.isActive = true,
    this.blueOnly = false,
    this.window = OnboardingArtWindow.crop,
    this.networkTier2 = true,
    this.networkSymmetric = kNetworkSymmetricDefault,
  });

  final OnboardingArtKind kind;
  final OnboardingArtController? controller;
  final bool autoplay;
  final bool loop;

  /// Overrides the platform setting when not null.
  final bool? reducedMotion;
  final bool isActive;

  /// Remaps the violets to the blue tokens (the lab switch).
  final bool blueOnly;

  /// The part of the art that fills the box (default: the measured content).
  final OnboardingArtWindow window;

  /// The network's second tier of persons (lab switch, default on).
  final bool networkTier2;

  /// The network's mirror-symmetric layout (lab switch, default on); off is
  /// the previous layout.
  final bool networkSymmetric;

  @override
  State<OnboardingArt> createState() => OnboardingArtState();
}

class OnboardingArtState extends State<OnboardingArt>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late OnboardingArtController _controller;
  OnboardingArtController? _own;
  late SvgScene _scene;
  late ArtScene _art;
  late SvgRenderer _renderer;
  Ticker? _ticker;
  bool _isTickerEnabled = true;
  bool _isResumed = true;
  bool _isReduced = false;

  @visibleForTesting
  bool get hasTicker => _ticker != null;

  @visibleForTesting
  bool get isTicking => _ticker?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isResumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _attachController();
    _buildScene();
    if (!widget.autoplay) _controller.pause();
  }

  void _attachController() {
    _own = widget.controller == null ? OnboardingArtController() : null;
    _controller = widget.controller ?? _own!;
    _controller.addListener(_sync);
  }

  void _buildScene() {
    _scene = widget.kind.build(
      widget.blueOnly
          ? OnboardingArtPalette.purpleToBlue
          : OnboardingArtPalette.authored,
    );
    _art = widget.kind.bind(
      _scene,
      tier2: widget.networkTier2,
      symmetric: widget.networkSymmetric,
    );
    _renderer = SvgRenderer(_scene);
    _controller.duration = _art.duration;
    _setBaseSpeed();
  }

  void _setBaseSpeed() {
    if (_controller.baseSpeed == widget.kind.speed) return;
    _controller.baseSpeed = widget.kind.speed;
    _controller.epoch++;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (enabled != _isTickerEnabled) {
      _isTickerEnabled = enabled;
      _controller.restartClock(); // the muted time must not count
    }
    final reduced = widget.reducedMotion ??
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (reduced != _isReduced || _ticker == null) {
      _isReduced = reduced;
      if (reduced) _controller.time.value = _art.staticT;
      _sync();
    }
  }

  @override
  void didUpdateWidget(OnboardingArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_sync);
      _own?.dispose();
      _attachController();
      _controller.duration = _art.duration;
      _setBaseSpeed();
    }
    if (oldWidget.kind != widget.kind ||
        oldWidget.blueOnly != widget.blueOnly ||
        oldWidget.networkTier2 != widget.networkTier2 ||
        oldWidget.networkSymmetric != widget.networkSymmetric) {
      _buildScene();
    }
    final reduced = widget.reducedMotion ??
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (reduced != _isReduced) {
      _isReduced = reduced;
      if (reduced) _controller.time.value = _art.staticT;
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isResumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final canRun = !_isReduced &&
        _controller.isPlaying &&
        widget.isActive &&
        _isResumed &&
        (widget.loop || _controller.time.value < _art.duration);
    if (canRun) {
      if (_ticker?.isActive ?? false) return;
      _ticker ??= createTicker(_onTick);
      _controller.restartClock();
      _ticker!.start();
    } else if (_ticker?.isActive ?? false) {
      _ticker!.stop();
    }
  }

  void _onTick(Duration elapsed) {
    var t = _controller.advance(elapsed);
    if (!widget.loop && t >= _art.duration) {
      t = _art.duration;
      _controller.time.value = t;
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_sync);
    _ticker?.dispose();
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vb = widget.window == OnboardingArtWindow.crop
        ? widget.kind.cropWindow(
            _scene.viewBox,
            symmetric: widget.networkSymmetric,
          )
        : _scene.viewBox;
    return Center(
      child: AspectRatio(
        aspectRatio: vb.width / vb.height,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: OnboardingArtPainter(
              scene: _scene,
              art: _art,
              renderer: _renderer,
              time: _controller.time,
              window: vb,
            ),
          ),
        ),
      ),
    );
  }
}

/// The shield / encryption animation (viewBox 1774x887).
class ShieldSecurityArt extends StatelessWidget {
  const ShieldSecurityArt({
    super.key,
    this.controller,
    this.autoplay = true,
    this.loop = true,
    this.reducedMotion,
    this.isActive = true,
    this.blueOnly = false,
    this.window = OnboardingArtWindow.crop,
  });

  final OnboardingArtController? controller;
  final bool autoplay, loop, isActive, blueOnly;
  final OnboardingArtWindow window;
  final bool? reducedMotion;

  @override
  Widget build(BuildContext context) => OnboardingArt(
    kind: OnboardingArtKind.shield,
    controller: controller,
    autoplay: autoplay,
    loop: loop,
    reducedMotion: reducedMotion,
    isActive: isActive,
    blueOnly: blueOnly,
    window: window,
  );
}

/// The connected-network animation (viewBox 2400x1600).
class NetworkIconsArt extends StatelessWidget {
  const NetworkIconsArt({
    super.key,
    this.controller,
    this.autoplay = true,
    this.loop = true,
    this.reducedMotion,
    this.isActive = true,
    this.blueOnly = false,
    this.window = OnboardingArtWindow.crop,
  });

  final OnboardingArtController? controller;
  final bool autoplay, loop, isActive, blueOnly;
  final OnboardingArtWindow window;
  final bool? reducedMotion;

  @override
  Widget build(BuildContext context) => OnboardingArt(
    kind: OnboardingArtKind.network,
    controller: controller,
    autoplay: autoplay,
    loop: loop,
    reducedMotion: reducedMotion,
    isActive: isActive,
    blueOnly: blueOnly,
    window: window,
  );
}

/// The enterprise-switching animation (viewBox 1536x1024).
class BuildingsSwitchingArt extends StatelessWidget {
  const BuildingsSwitchingArt({
    super.key,
    this.controller,
    this.autoplay = true,
    this.loop = true,
    this.reducedMotion,
    this.isActive = true,
    this.blueOnly = false,
    this.window = OnboardingArtWindow.crop,
  });

  final OnboardingArtController? controller;
  final bool autoplay, loop, isActive, blueOnly;
  final OnboardingArtWindow window;
  final bool? reducedMotion;

  @override
  Widget build(BuildContext context) => OnboardingArt(
    kind: OnboardingArtKind.buildings,
    controller: controller,
    autoplay: autoplay,
    loop: loop,
    reducedMotion: reducedMotion,
    isActive: isActive,
    blueOnly: blueOnly,
    window: window,
  );
}
