import 'dart:math' as math;

import '../game/daily.dart';
import '../game/puzzle_cache.dart';
import 'background.dart';
import 'storage.dart';

/// Hands out puzzles without making the player wait: daily puzzles are saved
/// once generated, tomorrow's is prepared while you look at today's result,
/// and the next Unwind puzzle is always ready before you ask for it.
class Puzzles {
  final Storage storage;
  Puzzles(this.storage);

  final _rnd = math.Random();
  Future<DailyPuzzle>? _nextUnwind;

  Future<DailyPuzzle> daily(DateTime now) async {
    final day = dayOf(now);
    final n = puzzleNumberFor(day);
    final raw = storage.cachedPuzzle(n);
    if (raw != null) {
      final p = decodePuzzle(raw, number: n, day: day, spec: specFor(day));
      if (p != null) return p;
    }
    final p = await runInBackground(() => puzzleForDay(day));
    await storage.cachePuzzle(n, encodePuzzle(p));
    return p;
  }

  /// A past daily puzzle for the archive (not cached: it's a one-off).
  Future<DailyPuzzle> archive(int number) => runInBackground(() => puzzleForDay(dayForNumber(number)));

  /// Quietly prepares the next [days] daily puzzles, one at a time (call it
  /// at a calm moment). They open instantly, even offline.
  Future<void> prefetchAhead(DateTime now, {int days = 7}) async {
    final today = puzzleNumberFor(dayOf(now));
    for (var k = 1; k <= days; k++) {
      final day = dayOf(now).add(Duration(days: k));
      final n = puzzleNumberFor(day);
      if (storage.cachedPuzzle(n) != null) continue;
      try {
        final p = await runInBackground(() => puzzleForDay(day));
        await storage.cachePuzzle(n, encodePuzzle(p), today: today);
      } catch (_) {}
    }
  }

  /// The next Unwind puzzle: already prepared if [prefetchUnwind] ran.
  Future<DailyPuzzle> unwind() {
    final next = _nextUnwind ?? _makeUnwind();
    _nextUnwind = null;
    return next;
  }

  void prefetchUnwind() => _nextUnwind ??= _makeUnwind();

  Future<DailyPuzzle> _makeUnwind() {
    final seed = _rnd.nextInt(0x7FFFFFFF);
    return runInBackground(() => practicePuzzle(seed));
  }
}
