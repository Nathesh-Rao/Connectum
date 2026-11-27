import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../../data/smart_view/sv_team.dart';
import 'sv_filter_draft.dart';
import 'sv_filter_sheet.dart';

/// What the "My team" line offers: the person's direct reports, with the name
/// and picture known for each (the user name until the answer arrives).
class SvTeamChoices {
  SvTeamChoices({
    required this.users,
    required this.nameOf,
    required this.pictureOf,
  });

  final RxList<String> users;
  final String Function(String user) nameOf;
  final String? Function(String user) pictureOf;
}

/// The two lines every structure's filter sheet has when somebody reports to
/// the person: "My team" (none chosen = every report) and "Linked as" (none
/// chosen = any way). Drawn only when [SvTeamChoices.users] is not empty.
class SvTeamLines extends StatelessWidget {
  const SvTeamLines({super.key, required this.draft, required this.choices});

  final SvFilterDraft draft;
  final SvTeamChoices choices;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final users = choices.users.toList();
      if (users.isEmpty) return const SizedBox.shrink();
      final members = draft.members.toList();
      final ways = draft.linked.toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xs),
          _Line(
            key: const ValueKey('sv-team-members'),
            title: 'My team',
            help: 'None chosen means every person who reports to you.',
            children: [
              for (final u in users)
                SvChoiceChip(
                  label: choices.nameOf(u),
                  isOn: members.contains(u),
                  onTap: () => draft.toggleMember(u),
                  leading: AppAvatar(
                    name: choices.nameOf(u),
                    size: AppSpacing.chipAvatar,
                    picture: choices.pictureOf(u),
                  ),
                ),
            ],
          ),
          _Line(
            key: const ValueKey('sv-team-linked'),
            title: 'Linked as',
            help: ways.isEmpty ? 'None chosen means any way.' : null,
            notes: [
              for (final w in SvTeam.ways)
                if (ways.contains(w.id)) '${w.label}: ${w.hint}',
            ],
            children: [
              for (final w in SvTeam.ways)
                SvChoiceChip(
                  label: w.label,
                  isOn: ways.contains(w.id),
                  onTap: () => draft.toggleWay(w.id),
                ),
            ],
          ),
        ],
      );
    });
  }
}

class _Line extends StatelessWidget {
  const _Line({
    super.key,
    required this.title,
    required this.children,
    this.help,
    this.notes = const [],
  });

  final String title;
  final String? help;
  final List<String> notes;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppSv.filterCardFill,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: AppSv.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppText.bodyStrong),
              if (help != null) Text(help!, style: AppText.caption),
              for (final n in notes) Text(n, style: AppText.caption),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: children,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
