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
  final Map<int, int> _lastPlay = {};

  Future<void>? _ready;
  Future<void> _init() => _ready ??= _start();

  /// The mix runs on its own thread, 4096 frames (85 ms) ahead of the
  /// speaker, so a busy moment (a page sliding in, a sound loading) can't
  /// leave the speaker without audio, which is heard as a screech. 48 kHz is
  /// what iPhones play at, so the output needs no conversion. A limiter on
  /// the whole mix keeps many notes at once from clipping.
  Future<void> _start() async {
    if (!_soloud.isInitialized) {
      await _soloud.init(sampleRate: 48000, bufferSize: 1024, devicePeriodFrames: 512, renderAheadFrames: 4096);
    }
    try {
      _soloud.setMaxActiveVoiceCount(24);
      final limiter = _soloud.filters.limiterFilter;
      if (!limiter.isActive) limiter.activate();
      limiter.threshold.value = -6;
      limiter.outputCeiling.value = -1.5;
      limiter.releaseTime.value = 120;
    } catch (_) {}
  }

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
    // The same sound twice within 30 ms only adds up into a harsh spike.
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now - (_lastPlay[note] ?? 0) < 30000) return;
    _lastPlay[note] = now;
    _soloud.play(_notes[note], volume: volume);
  }

  @override
  Future<void> playLoop(String channel, Float32List samples, int rate, double volume) async {
    stopLoop(channel);
    await _init();
    final source = await _soloud.loadMem('loop${_loopCount++}.wav', toWav(samples, rate: rate));
    // Fade in, so a loop never starts with a click.
    final handle = _soloud.play(source, volume: 0, looping: true);
    _soloud.fadeVolume(handle, volume, const Duration(milliseconds: 1500));
    _loops[channel] = (source, handle);
  }

  @override
  void stopLoop(String channel) {
    final loop = _loops.remove(channel);
    if (loop == null) return;
    final (source, handle) = loop;
    // Fade out, then free it: stopping mid-wave clicks.
    try {
      _soloud.fadeVolume(handle, 0, const Duration(milliseconds: 600));
      _soloud.scheduleStop(handle, const Duration(milliseconds: 650));
    } catch (_) {}
    Future<void>.delayed(const Duration(milliseconds: 800), () => _soloud.disposeSource(source));
  }

  @override
  void setLoopVolume(String channel, double volume, {double seconds = 2.5}) {
    final loop = _loops[channel];
    if (loop == null) return;
    _soloud.fadeVolume(loop.$2, volume, Duration(milliseconds: (seconds * 1000).round()));
  }
}
