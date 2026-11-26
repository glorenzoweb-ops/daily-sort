import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/analytics.dart';
import '../services/storage.dart';
import 'board.dart';
import 'daily.dart';
import 'solver.dart';

enum GameStatus { playing, won, outOfMoves }

/// What a tap did, so the UI can pick an animation and a haptic.
sealed class TapOutcome {
  const TapOutcome();
}

class Selected extends TapOutcome {
  final int tube;
  const Selected(this.tube);
}

class Deselected extends TapOutcome {
  const Deselected();
}

class Poured extends TapOutcome {
  final Move move;
  final int count;
  final int color;
  final BoardState before;
  final bool completedTube;
  final bool won;
  const Poured(this.move, this.count, this.color, this.before, this.completedTube, this.won);
}

class Invalid extends TapOutcome {
  final int tube;
  const Invalid(this.tube);
}

class Ignored extends TapOutcome {
  const Ignored();
}

class PourInfo {
  final Move move;
  final int color;
  final int count;
  final int destSlot; // height the first ball landed at
  final bool completedTube;
  const PourInfo(this.move, this.color, this.count, this.destSlot, this.completedTube);
}

class GameController extends ChangeNotifier {
  final DailyPuzzle puzzle;
  final Storage storage;

  late BoardState board;
  final List<Move> history = [];
  final List<int> moveColors = [];
  int attempts = 1;
  int? selected;
  GameStatus status = GameStatus.playing;
  DayRecord? _record;

  /// A past daily puzzle replayed from the archive: saved, but it never
  /// touches the streak or the stats.
  final bool archive;

  /// The guided first puzzle: never saved, never counted.
  final bool tutorial;

  GameController(this.puzzle, this.storage, {this.archive = false, this.tutorial = false}) {
    board = puzzle.start;
    if (puzzle.isPractice) return; // practice is never saved
    _record = storage.day(puzzle.number);
    final r = _record;
    if (r != null) {
      attempts = r.attempts;
      for (final m in r.moves) {
        if (!board.canPour(m.from, m.to)) break;
        moveColors.add(board.topColor(m.from)!);
        board = board.apply(m);
        history.add(m);
      }
      if (r.solved) {
        status = GameStatus.won;
      } else {
        _updateStatus();
      }
    }
  }

  /// The move a hint is pointing at, until the next tap.
  Move? hint;

  /// What a hint says when the board can't be solved in the moves left:
  /// undo this many moves first.
  int hintUndo = 0;

  /// Works out a hint: the first move of a shortest solution from here. If
  /// none fits in the moves left, how many moves to undo instead. Returns
  /// false when there is nothing to hint (solved, or out of moves).
  bool findHint() {
    if (status != GameStatus.playing) return false;
    hint = null;
    hintUndo = 0;
    final left = puzzle.isPractice ? 40 : movesLeft;
    final sol = solveOptimal(board, maxDepth: left, maxStates: 150000);
    if (sol != null && sol.isNotEmpty) {
      hint = sol.first;
    } else {
      // Step back until a solution fits again.
      var b = puzzle.start;
      final states = <BoardState>[b];
      for (final m in history) {
        b = b.apply(m);
        states.add(b);
      }
      for (var k = 1; k <= history.length; k++) {
        final at = history.length - k;
        if (solveOptimal(states[at], maxDepth: puzzle.moveLimit - at, maxStates: 150000) != null) {
          hintUndo = k;
          break;
        }
      }
      if (hintUndo == 0) hintUndo = history.length;
    }
    notifyListeners();
    return true;
  }

  bool _pendingHintMove = false;

  void _clearHint() {
    hint = null;
    hintUndo = 0;
  }

  int get movesUsed => history.length;
  int get movesLeft => puzzle.moveLimit - movesUsed;
  bool get canUndo => history.isNotEmpty && status != GameStatus.won;

  /// 3 stars at par, 2 at par+1, otherwise 1.
  int get stars => starsFor(movesUsed, puzzle.par);
  static int starsFor(int moves, int par) => moves <= par ? 3 : (moves == par + 1 ? 2 : 1);

  TapOutcome tap(int tube) {
    if (status != GameStatus.playing) return const Ignored();
    // The hint stays up while you pick its tube, and goes once you pour.
    if (hint != null && !(selected == null && tube == hint!.from)) _clearHint();
    final sel = selected;
    if (sel == null) {
      if (!board.canPick(tube)) {
        return Invalid(tube);
      }
      selected = tube;
      notifyListeners();
      return Selected(tube);
    }
    if (sel == tube) {
      selected = null;
      notifyListeners();
      return const Deselected();
    }
    final count = board.pourCount(sel, tube);
    if (count == 0) {
      // Tapping another pickable tube switches the selection.
      if (board.canPick(tube)) {
        selected = tube;
        notifyListeners();
        return Selected(tube);
      }
      selected = null;
      notifyListeners();
      return Invalid(tube);
    }
    final move = Move(sel, tube);
    final before = board;
    final color = board.topColor(sel)!;
    board = board.apply(move);
    history.add(move);
    moveColors.add(color);
    selected = null;
    final completed = board.isTubeComplete(tube);
    _updateStatus();
    _persist();
    notifyListeners();
    return Poured(move, count, color, before, completed, status == GameStatus.won);
  }

