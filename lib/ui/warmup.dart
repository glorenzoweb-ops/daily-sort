import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'palette.dart';

/// Draws one of every kind of effect the game uses into a tiny hidden image,
/// right after startup. The graphics card compiles a small program the first
/// time it meets each kind of effect; doing it now means the first tube
/// completion or the first win doesn't hitch while it compiles.
void warmUpEffects() {
  try {
    const size = 64.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, size, size));
    const r = Rect.fromLTWH(4, 4, 56, 56);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));
    c.drawRRect(rr, Paint()..shader = const LinearGradient(colors: [Palette.gold, Palette.danger]).createShader(r));
    c.drawCircle(
      r.center,
      20,
      Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)]).createShader(r),
    );
    for (final sigma in [1.5, 4.0, 12.0]) {
      c.drawRRect(
        rr.deflate(8),
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
      );
    }
    c.saveLayer(r, Paint()..color = const Color(0x80000000));
    c.drawCircle(r.center, 12, Paint()..color = Palette.balls[3]);
    c.restore();
    c.save();
    c.clipPath(Path()..addOval(r.deflate(6)));
    c.drawPath(
      Path()
        ..moveTo(4, 50)
        ..quadraticBezierTo(32, 0, 60, 50),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = Palette.balls[0],
    );
    c.restore();
    c.drawPath(
      Path()
        ..moveTo(8, 8)
        ..lineTo(30, 20)
        ..lineTo(12, 40)
        ..close(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.2
        ..color = const Color(0x55241A10),
    );
    c.drawCircle(const Offset(20, 20), 6, Paint()..blendMode = BlendMode.dstOut);
    final pic = rec.endRecording();
    final img = pic.toImageSync(size.toInt(), size.toInt());
    pic.dispose();

    // Images stamped with a fade and a tint, as the board's sprites are.
    final rec2 = ui.PictureRecorder();
    final c2 = Canvas(rec2, const Rect.fromLTWH(0, 0, size, size));
    final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    c2.drawImageRect(img, src, r, Paint()..filterQuality = FilterQuality.low);
    c2.drawImageRect(
      img,
      src,
      r,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color(0x80FFFFFF),
    );
    c2.drawImageRect(img, src, r, Paint()..colorFilter = const ColorFilter.mode(Color(0x99FF4D6D), BlendMode.srcIn));
    final pic2 = rec2.endRecording();
    pic2.toImageSync(size.toInt(), size.toInt()).dispose();
    pic2.dispose();
    img.dispose();
  } catch (_) {
    // Purely an optimization.
  }
}
