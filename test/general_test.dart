import 'package:daily_sort/game/game_controller.dart';
import 'package:daily_sort/main.dart';
import 'package:daily_sort/services/analytics.dart';
import 'package:daily_sort/services/premium.dart';
import 'package:daily_sort/services/reminder_time.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/appearance.dart';
import 'package:daily_sort/ui/tutorial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  test('reminder rings around the usual solve time', () {
    expect(reminderMinute([]), 9 * 60);
    expect(reminderMinute([20 * 60 + 7]), 20 * 60);
    // The middle time, so one late night doesn't move it.
    expect(reminderMinute([8 * 60 + 40, 23 * 60 + 50, 8 * 60 + 20]), 8 * 60 + 30);
  });

  test('only the last 7 solve times are kept', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Storage.open();
    for (var i = 0; i < 10; i++) {
      await s.addPlayMinute(i);
    }
    expect(s.playMinutes, [3, 4, 5, 6, 7, 8, 9]);
  });

  test('the guided puzzle solves in its 3 moves and records nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Storage.open();
    final g = GameController(tutorialPuzzle(), s, tutorial: true);
    for (final m in g.puzzle.solution) {
      g.tap(m.from);
      g.tap(m.to);
    }
    expect(g.status, GameStatus.won);
    expect(s.stats.solved, 0);
    expect(s.playMinutes, isEmpty);
  });

  test('analytics stays quiet until started', () {
    expect(Analytics.on, isFalse);
    Analytics.send('Test.signal'); // nothing queued, nothing thrown
  });

  testWidgets('first Play opens the guided puzzle, Skip goes to today', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    await tester.pumpWidget(
      DailySortApp(storage: storage, premium: ComingSoonPremium(), appearance: Appearance(storage)),
    );
    await settle(tester);
    await tester.tap(find.text('Play'));
    await settle(tester);
    expect(find.text('Tap the first tube'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('Tap the first tube'), findsNothing);
    expect(find.text('MOVES  '), findsOneWidget);
    expect(storage.seenHowTo, isTrue);
  });
}
