import 'package:daily_sort/ui/warmup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('warming up text and emoji draws without errors', (tester) async {
    warmUpText();
    // The fonts finish loading, then the screen lays text out again once.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
