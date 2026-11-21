import 'dart:math';

import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/game_controller.dart';
import 'package:daily_sort/services/reactions.dart';
import 'package:daily_sort/services/share.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/appearance.dart';
import 'package:daily_sort/ui/history.dart';
import 'package:daily_sort/ui/palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hints', () {
    test('following hints from the start solves the puzzle at par', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final p = puzzleForDay(dayForNumber(2));
      final g = GameController(p, storage);
      var steps = 0;
      while (g.status == GameStatus.playing && steps < 60) {
        expect(g.findHint(), isTrue);
        final m = g.hint!;
        g.tap(m.from);
        expect(g.hint, isNotNull, reason: 'the hint stays while you pick its tube');
        g.tap(m.to);
        expect(g.hint, isNull);
        steps++;
      }
      expect(g.status, GameStatus.won);
      expect(g.movesUsed, p.par);
    });

    test('off the path: the hint says how many moves to undo, then points on', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final p = puzzleForDay(dayForNumber(3));
      final g = GameController(p, storage);
      // Wander with random moves until one move is left: far too few.
      final rnd = Random(3);
      while (g.movesLeft > 1 && g.status == GameStatus.playing) {
        final moves = g.board.legalMoves().toList();
        final m = moves[rnd.nextInt(moves.length)];
        g.tap(m.from);
        g.tap(m.to);
      }
      expect(g.status, GameStatus.playing);
      expect(g.findHint(), isTrue);
      expect(g.hintUndo, greaterThan(0));
      final k = g.hintUndo;
      for (var i = 0; i < k; i++) {
        g.undo();
      }
      expect(g.hintUndo, 0);
      expect(g.hint, isNotNull);
    });

    test('used hints are counted per day and show on the share text', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      await storage.addHint(5);
      await storage.addHint(5);
      expect(storage.hintsUsed(5), 2);
      expect(storage.hintsUsed(6), 0);
      final text = buildShareText(
        puzzle: puzzleForDay(dayForNumber(5)),
        moves: 12,
        stars: 2,
        attempts: 1,
        moveColors: const [0, 1],
        hints: 2,
      );
      expect(text, contains('💡2'));
    });
  });

  group('reactions', () {
    test('a reaction survives the trip through a link', () {
      const r = Reaction(number: 4, emoji: 1, from: 'Ana-Lu');
      final back = Reaction.decode(r.encode())!;
      expect([back.number, back.emoji, back.from], [4, 1, 'Ana-Lu']);
      for (final bad in [null, '', '4-9-Ana', '0-1-Ana', 'x-1-Ana', '4-1']) {
        expect(Reaction.decode(bad), isNull, reason: '$bad');
      }
    });

    test('one reaction per friend per day, yours ignored, sent ones remembered', () async {
      SharedPreferences.setMockInitialValues({'myName': 'Gio'});
      final storage = await Storage.open();
      final x = Reactions(storage);
      expect(await x.receive(const Reaction(number: 2, emoji: 0, from: 'Ana'), today: 2), isTrue);
      expect(await x.receive(const Reaction(number: 2, emoji: 1, from: 'ana'), today: 2), isTrue);
      expect(await x.receive(const Reaction(number: 2, emoji: 1, from: 'gio'), today: 2), isFalse);
      expect(x.forDay(2).single.symbol, '🔥');
      await x.markSent('Bo', 2, 3, today: 2);
      expect(x.sentTo('bo', 2), 3);
      expect(x.sentTo('bo', 1), isNull);
    });

    test('the reaction message carries the reaction and your result', () {
      final t = buildReactionText(to: 'Ana', number: 2, toMoves: 13, emoji: 0, from: 'Gio', myResult: '2-12-1-0-Gio');
      expect(t, startsWith('👏 Ana'));
      expect(t, contains('?x=2-0-Gio&r=2-12-1-0-Gio'));
    });
  });

  group('appearance', () {
    test('choices are saved and applied to the palette', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      final a = Appearance(storage);
      expect(Palette.dark, isFalse); // tests run in light
      a.setChoice(ThemeChoice.dark);
      a.setColorblind(true);
      expect(Palette.dark, isTrue);
      expect(Palette.balls, Palette.safeBalls);
      final again = Appearance(storage);
      expect(again.choice, ThemeChoice.dark);
      expect(again.colorblind, isTrue);
      again.setChoice(ThemeChoice.light);
      again.setColorblind(false);
      expect(Palette.dark, isFalse);
      expect(Palette.balls, Palette.candyBalls);
    });

    test('every ball color has its own shape', () {
      expect(Palette.shapes.toSet().length, Palette.safeBalls.length);
    });
  });

  test('history counts first tries and hint-free solves, and keeps par', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    await storage.saveDay(1, DayRecord(solved: true, solvedMoves: 10, attempts: 1, par: 9));
    await storage.saveDay(2, DayRecord(solved: true, solvedMoves: 12, attempts: 3, par: 12));
    await storage.saveDay(3, DayRecord(attempts: 2));
    await storage.addHint(2);
    expect(storage.day(1)!.par, 9);
    final s = summarize(storage, 3);
    expect([s.solved, s.pct(s.firstTry), s.pct(s.hintFree)], [2, 50, 50]);
  });
}
