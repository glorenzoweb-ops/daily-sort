import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// A number whose digits roll like an odometer when it changes: up when it
/// grows, down when it shrinks. Only the digits that change move.
class RollingNumber extends StatefulWidget {
  final int value;
  final TextStyle style;
  const RollingNumber(this.value, {super.key, required this.style});

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber> {
  bool _up = true;

  @override
  void didUpdateWidget(covariant RollingNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _up = widget.value > old.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = '${widget.value}';
    return Semantics(
      label: digits,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < digits.length; i++)
            ClipRect(
              child: AnimatedSwitcher(
                duration: Motion.reduced ? Duration.zero : const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.center, children: [...previous, ?current]),
                transitionBuilder: (child, a) {
                  final incoming = child.key == ValueKey('$i${digits[i]}');
                  final dir = (_up ? 1.0 : -1.0) * (incoming ? 1 : -1);
                  // Outgoing digits run this backwards, so both slide the same way.
                  return SlideTransition(
                    position: Tween(begin: Offset(0, dir), end: Offset.zero).animate(a),
                    child: child,
                  );
                },
                // Keyed by position and value: unchanged digits stay put.
                child: Text(digits[i], key: ValueKey('$i${digits[i]}'), style: widget.style),
              ),
            ),
        ],
      ),
    );
  }
}
