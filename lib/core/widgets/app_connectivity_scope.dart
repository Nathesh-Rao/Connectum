import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../data/socket/connectivity_service.dart';

class AppConnectivityScope extends InheritedWidget {
  const AppConnectivityScope({
    super.key,
    required this.state,
    required super.child,
  });

  final Rx<AppConnectivity> state;

  static Rx<AppConnectivity>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppConnectivityScope>()?.state;

  @override
  bool updateShouldNotify(AppConnectivityScope oldWidget) =>
      state != oldWidget.state;
}
