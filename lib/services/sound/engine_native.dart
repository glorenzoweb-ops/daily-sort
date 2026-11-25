import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'engine.dart';
import 'synth.dart';

NoteEngine createEngine() => _NativeEngine();

/// Every sound goes through one mixer (SoLoud) on a single audio stream.
/// The audio session is opened once, not on every note, so quick pours never
/// stall and many notes can ring at the same time.
class _NativeEngine implements NoteEngine {
  final _soloud = SoLoud.instance;
  final List<AudioSource> _notes = [];
  final Map<String, (AudioSource, SoundHandle)> _loops = {};
  int _loopCount = 0;

  Future<void>? _ready;
  Future<void> _init() => _ready ??= _soloud.isInitialized ? Future.value() : _soloud.init(bufferSize: 1024);

  @override
  Future<void> load(List<Float32List> notes) async {
    await _init();
    for (final n in notes) {
      _notes.add(await _soloud.loadMem('note${_notes.length}.wav', toWav(n)));
    }
  }

  @override
  void play(int note, double volume) {
    if (note < 0 || note >= _notes.length || !_soloud.isInitialized) return;
    _soloud.play(_notes[note], volume: volume);
  }

  @override
  Future<void> playLoop(String channel, Float32List samples, int rate, double volume) async {
    stopLoop(channel);
    await _init();
    final source = await _soloud.loadMem('loop${_loopCount++}.wav', toWav(samples, rate: rate));
    final handle = _soloud.play(source, volume: volume, looping: true);
    _loops[channel] = (source, handle);
  }

  @override
  void stopLoop(String channel) {
    final loop = _loops.remove(channel);
    if (loop == null) return;
    final (source, handle) = loop;
    _soloud.stop(handle).then((_) => _soloud.disposeSource(source));
  }

  @override
  void setLoopVolume(String channel, double volume, {double seconds = 2.5}) {
    final loop = _loops[channel];
    if (loop == null) return;
    _soloud.fadeVolume(loop.$2, volume, Duration(milliseconds: (seconds * 1000).round()));
  }
}
