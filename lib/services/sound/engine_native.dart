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

  /// A 2048-frame buffer at 48 kHz (43 ms, the iPhone's own rate). The
  /// render-ahead ring tried before left ~100 ms gaps of silence mid-sound,
  /// heard as cracks. A limiter only catches peaks: its threshold is also a
  /// "drive" (below 0 dB it boosts everything first), so it stays at 0 dB.
  Future<void> _start() async {
    if (!_soloud.isInitialized) await _soloud.init(sampleRate: 48000, bufferSize: 2048);
    try {
      _soloud.setMaxActiveVoiceCount(24);
      final limiter = _soloud.filters.limiterFilter;
      if (!limiter.isActive) limiter.activate();
      limiter.threshold.value = 0;
      limiter.outputCeiling.value = -1;
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
