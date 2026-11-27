import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final thumb = find.byKey(const ValueKey('inbox-tab-thumb'));

  Future<InboxRig> start(WidgetTester t) async {
    final rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) => queryReply([record(1), record(2)]);
    Get.put(rig.controller);
    addTearDown(Get.reset);
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    return rig;
  }

  // The Home shell keeps every visited tab in a Stack. A tab that is built
  // for the first time shifts the others, so an Inbox view can be mounted
  // while its old copy is still alive for the rest of the frame.
  testWidgets('two Inbox views alive at once do not throw', (t) async {
    final rig = await start(t);
    Widget app(List<Widget> layers) => MaterialApp(
      home: Scaffold(body: Stack(children: layers)),
    );
    await t.pumpWidget(app(const [InboxView(key: ValueKey('a'))]));
    await settle(t);
    await t.pumpWidget(
      app(const [InboxView(key: ValueKey('a')), InboxView(key: ValueKey('b'))]),
    );
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.byType(PageView), findsNWidgets(2));
    rig.controller.selectTab(1);
    await settle(t);
    expect(t.takeException(), isNull);
    await t.pumpWidget(app(const [InboxView(key: ValueKey('b'))]));
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('re-mounting the view keeps the tab and the thumb', (t) async {
    final rig = await start(t);
    await t.pumpWidget(const MaterialApp(home: InboxView(key: ValueKey(1))));
    await settle(t);
    await t.tap(find.text('Approvals').first);
    await settle(t);
    final at = t.getRect(thumb).left;
    await t.pumpWidget(const MaterialApp(home: InboxView(key: ValueKey(2))));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(rig.controller.tabIndex.value, 1);
    expect(t.getRect(thumb).left, closeTo(at, 0.5));
    await t.drag(find.byType(PageView), const Offset(320, 0));
    await settle(t);
    expect(rig.controller.tabIndex.value, 0);
    expect(t.getRect(thumb).left, lessThan(at - 100));
  });
}

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
