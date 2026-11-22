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
  int? par; // saved with the solve, for the history calendar

  DayRecord({
    List<Move>? moves,
    this.attempts = 1,
    this.solved = false,
    this.solvedMoves,
    List<int>? solvedColors,
    this.par,
  }) : moves = moves ?? [],
       solvedColors = solvedColors ?? [];

  Map<String, dynamic> toJson() => {
    'moves': moves.map((m) => m.toJson()).toList(),
    'attempts': attempts,
    'solved': solved,
    'solvedMoves': solvedMoves,
    'solvedColors': solvedColors,
    'par': ?par,
  };

  static DayRecord fromJson(Map<String, dynamic> j) => DayRecord(
    moves: (j['moves'] as List).map((m) => Move.fromJson(m as List)).toList(),
    attempts: j['attempts'] as int? ?? 1,
    solved: j['solved'] as bool? ?? false,
    solvedMoves: j['solvedMoves'] as int?,
    solvedColors: (j['solvedColors'] as List?)?.cast<int>() ?? [],
    par: j['par'] as int?,
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

  /// The phone's time zone (minutes from UTC) when the streak last moved.
  /// A trip that changes it can skip a calendar day, so one missed day after
  /// a time zone change doesn't break the streak.
  int? tzMinutes;
  static const unwindPerFreeze = 5;

  Stats({
    this.played = 0,
    this.solved = 0,
    this.streak = 0,
    this.maxStreak = 0,
    this.lastSolvedNumber = 0,
    this.freezes = 0,
    this.freezeProgress = 0,
    this.tzMinutes,
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

  /// Travel grace: one missed day right after the time zone changed is
  /// forgiven, without spending a freeze. Returns true when it kicked in.
  bool applyTravelGrace(int today, int tzNow) {
    final missed = today - 1 - lastSolvedNumber;
    if (streak == 0 || lastSolvedNumber == 0 || missed != 1) return false;
    if (tzMinutes == null || tzMinutes == tzNow) return false;
    lastSolvedNumber = today - 1;
    tzMinutes = tzNow;
    return true;
  }

  /// Counts a solved daily toward the streak. Flying west can bring back a
  /// puzzle number older than the last solve: that keeps the streak as is.
  void addDailySolve(int number, int tzNow) {
    played++;
    solved++;
    tzMinutes = tzNow;
    if (number <= lastSolvedNumber) return;
    streak = lastSolvedNumber == number - 1 ? streak + 1 : 1;
    if (streak > maxStreak) maxStreak = streak;
    lastSolvedNumber = number;
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
    'tz': ?tzMinutes,
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
    tzMinutes: j['tz'] as int?,
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

  /// The name friends see on your results (empty until you pick one).
  String get myName => _prefs.getString('myName') ?? '';
  Future<void> setMyName(String v) => _prefs.setString('myName', v);

  /// Whether we already asked for a name (so "Skip" sticks).
  bool get askedName => _prefs.getBool('askedName') ?? false;
  Future<void> setAskedName() => _prefs.setBool('askedName', true);

  String? get friendsRaw => _prefs.getString('friends');
  Future<void> setFriendsRaw(String v) => _prefs.setString('friends', v);

  /// Times this device tapped "Start free trial" before payments were live.
  int get premiumInterest => _prefs.getInt('premiumInterest') ?? 0;
  Future<void> addPremiumInterest() => _prefs.setInt('premiumInterest', premiumInterest + 1);

  /// 'auto' (follow the phone), 'light' or 'dark'.
  String get theme => _prefs.getString('theme') ?? 'auto';
  Future<void> setTheme(String v) => _prefs.setString('theme', v);

  bool get colorblind => _prefs.getBool('colorblind') ?? false;
  Future<void> setColorblind(bool v) => _prefs.setBool('colorblind', v);

  /// Hints used on daily puzzle [number] (the free one counts too).
  int hintsUsed(int number) => _prefs.getInt('hints_$number') ?? 0;
  Future<void> addHint(int number) async {
    await _prefs.setInt('hints_$number', hintsUsed(number) + 1);
    for (final k in _prefs.getKeys().where((k) => k.startsWith('hints_')).toList()) {
      final n = int.tryParse(k.substring(6));
      if (n != null && n < number - 7) await _prefs.remove(k);
    }
  }

  /// Reactions friends sent to your results (JSON list).
  String? get reactionsRaw => _prefs.getString('reactions');
  Future<void> setReactionsRaw(String v) => _prefs.setString('reactions', v);

  /// Reactions you sent, so the board shows them (JSON map "number:name" → emoji index).
  String? get sentReactionsRaw => _prefs.getString('sentReactions');
  Future<void> setSentReactionsRaw(String v) => _prefs.setString('sentReactions', v);

  bool get hapticsOn => _prefs.getBool('haptics') ?? true;
  Future<void> setHaptics(bool v) => _prefs.setBool('haptics', v);

  /// Volumes, 0..1, for pour sounds, the soundscape and the music.
  double volume(String channel) {
    final v = _prefs.get('volume_$channel');
    return v is num ? v.toDouble().clamp(0.0, 1.0) : 1.0;
  }

  Future<void> setVolume(String channel, double v) => _prefs.setDouble('volume_$channel', v);

  /// Reduce motion. Null until the player picks: then the phone's setting
  /// decides.
  bool? get reduceMotion => _prefs.getBool('reduceMotion');
  Future<void> setReduceMotion(bool v) => _prefs.setBool('reduceMotion', v);

  /// Share results as words instead of emoji squares. Null until the player
  /// picks: then it is on while a screen reader runs.
  bool? get plainShare => _prefs.getBool('plainShare');
  Future<void> setPlainShare(bool v) => _prefs.setBool('plainShare', v);

  /// Everything saved on this device except the puzzle cache, for a backup.
  Map<String, Object> exportAll() => {
    for (final k in _prefs.getKeys())
      if (!k.startsWith('puzzle_') && _prefs.get(k) != null) k: _prefs.get(k)!,
  };

  /// Replaces everything saved on this device (but the puzzle cache) with
  /// [data], from a backup.
  Future<void> replaceAll(Map<String, Object?> data) async {
    for (final k in _prefs.getKeys().where((k) => !k.startsWith('puzzle_')).toList()) {
      await _prefs.remove(k);
    }
    for (final e in data.entries) {
      final v = e.value;
      if (e.key.startsWith('puzzle_')) continue;
      switch (v) {
        case bool():
          await _prefs.setBool(e.key, v);
        // On the web 1.0 is also an int: volumes are always doubles.
        case num() when e.key.startsWith('volume_'):
          await _prefs.setDouble(e.key, v.toDouble());
        case int():
          await _prefs.setInt(e.key, v);
        case double():
          await _prefs.setDouble(e.key, v);
        case String():
          await _prefs.setString(e.key, v);
        case List():
          await _prefs.setStringList(e.key, v.map((x) => '$x').toList());
      }
    }
  }
}
