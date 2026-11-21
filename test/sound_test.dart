import 'dart:math' as math;

import 'package:daily_sort/services/sound/ambience.dart';
import 'package:daily_sort/services/sound/music.dart';
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

  test('music pad is soft, never clips, and loops seamlessly', () async {
    final sw = Stopwatch()..start();
    final s = await synthPadAsync();
    // ignore: avoid_print
    print('pad synthesized in ${sw.elapsedMilliseconds} ms');
    expect(s.length, padRate * 32);
    var peak = 0.0, sum = 0.0, maxStep = 0.0;
    for (var i = 0; i < s.length; i++) {
      expect(s[i].isFinite, isTrue);
      peak = math.max(peak, s[i].abs());
      sum += s[i] * s[i];
      if (i > 0) maxStep = math.max(maxStep, (s[i] - s[i - 1]).abs());
    }
    final rms = math.sqrt(sum / s.length);
    expect(peak, lessThanOrEqualTo(0.6));
    expect(rms, inInclusiveRange(0.02, 0.1));
    // The seam is no bigger a jump than any step inside the loop.
    expect((s.last - s.first).abs(), lessThanOrEqualTo(maxStep * 1.5));
  });

  test('wind chimes and birdsong are gentle', () {
    for (var v = 0; v < 3; v++) {
      final c = synthChime(v);
      expect(c.map((x) => x.abs()).reduce(math.max), lessThanOrEqualTo(0.36));
      expect(c.last.abs(), lessThan(0.01));
    }
    final b = synthBirdsong();
    final peak = b.map((x) => x.abs()).reduce(math.max);
    expect(peak, inInclusiveRange(0.1, 0.23));
  });
}
