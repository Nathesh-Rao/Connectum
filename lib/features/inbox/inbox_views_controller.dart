import 'dart:async';

import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../data/repositories/inbox_views_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'models/inbox_saved_view.dart';

/// What the person answers to "Save your changes?".
enum UnsavedChoice { save, discard, cancel }

/// The question "Save your changes?" waiting for an answer. The view shows
/// the dialog and calls [reply]; the controller waits on [answer].
class UnsavedPrompt {
  final _done = Completer<UnsavedChoice>();

  Future<UnsavedChoice> get answer => _done.future;

  void reply(UnsavedChoice choice) {
    if (!_done.isCompleted) _done.complete(choice);
  }
}

/// The saved views of the Inbox: the list ([InboxViewsRepository]), which
/// view is open, and the setup it was opened or last saved with (the "changed"
/// test). Owned by `InboxController`, which applies a view to the filter.
class InboxViews extends GetxController {
  InboxViews({required this.repo, required this.connectivity});

  static const stillLoading =
      'Your views are still loading. Try again in a moment.';
  static const offlineNote = 'You are offline. Views cannot be changed now.';
  static const busy = 'Another change is still being saved.';
  static const loadError = 'Your views could not be read.';
  static const saveError = 'The view could not be saved.';
  static const removeError = 'That could not be removed.';
  static const defaultError = 'The default could not be changed.';
  static const noConnection =
      'There is no connection. Try again when you are online.';

  final InboxViewsRepository repo;
  final ConnectivityService connectivity;

  /// The open view's name; '' is the Default View.
  final current = ''.obs;

  /// The setup as the open view was opened or last saved, as a key.
  final kept = ''.obs;

  /// The map of the open view (what the phone does not model rides along).
  Map<String, dynamic> base = const {};

  /// A call is in flight: no second one starts.
  final isBusy = false.obs;

  /// Why the last action of the sheet failed ('' when it did not).
  final problem = ''.obs;

  bool get isOffline => connectivity.state.value != AppConnectivity.online;

  bool get isReady => repo.isReady.value;

  bool get hasLoadError => repo.hasError.value;

  String get openName =>
      current.value.isEmpty ? InboxViewLimits.defaultName : current.value;

  String? get defaultName => repo.defaultName.value;

  /// The Default View first, then the named views by name.
  List<String> get names => [
    InboxViewLimits.defaultName,
    for (final v in repo.views)
      if (v.name != InboxViewLimits.defaultName) v.name,
  ];

  InboxSavedView? saved(String name) {
    for (final v in repo.views) {
      if (v.name == name) return v;
    }
    return null;
  }

  /// The view the Inbox opens on when it is shown first (the web's
  /// `openFirstOf`): the one saved last, which the server keeps as `default`
  /// (every Save view and Save as new view sets it), else the Default View
  /// when it was saved; none when neither is there (the plain list). A
  /// `default` naming a view that is gone is no choice.
  InboxSavedView? get startView =>
      (defaultName == null ? null : saved(defaultName!)) ??
      saved(InboxViewLimits.defaultName);

  /// Is the open view the one the Inbox opens on? (Set as default / Clear.)
  bool get isOpenDefault =>
      current.value.isNotEmpty && defaultName == current.value;

  /// Remembers [name] ('' or the Default View's name for the Default View)
  /// as the open view with [setup] as its kept setup.
  void open(String name, Map<String, dynamic> setup, String key) {
    current.value = name == InboxViewLimits.defaultName ? '' : name;
    base = setup;
    kept.value = key;
    problem.value = '';
  }

  /// Reads the list; false when it failed (the old list stays).
  Future<bool> load() async {
    try {
      await repo.load();
      return true;
    } on SocketCallError catch (e) {
      AppLog.w('inbox_views', 'views not read: ${e.code}');
      return false;
    }
  }

  /// Saves [setup] under [name]. '' when it worked, else the text to show.
  Future<String> persist(
    String name,
    Map<String, dynamic> setup, {
    bool isNew = false,
    bool isDefault = false,
  }) => _run(
    saveError,
    () => repo.save(name, setup, isNew: isNew, isDefault: isDefault),
  );

  Future<String> remove(String name) =>
      _run(removeError, () => repo.delete(name));

  Future<String> setDefault(String? name) =>
      _run(defaultError, () => repo.setDefault(name));

  Future<String> _run(String fallback, Future<Object?> Function() call) async {
    if (isBusy.value) return busy;
    isBusy.value = true;
    problem.value = '';
    try {
      await call();
      return '';
    } on InboxViewError catch (e) {
      problem.value = e.message;
    } on SocketCallError catch (e) {
      AppLog.w('inbox_views', 'refused: ${e.code}');
      problem.value = e.isConnectionGap
          ? noConnection
          : InboxViewsRepository.messageOf(e, fallback);
    } finally {
      isBusy.value = false;
    }
    return problem.value;
  }

  /// Another person or organisation: nothing of the last one stays.
  void onSession(String plainKey) {
    current.value = '';
    base = const {};
    kept.value = plainKey;
    problem.value = '';
    isBusy.value = false;
  }
}
