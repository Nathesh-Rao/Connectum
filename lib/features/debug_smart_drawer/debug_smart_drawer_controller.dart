import 'package:get/get.dart';

/// A sandbox for [AppDrawerShell]: open and close it from code, by the menu
/// button and by the edge swipe, with sample rows and a horizontal strip in
/// the body to try the swipe against.
class DebugSmartDrawerController extends GetxController {
  static const views = [
    'Customer requests',
    'Leave requests',
    'Purchase orders',
    'Site visits',
    'Vendors',
  ];

  final isOpen = false.obs;
  final selected = 0.obs;

  void open() => isOpen.value = true;

  void close() => isOpen.value = false;

  void setOpen(bool value) => isOpen.value = value;

  void pick(int index) {
    selected.value = index;
    close();
  }
}
