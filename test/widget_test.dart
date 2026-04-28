import 'package:flutter_test/flutter_test.dart';
import 'package:scanorder/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ScanOrderApp());
    expect(find.text('ScanOrder'), findsAny);
  });
}