  void undo() {
    if (!canUndo) return;
    final m = history.removeLast();
    moveColors.removeLast();
    if (hintUndo > 0) {
      hintUndo--;
      // Undone far enough: the hint now points at the way on.
      if (hintUndo == 0) _pendingHintMove = true;
    } else {
      _clearHint();
    }
    // Rebuild from the start: pours aren't always reversible (partial pours).
    board = puzzle.start;
    for (final h in history) {
      board = board.apply(h);
    }
    selected = null;
    status = GameStatus.playing;
    if (_pendingHintMove) {
      _pendingHintMove = false;
      final sol = solveOptimal(board, maxDepth: puzzle.isPractice ? 40 : movesLeft, maxStates: 150000);
      hint = sol == null || sol.isEmpty ? null : sol.first;
    }
    _persist();
    notifyListeners();
    assert(m.from >= 0);
  }

  void restart() {
    if (status == GameStatus.won) return;
    if (history.isEmpty) return;
    history.clear();
    moveColors.clear();
    _clearHint();
    board = puzzle.start;
    selected = null;
    attempts++;
    status = GameStatus.playing;
    _persist();
    notifyListeners();
  }

  void _updateStatus() {
    if (board.isSolved) {
      status = GameStatus.won;
      _recordWin();
    } else if (!puzzle.isPractice && history.length >= puzzle.moveLimit) {
      // Unwind (practice) puzzles have no move limit: you can't fail.
      status = GameStatus.outOfMoves;
      if (!tutorial) Analytics.send('Daily.outOfMoves', {'puzzle': puzzle.number, 'archive': archive});
    } else {
      status = GameStatus.playing;
    }
  }

  /// Every pour so far, with what the song and painting need.
  List<PourInfo> get pours {
    final out = <PourInfo>[];
    var b = puzzle.start;
    for (final m in history) {
      final n = b.pourCount(m.from, m.to);
      final color = b.topColor(m.from)!;
      final slot = b.tubes[m.to].length;
      b = b.apply(m);
      out.add(PourInfo(m, color, n, slot, b.isTubeComplete(m.to)));
    }
    return out;
  }

  /// Saves the moves so far. Not right away: writing goes through the phone's
  /// settings store on the main thread, so it waits until the pour has landed
  /// and the board is quiet (a burst of moves is saved once).
  void _persist() {
    if (puzzle.isPractice) return;
    final r = _record ??= DayRecord();
    r.moves = List.of(history);
    r.attempts = attempts;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, flushSave);
    _waiting.add(this);
  }

  static final _waiting = <GameController>{};

  /// Saves every game with moves still waiting (the app is going away).
  static void flushAll() {
    for (final g in List.of(_waiting)) {
      g.flushSave();
    }
  }

  /// How long after the last move it is saved.
  static Duration saveDelay = const Duration(milliseconds: 900);
  Timer? _saveTimer;

  /// Saves now anything still waiting (also when the app goes to the background).
  void flushSave() {
    final t = _saveTimer;
    if (t == null) return;
    t.cancel();
    _saveTimer = null;
    _waiting.remove(this);
    final r = _record;
    if (r != null && !puzzle.isPractice) storage.saveDay(puzzle.number, r);
  }

  @override
  void dispose() {
    flushSave();
    super.dispose();
  }

  /// Set when this Unwind solve earned a streak freeze.
  bool earnedFreeze = false;

  /// The streak before and after this daily solve (for the celebration).
  int streakBefore = 0, streakAfter = 0;

  void _recordWin() {
    if (tutorial) return;
    if (puzzle.isPractice) {
      storage.addPracticeSolve();
      final s = storage.stats;
      earnedFreeze = s.addUnwindSolve();
      storage.saveStats(s);
      Analytics.send('Unwind.solved', {'moves': history.length});
      return;
    }
    final r = _record ??= DayRecord();
    if (r.solved) return;
    r
      ..solved = true
      ..solvedMoves = history.length
      ..solvedColors = List.of(moveColors)
      ..par = puzzle.par
      ..attempts = attempts
      ..moves = List.of(history);
    storage.saveDay(puzzle.number, r);
    if (archive) {
      Analytics.send('Archive.solved', {'puzzle': puzzle.number, 'stars': starsFor(history.length, puzzle.par)});
      return;
    }

    final s = storage.stats;
    streakBefore = s.currentStreak(puzzle.number);
    s.addDailySolve(puzzle.number, DateTime.now().timeZoneOffset.inMinutes);
    streakAfter = s.streak;
    final st = starsFor(history.length, puzzle.par);
    s.stars[st] = (s.stars[st] ?? 0) + 1;
    storage.saveStats(s);
    final now = DateTime.now();
    storage.addPlayMinute(now.hour * 60 + now.minute);
    Analytics.send('Daily.solved', {
      'puzzle': puzzle.number,
      'stars': st,
      'overPar': history.length - puzzle.par,
      'attempts': attempts,
      'streak': streakAfter,
      'hour': now.hour,
    });
  }
}
