class AppRoutes {
  AppRoutes._();

  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const authentication = '/authentication';
  static const verification = '/verification';
  static const enterprises = '/enterprises';
  static const enterpriseCreated = '/enterprise-created';
  static const chats = '/chats';
  static const aiAgents = '/ai-agents';
  static const conversation = '/conversation/:id';
  static const submissions = '/submissions';
  static const submissionDetail = '/submissions/:id';
  static const workspace = '/workspace';
  static const form = '/form';
  static const profile = '/profile';
  static const photoCrop = '/profile/photo-crop';
  static const notifications = '/notifications';
  static const security = '/security';
  static const newGroup = '/new-group';
  static const tasks = '/tasks';
  static const approvals = '/approvals';
  static const ticket = '/tickets/:id';
  static const chatInfo = '/chat-info/:id';

  static const gallery = '/gallery';
  static const galleryAuth = '/gallery/auth';
  static const debugSocket = '/debug/socket';
  static const debugAssets = '/debug/assets';
  static const debugE2e = '/debug/e2e';
  static const debugFormLogic = '/debug/formlogic';
  static const debugForms = '/debug/forms';
  static const debugConnect = '/debug/connect';
  static const debugQr = '/debug/qr';
  static const debugPalette = '/debug/palette';
  static const debugLogoIntro = '/debug/logo-intro';
  static const debugDecor = '/debug/decor';
  static const debugOnboarding = '/debug/onboarding';
  static const debugOnboardingAnim = '/debug/onboarding-anim';
  static const debugAuth = '/debug/auth';
  static const debugChat = '/debug/chat';
  static const debugNotifications = '/debug/notifications';
  static const debugTasks = '/debug/tasks';
  static const debugTickets = '/debug/tickets';
  static const debugCommands = '/debug/commands';
  static const debugAi = '/debug/ai';
  static const debugPhotoCrop = '/debug/photo-crop';

  static String ticketOf(int id) => '/tickets/$id';

  static String chatInfoOf(String conversationId) =>
      '/chat-info/${Uri.encodeComponent(conversationId)}';

  /// A conversation id holds `:` and a group name may hold spaces or `/`.
  static String conversationOf(String id) =>
      '/conversation/${Uri.encodeComponent(id)}';

  /// A submission's detail. [convId] and [msgId] name the form message it was
  /// opened from, which is where a submission that is not mine is read from.
  static String submissionDetailOf(
    String id, {
    String? convId,
    String? msgId,
  }) => Uri(
    path: '/submissions/${Uri.encodeComponent(id)}',
    queryParameters: {
      if (convId != null && msgId != null) ...{'conv': convId, 'msg': msgId},
    },
  ).toString();
}
