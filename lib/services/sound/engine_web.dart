import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'engine.dart';
import 'synth.dart';

NoteEngine createEngine() => _WebEngine();

/// Web Audio: sample-accurate, polyphonic, and works on iOS Safari once the
/// first tap has resumed the context.
class _WebEngine implements NoteEngine {
  web.AudioContext? _ctx;
  final List<web.AudioBuffer> _buffers = [];

  @override
  Future<void> load(List<Float32List> notes) async {
    final ctx = _ctx = web.AudioContext();
    for (final n in notes) {
      final b = ctx.createBuffer(1, n.length, sampleRate);
      b.copyToChannel(n.toJS, 0);
      _buffers.add(b);
    }
  }

  @override
  void play(int note, double volume) {
    final ctx = _ctx;
    if (ctx == null || note < 0 || note >= _buffers.length) return;
    if (ctx.state != 'running') ctx.resume();
    final src = ctx.createBufferSource()..buffer = _buffers[note];
    final gain = ctx.createGain()..gain.value = volume;
    src.connect(gain);
    gain.connect(ctx.destination);
    src.start();
  }
}
