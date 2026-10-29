import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_text.dart';

/// Three dots that rise in turn, beside a line such as "Priya is typing".
/// Still under reduced motion.
class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.label});

  final String label;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.slow * 2,
  );
  bool? _isStill;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isStill = MediaQuery.disableAnimationsOf(context);
    if (isStill == _isStill) return;
    _isStill = isStill;
    if (isStill) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Transform.translate(
                    offset: Offset(0, -3 * _wave(i)),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.noDot.withValues(
                          alpha: 0.55 + 0.45 * _wave(i),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption,
          ),
        ),
      ],
    );
  }

  /// 0 to 1, each dot a third of a cycle behind the one before it.
  double _wave(int i) {
    final t = (_controller.value - i / 3) % 1;
    return t < 0.4 ? Curves.easeInOut.transform(t / 0.4) : 0;
  }
}
