import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../game/game_controller.dart';
import '../services/sound.dart';
import 'palette.dart';

/// "Your solve is a painting": every pour becomes a ribbon flowing from one
/// tube's column to another, top to bottom in move order. No two different
/// solves look the same.
class SolveArtPainter extends CustomPainter {
  final List<PourInfo> pours;
  final int tubeCount;

  /// 0..1, how much of the painting is drawn (for the reveal animation).
  final double progress;
  final bool showGuides;

  SolveArtPainter({required this.pours, required this.tubeCount, this.progress = 1, this.showGuides = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (pours.isEmpty) return;
    // Tubes sit on a circle; every pour is a ribbon that swoops through the
    // middle, so a solve weaves a little mandala.
    final c = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.38;
    Offset node(int i) {
      final a = -math.pi / 2 + 2 * math.pi * i / tubeCount;
      return c + Offset(math.cos(a), math.sin(a)) * radius;
    }

    final base = radius * 0.055;

    if (showGuides) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x12000000),
      );
    }

    final shown = progress * pours.length;
    for (var k = 0; k < pours.length; k++) {
      final part = (shown - k).clamp(0.0, 1.0);
      if (part <= 0) break;
      final p = pours[k];
      final a = node(p.move.from), b = node(p.move.to);
      // The bend point drifts around the center as the solve goes on
      // (golden angle), so ribbons fan out instead of stacking.
      final ga = k * 2.39996;
      final bend = c + Offset(math.cos(ga), math.sin(ga)) * radius * (0.12 + 0.3 * (k / pours.length));
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(bend.dx * 2 - (a.dx + b.dx) / 2, bend.dy * 2 - (a.dy + b.dy) / 2, b.dx, b.dy);
      final drawn = part >= 1 ? path : _partial(path, part);
      final color = Palette.balls[p.color % Palette.balls.length];
      final width = base * (0.7 + 0.35 * p.count);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * 2.2
          ..color = color.withValues(alpha: 0.13),
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color.withValues(alpha: 0.9),
      );
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * 0.22
          ..color = Colors.white.withValues(alpha: 0.5),
      );
      if (part >= 1 && p.completedTube) _sparkle(canvas, b, base * 3.2, color);
      // The brush: a glowing tip leads the stroke that is being painted.
      if (part < 1) {
        for (final m in path.computeMetrics()) {
          final tip = m.getTangentForOffset(m.length * part)?.position;
          if (tip == null) continue;
          canvas.drawCircle(
            tip,
            width * 2.4,
            Paint()
              ..shader = RadialGradient(
                colors: [Colors.white.withValues(alpha: 0.9), color.withValues(alpha: 0.5), color.withValues(alpha: 0)],
                stops: const [0, 0.35, 1],
              ).createShader(Rect.fromCircle(center: tip, radius: width * 2.4)),
          );
        }
      }
    }

    // Tube nodes, colored by what ended up in them so far.
    final last = <int, int>{};
    for (var k = 0; k < math.min(pours.length, shown.ceil()); k++) {
      last[pours[k].move.to] = pours[k].color;
    }
    for (var i = 0; i < tubeCount; i++) {
      final o = node(i);
      final col = last[i] == null ? const Color(0xFFE6DDCC) : Palette.balls[last[i]! % Palette.balls.length];
      canvas.drawCircle(o, base * 2.1, Paint()..color = Colors.white);
      canvas.drawCircle(o, base * 1.5, Paint()..color = col);
    }
  }

  static Path _partial(Path p, double t) {
    final out = Path();
    for (final m in p.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * t), Offset.zero);
    }
    return out;
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()
      ..color = Palette.gold
      ..strokeWidth = r * 0.16
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final len = i.isEven ? r : r * 0.6;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * r * 0.55,
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.55 + len * 0.5),
        paint,
      );
    }
    canvas.drawCircle(c, r * 0.3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant SolveArtPainter old) => old.progress != progress || old.pours != pours;
}

