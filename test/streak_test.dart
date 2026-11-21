import 'package:daily_sort/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a freeze covers one missed day and keeps the streak', () {
    final s = Stats(streak: 6, maxStreak: 6, lastSolvedNumber: 10, freezes: 1);
    // Day 11 missed, now it's day 12.
    expect(s.applyFreezes(12), 1);
    expect(s.freezes, 0);
    expect(s.currentStreak(12), 6);
    expect(s.lastSolvedNumber, 11);
  });

  test('two missed days need two freezes, otherwise the streak is lost and freezes kept', () {
    final s = Stats(streak: 9, lastSolvedNumber: 10, freezes: 1);
    expect(s.applyFreezes(13), 0);
    expect(s.streak, 0);
    expect(s.freezes, 1);

    final t = Stats(streak: 9, lastSolvedNumber: 10, freezes: 2);
    expect(t.applyFreezes(13), 2);
    expect(t.currentStreak(13), 9);
  });

  test('no freeze is used when nothing was missed', () {
    final s = Stats(streak: 3, lastSolvedNumber: 10, freezes: 2);
    expect(s.applyFreezes(11), 0);
    expect(s.applyFreezes(10), 0);
    expect(s.freezes, 2);
  });

  test('every 5 Unwind solves earn a freeze, up to 2', () {
    final s = Stats();
    var earned = 0;
    for (var i = 0; i < 20; i++) {
      if (s.addUnwindSolve()) earned++;
    }
    expect(earned, 2);
    expect(s.freezes, Stats.maxFreezes);
    expect(s.freezeProgress, 0);
  });

  test('freezes survive saving and loading', () {
    final s = Stats.fromJson(Stats(freezes: 2, freezeProgress: 3).toJson());
    expect(s.freezes, 2);
    expect(s.freezeProgress, 3);
  });
}
