import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ui/perf_log.dart';

/// Haptics in one place, so they can be switched off and tuned together.
/// On web these are no-ops (browsers mostly don't expose vibration).
///
/// On iPhone they go through prepared, reused generators (AppDelegate.swift):
/// a cold Taptic Engine stalls the app for a moment and cracks the sound.
/// Taps are also spaced out: at most one every 70 ms, and a weaker one never
/// follows a stronger one that just played (a landing that completes a tube
/// is one tap, not two).
class Haptics {
  static bool enabled = true;

  static const _channel = MethodChannel('daily_sort/taps');
  static bool get _native => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool _nativeWorks = true;

  static int _lastAt = 0, _lastStrength = 0;

  /// Wakes the generators ahead of the first tap (call at launch).
  static void prepare() {
    if (enabled && _native) _send('prepare');
  }

  static void _tap(String kind, int strength, VoidCallback fallback) {
    if (!enabled) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAt < 70 && strength <= _lastStrength) return;
    _lastAt = now;
    _lastStrength = strength;
    if (_native && _nativeWorks) {
      _send(kind);
    } else {
      fallback();
    }
  }

  static Future<void> _send(String kind) async {
    try {
      final micros = await _channel.invokeMethod<Object?>(kind);
      if (micros is int) PerfLog.record('haptic: $kind (on iPhone)', micros / 1000);
    } on MissingPluginException {
      _nativeWorks = false;
    } catch (_) {}
  }

  static void select() => _tap('selection', 1, HapticFeedback.selectionClick);

  static void land() => _tap('light', 2, HapticFeedback.lightImpact);

  static void tubeComplete() => _tap('medium', 3, HapticFeedback.mediumImpact);

  static void invalid() => _tap('heavy', 4, HapticFeedback.heavyImpact);

  /// One "success" tap instead of a burst of four.
  static Future<void> win() async {
    _lastAt = 0; // always felt
    _tap('success', 5, HapticFeedback.heavyImpact);
  }
}
