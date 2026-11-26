import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'engine.dart';
import 'synth.dart';

NoteEngine createEngine() => _WebEngine();

class _Loop {
  final web.AudioBufferSourceNode src;
  final web.GainNode gain;
  _Loop(this.src, this.gain);
}

/// Web Audio: sample-accurate, polyphonic, and works on iOS Safari once the
/// first tap has resumed the context.
class _WebEngine implements NoteEngine {
  web.AudioContext? _ctx;
  final List<web.AudioBuffer> _buffers = [];
  final Map<String, _Loop> _loops = {};

  @override
  Future<void> load(List<Float32List> notes) async {
    final ctx = _context();
    for (final n in notes) {
      final b = ctx.createBuffer(1, n.length, sampleRate);
      b.copyToChannel(n.toJS, 0);
      _buffers.add(b);
    }
  }

  /// One context for every sound (browsers limit how many a page may
  /// open), with a compressor on the way out so many notes never clip.
  web.AudioNode? _out;
  web.AudioContext _context() {
    final ready = _ctx;
    if (ready != null) return ready;
    final ctx = _ctx = web.AudioContext();
    final comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -10;
    comp.knee.value = 8;
    comp.ratio.value = 8;
    comp.attack.value = 0.003;
    comp.release.value = 0.15;
    comp.connect(ctx.destination);
    _out = comp;
    return ctx;
  }

  @override
  void play(int note, double volume) {
    final ctx = _ctx;
    if (ctx == null || note < 0 || note >= _buffers.length) return;
    if (ctx.state != 'running') ctx.resume();
    final src = ctx.createBufferSource()..buffer = _buffers[note];
    final gain = ctx.createGain()..gain.value = volume;
    src.connect(gain);
    gain.connect(_out ?? ctx.destination);
    src.start();
  }

  @override
  Future<void> playLoop(String channel, Float32List samples, int rate, double volume) async {
    final ctx = _ctx;
    if (ctx == null) return;
    stopLoop(channel);
    if (ctx.state != 'running') ctx.resume();
    final b = ctx.createBuffer(1, samples.length, rate);
    b.copyToChannel(samples.toJS, 0);
    final src = ctx.createBufferSource()
      ..buffer = b
      ..loop = true;
    final gain = ctx.createGain();
    // Fade in over 1.5 s.
    gain.gain.setValueAtTime(0, ctx.currentTime);
    gain.gain.linearRampToValueAtTime(volume, ctx.currentTime + 1.5);
    src.connect(gain);
    gain.connect(_out ?? ctx.destination);
    src.start();
    _loops[channel] = _Loop(src, gain);
  }

  @override
  void stopLoop(String channel) {
    final l = _loops.remove(channel);
    final ctx = _ctx;
    if (l == null || ctx == null) return;
    try {
      // Short fade so it never clicks.
      final now = ctx.currentTime;
      l.gain.gain.cancelScheduledValues(now);
      l.gain.gain.setValueAtTime(l.gain.gain.value, now);
      l.gain.gain.linearRampToValueAtTime(0, now + 0.6);
      l.src.stop(now + 0.65);
    } catch (_) {}
  }

  @override
  void setLoopVolume(String channel, double volume, {double seconds = 2.5}) {
    final l = _loops[channel];
    final ctx = _ctx;
    if (l == null || ctx == null) return;
    final now = ctx.currentTime;
    l.gain.gain.cancelScheduledValues(now);
    l.gain.gain.setValueAtTime(l.gain.gain.value, now);
    l.gain.gain.linearRampToValueAtTime(volume, now + seconds);
  }
}
