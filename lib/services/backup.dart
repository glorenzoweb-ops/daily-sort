import 'dart:convert';

import 'storage.dart';

/// A backup code moves your streak, stats, history and settings to a new
/// phone (or a new browser). It's everything this device saved, as one line
/// of text: `DS1-` and then base64.
///
/// No account and no server: the player keeps the code (notes, a message to
/// themselves) and pastes it on the new device.
class Backup {
  static const prefix = 'DS1-';
  static final _find = RegExp(r'DS1-[A-Za-z0-9_\-]+');

  final Map<String, Object?> data;
  final DateTime made;
  const Backup(this.data, this.made);

  /// What this device would save right now. Moves of solved days are left
  /// out: nothing reads them, and they are most of the size.
  static Backup of(Storage storage, {DateTime? now}) {
    final data = <String, Object?>{};
    for (final e in storage.exportAll().entries) {
      var v = e.value;
      if (e.key.startsWith('day_') && v is String) v = _slimDay(v);
      data[e.key] = v;
    }
    return Backup(data, now ?? DateTime.now());
  }

  static String _slimDay(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['solved'] == true) j['moves'] = const [];
      return jsonEncode(j);
    } catch (_) {
      return raw;
    }
  }

  String encode() {
    final json = jsonEncode({'v': 1, 't': made.millisecondsSinceEpoch, 'p': data});
    return prefix + base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  /// Finds a backup code in [text] (it may be pasted with a message around
  /// it). Null if there is none, or it is damaged.
  static Backup? parse(String text) {
    final m = _find.firstMatch(text.replaceAll(RegExp(r'\s'), ''));
    if (m == null) return null;
    try {
      final b64 = base64Url.normalize(m.group(0)!.substring(prefix.length));
      final j = jsonDecode(utf8.decode(base64Url.decode(b64))) as Map<String, dynamic>;
      if (j['v'] != 1) return null;
      final p = (j['p'] as Map).cast<String, Object?>();
      return Backup(p, DateTime.fromMillisecondsSinceEpoch(j['t'] as int));
    } catch (_) {
      return null;
    }
  }

  /// The stats inside the code, to show before restoring.
  Stats get stats {
    final raw = data['stats'];
    if (raw is! String) return Stats();
    try {
      return Stats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Stats();
    }
  }

  Future<void> restoreTo(Storage storage) => storage.replaceAll(data);
}

/// The text a player saves or sends to themselves.
String backupMessage(String code) =>
    'My Daily Sort backup. On the new phone, open Settings, tap Restore and paste this:\n\n$code';
