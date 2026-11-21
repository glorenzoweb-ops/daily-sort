import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// One slow clock for everything that moves in the background: drifting
/// clouds and stars, ball buddies breathing and blinking. They all redraw on
/// the same frames, 20 times a second, instead of each picking its own beat.
///
/// It runs on a timer, not a ticker: a ticker asks for a frame on every
/// screen refresh (60+ a second), and on the web every frame redraws the
/// whole screen even when nothing changed.
class AmbientClock extends ChangeNotifier {
  AmbientClock._();
  static final AmbientClock instance = AmbientClock._();

  static const fps = 20;

  final Stopwatch _sw = Stopwatch();
  Timer? _timer;

  /// Seconds since the clock started.
  double get seconds => _sw.elapsedMicroseconds / 1e6;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_timer == null) {
      _sw.start();
      _timer = Timer.periodic(const Duration(microseconds: 1000000 ~/ fps), (_) => notifyListeners());
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
      _sw.stop();
    }
  }
}
