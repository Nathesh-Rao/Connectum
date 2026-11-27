import 'package:flutter/material.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/sv_file.dart';
import '../sv_file_preview_controller.dart';
import '../widgets/sv_file_chips.dart';
import 'sv_media_player.dart';

String svClock(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// Video or audio from the cached temp file: play / pause, a seek bar with
/// the times, 10 s back and forward, mute and speed. Pauses when its page is
/// not the current one; the player is released when the page goes.
class SvMediaViewer extends StatefulWidget {
  const SvMediaViewer({
    super.key,
    required this.load,
    required this.isActive,
    required this.factory,
  });

  final SvFileLoad load;
  final bool isActive;
  final SvMediaPlayerFactory factory;

  @override
  State<SvMediaViewer> createState() => _SvMediaViewerState();
}

class _SvMediaViewerState extends State<SvMediaViewer> {
  late final SvMediaPlayer _player;
  bool _isSeeking = false;
  double _seek = 0;

  bool get _isAudio => widget.load.file.viewer == SvViewer.audio;

  @override
  void initState() {
    super.initState();
    _player = widget.factory(widget.load.local!);
    _player.init();
  }

  @override
  void didUpdateWidget(SvMediaViewer old) {
    super.didUpdateWidget(old);
    if (!widget.isActive && old.isActive) _player.pause();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SvMediaState>(
      valueListenable: _player.state,
      builder: (context, s, _) {
        if (s.hasError) return _Failed(file: widget.load.file);
        return Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isAudio)
                    _AudioCard(file: widget.load.file)
                  else if (s.isReady)
                    Center(
                      child: AspectRatio(
                        aspectRatio: s.aspectRatio,
                        child: _player.surface(),
                      ),
                    ),
                  if (!s.isReady || s.isBuffering)
                    const CircularProgressIndicator(
                      key: ValueKey('sv-media-busy'),
                      color: AppColors.primary,
                    ),
                  if (s.isReady && !s.isBuffering && !_isAudio)
                    _PlayButton(isPlaying: s.isPlaying, onTap: _player.toggle),
                ],
              ),
            ),
            _Transport(
              state: s,
              player: _player,
              isSeeking: _isSeeking,
              seek: _seek,
              onSeekStart: (v) => setState(() {
                _isSeeking = true;
                _seek = v;
              }),
              onSeekChange: (v) => setState(() => _seek = v),
              onSeekEnd: (v) {
                setState(() => _isSeeking = false);
                _player.seekTo(Duration(milliseconds: v.round()));
              },
              showPlay: _isAudio,
            ),
          ],
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 160),
    opacity: isPlaying ? 0 : 1,
    child: IgnorePointer(
      ignoring: isPlaying,
      child: Semantics(
        button: true,
        label: 'Play',
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('sv-media-play'),
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              size: 40,
              color: AppColors.white,
            ),
          ),
        ),
      ),
    ),
  );
}

class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.file});

  final SvFile file;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSv.fileCircle,
          height: AppSv.fileCircle,
          decoration: BoxDecoration(
            color: file.kind.palette.background,
            shape: BoxShape.circle,
          ),
          child: Icon(
            svFileIcon(file.kind),
            size: AppSv.fileCircleIcon,
            color: file.kind.palette.foreground,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          SvFile.middleEllipsis(file.name, 40),
          style: AppSv.fileTitle,
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    ),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.file});

  final SvFile file;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        "This ${file.viewer == SvViewer.audio ? 'audio' : 'video'} can't be "
        'played here. Download it or open it with another app.',
        style: AppText.supporting,
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.state,
    required this.player,
    required this.isSeeking,
    required this.seek,
    required this.onSeekStart,
    required this.onSeekChange,
    required this.onSeekEnd,
    required this.showPlay,
  });

  final SvMediaState state;
  final SvMediaPlayer player;
  final bool isSeeking;
  final double seek;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChange;
  final ValueChanged<double> onSeekEnd;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    final total = state.duration.inMilliseconds.toDouble();
    final pos = isSeeking
        ? seek
        : state.position.inMilliseconds.toDouble().clamp(
            0,
            total <= 0 ? 1 : total,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                svClock(Duration(milliseconds: pos.round())),
                key: const ValueKey('sv-media-elapsed'),
                style: AppSv.fileChipSize,
              ),
              Expanded(
                child: Slider(
                  value: total <= 0 ? 0 : pos.toDouble(),
                  max: total <= 0 ? 1 : total,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.primaryTint,
                  onChangeStart: onSeekStart,
                  onChanged: total <= 0 ? null : onSeekChange,
                  onChangeEnd: onSeekEnd,
                ),
              ),
              Text(
                svClock(state.duration),
                key: const ValueKey('sv-media-total'),
                style: AppSv.fileChipSize,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton.icon(
                icon: state.isMuted ? Icons.volume_off : Icons.volume_up,
                semanticLabel: state.isMuted ? 'Unmute' : 'Mute',
                onPressed: player.toggleMute,
              ),
              AppButton.icon(
                icon: Icons.replay_10,
                semanticLabel: 'Back 10 seconds',
                onPressed: () => player.skip(const Duration(seconds: -10)),
              ),
              if (showPlay)
                AppButton.icon(
                  icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                  semanticLabel: state.isPlaying ? 'Pause' : 'Play',
                  onPressed: player.toggle,
                ),
              AppButton.icon(
                icon: Icons.forward_10,
                semanticLabel: 'Forward 10 seconds',
                onPressed: () => player.skip(const Duration(seconds: 10)),
              ),
              PopupMenuButton<double>(
                tooltip: 'Playback speed',
                color: AppColors.white,
                initialValue: state.speed,
                onSelected: player.setSpeed,
                itemBuilder: (context) => [
                  for (final s in const [0.5, 1.0, 1.5, 2.0])
                    PopupMenuItem(value: s, child: Text('$s×')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text('${state.speed}×', style: AppText.readableStrong),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
