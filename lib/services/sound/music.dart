import 'dart:math' as math;
import 'dart:typed_data';

import 'synth.dart';

/// Sample rate of the music pad loop.
const int padRate = 22050;
const double _padSeconds = 32;

/// A slow, warm pad: four chords in C major (the same key as the pour notes),
/// eight seconds each, melting into each other. Every frequency is rounded so
/// it completes whole cycles in 32 s, which makes the loop seamless.
Future<Float32List> synthPadAsync([Future<void> Function()? pause]) async {
  final n = (padRate * _padSeconds).round();
  final out = Float32List(n);
  const chords = [
    [130.81, 164.81, 196.00, 293.66], // Cadd9
    [110.00, 130.81, 164.81, 196.00], // Am7
    [87.31, 130.81, 174.61, 220.00], // F
    [98.00, 146.83, 196.00, 246.94], // G
  ];
  double lock(double f) => (f * _padSeconds).roundToDouble() / _padSeconds;
  const seg = _padSeconds / 4;
  for (var c = 0; c < chords.length; c++) {
    final center = c * seg + seg / 2;
    // Cyclic distance from the chord's center, so the last chord fades into
    // the first across the loop seam.
    final env = Float32List(n);
    for (var i = 0; i < n; i++) {
      var d = (i / padRate - center).abs();
      if (d > _padSeconds / 2) d = _padSeconds - d;
      env[i] = d >= seg ? 0 : 0.5 + 0.5 * math.cos(d / seg * math.pi);
    }
    for (final base in chords[c]) {
      // Two slightly detuned voices plus a soft octave: a gentle chorus.
      final voices = [lock(base - 0.4), lock(base + 0.4), lock(base * 2 + 0.25)];
      const amps = [1.0, 1.0, 0.25];
      for (var v = 0; v < voices.length; v++) {
        await pause?.call(); // let a frame paint between voices
        // Oscillator by rotation: much cheaper than sin() per sample.
        final dw = 2 * math.pi * voices[v] / padRate;
        final cs = math.cos(dw), sn = math.sin(dw);
        var x = 1.0, y = 0.0;
        for (var i = 0; i < n; i++) {
          if (env[i] > 0) out[i] += amps[v] * env[i] * y;
          final nx = x * cs - y * sn;
          y = x * sn + y * cs;
          x = nx;
        }
      }
    }
  }
  return normalize(out, rms: 0.05, peak: 0.6);
}

/// A wind chime tuned to the high pour notes: a few bell strikes that ring
/// out. [variant] picks a different pattern.
Float32List synthChime(int variant) {
  final r = math.Random(variant * 31 + 5);
  final n = (sampleRate * 3.0).round();
  final out = Float32List(n);
  const partials = [1.0, 2.0, 3.01, 4.17];
  const amps = [1.0, 0.35, 0.18, 0.08];
  var at = 0.0;
  for (var s = 0; s < 5; s++) {
    final f = scale[5 + r.nextInt(5)];
    final amp = 0.5 + r.nextDouble() * 0.5;
    final start = (at * sampleRate).round();
    // Each partial is a decaying oscillator stepped by rotation, which is
    // ~10x cheaper than calling sin() and exp() for every sample.
    for (var p = 0; p < partials.length; p++) {
      final dw = 2 * math.pi * f * partials[p] / sampleRate;
      final decay = math.exp(-(1.6 + p * 1.4) / sampleRate);
      final cs = math.cos(dw) * decay, sn = math.sin(dw) * decay;
      var x = amp * amps[p], y = 0.0;
      for (var i = start; i < n; i++) {
        final k = i - start;
        out[i] += k < 132 ? y * k / 132 : y; // 3 ms attack
        final nx = x * cs - y * sn;
        y = x * sn + y * cs;
        x = nx;
      }
    }
    at += 0.12 + r.nextDouble() * 0.3;
  }
  // Fade the very end so nothing clicks.
  for (var i = n - 2000; i < n; i++) {
    out[i] *= (n - i) / 2000;
  }
  return normalize(out, peak: 0.35);
}

/// The solve, when a soundscape or music is on: a warm chord rolled upward
/// on the music's felt notes (C4 E4 G4 C5 E5), like a sigh of relief. It
/// replaced a synthesized birdsong whose 3 to 4 kHz chirps sounded shrill on
/// phone speakers.
Float32List synthSunrise() {
  final n = (sampleRate * 4.0).round();
  final out = Float32List(n);
  const notes = [261.63, 329.63, 392.00, 523.25, 659.25];
  for (var k = 0; k < notes.length; k++) {
    final note = synthFelt(notes[k]);
    final start = (k * 0.11 * sampleRate).round();
    final amp = 1.0 - k * 0.12;
    for (var i = 0; i < note.length && start + i < n; i++) {
      out[start + i] += note[i] * amp;
    }
  }
  for (var i = n - 4000; i < n; i++) {
    out[i] *= (n - i) / 4000;
  }
  return normalize(out, peak: 0.3);
}

/// A soft cork "pop": a quick falling thump with a breath of air.
Float32List synthPop() {
  final r = math.Random(99);
  final n = (sampleRate * 0.16).round();
  final out = Float32List(n);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final f = 520 * math.exp(-t * 28) + 140;
    phase += 2 * math.pi * f / sampleRate;
    final env = (t < 0.002 ? t / 0.002 : 1) * math.exp(-t * 38);
    out[i] = env * (math.sin(phase) + 0.25 * (r.nextDouble() * 2 - 1) * math.exp(-t * 90));
  }
  return normalize(out, peak: 0.5);
}

/// Scales [out] in place to the given loudness ([rms]) without exceeding
/// [peak], and returns it.
Float32List normalize(Float32List out, {double? rms, double peak = 0.8}) {
  var sum = 0.0, top = 0.0;
  for (final v in out) {
    sum += v * v;
    if (v.abs() > top) top = v.abs();
  }
  if (top == 0) return out;
  var gain = rms == null ? peak / top : rms / math.sqrt(sum / out.length);
  if (top * gain > peak) gain = peak / top;
  for (var i = 0; i < out.length; i++) {
    out[i] *= gain;
  }
  return out;
}
