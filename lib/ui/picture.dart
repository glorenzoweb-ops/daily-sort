import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../game/board.dart';
import 'palette.dart';

/// The picture of the day: a little coloring-book scene. Each ball color
/// paints one part of it, and that part fills in when you complete a tube of
/// that color. The title stays a mystery until the puzzle is solved.
///
/// Scenes are drawn from code on a 200 x 100 canvas, so they cost nothing to
/// ship and stay sharp at any size. Layer k is painted in [Palette.balls][k].
class Scene {
  final String title;

  /// One path per ball color (0 red, 1 yellow, 2 green, 3 blue, 4 purple).
  final List<Path> layers;

  /// White lines drawn on top of a layer once it's colored (stripes, ropes…).
  final List<Path?> details;

  /// Drawing order of the layers, back to front.
  final List<int> order;

  /// Uncolored shapes drawn last (clouds in front of a rainbow…).
  final Path? front;

  Scene(this.title, this.layers, this.order, {List<Path?>? details, this.front})
    : details = details ?? List.filled(5, null);
}

const double sceneW = 200, sceneH = 100;

/// Same scene for everyone on a given day. Consecutive days never repeat.
Scene sceneForNumber(int number) {
  final all = scenes;
  return all[(number * 5 + 3) % all.length];
}

/// Unwind puzzles get a scene from their starting board.
Scene sceneForBoard(BoardState b) => scenes[b.canonicalKey.hashCode.abs() % scenes.length];

/// Ball colors that sit in a completed tube right now.
Set<int> completedColors(BoardState b) => {
  for (var i = 0; i < b.tubeCount; i++)
    if (b.isTubeComplete(i) && b.tubes[i].isNotEmpty) b.tubes[i].first,
};

// ---------------------------------------------------------------------------
// Shape helpers (scene units)

Path _circle(double x, double y, double r) => Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
Path _oval(double x, double y, double w, double h) =>
    Path()..addOval(Rect.fromCenter(center: Offset(x, y), width: w, height: h));
Path _rect(double l, double t, double r, double b, [double radius = 0]) =>
    Path()..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));

Path _poly(List<double> xy) {
  final p = Path()..moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    p.lineTo(xy[i], xy[i + 1]);
  }
  return p..close();
}

Path _merge(List<Path> ps) {
  final out = Path();
  for (final p in ps) {
    out.addPath(p, Offset.zero);
  }
  return out;
}

/// Water from [top] down, with a gently waving surface.
Path _water(double top, {double amp = 1.2, int waves = 6}) {
  final p = Path()..moveTo(0, top);
  final step = sceneW / waves;
  for (var i = 0; i < waves; i++) {
    final x = i * step;
    p.quadraticBezierTo(x + step / 4, top - amp, x + step / 2, top);
    p.quadraticBezierTo(x + step * 3 / 4, top + amp, x + step, top);
  }
  return p
    ..lineTo(sceneW, sceneH)
    ..lineTo(0, sceneH)
    ..close();
}

/// A round hill from x0 to x1 peaking at (px, py), sitting on y = base.
Path _hump(double x0, double x1, double px, double py, double base) => Path()
  ..moveTo(x0, base)
  ..cubicTo(x0 + (px - x0) * 0.3, py, px - (px - x0) * 0.3, py, px, py)
  ..cubicTo(px + (x1 - px) * 0.3, py, x1 - (x1 - px) * 0.3, py, x1, base)
  ..close();

Path _balloon(double x, double y, double r) => _merge([
  _circle(x, y, r),
  _poly([x - r * 0.86, y + r * 0.5, x, y + r * 1.75, x + r * 0.86, y + r * 0.5]),
  _rect(x - r * 0.28, y + r * 2.05, x + r * 0.28, y + r * 2.45, r * 0.06),
]);

Path _balloonRopes(double x, double y, double r) => Path()
  ..moveTo(x - r * 0.25, y + r * 1.7)
  ..lineTo(x - r * 0.25, y + r * 2.05)
  ..moveTo(x + r * 0.25, y + r * 1.7)
  ..lineTo(x + r * 0.25, y + r * 2.05)
  ..moveTo(x, y - r)
  ..quadraticBezierTo(x - r * 0.55, y + r * 0.3, x, y + r * 1.7)
  ..moveTo(x, y - r)
  ..quadraticBezierTo(x + r * 0.55, y + r * 0.3, x, y + r * 1.7);

