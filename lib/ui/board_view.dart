import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../game/board.dart';
import '../game/game_controller.dart';
import '../services/feedback.dart';
import 'palette.dart';

/// Geometry for laying tubes out in one row, sized to the available width.
class BoardLayout {
  final Size size;
  final int tubes;
  final int capacity;
  late final double tubeW, gap, ball, tubeH, tubeTop, x0, liftY;

  BoardLayout(this.size, this.tubes, this.capacity) {
    final maxTube = 74.0;
    tubeW = math.min(
      math.min(maxTube, (size.width - 12) / (tubes + (tubes - 1) * 0.26)),
      size.height / (capacity * 0.8 + 1.5), // fits short phones too
    );
    gap = tubeW * 0.26;
    ball = tubeW * 0.8;
    tubeH = capacity * ball + ball * 0.42;
    final rowW = tubes * tubeW + (tubes - 1) * gap;
    x0 = (size.width - rowW) / 2;
    // Center the tubes (plus the lift space above them) vertically.
    tubeTop = math.max(ball * 1.2, (size.height - tubeH + ball * 0.9) / 2);
    liftY = tubeTop - ball * 0.85;
  }

  double cx(int i) => x0 + i * (tubeW + gap) + tubeW / 2;
  Rect tubeRect(int i) => Rect.fromLTWH(x0 + i * (tubeW + gap), tubeTop, tubeW, tubeH);
  double slotY(int k) => tubeTop + tubeH - ball * 0.21 - ball / 2 - k * ball;

  int? hit(Offset p) {
    for (var i = 0; i < tubes; i++) {
      final r = tubeRect(i).inflate(gap / 2);
      if (p.dx >= r.left && p.dx <= r.right && p.dy >= liftY - ball) return i;
    }
    return null;
  }
}

/// The interactive board: draws tubes and balls and runs all the juice
/// (lift, arc-and-drop pour, squash, shake, glow, win bounce).
class BoardView extends StatefulWidget {
  final GameController game;
  final VoidCallback? onWinAnimationDone;
  const BoardView({super.key, required this.game, this.onWinAnimationDone});

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  late final AnimationController _lift =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 170));
  late final AnimationController _pour = AnimationController(vsync: this);
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _win =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  int? _liftTube; // tube whose top ball is lifted (or dropping back)
  Poured? _pending;
  int? _shakeTube;
  int? _glowTube;
  BoardLayout? _layout;

  @override
  void initState() {
    super.initState();
    _pour.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finishPour();
    });
    _win.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onWinAnimationDone?.call();
    });
    widget.game.addListener(_onGame);
  }

  @override
  void didUpdateWidget(covariant BoardView old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.removeListener(_onGame);
      widget.game.addListener(_onGame);
    }
  }

  void _onGame() {
    // Undo / restart change the board without a tap: drop any animation.
    if (_pending != null && widget.game.history.isEmpty) {
      _pour.stop();
      _pending = null;
    }
    if (widget.game.selected == null && _lift.value > 0 && _pending == null) {
      _lift.reverse();
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    for (final c in [_lift, _pour, _shake, _glow, _win]) {
      c.dispose();
    }
    super.dispose();
  }

  void _finishPour() {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    Haptics.land();
    if (p.completedTube) {
      Haptics.tubeComplete();
      _glowTube = p.move.to;
      _glow.forward(from: 0);
    }
    if (p.won) {
      Haptics.win();
      _win.forward(from: 0);
    }
    setState(() {});
  }

  void _onTap(Offset pos) {
    final layout = _layout;
    if (layout == null) return;
    final tube = layout.hit(pos);
    if (tube == null) {
      if (widget.game.selected != null) {
        widget.game.tap(widget.game.selected!); // tap outside = put it back
      }
      return;
    }
    if (_pending != null) {
      _pour.stop();
      _finishPour();
    }
    final out = widget.game.tap(tube);
    switch (out) {
      case Selected(:final tube):
        Haptics.select();
        _liftTube = tube;
        _lift.forward(from: 0);
      case Deselected():
        Haptics.select();
        _lift.reverse();
      case Poured():
        _pending = out;
        final ms = 330 + 70 * (out.count - 1);
        _pour.duration = Duration(milliseconds: ms);
        _pour.forward(from: 0);
        _lift.value = 0;
      case Invalid(:final tube):
        Haptics.invalid();
        _shakeTube = tube;
        _shake.forward(from: 0);
        _lift.reverse();
      case Ignored():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return LayoutBuilder(builder: (context, c) {
      final layout = BoardLayout(c.biggest, game.board.tubeCount, game.board.capacity);
      _layout = layout;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _onTap(d.localPosition),
        child: AnimatedBuilder(
          animation: Listenable.merge([_lift, _pour, _shake, _glow, _win]),
          builder: (context, _) => CustomPaint(
            size: c.biggest,
            painter: _BoardPainter(
              layout: layout,
              board: _pending?.before ?? game.board,
              pending: _pending,
              pourT: _pour.value,
              liftTube: _liftTube,
              liftT: Curves.easeOutBack.transform(_lift.value.clamp(0.0, 1.0)),
              shakeTube: _shakeTube,
              shakeT: _shake.value,
              glowTube: _glowTube,
              glowT: _glow.value,
              winT: _win.isAnimating || _win.isCompleted ? _win.value : (game.status == GameStatus.won ? 1.0 : 0.0),
              won: game.status == GameStatus.won && _pending == null,
            ),
          ),
        ),
      );
    });
  }
}

