import 'package:get/get.dart';

import '../../data/ai/ai_models.dart';
import '../../data/ai/ai_repository.dart';
import '../../data/ai/ai_setup_cache.dart';
import '../../data/ai/fake_ai_repository.dart';
import '../../data/repositories/message_repository.dart' show SendResult;
import '../ai_chat/ai_summary_controller.dart';

/// Every state of the in-chat AI (an end-to-end chat is blocked) on the fake repository, or on the real one
/// with [useReal]; the real one reads the messages this phone holds for
/// `dm:ana` and asks the server.
class DebugAiController extends GetxController {
  DebugAiController(this.real);

  final AiRepository real;
  final fake = FakeAiRepository();
  final isE2e = false.obs;

  final isAdmin = false.obs;
  final isOffline = false.obs;
  final isStreaming = false.obs;
  final isReal = false.obs;

  /// A care thread of `ravi`: no range, `care.summary`, the truncated note.
  final isCare = false.obs;
  final isSendFailing = false.obs;

  /// Which care thread a typed question reads (team, patient, long,
  /// not_found), on the fake repository.
  final careThread = FakeCareThread.team.obs;

  /// What "Share in chat" posted, in place of a chat.
  final posted = <String>[].obs;
  final setupState = AiSetupState.ready.obs;
  final agentCount = 1.obs;
  final scenario = FakeAiScenario.markdown.obs;
  final failure = AiErrorKind.failed.obs;
  final setupFailure = Rxn<AiErrorKind>();

  late AiSummaryController summary = _build();

  AiSummaryController _build() {
    final ai = isReal.value ? real : fake;
    return AiSummaryController(
      ai: ai,
      setup: AiSetupCache(ai),
      chatId: 'dm:ana',
      title: () => isE2e.value ? 'Ana (encrypted)' : 'Ana',
      isEncrypted: () => isE2e.value,
      isOnline: () => !isOffline.value,
      post: (text) async {
        if (isSendFailing.value) return SendResult.invalid;
        posted.add(text);
        return SendResult.queued;
      },
      isAdmin: () => isAdmin.value,
      carePerson: isCare.value ? 'ravi' : null,
    );
  }

  /// A new controller, so the setup cache starts empty.
  void apply() {
    fake
      ..setup = AiSetup(
        setupState.value,
        agents: setupState.value == AiSetupState.ready
            ? [
                for (var i = 0; i < agentCount.value; i++)
                  AiAgent(
                    id: 'agent$i',
                    name: i == 0 ? 'Claude' : 'Agent ${i + 1}',
                    provider: 'anthropic',
                  ),
              ]
            : const [],
      )
      ..scenario = scenario.value
      ..care = careThread.value
      ..failure = failure.value
      ..setupFailure = setupFailure.value
      ..isStreaming = isStreaming.value;
    summary = _build();
  }

  void setSetup(AiSetupState value) {
    setupState.value = value;
    apply();
  }

  void setScenario(FakeAiScenario value) {
    scenario.value = value;
    apply();
  }

  void setFailure(AiErrorKind value) {
    failure.value = value;
    scenario.value = FakeAiScenario.failure;
    apply();
  }

  void toggleAgents() {
    agentCount.value = agentCount.value == 1 ? 3 : 1;
    apply();
  }

  void toggleSetupFailure() {
    setupFailure.value = setupFailure.value == null
        ? AiErrorKind.offline
        : null;
    apply();
  }

  void toggleReal() {
    isReal.toggle();
    apply();
  }

  void setCare(FakeCareThread value) {
    careThread.value = value;
    isCare.value = true;
    apply();
  }

  void toggleCare() {
    isCare.toggle();
    apply();
  }

  void toggleE2e() => isE2e.toggle();

  void toggleAdmin() => isAdmin.toggle();
  void toggleOffline() => isOffline.toggle();
  void toggleSendFailing() => isSendFailing.toggle();

  void toggleStreaming() {
    isStreaming.toggle();
    apply();
  }
}
