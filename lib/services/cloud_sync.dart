import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'backup.dart';
import 'storage.dart';

/// Streak, stats and history kept in the player's iCloud (key-value store),
/// so a new iPhone or a reinstall picks up where they left off. It is the
/// same data as a backup code, saved for them.
///
/// The copy with more solved puzzles wins: a device that is behind never
/// overwrites iCloud, and a fresh install takes the iCloud copy. iPhone only;
/// it needs the iCloud "Key-value storage" capability in Xcode, and without
/// it nothing syncs (and nothing breaks).
class CloudSync {
  static const _channel = MethodChannel('daily_sort/cloud');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<Backup?> _cloud() async {
    final raw = await _channel.invokeMethod<String>('get');
    return raw == null ? null : Backup.parse(raw);
  }

  /// Saves this device's progress to iCloud, unless iCloud holds more.
  static Future<void> push(Storage storage) async {
    if (!supported) return;
    try {
      final cloud = await _cloud();
      if (cloud != null && cloud.stats.solved > storage.stats.solved) return;
      final b = Backup.of(storage);
      await _channel.invokeMethod<void>('set', b.encode());
      await storage.setCloudSavedAt(b.made.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('iCloud: $e');
    }
  }

  /// On a device with nothing solved yet, takes the iCloud copy if it has
  /// progress. True when it did.
  static Future<bool> restoreIfNew(Storage storage) async {
    if (!supported || storage.stats.solved > 0) return false;
    try {
      final cloud = await _cloud().timeout(const Duration(seconds: 2));
      if (cloud == null || cloud.stats.solved == 0) return false;
      await cloud.restoreTo(storage);
      return true;
    } catch (e) {
      debugPrint('iCloud: $e');
      return false;
    }
  }
}
