import 'package:flutter/material.dart';

/// The icon of a command category (the server sends none).
class CommandCategoryIcon {
  CommandCategoryIcon._();

  static IconData of(String category) => switch (category) {
    'messaging' => Icons.chat_bubble_outline,
    'lookup' => Icons.search,
    'groups' => Icons.groups_outlined,
    'profile' => Icons.person_outline,
    'people' => Icons.people_outline,
    'inbox' => Icons.inbox_outlined,
    'forms' => Icons.description_outlined,
    'admin' => Icons.admin_panel_settings_outlined,
    'help' => Icons.help_outline,
    _ => Icons.bolt,
  };
}
