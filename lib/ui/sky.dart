import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// A soft sky behind the game that follows the player's local time: peach
/// mornings, clear days, golden sunsets and a starry lavender night. Kept
/// pastel so the dark text on top always stays readable.
class SkyBackground extends StatefulWidget {
  /// Override the clock (tests, previews). Hours, 0..24.
  final double? hour;
  const SkyBackground({super.key, this.hour});

  @override
  State<SkyBackground> createState() => _SkyBackgroundState();
}

class _SkyBackgroundState extends State<SkyBackground> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: SkyPainter(_t, hourOverride: widget.hour),
        size: Size.infinite,
      ),
    );
  }
}

/// One look of the sky at a given hour.
class _Mood {
  final Color top, mid, bottom, hills, glow;
  const _Mood(this.top, this.mid, this.bottom, this.hills, this.glow);

  static _Mood lerp(_Mood a, _Mood b, double t) => _Mood(
    Color.lerp(a.top, b.top, t)!,
    Color.lerp(a.mid, b.mid, t)!,
    Color.lerp(a.bottom, b.bottom, t)!,
    Color.lerp(a.hills, b.hills, t)!,
    Color.lerp(a.glow, b.glow, t)!,
  );
}

const _night = _Mood(Color(0xFFD5D0F2), Color(0xFFE6E0F6), Color(0xFFF3EEF9), Color(0xFFDCD5EE), Color(0xFFFFF1C9));
const _morning = _Mood(Color(0xFFFFD9C4), Color(0xFFFFE9D6), Color(0xFFFFF6E8), Color(0xFFF3E1C9), Color(0xFFFFE2A8));
const _day = _Mood(Color(0xFFCBE7F7), Color(0xFFE6F3F6), Color(0xFFFFF7EA), Color(0xFFE5EED6), Color(0xFFFFF4C2));
const _sunset = _Mood(Color(0xFFFFC2A8), Color(0xFFFFD6CF), Color(0xFFFFEBD6), Color(0xFFF5D3C2), Color(0xFFFFB86B));

/// (hour, mood) keyframes around the clock.
const _keys = <(double, _Mood)>[
  (0, _night),
  (5, _night),
  (7.5, _morning),
  (11, _day),
  (16.5, _day),
  (19, _sunset),
  (21, _night),
  (24, _night),
];

/// How much of each scene element shows at [h]: (sun, moonAndStars, clouds).
(double, double, double) _layers(double h) {
  double bump(double a, double b, double c, double d) {
    if (h <= a || h >= d) return 0;
    if (h < b) return (h - a) / (b - a);
    if (h <= c) return 1;
    return (d - h) / (d - c);
  }

  final sun = bump(5.5, 7.5, 18.5, 20.5);
  final night = 1 - bump(5, 7, 19.5, 21.5);
  final clouds = bump(6, 9, 18, 20.5);
  return (sun, night, clouds);
}

_Mood _moodAt(double h) {
  for (var i = 0; i < _keys.length - 1; i++) {
    final (h0, m0) = _keys[i];
    final (h1, m1) = _keys[i + 1];
    if (h >= h0 && h <= h1) {
      final t = h1 == h0 ? 0.0 : (h - h0) / (h1 - h0);
      return _Mood.lerp(m0, m1, Curves.easeInOut.transform(t));
    }
  }
  return _night;
}

class SkyPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final double? hourOverride;
  SkyPainter(this.time, {this.hourOverride}) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final h = hourOverride ?? now.hour + now.minute / 60;
    final m = _moodAt(h);
    final (sunA, nightA, cloudA) = _layers(h);
    final t = time.value;
    final w = size.width, H = size.height;
    final full = Offset.zero & size;

    // Sky gradient.
    canvas.drawRect(
      full,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [m.top, m.mid, m.bottom],
          stops: const [0, 0.45, 1],
        ).createShader(full),
    );

    // Sun: rises on the left, sets on the right, low near the edges of the day.
    if (sunA > 0) {
      final u = ((h - 6) / 13).clamp(0.0, 1.0);
      final c = Offset(w * (0.12 + 0.76 * u), H * (0.2 - 0.12 * math.sin(u * math.pi)));
      final r = math.min(w, H) * 0.09;
      canvas.drawCircle(
        c,
        r * 4,
        Paint()
          ..shader = RadialGradient(
            colors: [
              m.glow.withValues(alpha: 0.55 * sunA),
              m.glow.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r * 4)),
      );
      canvas.drawCircle(c, r, Paint()..color = Color.lerp(m.glow, Colors.white, 0.45)!.withValues(alpha: 0.9 * sunA));
    }

    // Moon and stars.
    if (nightA > 0) {
      final r = math.min(w, H) * 0.06;
      final c = Offset(w * 0.8, H * 0.11);
      canvas.drawCircle(
        c,
        r * 3.5,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFF6D8).withValues(alpha: 0.7 * nightA),
              const Color(0x00FFF6D8),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r * 3.5)),
      );
      // Crescent: a pale disc with a sky-colored bite.
      canvas.saveLayer(Rect.fromCircle(center: c, radius: r * 1.2), Paint());
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFF3C4).withValues(alpha: nightA));
      canvas.drawCircle(c.translate(r * 0.45, -r * 0.25), r * 0.85, Paint()..blendMode = BlendMode.dstOut);
      canvas.restore();

      final rnd = math.Random(7);
      for (var i = 0; i < 46; i++) {
        final p = Offset(rnd.nextDouble() * w, rnd.nextDouble() * H * 0.42);
        final tw = 0.5 + 0.5 * math.sin(t * (0.6 + rnd.nextDouble()) + i);
        final s = 0.8 + rnd.nextDouble() * 1.6;
        final a = nightA * (0.35 + 0.65 * tw);
        canvas.drawCircle(p, s * 2.6, Paint()..color = const Color(0xFFFFE9A8).withValues(alpha: 0.18 * a));
        _star(canvas, p, s * (1.2 + 0.4 * tw), const Color(0xFFFFE08A).withValues(alpha: a));
      }
    }

    // Slow drifting clouds.
    if (cloudA > 0) {
      for (var i = 0; i < 4; i++) {
        final speed = 6.0 + i * 3;
        final span = w + 260;
        final x = (i * 211 + t * speed) % span - 130;
        final y = H * (0.07 + 0.09 * i);
        _cloud(canvas, Offset(x, y), 34.0 + i * 6, Colors.white.withValues(alpha: 0.75 * cloudA));
      }
    }

    // Soft hills at the bottom for depth.
    final hills = Path()..moveTo(0, H);
    for (var x = 0.0; x <= w + 8; x += 8) {
      final y =
          H * 0.9 - math.sin(x / w * math.pi * 1.4 + 0.6) * H * 0.035 - math.sin(x / w * math.pi * 3.3) * H * 0.012;
      hills.lineTo(x, y);
    }
    hills
      ..lineTo(w, H)
      ..close();
    canvas.drawPath(hills, Paint()..color = m.hills.withValues(alpha: 0.75));

    // Warm light from the top-left, and a gentle vignette.
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.9, -1),
          radius: 1.2,
          colors: [m.glow.withValues(alpha: 0.18), m.glow.withValues(alpha: 0)],
        ).createShader(full),
    );
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: const [Color(0x00000000), Color(0x00000000), Color(0x1A3A2A1A)],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCenter(center: full.center, width: w * 1.25, height: H * 1.05)),
    );
  }

  void _star(Canvas canvas, Offset c, double s, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - s * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + s * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + s * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - s * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - s * 2)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _cloud(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18);
    canvas.drawCircle(c, r, paint);
    canvas.drawCircle(c.translate(r * 0.9, r * 0.2), r * 0.75, paint);
    canvas.drawCircle(c.translate(-r * 0.95, r * 0.25), r * 0.7, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(c.dx - r * 1.6, c.dy, c.dx + r * 1.6, c.dy + r * 0.85),
        Radius.circular(r * 0.5),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant SkyPainter old) => old.hourOverride != hourOverride;
}
