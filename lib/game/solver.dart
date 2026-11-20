import 'dart:collection';

import 'board.dart';

/// Breadth-first solver. Returns the shortest list of moves that solves
/// [start], or null if there is none within [maxDepth] / [maxStates].
///
/// Used to (1) prove every daily puzzle is solvable within its move limit and
/// to set its par, and (2) power hints later.
List<Move>? solveOptimal(BoardState start, {int maxDepth = 40, int maxStates = 400000}) {
  if (start.isSolved) return const [];
  final parent = <String, (String, Move)>{};
  final seen = <String>{start.canonicalKey};
  final queue = Queue<(BoardState, int)>()..add((start, 0));

  while (queue.isNotEmpty) {
    final (state, depth) = queue.removeFirst();
    if (depth >= maxDepth) continue;
    final key = state.canonicalKey;
    for (final m in state.legalMoves()) {
      final next = state.apply(m);
      final nk = next.canonicalKey;
      if (!seen.add(nk)) continue;
      parent[nk] = (key, m);
      if (next.isSolved) {
        return _rebuild(start, nk, parent);
      }
      if (seen.length > maxStates) return null;
      queue.add((next, depth + 1));
    }
  }
  return null;
}

/// Moves stored in [parent] refer to tube indices of the state they were
/// generated from. Since we search over real (un-canonicalized) states the
/// indices along a single BFS path are consistent, so we replay them directly.
List<Move> _rebuild(BoardState start, String goalKey, Map<String, (String, Move)> parent) {
  final moves = <Move>[];
  var k = goalKey;
  final startKey = start.canonicalKey;
  while (k != startKey) {
    final (pk, m) = parent[k]!;
    moves.add(m);
    k = pk;
  }
  return moves.reversed.toList();
}
