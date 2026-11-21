import 'dart:convert';

import 'board.dart';
import 'daily.dart';

/// Saves a generated puzzle so it never has to be generated (and solved)
/// again on this device. Generation itself is untouched, so every player
/// still gets exactly the same puzzle.
String encodePuzzle(DailyPuzzle p) => jsonEncode({
  't': p.start.tubes,
  'c': p.start.capacity,
  'pt': p.start.rules.pickyTube,
  'pc': p.start.rules.pickyColor,
  'lt': p.start.rules.lockedTube,
  'ua': p.start.rules.unlockAfter,
  's': [
    for (final m in p.solution) [m.from, m.to],
  ],
  'l': p.moveLimit,
});

/// Rebuilds a saved puzzle, or returns null if it's damaged or its saved
/// solution doesn't actually solve it.
DailyPuzzle? decodePuzzle(String raw, {required int number, required DateTime day, required PuzzleSpec spec}) {
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final tubes = [for (final t in j['t'] as List) List<int>.from(t as List)];
    final rules = Rules(
      pickyTube: j['pt'] as int?,
      pickyColor: j['pc'] as int,
      lockedTube: j['lt'] as int?,
      unlockAfter: j['ua'] as int,
    );
    final start = BoardState(tubes, j['c'] as int, rules: rules);
    final solution = [for (final m in j['s'] as List) Move((m as List)[0] as int, m[1] as int)];
    var b = start;
    for (final m in solution) {
      if (!b.canPour(m.from, m.to)) return null;
      b = b.apply(m);
    }
    if (!b.isSolved || solution.isEmpty) return null;
    return DailyPuzzle(
      number: number,
      day: day,
      spec: spec,
      start: start,
      solution: solution,
      moveLimit: j['l'] as int,
    );
  } catch (_) {
    return null;
  }
}
