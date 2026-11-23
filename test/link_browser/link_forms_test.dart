import 'package:connectum/data/models/form_option.dart';
import 'package:connectum/data/models/link_target.dart';
import 'package:connectum/data/repositories/form_options_repository.dart';
import 'package:connectum/data/socket/connectivity_service.dart';
import 'package:connectum/core/utils/link_launcher.dart';
import 'package:connectum/features/forms/forms_picker_controller.dart';
import 'package:connectum/features/forms/widgets/form_chip.dart';
import 'package:connectum/features/forms/widgets/forms_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Options implements FormOptionsRepository {
  _Options(this.url, {this.error});

  final String url;
  final LinkOpenError? error;
  int resolved = 0;

  @override
  final options = <FormOption>[].obs;
  @override
  final categories = <String, FormCategory>{}.obs;
  @override
  final recents = <FormRecent>[].obs;
  @override
  final isLoaded = true.obs;
  @override
  final hasError = false.obs;
  @override
  Future<void> refresh() async {}
  @override
  Future<LinkTarget> resolveLink(String optionId) async {
    resolved++;
    if (error != null) throw error!;
    return LinkTarget(url: url, name: 'Timesheet');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Online implements ConnectivityService {
  @override
  final state = AppConnectivity.online.obs;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

FormOption _link(String caption) => FormOption(
  id: 'id-$caption',
  caption: caption,
  type: 'link',
  target: 'link-id',
  targetScope: '',
  category: 'link',
  order: 0,
);

FormOption _unsupported(String caption) => FormOption(
  id: 'id-$caption',
  caption: caption,
  type: 'axpert_iview',
  target: 'x',
  targetScope: '',
  category: 'axpert',
  order: 1,
);

Future<(FormsPickerController, List<String>)> _open(
  WidgetTester tester,
  _Options repo, {
  bool isLaunchOk = true,
}) async {
  repo.options.assignAll([_link('Test link'), _unsupported('Old screen')]);
  final launched = <String>[];
  final c = FormsPickerController(
    options: repo,
    connectivity: _Online(),
    shell: null,
    launcher: LinkLauncher(
      launch: (uri) async {
        launched.add(uri.toString());
        return isLaunchOk;
      },
    ),
    trustedHosts: const {'connectum.app'},
    cleartextHosts: const {},
  );
  await tester.pumpWidget(
    GetMaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => FormsPickerSheet.show(context, c),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (c, launched);
}

void main() {
  testWidgets('a link option is a normal chip with the link icon', (
    tester,
  ) async {
    await _open(tester, _Options('https://example.org/x'));
    final chip = tester.widget<FormChip>(
      find.widgetWithText(FormChip, 'Test link'),
    );
    expect(chip.onTap, isNotNull);
    expect(chip.icon, Icons.link);
    expect(find.text('Not available on mobile yet'), findsOneWidget);
    final other = tester.widget<FormChip>(
      find.widgetWithText(FormChip, 'Old screen'),
    );
    expect(other.onTap, isNull);
    expect(find.text('1 form'), findsOneWidget);
  });

  testWidgets('a third-party link goes to the phone browser', (tester) async {
    final repo = _Options('https://example.org/x?call.key=abc');
    final (_, launched) = await _open(tester, repo);
    await tester.tap(find.text('Test link'));
    await tester.pumpAndSettle();
    expect(repo.resolved, 1);
    expect(launched, ['https://example.org/x?call.key=abc']);
    expect(find.byType(FormsPickerSheet), findsNothing);
  });

  testWidgets('a blocked address stays in the sheet with a notice', (
    tester,
  ) async {
    final repo = _Options('javascript:alert(1)');
    final (c, launched) = await _open(tester, repo);
    await tester.tap(find.text('Test link'));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(
      find.text("This link can't be opened from the app."),
      findsOneWidget,
    );
    expect(c.isLinkOpening.value, isFalse);
  });

  testWidgets('a failed launch offers Copy link', (tester) async {
    final repo = _Options('https://example.org/x');
    await _open(tester, repo, isLaunchOk: false);
    await tester.tap(find.text('Test link'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open the browser."), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('a server refusal shows its words and resets the flag', (
    tester,
  ) async {
    final repo = _Options(
      '',
      error: const LinkOpenError("You don't have access to that link."),
    );
    final (c, _) = await _open(tester, repo);
    await tester.tap(find.text('Test link'));
    await tester.pumpAndSettle();
    expect(find.text("You don't have access to that link."), findsOneWidget);
    expect(c.isLinkOpening.value, isFalse);
  });
}
