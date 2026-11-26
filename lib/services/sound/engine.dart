import 'dart:typed_data';

/// Plays pre-synthesized sounds. Implemented per platform.
abstract class NoteEngine {
  /// One-shot sounds (notes, clinks, chimes, the solve chord) at [sampleRate].
  Future<void> load(List<Float32List> notes);
  void play(int note, double volume);

  /// Starts a looping background sound on [channel] (replacing whatever that
  /// channel played). Channels mix: a soundscape and music can play together.
  Future<void> playLoop(String channel, Float32List samples, int rate, double volume);
  void stopLoop(String channel);

  /// Glides a looping channel to [volume] over [seconds].
  void setLoopVolume(String channel, double volume, {double seconds = 2.5});
}
