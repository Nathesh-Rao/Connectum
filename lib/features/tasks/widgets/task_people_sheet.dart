import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/theme/theme.dart';
import 'package:connectum/core/widgets/widgets.dart';
import '../../chats/models/chat_person.dart';
import '../task_people_controller.dart';
import '../tasks_controller.dart';
import '../tasks_texts.dart';

/// A searchable list of colleagues to pick one from. [show]'s `onPicked` runs
/// after the sheet closes.
class TaskPeopleSheet extends StatelessWidget {
  const TaskPeopleSheet({
    super.key,
    required this.people,
    required this.onPick,
  });

  final TaskPeopleController people;
  final ValueChanged<ChatPerson> onPick;

  static Future<void> show(
    BuildContext context,
    TasksController controller, {
    required String title,
    required ValueChanged<ChatPerson> onPicked,
  }) {
    final people = controller.newPeople()..load();
    ChatPerson? picked;
    return AppBottomSheet.show<void>(
      context,
      title: title,
      child: TaskPeopleSheet(
        people: people,
        onPick: (p) {
          picked = p;
          Navigator.of(context).pop();
        },
      ),
      onDispose: people.close,
    ).whenComplete(() {
      final p = picked;
      if (p != null) onPicked(p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = people;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: p.query,
          hint: TasksTexts.pickerSearch,
          leading: const Icon(Icons.search, size: 18, color: AppColors.muted),
          onChanged: p.onQueryChanged,
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: AppSpacing.pickerListHeight,
          child: Obx(() {
            if (p.isLoading.value) {
              return const Center(child: AppSpinner(isStandalone: true));
            }
            final error = p.error.value;
            if (error != null) {
              return Center(child: Text(error, style: AppText.readable));
            }
            final list = p.people.toList();
            if (list.isEmpty) {
              return const Center(
                child: Text(TasksTexts.pickerEmpty, style: AppText.readable),
              );
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 120) p.loadMore();
                return false;
              },
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final person = list[i];
                  return AppListRow(
                    title: person.name,
                    subtitle: person.detail.isEmpty ? null : person.detail,
                    minHeight: AppSpacing.settingRowHeight,
                    leading: AppAvatar(name: person.name, size: 32),
                    onTap: () => onPick(person),
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}
