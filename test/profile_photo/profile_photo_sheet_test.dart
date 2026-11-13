import 'package:connectum/data/profile_photo/profile_photo_picker.dart';
import 'package:connectum/features/profile/widgets/profile_photo_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool hasPhoto, required List<String> log}) =>
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => ProfilePhotoSheet(
                hasPhoto: hasPhoto,
                onPick: (s) => log.add(s.name),
                onRemove: () => log.add('remove'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('without a photo: take and choose only', (tester) async {
    await tester.pumpWidget(_host(hasPhoto: false, log: []));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Remove photo'), findsNothing);
  });

  testWidgets('with a photo: remove shows too', (tester) async {
    await tester.pumpWidget(_host(hasPhoto: true, log: []));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Remove photo'), findsOneWidget);
  });

  testWidgets('each row closes the sheet and reports its choice', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_host(hasPhoto: true, log: log));
    for (final (label, expected) in [
      ('Take photo', PhotoSource.camera.name),
      ('Choose from gallery', PhotoSource.gallery.name),
      ('Remove photo', 'remove'),
    ]) {
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(log.last, expected);
      expect(find.text(label), findsNothing);
    }
  });
}
