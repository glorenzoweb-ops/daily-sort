import 'board.dart';
import 'rng.dart';
import 'solver.dart';

/// Day #1 of Daily Sort. Puzzle numbers count up from here.
final DateTime launchDate = DateTime.utc(2026, 11, 20);

/// How many moves above par the player is allowed. Hard mode (premium,
/// later) can set this to 0.
const int defaultMoveSlack = 2;

enum Difficulty { easy, medium, hard }

class DifficultySpec {
  final int colors;
  final int emptyTubes;
  final int capacity;
  final int minPar;
  final int maxPar;
  const DifficultySpec(this.colors, this.emptyTubes, this.capacity, this.minPar, this.maxPar);
}

const Map<Difficulty, DifficultySpec> difficultySpecs = {
  Difficulty.easy: DifficultySpec(4, 2, 4, 7, 9),
  Difficulty.medium: DifficultySpec(4, 2, 4, 10, 13),
  Difficulty.hard: DifficultySpec(5, 2, 4, 12, 16),
};

/// Mon/Tue easy, Wed/Thu/Fri medium, weekend hard (like crossword weeks).
Difficulty difficultyFor(DateTime day) {
  switch (day.weekday) {
    case DateTime.monday:
    case DateTime.tuesday:
      return Difficulty.easy;
    case DateTime.saturday:
    case DateTime.sunday:
      return Difficulty.hard;
    default:
      return Difficulty.medium;
  }
}

class DailyPuzzle {
  final int number;
  final DateTime day; // date only, UTC midnight
  final Difficulty difficulty;
  final BoardState start;
  final List<Move> solution; // a shortest solution
  final int par;
  final int moveLimit;

  DailyPuzzle({
    required this.number,
    required this.day,
    required this.difficulty,
    required this.start,
    required this.solution,
    required this.moveLimit,
  }) : par = solution.length;

  int get colors => difficultySpecs[difficulty]!.colors;
}

/// Strips the time and time zone: a "day" is the player's local calendar day,
/// like Wordle.
DateTime dayOf(DateTime local) => DateTime.utc(local.year, local.month, local.day);

int puzzleNumberFor(DateTime day) => dayOf(day).difference(launchDate).inDays + 1;

DateTime dayForNumber(int number) => launchDate.add(Duration(days: number - 1));

final Map<int, DailyPuzzle> _cache = {};

/// The puzzle for a calendar day. Same input → same puzzle on every device.
DailyPuzzle puzzleForDay(DateTime anyTimeThatDay) {
  final day = dayOf(anyTimeThatDay);
  final number = puzzleNumberFor(day);
  return _cache[number] ??= _generate(day, number);
}

DailyPuzzle _generate(DateTime day, int number) {
  final difficulty = difficultyFor(day);
  final spec = difficultySpecs[difficulty]!;
  final rng = SeededRng(day.year * 10000 + day.month * 100 + day.day);

  BoardState? best;
  List<Move>? bestSolution;
  var bestDistance = 1 << 30;

  for (var attempt = 0; attempt < 200; attempt++) {
    final board = _deal(rng, spec);
    if (board == null) continue;
    final sol = solveOptimal(board, maxDepth: spec.maxPar + 4);
    if (sol == null || sol.isEmpty) continue;
    final par = sol.length;
    if (par >= spec.minPar && par <= spec.maxPar) {
      return DailyPuzzle(
        number: number,
        day: day,
        difficulty: difficulty,
        start: board,
        solution: sol,
        moveLimit: par + defaultMoveSlack,
      );
    }
    final distance = par < spec.minPar ? spec.minPar - par : par - spec.maxPar;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = board;
      bestSolution = sol;
    }
  }
  // Practically unreachable, but still a valid, proven-solvable puzzle.
  return DailyPuzzle(
    number: number,
    day: day,
    difficulty: difficulty,
    start: best!,
    solution: bestSolution!,
    moveLimit: bestSolution.length + defaultMoveSlack,
  );
}

BoardState? _deal(SeededRng rng, DifficultySpec spec) {
  final balls = <int>[
    for (var c = 0; c < spec.colors; c++)
      for (var k = 0; k < spec.capacity; k++) c,
  ];
  rng.shuffle(balls);
  final tubes = <List<int>>[
    for (var t = 0; t < spec.colors; t++) balls.sublist(t * spec.capacity, (t + 1) * spec.capacity),
    for (var e = 0; e < spec.emptyTubes; e++) <int>[],
  ];
  final board = BoardState(tubes, spec.capacity);
  // Reject boards where a tube starts complete or has 3+ of a color on top
  // (too easy, looks unshuffled).
  for (var i = 0; i < spec.colors; i++) {
    if (board.topRun(i) >= spec.capacity - 1) return null;
  }
  return board;
}
