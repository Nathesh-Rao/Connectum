import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/app_action_bar.dart';
import '../../../core/widgets/app_form_card.dart';
import '../../../data/repositories/ticket_repository.dart';
import '../models/ticket_action_style.dart';
import 'record_status_block.dart';

/// What a record card shows under its fields, in a chat and in the Work
/// Space: where the record stands (status, who it is with, completion, the
/// last update) and one button per action the server returned and enabled.
/// It follows one record's live state, so only this card rebuilds when that
/// record changes.
///
/// Drawing never reads anything: while the card is on screen it tells the
/// repository's queue so ([TicketRepository.loadActions]) and the bar fades in
/// when the answer arrives. A card that is no record is not built with this.
class RecordCardActions extends StatelessWidget {
  const RecordCardActions({
    super.key,
    required this.recordId,
    required this.tickets,
    required this.onAction,
  });

  final int recordId;
  final TicketRepository tickets;

  /// A button was tapped: [actionId] is `send` or `status`.
  final void Function(BuildContext context, String actionId) onAction;

  @override
  Widget build(BuildContext context) {
    return _OnScreen(
      recordId: recordId,
      tickets: tickets,
      child: Obx(() {
        final live = tickets.liveOf(recordId).value;
        final actions = tickets.itemsOf(recordId);
        final footer =
            AppFormCardScope.maybeOf(context)?.footer ??
            const SizedBox.shrink();
        if (actions.isEmpty && !live.isShown) return footer;
        return AppFormCardActionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecordStatusBlock(live: live),
              _Appear(
                child: actions.isEmpty
                    ? null
                    : AppActionBar(
                        inset: AppFormCardActionArea.inset,
                        items: actionItemsOf(actions),
                        onTap: (item) => onAction(context, item.id),
                      ),
              ),
              if (actions.isEmpty) footer,
            ],
          ),
        );
      }),
    );
  }
}

/// Tells the queue this record's card is on screen while it is built and its
/// screen is the one in front (a covered screen has its tickers off).
class _OnScreen extends StatefulWidget {
  const _OnScreen({
    required this.recordId,
    required this.tickets,
    required this.child,
  });

  final int recordId;
  final TicketRepository tickets;
  final Widget child;

  @override
  State<_OnScreen> createState() => _OnScreenState();
}

class _OnScreenState extends State<_OnScreen> {
  bool _isShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _set(TickerMode.of(context));
  }

  @override
  void didUpdateWidget(_OnScreen old) {
    super.didUpdateWidget(old);
    if (old.recordId != widget.recordId) {
      if (_isShown) old.tickets.releaseActions([old.recordId]);
      _isShown = false;
      _set(TickerMode.of(context));
    }
  }

  // Deferred out of the build that mounts the card: the queue may change
  // observables.
  void _set(bool isOn) {
    if (isOn == _isShown) return;
    _isShown = isOn;
    final id = widget.recordId;
    final tickets = widget.tickets;
    if (isOn) {
      scheduleMicrotask(() {
        if (mounted && _isShown) tickets.loadActions([id]);
      });
    } else {
      tickets.releaseActions([id]);
    }
  }

  @override
  void dispose() {
    if (_isShown) widget.tickets.releaseActions([widget.recordId]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The bar grows in and fades in (150 ms) when it first has something to
/// show, so the card does not jump.
class _Appear extends StatelessWidget {
  const _Appear({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppDurations.reduced,
      curve: AppCurves.out,
      alignment: Alignment.topCenter,
      child: child == null
          ? const SizedBox(width: double.infinity)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: AppDurations.reduced,
              curve: AppCurves.out,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: child,
            ),
    );
  }
}
