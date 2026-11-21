import 'package:flutter/foundation.dart';

import '../services/storage.dart';
import 'board.dart';
import 'daily.dart';

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

  GameController(this.puzzle, this.storage) {
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

  int get movesUsed => history.length;
  int get movesLeft => puzzle.moveLimit - movesUsed;
  bool get canUndo => history.isNotEmpty && status != GameStatus.won;

  /// 3 stars at par, 2 at par+1, otherwise 1.
  int get stars => starsFor(movesUsed, puzzle.par);
  static int starsFor(int moves, int par) => moves <= par ? 3 : (moves == par + 1 ? 2 : 1);

  TapOutcome tap(int tube) {
    if (status != GameStatus.playing) return const Ignored();
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
    // Rebuild from the start: pours aren't always reversible (partial pours).
    board = puzzle.start;
    for (final h in history) {
      board = board.apply(h);
    }
    selected = null;
    status = GameStatus.playing;
    _persist();
    notifyListeners();
    assert(m.from >= 0);
  }

  void restart() {
    if (status == GameStatus.won) return;
    if (history.isEmpty) return;
    history.clear();
    moveColors.clear();
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

  void _persist() {
    if (puzzle.isPractice) return;
    final r = _record ??= DayRecord();
    r.moves = List.of(history);
    r.attempts = attempts;
    storage.saveDay(puzzle.number, r);
  }

  /// Set when this Unwind solve earned a streak freeze.
  bool earnedFreeze = false;

  /// The streak before and after this daily solve (for the celebration).
  int streakBefore = 0, streakAfter = 0;

  void _recordWin() {
    if (puzzle.isPractice) {
      storage.addPracticeSolve();
      final s = storage.stats;
      earnedFreeze = s.addUnwindSolve();
      storage.saveStats(s);
      return;
    }
    final r = _record ??= DayRecord();
    if (r.solved) return;
    r
      ..solved = true
      ..solvedMoves = history.length
      ..solvedColors = List.of(moveColors)
      ..attempts = attempts
      ..moves = List.of(history);
    storage.saveDay(puzzle.number, r);

    final s = storage.stats;
    streakBefore = s.currentStreak(puzzle.number);
    s.played++;
    s.solved++;
    s.streak = s.lastSolvedNumber == puzzle.number - 1 ? s.streak + 1 : 1;
    if (s.streak > s.maxStreak) s.maxStreak = s.streak;
    streakAfter = s.streak;
    s.lastSolvedNumber = puzzle.number;
    final st = starsFor(history.length, puzzle.par);
    s.stars[st] = (s.stars[st] ?? 0) + 1;
    storage.saveStats(s);
  }
}
