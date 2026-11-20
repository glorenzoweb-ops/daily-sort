import 'dart:math' as math;
import 'dart:typed_data';

import 'sound/ambience.dart';
import 'sound/engine.dart';
import 'sound/engine_native.dart' if (dart.library.js_interop) 'sound/engine_web.dart';
import 'sound/synth.dart';

/// Every color is a note. Each pour plays one, and your whole solve becomes a
/// little melody ("your solve song").
class Sounds {
  static bool enabled = true;
  static NoteEngine? _engine;

  static const _clinkFreqs = [2200.0, 2550.0, 2950.0];
  static final _rnd = math.Random();

  /// The chosen background soundscape. Browsers only allow audio to start
  /// from a tap, so a saved choice starts on the first tap ([wake]).
  static Ambience ambience = Ambience.off;
  static bool _ambiencePlaying = false;
  static final Map<Ambience, Float32List> _loops = {};

  static Future<void> init() async {
    try {
      final e = createEngine();
      await e.load([for (final f in scale) pluck(f), for (final f in _clinkFreqs) synthClink(f)]);
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

  /// Soft glass clink when balls land.
  static void clink() => note(scale.length + _rnd.nextInt(_clinkFreqs.length), volume: 0.35);

  /// Call from any tap: starts the saved soundscape once audio is allowed.
  static void wake() {
    if (!_ambiencePlaying && ambience != Ambience.off) setAmbience(ambience);
  }

  static void setAmbience(Ambience a) {
    ambience = a;
    final e = _engine;
    if (e == null) return;
    try {
      if (a == Ambience.off) {
        e.stopLoop();
        _ambiencePlaying = false;
        return;
      }
      final samples = _loops[a] ??= synthAmbience(a);
      e.playLoop(samples, ambienceRate, 0.55);
      _ambiencePlaying = true;
    } catch (_) {}
  }
}
