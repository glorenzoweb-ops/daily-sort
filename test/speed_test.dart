import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/puzzle_cache.dart';
import 'package:daily_sort/services/puzzles.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/ambient_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the next 7 days are prepared and today stays cached', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await Storage.open();
    final puzzles = Puzzles(storage);
    final now = DateTime(2026, 11, 25, 19);
    final today = await puzzles.daily(now);
    await puzzles.prefetchAhead(now);
    expect(storage.cachedPuzzle(today.number), isNotNull);
    for (var k = 1; k <= 7; k++) {
      expect(storage.cachedPuzzle(today.number + k), isNotNull, reason: 'day +$k');
    }
    // A prepared day is the same puzzle everyone gets that day.
    final day3 = dayOf(now).add(const Duration(days: 3));
    final fresh = puzzleForDay(day3);
    final cached = decodePuzzle(
      storage.cachedPuzzle(today.number + 3)!,
      number: fresh.number,
      day: day3,
      spec: specFor(day3),
    );
    expect(cached!.par, fresh.par);
    expect(cached.start.tubes.toString(), fresh.start.tubes.toString());
  });

  test('the idle clock pauses while a sheet holds it', () async {
    var ticks = 0;
    void count() => ticks++;
    final clock = AmbientClock.instance..addListener(count);
    clock.hold();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ticks, 0);
    clock.release();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(ticks, greaterThan(0));
    clock.removeListener(count);
  });
}
