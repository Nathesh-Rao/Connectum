import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_scaffold.dart';
import '../../core/widgets/app_text_field.dart';
import 'debug_socket_controller.dart';

class DebugSocketView extends GetView<DebugSocketController> {
  const DebugSocketView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.lg),
          const Text('Debug: socket', style: AppText.heading),
          _section('State'),
          Obx(
            () => Text(
              'socket: ${c.socket.connection.value.name}\n'
              'connectivity: ${c.connectivity.state.value.name}\n'
              'network: ${c.connectivity.hasNetwork.value}\n'
              'org/user: ${c.session.store.orgId ?? '-'} / ${c.session.store.userId ?? '-'}\n'
              'config: ${AppConfig.isConfigured ? 'BASE_URL and WS_URL set' : 'BASE_URL / WS_URL NOT set'}\n'
              'notice: ${c.session.loginNotice.value ?? '-'}',
              style: AppText.readable,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Obx(
            () => Row(
              children: [
                Expanded(
                  child: Text('Simulate offline', style: AppText.bodyStrong),
                ),
                Switch(
                  value: c.connectivity.simulateOffline.value,
                  activeThumbColor: AppColors.accent,
                  onChanged: (v) => c.connectivity.simulateOffline.value = v,
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Connect',
                  onPressed: c.connect,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Disconnect',
                  onPressed: c.disconnect,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Sync now', onPressed: c.syncNow),
          _section('Outbox'),
          Obx(() => Text(c.outbox.value, style: AppText.readable)),
          _section('Test login (token stays in secure storage)'),
          AppTextField(controller: c.orgId, label: 'Organisation id'),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(controller: c.username, label: 'Username'),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: c.token,
            label: 'Session token',
            obscureText: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.primary(label: 'Sign in', onPressed: c.loginDirect),
          _section('Or run the enter flow (logs redacted shape)'),
          AppTextField(
            controller: c.identityToken,
            label: 'Identity token',
            obscureText: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(controller: c.enterpriseId, label: 'Enterprise id'),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Enter', onPressed: c.enterFlow),
          _section('Send a test message'),
          AppTextField(
            controller: c.convId,
            label: 'Conversation id (dm:<user>, group:<name>, global)',
          ),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(controller: c.messageText, label: 'Text'),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Send', onPressed: c.sendTest),
          _section('Form meta test (creates a real submission)'),
          AppTextField(controller: c.formName, label: 'Form name'),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(
            controller: c.formValues,
            label: 'Values (JSON)',
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Submit and read back',
            onPressed: c.metaTest,
          ),
          _section('Results'),
          Obx(() => Text(c.notes.join('\n\n'), style: AppText.readable)),
          _section('Last 20 events (redacted)'),
          Obx(() => Text(c.socket.eventLog.join('\n'), style: AppText.caption)),
          const SizedBox(height: AppSpacing.md),
          AppButton.secondary(
            label: 'Sign out (wipes this org data)',
            onPressed: c.signOut,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
    child: Text(title, style: AppText.subtitle),
  );
}
