import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../config/app_config.dart';
import '../../features/link_browser/link_browser_binding.dart';
import '../../features/link_browser/link_browser_view.dart';
import '../../features/authentication/authentication_binding.dart';
import '../../features/authentication/authentication_view.dart';
import '../../features/chat_info/chat_info_binding.dart';
import '../../features/chat_info/chat_info_view.dart';
import '../../features/conversation/conversation_binding.dart';
import '../../features/conversation/conversation_view.dart';
import '../../features/debug_ai/debug_ai_binding.dart';
import '../../features/debug_photo_crop/debug_photo_crop_binding.dart';
import '../../features/debug_crashtest/debug_crashtest_binding.dart';
import '../../features/debug_crashtest/debug_crashtest_view.dart';
import '../../features/debug_refresh/debug_refresh_binding.dart';
import '../../features/debug_refresh/debug_refresh_view.dart';
import '../../features/debug_photo_crop/debug_photo_crop_view.dart';
import '../../features/profile_photo/profile_photo_crop_binding.dart';
import '../../features/profile_photo/profile_photo_crop_view.dart';
import '../../features/debug_ai/debug_ai_view.dart';
import '../../features/debug_assets/debug_assets_binding.dart';
import '../../features/debug_chat/debug_chat_binding.dart';
import '../../features/debug_commands/debug_commands_binding.dart';
import '../../features/debug_commands/debug_commands_view.dart';
import '../../features/debug_notifications/debug_notifications_binding.dart';
import '../../features/debug_notifications/debug_notifications_view.dart';
import '../../features/debug_chat/debug_chat_view.dart';
import '../../features/debug_assets/debug_assets_view.dart';
import '../../features/debug_connect/debug_connect_binding.dart';
import '../../features/debug_connect/debug_connect_view.dart';
import '../../features/debug_e2e/debug_e2e_binding.dart';
import '../../features/debug_e2e/debug_e2e_view.dart';
import '../../features/debug_forms/debug_forms_binding.dart';
import '../../features/debug_forms/debug_forms_view.dart';
import '../../features/debug_formlogic/debug_formlogic_binding.dart';
import '../../features/debug_formlogic/debug_formlogic_view.dart';
import '../../features/debug_auth/debug_auth_binding.dart';
import '../../features/debug_auth/debug_auth_view.dart';
import '../../features/debug_decor/debug_decor_binding.dart';
import '../../features/debug_decor/debug_decor_view.dart';
import '../../features/debug_onboarding/debug_onboarding_binding.dart';
import '../../features/debug_onboarding/debug_onboarding_view.dart';
import '../../features/debug_onboarding_anim/debug_onboarding_anim_binding.dart';
import '../../features/debug_onboarding_anim/debug_onboarding_anim_view.dart';
import '../../features/debug_logo_intro/debug_logo_intro_binding.dart';
import '../../features/debug_logo_intro/debug_logo_intro_view.dart';
import '../../features/debug_palette/debug_palette_binding.dart';
import '../../features/debug_palette/debug_palette_view.dart';
import '../../features/debug_qr/debug_qr_binding.dart';
import '../../features/debug_qr/debug_qr_view.dart';
import '../../features/debug_socket/debug_socket_binding.dart';
import '../../features/debug_tasks/debug_tasks_binding.dart';
import '../../features/debug_tasks/debug_tasks_view.dart';
import '../../features/debug_smart_drawer/debug_smart_drawer_binding.dart';
import '../../features/debug_smart_drawer/debug_smart_drawer_view.dart';
import '../../features/debug_smart_insights/debug_smart_insights_binding.dart';
import '../../features/debug_smart_insights/debug_smart_insights_view.dart';
import '../../features/debug_smart_files/debug_smart_files_binding.dart';
import '../../features/debug_smart_files/debug_smart_files_view.dart';
import '../../features/debug_smart_query/debug_smart_query_binding.dart';
import '../../features/debug_smart_views/debug_smart_views_binding.dart';
import '../../features/debug_smart_views/debug_smart_views_view.dart';
import '../../features/debug_smart_query/debug_smart_query_view.dart';
import '../../features/debug_smart_table/debug_smart_table_binding.dart';
import '../../features/debug_smart_table/debug_smart_table_view.dart';
import '../../features/debug_smart_view/debug_smart_view_binding.dart';
import '../../features/debug_smart_view/debug_smart_view_view.dart';
import '../../features/debug_tickets/debug_tickets_binding.dart';
import '../../features/debug_tickets/debug_tickets_view.dart';
import '../../features/debug_socket/debug_socket_view.dart';
import '../../features/enterprise_created/enterprise_created_binding.dart';
import '../../features/enterprise_created/enterprise_created_view.dart';
import '../../features/enterprises/enterprises_binding.dart';
import '../../features/enterprises/enterprises_view.dart';
import '../../features/forms/form_binding.dart';
import '../../features/forms/form_view.dart';
import '../../features/forms/models/form_launch.dart';
import '../../features/gallery/gallery_auth_binding.dart';
import '../../features/home_shell/home_shell_binding.dart';
import '../../features/home_shell/home_shell_controller.dart';
import '../../features/home_shell/home_shell_view.dart';
import '../../features/gallery/gallery_auth_view.dart';
import '../../features/gallery/gallery_binding.dart';
import '../../features/gallery/gallery_view.dart';
import '../../features/new_group/new_group_binding.dart';
import '../../features/new_group/new_group_view.dart';
import '../../features/notifications/notifications_binding.dart';
import '../../features/notifications/notifications_view.dart';
import '../../features/onboarding/onboarding_binding.dart';
import '../../features/onboarding/onboarding_view.dart';
import '../../features/security/security_binding.dart';
import '../../features/security/security_view.dart';
import '../../features/splash/splash_binding.dart';
import '../../features/splash/splash_view.dart';
import '../../features/struct_records/struct_records_binding.dart';
import '../../features/struct_records/struct_records_view.dart';
import '../../features/submission_detail/submission_detail_binding.dart';
import '../../features/tasks/tasks_binding.dart';
import '../../features/tasks/tasks_view.dart';
import '../../features/tickets/ticket_detail_binding.dart';
import '../../features/tickets/record_detail_view.dart';
import '../../features/submission_detail/submission_detail_view.dart';
import '../../features/verification/verification_binding.dart';
import '../../features/profile/profile_binding.dart';
import '../../features/profile/profile_view.dart';
import '../../features/log_viewer/log_viewer_binding.dart';
import '../../features/log_viewer/log_viewer_view.dart';
import '../../features/workspace/workspace_binding.dart';
import '../../features/workspace/workspace_view.dart';
import '../../features/verification/verification_view.dart';
import 'app_routes.dart';
import 'app_transitions.dart';

