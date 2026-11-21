import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/board.dart';

/// Saved progress for one daily puzzle.
class DayRecord {
  List<Move> moves;
  int attempts;
  bool solved;
  int? solvedMoves;
  List<int> solvedColors; // color of each move in the winning run (for share)

  DayRecord({List<Move>? moves, this.attempts = 1, this.solved = false, this.solvedMoves, List<int>? solvedColors})
    : moves = moves ?? [],
      solvedColors = solvedColors ?? [];

  Map<String, dynamic> toJson() => {
    'moves': moves.map((m) => m.toJson()).toList(),
    'attempts': attempts,
    'solved': solved,
    'solvedMoves': solvedMoves,
    'solvedColors': solvedColors,
  };

  static DayRecord fromJson(Map<String, dynamic> j) => DayRecord(
    moves: (j['moves'] as List).map((m) => Move.fromJson(m as List)).toList(),
    attempts: j['attempts'] as int? ?? 1,
    solved: j['solved'] as bool? ?? false,
    solvedMoves: j['solvedMoves'] as int?,
    solvedColors: (j['solvedColors'] as List?)?.cast<int>() ?? [],
  );
}

class Stats {
  int played;
  int solved;
  int streak;
  int maxStreak;

  /// Last daily puzzle number the streak covers: the last solve, or the last
  /// day a streak freeze filled in.
  int lastSolvedNumber;
  Map<int, int> stars; // stars → count

  /// Streak freezes in the bank, and Unwind solves toward the next one.
  int freezes;
  int freezeProgress;
  static const maxFreezes = 2;
  static const unwindPerFreeze = 5;

  Stats({
    this.played = 0,
    this.solved = 0,
    this.streak = 0,
    this.maxStreak = 0,
    this.lastSolvedNumber = 0,
    this.freezes = 0,
    this.freezeProgress = 0,
    Map<int, int>? stars,
  }) : stars = stars ?? {1: 0, 2: 0, 3: 0};

  /// The streak as of [today]: broken if yesterday wasn't solved.
  int currentStreak(int today) => lastSolvedNumber >= today - 1 ? streak : 0;

  /// Days missed before [today] are covered by banked freezes, if there are
  /// enough. Returns how many freezes were used (0 if none were needed, or
  /// if there weren't enough and the streak is lost).
  int applyFreezes(int today) {
    final missed = today - 1 - lastSolvedNumber;
    if (streak == 0 || lastSolvedNumber == 0 || missed <= 0) return 0;
    if (missed > freezes) {
      streak = 0;
      return 0;
    }
    freezes -= missed;
    lastSolvedNumber = today - 1;
    return missed;
  }

  /// Counts an Unwind solve toward the next freeze. Returns true when it
  /// earns one.
  bool addUnwindSolve() {
    if (freezes >= maxFreezes) {
      freezeProgress = 0;
      return false;
    }
    freezeProgress++;
    if (freezeProgress < unwindPerFreeze) return false;
    freezeProgress = 0;
    freezes++;
    return true;
  }

  Map<String, dynamic> toJson() => {
    'played': played,
    'solved': solved,
    'streak': streak,
    'maxStreak': maxStreak,
    'lastSolvedNumber': lastSolvedNumber,
    'freezes': freezes,
    'freezeProgress': freezeProgress,
    'stars': stars.map((k, v) => MapEntry('$k', v)),
  };

  static Stats fromJson(Map<String, dynamic> j) => Stats(
    played: j['played'] as int? ?? 0,
    solved: j['solved'] as int? ?? 0,
    streak: j['streak'] as int? ?? 0,
    maxStreak: j['maxStreak'] as int? ?? 0,
    lastSolvedNumber: j['lastSolvedNumber'] as int? ?? 0,
    freezes: j['freezes'] as int? ?? 0,
    freezeProgress: j['freezeProgress'] as int? ?? 0,
    stars: ((j['stars'] as Map?) ?? {}).map((k, v) => MapEntry(int.parse(k as String), v as int)),
  );
}

/// Thin wrapper over SharedPreferences (localStorage on web).
class Storage {
  final SharedPreferences _prefs;
  Storage(this._prefs);

  static Future<Storage> open() async => Storage(await SharedPreferences.getInstance());

  DayRecord? day(int number) {
    final raw = _prefs.getString('day_$number');
    if (raw == null) return null;
    try {
      return DayRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDay(int number, DayRecord r) => _prefs.setString('day_$number', jsonEncode(r.toJson()));

  Stats get stats {
    final raw = _prefs.getString('stats');
    if (raw == null) return Stats();
    try {
      return Stats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Stats();
    }
  }

  Future<void> saveStats(Stats s) => _prefs.setString('stats', jsonEncode(s.toJson()));

  /// Daily puzzles already generated on this device (see puzzle_cache.dart).
  String? cachedPuzzle(int number) => _prefs.getString('puzzle_$number');
  Future<void> cachePuzzle(int number, String raw) async {
    await _prefs.setString('puzzle_$number', raw);
    // Keep only yesterday onward.
    for (final k in _prefs.getKeys().where((k) => k.startsWith('puzzle_')).toList()) {
      final n = int.tryParse(k.substring(7));
      if (n != null && n < number - 1) await _prefs.remove(k);
    }
  }

  bool get seenHowTo => _prefs.getBool('seenHowTo') ?? false;
  Future<void> setSeenHowTo() => _prefs.setBool('seenHowTo', true);

  int get practiceSolved => _prefs.getInt('practiceSolved') ?? 0;
  Future<void> addPracticeSolve() => _prefs.setInt('practiceSolved', practiceSolved + 1);

  String get ambience => _prefs.getString('ambience') ?? 'off';
  Future<void> setAmbience(String v) => _prefs.setString('ambience', v);

  bool get musicOn => _prefs.getBool('music') ?? false;
  Future<void> setMusic(bool v) => _prefs.setBool('music', v);

  bool get soundOn => _prefs.getBool('sound') ?? true;
  Future<void> setSound(bool v) => _prefs.setBool('sound', v);

  bool twistSeen(String twist) => _prefs.getBool('twistSeen_$twist') ?? false;
  Future<void> setTwistSeen(String twist) => _prefs.setBool('twistSeen_$twist', true);

  bool get hapticsOn => _prefs.getBool('haptics') ?? true;
  Future<void> setHaptics(bool v) => _prefs.setBool('haptics', v);
}
