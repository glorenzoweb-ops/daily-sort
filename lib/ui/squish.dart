import 'package:material_ui/material_ui.dart';

/// Makes any button feel soft: it squishes down while pressed and springs
/// back when released. Doesn't steal the tap from the child.
class Squish extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  const Squish({super.key, required this.child, this.pressedScale = 0.9});

  @override
  State<Squish> createState() => _SquishState();
}

class _SquishState extends State<Squish> {
  bool _down = false;

  void _set(bool v) {
    if (v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: Duration(milliseconds: _down ? 90 : 320),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}