class AppPages {
  AppPages._();

  /// The route table. Release builds get only the app's own routes; `/gallery`
  /// and every `/debug/*` route exist outside release (`isRelease` is injected
  /// by tests; the default is the compile-time `kReleaseMode`).
  static List<GetPage<dynamic>> build({bool isRelease = kReleaseMode}) => [
    ..._core(),
    if (!isRelease) ..._debug(),
  ];

  /// `START_ROUTE` is honoured outside release only.
  static String initialFor({
    bool isRelease = kReleaseMode,
    String startRoute = AppConfig.startRoute,
  }) => !isRelease && startRoute.isNotEmpty ? startRoute : AppRoutes.splash;

  static String get initial =>
      kReleaseMode ? AppRoutes.splash : initialFor(isRelease: false);

  static final pages = kReleaseMode ? _core() : build(isRelease: false);

  static GetPage<dynamic> _page(
    String name,
    GetPageBuilder page,
    Bindings binding,
    AppTransitionKind kind,
  ) {
    final transition = AppTransition(kind);
    return GetPage(
      name: name,
      page: page,
      binding: binding,
      customTransition: transition,
      transitionDuration: transition.duration,
      opaque: kind != AppTransitionKind.slideUp,
    );
  }

  static GetPage<dynamic> _authenticationPage() {
    final binding = AuthenticationBinding();
    return _page(
      AppRoutes.authentication,
      () => AuthenticationView(controllerTag: binding.tag),
      binding,
      AppTransitionKind.push,
    );
  }

