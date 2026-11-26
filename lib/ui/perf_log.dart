import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'perf.dart';

/// Times the steps of a move while the performance graphs are on, and shows
/// the slowest of each on screen. A frame has about 16 ms; a step that takes
/// more than a few is what makes the game stop for a moment.
class PerfLog {
  static final Map<String, double> _worst = {};
  static final changed = ValueNotifier(0);
  static bool _framesHooked = false;

  static bool get on => showPerformance.value;

  /// Runs [f], timing it as [step] when the graphs are on.
  static T time<T>(String step, T Function() f) {
    if (!on) return f();
    final sw = Stopwatch()..start();
    try {
      return f();
    } finally {
      record(step, sw.elapsedMicroseconds / 1000);
    }
  }

  static void record(String step, double ms) {
    if (!on) return;
    _hookFrames();
    if (ms <= (_worst[step] ?? -1)) return;
    _worst[step] = ms;
    _refreshSoon();
  }

  static bool _refreshing = false;

  /// Steps are timed in the middle of building and drawing a frame, when the
  /// panel can't be rebuilt; so it updates just after.
  static void _refreshSoon() {
    if (_refreshing) return;
    _refreshing = true;
    Timer(const Duration(milliseconds: 100), () {
      _refreshing = false;
      changed.value++;
    });
  }

  static void reset() {
    _worst.clear();
    changed.value++;
  }

  static List<MapEntry<String, double>> get worst =>
      _worst.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  static void _hookFrames() {
    if (_framesHooked) return;
    _framesHooked = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (!on) return;
      for (final t in timings) {
        record('whole frame (UI)', t.buildDuration.inMicroseconds / 1000);
        record('whole frame (Raster)', t.rasterDuration.inMicroseconds / 1000);
      }
    });
  }
}

/// The slowest steps since the last reset, over the graphs. Tap to reset.
class PerfLogPanel extends StatelessWidget {
  const PerfLogPanel({super.key});

  @override
  Widget build(BuildContext context) {
    PerfLog._hookFrames();
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: GestureDetector(
          onTap: PerfLog.reset,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: const Color(0xD0000000), borderRadius: BorderRadius.circular(10)),
            child: ValueListenableBuilder(
              valueListenable: PerfLog.changed,
              builder: (context, _, _) {
                final rows = PerfLog.worst.take(10);
                return DefaultTextStyle(
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.35),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Slowest (ms) · tap to reset', style: TextStyle(fontWeight: FontWeight.w900)),
                      // A debug build is many times slower than the real app.
                      Text(
                        kReleaseMode ? 'release build' : (kProfileMode ? 'profile build' : 'DEBUG build (slow)'),
                        style: TextStyle(color: kDebugMode ? const Color(0xFFFFD27A) : Colors.white70),
                      ),
                      if (rows.isEmpty) const Text('play a few moves…'),
                      for (final r in rows)
                        Text(
                          '${r.value.toStringAsFixed(1).padLeft(6)}  ${r.key}',
                          style: TextStyle(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: r.value > 8 ? const Color(0xFFFF8A80) : Colors.white,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
