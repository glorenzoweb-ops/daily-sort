import 'package:daily_sort/game/board.dart';
import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/rng.dart';
import 'package:daily_sort/services/share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rng is deterministic and stays 32-bit', () {
    final a = SeededRng(20261120), b = SeededRng(20261120);
    for (var i = 0; i < 1000; i++) {
      final x = a.nextUint32();
      expect(x, b.nextUint32());
      expect(x >= 0 && x <= 0xFFFFFFFF, isTrue);
    }
  });

  test('pinned first puzzle never changes (protects players already sharing results)', () {
    final p = puzzleForDay(DateTime(2026, 11, 20));
    expect(p.number, 1);
    // If this fails you changed the generator: every past and future puzzle
    // would change. Only update deliberately.
    expect(p.start.tubes.map((t) => t.join()).join('|'), pinnedDay1);
  });

  test('first 60 puzzles match the pinned fingerprint (same on VM and web)', () {
    var h = 0;
    for (var i = 0; i < 60; i++) {
      final p = puzzleForDay(DateTime(2026, 11, 20).add(Duration(days: i)));
      for (final c in p.start.canonicalKey.codeUnits) {
        h = (h * 31 + c) & 0x7FFFFFFF;
      }
      h = (h * 31 + p.par) & 0x7FFFFFFF;
    }
    expect(h, pinnedFingerprint);
  });

  test('every puzzle for the next 400 days is solvable within its move limit', () {
    final start = DateTime(2026, 11, 20);
    for (var i = 0; i < 400; i++) {
      final p = puzzleForDay(start.add(Duration(days: i)));
      final spec = difficultySpecs[p.difficulty]!;
      expect(p.number, i + 1);
      expect(p.par, inInclusiveRange(spec.minPar, spec.maxPar), reason: 'day ${p.number}');
      expect(p.moveLimit, p.par + defaultMoveSlack);
      expect(p.start.isSolved, isFalse);
      var b = p.start;
      for (final m in p.solution) {
        expect(b.canPour(m.from, m.to), isTrue, reason: 'day ${p.number} move $m');
        b = b.apply(m);
      }
      expect(b.isSolved, isTrue, reason: 'day ${p.number}');
      expect(p.solution.length, lessThanOrEqualTo(p.moveLimit));
    }
  });

  test('pour rules', () {
    final b = BoardState([
      [0, 1, 1],
      [1],
      [],
      [0, 0, 0, 0],
    ], 4);
    expect(b.pourCount(0, 1), 2); // run of two 1s onto a 1
    expect(b.pourCount(0, 2), 2);
    expect(b.pourCount(0, 3), 0); // full
    expect(b.pourCount(2, 0), 0); // empty source
    final n = b.apply(const Move(0, 1));
    expect(n.tubes[1], [1, 1, 1]);
    expect(n.tubes[0], [0]);
  });

  test('share text', () {
    final p = puzzleForDay(DateTime(2026, 11, 20));
    final t = buildShareText(
        puzzle: p, moves: p.par, stars: 3, attempts: 1, moveColors: List.generate(p.par, (i) => i % 4), streak: 3);
    expect(t, startsWith('Daily Sort #1 ⭐⭐⭐\n${p.par}/${p.moveLimit} moves · par ${p.par} · 1st try · 🔥3\n🟥🟨🟩🟦🟥'));
    expect(t, endsWith(shareUrl));
  });
}

const pinnedDay1 = '1301|2203|1120|3302||';
const pinnedFingerprint = 164223875;
