import 'dart:typed_data';

/// Plays pre-synthesized notes. Implemented per platform.
abstract class NoteEngine {
  Future<void> load(List<Float32List> notes);
  void play(int note, double volume);

  /// Starts a looping background sound (stopping any previous one).
  Future<void> playLoop(Float32List samples, int rate, double volume);
  void stopLoop();
}
