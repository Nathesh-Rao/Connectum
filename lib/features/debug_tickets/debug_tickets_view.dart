import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import 'debug_tickets_controller.dart';

class DebugTicketsView extends GetView<DebugTicketsController> {
  const DebugTicketsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Tickets (debug)', style: AppText.heading),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'The captured sample replies answer the calls; nothing is sent. '
            'Sample user: ana.',
            style: AppText.readable,
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sample data, no server', style: AppText.body),
              value: c.isSample.value,
              onChanged: c.isLoading.value ? null : c.toggleSample,
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'Open Tickets',
              onPressed: c.openTickets,
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'Open ticket #38 (with me)',
              onPressed: () => c.openTicket(38),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Inject', style: AppText.subtitle),
          const SizedBox(height: AppSpacing.xs),
          _Gap(
            AppButton.secondary(
              label: 'ticket_assigned (raised to me)',
              onPressed: c.injectAssigned,
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'A ticket waiting for approval',
              onPressed: c.addWaiting,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Obx(
            () => Text(
              c.nextFailure.value == null
                  ? 'Make the next update fail'
                  : 'Next update: ${c.nextFailure.value}',
              style: AppText.subtitle,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _Gap(
            AppButton.secondary(
              label: 'stale',
              onPressed: () => c.failNext(
                'stale',
                'This ticket was updated by someone else. Reload to see the latest.',
              ),
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'forbidden',
              onPressed: () =>
                  c.failNext('forbidden', 'You cannot do this on this ticket.'),
            ),
          ),
          _Gap(
            AppButton.secondary(
              label: 'lost answer (retry reuses the request id)',
              onPressed: c.loseNextAnswer,
            ),
          ),
          AppButton.text(label: 'Clear', onPressed: c.clearFailure),
          const SizedBox(height: AppSpacing.md),
          _Gap(
            AppButton.secondary(
              label: 'Show request ids seen',
              onPressed: c.showRequestIds,
            ),
          ),
          Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final id in c.requestIds)
                  Text(id, style: AppText.readable),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: child,
  );
}
