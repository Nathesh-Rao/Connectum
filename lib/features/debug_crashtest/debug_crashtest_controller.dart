import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/crash/crash_breadcrumbs.dart';
import '../../core/crash/crash_config.dart';
import '../../core/crash/crash_service.dart';

class DebugCrashTestController extends GetxController {
  DebugCrashTestController(this.service, {this.emailOf});

  final CrashService service;

  /// The signed-in email, only to show it masked.
  final String? Function()? emailOf;

  final crumbs = <String>[].obs;
  final isFatalConfirmOpen = false.obs;

  @override
  void onInit() {
    super.onInit();
    _refresh();
  }

  bool get isFirebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool get isEnabled => service.reporter.isEnabled;

  String get buildMode => kReleaseMode
      ? 'release'
      : kProfileMode
      ? 'profile'
      : 'debug';

  String get identityText {
    final email = emailOf?.call();
    if (email == null || email.isEmpty) return 'no';
    final head = email.length < 2 ? email : email.substring(0, 2);
    return 'yes ($head***)';
  }

  bool get isCollectionOn => isCrashCollectionOn;

  void _refresh() => crumbs.assignAll(service.recentCrumbs);

  void sendBreadcrumb() {
    CrashBreadcrumbs.add(Crumb.screen, code: 'crashtest');
    _refresh();
  }

  void recordNonFatal() {
    service.reporter.recordNonFatal(
      StateError('crash test non-fatal'),
      StackTrace.current,
      reason: 'debug crash test',
    );
  }

  void throwAsync() {
    Future<void>.delayed(
      Duration.zero,
      () => throw StateError('crash test unhandled async error'),
    );
  }

  void throwInCallback() {
    scheduleMicrotask(() {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('crash test Flutter callback error'),
        ),
      );
    });
  }

  void crashNative() => FirebaseCrashlytics.instance.crash();
}
