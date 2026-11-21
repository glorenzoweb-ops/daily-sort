import 'dart:convert';

import 'storage.dart';

/// A daily result someone sent you (or yours, ready to send).
///
/// There is no server: results travel inside the share link
/// (`...daily-sort/?r=2-13-1-5-Ana`). When a friend opens your link, you
/// land on their board, and when they share back, they land on yours. That
/// is how daily-puzzle groups already work in group chats.
class FriendResult {
  final String name;
  final int number;
  final int moves;
  final int attempts;
  final int streak;

  const FriendResult({
    required this.name,
    required this.number,
    required this.moves,
    this.attempts = 1,
    this.streak = 0,
  });

  /// Short and readable in a link: number-moves-attempts-streak-name.
  String encode() => '$number-$moves-$attempts-$streak-${Uri.encodeComponent(name)}';

  static FriendResult? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length < 5) return null;
    final nums = parts.take(4).map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    final [number!, moves!, attempts!, streak!] = nums;
    if (number < 1 || number > 100000 || moves < 1 || moves > 99) return null;
    if (attempts < 1 || attempts > 999 || streak < 0 || streak > 100000) return null;
    String name;
    try {
      name = Uri.decodeComponent(parts.skip(4).join('-'));
    } catch (_) {
      return null;
    }
    name = cleanName(name);
    if (name.isEmpty) name = 'A friend';
    return FriendResult(name: name, number: number, moves: moves, attempts: attempts, streak: streak);
  }

  Map<String, dynamic> toJson() => {'n': name, 'p': number, 'm': moves, 'a': attempts, 's': streak};

  static FriendResult fromJson(Map<String, dynamic> j) => FriendResult(
    name: j['n'] as String,
    number: j['p'] as int,
    moves: j['m'] as int,
    attempts: j['a'] as int? ?? 1,
    streak: j['s'] as int? ?? 0,
  );
}

/// Trims, drops control characters and keeps names short.
String cleanName(String raw) {
  final s = raw.replaceAll(RegExp(r'[\u0000-\u001F\u007F<>]'), '').trim().replaceAll(RegExp(r'\s+'), ' ');
  return s.length > 16 ? s.substring(0, 16).trim() : s;
}

/// Friends' results kept on this device.
class Friends {
  final Storage storage;
  Friends(this.storage);

  static const keepDays = 30;

  List<FriendResult> get all {
    final raw = storage.friendsRaw;
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => FriendResult.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds (or replaces) a friend's result for that day. Ignores your own.
  Future<bool> add(FriendResult r, {required int today}) async {
    final me = storage.myName;
    if (me.isNotEmpty && r.name.toLowerCase() == me.toLowerCase()) return false;
    final list = all
      ..removeWhere((e) => e.number == r.number && e.name.toLowerCase() == r.name.toLowerCase())
      ..removeWhere((e) => e.number < today - keepDays)
      ..add(r);
    await storage.setFriendsRaw(jsonEncode(list.map((e) => e.toJson()).toList()));
    return true;
  }

  /// Everyone who has ever sent you a result, most recent first.
  List<String> get names {
    final seen = <String>{};
    final out = <String>[];
    for (final r in all.reversed) {
      if (seen.add(r.name.toLowerCase())) out.add(r.name);
    }
    return out;
  }

  List<FriendResult> forDay(int number) => all.where((r) => r.number == number).toList();
}

/// A row on the friends board.
class BoardEntry {
  final String name;
  final int moves;
  final int attempts;
  final int streak;
  final bool isMe;
  const BoardEntry(this.name, this.moves, this.attempts, this.streak, {this.isMe = false});
}

/// Fewest moves first, then fewest tries.
List<BoardEntry> rankDay(List<FriendResult> friends, {BoardEntry? me}) {
  final rows = [for (final f in friends) BoardEntry(f.name, f.moves, f.attempts, f.streak), ?me];
  rows.sort((a, b) {
    final m = a.moves.compareTo(b.moves);
    if (m != 0) return m;
    final t = a.attempts.compareTo(b.attempts);
    if (t != 0) return t;
    return (a.isMe ? 0 : 1).compareTo(b.isMe ? 0 : 1);
  });
  return rows;
}
