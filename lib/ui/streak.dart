import 'package:material_ui/material_ui.dart';

import '../services/feedback.dart';
import '../services/storage.dart';
import 'palette.dart';
import 'squish.dart';

const _flameTop = Color(0xFFFFC23F);
const _flameBottom = Color(0xFFFF6A3D);
const _ice = Color(0xFF5AB8F0);

/// Streak lengths that get a full-screen celebration.
const streakMilestones = {3, 7, 14, 30, 50, 100, 200, 365};

/// The flame in two tones: a cheap stand-in for a gradient (a ShaderMask
/// would cost an extra offscreen layer on every frame).
Widget _flameIcon(double size, {bool lit = true}) {
  const icon = Icons.local_fire_department_rounded;
  final top = lit ? _flameTop : const Color(0xFFD8CFC0);
  final bottom = lit ? _flameBottom : const Color(0xFFC2B6A3);
  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      children: [
        Icon(icon, size: size, color: bottom),
        ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 0.48,
            child: Icon(icon, size: size, color: top),
          ),
        ),
      ],
    ),
  );
}

/// The flame counter next to the moves pill. Lit once today's puzzle is
/// solved; it bounces when the streak grows. Shows banked freezes as a small
/// snowflake badge.
class StreakFlame extends StatefulWidget {
  final int streak;
  final bool litToday;
  final int freezes;
  final VoidCallback onTap;
  const StreakFlame({
    super.key,
    required this.streak,
    required this.litToday,
    required this.freezes,
    required this.onTap,
  });

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(covariant StreakFlame old) {
    super.didUpdateWidget(old);
    if (widget.streak > old.streak || (widget.litToday && !old.litToday)) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.streak} day streak, ${widget.freezes} streak freezes',
      child: Squish(
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _pop,
            builder: (context, child) {
              final t = _pop.value;
              final scale = 1 + 0.35 * Curves.elasticOut.transform(t) * (1 - t);
              return Transform.scale(scale: scale, child: child);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 48,
                  padding: const EdgeInsets.fromLTRB(10, 0, 16, 0),
                  decoration: BoxDecoration(
                    color: Palette.card,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: widget.litToday ? const Color(0xFFFFB27A) : Palette.tubeStroke, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: widget.litToday ? const Color(0x55FF8A3D) : const Color(0x22241A10),
                        blurRadius: widget.litToday ? 16 : 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _flameIcon(28, lit: widget.litToday),
                      const SizedBox(width: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (c, a) => ScaleTransition(
                          scale: Tween(
                            begin: 1.6,
                            end: 1.0,
                          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
                          child: FadeTransition(opacity: a, child: c),
                        ),
                        child: Text(
                          '${widget.streak}',
                          key: ValueKey(widget.streak),
                          style: Palette.display(
                            size: 22,
                            color: widget.litToday ? const Color(0xFFE5602B) : Palette.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.freezes > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _ice,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.ac_unit_rounded, size: 11, color: Colors.white),
                          Text(
                            '${widget.freezes}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two freeze slots, filled or empty.
class FreezeSlots extends StatelessWidget {
  final int freezes;
  const FreezeSlots({super.key, required this.freezes});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < Stats.maxFreezes; i++)
        Container(
          width: 44,
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i < freezes ? const Color(0xFFE3F3FD) : Palette.panel,
            border: Border.all(color: i < freezes ? _ice : Palette.tubeStroke, width: 2),
          ),
          child: Icon(Icons.ac_unit_rounded, color: i < freezes ? _ice : const Color(0xFFD8CFC0), size: 24),
        ),
    ],
  );
}

/// Unwind solves toward the next freeze, as five little dots.
class FreezeProgress extends StatelessWidget {
  final Stats stats;
  final bool justEarned;
  const FreezeProgress({super.key, required this.stats, this.justEarned = false});

  @override
  Widget build(BuildContext context) {
    final full = stats.freezes >= Stats.maxFreezes;
    final String line;
    if (justEarned) {
      line = 'You earned a streak freeze! It protects your streak if you miss a day.';
    } else if (full) {
      line = 'Your freezes are full (${Stats.maxFreezes}/${Stats.maxFreezes}). Your streak is well protected.';
    } else {
      final left = Stats.unwindPerFreeze - stats.freezeProgress;
      line = '$left more Unwind ${left == 1 ? 'solve' : 'solves'} to earn a streak freeze.';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8FD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFE2F7), width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FreezeSlots(freezes: stats.freezes),
              if (!full) ...[
                const SizedBox(width: 14),
                for (var i = 0; i < Stats.unwindPerFreeze; i++)
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < stats.freezeProgress ? _ice : const Color(0xFFDCEAF3),
                    ),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            line,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF2F6E95)),
          ),
        ],
      ),
    );
  }
}

