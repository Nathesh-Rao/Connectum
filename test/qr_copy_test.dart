import 'package:connectum/core/utils/qr_share_service.dart';
import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/core/widgets/app_qr_share_card.dart';
import 'package:connectum/data/repositories/qr_repository.dart';
import 'package:connectum/features/qr/models/qr_models.dart';
import 'package:connectum/features/qr/qr_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _person = {
  'code': 'KVZDHDQD',
  'display': 'KVZD-HDQD',
  'payload': 'p1',
  'name': 'Ana Fake',
  'username': 'ana',
};

const _enterprise = {
  'code': '7454YKKJ',
  'display': '7454-YKKJ',
  'payload': 'p2',
  'name': 'Sri Ganesh Clinic',
  'setupDone': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final copied = <String>[];
  setUp(() {
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  Future<QrController> controller(QrKind kind) async {
    final c = QrController(
      repository: QrRepository.from(
        () async => {
          'person': _person,
          'enterprise': _enterprise,
          'branches': [
            {'name': 'Madurai', 'payload': 'p3'},
          ],
        },
      ),
      share: QrShareService(),
      initialKind: kind,
    );
    await c.load();
    return c;
  }

  test('My QR copies the person code as shown', () async {
    final c = await controller(QrKind.person);
    await c.copyCode();
    expect(copied, ['KVZD-HDQD']);
  });

  test(
    'Organisation QR copies the organisation code, with a branch too',
    () async {
      final c = await controller(QrKind.organisation);
      await c.copyCode();
      c.selectBranch(c.branches.first);
      await c.copyCode();
      expect(copied, ['7454-YKKJ', '7454-YKKJ']);
    },
  );

  const data = QrCardData(
    kind: QrKind.person,
    name: 'Ana',
    display: 'KVZD-HDQD',
    payload: 'p1',
  );

  testWidgets('tapping the code calls copy; Semantics says Copy code', (
    t,
  ) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppQrShareCard(data: data, width: 320, onCopy: () => taps++),
        ),
      ),
    );
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Copy code'), findsOneWidget);
    await t.tap(find.text('KVZD-HDQD'));
    expect(taps, 1);
  });

  testWidgets('the exported card has no copy icon or tap area', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AppQrShareFrame(data: data)),
        ),
      ),
    );
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    expect(find.bySemanticsLabel('Copy code'), findsNothing);
    final card = t.widget<AppQrShareCard>(find.byType(AppQrShareCard));
    expect(card.isExporting, isTrue);
  });

  test('notice host is untouched by the copy', () {
    expect(AppNotices.success, isNotNull);
  });
}
