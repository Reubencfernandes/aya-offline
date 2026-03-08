import 'package:flutter_test/flutter_test.dart';
import 'package:aya_flutter/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const AyaApp());
    expect(find.text('Aya'), findsOneWidget);
  });
}
