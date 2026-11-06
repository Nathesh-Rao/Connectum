import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_bottom_sheet.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/models/hash_command.dart';
import '../../../data/repositories/command_repository.dart';
import 'command_category_icon.dart';

/// The sheets the "#" commands open. Each is shown from the app's navigator,
/// so a controller never needs a BuildContext.
class CommandSheets {
  CommandSheets._();

  static const _searchFrom = 10;

  static Future<void> showRows({
    required String title,
    required List<CommandRow> rows,
    required void Function(String convId) onOpen,
  }) async {
    final context = Get.context;
    if (context == null) return;
    await AppBottomSheet.show<void>(
      context,
      title: title,
      child: _RowsSheet(rows: rows, onOpen: onOpen),
    );
  }

  static Future<bool> confirmLeave(String group) async {
    final context = Get.context;
    if (context == null) return false;
    final isSure = await AppBottomSheet.show<bool>(
      context,
      title: 'Leave $group?',
      child: Builder(
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'You will no longer get messages from this group.',
              style: AppText.readable,
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton.secondary(
              label: 'Leave group',
              isDanger: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            AppButton.text(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
    return isSure ?? false;
  }

  /// The directory of every command; [name] opens one command's detail.
  static Future<void> showHelp(
    CommandRepository commands, {
    String? name,
  }) async {
    await commands.ensureLoaded();
    final first = name == null ? null : await commands.detail(name);
    final after = Get.context;
    if (after == null || !after.mounted) return;
    await AppBottomSheet.show<void>(
      after,
      title: first == null ? 'Commands' : '#${first.name}',
      child: _HelpSheet(commands: commands, first: first),
    );
  }
}

class _RowsSheet extends StatefulWidget {
  const _RowsSheet({required this.rows, required this.onOpen});

  final List<CommandRow> rows;
  final void Function(String convId) onOpen;

  @override
  State<_RowsSheet> createState() => _RowsSheetState();
}

class _RowsSheetState extends State<_RowsSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final r in widget.rows)
        if (q.isEmpty || r.title.toLowerCase().contains(q)) r,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.rows.length > CommandSheets._searchFrom) ...[
          AppTextField(
            controller: _search,
            hint: 'Search',
            minHeight: AppSpacing.searchHeight,
            fillColor: AppColors.searchFill,
            borderColor: Colors.transparent,
            textStyle: AppText.input,
            leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text('Nothing to show', style: AppText.readable),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: shown.length,
              itemBuilder: (context, i) {
                final r = shown[i];
                return AppListRow(
                  title: r.title,
                  subtitle: r.subtitle.isEmpty ? null : r.subtitle,
                  minHeight: AppSpacing.minTapTarget,
                  leading: AppAvatar(
                    name: r.title,
                    size: AppSpacing.avatarSmall,
                  ),
                  onTap: r.convId.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          widget.onOpen(r.convId);
                        },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _HelpSheet extends StatefulWidget {
  const _HelpSheet({required this.commands, required this.first});

  final CommandRepository commands;
  final HashCommand? first;

  @override
  State<_HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends State<_HelpSheet> {
  late HashCommand? _open = widget.first;

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return _Detail(
        command: open,
        onBack: widget.first == null
            ? () => setState(() => _open = null)
            : null,
      );
    }
    final categories = widget.commands.categories;
    String label(String id) =>
        categories.where((c) => c.id == id).firstOrNull?.label ?? id;
    final rows = <Widget>[];
    String? last;
    for (final c in widget.commands.menu('')) {
      if (c.category != last) {
        last = c.category;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(label(c.category).toUpperCase(), style: AppText.kicker),
          ),
        );
      }
      rows.add(
        AppListRow(
          title: c.usage.isEmpty ? '#${c.name}' : c.usage,
          subtitle: c.summary,
          minHeight: AppSpacing.minTapTarget,
          leading: Icon(
            CommandCategoryIcon.of(c.category),
            size: 20,
            color: AppColors.muted,
          ),
          onTap: () => setState(() => _open = c),
        ),
      );
    }
    return Flexible(child: ListView(shrinkWrap: true, children: rows));
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.command, this.onBack});

  final HashCommand command;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = command;
    final who = c.requires == 'none' || c.requires.isEmpty
        ? 'Everyone'
        : 'Needs ${c.requires}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.summary.isNotEmpty) Text(c.summary, style: AppText.readable),
        const SizedBox(height: AppSpacing.sm),
        Text(
          c.usage.isEmpty ? '#${c.name}' : c.usage,
          style: AppText.readableStrong,
        ),
        if (c.aliases.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Also: ${c.aliases.map((a) => '#$a').join(', ')}',
            style: AppText.caption,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        for (final a in c.args)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Text(
              '${a.name} · ${a.type}${a.isRequired ? '' : ' (optional)'}'
              '${a.values.isEmpty ? '' : ': ${a.values.join(', ')}'}'
              '${a.max == null ? '' : ' · up to ${a.max} characters'}',
              style: AppText.caption,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        Text('Who can use it: $who', style: AppText.caption),
        if (onBack != null)
          AppButton.text(label: 'All commands', onPressed: onBack),
      ],
    );
  }
}
