import 'package:connectum/data/repositories/e2e_repository.dart';
import 'package:connectum/data/repositories/hand_on_repository.dart';
import 'package:connectum/data/session_store.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/hand_on/hand_on_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _E2e extends Fake implements E2eRepository {}

class _Socket extends Fake implements SocketService {}

class _Session extends Fake implements SessionStore {}

const _offer = HandOnOffer(id: 'd1', name: 'Tablet', ts: 1, isContinue: false);

void main() {
  late HandOnRepository hand;
  late HandOnController controller;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    hand = HandOnRepository(
      _E2e(),
      _Socket(),
      _Session(),
      call: (_, _) async => {},
    );
    controller = HandOnController(hand);
  });

  tearDown(() => controller.onClose());

  test('later with an offer set does not throw', () {
    hand.offer.value = _offer;
    hand.phase.value = HandOnPhase.offered;
    controller.onInit();
    expect(hand.later, returnsNormally);
    expect(hand.phase.value, HandOnPhase.idle);
  });

  test('the offered phase with no offer does not throw', () {
    hand.phase.value = HandOnPhase.offered;
    expect(controller.onInit, returnsNormally);
    // later clears the offer first, while the phase is still offered.
    hand.offer.value = _offer;
    expect(() => hand.offer.value = null, returnsNormally);
    expect(hand.later, returnsNormally);
  });
}
