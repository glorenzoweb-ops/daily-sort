import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'engine.dart';
import 'synth.dart';

NoteEngine createEngine() => _NativeEngine();

class _NativeEngine implements NoteEngine {
  // Two players per note so quick repeats overlap instead of cutting off.
  final List<List<AudioPlayer>> _players = [];
  final List<int> _next = [];
  final Map<String, AudioPlayer> _loops = {};
  final Map<String, double> _loopVolume = {};
  final Map<String, Timer> _glides = {};

  @override
  Future<void> load(List<Float32List> notes) async {
    for (final n in notes) {
      final bytes = toWav(n);
      final pair = <AudioPlayer>[];
      for (var k = 0; k < 2; k++) {
        final p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(BytesSource(bytes, mimeType: 'audio/wav'));
        pair.add(p);
      }
      _players.add(pair);
      _next.add(0);
    }
  }

  @override
  void play(int note, double volume) {
    if (note < 0 || note >= _players.length) return;
    final p = _players[note][_next[note]];
    _next[note] = (_next[note] + 1) % _players[note].length;
    p.setVolume(volume);
    p.seek(Duration.zero).then((_) => p.resume());
  }

  @override
  Future<void> playLoop(String channel, Float32List samples, int rate, double volume) async {
    stopLoop(channel);
    final p = _loops[channel] = AudioPlayer();
    _loopVolume[channel] = volume;
    await p.setReleaseMode(ReleaseMode.loop);
    await p.setVolume(volume);
    await p.play(BytesSource(toWav(samples, rate: rate), mimeType: 'audio/wav'));
  }

  @override
  void stopLoop(String channel) {
    _glides.remove(channel)?.cancel();
    final p = _loops.remove(channel);
    if (p != null) {
      p.stop();
      p.dispose();
    }
  }

  @override
  void setLoopVolume(String channel, double volume, {double seconds = 2.5}) {
    final p = _loops[channel];
    if (p == null) return;
    _glides.remove(channel)?.cancel();
    final from = _loopVolume[channel] ?? volume;
    const step = Duration(milliseconds: 100);
    final steps = (seconds * 10).round().clamp(1, 1000);
    var k = 0;
    _glides[channel] = Timer.periodic(step, (t) {
      k++;
      final v = from + (volume - from) * (k / steps);
      _loopVolume[channel] = v;
      p.setVolume(v);
      if (k >= steps) {
        t.cancel();
        _glides.remove(channel);
      }
    });
  }
}
