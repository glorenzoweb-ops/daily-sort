import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../game/game_controller.dart';
import '../services/premium.dart';
import '../services/share.dart';
import '../services/storage.dart';
import 'palette.dart';

Future<T?> showCozySheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (_) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: const BoxDecoration(
            color: Palette.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.paddingOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: const Color(0xFFE6DED0), borderRadius: BorderRadius.circular(3)),
              ),
              child,
            ]),
          ),
        ),
      ),
    ),
  );
}

class _H extends StatelessWidget {
  final String text;
  const _H(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Palette.ink));
}

// ---------------------------------------------------------------------------
// How to play

class HowToSheet extends StatelessWidget {
  const HowToSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(String emoji, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 36, child: Text(emoji, style: const TextStyle(fontSize: 22))),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 16, height: 1.35, color: Palette.ink, fontWeight: FontWeight.w600))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _H('How to play'),
      const SizedBox(height: 16),
      row('👆', 'Tap a tube to pick up its top ball, then tap another tube to pour it in.'),
      row('🎨', 'You can only pour onto the same color, or into an empty tube.'),
      row('🧪', 'Sort every color into its own tube before you run out of moves.'),
      row('⭐', 'Par is the fewest moves possible. Hit par for three stars.'),
      row('🌍', 'Everyone in the world gets the same puzzle. A new one drops at midnight.'),
      const SizedBox(height: 20),
      _BigButton(label: "Let's sort", onTap: () => Navigator.pop(context)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Result + stats

class ResultSheet extends StatefulWidget {
  final GameController game;
  final Storage storage;
  final PremiumService premium;
  final bool showResult;
  const ResultSheet({super.key, required this.game, required this.storage, required this.premium, this.showResult = true});

  @override
  State<ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<ResultSheet> {
  Timer? _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    setState(() => _left = midnight.difference(now));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _share() async {
    final g = widget.game;
    final stats = widget.storage.stats;
    final text = buildShareText(
      puzzle: g.puzzle,
      moves: g.movesUsed,
      stars: g.stars,
      attempts: g.attempts,
      moveColors: g.moveColors,
      streak: stats.currentStreak(g.puzzle.number),
    );
    final r = await shareResult(text);
    if (!mounted) return;
    if (r == ShareOutcome.copied) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Result copied. Paste it anywhere!'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final stats = widget.storage.stats;
    final solved = g.status == GameStatus.won;
    final showResult = widget.showResult && solved;
    final perfect = g.movesUsed <= g.puzzle.par;
    final perfectPct = stats.solved == 0 ? 0 : ((stats.stars[3] ?? 0) * 100 / stats.solved).round();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showResult) ...[
        _H(perfect ? 'Perfect sort!' : 'Sorted!'),
        const SizedBox(height: 8),
        _Stars(count: g.stars),
        const SizedBox(height: 8),
        Text(
          '${g.movesUsed} moves · par ${g.puzzle.par}${g.attempts > 1 ? ' · ${ordinal(g.attempts)} try' : ''}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: Palette.inkSoft, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        _EmojiGrid(colors: g.moveColors),
        const SizedBox(height: 20),
        _BigButton(label: 'Share result', icon: Icons.ios_share_rounded, onTap: _share),
        const SizedBox(height: 22),
      ] else ...[
        const _H('Statistics'),
        const SizedBox(height: 18),
      ],
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Stat('${stats.solved}', 'Solved'),
        _Stat('${stats.currentStreak(g.puzzle.number)}', 'Streak'),
        _Stat('${stats.maxStreak}', 'Best'),
        _Stat('$perfectPct%', 'Perfect'),
      ]),
      const SizedBox(height: 22),
      if (solved) ...[
        const Text('Next puzzle in',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Palette.inkSoft, fontWeight: FontWeight.w700)),
        Text(_fmt(_left),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Palette.ink,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 18),
      ],
      PremiumTeaser(premium: widget.premium),
    ]);
  }
}

class _Stars extends StatelessWidget {
  final int count;
  const _Stars({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < 3; i++)
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 380 + i * 160),
          curve: Interval(i * 0.25, 1, curve: Curves.elasticOut),
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.star_rounded,
                size: 46, color: i < count ? Palette.gold : const Color(0xFFEDE6D9)),
          ),
        ),
    ]);
  }
}

class _EmojiGrid extends StatelessWidget {
  final List<int> colors;
  const _EmojiGrid({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < colors.length; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 300 + i * 60),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: v.clamp(0, 2), child: child),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Palette.balls[colors[i] % Palette.balls.length],
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Palette.ink)),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.inkSoft)),
      ]);
}

class _BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const _BigButton({required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Palette.ink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        onPressed: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: 10)],
          Text(label),
        ]),
      ),
    );
  }
}

/// "Daily Sort+" card. Payments aren't live yet, so it says "coming soon".
class PremiumTeaser extends StatelessWidget {
  final PremiumService premium;
  const PremiumTeaser({super.key, required this.premium});

  @override
  Widget build(BuildContext context) {
    if (premium.isPremium) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(children: [
        Text('✨', style: TextStyle(fontSize: 28)),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Daily Sort+ is coming',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Palette.ink)),
            SizedBox(height: 2),
            Text('Every past puzzle, hints and a par-or-bust hard mode.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.inkSoft)),
          ]),
        ),
      ]),
    );
  }
}

/// Day label like "Fri, Nov 20".
String dayLabel(DateTime d) {
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${wd[d.weekday - 1]}, ${mo[d.month - 1]} ${d.day}';
}

String difficultyLabel(Difficulty d) => switch (d) {
      Difficulty.easy => 'Easy',
      Difficulty.medium => 'Medium',
      Difficulty.hard => 'Tricky',
    };