Path _pine(double x, double base, double h) => _merge([
  _poly([x - h * 0.28, base - h * 0.25, x, base - h, x + h * 0.28, base - h * 0.25]),
  _poly([x - h * 0.34, base, x, base - h * 0.6, x + h * 0.34, base]),
]);

Path _tulip(double x, double y, double s) => Path()
  ..moveTo(x - s, y - s * 0.9)
  ..lineTo(x - s * 0.5, y - s * 0.35)
  ..lineTo(x, y - s)
  ..lineTo(x + s * 0.5, y - s * 0.35)
  ..lineTo(x + s, y - s * 0.9)
  ..quadraticBezierTo(x + s * 1.05, y + s * 0.6, x, y + s * 0.65)
  ..quadraticBezierTo(x - s * 1.05, y + s * 0.6, x - s, y - s * 0.9)
  ..close();

Path _forgetMeNot(double x, double y, double s) =>
    _merge([for (var i = 0; i < 5; i++) _circle(x + math.cos(i * 1.2566) * s, y + math.sin(i * 1.2566) * s, s * 0.7)]);

Path _lavender(double x, double base, double h) =>
    _merge([for (var i = 0; i < 6; i++) _oval(x + (i.isEven ? -0.9 : 0.9), base - h + i * h * 0.13, 2.2, 3.4)]);

// ---------------------------------------------------------------------------
// The scenes. Add new ones at the end: the rotation picks by index.

final List<Scene> scenes = _buildScenes();

