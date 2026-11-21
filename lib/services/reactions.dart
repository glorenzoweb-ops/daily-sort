import 'dart:convert';

import 'friends.dart';
import 'share.dart';
import 'storage.dart';

/// The reactions you can send to a friend's result.
const reactionEmoji = ['👏', '🔥', '😮', '😂'];

/// A reaction to one daily result. Like results, it travels in a link
/// (`?x=2-1-Ana`: puzzle 2, 🔥, from Ana), so no server is needed.
class Reaction {
  final int number;
  final int emoji;
  final String from;
  const Reaction({required this.number, required this.emoji, required this.from});

  String get symbol => reactionEmoji[emoji];

  String encode() => '$number-$emoji-${Uri.encodeComponent(from)}';

  static Reaction? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('-');
    if (parts.length < 3) return null;
    final number = int.tryParse(parts[0]);
    final emoji = int.tryParse(parts[1]);
    if (number == null || number < 1 || number > 100000) return null;
    if (emoji == null || emoji < 0 || emoji >= reactionEmoji.length) return null;
    String from;
    try {
      from = cleanName(Uri.decodeComponent(parts.skip(2).join('-')));
    } catch (_) {
      return null;
    }
    if (from.isEmpty) from = 'A friend';
    return Reaction(number: number, emoji: emoji, from: from);
  }

  Map<String, dynamic> toJson() => {'p': number, 'e': emoji, 'f': from};
  static Reaction fromJson(Map<String, dynamic> j) =>
      Reaction(number: j['p'] as int, emoji: j['e'] as int, from: j['f'] as String);
}

/// Reactions received and sent, kept on this device for a month.
class Reactions {
  final Storage storage;
  Reactions(this.storage);

  static const keepDays = 30;

  List<Reaction> get received {
    final raw = storage.reactionsRaw;
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => Reaction.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Saves a reaction from a link. One per friend per day: a new one
  /// replaces the old. Returns false for your own.
  Future<bool> receive(Reaction r, {required int today}) async {
    final me = storage.myName;
    if (me.isNotEmpty && r.from.toLowerCase() == me.toLowerCase()) return false;
    final list = received
      ..removeWhere((e) => e.number == r.number && e.from.toLowerCase() == r.from.toLowerCase())
      ..removeWhere((e) => e.number < today - keepDays)
      ..add(r);
    await storage.setReactionsRaw(jsonEncode(list.map((e) => e.toJson()).toList()));
    return true;
  }

  List<Reaction> forDay(int number) => received.where((r) => r.number == number).toList();

  Map<String, int> get _sent {
    final raw = storage.sentReactionsRaw;
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as int));
    } catch (_) {
      return {};
    }
  }

  /// The emoji you sent [name] for puzzle [number], if any.
  int? sentTo(String name, int number) => _sent['$number:${name.toLowerCase()}'];

  Future<void> markSent(String name, int number, int emoji, {required int today}) async {
    final m = _sent..['$number:${name.toLowerCase()}'] = emoji;
    m.removeWhere((k, _) => (int.tryParse(k.split(':').first) ?? 0) < today - keepDays);
    await storage.setSentReactionsRaw(jsonEncode(m));
  }
}

/// The message and link that carry a reaction (and your own result, when
/// you have one, so it lands on their board too).
String buildReactionText({
  required String to,
  required int number,
  required int toMoves,
  required int emoji,
  required String from,
  String? myResult,
}) {
  final link =
      '$shareUrl?x=${Reaction(number: number, emoji: emoji, from: from).encode()}'
      '${myResult == null ? '' : '&r=$myResult'}';
  final line = switch (emoji) {
    0 => 'nice sort',
    1 => 'on fire',
    2 => 'how?!',
    _ => 'haha',
  };
  return '${reactionEmoji[emoji]} $to, $line: $toMoves moves on Daily Sort #$number!\n$link';
}
