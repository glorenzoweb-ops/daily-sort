import 'package:material_ui/material_ui.dart';

/// Frame-time graphs over the app, for spotting slow frames on a real phone.
/// Turned on and off by tapping the title 5 times; never saved.
final showPerformance = ValueNotifier(false);

/// Five quick taps on [child] toggle [showPerformance].
class SecretTaps extends StatefulWidget {
  final Widget child;
  const SecretTaps({super.key, required this.child});

  @override
  State<SecretTaps> createState() => _SecretTapsState();
}

class _SecretTapsState extends State<SecretTaps> {
  final List<DateTime> _taps = [];

  void _tap() {
    final now = DateTime.now();
    _taps
      ..add(now)
      ..removeWhere((t) => now.difference(t) > const Duration(seconds: 3));
    if (_taps.length < 5) return;
    _taps.clear();
    showPerformance.value = !showPerformance.value;
  }

  @override
  Widget build(BuildContext context) =>
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap, excludeFromSemantics: true, child: widget.child);
}