List<Scene> _buildScenes() => [
  // Lighthouse at dusk
  Scene(
    'Lighthouse at dusk',
    [
      _merge([
        _poly([151, 62, 154, 27, 164, 27, 167, 62]),
        _poly([150, 27, 159, 17, 168, 27]),
      ]),
      _merge([
        _circle(58, 54, 13),
        _poly([157, 23, 96, 9, 96, 33]),
      ]),
      _merge([
        _poly([118, 100, 124, 74, 138, 63, 172, 58, 200, 61, 200, 100]),
        _hump(0, 46, 20, 84, 100),
      ]),
      _water(64),
      _merge([
        _poly([0, 64, 22, 46, 40, 57, 66, 40, 96, 60, 116, 52, 136, 64]),
        _oval(36, 18, 32, 8),
        _oval(92, 26, 24, 6),
      ]),
    ],
    [4, 1, 3, 2, 0],
    details: [
      Path()
        ..moveTo(152.5, 36)
        ..lineTo(165.5, 36)
        ..moveTo(151.8, 48)
        ..lineTo(166.2, 48)
        ..addRect(const Rect.fromLTWH(157, 52, 4, 10)),
      null,
      null,
      Path()
        ..moveTo(20, 76)
        ..lineTo(34, 76)
        ..moveTo(70, 84)
        ..lineTo(92, 84)
        ..moveTo(40, 92)
        ..lineTo(58, 92),
      null,
    ],
  ),
  // Hot air balloons
  Scene(
    'Hot air balloons',
    [
      _balloon(70, 32, 16),
      _balloon(128, 20, 10),
      Path()
        ..moveTo(0, 86)
        ..quadraticBezierTo(50, 68, 100, 84)
        ..quadraticBezierTo(150, 98, 200, 80)
        ..lineTo(200, 100)
        ..lineTo(0, 100)
        ..close(),
      _balloon(164, 46, 8),
      _poly([0, 82, 28, 54, 52, 72, 84, 44, 118, 74, 150, 52, 200, 78, 200, 100, 0, 100]),
    ],
    [4, 2, 1, 3, 0],
    details: [_balloonRopes(70, 32, 16), _balloonRopes(128, 20, 10), null, _balloonRopes(164, 46, 8), null],
  ),
  // Sailboat in the bay
  Scene(
    'Sailboat in the bay',
    [
      _merge([
        _poly([72, 22, 72, 68, 104, 68]),
        _poly([67, 30, 67, 68, 46, 68]),
        _poly([42, 72, 108, 72, 100, 81, 50, 81]),
      ]),
      _circle(150, 42, 15),
      _merge([
        _oval(176, 92, 64, 22),
        Path()
          ..moveTo(176, 84)
          ..quadraticBezierTo(170, 66, 178, 50)
          ..lineTo(181, 51)
          ..quadraticBezierTo(174, 66, 180, 84)
          ..close(),
        _oval(166, 50, 22, 6),
        _oval(190, 50, 22, 6),
        _oval(172, 44, 18, 5),
        _oval(186, 44, 18, 5),
      ]),
      _water(60),
      _merge([_hump(0, 84, 36, 44, 61), _hump(104, 160, 134, 52, 61)]),
    ],
    [1, 4, 3, 2, 0],
    details: [
      Path()
        ..moveTo(69.5, 20)
        ..lineTo(69.5, 72),
      null,
      null,
      Path()
        ..moveTo(10, 74)
        ..lineTo(30, 74)
        ..moveTo(120, 80)
        ..lineTo(140, 80)
        ..moveTo(20, 92)
        ..lineTo(44, 92),
      null,
    ],
  ),
  // Village by the river
  Scene(
    'Village by the river',
    [
      _merge([
        _poly([28, 62, 41, 50, 54, 62]),
        _poly([56, 67, 67, 57, 78, 67]),
        _poly([133, 60, 146, 48, 160, 60]),
        _poly([160, 66, 170, 57, 180, 66]),
      ]),
      _merge([_rect(31, 62, 51, 80), _rect(59, 67, 75, 82), _rect(136, 60, 157, 78), _rect(163, 66, 177, 80)]),
      _merge([
        Path()
          ..moveTo(0, 66)
          ..quadraticBezierTo(60, 56, 110, 62)
          ..quadraticBezierTo(160, 68, 200, 58)
          ..lineTo(200, 100)
          ..lineTo(0, 100)
          ..close(),
        _circle(16, 60, 8),
        _circle(188, 52, 9),
        _circle(116, 56, 6),
      ]),
      Path()
        ..moveTo(78, 100)
        ..quadraticBezierTo(112, 84, 104, 64)
        ..lineTo(110, 64)
        ..quadraticBezierTo(128, 84, 124, 100)
        ..close(),
      _poly([0, 66, 30, 36, 52, 54, 86, 26, 118, 56, 148, 34, 200, 62, 200, 70, 0, 70]),
    ],
    [4, 2, 3, 1, 0],
    details: [
      null,
      Path()
        ..addRect(const Rect.fromLTWH(38, 70, 6, 10))
        ..addRect(const Rect.fromLTWH(64, 71, 6, 5))
        ..addRect(const Rect.fromLTWH(143, 67, 7, 11))
        ..addRect(const Rect.fromLTWH(167, 70, 6, 5)),
      null,
      null,
      Path()
        ..moveTo(80, 32)
        ..lineTo(86, 26)
        ..lineTo(92, 32),
    ],
  ),
  // Flower meadow
  Scene(
    'Flower meadow',
    [
      _merge([_tulip(30, 62, 6), _tulip(118, 66, 5), _tulip(176, 60, 6)]),
      _merge([
        for (var i = 0; i < 10; i++) _oval(96 + math.cos(i * 0.628) * 11, 34 + math.sin(i * 0.628) * 11, 9, 9),
        _circle(96, 34, 7),
      ]),
      _merge([
        Path()
          ..moveTo(0, 74)
          ..quadraticBezierTo(50, 64, 100, 72)
          ..quadraticBezierTo(150, 80, 200, 70)
          ..lineTo(200, 100)
          ..lineTo(0, 100)
          ..close(),
        _rect(29.2, 66, 30.8, 80),
        _rect(95.2, 44, 96.8, 76),
        _rect(117.2, 70, 118.8, 82),
        _rect(175.2, 64, 176.8, 78),
        _oval(90, 60, 10, 4),
        _oval(102, 54, 10, 4),
      ]),
      _merge([
        _forgetMeNot(58, 76, 2.6),
        _forgetMeNot(146, 82, 2.6),
        _forgetMeNot(70, 88, 2.2),
        _forgetMeNot(190, 86, 2.2),
      ]),
      _merge([_lavender(12, 82, 22), _lavender(140, 74, 24), _lavender(160, 80, 20)]),
    ],
    [2, 3, 4, 1, 0],
    details: [null, _circle(96, 34, 4.5), null, null, null],
  ),
  // Mountain lake at night
  Scene(
    'Moonlit lake',
    [
      _merge([
        _poly([78, 76, 122, 76, 115, 83, 85, 83]),
        _rect(99, 68, 102, 76, 1),
        _circle(100.5, 66, 2.4),
      ]),
      _merge([
        Path.combine(PathOperation.difference, _circle(42, 24, 11), _circle(48, 20, 9)),
        _circle(120, 14, 1.4),
        _circle(150, 26, 1.1),
        _circle(176, 12, 1.4),
        _circle(86, 30, 1.1),
        _circle(14, 12, 1.1),
      ]),
      _merge([_pine(14, 70, 26), _pine(30, 70, 20), _pine(170, 70, 24), _pine(186, 70, 30), _pine(154, 70, 16)]),
      _rect(0, 66, 200, 100),
      _poly([0, 68, 26, 40, 46, 56, 84, 18, 120, 58, 146, 36, 200, 66, 200, 68]),
    ],
    [1, 4, 3, 2, 0],
    details: [
      null,
      null,
      null,
      Path()
        ..moveTo(84, 90)
        ..lineTo(116, 90)
        ..moveTo(30, 80)
        ..lineTo(56, 80)
        ..moveTo(140, 86)
        ..lineTo(168, 86),
      Path()
        ..moveTo(76, 26)
        ..lineTo(84, 18)
        ..lineTo(92, 26),
    ],
  ),
  // Fruit bowl
  Scene(
    'Fruit bowl',
    [
      _merge([_circle(86, 50, 13), _circle(118, 52, 11)]),
      _merge([_oval(140, 50, 30, 19), _oval(156, 52, 8, 6)]),
      _merge([_circle(102, 44, 11), _circle(102, 32, 7), _oval(110, 22, 9, 4.5)]),
      _merge([
        Path()
          ..moveTo(46, 58)
          ..lineTo(154, 58)
          ..arcToPoint(const Offset(46, 58), radius: const Radius.elliptical(54, 30))
          ..close(),
        _rect(86, 86, 114, 92, 2),
      ]),
      _merge([
        for (final (x, y) in const [(58.0, 40.0), (66.0, 38.0), (62.0, 46.0), (70.0, 46.0), (54.0, 48.0), (66.0, 53.0)])
          _circle(x, y, 4.6),
      ]),
    ],
    [4, 1, 2, 0, 3],
    details: [
      Path()
        ..moveTo(86, 37)
        ..quadraticBezierTo(88, 33, 90, 31),
      null,
      null,
      Path()
        ..moveTo(52, 66)
        ..quadraticBezierTo(100, 74, 148, 66),
      null,
    ],
  ),
  // Rainbow
  Scene(
    'Rainbow after rain',
    [for (var k = 0; k < 5; k++) _rainbowBand(k)],
    [0, 1, 2, 3, 4],
    front: _merge([
      _circle(20, 92, 10),
      _circle(34, 90, 12),
      _circle(48, 95, 8),
      _circle(152, 95, 8),
      _circle(166, 90, 12),
      _circle(180, 92, 10),
      _rect(10, 92, 56, 100),
      _rect(144, 92, 190, 100),
    ]),
  ),
];