/// The painting drawing itself while the solve song plays, note by note.
class SolveArtPlayer extends StatefulWidget {
  final List<PourInfo> pours;
  final int tubeCount;
  final bool autoplay;
  final Duration startDelay;
  const SolveArtPlayer({
    super.key,
    required this.pours,
    required this.tubeCount,
    this.autoplay = true,
    this.startDelay = const Duration(milliseconds: 350),
  });

  @override
  State<SolveArtPlayer> createState() => SolveArtPlayerState();
}

class SolveArtPlayerState extends State<SolveArtPlayer> with SingleTickerProviderStateMixin {
  static const perNote = 260; // ms
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: perNote * (widget.pours.isEmpty ? 1 : widget.pours.length) + 300),
  );
  int _played = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) Sounds.win();
    });
    if (widget.autoplay) {
      // Starts once the stars have landed, so their notes don't overlap.
      Future<void>.delayed(widget.startDelay, () {
        if (mounted) play();
      });
    } else {
      _c.value = 1;
      _played = widget.pours.length;
    }
  }

  void play() {
    _played = 0;
    _c.forward(from: 0);
  }

  double get _artT => (_c.value * _c.duration!.inMilliseconds / (perNote * widget.pours.length)).clamp(0.0, 1.0);

  void _onTick() {
    // Play each pour's note the moment its ribbon starts drawing.
    final shown = _artT * widget.pours.length;
    while (_played < widget.pours.length && shown >= _played) {
      final p = widget.pours[_played];
      Sounds.pour(p.color, p.destSlot);
      _played++;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(
              painter: SolveArtPainter(pours: widget.pours, tubeCount: widget.tubeCount, progress: _artT),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => AnimatedOpacity(
              opacity: _c.isAnimating ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Material(
                color: Palette.navy,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _c.isAnimating ? null : play,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 4),
                        Text(
                          'Play my song',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders the shareable 1080x1350 image (Instagram/TikTok-photo friendly).
Future<Uint8List> renderSolveCard({
  required List<PourInfo> pours,
  required int tubeCount,
  required String title,
  required String subtitle,
  required int stars,
  required String footer,
  String? fontFamily,
}) async {
  const w = 1080.0, h = 1350.0;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFFFF7EA));
  final lines = Paint()..color = Palette.gridLine;
  for (double y = 0; y < h; y += 48) {
    canvas.drawRect(Rect.fromLTWH(0, y, w, 2), lines);
  }

  void text(String s, double y, double size, Color color, FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight, fontFamily: fontFamily),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w - 120);
    tp.paint(canvas, Offset((w - tp.width) / 2, y));
  }

  text(title, 70, 84, Palette.navy, FontWeight.w900);
  text(subtitle, 178, 40, const Color(0xFF8A8070), FontWeight.w700);
  // Stars
  for (var i = 0; i < 3; i++) {
    _star(canvas, Offset(w / 2 + (i - 1) * 86, 290), 36, i < stars ? Palette.gold : const Color(0xFFE6DDCC));
  }

  // The solve painting, big.
  final card = RRect.fromRectAndRadius(const Rect.fromLTWH(90, 400, w - 180, 720), const Radius.circular(44));
  canvas.drawRRect(card.shift(const Offset(0, 10)), Paint()..color = const Color(0x14000000));
  canvas.drawRRect(card, Paint()..color = Colors.white);
  canvas.save();
  canvas.clipRRect(card);
  canvas.translate(card.left, card.top);
  SolveArtPainter(pours: pours, tubeCount: tubeCount).paint(canvas, Size(card.width, card.height));
  canvas.restore();
  text('Every solve paints a different picture', card.bottom + 28, 34, const Color(0xFF8A8070), FontWeight.w700);

  text(footer, 1250, 34, const Color(0xFF8A8070), FontWeight.w800);

  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void _star(Canvas canvas, Offset c, double r, Color color) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isEven ? r : r * 0.48;
    final p = c + Offset(math.cos(a), math.sin(a)) * rr;
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  path.close();
  canvas.drawPath(path, Paint()..color = color);
}
