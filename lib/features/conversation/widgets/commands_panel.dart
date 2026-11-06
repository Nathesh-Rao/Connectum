import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../data/commands/command_reply.dart';
import '../../../data/models/hash_command.dart';
import '../../commands/widgets/command_category_icon.dart';
import '../models/command_prompt.dart';

/// The "#" menu of a message box: a compact card right above the box (so
/// above the keyboard), at most six rows visible and scrollable. A tap on a
/// command puts `#name ` in the box, a tap on a choice puts its value in;
/// back closes it. Nothing runs until send.
class CommandsPanel extends StatelessWidget {
  const CommandsPanel({
    super.key,
    required this.prompt,
    required this.onPick,
    required this.onPickItem,
    required this.onPickName,
    required this.isOnline,
  });

  final CommandPrompt prompt;
  final ValueChanged<HashCommand> onPick;
  final ValueChanged<CommandSuggestion> onPickItem;
  final ValueChanged<String> onPickName;
  final bool Function() isOnline;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AppDurations.fast,
    curve: AppCurves.out,
    alignment: Alignment.bottomCenter,
    child: Obx(() {
      if (!prompt.isOpen) return const SizedBox(width: double.infinity);
      final Widget body;
      if (prompt.unknownNames.isNotEmpty) {
        body = _Suggested(
          names: prompt.unknownNames.toList(),
          onTap: onPickName,
        );
      } else if (prompt.command.value != null) {
        body = _Arguments(prompt: prompt, onPickItem: onPickItem);
      } else {
        body = _Names(prompt: prompt, onPick: onPick, isOnline: isOnline);
      }
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) => prompt.close(),
        child: Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            0,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: AppRadius.controlAll,
          ),
          child: body,
        ),
      );
    }),
  );
}

const _maxHeight = AppSpacing.commandRowHeight * AppSpacing.commandMaxRows;

class _Names extends StatelessWidget {
  const _Names({
    required this.prompt,
    required this.onPick,
    required this.isOnline,
  });

  final CommandPrompt prompt;
  final ValueChanged<HashCommand> onPick;
  final bool Function() isOnline;

  @override
  Widget build(BuildContext context) {
    final rows = prompt.matches;
    if (rows.isEmpty) {
      final text = !prompt.hasCatalog
          ? (prompt.isLoading
                ? 'Loading commands…'
                : isOnline()
                ? "Commands aren't available right now."
                : 'Commands need a connection the first time.')
          : 'No matching command';
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(text, style: AppText.readable),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
        itemCount: rows.length,
        itemBuilder: (context, i) => _CommandRow(
          key: ValueKey(rows[i].name),
          command: rows[i],
          onTap: () => onPick(rows[i]),
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({super.key, required this.command, required this.onTap});

  final HashCommand command;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = command;
    final color = c.isAvailable ? AppColors.ink : AppColors.muted;
    return InkWell(
      onTap: c.isAvailable ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.commandRowHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            children: [
              Icon(CommandCategoryIcon.of(c.category), size: 20, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#${c.name}${c.summary.isEmpty ? '' : '  ${c.summary}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.readableStrong.copyWith(color: color),
                    ),
                    if (c.usage.isNotEmpty)
                      Text(
                        c.usage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                  ],
                ),
              ),
              if (!c.isAvailable && c.requires != 'none')
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: Text('Needs ${c.requires}', style: AppText.caption),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Arguments extends StatelessWidget {
  const _Arguments({required this.prompt, required this.onPickItem});

  final CommandPrompt prompt;
  final ValueChanged<CommandSuggestion> onPickItem;

  @override
  Widget build(BuildContext context) {
    final items = prompt.items.toList();
    final cmd = prompt.command.value!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Text(
            prompt.hint.value.isEmpty ? '#${cmd.name}' : prompt.hint.value,
            style: AppText.caption,
          ),
        ),
        if (items.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxHeight),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < AppSpacing.commandRowHeight) {
                  prompt.loadMore();
                }
                return false;
              },
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  return InkWell(
                    key: ValueKey('${item.value}-$i'),
                    onTap: () => onPickItem(item),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AppSpacing.minTapTarget,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.label.isEmpty ? item.value : item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.readableStrong,
                              ),
                            ),
                            if (item.hint.isNotEmpty)
                              Text(item.hint, style: AppText.caption),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Suggested extends StatelessWidget {
  const _Suggested({required this.names, required this.onTap});

  final List<String> names;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Did you mean', style: AppText.caption),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final n in names)
              GestureDetector(
                onTap: () => onTap(n),
                child: AppTag(label: '#$n'),
              ),
          ],
        ),
      ],
    ),
  );
}
