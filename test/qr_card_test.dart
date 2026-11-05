import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectum/core/debug/seed_qr.dart';
import 'package:connectum/core/utils/qr_share_service.dart';
import 'package:connectum/features/qr/models/qr_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _person = {
  'code': 'KVZDHDQD',
  'display': 'KVZD-HDQD',
  'payload': 'https://x.example/connect/KVZDHDQD?org=7454YKKJ',
  'url': 'https://x.example/connect/KVZDHDQD?org=7454YKKJ',
  'name': 'Ana Fake',
  'username': 'ana',
};

Map<String, dynamic> _enterprise({Object? location, bool hasUrl = true}) => {
  'code': '7454YKKJ',
  'display': '7454-YKKJ',
  'payload': hasUrl
      ? 'https://x.example/connect/7454YKKJ'
      : 'connectum:7454YKKJ',
  'url': hasUrl ? 'https://x.example/connect/7454YKKJ' : null,
  'name': 'Sri Ganesh Clinic',
  'location': location,
  'categories': <String>[],
  'setupDone': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('connect.my parsing', () {
    test('with branches, keeps every payload as received', () {
      final codes = QrCodes.fromJson({
        'person': _person,
        'enterprise': _enterprise(
          location: {'city': 'Chennai', 'country': 'India'},
        ),
        'branches': [
          {
            'name': 'Café & Co',
            'city': 'Zürich',
            'payload':
                'https://x.example/connect/7454YKKJ?branch=Caf%C3%A9%20%26%20Co',
            'url':
                'https://x.example/connect/7454YKKJ?branch=Caf%C3%A9%20%26%20Co',
          },
          {'name': 'Madurai', 'city': null, 'payload': 'p2', 'url': null},
        ],
      });
      expect(codes.kinds, [QrKind.person, QrKind.organisation]);
      expect(codes.person!.payload, _person['payload']);
      expect(codes.person!.display, 'KVZD-HDQD');
      expect(codes.person!.organisation, _enterprise()['name']);
      expect(codes.organisation!.organisation, isNull);
      expect(codes.branches, hasLength(2));
      expect(
        codes.organisation!.withBranch(codes.branches.first).payload,
        codes.branches.first.payload,
      );
      expect(
        codes.organisation!.withBranch(codes.branches.first).display,
        '7454-YKKJ',
      );
      expect(
        codes.organisation!.withBranch(null).payload,
        _enterprise()['payload'],
      );
    });

    test('without branches, url null and location null', () {
      final codes = QrCodes.fromJson({
        'person': {
          ..._person,
          'payload': 'connectum:KVZDHDQD?org=7454YKKJ',
          'url': null,
        },
        'enterprise': _enterprise(hasUrl: false),
      });
      expect(codes.branches, isEmpty);
      expect(codes.person!.url, isNull);
      expect(codes.person!.payload, 'connectum:KVZDHDQD?org=7454YKKJ');
    });

    test('location with only a city, empty name falls back', () {
      final codes = QrCodes.fromJson({
        'person': _person,
        'enterprise': {
          ..._enterprise(location: {'city': 'Pune'}),
          'name': '',
        },
      });
      expect(codes.organisation!.name, 'Connectum Enterprise');
    });

    test('shows only the part that exists', () {
      expect(QrCodes.fromJson({'person': _person}).kinds, [QrKind.person]);
      final onlyOrg = QrCodes.fromJson({
        'enterprise': _enterprise(),
        'branches': [
          {'name': 'A', 'payload': 'p'},
        ],
      });
      expect(onlyOrg.kinds, [QrKind.organisation]);
      expect(QrCodes.fromJson({}).kinds, isEmpty);
    });
  });

  group('share text', () {
    final withUrl = QrCodes.fromJson({
      'person': _person,
      'enterprise': _enterprise(),
    });
    final withoutUrl = QrCodes.fromJson({
      'person': {
        ..._person,
        'payload': 'connectum:KVZDHDQD?org=7454YKKJ',
        'url': null,
      },
      'enterprise': _enterprise(hasUrl: false),
    });

    test('person with a url', () {
      expect(withUrl.person!.shareSubject, 'Connect with Ana Fake');
      expect(
        withUrl.person!.shareText,
        'Connect with me on Connectum using code KVZD-HDQD: '
        'https://x.example/connect/KVZDHDQD?org=7454YKKJ',
      );
    });

    test('person without a url uses the payload', () {
      expect(
        withoutUrl.person!.shareText,
        'Connect with me on Connectum using code KVZD-HDQD: '
        'connectum:KVZDHDQD?org=7454YKKJ',
      );
    });

    test('organisation with a url, and with a branch', () {
      expect(withUrl.organisation!.shareSubject, 'Join Sri Ganesh Clinic');
      expect(
        withUrl.organisation!.shareText,
        'Join Sri Ganesh Clinic on Connectum using code 7454-YKKJ: '
        'https://x.example/connect/7454YKKJ',
      );
      const branch = QrBranch(
        name: 'Madurai',
        payload: 'https://x.example/connect/7454YKKJ?branch=Madurai',
        url: 'https://x.example/connect/7454YKKJ?branch=Madurai',
      );
      expect(
        withUrl.organisation!.withBranch(branch).shareText,
        'Join Sri Ganesh Clinic on Connectum using code 7454-YKKJ: '
        'https://x.example/connect/7454YKKJ?branch=Madurai',
      );
    });

    test('organisation without a url uses the payload', () {
      expect(
        withoutUrl.organisation!.shareText,
        'Join Sri Ganesh Clinic on Connectum using code 7454-YKKJ: '
        'connectum:7454YKKJ',
      );
    });
  });

  test('branch option labels', () {
    expect(
      const QrBranch(name: 'Chennai Main', city: 'Chennai', payload: 'p').label,
      'Chennai Main · Chennai',
    );
    expect(const QrBranch(name: 'Madurai', payload: 'p').label, 'Madurai');
  });

  testWidgets('the sample renders to a 1080 px wide, non-empty PNG', (
    tester,
  ) async {
    final cases = <QrCardData>[];
    for (final scenario in [
      SeedQr.scenarios.first,
      SeedQr.scenarios[2],
      SeedQr.scenarios[4],
    ]) {
      final codes = QrCodes.fromJson(scenario.answer());
      cases.addAll([
        codes.person!,
        codes.organisation!.withBranch(
          codes.branches.isEmpty ? null : codes.branches.first,
        ),
      ]);
    }
    await tester.runAsync(() async {
      for (final data in cases) {
        final bytes = await QrShareService().render(data);
        expect(bytes.length, greaterThan(1000));
        final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1080);
        expect(frame.image.height, greaterThan(1080));
        frame.image.dispose();
      }
    });
  });

  test('file name is clear and safe', () {
    final data = QrCodes.fromJson({
      'enterprise': {..._enterprise(), 'name': 'Sri Ganesh Clinic!'},
    }).organisation!;
    expect(data.fileName, 'connectum-qr-sri-ganesh-clinic.png');
  });
}
