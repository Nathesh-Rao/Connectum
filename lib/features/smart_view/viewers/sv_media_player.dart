import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// What the transport controls show.
class SvMediaState {
  const SvMediaState({
    this.isReady = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.hasError = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1,
    this.speed = 1,
    this.aspectRatio = 16 / 9,
  });

  final bool isReady;
  final bool isPlaying;
  final bool isBuffering;
  final bool hasError;
  final Duration position;
  final Duration duration;
  final double volume;
  final double speed;
  final double aspectRatio;

  bool get isMuted => volume == 0;
}

/// The one player of a video or audio page, over `video_player`, playing the
/// cached temp file only. Tests subclass it through [SvMediaPlayer.test].
class SvMediaPlayer {
  SvMediaPlayer.file(File file) : _c = VideoPlayerController.file(file);

  @visibleForTesting
  SvMediaPlayer.test() : _c = null;

  final VideoPlayerController? _c;
  final state = ValueNotifier<SvMediaState>(const SvMediaState());
  bool _isDisposed = false;

  Future<void> init() async {
    final c = _c;
    if (c == null) return;
    try {
      await c.initialize();
    } on Object {
      if (!_isDisposed) state.value = const SvMediaState(hasError: true);
      return;
    }
    if (_isDisposed) return;
    c.addListener(_sync);
    _sync();
  }

  void _sync() {
    final c = _c;
    if (c == null || _isDisposed) return;
    final v = c.value;
    state.value = SvMediaState(
      isReady: v.isInitialized,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      hasError: v.hasError,
      position: v.position,
      duration: v.duration,
      volume: v.volume,
      speed: v.playbackSpeed,
      aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
    );
  }

  Future<void> play() async => _c?.play();

  Future<void> pause() async => _c?.pause();

  Future<void> toggle() => state.value.isPlaying ? pause() : play();

  Future<void> seekTo(Duration to) async {
    final d = state.value.duration;
    final clamped = to < Duration.zero ? Duration.zero : (to > d ? d : to);
    await _c?.seekTo(clamped);
  }

  Future<void> skip(Duration by) => seekTo(state.value.position + by);

  Future<void> toggleMute() async => _c?.setVolume(state.value.isMuted ? 1 : 0);

  Future<void> setSpeed(double speed) async => _c?.setPlaybackSpeed(speed);

  /// The video picture; nothing for audio or while not ready.
  Widget surface() {
    final c = _c;
    return c == null ? const SizedBox.shrink() : VideoPlayer(c);
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    final c = _c;
    c?.removeListener(_sync);
    await c?.dispose();
    state.dispose();
  }
}

typedef SvMediaPlayerFactory = SvMediaPlayer Function(File file);
