import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'ambient_clock.dart';
import 'palette.dart';

/// A soft sky behind the game that follows the player's local time: peach
/// mornings, clear days, golden sunsets and a starry lavender night. Kept
/// pastel so the dark text on top always stays readable. In dark mode it is
/// a deep blue night instead, under light text.
class SkyBackground extends StatefulWidget {
  /// Override the clock (tests, previews). Hours, 0..24.
  final double? hour;
  const SkyBackground({super.key, this.hour});

  @override
  State<SkyBackground> createState() => _SkyBackgroundState();
}

class _SkyBackgroundState extends State<SkyBackground> {
  final ValueNotifier<double> _t = ValueNotifier(0);

  // Clouds and stars move slowly: they follow the shared 20 fps clock, so
  // they redraw on the same frames as the board's idle life.
  void _onClock() => _t.value = AmbientClock.instance.seconds;

  @override
  void initState() {
    super.initState();
    AmbientClock.instance.addListener(_onClock);
  }

  late final SkyPainter _painter = SkyPainter(_t, hourOverride: widget.hour);

  @override
  void dispose() {
    AmbientClock.instance.removeListener(_onClock);
    _t.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _painter..dpr = MediaQuery.devicePixelRatioOf(context), size: Size.infinite),
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

/// Dark mode: a deep blue night at every hour.
const _deepNight = _Mood(Color(0xFF0E1024), Color(0xFF181B36), Color(0xFF23264A), Color(0xFF1A1D38), Color(0xFF6E6AA8));
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
  if (Palette.dark) return _deepNight;
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

  double dpr = 1;
  ui.Image? _base;
  Size? _baseSize;
  int _baseBucket = -1;
  double _baseDpr = 0;
  ui.Image? _cloudImg, _starImg;

  void dispose() {
    _base?.dispose();
    _cloudImg?.dispose();
    _starImg?.dispose();
  }

  static ui.Image _render(Size size, double dpr, void Function(Canvas) draw) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(dpr);
    draw(c);
    final pic = rec.endRecording();
    final img = pic.toImageSync(math.max(1, (size.width * dpr).ceil()), math.max(1, (size.height * dpr).ceil()));
    pic.dispose();
    return img;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    // Dark mode keeps the sky at night, whatever the time.
    final h = Palette.dark ? 0.0 : hourOverride ?? now.hour + now.minute / 60;
    // The gradient, sun or moon, hills and light change only with the clock:
    // draw them into one image every 10 minutes. (Making the image means a
    // read back from the graphics card, so not too often.)
    final bucket = Palette.dark ? -1 : (h * 6).floor();
    if (_base == null || _baseSize != size || _baseBucket != bucket || _baseDpr != dpr) {
      _base?.dispose();
      _base = _render(size, dpr, (c) => _paintStatic(c, size, h));
      _baseSize = size;
      _baseBucket = bucket;
      _baseDpr = dpr;
    }
    final full = Offset.zero & size;
    final img = _base!;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      full,
      Paint()..filterQuality = FilterQuality.low,
    );
    _paintMoving(canvas, size, h);
  }

  void _paintMoving(Canvas canvas, Size size, double h) {
    final (_, nightA, cloudA) = _layers(h);
    final t = time.value;
    final w = size.width, H = size.height;
    if (nightA > 0) {
      final star = _starImg ??= _render(const Size(24, 24), dpr, (c) {
        c.drawCircle(const Offset(12, 12), 10, Paint()..color = const Color(0x2EFFE9A8));
        _star(c, const Offset(12, 12), 4.5, const Color(0xFFFFE08A));
      });
      final src = Rect.fromLTWH(0, 0, star.width.toDouble(), star.height.toDouble());
      final rnd = math.Random(7);
      final paint = Paint()..filterQuality = FilterQuality.low;
      for (var i = 0; i < 46; i++) {
        final p = Offset(rnd.nextDouble() * w, rnd.nextDouble() * H * 0.42);
        final tw = 0.5 + 0.5 * math.sin(t * (0.6 + rnd.nextDouble()) + i);
        final s = 0.8 + rnd.nextDouble() * 1.6;
        final a = nightA * (0.35 + 0.65 * tw);
        final half = 12 * s * (1.2 + 0.4 * tw) / 4.5 * 1.05;
        paint.color = Colors.white.withValues(alpha: a.clamp(0.0, 1.0));
        canvas.drawImageRect(star, src, Rect.fromCenter(center: p, width: half * 2, height: half * 2), paint);
      }
    }
    if (cloudA > 0) {
      final cloud = _cloudImg ??= _render(const Size(200, 120), dpr, (c) {
        _cloud(c, const Offset(100, 50), 40, Colors.white);
      });
      final src = Rect.fromLTWH(0, 0, cloud.width.toDouble(), cloud.height.toDouble());
      final paint = Paint()
        ..filterQuality = FilterQuality.low
        ..color = Colors.white.withValues(alpha: 0.75 * cloudA);
      for (var i = 0; i < 4; i++) {
        final speed = 6.0 + i * 3;
        final span = w + 260;
        final x = (i * 211 + t * speed) % span - 130;
        final y = H * (0.07 + 0.09 * i);
        final k = (34.0 + i * 6) / 40;
        canvas.drawImageRect(cloud, src, Rect.fromLTWH(x - 100 * k, y - 50 * k, 200 * k, 120 * k), paint);
      }
    }
  }

  void _paintStatic(Canvas canvas, Size size, double h) {
    final m = _moodAt(h);
    final (sunA, nightA, _) = _layers(h);
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
