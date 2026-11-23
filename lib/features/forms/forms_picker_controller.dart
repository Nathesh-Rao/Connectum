import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/utils/link_launcher.dart';
import '../../core/utils/link_open_policy.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/form_option.dart';
import '../../data/models/link_target.dart';
import '../../data/repositories/form_options_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../home_shell/home_shell_controller.dart';
import '../home_shell/home_tab.dart';
import '../link_browser/models/link_browser_args.dart';
import 'form_icon_dictionary.dart';
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
    this.launcher = const LinkLauncher(),
    this.trustedHosts,
    this.cleartextHosts,
  });

  final LinkLauncher launcher;

  /// Hosts a link opens inside the app for; the app's own by default.
  final Set<String>? trustedHosts;
  final Set<String>? cleartextHosts;

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

  /// A link option is being resolved; taps meanwhile are ignored.
  final isLinkOpening = false.obs;

  /// Why the last link didn't open, shown in the sheet.
  final linkNotice = RxnString();

  /// The address to offer "Copy link" for when the phone couldn't open it.
  final linkToCopy = RxnString();

  bool get isOffline => connectivity.state.value == AppConnectivity.offline;

  /// Called when the sheet opens: refreshes the list when online.
  void prepare() {
    queryField.clear();
    query.value = '';
    linkNotice.value = null;
    linkToCopy.value = null;
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

  /// A form can be filled and a link opened; the rest are listed but
  /// unavailable here.
  bool isAvailable(FormOption o) => o.isForm || o.isLink;

  /// The category's own icon when it names a specific one, else the label
  /// dictionary, else the category default.
  IconData iconOf(FormOption o) {
    final name = options.categories[o.category]?.icon ?? '';
    final isSpecific = FormIcons.isSpecific(name);
    return FormIconDictionary.resolve(
      o.caption,
      explicit: isSpecific ? FormIcons.of(name) : null,
      fallback: o.isLink && !isSpecific ? Icons.link : FormIcons.of(name),
    );
  }

  /// Opens a link option: the server gives its address, then [LinkOpenPolicy]
  /// picks the in-app page or the phone's browser. [closeSheet] runs just
  /// before the in-app page opens; on a failure the sheet stays with a notice.
  Future<void> openLink(
    FormOption option, {
    required VoidCallback closeSheet,
  }) async {
    if (!option.isLink || isLinkOpening.value) return;
    linkNotice.value = null;
    linkToCopy.value = null;
    if (isOffline) {
      linkNotice.value = 'Links need a connection. Check it and try again.';
      return;
    }
    isLinkOpening.value = true;
    try {
      final LinkTarget target;
      try {
        target = await options.resolveLink(option.id);
      } on LinkOpenError catch (e) {
        linkNotice.value = e.message;
        return;
      }
      final mode = LinkOpenPolicy.decide(
        target.url,
        trustedHosts ?? LinkHosts.trusted,
        cleartextHosts: cleartextHosts ?? LinkHosts.cleartext,
      );
      switch (mode) {
        case LinkOpenMode.blocked:
          linkNotice.value = LinkOpenPolicy.blockedMessage;
        case LinkOpenMode.external:
          if (await launcher.openExternal(target.url)) {
            closeSheet();
          } else {
            linkNotice.value = "Couldn't open the browser.";
            linkToCopy.value = target.url;
          }
        case LinkOpenMode.inApp:
          closeSheet();
          await Get.toNamed<void>(
            AppRoutes.linkBrowser,
            arguments: LinkBrowserArgs(
              url: target.url,
              title: target.name.isEmpty ? option.caption : target.name,
            ),
          );
      }
    } finally {
      isLinkOpening.value = false;
    }
  }

  Future<void> copyLinkToClipboard() async {
    final url = linkToCopy.value;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    linkToCopy.value = null;
    linkNotice.value = 'Link copied';
  }

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
    shell?.select(HomeTab.submits);
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

  /// Known names other than the generic data-entry one every form shares.
  static bool isSpecific(String name) =>
      name.isNotEmpty &&
      name != 'edit_note' &&
      of(name) != Icons.description_outlined;

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
