import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/game_controller.dart';
import 'package:daily_sort/services/friends.dart';
import 'package:daily_sort/services/premium.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/picture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('friend links', () {
    test('a result survives the trip through a link', () {
      const r = FriendResult(name: 'Ana-Lu é', number: 2, moves: 13, attempts: 2, streak: 5);
      final back = FriendResult.decode(r.encode())!;
      expect(back.name, 'Ana-Lu é');
      expect([back.number, back.moves, back.attempts, back.streak], [2, 13, 2, 5]);
    });

    test('garbage and silly values are rejected, names are cleaned', () {
      for (final bad in [null, '', 'hello', '2-13-1', 'x-13-1-0-Ana', '2-0-1-0-Ana', '2-500-1-0-Ana', '0-13-1-0-Ana']) {
        expect(FriendResult.decode(bad), isNull, reason: '$bad');
      }
      expect(FriendResult.decode('2-13-1-0-')!.name, 'A friend');
      expect(FriendResult.decode('2-13-1-0-%3Cb%3EBob%3C%2Fb%3E')!.name, 'bBob/b');
      expect(FriendResult.decode('2-13-1-0-${'x' * 40}')!.name.length, 16);
    });

    test('friends are stored per day, your own result is ignored, old days pruned', () async {
      SharedPreferences.setMockInitialValues({'myName': 'Gio'});
      final storage = await Storage.open();
      final f = Friends(storage);
      expect(await f.add(const FriendResult(name: 'Ana', number: 1, moves: 12), today: 2), isTrue);
      expect(await f.add(const FriendResult(name: 'ana', number: 1, moves: 10), today: 2), isTrue);
      expect(await f.add(const FriendResult(name: 'gio', number: 2, moves: 9), today: 2), isFalse);
      await f.add(const FriendResult(name: 'Bo', number: 2, moves: 14), today: 2);
      expect(f.forDay(1).single.moves, 10);
      expect(f.names, ['Bo', 'ana']);
      await f.add(const FriendResult(name: 'Cy', number: 40, moves: 14), today: 40);
      expect(f.forDay(1), isEmpty);
    });

    test('the board ranks by moves, then tries', () {
      final rows = rankDay(const [
        FriendResult(name: 'A', number: 1, moves: 12, attempts: 2),
        FriendResult(name: 'B', number: 1, moves: 12, attempts: 1),
        FriendResult(name: 'C', number: 1, moves: 15),
      ], me: const BoardEntry('Me', 11, 3, 0, isMe: true));
      expect(rows.map((r) => r.name), ['Me', 'B', 'A', 'C']);
    });
  });

  group('archive', () {
    test('only the last few days are free', () {
      final free = ComingSoonPremium();
      expect(archiveLocked(9, 10, free), isFalse);
      expect(archiveLocked(10 - freeArchiveDays, 10, free), isFalse);
      expect(archiveLocked(10 - freeArchiveDays - 1, 10, free), isTrue);
      expect(archiveLocked(1, 10, UnlockedPremium()), isFalse);
    });

    test('solving an archive puzzle saves it but leaves the streak alone', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      await storage.saveStats(Stats(streak: 4, maxStreak: 4, lastSolvedNumber: 9, solved: 4));
      final p = puzzleForDay(dayForNumber(1));
      final g = GameController(p, storage, archive: true);
      for (final m in p.solution) {
        g.tap(m.from);
        g.tap(m.to);
      }
      expect(g.status, GameStatus.won);
      expect(storage.day(1)!.solved, isTrue);
      final s = storage.stats;
      expect([s.streak, s.lastSolvedNumber, s.solved], [4, 9, 4]);
    });
  });

  group('picture of the day', () {
    test('every scene has five drawable layers on the canvas (a little bleed past the edge is fine)', () {
      expect(scenes.length, greaterThanOrEqualTo(8));
      for (final s in scenes) {
        expect(s.layers.length, 5, reason: s.title);
        expect(s.order.toSet(), {0, 1, 2, 3, 4}, reason: s.title);
        for (final l in s.layers) {
          final b = l.getBounds();
          expect(b.isEmpty, isFalse, reason: s.title);
          expect(
            b.left >= -10 && b.top >= -10 && b.right <= sceneW + 10 && b.bottom <= sceneH + 10,
            isTrue,
            reason: s.title,
          );
        }
      }
    });

    test('same picture for everyone, never the same two days running', () {
      for (var n = 1; n < 60; n++) {
        expect(sceneForNumber(n), same(sceneForNumber(n)));
        expect(sceneForNumber(n), isNot(same(sceneForNumber(n + 1))));
      }
      expect({for (var n = 1; n <= scenes.length; n++) sceneForNumber(n)}.length, scenes.length);
    });

    test('a layer colors in when its tube is complete', () {
      final p = puzzleForDay(dayForNumber(1));
      var b = p.start;
      expect(completedColors(b), isEmpty);
      for (final m in p.solution) {
        b = b.apply(m);
      }
      expect(completedColors(b), {for (var c = 0; c < p.colors; c++) c});
    });
  });
}
