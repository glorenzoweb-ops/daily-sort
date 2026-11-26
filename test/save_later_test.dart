import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/game_controller.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/perf.dart';
import 'package:daily_sort/ui/perf_log.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('moves are saved once the board is quiet, not during the pour', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Storage.open();
    final p = puzzleForDay(dayForNumber(3));
    final g = GameController(p, s);
    GameController.saveDelay = const Duration(milliseconds: 50);
    final m = g.board.legalMoves().first;
    g.tap(m.from);
    g.tap(m.to);
    expect(s.day(p.number)?.moves ?? const [], isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(s.day(p.number)!.moves, hasLength(1));
  });

  test('leaving the app saves what is waiting', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Storage.open();
    final p = puzzleForDay(dayForNumber(4));
    final g = GameController(p, s);
    GameController.saveDelay = const Duration(seconds: 30);
    final m = g.board.legalMoves().first;
    g.tap(m.from);
    g.tap(m.to);
    GameController.flushAll();
    expect(s.day(p.number)!.moves, hasLength(1));
  });

  testWidgets('the timing panel lists the slowest steps', (tester) async {
    showPerformance.value = true;
    PerfLog.record('sound: clink', 2.5);
    PerfLog.record('sound: clink', 1.0);
    PerfLog.record('haptic: medium (on iPhone)', 12.0);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: PerfLogPanel())));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('2.5  sound: clink'), findsOneWidget);
    expect(find.textContaining('haptic: medium'), findsOneWidget);
    await tester.tap(find.textContaining('Slowest'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('sound: clink'), findsNothing);
    showPerformance.value = false;
  });
}