  static List<GetPage<dynamic>> _core() => <GetPage<dynamic>>[
    _page(
      AppRoutes.splash,
      () => const SplashView(),
      SplashBinding(),
      AppTransitionKind.fade,
    ),
    _page(
      AppRoutes.onboarding,
      () => const OnboardingView(),
      OnboardingBinding(),
      AppTransitionKind.intro,
    ),
    _authenticationPage(),
    _page(
      AppRoutes.verification,
      () => const VerificationView(),
      VerificationBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.enterprises,
      () => const EnterprisesView(),
      EnterprisesBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.enterpriseCreated,
      () => const EnterpriseCreatedView(),
      EnterpriseCreatedBinding(),
      AppTransitionKind.enter,
    ),
    for (final route in HomeShellController.tabRoutes)
      _page(
        route,
        () => const HomeShellView(),
        HomeShellBinding(),
        AppTransitionKind.enter,
      ),
    _page(
      AppRoutes.conversation,
      () => ConversationView(
        conversationId: Uri.decodeComponent(Get.parameters['id'] ?? ''),
      ),
      ConversationBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.chatInfo,
      () => ChatInfoView(
        conversationId: Uri.decodeComponent(Get.parameters['id'] ?? ''),
      ),
      ChatInfoBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.newGroup,
      () => const NewGroupView(),
      NewGroupBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.submissionDetail,
      () => SubmissionDetailView(
        submissionId: Uri.decodeComponent(Get.parameters['id'] ?? ''),
      ),
      SubmissionDetailBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.structRecords,
      () => const StructRecordsView(),
      StructRecordsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.linkBrowser,
      () => const LinkBrowserView(),
      LinkBrowserBinding(),
      AppTransitionKind.slideUp,
    ),
    _page(
      AppRoutes.form,
      () => FormView(launch: Get.arguments as FormLaunch),
      FormBinding(),
      AppTransitionKind.slideUp,
    ),
    _page(
      AppRoutes.profile,
      () => const ProfileView(),
      ProfileBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.logViewer,
      () => const LogViewerView(),
      LogViewerBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.workspace,
      () => const WorkspaceView(),
      WorkspaceBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.notifications,
      () => const NotificationsView(),
      NotificationsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.tasks,
      () => const TasksView(),
      TasksBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.ticket,
      () => const RecordDetailView(),
      TicketDetailBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.security,
      () => const SecurityView(),
      SecurityBinding(),
      AppTransitionKind.push,
    ),
  ];

  static List<GetPage<dynamic>> _debug() => <GetPage<dynamic>>[
    _page(
      AppRoutes.gallery,
      () => const GalleryView(),
      GalleryBinding(),
      AppTransitionKind.fade,
    ),
    _page(
      AppRoutes.galleryAuth,
      () => const GalleryAuthView(),
      GalleryAuthBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugNotifications,
      () => const DebugNotificationsView(),
      DebugNotificationsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugCommands,
      () => const DebugCommandsView(),
      DebugCommandsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugRefresh,
      () => const DebugRefreshView(),
      DebugRefreshBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugCrashTest,
      () => const DebugCrashTestView(),
      DebugCrashTestBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.photoCrop,
      () => const ProfilePhotoCropView(),
      ProfilePhotoCropBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugPhotoCrop,
      () => const DebugPhotoCropView(),
      DebugPhotoCropBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugAi,
      () => const DebugAiView(),
      DebugAiBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSmartInsights,
      () => const DebugSmartInsightsView(),
      DebugSmartInsightsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSmartViews,
      () => const DebugSmartViewsView(),
      DebugSmartViewsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSmartQuery,
      () => const DebugSmartQueryView(),
      DebugSmartQueryBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSmartFiles,
      () => const DebugSmartFilesView(),
      DebugSmartFilesBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSmartDrawer,
      () => const DebugSmartDrawerView(),
      DebugSmartDrawerBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSmartView,
      () => const DebugSmartViewView(),
      DebugSmartViewBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSmartTable,
      () => const DebugSmartTableView(),
      DebugSmartTableBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugTickets,
      () => const DebugTicketsView(),
      DebugTicketsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugTasks,
      () => const DebugTasksView(),
      DebugTasksBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugChat,
      () => const DebugChatView(),
      DebugChatBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugAssets,
      () => const DebugAssetsView(),
      DebugAssetsBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugSocket,
      () => const DebugSocketView(),
      DebugSocketBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugE2e,
      () => const DebugE2eView(),
      DebugE2eBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugFormLogic,
      () => const DebugFormLogicView(),
      DebugFormLogicBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugConnect,
      () => const DebugConnectView(),
      DebugConnectBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugLogoIntro,
      () => const DebugLogoIntroView(),
      DebugLogoIntroBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugPalette,
      () => const DebugPaletteView(),
      DebugPaletteBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugDecor,
      () => const DebugDecorView(),
      DebugDecorBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugOnboarding,
      () => const DebugOnboardingView(),
      DebugOnboardingBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugOnboardingAnim,
      () => const DebugOnboardingAnimView(),
      DebugOnboardingAnimBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugAuth,
      () => const DebugAuthView(),
      DebugAuthBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugQr,
      () => const DebugQrView(),
      DebugQrBinding(),
      AppTransitionKind.push,
    ),
    _page(
      AppRoutes.debugForms,
      () => const DebugFormsView(),
      DebugFormsBinding(),
      AppTransitionKind.push,
    ),
  ];
}