class _BoardPainter extends CustomPainter {
  final BoardLayout layout;
  final BoardState board;
  final Poured? pending;
  final double pourT;
  final int? liftTube;
  final double liftT;
  final int? shakeTube;
  final double shakeT;
  final int? glowTube;
  final double glowT;
  final double winT;
  final bool won;

  _BoardPainter({
    required this.layout,
    required this.board,
    required this.pending,
    required this.pourT,
    required this.liftTube,
    required this.liftT,
    required this.shakeTube,
    required this.shakeT,
    required this.glowTube,
    required this.glowT,
    required this.winT,
    required this.won,
  });

  static double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final L = layout;
    final p = pending;
    for (var i = 0; i < board.tubeCount; i++) {
      var dx = 0.0, dy = 0.0;
      if (i == shakeTube && shakeT > 0 && shakeT < 1) {
        dx = math.sin(shakeT * math.pi * 6) * 7 * (1 - shakeT);
      }
      if (won && winT > 0) {
        final t = _seg(winT, i * 0.07, i * 0.07 + 0.35);
        dy = -math.sin(t * math.pi) * L.ball * 0.55;
      }
      canvas.save();
      canvas.translate(dx, dy);

      final complete = board.isTubeComplete(i) && p == null;
      var glow = 0.0;
      if (i == glowTube && glowT > 0 && glowT < 1) glow = math.sin(glowT * math.pi);
      if (won && complete) glow = math.max(glow, 0.55 + 0.25 * math.sin(winT * math.pi * 4 + i));
      _tube(canvas, L.tubeRect(i), glow, complete ? Palette.balls[board.tubes[i].first] : null);

      // Balls resting in the tube.
      final t = board.tubes[i];
      var n = t.length;
      if (p != null && p.move.from == i) n -= p.count;
      for (var k = 0; k < n; k++) {
        var y = L.slotY(k);
        if (p == null && i == liftTube && k == n - 1 && liftT > 0) {
          y = y + (L.liftY - y) * liftT;
        }
        _ball(canvas, Offset(L.cx(i), y), Palette.balls[t[k]], L.ball / 2);
      }
      canvas.restore();
    }
    if (p != null) _flying(canvas, p);
  }

  void _flying(Canvas canvas, Poured p) {
    final L = layout;
    final src = p.before.tubes[p.move.from];
    final dstLen = p.before.tubes[p.move.to].length;
    final color = Palette.balls[p.color];
    const stagger = 0.13;
    final span = 1 - stagger * (p.count - 1);
    for (var q = 0; q < p.count; q++) {
      final t = _seg(pourT, q * stagger, q * stagger + span);
      // q = 0 is the top ball; it was already lifted when selected.
      final startY = q == 0 ? L.liftY : L.slotY(src.length - 1 - q);
      final endY = L.slotY(dstLen + q);
      final x0 = L.cx(p.move.from), x1 = L.cx(p.move.to);
      double x, y;
      var scaleX = 1.0, scaleY = 1.0;
      if (t < 0.22) {
        final u = Curves.easeOut.transform(_seg(t, 0, 0.22));
        x = x0;
        y = startY + (L.liftY - startY) * u;
      } else if (t < 0.62) {
        final u = Curves.easeInOut.transform(_seg(t, 0.22, 0.62));
        x = x0 + (x1 - x0) * u;
        y = L.liftY - math.sin(u * math.pi) * L.ball * 0.55;
      } else if (t < 0.9) {
        final u = Curves.easeIn.transform(_seg(t, 0.62, 0.9));
        x = x1;
        y = L.liftY + (endY - L.liftY) * u;
        scaleY = 1 + 0.08 * u;
        scaleX = 1 - 0.05 * u;
      } else {
        // Little squash on landing.
        final u = math.sin(_seg(t, 0.9, 1) * math.pi);
        x = x1;
        y = endY;
        scaleX = 1 + 0.12 * u;
        scaleY = 1 - 0.12 * u;
      }
      canvas.save();
      canvas.translate(x, y + (1 - scaleY) * L.ball / 2);
      canvas.scale(scaleX, scaleY);
      _ball(canvas, Offset.zero, color, L.ball / 2);
      canvas.restore();
    }
  }

  void _tube(Canvas canvas, Rect r, double glow, Color? doneColor) {
    final radius = Radius.circular(r.width / 2);
    final rr = RRect.fromRectAndCorners(r,
        topLeft: Radius.circular(r.width * 0.12),
        topRight: Radius.circular(r.width * 0.12),
        bottomLeft: radius,
        bottomRight: radius);
    if (glow > 0) {
      canvas.drawRRect(
          rr.inflate(2),
          Paint()
            ..color = (doneColor ?? Palette.gold).withValues(alpha: 0.55 * glow)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 * glow + 2));
    }
    canvas.drawRRect(rr.shift(const Offset(0, 4)), Paint()..color = const Color(0x0F000000));
    canvas.drawRRect(rr, Paint()..color = Palette.tubeFill);
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.5, r.width * 0.055)
          ..color = Palette.tubeStroke);
    // Glass highlight.
    final hl = Rect.fromLTWH(r.left + r.width * 0.16, r.top + r.width * 0.25, r.width * 0.1, r.height * 0.55);
    canvas.drawRRect(RRect.fromRectAndRadius(hl, Radius.circular(hl.width)),
        Paint()..color = const Color(0x66FFFFFF));
    if (doneColor != null) {
      // Little colored cap on completed tubes.
      final cap = Rect.fromLTWH(r.left - 3, r.top - 9, r.width + 6, 11);
      canvas.drawRRect(RRect.fromRectAndRadius(cap, const Radius.circular(5)), Paint()..color = doneColor);
    }
  }

  void _ball(Canvas canvas, Offset c, Color color, double r) {
    canvas.drawCircle(c.translate(0, r * 0.1), r, Paint()..color = const Color(0x1F000000));
    final shader = RadialGradient(
      center: const Alignment(-0.35, -0.4),
      radius: 0.95,
      colors: [Color.lerp(color, Colors.white, 0.75)!, color, Color.lerp(color, Colors.black, 0.12)!],
      stops: const [0.0, 0.32, 1.0],
    ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
