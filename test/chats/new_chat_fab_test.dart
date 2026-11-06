import 'package:connectum/features/chats/models/new_chat_button_state.dart';
import 'package:connectum/features/chats/widgets/new_chat_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

bool _isExcluded(WidgetTester tester) => tester
    .widget<ExcludeSemantics>(
      find
          .descendant(
            of: find.byType(NewChatFab),
            matching: find.byType(ExcludeSemantics),
          )
          .first,
    )
    .excluding;

void main() {
  late NewChatButtonState state;
  var taps = 0;

  Widget host({int count = 60, bool isKeyboardOpen = false}) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: state.onScroll,
              child: ListView.builder(
                itemCount: count,
                itemBuilder: (_, i) => SizedBox(height: 80, child: Text('$i')),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: Obx(
                () => NewChatFab(
                  isShown: state.isShown.value,
                  isKeyboardOpen: isKeyboardOpen,
                  onPressed: () => taps++,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  setUp(() {
    state = NewChatButtonState();
    taps = 0;
  });

  final list = find.byType(ListView);

  testWidgets('visible at rest', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());
    expect(state.isShown.value, isTrue);
    expect(_isExcluded(tester), isFalse);
    handle.dispose();
  });

  testWidgets('hidden after a downward scroll, shown after an upward one', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(state.isShown.value, isFalse);
    await tester.drag(list, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(state.isShown.value, isTrue);
  });

  testWidgets('a tiny movement does not switch it', (tester) async {
    await tester.pumpWidget(host());
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 6));
    await tester.pumpAndSettle();
    expect(state.isShown.value, isFalse);
  });

  testWidgets('shown again back at the top', (tester) async {
    await tester.pumpWidget(host());
    await tester.drag(list, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(state.isShown.value, isFalse);
    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(state.isShown.value, isTrue);
  });

  testWidgets('shown on a list too short to scroll', (tester) async {
    await tester.pumpWidget(host(count: 3));
    await tester.drag(list, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(state.isShown.value, isTrue);
  });

  testWidgets('a flag write only happens when the value changes', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    var writes = 0;
    state.isShown.listen((_) => writes++);
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(writes, 1);
  });

  testWidgets('hidden while the keyboard is open', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(isKeyboardOpen: true));
    await tester.pumpAndSettle();
    expect(_isExcluded(tester), isTrue);
    await tester.tapAt(
      tester.getBottomRight(find.byType(Scaffold)) - const Offset(44, 44),
    );
    expect(taps, 0);
    handle.dispose();
  });

  testWidgets('not tappable when hidden, opens when shown', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.tap(find.byType(NewChatFab));
    expect(taps, 1);
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(NewChatFab), warnIfMissed: false);
    expect(taps, 1);
    expect(_isExcluded(tester), isTrue);
    handle.dispose();
  });

  testWidgets('is 56 square', (tester) async {
    await tester.pumpWidget(host());
    expect(tester.getSize(find.byType(NewChatFab)), const Size(56, 56));
  });
}