Path _rainbowBand(int k) {
  const c = Offset(100, 96);
  const outer = 80.0, w = 9.0;
  Path half(double r) => Path()
    ..moveTo(c.dx - r, c.dy)
    ..arcToPoint(Offset(c.dx + r, c.dy), radius: Radius.circular(r))
    ..close();
  return Path.combine(PathOperation.difference, half(outer - k * w), half(outer - (k + 1) * w));
}

// ---------------------------------------------------------------------------
// Painting

const _paper = Color(0xFFFFFBF3);
const _blank = Color(0xFFFFFFFF);
const _pencil = Color(0x55241A10);

/// Paints [scene] into [size]. [reveal][k] is how far layer k has filled in
/// (0 = pencil sketch, 1 = fully colored).
void paintScene(Canvas canvas, Size size, Scene scene, List<double> reveal) {
  canvas.save();
  canvas.scale(size.width / sceneW, size.height / sceneH);
  canvas.clipRect(const Rect.fromLTWH(0, 0, sceneW, sceneH));
  canvas.drawRect(const Rect.fromLTWH(0, 0, sceneW, sceneH), Paint()..color = _paper);
  final outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7
    ..strokeJoin = StrokeJoin.round;
  for (final k in scene.order) {
    final path = scene.layers[k];
    final t = reveal[k].clamp(0.0, 1.0);
    final color = Palette.balls[k];
    if (t < 1) canvas.drawPath(path, Paint()..color = _blank);
    if (t > 0) {
      final b = path.getBounds();
      canvas.save();
      if (t < 1) {
        final r = (b.size.longestSide * 0.75 + 4) * Curves.easeOutCubic.transform(t);
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: b.center, radius: r)));
      }
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(color, Colors.white, 0.28)!, color],
          ).createShader(b),
      );
      final d = scene.details[k];
      if (d != null) {
        canvas.drawPath(
          d,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.75),
        );
      }
      canvas.restore();
    }
    outline.color = Color.lerp(_pencil, Color.lerp(color, Palette.ink, 0.35)!.withValues(alpha: 0.6), t)!;
    canvas.drawPath(path, outline);
  }
  final front = scene.front;
  if (front != null) {
    canvas.drawPath(front, Paint()..color = _blank);
    outline.color = _pencil;
    canvas.drawPath(front, outline);
  }
  canvas.restore();
}

