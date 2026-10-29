import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/form_option.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../home_shell/home_shell_controller.dart';
import 'models/form_launch.dart';

/// The sheet behind the forms button: search, the forms used lately, the
/// whole list, and My Submissions. One lives with each conversation (and the
/// workspace) that has a forms button.
class FormsPickerController extends GetxController {
  FormsPickerController({
    required this.options,
    required this.connectivity,
    required this.shell,
    this.convId,
    this.isEncrypted,
  });

  static const _submissionsTab = 2;

  final FormOptionsRepository options;
  final ConnectivityService connectivity;
  final HomeShellController? shell;

  /// The conversation a form opened from here posts into; null in the
  /// workspace.
  final String? convId;

  /// Whether that conversation is end-to-end encrypted, asked when a form is
  /// opened (the form screen says its message isn't encrypted).
  final bool Function()? isEncrypted;

  final queryField = TextEditingController();
  final query = ''.obs;

  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  /// Called when the sheet opens: refreshes the list when online.
  void prepare() {
    queryField.clear();
    query.value = '';
    options.refresh();
  }

  AppViewState get viewState {
    if (options.options.isNotEmpty) return AppViewState.content;
    if (!options.isLoaded.value) {
      if (options.hasError.value) return AppViewState.error;
      return isOffline ? AppViewState.offline : AppViewState.loading;
    }
    return AppViewState.empty;
  }

  bool matches(String text) {
    final q = query.value.trim().toLowerCase();
    return q.isEmpty || text.toLowerCase().contains(q);
  }

  /// Every option that matches the search, the ones that aren't forms too.
  List<FormOption> get shown => [
    for (final o in options.options)
      if (matches(o.caption)) o,
  ];

  List<FormRecent> get recents => [
    for (final r in options.recents)
      if (options.options.any((o) => o.isForm && o.target == r.name)) r,
  ];

  bool get showsMySubmissions => matches('My Submissions');

  /// A form can be filled when it is a data-entry option; the rest are
  /// listed but unavailable here.
  bool isAvailable(FormOption o) => o.isForm;

  IconData iconOf(FormOption o) =>
      FormIcons.of(options.categories[o.category]?.icon ?? '');

  void open(FormOption option) {
    if (!option.isForm) return;
    _launch(option.target, option.targetScope, option.caption);
  }

  void openRecent(FormRecent recent) =>
      _launch(recent.name, recent.scope, recent.caption);

  void _launch(String name, String scope, String caption) {
    Get.toNamed(
      AppRoutes.form,
      arguments: FormLaunch(
        name: name,
        scope: scope,
        caption: caption,
        convId: convId,
        isEncryptedChat: isEncrypted?.call() ?? false,
      ),
    );
  }

  /// Leaves the conversation and shows the Submissions tab of the home.
  void openMySubmissions() {
    Get.until((r) => HomeShellController.tabRoutes.contains(r.settings.name));
    shell?.select(_submissionsTab);
  }

  @override
  void onClose() {
    queryField.dispose();
    super.onClose();
  }
}

/// The category icons the server names, as Material icons.
class FormIcons {
  FormIcons._();

  static IconData of(String name) => switch (name) {
    'edit_note' => Icons.edit_note,
    'download' => Icons.download_outlined,
    'upload' => Icons.upload_outlined,
    'query_stats' => Icons.query_stats,
    'link' => Icons.link,
    'bolt' => Icons.bolt,
    'history' => Icons.history,
    _ => Icons.description_outlined,
  };
}
