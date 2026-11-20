/// Pure game rules for a ball-sort board. No Flutter imports, so it runs in
/// unit tests and the solver.
library;

/// A single pour: move the top run of same-colored balls from [from] to [to].
class Move {
  final int from;
  final int to;
  const Move(this.from, this.to);

  @override
  bool operator ==(Object other) => other is Move && other.from == from && other.to == to;

  @override
  int get hashCode => from * 31 + to;

  @override
  String toString() => '$from→$to';

  List<int> toJson() => [from, to];
  static Move fromJson(List<dynamic> j) => Move(j[0] as int, j[1] as int);
}

/// Optional twist rules on top of classic ball sort.
class Rules {
  /// A tube that only accepts balls of [pickyColor].
  final int? pickyTube;
  final int pickyColor;

  /// A tube that can't be touched until [unlockAfter] moves have been made.
  final int? lockedTube;
  final int unlockAfter;

  const Rules({this.pickyTube, this.pickyColor = 0, this.lockedTube, this.unlockAfter = 0});

  static const none = Rules();

  bool get isClassic => pickyTube == null && lockedTube == null;
}

/// Immutable board. Each tube is a list of color indices, bottom first.
class BoardState {
  final List<List<int>> tubes;
  final int capacity;
  final Rules rules;
  final int movesMade;

  BoardState(List<List<int>> tubes, this.capacity, {this.rules = Rules.none, this.movesMade = 0})
    : tubes = List.unmodifiable(tubes.map((t) => List<int>.unmodifiable(t)));

  int get tubeCount => tubes.length;

  int? topColor(int i) => tubes[i].isEmpty ? null : tubes[i].last;

  /// Moves left until the locked tube opens (0 = open or no lock).
  int get lockRemaining {
    if (rules.lockedTube == null) return 0;
    final r = rules.unlockAfter - movesMade;
    return r > 0 ? r : 0;
  }

  bool isLocked(int i) => i == rules.lockedTube && lockRemaining > 0;
  bool isPicky(int i) => i == rules.pickyTube;

  /// How many balls of the top color sit together at the top of tube [i].
  int topRun(int i) {
    final t = tubes[i];
    if (t.isEmpty) return 0;
    final c = t.last;
    var n = 0;
    for (var k = t.length - 1; k >= 0 && t[k] == c; k--) {
      n++;
    }
    return n;
  }

  bool isTubeComplete(int i) {
    final t = tubes[i];
    return t.length == capacity && t.every((c) => c == t.first);
  }

  /// Whether the player may pick up from tube [i].
  bool canPick(int i) => tubes[i].isNotEmpty && !isTubeComplete(i) && !isLocked(i);

  /// Number of balls that would move for [from]→[to], or 0 if illegal.
  int pourCount(int from, int to) {
    if (from == to) return 0;
    if (isLocked(from) || isLocked(to)) return 0;
    final src = tubes[from];
    final dst = tubes[to];
    if (src.isEmpty) return 0;
    if (dst.length >= capacity) return 0;
    if (dst.isNotEmpty && dst.last != src.last) return 0;
    if (isPicky(to) && src.last != rules.pickyColor) return 0;
    final run = topRun(from);
    final space = capacity - dst.length;
    return run < space ? run : space;
  }

  bool canPour(int from, int to) => pourCount(from, to) > 0;

  BoardState apply(Move m) {
    final n = pourCount(m.from, m.to);
    assert(n > 0, 'illegal move $m');
    final next = tubes.map((t) => List<int>.of(t)).toList();
    for (var k = 0; k < n; k++) {
      next[m.to].add(next[m.from].removeLast());
    }
    return BoardState(next, capacity, rules: rules, movesMade: movesMade + 1);
  }

  bool get isSolved {
    for (var i = 0; i < tubes.length; i++) {
      if (tubes[i].isNotEmpty && !isTubeComplete(i)) return false;
    }
    return true;
  }

  /// Order-independent key: two boards that differ only by which plain tube
  /// is where are the same puzzle position. Special tubes are tagged.
  String get canonicalKey {
    final parts = <String>[];
    for (var i = 0; i < tubes.length; i++) {
      final body = String.fromCharCodes(tubes[i].map((c) => 65 + c));
      final tag = isPicky(i) ? '*' : (i == rules.lockedTube ? '#' : '');
      parts.add('$tag$body');
    }
    parts.sort();
    final key = parts.join('|');
    final lock = lockRemaining;
    return lock > 0 ? '$key@$lock' : key;
  }

  bool _isPlain(int i) => !isPicky(i) && i != rules.lockedTube;

  Iterable<Move> legalMoves() sync* {
    for (var i = 0; i < tubes.length; i++) {
      if (tubes[i].isEmpty) continue;
      // Pouring a single-color tube into a plain empty tube changes nothing.
      final mono = topRun(i) == tubes[i].length && _isPlain(i);
      var triedEmpty = false;
      for (var j = 0; j < tubes.length; j++) {
        if (i == j) continue;
        if (tubes[j].isEmpty && _isPlain(j)) {
          if (mono || triedEmpty) continue; // plain empty tubes are equivalent
          triedEmpty = true;
        }
        if (canPour(i, j)) yield Move(i, j);
      }
    }
  }
}
