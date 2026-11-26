import 'package:daily_sort/ui/perf.dart';
import 'package:daily_sort/ui/perf_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _Timed extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => PerfLog.time('board: draw', () {});
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

void main() {
  testWidgets('steps timed while drawing still show up in the panel', (tester) async {
    showPerformance.value = true;
    PerfLog.reset();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(children: [CustomPaint(painter: _Timed(), size: const Size(10, 10)), const PerfLogPanel()]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('board: draw'), findsOneWidget);
    showPerformance.value = false;
  });
}
