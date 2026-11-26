import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../game/game_controller.dart';
import 'palette.dart';
import 'solve_art.dart';

/// What every share card shows.
class ShareCardData {
  final int number; // 0 for Unwind
  final String dayLabel;
  final int moves, par, stars, streak;
  final List<PourInfo> pours;
  final int tubeCount;

  /// The solved board, one list of colors per tube (bottom first).
  final List<List<int>> solved;

  /// Font families (null: 'Fredoka' and 'Nunito').
  final String? displayFont, bodyFont;
  const ShareCardData({
    required this.number,
    required this.dayLabel,
    required this.moves,
    required this.par,
    required this.stars,
    required this.streak,
    required this.pours,
    required this.tubeCount,
    required this.solved,
    this.displayFont,
    this.bodyFont,
  });

  String get title => number == 0 ? 'Daily Sort · Unwind' : 'Daily Sort #$number';
}

/// The 1080x1920 story image a solve is shared as (Instagram/TikTok/WhatsApp
/// stories): "Sorted in N!", the stars, the painting in a glowing window, the
/// sorted ball buddies on their shelf, and a challenge.
Future<Uint8List> renderShareCard(ShareCardData d) async {
  const size = Size(1080, 1920);
  final rec = ui.PictureRecorder();
  _story(Canvas(rec, Offset.zero & size), size, d);
  final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

// ---------------------------------------------------------------- helpers

/// Font families; the app passes the bundled Google Fonts names.
String _display = 'Fredoka', _body = 'Nunito';

double _text(
  Canvas c,
  String s,
  Offset at,
  double size,
  Color color, {
  String? family,
  FontWeight weight = FontWeight.w800,
  double maxWidth = 960,
  TextAlign align = TextAlign.center,
  double spacing = 0,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
        fontSize: size,
        color: color,
        fontWeight: weight,
        fontFamily: family ?? _body,
        letterSpacing: spacing,
        height: 1.1,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout(maxWidth: maxWidth);
  final dx = switch (align) {
    TextAlign.center => at.dx - tp.width / 2,
    TextAlign.right => at.dx - tp.width,
    _ => at.dx,
  };
  tp.paint(c, Offset(dx, at.dy));
  return tp.height;
}

void _star(Canvas c, Offset at, double r, Color color) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isEven ? r : r * 0.5;
    final p = at + Offset(math.cos(a), math.sin(a)) * rr;
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
  c.drawPath(
    path,
    Paint()
      ..color = color
      ..strokeJoin = StrokeJoin.round,
  );
  c.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.18
      ..strokeJoin = StrokeJoin.round,
  );
}

void _stars(Canvas c, Offset center, double r, int stars, {Color off = const Color(0xFFE6DDCC)}) {
  for (var i = 0; i < 3; i++) {
    _star(c, center + Offset((i - 1) * r * 2.5, 0), r, i < stars ? Palette.gold : off);
  }
}

/// A glossy ball buddy with a happy face.
void _ball(Canvas c, Offset at, double r, Color color, {bool face = true}) {
  c.drawCircle(at + Offset(0, r * 0.12), r, Paint()..color = const Color(0x22000000));
  c.drawCircle(
    at,
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        radius: 1.1,
        colors: [Color.lerp(color, Colors.white, 0.35)!, color, Color.lerp(color, Colors.black, 0.18)!],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: at, radius: r)),
  );
  c.drawOval(
    Rect.fromCenter(center: at + Offset(-r * 0.32, -r * 0.42), width: r * 0.62, height: r * 0.34),
    Paint()..color = Colors.white.withValues(alpha: 0.55),
  );
  if (!face) return;
  final eye = Paint()..color = const Color(0xFF241A10);
  c.drawCircle(at + Offset(-r * 0.3, r * 0.02), r * 0.11, eye);
  c.drawCircle(at + Offset(r * 0.3, r * 0.02), r * 0.11, eye);
  final smile = Path()
    ..moveTo(at.dx - r * 0.2, at.dy + r * 0.24)
    ..quadraticBezierTo(at.dx, at.dy + r * 0.44, at.dx + r * 0.2, at.dy + r * 0.24);
  c.drawPath(
    smile,
    Paint()
      ..color = const Color(0xFF241A10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.08
      ..strokeCap = StrokeCap.round,
  );
}

