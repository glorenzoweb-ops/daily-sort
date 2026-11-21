import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/puzzle_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved puzzles come back identical, every twist', () {
    for (var d = 0; d < 7; d++) {
      final day = launchDate.add(Duration(days: d));
      final p = puzzleForDay(day);
      final q = decodePuzzle(encodePuzzle(p), number: p.number, day: p.day, spec: p.spec)!;
      expect(q.start.canonicalKey, p.start.canonicalKey);
      expect(q.start.tubes, p.start.tubes);
      expect(q.start.rules.pickyTube, p.start.rules.pickyTube);
      expect(q.start.rules.lockedTube, p.start.rules.lockedTube);
      expect(q.par, p.par);
      expect(q.moveLimit, p.moveLimit);
    }
  });

  test('a damaged save is rejected', () {
    final p = puzzleForDay(launchDate);
    final raw = encodePuzzle(p).replaceFirst('"s":[[', '"s":[[9,9],[');
    expect(decodePuzzle(raw, number: 1, day: p.day, spec: p.spec), isNull);
    expect(decodePuzzle('nonsense', number: 1, day: p.day, spec: p.spec), isNull);
  });
}
