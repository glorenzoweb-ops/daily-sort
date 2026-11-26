import 'dart:convert';

import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/game_controller.dart';
import 'package:daily_sort/services/backup.dart';
import 'package:daily_sort/services/share.dart';
import 'package:daily_sort/services/sound.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/board_view.dart';
import 'package:daily_sort/ui/palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backup code', () {
    test('moves stats, days and settings to a new device', () async {
      SharedPreferences.setMockInitialValues({});
      final old = await Storage.open();
      await old.saveStats(Stats(played: 9, solved: 8, streak: 6, maxStreak: 7, lastSolvedNumber: 4, freezes: 1));
      await old.saveDay(3, DayRecord(solved: true, solvedMoves: 10, solvedColors: [1, 2], par: 9));
      await old.cachePuzzle(4, 'cached');
      await old.setMyName('Ana');
      await old.setVolume('music', 0.4);
      await old.setColorblind(true);
      final code = Backup.of(old).encode();
      expect(code, startsWith('DS1-'));
      expect(code, isNot(contains('=')));

      // Pasted with the message around it, and broken over lines.
      final pasted = '${backupMessage(code.substring(0, 30))}\n${code.substring(30)}';
      final b = Backup.parse(pasted);
      expect(b, isNotNull);
      expect(b!.stats.streak, 6);

      SharedPreferences.setMockInitialValues({'myName': 'Someone else', 'puzzle_9': 'keep'});
      final fresh = await Storage.open();
      await b.restoreTo(fresh);
      expect(fresh.stats.streak, 6);
      expect(fresh.stats.freezes, 1);
      expect(fresh.day(3)!.solvedMoves, 10);
      expect(fresh.day(3)!.solvedColors, [1, 2]);
      expect(fresh.myName, 'Ana');
      expect(fresh.colorblind, isTrue);
      expect(fresh.volume('music'), closeTo(0.4, 1e-9));
      expect(fresh.cachedPuzzle(4), isNull, reason: 'the puzzle cache stays out of the code');
      expect(fresh.cachedPuzzle(9), 'keep', reason: 'and the new device keeps its own');
    });

    test('solved days leave their moves out, unfinished days keep them', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Storage.open();
      final p = puzzleForDay(dayForNumber(2));
      final g = GameController(p, s);
      final m = g.board.legalMoves().first;
      g.tap(m.from);
      g.tap(m.to);
      g.flushSave();
      await s.saveDay(1, DayRecord(solved: true, solvedMoves: 9, moves: [m, m, m]));
      final b = Backup.parse(Backup.of(s).encode())!;
      final day1 = jsonDecode(b.data['day_1'] as String) as Map;
      final day2 = jsonDecode(b.data['day_2'] as String) as Map;
      expect(day1['moves'], isEmpty);
      expect(day2['moves'], hasLength(1));
    });

    test('rejects text that is not a code', () {
      expect(Backup.parse(''), isNull);
      expect(Backup.parse('hello'), isNull);
      expect(Backup.parse('DS1-notbase64json'), isNull);
    });
  });

  group('travel grace', () {
    Stats st() => Stats(streak: 5, maxStreak: 5, lastSolvedNumber: 10, tzMinutes: -300);

    test('one missed day after a time zone change keeps the streak', () {
      final s = st();
      expect(s.applyTravelGrace(12, 60), isTrue);
      expect(s.lastSolvedNumber, 11);
      expect(s.currentStreak(12), 5);
      expect(s.tzMinutes, 60);
      expect(s.applyTravelGrace(12, 60), isFalse, reason: 'only once per change');
    });

    test('no grace in the same time zone, or for two missed days', () {
      expect(st().applyTravelGrace(12, -300), isFalse);
      expect(st().applyTravelGrace(13, 60), isFalse);
      expect(Stats(streak: 5, lastSolvedNumber: 10).applyTravelGrace(12, 60), isFalse);
    });

    test('flying west back to an older puzzle keeps the streak', () {
      final s = st();
      s.addDailySolve(10, -480);
      expect(s.streak, 5);
      expect(s.lastSolvedNumber, 10);
      s.addDailySolve(11, -480);
      expect(s.streak, 6);
      expect(s.maxStreak, 6);
    });
  });

  test('plain share text has no emoji', () {
    final p = puzzleForDay(dayForNumber(2));
    final t = buildShareText(
      puzzle: p,
      moves: p.par + 1,
      stars: 2,
      attempts: 2,
      moveColors: [0, 1, 2],
      streak: 4,
      hints: 1,
      plain: true,
    );
    expect(t, contains('Daily Sort #2: 2 of 3 stars.'));
    expect(t, contains('Solved in ${p.par + 1} moves, par ${p.par}, 2nd try, 4-day streak, 1 hint.'));
    for (final e in [...Palette.emoji, '⭐', '🔥', '💡']) {
      expect(t, isNot(contains(e)));
    }
  });

  test('pour volume at zero turns pour sounds off', () {
    Sounds.setEffectsLevel(0);
    expect(Sounds.enabled, isFalse);
    Sounds.setEffectsLevel(0.5);
    expect(Sounds.enabled, isTrue);
    Sounds.setEffectsLevel(1);
  });

  testWidgets('screen readers hear every tube', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await tester.runAsync(Storage.open);
    final p = puzzleForDay(dayForNumber(2));
    final g = GameController(p, storage!);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 400, height: 500, child: BoardView(game: g)),
        ),
      ),
    );
    await tester.pump();
    final first = p.start.tubes[0].map((c) => Palette.ballNames[c]).join(', ');
    expect(find.bySemanticsLabel(RegExp('^Tube 1 of ${p.start.tubeCount}\\. bottom to top: $first')), findsOneWidget);
    // Tapping through semantics picks the tube up.
    tester.semantics.tap(find.semantics.byLabel(RegExp('^Tube 1 of')));
    await tester.pump();
    expect(g.selected, 0);
    expect(find.bySemanticsLabel(RegExp('^Tube 1 of.*picked up')), findsOneWidget);
    handle.dispose();
    g.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
