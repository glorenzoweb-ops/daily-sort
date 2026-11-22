import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'background.dart';
import 'sound/ambience.dart';
import 'sound/engine.dart';
import 'sound/engine_native.dart' if (dart.library.js_interop) 'sound/engine_web.dart';
import 'sound/music.dart';
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

  static const _ambienceVolume = 0.55;
  static const _musicVolume = 0.5;

  /// The player's volume sliders, 0..1: pour sounds (notes, clinks, corks,
  /// chimes), the soundscape and the music.
  static double effectsLevel = 1, ambienceLevel = 1, musicLevel = 1;

  static void setEffectsLevel(double v) {
    effectsLevel = v.clamp(0.0, 1.0);
    enabled = effectsLevel > 0;
  }

  static void setAmbienceLevel(double v) {
    ambienceLevel = v.clamp(0.0, 1.0);
    _applyCalm(seconds: 0.3);
  }

  static void setMusicLevel(double v) {
    musicLevel = v.clamp(0.0, 1.0);
    try {
      if (_musicPlaying) _engine?.setLoopVolume('music', _musicVolume * musicLevel, seconds: 0.3);
    } catch (_) {}
  }

  /// Endless calm music: a slow pad plus a kalimba that wanders over the same
  /// notes as the pours, never repeating the same way twice.
  static bool music = false;
  static bool _musicPlaying = false;
  static Float32List? _pad;
  static Timer? _melody;
  static int _melodyNote = 4;

  /// How close the board is to solved, 0..1. The soundscape softens as you
  /// get there.
  static double _calm = 0;

  // One-shot sample indices after the notes and clinks.
  static int get _chime0 => scale.length + _clinkFreqs.length;
  static const _chimes = 3;
  static int get _birds => _chime0 + _chimes;
  static int get _pop => _birds + 1;

  /// A cork pops into a finished tube.
  static void pop() {
    if (enabled) _oneShot(_pop, 0.55 * effectsLevel);
  }

  /// Builds every sound without ever freezing the screen: the pour notes
  /// first (needed on the first tap), then the rest piece by piece in the
  /// background, then the saved soundscape and music so they start instantly.
  static Future<void> init() async {
    try {
      final e = createEngine();
      await e.load(await runInBackground(() => [for (final f in scale) pluck(f)]));
      await e.load(await runInBackground(() => [for (final f in _clinkFreqs) synthClink(f)]));
      _engine = e;
      for (var v = 0; v < _chimes; v++) {
        await e.load([await runInBackground(() => synthChime(v))]);
      }
      await e.load([await runInBackground(synthBirdsong)]);
      await e.load([await runInBackground(synthPop)]);
      await _prepareAmbience(ambience);
      if (music) await _preparePad();
    } catch (_) {
      // Sound is a nice-to-have; never block the game.
    }
  }

  static Future<Float32List?> _prepareAmbience(Ambience a) async {
    if (a == Ambience.off) return null;
    return _loops[a] ??= await runInBackground(() => synthAmbience(a));
  }

  static Future<Float32List>? _padJob;
  static Future<Float32List> _preparePad() async {
    final ready = _pad;
    if (ready != null) return ready;
    return _pad = await (_padJob ??= hasBackgroundThread
        ? runInBackground(() => synthPadAsync())
        : synthPadAsync(breathe));
  }

  /// The note a pour plays: its color, raised by how high it lands.
  static int noteFor(int color, int destSlot) => (color + destSlot).clamp(0, scale.length - 1);

  static void note(int index, {double volume = 0.8}) {
    if (!enabled) return;
    try {
      _engine?.play(index, volume * effectsLevel);
    } catch (_) {}
  }

  static void pour(int color, int destSlot) => note(noteFor(color, destSlot));

  static void tubeComplete(int color) {
    note(noteFor(color, 0) + 5 > 9 ? 9 : noteFor(color, 0) + 5, volume: 0.6);
    // A wind chime answers when a soundscape or music is on.
    if (ambience != Ambience.off || music) _oneShot(_chime0 + _rnd.nextInt(_chimes), 0.5 * effectsLevel);
  }

  /// The solve: the storm clears and the birds come out.
  static void solved() {
    if (ambience == Ambience.off && !music) return;
    _oneShot(_birds, 0.6 * ambienceLevel);
    _calm = 1;
    _applyCalm(seconds: 4);
  }

  /// Report board progress (0 = fresh, 1 = solved). The soundscape fades
  /// down to 40% as the tubes fill, and comes back with a new puzzle.
  static void setCalm(double progress) {
    final p = progress.clamp(0.0, 1.0);
    if ((p - _calm).abs() < 0.01) return;
    _calm = p;
    _applyCalm(seconds: p == 0 ? 4 : 2.5);
  }

  static void _applyCalm({required double seconds}) {
    try {
      _engine?.setLoopVolume('ambience', _ambienceVolume * ambienceLevel * (1 - 0.6 * _calm), seconds: seconds);
    } catch (_) {}
  }

  static void _oneShot(int index, double volume) {
    try {
      _engine?.play(index, volume);
    } catch (_) {}
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
    if (!_musicPlaying && music) setMusic(true);
  }

  static void setMusic(bool on) {
    music = on;
    final e = _engine;
    if (e == null) return;
    try {
      if (!on) {
        e.stopLoop('music');
        _melody?.cancel();
        _melody = null;
        _musicPlaying = false;
        return;
      }
      _musicPlaying = true;
      _preparePad().then((pad) {
        if (!music || !_musicPlaying) return;
        e.playLoop('music', pad, padRate, _musicVolume * musicLevel);
      });
      // The kalimba can start right away; the pad fades in when it's ready.
      _scheduleMelody(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// A kalimba that strolls up and down the scale: small steps, the odd
  /// leap, and rests, so it never plays the same tune twice.
  static void _scheduleMelody(Duration wait) {
    _melody?.cancel();
    _melody = Timer(wait, () {
      if (!music) return;
      if (_rnd.nextDouble() < 0.82) {
        final step = const [-2, -1, -1, 1, 1, 2][_rnd.nextInt(6)];
        _melodyNote = (_melodyNote + step).clamp(0, 7);
        _oneShot(_melodyNote, (0.14 + _rnd.nextDouble() * 0.1) * musicLevel);
        // Now and then a soft fifth above, like a second hand.
        if (_rnd.nextDouble() < 0.15) _oneShot((_melodyNote + 2).clamp(0, 9), 0.08 * musicLevel);
      }
      final ms = 1400 + _rnd.nextInt(2200);
      _scheduleMelody(Duration(milliseconds: ms));
    });
  }

  static void setAmbience(Ambience a) {
    ambience = a;
    final e = _engine;
    if (e == null) return;
    try {
      if (a == Ambience.off) {
        e.stopLoop('ambience');
        _ambiencePlaying = false;
        return;
      }
      _ambiencePlaying = true;
      _prepareAmbience(a).then((samples) {
        if (samples == null || ambience != a) return;
        e.playLoop('ambience', samples, ambienceRate, _ambienceVolume * ambienceLevel * (1 - 0.6 * _calm));
      });
    } catch (_) {}
  }
}
