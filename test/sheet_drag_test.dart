import 'package:daily_sort/ui/sheets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> open(WidgetTester tester, Widget content) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => showCozySheet(context, content), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sheet closes when pulled down from its middle', (tester) async {
    await open(tester, const Column(children: [Text('Hello'), SizedBox(height: 200), Text('Body')]));
    expect(find.text('Body'), findsOneWidget);
    await tester.drag(find.text('Body'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('a short pull springs back', (tester) async {
    await open(tester, const Column(children: [Text('Hello'), SizedBox(height: 300), Text('Body')]));
    await tester.timedDrag(find.text('Body'), const Offset(0, 40), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('a tall sheet scrolls first, then closes from the top', (tester) async {
    await open(tester, Column(children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('Row $i'))]));
    final before = tester.getTopLeft(find.text('Row 5')).dy;
    await tester.drag(find.text('Row 5'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Row 5')).dy, lessThan(before - 300)); // scrolled, still open
    await tester.timedDrag(find.text('Row 10'), const Offset(0, 1400), const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Row 10'), findsNothing);
  });

  testWidgets('sideways drags never move the sheet', (tester) async {
    await open(tester, const Column(children: [Text('Hello'), SizedBox(height: 200), Text('Body')]));
    await tester.drag(find.text('Body'), const Offset(300, 30));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
  });
}
