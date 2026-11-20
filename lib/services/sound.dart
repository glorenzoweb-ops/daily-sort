import 'sound/engine.dart';
import 'sound/engine_native.dart' if (dart.library.js_interop) 'sound/engine_web.dart';
import 'sound/synth.dart';

/// Every color is a note. Each pour plays one, and your whole solve becomes a
/// little melody ("your solve song").
class Sounds {
  static bool enabled = true;
  static NoteEngine? _engine;

  static Future<void> init() async {
    try {
      final e = createEngine();
      await e.load([for (final f in scale) pluck(f)]);
      _engine = e;
    } catch (_) {
      _engine = null; // sound is a nice-to-have; never block the game
    }
  }

  /// The note a pour plays: its color, raised by how high it lands.
  static int noteFor(int color, int destSlot) => (color + destSlot).clamp(0, scale.length - 1);

  static void note(int index, {double volume = 0.8}) {
    if (!enabled) return;
    try {
      _engine?.play(index, volume);
    } catch (_) {}
  }

  static void pour(int color, int destSlot) => note(noteFor(color, destSlot));

  static void tubeComplete(int color) {
    note(noteFor(color, 0) + 5 > 9 ? 9 : noteFor(color, 0) + 5, volume: 0.6);
  }

  static Future<void> win() async {
    for (final n in const [0, 2, 4, 7, 9]) {
      note(n, volume: 0.7);
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
  }

  static void invalid() => note(0, volume: 0.25);
}
