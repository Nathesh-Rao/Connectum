import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/socket/connectivity_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_connectivity_scope.dart';

class AppOfflineBar extends StatefulWidget {
  const AppOfflineBar({super.key});

  @override
  State<AppOfflineBar> createState() => _AppOfflineBarState();
}

class _AppOfflineBarState extends State<AppOfflineBar> {
  static const _delay = Duration(seconds: 2);
  static const _height = 28.0;

  Rx<AppConnectivity>? _state;
  Worker? _worker;
  Timer? _timer;
  bool _isVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppConnectivityScope.maybeOf(context);
    if (state == _state) return;
    _worker?.dispose();
    _state = state;
    if (state != null) {
      _worker = ever(state, _onChanged);
      _onChanged(state.value);
    }
  }

  // Shows only after the state has lasted about 2 seconds; hides at once.
  void _onChanged(AppConnectivity value) {
    if (value == AppConnectivity.online) {
      _timer?.cancel();
      _timer = null;
      if (_isVisible) setState(() => _isVisible = false);
    } else if (_isVisible) {
      setState(() {});
    } else {
      _timer ??= Timer(_delay, () {
        _timer = null;
        if (mounted && _state?.value != AppConnectivity.online) {
          setState(() => _isVisible = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOffline = _state?.value == AppConnectivity.offline;
    return AnimatedSize(
      duration: AppDurations.base,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppDurations.fast,
        switchInCurve: AppCurves.out,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: _isVisible
            ? Container(
                key: const ValueKey('bar'),
                width: double.infinity,
                height: _height,
                color: AppColors.ink,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 14,
                      color: AppColors.background,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOffline ? "You're offline" : 'Connecting…',
                      style: AppText.readable.copyWith(
                        color: AppColors.background,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox(key: ValueKey('none'), width: double.infinity),
      ),
    );
  }
}
