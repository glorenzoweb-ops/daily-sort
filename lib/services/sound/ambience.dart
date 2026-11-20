import 'dart:math' as math;
import 'dart:typed_data';

/// Background soundscapes, synthesized (no audio files). Each is a seamless
/// 12-second loop at [ambienceRate].
enum Ambience { off, rain, waves, fireplace, night }

const int ambienceRate = 22050;
const double _seconds = 12;

String ambienceLabel(Ambience a) => switch (a) {
  Ambience.off => 'Off',
  Ambience.rain => 'Rain',
  Ambience.waves => 'Waves',
  Ambience.fireplace => 'Fireplace',
  Ambience.night => 'Night',
};

String ambienceEmoji(Ambience a) => switch (a) {
  Ambience.off => '🔇',
  Ambience.rain => '🌧️',
  Ambience.waves => '🌊',
  Ambience.fireplace => '🔥',
  Ambience.night => '🌙',
};

Float32List synthAmbience(Ambience a) {
  final rnd = math.Random(a.index * 7919 + 17);
  final n = (ambienceRate * _seconds).round();
  const fade = ambienceRate ~/ 2; // crossfade the tail into the head
  final raw = Float32List(n + fade);
  switch (a) {
    case Ambience.off:
      break;
    case Ambience.rain:
      _rain(raw, rnd);
    case Ambience.waves:
      _waves(raw, rnd);
    case Ambience.fireplace:
      _fire(raw, rnd);
    case Ambience.night:
      _night(raw, rnd);
  }
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = raw[i];
  }
  for (var i = 0; i < fade; i++) {
    final w = i / fade;
    out[i] = raw[i] * w + raw[n + i] * (1 - w);
  }
  // Even out loudness across soundscapes, and never clip.
  var sum = 0.0, peak = 0.0;
  for (final v in out) {
    sum += v * v;
    if (v.abs() > peak) peak = v.abs();
  }
  if (sum == 0) return out;
  var gain = 0.06 / math.sqrt(sum / n);
  if (peak * gain > 0.8) gain = 0.8 / peak;
  for (var i = 0; i < n; i++) {
    out[i] *= gain;
  }
  return out;
}

double _white(math.Random r) => r.nextDouble() * 2 - 1;

void _rain(Float32List o, math.Random r) {
  var lp = 0.0, lp2 = 0.0;
  for (var i = 0; i < o.length; i++) {
    final w = _white(r);
    lp += 0.35 * (w - lp); // soft hiss
    lp2 += 0.04 * (w - lp2); // low rumble
    o[i] = 0.16 * lp + 0.25 * lp2;
  }
  // Droplets: tiny bright ticks.
  final drops = (o.length / ambienceRate * 26).round();
  for (var d = 0; d < drops; d++) {
    final at = r.nextInt(o.length - 600);
    final f = 1800 + r.nextDouble() * 2400;
    final amp = 0.05 + r.nextDouble() * 0.07;
    for (var k = 0; k < 600; k++) {
      final t = k / ambienceRate;
      o[at + k] += amp * math.sin(2 * math.pi * f * t) * math.exp(-t * 160);
    }
  }
}

void _waves(Float32List o, math.Random r) {
  var b = 0.0, lp = 0.0;
  for (var i = 0; i < o.length; i++) {
    final w = _white(r);
    b = (b + 0.02 * w) * 0.998; // brown noise
    lp += 0.12 * (w - lp);
    final t = i / ambienceRate;
    // Two swells per loop (period divides 12 s, so it loops cleanly).
    final swell = math.pow(0.5 - 0.5 * math.cos(2 * math.pi * t / 6), 2).toDouble();
    o[i] = (2.2 * b + 0.18 * lp * swell) * (0.35 + 0.65 * swell) * 0.6;
  }
}

void _fire(Float32List o, math.Random r) {
  var b = 0.0;
  for (var i = 0; i < o.length; i++) {
    b = (b + 0.02 * _white(r)) * 0.997;
    o[i] = 2.0 * b * 0.5;
  }
  // Crackles and pops.
  final pops = (o.length / ambienceRate * 14).round();
  for (var p = 0; p < pops; p++) {
    final at = r.nextInt(o.length - 900);
    final amp = 0.08 + r.nextDouble() * 0.22;
    final len = 80 + r.nextInt(700);
    for (var k = 0; k < len; k++) {
      o[at + k] += amp * _white(r) * math.exp(-k / (len / 4));
    }
  }
}

void _night(Float32List o, math.Random r) {
  var lp = 0.0;
  for (var i = 0; i < o.length; i++) {
    lp += 0.02 * (_white(r) - lp);
    o[i] = 0.5 * lp; // soft air
  }
  // Crickets: groups of short 4.6 kHz chirps.
  var t0 = 0.3;
  while (t0 < _seconds - 1) {
    final f = 4300 + r.nextDouble() * 600;
    final amp = 0.025 + r.nextDouble() * 0.02;
    for (var c = 0; c < 3; c++) {
      final start = ((t0 + c * 0.07) * ambienceRate).round();
      for (var k = 0; k < (0.045 * ambienceRate).round(); k++) {
        final t = k / ambienceRate;
        final env = math.sin(math.pi * t / 0.045);
        if (start + k < o.length) o[start + k] += amp * env * math.sin(2 * math.pi * f * t);
      }
    }
    t0 += 0.6 + r.nextDouble() * 1.1;
  }
}
