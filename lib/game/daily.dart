import 'board.dart';
import 'rng.dart';
import 'solver.dart';

/// Day #1 of Daily Sort. Puzzle numbers count up from here.
final DateTime launchDate = DateTime.utc(2026, 11, 20);

/// How many moves above par the player is allowed. Hard mode (premium,
/// later) can set this to 0.
const int defaultMoveSlack = 2;

enum Difficulty { easy, medium, hard }

/// The rule twist a puzzle uses. Each weekday has its own.
enum Twist { classic, tallTubes, pickyTube, lockedTube }

class PuzzleSpec {
  final Difficulty difficulty;
  final Twist twist;
  final int colors;
  final int emptyTubes;
  final int capacity;
  final int minPar;
  final int maxPar;
  const PuzzleSpec(this.difficulty, this.twist, this.colors, this.emptyTubes, this.capacity, this.minPar, this.maxPar);
}

/// How many moves the locked tube stays shut.
const int lockMoves = 3;

/// The weekly rhythm. Classic Mon/Fri/Sat; a twist on the other days.
/// Changing an entry changes every future puzzle on that weekday.
const Map<int, PuzzleSpec> weekdaySpecs = {
  DateTime.monday: PuzzleSpec(Difficulty.easy, Twist.classic, 4, 2, 4, 7, 9),
  DateTime.tuesday: PuzzleSpec(Difficulty.medium, Twist.tallTubes, 4, 2, 5, 9, 13),
  DateTime.wednesday: PuzzleSpec(Difficulty.medium, Twist.pickyTube, 4, 2, 4, 9, 13),
  DateTime.thursday: PuzzleSpec(Difficulty.medium, Twist.lockedTube, 4, 2, 4, 9, 13),
  DateTime.friday: PuzzleSpec(Difficulty.medium, Twist.classic, 4, 2, 4, 10, 13),
  DateTime.saturday: PuzzleSpec(Difficulty.hard, Twist.classic, 5, 2, 4, 12, 16),
  DateTime.sunday: PuzzleSpec(Difficulty.hard, Twist.pickyTube, 5, 2, 4, 12, 16),
};

PuzzleSpec specFor(DateTime day) => weekdaySpecs[day.weekday]!;

class DailyPuzzle {
  /// Puzzle number; 0 for practice puzzles.
  final int number;
  final DateTime day; // date only, UTC midnight
  final PuzzleSpec spec;
  final BoardState start;
  final List<Move> solution; // a shortest solution
  final int par;
  final int moveLimit;

  DailyPuzzle({
    required this.number,
    required this.day,
    required this.spec,
    required this.start,
    required this.solution,
    required this.moveLimit,
  }) : par = solution.length;

  bool get isPractice => number == 0;
  Difficulty get difficulty => spec.difficulty;
  Twist get twist => spec.twist;
  int get colors => spec.colors;
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
  return _cache[number] ??= generatePuzzle(
    seed: day.year * 10000 + day.month * 100 + day.day,
    spec: specFor(day),
    number: number,
    day: day,
  );
}

/// An endless Unwind puzzle: no move limit, no fail state. Doesn't count for
/// stats or streaks.
DailyPuzzle practicePuzzle(int seed) {
  // Calmer mix for Unwind: 4 colors only, no locked tube.
  final specs = [
    weekdaySpecs[DateTime.monday]!,
    weekdaySpecs[DateTime.tuesday]!,
    weekdaySpecs[DateTime.wednesday]!,
    weekdaySpecs[DateTime.friday]!,
  ];
  final spec = specs[SeededRng(seed ^ 0x51ed).nextInt(specs.length)];
  return generatePuzzle(seed: seed, spec: spec, number: 0, day: dayOf(DateTime.now()));
}

DailyPuzzle generatePuzzle({required int seed, required PuzzleSpec spec, required int number, required DateTime day}) {
  final rng = SeededRng(seed);

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
        spec: spec,
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
    spec: spec,
    start: best!,
    solution: bestSolution!,
    moveLimit: bestSolution.length + defaultMoveSlack,
  );
}

BoardState? _deal(SeededRng rng, PuzzleSpec spec) {
  final balls = <int>[
    for (var c = 0; c < spec.colors; c++)
      for (var k = 0; k < spec.capacity; k++) c,
  ];
  rng.shuffle(balls);
  final tubes = <List<int>>[
    for (var t = 0; t < spec.colors; t++) balls.sublist(t * spec.capacity, (t + 1) * spec.capacity),
    for (var e = 0; e < spec.emptyTubes; e++) <int>[],
  ];
  // Classic draws nothing extra from the RNG, so classic puzzles stay
  // identical to the ones generated before twists existed.
  var rules = Rules.none;
  switch (spec.twist) {
    case Twist.classic:
    case Twist.tallTubes:
      break;
    case Twist.pickyTube:
      rules = Rules(pickyTube: spec.colors, pickyColor: rng.nextInt(spec.colors));
    case Twist.lockedTube:
      rules = Rules(lockedTube: rng.nextInt(spec.colors), unlockAfter: lockMoves);
  }
  final board = BoardState(tubes, spec.capacity, rules: rules);
  // Reject boards where a tube starts (nearly) complete: too easy, looks
  // unshuffled.
  for (var i = 0; i < spec.colors; i++) {
    if (board.topRun(i) >= spec.capacity - 1) return null;
  }
  return board;
}
