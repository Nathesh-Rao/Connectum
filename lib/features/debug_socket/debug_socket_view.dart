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
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Simulate switch reload (Chats, 8 s)',
            onPressed: c.simulateSwitchReload,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Open Priya, then Arjun over it',
            onPressed: c.openStacked,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(
            label: 'Reload with a conversation open (6 s)',
            onPressed: c.reloadWithConversation,
          ),
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
          _section('Send with a client id (dm:, group:, host:)'),
          Obx(() => Text('cid: ${c.lastCid.value}', style: AppText.readable)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Send with cid',
                  onPressed: c.sendWithCid,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Same cid again',
                  onPressed: c.sendSameCidAgain,
                ),
              ),
            ],
          ),
          _section('Stored messages of the conversation above'),
          AppButton.secondary(label: 'Show last 8', onPressed: c.showMessages),
          const SizedBox(height: AppSpacing.xs),
          Obx(() => Text(c.recent.value, style: AppText.caption)),
          _section('Conversations (e2e flag, load older)'),
          Obx(
            () => Column(
              children: [
                for (final conv in c.conversationRepository.conversations)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${conv.convId}${conv.isEncrypted ? '  e2e' : ''}',
                          style: AppText.readable,
                        ),
                      ),
                      AppButton.text(
                        label: 'Load older',
                        onPressed: () => c.loadOlder(conv.convId),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          _section('Run an /sd action (read-only ones only)'),
          AppTextField(controller: c.sdAction, label: 'Action'),
          const SizedBox(height: AppSpacing.xs),
          AppTextField(controller: c.sdArgs, label: 'Args (JSON)'),
          const SizedBox(height: AppSpacing.xs),
          AppButton.secondary(label: 'Run', onPressed: c.runSd),
          _section('Inbox state (uses the conversation id and up-to id above)'),
          AppTextField(controller: c.upTo, label: 'Up to message id'),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'conv.list full',
                  onPressed: c.convListFull,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Stored state',
                  onPressed: c.showInboxState,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Mark read',
                  onPressed: c.markReadDebug,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Delivered',
                  onPressed: c.deliveredDebug,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Pin / unpin',
                  onPressed: c.togglePin,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Mute / unmute',
                  onPressed: c.toggleMute,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'conv.readers',
                  onPressed: c.readersDebug,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Presence list',
                  onPressed: c.presenceList,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Fake delivered receipt',
                  onPressed: () => c.fakeReceipt('delivered'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Fake read receipt',
                  onPressed: () => c.fakeReceipt('read'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Fake incoming',
                  onPressed: c.fakeIncoming,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Seed rows',
                  onPressed: c.seedMigrationRows,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _section('Form cid test (creates one real submission)'),
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
            label: 'Submit, repeat, show duplicate',
            onPressed: c.cidTest,
          ),
          _section('Migration check (own account, debug only)'),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Seed rows',
                  onPressed: c.seedMigrationRows,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Count rows',
                  onPressed: c.countRows,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Show outbox rows',
                  onPressed: c.showOutboxRows,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.secondary(
                  label: 'Remove test rows',
                  onPressed: c.removeTestRows,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
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
