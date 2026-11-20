import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'engine.dart';
import 'synth.dart';

NoteEngine createEngine() => _NativeEngine();

class _NativeEngine implements NoteEngine {
  // Two players per note so quick repeats overlap instead of cutting off.
  final List<List<AudioPlayer>> _players = [];
  final List<int> _next = [];
  AudioPlayer? _loop;

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
  Future<void> playLoop(Float32List samples, int rate, double volume) async {
    stopLoop();
    final p = _loop = AudioPlayer();
    await p.setReleaseMode(ReleaseMode.loop);
    await p.setVolume(volume);
    await p.play(BytesSource(toWav(samples, rate: rate), mimeType: 'audio/wav'));
  }

  @override
  void stopLoop() {
    final p = _loop;
    _loop = null;
    if (p != null) {
      p.stop();
      p.dispose();
    }
  }
}