void _painting(Canvas c, Rect r, ShareCardData d) {
  c.save();
  c.translate(r.left, r.top);
  SolveArtPainter(pours: d.pours, tubeCount: d.tubeCount, showGuides: false).paint(c, r.size);
  c.restore();
}

// ------------------------------------------------- The story card

void _story(Canvas c, Size s, ShareCardData d) {
  final w = s.width, h = s.height;
  _display = d.displayFont ?? 'Fredoka';
  _body = d.bodyFont ?? 'Nunito';
  // Evening sky.
  c.drawRect(
    Offset.zero & s,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2A2D5C), Color(0xFF6C5CA8), Color(0xFFF2A07B), Color(0xFFFFD9A8)],
        stops: [0, 0.38, 0.72, 1],
      ).createShader(Offset.zero & s),
  );
  final r = math.Random(d.number + 3);
  for (var i = 0; i < 46; i++) {
    final p = Offset(r.nextDouble() * w, r.nextDouble() * h * 0.42);
    c.drawCircle(
      p,
      1.5 + r.nextDouble() * 2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.35 + r.nextDouble() * 0.5),
    );
  }

  _text(c, d.title, Offset(w / 2, 150), 46, Colors.white.withValues(alpha: 0.85), weight: FontWeight.w900);
  _text(c, 'Sorted in ${d.moves}!', Offset(w / 2, 220), 120, Colors.white, family: _display, weight: FontWeight.w700);
  _stars(c, Offset(w / 2, 420), 40, d.stars, off: Colors.white.withValues(alpha: 0.25));
  final sub = d.streak > 1 ? 'par ${d.par} · ${d.streak}-day streak' : 'par ${d.par} · ${d.dayLabel}';
  _text(c, sub, Offset(w / 2, 490), 40, Colors.white.withValues(alpha: 0.9));

  // The painting in a glowing round window.
  const center = Offset(540, 860);
  c.drawCircle(
    center,
    300,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
  );
  c.drawCircle(center, 270, Paint()..color = const Color(0xFFFFFAF2));
  c.save();
  c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: 262)));
  _painting(c, Rect.fromCircle(center: center, radius: 290), d);
  c.restore();

  // The sorted tubes on a shelf, the buddies all happy.
  final tubes = d.solved;
  final n = tubes.length;
  final cap = tubes.fold<int>(0, (m, t) => math.max(m, t.length)).clamp(3, 6);
  const ballR = 34.0;
  final gap = math.min(150.0, (w - 160) / n);
  final shelfY = 1560.0;
  final x0 = w / 2 - gap * (n - 1) / 2;
  for (var i = 0; i < n; i++) {
    final x = x0 + gap * i;
    final tube = RRect.fromRectAndCorners(
      Rect.fromLTWH(x - 48, shelfY - cap * ballR * 2.1 - 40, 96, cap * ballR * 2.1 + 40),
      bottomLeft: const Radius.circular(48),
      bottomRight: const Radius.circular(48),
      topLeft: const Radius.circular(10),
      topRight: const Radius.circular(10),
    );
    c.drawRRect(tube, Paint()..color = Colors.white.withValues(alpha: 0.22));
    for (var k = 0; k < tubes[i].length; k++) {
      _ball(c, Offset(x, shelfY - 44 - k * ballR * 2.1), ballR, Palette.balls[tubes[i][k] % Palette.balls.length]);
    }
    c.drawRRect(
      tube,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(80, shelfY, w - 160, 30), const Radius.circular(14)),
    Paint()..color = const Color(0xFF9A6A3E),
  );

  _text(
    c,
    'Can you beat me?',
    Offset(w / 2, 1690),
    56,
    const Color(0xFF4A2E1A),
    family: _display,
    weight: FontWeight.w700,
  );
  _text(c, 'Daily Sort: one puzzle a day, the same for everyone', Offset(w / 2, 1778), 34, const Color(0xFF6B4A33));
}
