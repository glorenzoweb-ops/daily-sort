import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 44100;

/// Two octaves of C-major pentatonic: anything you play sounds pleasant.
const List<double> scale = [
  523.25, 587.33, 659.25, 783.99, 880.00, // C5 D5 E5 G5 A5
  1046.50, 1174.66, 1318.51, 1567.98, 1760.00, // C6 D6 E6 G6 A6
];

/// A soft kalimba-like pluck, synthesized so the app ships no audio files.
Float32List pluck(double freq, {double seconds = 0.9}) {
  final n = (sampleRate * seconds).round();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final attack = t < 0.004 ? t / 0.004 : 1.0;
    final body = math.sin(2 * math.pi * freq * t) * math.exp(-t * 5.5);
    final bell = math.sin(2 * math.pi * freq * 2.0 * t) * 0.28 * math.exp(-t * 11);
    // The metal tine, left out where it would ring above 9 kHz (harsh on
    // phone speakers).
    final tine = freq * 5.4 > 9000 ? 0.0 : math.sin(2 * math.pi * freq * 5.4 * t) * 0.08 * math.exp(-t * 28);
    out[i] = (0.42 * attack * (body + bell + tine)).toDouble();
  }
  return out;
}

/// 16-bit mono WAV file bytes (for the native audio player).
Uint8List toWav(Float32List samples, {int rate = sampleRate}) {
  final data = ByteData(44 + samples.length * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// A short glass "clink" for when balls land: inharmonic partials that die
/// out fast, like tapping a glass tube.
Float32List synthClink(double freq) {
  final n = (sampleRate * 0.35).round();
  final out = Float32List(n);
  const partials = [1.0, 2.76, 5.40, 8.93];
  const amps = [1.0, 0.5, 0.25, 0.12];
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    var v = 0.0;
    for (var p = 0; p < partials.length; p++) {
      // Partials above 9 kHz sounded like a screech (and some went past what
      // the sample rate can hold, folding back as noise).
      if (freq * partials[p] > 9000) continue;
      v += amps[p] * math.sin(2 * math.pi * freq * partials[p] * t) * math.exp(-t * (14 + p * 9));
    }
    out[i] = (0.22 * v * (t < 0.002 ? t / 0.002 : 1)).toDouble();
  }
  return out;
}

/// The music's own instrument: a soft felt music box an octave below the
/// pours, with a slow, rounded attack, so the soundtrack never sounds like a
/// ball landing.
Float32List synthFelt(double freq) {
  final n = (sampleRate * 2.4).round();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final attack = t < 0.035 ? math.sin(t / 0.035 * math.pi / 2) : 1.0;
    final body = math.sin(2 * math.pi * freq * t) * math.exp(-t * 1.6);
    final warm = math.sin(2 * math.pi * freq * 2 * t + 0.6) * 0.22 * math.exp(-t * 3.2);
    final air = math.sin(2 * math.pi * freq * 3 * t) * 0.06 * math.exp(-t * 6);
    out[i] = 0.5 * attack * (body + warm + air);
  }
  for (var i = n - 3000; i < n; i++) {
    out[i] *= (n - i) / 3000;
  }
  return out;
}
