/// A tiny deterministic PRNG (xorshift32).
///
/// We don't use `dart:math`'s [Random] because its output is not guaranteed to
/// be identical across the Dart VM (Android/iOS) and JavaScript (web). Every
/// player in the world must get the exact same puzzle, so all math here is
/// explicit 32-bit and safe on both platforms.
class SeededRng {
  int _state;

  SeededRng(int seed) : _state = _mix(seed) {
    if (_state == 0) _state = 0x9E3779B9;
  }

  static const int _mask = 0xFFFFFFFF;

  /// Scrambles a seed so that close dates (20261120, 20261121) give very
  /// different streams.
  static int _mix(int x) {
    x &= _mask;
    for (var i = 0; i < 4; i++) {
      x ^= (x << 13) & _mask;
      x ^= x >> 17;
      x ^= (x << 5) & _mask;
      x = (x ^ 0x5bd1e995) & _mask;
    }
    return x & _mask;
  }

  /// Next unsigned 32-bit value.
  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >> 17;
    x ^= (x << 5) & _mask;
    _state = x & _mask;
    return _state;
  }

  /// Uniform-ish integer in [0, max).
  int nextInt(int max) => nextUint32() % max;

  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
  }
}
