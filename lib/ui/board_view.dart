import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../game/board.dart';
import '../game/game_controller.dart';
import '../services/feedback.dart';
import '../services/sound.dart';
import 'palette.dart';
import 'solve_art.dart';

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
  late final AnimationController _win = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));

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
  List<PourInfo> _winPours = const [];
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
      Future<void>.delayed(const Duration(milliseconds: 330), Sounds.pop);
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
      _winPours = widget.game.pours;
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
                winPours: _win.isAnimating ? _winPours : const [],
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
  final List<PourInfo> winPours;

  _BoardPainter({
    this.winPours = const [],
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
    _shelf(canvas);
    for (var i = 0; i < board.tubeCount; i++) {
      var dx = 0.0, dy = 0.0;
      if (i == shakeTube && shakeT > 0 && shakeT < 1) {
        dx = math.sin(shakeT * math.pi * 6) * 7 * (1 - shakeT);
      }
      if (won && winT > 0) {
        final t = _seg(winT, i * 0.03, i * 0.03 + 0.15);
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
      final doneColor = complete ? Palette.balls[board.tubes[i].first] : null;
      final pickyColor = board.isPicky(i) ? Palette.balls[board.rules.pickyColor] : null;
      _tubeBack(canvas, L.tubeRect(i), glow, doneColor, pickyColor);

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
      _tubeFront(canvas, L.tubeRect(i), pickyColor);
      if (board.isLocked(i)) _lockMark(canvas, L.tubeRect(i), board.lockRemaining);
      if (doneColor != null) {
        // The cork drops in (with a bounce) right after the tube completes.
        var drop = 1.0;
        if (i == glowTube && glowT > 0 && glowT < 1) drop = _seg(glowT, 0.0, 0.42);
        _cork(canvas, L.tubeRect(i), doneColor, drop, i);
      }
      canvas.restore();
    }
    if (p != null) _flying(canvas, p);
    canvas.restore();
    _drawSparks(canvas);
    if (winPours.isNotEmpty) _winPainting(canvas, size);
  }

  /// A wooden shelf the tubes stand on, with a soft shadow under each tube.
  void _shelf(Canvas canvas) {
    final L = layout;
    final y = L.tubeTop + L.tubeH;
    final left = L.x0 - L.gap * 1.2, right = L.x0 + L.tubes * L.tubeW + (L.tubes - 1) * L.gap + L.gap * 1.2;
    final h = L.ball * 0.34;
    final top = Rect.fromLTRB(left, y - h * 0.25, right, y + h * 0.55);
    final front = Rect.fromLTRB(left, top.bottom - 1, right, top.bottom + h * 0.6);
    // Shadow the shelf casts.
    canvas.drawRRect(
      RRect.fromRectAndRadius(front.shift(Offset(0, h * 0.5)).inflate(h * 0.2), Radius.circular(h)),
      Paint()
        ..color = const Color(0x22301E0A)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.9),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(front, bottomLeft: Radius.circular(h * 0.5), bottomRight: Radius.circular(h * 0.5)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD9A877), Color(0xFFC18E5E)],
        ).createShader(front),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(top, Radius.circular(h * 0.4)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6D9B4), Color(0xFFE9C392)],
        ).createShader(top),
    );
    // Wood grain.
    final grain = Paint()
      ..color = const Color(0x1A7A4A1E)
      ..strokeWidth = 1;
    for (var k = 0; k < 3; k++) {
      final gy = top.top + top.height * (0.3 + k * 0.22);
      canvas.drawLine(Offset(left + 10 + k * 23, gy), Offset(right - 14 - k * 31, gy), grain);
    }
    // Contact shadows.
    for (var i = 0; i < L.tubes; i++) {
      final c = Offset(L.cx(i), y + h * 0.05);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: L.tubeW * 1.15, height: h * 0.7),
        Paint()
          ..color = const Color(0x33402810)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.25),
      );
    }
  }

  /// The win: colors stream out of the tubes and paint the solve painting in
  /// a glowing disc over the board, then it floats away to the result card.
  void _winPainting(Canvas canvas, Size size) {
    final L = layout;
    final appear = Curves.easeOutBack.transform(_seg(winT, 0.18, 0.32));
    final leave = Curves.easeIn.transform(_seg(winT, 0.88, 1.0));
    final a = (_seg(winT, 0.18, 0.26) * (1 - leave)).clamp(0.0, 1.0);
    if (a <= 0) return;
    final center = Offset(size.width / 2, L.tubeTop + L.tubeH * 0.45);
    final radius = math.min(size.width * 0.44, L.tubeH * 0.72) * appear * (1 - 0.35 * leave);
    // Soft veil that fades the board behind the disc.
    final veil = Rect.fromCircle(center: center, radius: math.max(1, radius * 2.4));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF7EA).withValues(alpha: 0.7 * a),
            const Color(0x00FFF7EA),
          ],
        ).createShader(veil),
    );
    // Streams of color from each tube into the disc.
    final streamA = _seg(winT, 0.25, 0.35) * (1 - _seg(winT, 0.72, 0.82));
    if (streamA > 0) {
      for (var i = 0; i < board.tubeCount; i++) {
        if (board.tubes[i].isEmpty) continue;
        final color = Palette.balls[board.tubes[i].first];
        final from = Offset(L.cx(i), L.tubeTop);
        final ctrl = Offset((from.dx + center.dx) / 2, L.tubeTop - L.ball * 2.5);
        for (var k = 0; k < 9; k++) {
          final s = (time * 0.9 + k / 9 + i * 0.13) % 1.0;
          final q = Offset.lerp(Offset.lerp(from, ctrl, s)!, Offset.lerp(ctrl, center, s)!, s)!;
          canvas.drawCircle(
            q,
            L.ball * (0.16 - 0.08 * s),
            Paint()..color = color.withValues(alpha: streamA * a * (1 - s * 0.6)),
          );
        }
      }
    }
    // The disc.
    canvas.drawCircle(
      center,
      radius * 1.18,
      Paint()
        ..color = Palette.gold.withValues(alpha: 0.35 * a)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.25 + 1),
    );
    canvas.drawCircle(center, radius, Paint()..color = Colors.white.withValues(alpha: a));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Palette.gold.withValues(alpha: a),
    );
    if (radius > 4) {
      canvas.save();
      canvas.translate(center.dx - radius, center.dy - radius);
      canvas.saveLayer(Rect.fromLTWH(0, 0, radius * 2, radius * 2), Paint()..color = Colors.black.withValues(alpha: a));
      SolveArtPainter(
        pours: winPours,
        tubeCount: board.tubeCount,
        progress: Curves.easeInOut.transform(_seg(winT, 0.3, 0.85)),
        showGuides: false,
      ).paint(canvas, Size(radius * 2, radius * 2));
      canvas.restore();
      canvas.restore();
    }
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
    final color = Palette.balls[p.color];
    for (var q = 0; q < p.count; q++) {
      // q = 0 is the top ball; it was already lifted when selected.
      final startY = q == 0 ? L.liftY : L.slotY(src.length - 1 - q);
      final endY = L.slotY(dstLen + q);
      double tq(double t) => _seg(t, q * stagger, q * stagger + span);
      final t = tq(pourT);
      // A soft comet trail while the ball is in the air.
      if (t > 0.05 && t < 0.86) {
        for (var g = 1; g <= 4; g++) {
          final gt = tq(pourT - g * 0.035 * span);
          final (gx, gy, _, _) = _flight(gt, startY, endY, p);
          canvas.drawCircle(
            Offset(gx, gy),
            L.ball / 2 * (1 - g * 0.13),
            Paint()..color = color.withValues(alpha: 0.22 - g * 0.045),
          );
        }
      }
      final (x, y, scaleX, scaleY) = _flight(t, startY, endY, p);
      canvas.save();
      canvas.translate(x, y + (1 - scaleY) * L.ball / 2);
      canvas.scale(scaleX, scaleY);
      _buddy(canvas, Offset.zero, p.color, L.ball / 2, Mood.excited, 99 + q, L.cx(p.move.to), 0);
      canvas.restore();
    }
  }

  /// Where a pouring ball is at time [t] (0..1): position and squash/stretch.
  (double, double, double, double) _flight(double t, double startY, double endY, Poured p) {
    final L = layout;
    final x0 = L.cx(p.move.from), x1 = L.cx(p.move.to);
    if (t < 0.22) {
      final u = Curves.easeOut.transform(_seg(t, 0, 0.22));
      return (x0, startY + (L.liftY - startY) * u, 1 - 0.06 * u, 1 + 0.08 * u);
    } else if (t < 0.62) {
      final u = Curves.easeInOut.transform(_seg(t, 0.22, 0.62));
      // Stretch along the motion while it travels sideways.
      final speed = math.sin(u * math.pi);
      return (x0 + (x1 - x0) * u, L.liftY - speed * L.ball * 0.55, 1 + 0.14 * speed, 1 - 0.1 * speed);
    } else if (t < 0.86) {
      final u = Curves.easeIn.transform(_seg(t, 0.62, 0.86));
      return (x1, L.liftY + (endY - L.liftY) * u, 1 - 0.07 * u, 1 + 0.12 * u);
    } else if (t < 0.93) {
      // Squash on landing...
      final u = math.sin(_seg(t, 0.86, 0.93) * math.pi);
      return (x1, endY, 1 + 0.16 * u, 1 - 0.16 * u);
    }
    // ...then a tiny hop as it settles.
    final u = math.sin(_seg(t, 0.93, 1) * math.pi);
    return (x1, endY - u * L.ball * 0.1, 1, 1);
  }

  static RRect _tubeShape(Rect r) => RRect.fromRectAndCorners(
    r,
    topLeft: Radius.circular(r.width * 0.12),
    topRight: Radius.circular(r.width * 0.12),
    bottomLeft: Radius.circular(r.width / 2),
    bottomRight: Radius.circular(r.width / 2),
  );

  /// Behind the balls: glow, the inside of the glass, and a colored light
  /// in finished tubes.
  void _tubeBack(Canvas canvas, Rect r, double glow, Color? doneColor, Color? pickyColor) {
    final rr = _tubeShape(r);
    if (glow > 0) {
      canvas.drawRRect(
        rr.inflate(2),
        Paint()
          ..color = (doneColor ?? Palette.gold).withValues(alpha: 0.6 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * glow + 2),
      );
    }
    // The glass interior: cooler, darker toward the curved edges.
    final tint = pickyColor ?? const Color(0xFF9DB7CC);
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          colors: [
            tint.withValues(alpha: pickyColor != null ? 0.32 : 0.30),
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.45),
            tint.withValues(alpha: pickyColor != null ? 0.38 : 0.36),
          ],
          stops: const [0, 0.3, 0.62, 1],
        ).createShader(r),
    );
    if (doneColor != null) {
      // A finished tube fills with its color's light.
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              doneColor.withValues(alpha: 0.32 + 0.25 * glow),
              doneColor.withValues(alpha: 0.06),
            ],
          ).createShader(r),
      );
    }
    // Back wall of the glass bottom.
    final w = r.width;
    canvas.drawArc(
      Rect.fromLTWH(r.left + w * 0.12, r.bottom - w * 0.9, w * 0.76, w * 0.8),
      0.15 * math.pi,
      0.7 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.05
        ..color = const Color(0x1A31506A),
    );
  }

  /// In front of the balls: the thick glass rim, the lip and the highlights.
  void _tubeFront(Canvas canvas, Rect r, Color? pickyColor) {
    final rr = _tubeShape(r);
    final w = r.width;
    final sw = math.max(3.0, w * 0.075);
    // A faint sheen over everything inside.
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.06),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(r),
    );
    // Thick rim: bright on the lit left side, deeper on the right.
    canvas.drawRRect(
      rr.deflate(sw / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..shader = LinearGradient(
          colors: pickyColor != null
              ? [Color.lerp(pickyColor, Colors.white, 0.45)!, pickyColor, Color.lerp(pickyColor, Colors.black, 0.15)!]
              : const [Color(0xFFFFFFFF), Color(0xFFD5E0E8), Color(0xFFAFC0CD)],
          stops: const [0.05, 0.5, 1],
        ).createShader(r),
    );
    // Inner edge of the glass wall: gives it thickness.
    canvas.drawRRect(
      rr.deflate(sw + 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x2231506A),
    );
    // Long highlight on the left and a thin one on the right.
    final hl = Rect.fromLTWH(r.left + w * 0.17, r.top + w * 0.32, w * 0.1, r.height * 0.62);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hl, Radius.circular(hl.width)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.05)],
        ).createShader(hl),
    );
    final hl2 = Rect.fromLTWH(r.right - w * 0.24, r.top + w * 0.45, w * 0.045, r.height * 0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hl2, Radius.circular(hl2.width)),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
    // Caustic: light focused through the round bottom.
    canvas.drawArc(
      Rect.fromLTWH(r.left + w * 0.22, r.bottom - w * 0.62, w * 0.56, w * 0.46),
      0.2 * math.pi,
      0.6 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w * 0.04
        ..color = Colors.white.withValues(alpha: 0.6),
    );
    // The lip around the opening.
    final lip = Rect.fromCenter(center: Offset(r.center.dx, r.top + w * 0.02), width: w * 1.1, height: w * 0.24);
    canvas.drawOval(
      lip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw * 0.9
        ..shader = LinearGradient(
          colors: pickyColor != null
              ? [Color.lerp(pickyColor, Colors.white, 0.5)!, pickyColor]
              : const [Color(0xFFFFFFFF), Color(0xFFB9C9D5)],
        ).createShader(lip),
    );
    canvas.drawArc(
      lip.deflate(sw * 0.2),
      math.pi * 1.1,
      math.pi * 0.45,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw * 0.35
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
    if (pickyColor != null) {
      // Target dot above a picky tube: "only this color".
      final c = Offset(r.center.dx, r.top - w * 0.42);
      canvas.drawCircle(c, w * 0.2, Paint()..color = pickyColor);
      canvas.drawCircle(
        c,
        w * 0.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white,
      );
    }
  }

  /// A cork stopper with a colored wax seal. [drop] 0..1 animates it in.
  void _cork(Canvas canvas, Rect r, Color color, double drop, int seed) {
    if (drop <= 0) return;
    final w = r.width;
    final h = w * 0.46;
    final fall = (1 - Curves.bounceOut.transform(drop)) * w * 1.8;
    final top = r.top - h * 0.95 - fall;
    final a = _seg(drop, 0, 0.15);
    final body = Path()
      ..moveTo(r.center.dx - w * 0.44, top)
      ..lineTo(r.center.dx + w * 0.44, top)
      ..lineTo(r.center.dx + w * 0.34, top + h)
      ..quadraticBezierTo(r.center.dx, top + h * 1.12, r.center.dx - w * 0.34, top + h)
      ..close();
    final bounds = Rect.fromLTRB(r.center.dx - w * 0.44, top, r.center.dx + w * 0.44, top + h);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFE8BE86).withValues(alpha: a),
            const Color(0xFFD5A266).withValues(alpha: a),
            const Color(0xFFB98447).withValues(alpha: a),
          ],
        ).createShader(bounds),
    );
    // Cork speckles.
    final rnd = math.Random(seed);
    final dot = Paint()..color = const Color(0x55835426).withValues(alpha: 0.35 * a);
    for (var k = 0; k < 7; k++) {
      canvas.drawCircle(
        Offset(bounds.left + w * (0.18 + rnd.nextDouble() * 0.52), top + h * (0.35 + rnd.nextDouble() * 0.5)),
        w * 0.025,
        dot,
      );
    }
    // Top face.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(r.center.dx, top), width: w * 0.88, height: w * 0.22),
      Paint()..color = const Color(0xFFF0CF9E).withValues(alpha: a),
    );
    // Wax seal in the tube's color.
    final seal = Offset(r.center.dx, top + h * 0.55);
    canvas.drawCircle(seal, w * 0.16, Paint()..color = Color.lerp(color, Colors.black, 0.15)!.withValues(alpha: a));
    canvas.drawCircle(seal.translate(-w * 0.03, -w * 0.03), w * 0.11, Paint()..color = color.withValues(alpha: a));
    canvas.drawCircle(
      seal.translate(-w * 0.06, -w * 0.06),
      w * 0.035,
      Paint()..color = Colors.white.withValues(alpha: 0.7 * a),
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

  /// A glossy candy ball: soft contact shadow, deep body shading, bounced
  /// light from below, a crisp specular highlight and a fine outline.
  void _ball(Canvas canvas, Offset c, Color color, double r) {
    // Contact shadow on whatever is underneath.
    final sh = Rect.fromCenter(center: c.translate(0, r * 0.88), width: r * 1.7, height: r * 0.55);
    canvas.drawOval(
      sh,
      Paint()..shader = const RadialGradient(colors: [Color(0x40301A08), Color(0x00301A08)]).createShader(sh),
    );
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.32, -0.38),
          radius: 1.05,
          colors: [
            Color.lerp(color, Colors.white, 0.6)!,
            Color.lerp(color, Colors.white, 0.08)!,
            color,
            Color.lerp(color, Colors.black, 0.28)!,
          ],
          stops: const [0.0, 0.3, 0.62, 1.0],
        ).createShader(rect),
    );
    // Bounced light along the bottom edge.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.15, 1.05),
          radius: 0.62,
          colors: [Color.lerp(color, Colors.white, 0.45)!.withValues(alpha: 0.75), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
    // Soft broad shine, then the sharp highlight.
    canvas.drawCircle(
      c.translate(-r * 0.3, -r * 0.35),
      r * 0.55,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.38), Colors.white.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c.translate(-r * 0.3, -r * 0.35), radius: r * 0.55)),
    );
    canvas.save();
    canvas.translate(c.dx - r * 0.42, c.dy - r * 0.5);
    canvas.rotate(-0.6);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: r * 0.42, height: r * 0.22),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.restore();
    canvas.drawCircle(c.translate(r * 0.45, r * 0.42), r * 0.06, Paint()..color = Colors.white.withValues(alpha: 0.5));
    canvas.drawCircle(
      c,
      r - r * 0.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.04
        ..color = Color.lerp(color, Colors.black, 0.35)!.withValues(alpha: 0.35),
    );
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
