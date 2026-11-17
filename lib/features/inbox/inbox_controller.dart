import 'package:get/get.dart';

/// The Inbox tab, as a sample: no data and no network. Only the chosen pill
/// is state.
class InboxController extends GetxController {
  static const filters = [
    'All',
    'Tasks & tickets',
    'Approvals',
    'Reminders',
    'My submissions',
    'Broadcast',
  ];

  /// The static sample count on the Broadcast pill.
  static const broadcastSample = 6;

  final selected = 0.obs;

  void select(int index) => selected.value = index;
}
