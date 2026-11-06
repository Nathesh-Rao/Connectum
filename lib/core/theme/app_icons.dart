class AppHomeIcons {
  const AppHomeIcons();

  final newChat = 'assets/icons/home/new_chat.png';
  final workSpace = 'assets/icons/home/work_space.png';
  final group = 'assets/icons/home/group.png';
  final ticket = 'assets/icons/home/ticket.png';
}

class AppBottomNavIcons {
  const AppBottomNavIcons();

  final chatSelected = 'assets/icons/bottom_nav/chat_selected.png';
  final chatUnselected = 'assets/icons/bottom_nav/chat_unselected.png';
  final aiSelected = 'assets/icons/bottom_nav/ai_selected.png';
  final aiUnselected = 'assets/icons/bottom_nav/ai_unselected.png';
  final submissionsSelected =
      'assets/icons/bottom_nav/submissions_selected.png';
  final submissionsUnselected =
      'assets/icons/bottom_nav/submissions_unselected.png';
  final profileSelected = 'assets/icons/bottom_nav/profile_selected.png';
  final profileUnselected = 'assets/icons/bottom_nav/profile_unselected.png';
}

/// Paths of the PNG icons, e.g. `AppIcons.home.newChat`.
class AppIcons {
  AppIcons._();

  static const home = AppHomeIcons();
  static const bottomNav = AppBottomNavIcons();
}
