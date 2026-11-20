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
    final tine = math.sin(2 * math.pi * freq * 5.4 * t) * 0.08 * math.exp(-t * 28);
    out[i] = (0.42 * attack * (body + bell + tine)).toDouble();
  }
  return out;
}

/// 16-bit mono WAV file bytes (for the native audio player).
Uint8List toWav(Float32List samples) {
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
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
