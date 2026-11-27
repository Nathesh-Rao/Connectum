import 'package:connectum/core/theme/app_theme.dart';
import 'package:connectum/core/utils/qr_share_service.dart';
import 'package:connectum/core/widgets/app_confirm_dialog.dart';
import 'package:connectum/data/repositories/qr_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/qr/models/qr_models.dart';
import 'package:connectum/features/qr/qr_controller.dart';
import 'package:connectum/features/qr/qr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _answer = {
  'person': {
    'code': 'KVZDHDQD',
    'display': 'KVZD-HDQD',
    'payload': 'p1',
    'name': 'Ana',
    'username': 'ana',
  },
};

QrController _controller({
  required Future<Map<String, dynamic>> Function() rotate,
  required List<String> calls,
}) => QrController(
  repository: QrRepository.from(() async {
    calls.add('my');
    return _answer;
  }, rotate: rotate),
  share: QrShareService(),
);

void main() {
  test(
    'regenerate calls connect.rotate once, then loads the codes again',
    () async {
      final calls = <String>[];
      final c = _controller(
        calls: calls,
        rotate: () async {
          calls.add('rotate');
          return {};
        },
      );
      await c.load();
      await c.regenerate();
      expect(calls, ['my', 'rotate', 'my']);
      expect(c.isRegenerating.value, isFalse);
      expect(QrController.regenerated, 'Your QR code has been regenerated.');
    },
  );

  test('a double tap runs it once', () async {
    final calls = <String>[];
    final c = _controller(
      calls: calls,
      rotate: () async {
        calls.add('rotate');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return {};
      },
    );
    await c.load();
    await Future.wait([c.regenerate(), c.regenerate()]);
    expect(calls.where((x) => x == 'rotate'), hasLength(1));
  });

  test('a failure keeps the old code on screen and resets the flag', () async {
    final calls = <String>[];
    final c = _controller(
      calls: calls,
      rotate: () async => throw const SocketCallError('error', 'No way.'),
    );
    await c.load();
    await c.regenerate();
    expect(calls, ['my']);
    expect(c.person.value, isNotNull);
    expect(c.isRegenerating.value, isFalse);
    expect(QrController.regenerateFailed, 'Could not regenerate the QR code.');
  });

  testWidgets('the button and the confirm dialog use the new words', (
    tester,
  ) async {
    Get.reset();
    Get.testMode = true;
    final calls = <String>[];
    final c = _controller(
      calls: calls,
      rotate: () async {
        calls.add('rotate');
        return {};
      },
    );
    Get.put(c);
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: QrView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rotate'), findsNothing);
    await tester.tap(find.text('Regenerate QR code'));
    await tester.pumpAndSettle();
    expect(find.byType(AppConfirmDialog), findsOneWidget);
    expect(find.text('Regenerate your QR code?'), findsOneWidget);
    expect(
      find.text(
        'Your current QR code and Connectum code will stop working. Anyone '
        'who saved or printed it will need the new one.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, ['my']);

    await tester.tap(find.text('Regenerate QR code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Regenerate'));
    await tester.pumpAndSettle();
    expect(calls, ['my', 'rotate', 'my']);
  });

  test('only the person code can be regenerated', () async {
    final c = _controller(calls: [], rotate: () async => {});
    await c.load();
    expect(c.canRegenerate, isTrue);
    c.selected.value = QrKind.organisation;
    expect(c.canRegenerate, isFalse);
  });
}