class ScenePainter extends CustomPainter {
  final Scene scene;
  final List<double> reveal;

  /// Turn the still picture into an image after a moment (for the big frame
  /// above the board; small thumbnails just replay the recording).
  final bool stamp;
  ScenePainter(this.scene, this.reveal, {this.stamp = false}) : super(repaint: stamp ? _ScenePictures.ready : null);

  @override
  void paint(Canvas canvas, Size size) {
    // A picture that isn't mid-reveal is recorded once and replayed, and a
    // moment later turned into an image that's just stamped on each frame.
    // The image is made later rather than right away because making it means
    // a read back from the graphics card, which would hitch right as a tube
    // completes.
    final still = reveal.every((v) => v == 0 || v == 1);
    if (!still || size.isEmpty) {
      paintScene(canvas, size, scene, reveal);
      return;
    }
    final img = stamp ? _ScenePictures.image(scene, reveal, size) : null;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawPicture(_ScenePictures.picture(scene, reveal, size, makeImage: stamp));
    }
  }

  @override
  bool shouldRepaint(covariant ScenePainter old) => old.scene != scene || !_sameList(old.reveal, reveal);

  static bool _sameList(List<double> a, List<double> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Still pictures: recorded right away, turned into images a little later.
class _ScenePictures {
  static final Map<String, ui.Picture> _pictures = {};
  static final Map<String, ui.Image> _images = {};
  static final Set<String> _pending = {};
  static const _max = 32;

  /// Bumped when an image is ready, so painters switch to it.
  static final ValueNotifier<int> ready = ValueNotifier(0);

  static String _key(Scene scene, List<double> reveal, Size size) =>
      '${Palette.colorblind ? 'cb' : ''}${scenes.indexOf(scene)}|${reveal.map((v) => v == 1 ? 1 : 0).join()}|${size.width.round()}|${size.height.round()}';

  static ui.Picture picture(Scene scene, List<double> reveal, Size size, {bool makeImage = false}) {
    final key = _key(scene, reveal, size);
    var pic = _pictures.remove(key);
    if (pic == null) {
      final rec = ui.PictureRecorder();
      paintScene(Canvas(rec), size, scene, reveal);
      pic = rec.endRecording();
    }
    _pictures[key] = pic;
    _trim(_pictures);
    if (makeImage && _pending.add(key)) {
      Timer(const Duration(milliseconds: 1200), () => _makeImage(key, scene, List.of(reveal), size));
    }
    return pic;
  }

  static ui.Image? image(Scene scene, List<double> reveal, Size size) {
    final key = _key(scene, reveal, size);
    final img = _images.remove(key);
    if (img != null) _images[key] = img;
    return img;
  }

  static void _makeImage(String key, Scene scene, List<double> reveal, Size size) {
    _pending.remove(key);
    if (_images.containsKey(key)) return;
    try {
      final dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 2;
      final w = math.max(1, (size.width * dpr).round()), h = math.max(1, (size.height * dpr).round());
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(w / size.width, h / size.height);
      paintScene(c, size, scene, reveal);
      final pic = rec.endRecording();
      _images[key] = pic.toImageSync(w, h);
      pic.dispose();
      _trim(_images);
      ready.value++;
    } catch (_) {}
  }

  static void _trim<T>(Map<String, T> m) {
    while (m.length > _max) {
      // Not disposed: a frame on screen may still be using it. Dropping the
      // reference lets it be freed once nothing does.
      m.remove(m.keys.first);
    }
  }
}

/// Reveal values for a finished or saved state: colored layers at 1.
List<double> revealFor(Set<int> colored, int colors) => [
  for (var k = 0; k < 5; k++) (colored.contains(k) || k >= colors) ? 1.0 : 0.0,
];

/// The framed picture above the board. Layers fill in with a watercolor wipe
/// as their tubes complete (and fade back on undo).
class PictureFrame extends StatefulWidget {
  final Scene scene;
  final Set<int> colored;

  /// How many ball colors the puzzle has. Layers past it start colored.
  final int colors;
  final bool solved;
  final String caption;
  final VoidCallback? onTap;

  const PictureFrame({
    super.key,
    required this.scene,
    required this.colored,
    required this.colors,
    required this.solved,
    this.caption = "Today's picture",
    this.onTap,
  });

  @override
  State<PictureFrame> createState() => _PictureFrameState();
}

class _PictureFrameState extends State<PictureFrame> with TickerProviderStateMixin {
  late final List<AnimationController> _layers = [
    for (var k = 0; k < 5; k++)
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
        reverseDuration: const Duration(milliseconds: 350),
        value: revealFor(widget.colored, widget.colors)[k],
      ),
  ];
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: 1,
  );

  @override
  void didUpdateWidget(PictureFrame old) {
    super.didUpdateWidget(old);
    final target = revealFor(widget.colored, widget.colors);
    final sceneChanged = old.scene != widget.scene;
    var grew = false;
    for (var k = 0; k < 5; k++) {
      final c = _layers[k];
      if (sceneChanged) {
        c.value = target[k];
      } else if (target[k] == 1 && c.value < 1 && c.status != AnimationStatus.forward) {
        c.forward();
        grew = true;
      } else if (target[k] == 0 && c.value > 0 && c.status != AnimationStatus.reverse) {
        c.reverse();
      }
    }
    if (grew) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    for (final c in _layers) {
      c.dispose();
    }
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.colored.where((c) => c < widget.colors).length;
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AnimatedBuilder(
              animation: _pop,
              builder: (_, child) {
                final t = _pop.value;
                final s = 1 + 0.05 * math.sin(t * math.pi) * (1 - t);
                return Transform.scale(scale: s, child: child);
              },
              child: AspectRatio(
                aspectRatio: sceneW / sceneH + 0.06,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE2B98A), Color(0xFFB98552)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Color(0x33241A10), blurRadius: 12, offset: Offset(0, 5))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge(_layers),
                        builder: (_, _) => CustomPaint(
                          painter: ScenePainter(widget.scene, [for (final c in _layers) c.value], stamp: true),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              widget.solved ? widget.scene.title : '${widget.caption}  ·  $done of ${widget.colors} colors',
              key: ValueKey(widget.solved),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: widget.solved ? Palette.ink : Palette.inkSoft,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