/// Tapping the flame: what the streak is and how freezes work.
class StreakSheet extends StatelessWidget {
  final Stats stats;
  final int today;
  final bool solvedToday;
  final VoidCallback onUnwind;
  const StreakSheet({
    super.key,
    required this.stats,
    required this.today,
    required this.solvedToday,
    required this.onUnwind,
  });

  @override
  Widget build(BuildContext context) {
    final streak = stats.currentStreak(today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _flameIcon(72, lit: solvedToday)),
        Text(
          streak == 1 ? '1-day streak' : '$streak-day streak',
          textAlign: TextAlign.center,
          style: Palette.display(size: 30),
        ),
        const SizedBox(height: 6),
        Text(
          solvedToday
              ? 'Done for today. Come back tomorrow to keep it going.'
              : (streak == 0
                    ? 'Solve today\'s puzzle to start a streak.'
                    : 'Solve today\'s puzzle to keep your streak alive.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.inkSoft),
        ),
        const SizedBox(height: 4),
        Text(
          'Best: ${stats.maxStreak} ${stats.maxStreak == 1 ? 'day' : 'days'}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.inkSoft),
        ),
        const SizedBox(height: 18),
        FreezeProgress(stats: stats),
        const SizedBox(height: 14),
        Squish(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2EA383),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              onPressed: onUnwind,
              icon: const Icon(Icons.spa_rounded),
              label: const Text('Earn freezes in Unwind'),
            ),
          ),
        ),
      ],
    );
  }
}

String _milestoneLine(int days) => switch (days) {
  3 => 'A habit is forming.',
  7 => 'A whole week of calm sorting.',
  14 => 'Two weeks strong.',
  30 => 'A full month. Legendary.',
  50 => 'Fifty days of tidy tubes.',
  100 => 'Triple digits!',
  200 => 'Two hundred days. Wow.',
  365 => 'A whole year of sorting!',
  _ => 'Keep it going!',
};

/// Full-screen celebration when the streak reaches a milestone.
Future<void> showStreakMilestone(BuildContext context, int days) {
  Haptics.win();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x88241A10),
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (context, _, _) => _Milestone(days: days),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
        child: child,
      ),
    ),
  );
}

class _Milestone extends StatefulWidget {
  final int days;
  const _Milestone({required this.days});

  @override
  State<_Milestone> createState() => _MilestoneState();
}

class _MilestoneState extends State<_Milestone> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 300,
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Palette.picked, Palette.card],
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [BoxShadow(color: Color(0x66FF8A3D), blurRadius: 40, offset: Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (context, child) => Transform.scale(scale: 1 + 0.08 * _c.value, child: child),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x66FFC23F), blurRadius: 40, spreadRadius: 6)],
                  ),
                  child: _flameIcon(120),
                ),
              ),
              Text('${widget.days}-day streak!', textAlign: TextAlign.center, style: Palette.display(size: 32)),
              const SizedBox(height: 6),
              Text(
                _milestoneLine(widget.days),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.inkSoft),
              ),
              const SizedBox(height: 20),
              Squish(
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF7A3D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Keep it going'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
