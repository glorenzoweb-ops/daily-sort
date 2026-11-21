import 'dart:math' as math;

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// How the app picks light or dark.
enum ThemeChoice { auto, light, dark }

/// Cozy paper-and-candy palette (matches the TikTok clips).
///
/// The UI colors follow [dark] and the ball colors follow [colorblind]. Both
/// are set at the top of the app (see `main.dart`), which rebuilds every
/// screen when they change.
class Palette {
  /// Dark menus and a night sky.
  static bool dark = false;

  /// Colors that stay apart for every kind of color blindness, and a shape on
  /// every ball.
  static bool colorblind = false;

  /// The deep ink of the light theme. Stays dark in both themes, for things
  /// drawn on bright candy colors (faces, the moves pill).
  static const navy = Color(0xFF1B1B2F);

  static Color get background => dark ? const Color(0xFF15172A) : const Color(0xFFFFF7EA);
  static Color get ink => dark ? const Color(0xFFF4EFE6) : navy;
  static Color get inkSoft => dark ? const Color(0xFFA9A3BC) : const Color(0xFF8A8070);

  /// Cards, buttons and sheets.
  static Color get card => dark ? const Color(0xFF242740) : Colors.white;

  /// The bottom of a sheet's gradient.
  static Color get cardLow => dark ? const Color(0xFF1C1F34) : const Color(0xFFFFFAF2);

  /// Soft panels inside a card.
  static Color get panel => dark ? const Color(0xFF1B1E33) : const Color(0xFFFFF7EA);

  /// Hairlines and quiet borders.
  static Color get line => dark ? const Color(0xFF383C58) : const Color(0xFFEDE6D9);

  /// The warm fill behind something picked (your row, the chosen tile).
  static Color get picked => dark ? const Color(0xFF3B3424) : const Color(0xFFFFF3D6);

  /// Text and icons on an [ink]-filled button.
  static Color get onInk => dark ? navy : Colors.white;

  static Color get tubeStroke => dark ? const Color(0xFF474B6A) : const Color(0xFFD8CFC0);
  static const gridLine = Color(0x09000000);
  static const gold = Color(0xFFFFC23F);
  static const danger = Color(0xFFE5484D);

  /// Ball colors, index = color id. Each has a matching emoji square for the
  /// share card, so keep the lists in sync.
  static List<Color> get balls => colorblind ? safeBalls : candyBalls;

  static const candyBalls = <Color>[
    Color(0xFFFF4D6D), // red
    Color(0xFFFFC23F), // yellow
    Color(0xFF2EC4A0), // green
    Color(0xFF4D7CFF), // blue
    Color(0xFFA066F0), // purple
    Color(0xFFFF8A3D), // orange
  ];

  /// Based on the Okabe-Ito set, which stays distinct with red-green and
  /// blue-yellow color blindness. Same roles as [candyBalls], so the share
  /// emoji still match.
  static const safeBalls = <Color>[
    Color(0xFFD55E00), // vermilion
    Color(0xFFF0E442), // yellow
    Color(0xFF009E73), // bluish green
    Color(0xFF0072B2), // blue
    Color(0xFFCC79A7), // reddish purple
    Color(0xFFE69F00), // orange
  ];

  /// The shape drawn on each ball in colorblind mode.
  static const shapes = <BallShape>[
    BallShape.triangle,
    BallShape.star,
    BallShape.square,
    BallShape.diamond,
    BallShape.plus,
    BallShape.ring,
  ];

  /// Rounded, playful display font for titles and big numbers.
  static TextStyle display({double size = 26, Color? color, double spacing = 0}) =>
      GoogleFonts.fredoka(fontSize: size, fontWeight: FontWeight.w700, color: color ?? ink, letterSpacing: spacing);

  static const emoji = <String>['🟥', '🟨', '🟩', '🟦', '🟪', '🟧'];
}

enum BallShape { triangle, star, square, diamond, plus, ring }

/// Draws [shape] centered at [c], [s] across, filled with [fill] and outlined
/// with [outline]. Used on the balls and in the settings preview.
void paintBallShape(Canvas canvas, Offset c, double s, BallShape shape, Color fill, Color outline) {
  final h = s / 2;
  final path = Path();
  switch (shape) {
    case BallShape.triangle:
      path
        ..moveTo(c.dx, c.dy - h)
        ..lineTo(c.dx + h * 1.05, c.dy + h * 0.8)
        ..lineTo(c.dx - h * 1.05, c.dy + h * 0.8)
        ..close();
    case BallShape.star:
      for (var i = 0; i < 10; i++) {
        final r = i.isEven ? h * 1.1 : h * 0.48;
        final a = -1.5708 + i * 0.6283;
        final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
    case BallShape.square:
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: s * 0.82, height: s * 0.82),
          Radius.circular(s * 0.12),
        ),
      );
    case BallShape.diamond:
      path
        ..moveTo(c.dx, c.dy - h * 1.1)
        ..lineTo(c.dx + h * 0.8, c.dy)
        ..lineTo(c.dx, c.dy + h * 1.1)
        ..lineTo(c.dx - h * 0.8, c.dy)
        ..close();
    case BallShape.plus:
      final t = s * 0.17;
      path
        ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s, height: t * 2), Radius.circular(t)))
        ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: t * 2, height: s), Radius.circular(t)));
    case BallShape.ring:
      path
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: h))
        ..addOval(Rect.fromCircle(center: c, radius: h * 0.48));
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.16
      ..strokeJoin = StrokeJoin.round,
  );
  canvas.drawPath(path, Paint()..color = fill);
}
