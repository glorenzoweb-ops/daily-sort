import 'package:flutter/services.dart';

/// Haptics in one place, so they can be switched off and tuned together.
/// On web these are no-ops (browsers mostly don't expose vibration).
class Haptics {
  static bool enabled = true;

  static void select() {
    if (enabled) HapticFeedback.selectionClick();
  }

  static void land() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void invalid() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  static void tubeComplete() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static Future<void> win() async {
    if (!enabled) return;
    for (var i = 0; i < 3; i++) {
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
    HapticFeedback.heavyImpact();
  }
}
