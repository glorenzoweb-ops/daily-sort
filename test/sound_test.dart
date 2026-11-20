import 'dart:math' as math;

import 'package:daily_sort/services/sound/ambience.dart';
import 'package:daily_sort/services/sound/synth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('soundscapes are audible, never clip, and loop without a click', () {
    for (final a in Ambience.values.where((a) => a != Ambience.off)) {
      final s = synthAmbience(a);
      expect(s.length, ambienceRate * 12);
      var peak = 0.0, sum = 0.0;
      for (final v in s) {
        expect(v.isFinite, isTrue);
        peak = math.max(peak, v.abs());
        sum += v * v;
      }
      final rms = math.sqrt(sum / s.length);
      // ignore: avoid_print
      print('${a.name}: rms ${rms.toStringAsFixed(3)} peak ${peak.toStringAsFixed(2)}');
      expect(peak, lessThan(1.0), reason: a.name);
      expect(rms, inInclusiveRange(0.01, 0.3), reason: a.name);
      // Seam: the jump from the last sample back to the first is small.
      expect((s.last - s.first).abs(), lessThan(0.25), reason: a.name);
    }
  });

  test('clink is short and quiet', () {
    final c = synthClink(2500);
    expect(c.reduce(math.max), lessThan(0.5));
  });
}
