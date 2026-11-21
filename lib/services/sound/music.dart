import 'dart:math' as math;
import 'dart:typed_data';

import 'synth.dart';

/// Sample rate of the music pad loop.
const int padRate = 22050;
const double _padSeconds = 32;

/// A slow, warm pad: four chords in C major (the same key as the pour notes),
/// eight seconds each, melting into each other. Every frequency is rounded so
/// it completes whole cycles in 32 s, which makes the loop seamless.
Float32List synthPad() {
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
    for (var i = start; i < n; i++) {
      final t = (i - start) / sampleRate;
      var v = 0.0;
      for (var p = 0; p < partials.length; p++) {
        v += amps[p] * math.sin(2 * math.pi * f * partials[p] * t) * math.exp(-t * (1.6 + p * 1.4));
      }
      out[i] += amp * v * (t < 0.003 ? t / 0.003 : 1);
    }
    at += 0.12 + r.nextDouble() * 0.3;
  }
  // Fade the very end so nothing clicks.
  for (var i = n - 2000; i < n; i++) {
    out[i] *= (n - i) / 2000;
  }
  return normalize(out, peak: 0.35);
}

/// Morning birdsong for a solve: two birds trading short chirps and trills.
Float32List synthBirdsong() {
  final r = math.Random(424242);
  final n = (sampleRate * 7.0).round();
  final out = Float32List(n);
  var t0 = 0.15;
  while (t0 < 6.2) {
    final bird = r.nextInt(2);
    final base = bird == 0 ? 3200.0 : 4300.0;
    final notes = 2 + r.nextInt(5);
    var at = t0;
    for (var k = 0; k < notes; k++) {
      final len = 0.05 + r.nextDouble() * 0.09;
      final f0 = base * (1.05 + r.nextDouble() * 0.35);
      final f1 = base * (0.7 + r.nextDouble() * 0.25);
      final start = (at * sampleRate).round();
      final m = (len * sampleRate).round();
      var phase = 0.0;
      for (var i = 0; i < m && start + i < n; i++) {
        final x = i / m;
        // Downward sweep with a tiny warble.
        final f = f0 + (f1 - f0) * x + 120 * math.sin(2 * math.pi * 38 * i / sampleRate);
        phase += 2 * math.pi * f / sampleRate;
        final env = math.sin(math.pi * x);
        out[start + i] += env * env * math.sin(phase) * (bird == 0 ? 1.0 : 0.7);
      }
      at += len + 0.02 + r.nextDouble() * 0.05;
    }
    t0 = at + 0.35 + r.nextDouble() * 0.9;
  }
  return normalize(out, peak: 0.22);
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
