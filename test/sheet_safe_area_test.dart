import 'package:daily_sort/ui/sheets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a tall sheet stays below the Dynamic Island', (tester) async {
    // iPhone 15-like screen: 59 pt status bar with the Dynamic Island.
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const Scaffold();
          },
        ),
      ),
    );
    showCozySheet<void>(ctx, const SizedBox(key: Key('tall'), height: 3000));
    await tester.pumpAndSettle();

    final scroll = find.ancestor(of: find.byKey(const Key('tall')), matching: find.byType(SingleChildScrollView));
    expect(tester.getTopLeft(scroll).dy, greaterThanOrEqualTo(59));
  });
}
