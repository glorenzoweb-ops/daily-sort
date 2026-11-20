import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'palette.dart';

/// Lightweight confetti burst. Call [ConfettiController.burst] to fire.
class ConfettiController extends ChangeNotifier {
  void burst() => notifyListeners();
}

class Confetti extends StatefulWidget {
  final ConfettiController controller;
  const Confetti({super.key, required this.controller});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _Piece {
  final double x, vx, vy, spin, size;
  final Color color;
  final bool round;
  _Piece(this.x, this.vx, this.vy, this.spin, this.size, this.color, this.round);
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  List<_Piece> _pieces = const [];
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_fire);
  }

  void _fire() {
    _pieces = List.generate(110, (i) {
      final a = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 1.6;
      final v = 0.9 + _rnd.nextDouble() * 0.9;
      return _Piece(
        0.5 + (_rnd.nextDouble() - 0.5) * 0.2,
        math.cos(a) * v * 0.55,
        math.sin(a) * v,
        (_rnd.nextDouble() - 0.5) * 18,
        6 + _rnd.nextDouble() * 7,
        Palette.balls[i % Palette.balls.length],
        _rnd.nextBool(),
      );
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_fire);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => _c.isAnimating
            ? CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_pieces, _c.value))
            : const SizedBox.expand(),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final time = t * 2.6;
    final fade = t > 0.75 ? 1 - (t - 0.75) / 0.25 : 1.0;
    for (final p in pieces) {
      final x = (p.x + p.vx * time * 0.5) * size.width;
      final y = size.height * 0.55 + (p.vy * time + 0.9 * time * time) * size.height * 0.45;
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * time);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2.4, paint);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
                const Radius.circular(2)),
            paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => true;
}
