import 'package:connectum/core/errors/error_widget.dart';
import 'package:connectum/core/widgets/app_friendly_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final original = ErrorWidget.builder;
  tearDown(() => ErrorWidget.builder = original);

  testWidgets('release: friendly tile, no error text', (tester) async {
    installErrorWidget(isRelease: true);
    final details = FlutterErrorDetails(exception: Exception('secret trace'));
    await tester.pumpWidget(ErrorWidget.builder(details));
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Please try again.'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    ErrorWidget.builder = original;
  });

  test('debug keeps the default builder', () {
    installErrorWidget(isRelease: false);
    expect(identical(ErrorWidget.builder, original), isTrue);
    expect(
      ErrorWidget.builder(FlutterErrorDetails(exception: 'x')),
      isNot(isA<AppFriendlyError>()),
    );
  });
}
