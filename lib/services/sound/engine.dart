import 'dart:typed_data';

/// Plays pre-synthesized notes. Implemented per platform.
abstract class NoteEngine {
  Future<void> load(List<Float32List> notes);
  void play(int note, double volume);
}
