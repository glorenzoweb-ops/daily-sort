import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../game/board.dart';
import '../game/game_controller.dart';
import '../services/feedback.dart';
import '../services/sound.dart';
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

  /// Unwind mode: a soft glow that breathes at ~6 breaths a minute.
  final bool breathe;
  const BoardView({super.key, required this.game, this.onWinAnimationDone, this.breathe = false});

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  late final AnimationController _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 170));
  late final AnimationController _pour = AnimationController(vsync: this);
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _win = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  // A clock that always runs, for idle life (breathing, blinking), jelly
  // wobble and particles.
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final Map<int, double> _landAt = {}; // tube → time of last landing
  final List<_Spark> _sparks = [];
  double _shakeAt = -10; // screen shake start
  final _rnd = math.Random();

  int? _liftTube; // tube whose top ball is lifted (or dropping back)
  Poured? _pending;
  int? _shakeTube;
  int? _glowTube;
  BoardLayout? _layout;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      _sparks.removeWhere((s) => t - s.born > 1.3);
      _time.value = t;
    })..start();
    _pour.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finishPour();
    });
    _win.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onWinAnimationDone?.call();
    });
    widget.game.addListener(_onGame);
    _reportCalm();
  }

  @override
  void didUpdateWidget(covariant BoardView old) {
    super.didUpdateWidget(old);
    if (old.game != widget.game) {
      old.game.removeListener(_onGame);
      widget.game.addListener(_onGame);
      _reportCalm();
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
    _reportCalm();
    setState(() {});
  }

  /// The soundscape softens as tubes complete (and returns with a new board).
  void _reportCalm() {
    final b = widget.game.board;
    final colors = widget.game.puzzle.colors;
    var done = 0;
    for (var i = 0; i < b.tubeCount; i++) {
      if (b.isTubeComplete(i)) done++;
    }
    Sounds.setCalm(done / colors);
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGame);
    for (final c in [_lift, _pour, _shake, _glow, _win]) {
      c.dispose();
    }
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _finishPour() {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    Haptics.land();
    Sounds.clink();
    _landAt[p.move.to] = _time.value;
    if (p.completedTube) {
      Haptics.tubeComplete();
      Sounds.tubeComplete(p.color);
      _glowTube = p.move.to;
      _glow.forward(from: 0);
      _burst(p.move.to, p.color);
    }
    if (p.before.lockRemaining == 1) {
      // The locked tube just opened.
      Haptics.tubeComplete();
      Sounds.note(7, volume: 0.5);
    }
    if (p.won) {
      Haptics.win();
      Sounds.solved();
      _win.forward(from: 0);
    }
    setState(() {});
  }

  /// Confetti puff out of a tube that just completed, plus a tiny shake.
  void _burst(int tube, int color) {
    final L = _layout;
    if (L == null) return;
    final origin = Offset(L.cx(tube), L.tubeTop);
    for (var i = 0; i < 28; i++) {
      final a = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 2.2;
      final v = L.ball * (3.5 + _rnd.nextDouble() * 4.5);
      _sparks.add(
        _Spark(
          origin,
          Offset(math.cos(a), math.sin(a)) * v,
          _time.value,
          i % 4 == 0 ? Palette.gold : Palette.balls[color],
          L.ball * (0.08 + _rnd.nextDouble() * 0.1),
          _rnd.nextBool(),
          _rnd.nextDouble() * 6,
        ),
      );
    }
    _shakeAt = _time.value;
  }

  void _onTap(Offset pos) {
    Sounds.wake();
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
        // Play the note right away: browsers only allow audio in a tap.
        Sounds.pour(out.color, out.before.tubes[out.move.to].length);
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
    return LayoutBuilder(
      builder: (context, c) {
        final layout = BoardLayout(c.biggest, game.board.tubeCount, game.board.capacity);
        _layout = layout;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _onTap(d.localPosition),
          child: AnimatedBuilder(
            animation: Listenable.merge([_lift, _pour, _shake, _glow, _win, _time]),
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
                time: _time.value,
                landAt: _landAt,
                sparks: _sparks,
                shakeAt: _shakeAt,
                lookTube: _pending?.move.to ?? game.selected,
                breathe: widget.breathe,
              ),
            ),
          ),
        );
      },
    );
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
  final double time;
  final Map<int, double> landAt;
  final List<_Spark> sparks;
  final double shakeAt;
  final int? lookTube;
  final bool breathe;

  _BoardPainter({
    this.breathe = false,
    required this.time,
    required this.landAt,
    required this.sparks,
    required this.shakeAt,
    required this.lookTube,
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
    // Tiny screen shake right after a tube completes.
    final sd = time - shakeAt;
    canvas.save();
    if (sd >= 0 && sd < 0.3) {
      final k = (1 - sd / 0.3) * L.ball * 0.06;
      canvas.translate(math.sin(sd * 70) * k, math.cos(sd * 53) * k);
    }
    final lookX = lookTube == null ? null : L.cx(lookTube!);
    if (breathe) _breathing(canvas, size);
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

      // Jelly: the tube and its balls wobble for a moment after a landing.
      final wob = _wobble(i);
      final r0 = L.tubeRect(i);
      canvas.translate(r0.center.dx, r0.bottom);
      canvas.scale(1 + 0.03 * wob, 1 - 0.015 * wob);
      canvas.translate(-r0.center.dx, -r0.bottom);

      final complete = board.isTubeComplete(i) && p == null;
      var glow = 0.0;
      if (i == glowTube && glowT > 0 && glowT < 1) glow = math.sin(glowT * math.pi);
      if (won && complete) glow = math.max(glow, 0.55 + 0.25 * math.sin(winT * math.pi * 4 + i));
      _tube(canvas, L.tubeRect(i), glow, complete ? Palette.balls[board.tubes[i].first] : null);
      if (board.isPicky(i)) _pickyMark(canvas, L.tubeRect(i), Palette.balls[board.rules.pickyColor]);

      // Balls resting in the tube.
      final t = board.tubes[i];
      var n = t.length;
      if (p != null && p.move.from == i) n -= p.count;
      for (var k = 0; k < n; k++) {
        var y = L.slotY(k);
        final lifted = p == null && i == liftTube && k == n - 1 && liftT > 0;
        if (lifted) {
          y = y + (L.liftY - y) * liftT;
        }
        final Mood mood;
        if (won || complete) {
          mood = Mood.cheer;
        } else if (lifted && liftT > 0.5) {
          mood = Mood.surprised;
        } else if ((k > 0 && t[k - 1] == t[k]) || (k + 1 < n && t[k + 1] == t[k])) {
          mood = Mood.happy;
        } else {
          mood = Mood.worried;
        }
        // Balls nearer the top wobble more.
        final jelly = wob * (0.4 + 0.6 * (k + 1) / math.max(1, n));
        _buddy(canvas, Offset(L.cx(i), y), t[k], L.ball / 2, mood, i * 7 + k * 13, lookX, jelly);
      }
      if (board.isLocked(i)) _lockMark(canvas, L.tubeRect(i), board.lockRemaining);
      canvas.restore();
    }
    if (p != null) _flying(canvas, p);
    canvas.restore();
    _drawSparks(canvas);
  }

  /// 10-second breath: 4 s in, 6 s out (about 6 breaths a minute, the pace
  /// used in slow-breathing relaxation exercises).
  static double breathAt(double t) {
    final ph = t % 10;
    return ph < 4 ? Curves.easeInOut.transform(ph / 4) : 1 - Curves.easeInOut.transform((ph - 4) / 6);
  }

  void _breathing(Canvas canvas, Size size) {
    final L = layout;
    final b = breathAt(time);
    final row = Rect.fromLTRB(L.x0, L.tubeTop, L.x0 + L.tubes * L.tubeW + (L.tubes - 1) * L.gap, L.tubeTop + L.tubeH);
    final glowRect = row.inflate(L.ball * (0.6 + 0.9 * b));
    canvas.drawRRect(
      RRect.fromRectAndRadius(glowRect, Radius.circular(L.ball * 1.5)),
      Paint()
        ..color = const Color(0xFFFFD27A).withValues(alpha: 0.10 + 0.22 * b)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, L.ball * (0.8 + 0.8 * b)),
    );
    // A quiet cue under the tubes.
    final inhaling = time % 10 < 4;
    final label = inhaling ? 'breathe in' : 'breathe out';
    final edge = inhaling ? (time % 10) / 4 : ((time % 10) - 4) / 6;
    final alpha = (math.sin(edge * math.pi)).clamp(0.0, 1.0) * 0.55;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Palette.inkSoft.withValues(alpha: alpha),
          fontSize: math.max(13, L.ball * 0.32),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final y = math.min(size.height - tp.height - 2, row.bottom + L.ball * 0.55);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
  }

  double _wobble(int tube) {
    final t0 = landAt[tube];
    if (t0 == null) return 0;
    final d = time - t0;
    if (d < 0 || d > 0.8) return 0;
    return math.exp(-d * 6) * math.cos(d * 30);
  }

  void _drawSparks(Canvas canvas) {
    final g = layout.ball * 14;
    for (final s in sparks) {
      final d = time - s.born;
      if (d < 0 || d > 1.3) continue;
      final pos = s.origin + s.v * d + Offset(0, 0.5 * g * d * d);
      final paint = Paint()..color = s.color.withValues(alpha: (1 - d / 1.3).clamp(0.0, 1.0));
      if (s.round) {
        canvas.drawCircle(pos, s.size, paint);
      } else {
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(s.spin * d * 3);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: s.size * 2.2, height: s.size * 1.1), paint);
        canvas.restore();
      }
    }
  }

  void _flying(Canvas canvas, Poured p) {
    final L = layout;
    final src = p.before.tubes[p.move.from];
    final dstLen = p.before.tubes[p.move.to].length;
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
      _buddy(canvas, Offset.zero, p.color, L.ball / 2, Mood.excited, 99 + q, x1, 0);
      canvas.restore();
    }
  }

  void _tube(Canvas canvas, Rect r, double glow, Color? doneColor) {
    final radius = Radius.circular(r.width / 2);
    final rr = RRect.fromRectAndCorners(
      r,
      topLeft: Radius.circular(r.width * 0.12),
      topRight: Radius.circular(r.width * 0.12),
      bottomLeft: radius,
      bottomRight: radius,
    );
    if (glow > 0) {
      canvas.drawRRect(
        rr.inflate(2),
        Paint()
          ..color = (doneColor ?? Palette.gold).withValues(alpha: 0.55 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 * glow + 2),
      );
    }
    canvas.drawRRect(rr.shift(const Offset(0, 4)), Paint()..color = const Color(0x0F000000));
    canvas.drawRRect(rr, Paint()..color = Palette.tubeFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.5, r.width * 0.055)
        ..color = Palette.tubeStroke,
    );
    // Glass highlight.
    final hl = Rect.fromLTWH(r.left + r.width * 0.16, r.top + r.width * 0.25, r.width * 0.1, r.height * 0.55);
    canvas.drawRRect(RRect.fromRectAndRadius(hl, Radius.circular(hl.width)), Paint()..color = const Color(0x66FFFFFF));
    if (doneColor != null) {
      // Little colored cap on completed tubes.
      final cap = Rect.fromLTWH(r.left - 3, r.top - 9, r.width + 6, 11);
      canvas.drawRRect(RRect.fromRectAndRadius(cap, const Radius.circular(5)), Paint()..color = doneColor);
    }
  }

  /// Picky tube: tinted glass, a colored base and a target dot above.
  void _pickyMark(Canvas canvas, Rect r, Color color) {
    final rr = RRect.fromRectAndCorners(
      r,
      topLeft: Radius.circular(r.width * 0.12),
      topRight: Radius.circular(r.width * 0.12),
      bottomLeft: Radius.circular(r.width / 2),
      bottomRight: Radius.circular(r.width / 2),
    );
    canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.5, r.width * 0.06)
        ..color = color.withValues(alpha: 0.75),
    );
    final c = Offset(r.center.dx, r.top - r.width * 0.42);
    canvas.drawCircle(c, r.width * 0.2, Paint()..color = color);
    canvas.drawCircle(
      c,
      r.width * 0.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
  }

  /// Locked tube: frosted cover with a padlock and the moves until it opens.
  void _lockMark(Canvas canvas, Rect r, int remaining) {
    final rr = RRect.fromRectAndCorners(
      r,
      topLeft: Radius.circular(r.width * 0.12),
      topRight: Radius.circular(r.width * 0.12),
      bottomLeft: Radius.circular(r.width / 2),
      bottomRight: Radius.circular(r.width / 2),
    );
    canvas.drawRRect(rr, Paint()..color = const Color(0xB3EDE6D9));
    final c = Offset(r.center.dx, r.center.dy - r.width * 0.1);
    final s = r.width * 0.5;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: s, height: s * 0.78),
      Radius.circular(s * 0.18),
    );
    canvas.drawArc(
      Rect.fromCenter(center: c.translate(0, -s * 0.38), width: s * 0.62, height: s * 0.7),
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.14
        ..color = Palette.ink,
    );
    canvas.drawRRect(body, Paint()..color = Palette.ink);
    final tp = TextPainter(
      text: TextSpan(
        text: '$remaining',
        style: TextStyle(color: Colors.white, fontSize: s * 0.5, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  /// A ball with a face. It breathes, blinks, looks toward the tube you
  /// picked, and its expression follows its mood.
  void _buddy(Canvas canvas, Offset c, int colorIndex, double r, Mood mood, int seed, double? lookX, double jelly) {
    final phase = seed * 1.7;
    // Breathing (idle life) plus jelly wobble, anchored at the ball's bottom.
    final breath = 0.025 * math.sin(time * 2.4 + phase);
    final sx = 1 - breath * 0.6 + 0.12 * jelly;
    final sy = 1 + breath - 0.12 * jelly;
    canvas.save();
    canvas.translate(c.dx, c.dy + r);
    canvas.scale(sx, sy);
    canvas.translate(0, -r);
    if (mood == Mood.cheer) {
      // Little happy hop, each ball on its own beat.
      canvas.translate(0, -r * 0.08 * math.max(0, math.sin(time * 6 + phase)));
    }
    _ball(canvas, Offset.zero, Palette.balls[colorIndex], r);
    _face(canvas, r, mood, phase, lookX == null ? 0 : ((lookX - c.dx) / (r * 4)).clamp(-1.0, 1.0));
    canvas.restore();
  }

  void _face(Canvas canvas, double r, Mood mood, double phase, double look) {
    const ink = Color(0xE61B1B2F);
    final eyeY = -r * 0.08;
    final eyeDx = r * 0.3;
    final lx = look * r * 0.07;
    final blinking = (time + phase) % 4.3 < 0.13;

    // Blush.
    final blush = Paint()..color = const Color(0x40FF5A7A);
    canvas.drawCircle(Offset(-r * 0.52, r * 0.2), r * 0.13, blush);
    canvas.drawCircle(Offset(r * 0.52, r * 0.2), r * 0.13, blush);

    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.09;

    // Eyes.
    if (mood == Mood.cheer) {
      for (final sx in [-1.0, 1.0]) {
        final e = Offset(sx * eyeDx, eyeY);
        canvas.drawArc(
          Rect.fromCenter(center: e, width: r * 0.32, height: r * 0.3),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          stroke,
        );
      }
    } else {
      final big = mood == Mood.surprised || mood == Mood.excited;
      final h = blinking ? r * 0.04 : r * (big ? 0.3 : 0.24);
      final w = r * (big ? 0.22 : 0.19);
      for (final sx in [-1.0, 1.0]) {
        final e = Offset(sx * eyeDx + lx, eyeY);
        canvas.drawOval(Rect.fromCenter(center: e, width: w, height: h), Paint()..color = ink);
        if (!blinking) {
          canvas.drawCircle(e.translate(w * 0.18, -h * 0.22), w * 0.2, Paint()..color = Colors.white);
        }
      }
      if (mood == Mood.worried) {
        // Slanted brows.
        for (final sx in [-1.0, 1.0]) {
          canvas.drawLine(
            Offset(sx * (eyeDx + r * 0.1), eyeY - r * 0.2),
            Offset(sx * (eyeDx - r * 0.08), eyeY - r * 0.27),
            stroke..strokeWidth = r * 0.06,
          );
        }
        stroke.strokeWidth = r * 0.09;
      }
    }

    // Mouth.
    final m = Offset(lx * 0.5, r * 0.3);
    switch (mood) {
      case Mood.cheer:
        final path = Path()
          ..moveTo(m.dx - r * 0.2, m.dy - r * 0.05)
          ..quadraticBezierTo(m.dx, m.dy + r * 0.38, m.dx + r * 0.2, m.dy - r * 0.05)
          ..close();
        canvas.drawPath(path, Paint()..color = ink);
        canvas.drawCircle(Offset(m.dx, m.dy + r * 0.1), r * 0.07, Paint()..color = const Color(0xFFFF7A90));
      case Mood.happy:
        canvas.drawArc(
          Rect.fromCenter(center: m.translate(0, -r * 0.06), width: r * 0.4, height: r * 0.28),
          0.15 * math.pi,
          0.7 * math.pi,
          false,
          stroke,
        );
      case Mood.worried:
        canvas.drawArc(
          Rect.fromCenter(center: m.translate(0, r * 0.06), width: r * 0.32, height: r * 0.2),
          1.15 * math.pi,
          0.7 * math.pi,
          false,
          stroke,
        );
      case Mood.surprised:
      case Mood.excited:
        canvas.drawOval(Rect.fromCenter(center: m, width: r * 0.17, height: r * 0.21), Paint()..color = ink);
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

/// How a ball buddy feels.
enum Mood { worried, happy, cheer, surprised, excited }

class _Spark {
  final Offset origin;
  final Offset v;
  final double born;
  final Color color;
  final double size;
  final bool round;
  final double spin;
  const _Spark(this.origin, this.v, this.born, this.color, this.size, this.round, this.spin);
}
