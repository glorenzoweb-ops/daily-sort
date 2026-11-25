import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../game/game_controller.dart';
import '../services/storage.dart';
import 'game_screen.dart' show TwistChip;
import 'motion.dart';
import 'palette.dart';
import 'perf.dart';
import 'sheets.dart';
import 'squish.dart';
import 'streak.dart';

/// The calm first screen: a greeting, today's puzzle and one big button.
/// The sky behind it is the game's own, so it follows the hour.
class HomeView extends StatefulWidget {
  final Storage storage;

  /// Today's game, once loaded.
  final GameController? daily;
  final VoidCallback onPlay;
  final VoidCallback onUnwind;
  final VoidCallback onArchive;
  final VoidCallback onExtras;
  final VoidCallback onStats;
  final VoidCallback onSettings;
  final VoidCallback onHowTo;
  final VoidCallback onStreak;
  final DateTime? now;
  const HomeView({
    super.key,
    required this.storage,
    required this.daily,
    required this.onPlay,
    required this.onUnwind,
    required this.onArchive,
    required this.onExtras,
    required this.onStats,
    required this.onSettings,
    required this.onHowTo,
    required this.onStreak,
    this.now,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

/// "Good evening, Gio 🌙": by the hour, with the player's name if known.
String greeting(DateTime now, String name) {
  final h = now.hour;
  final (String hello, String emoji) = h < 5
      ? ('Good night', '🌙')
      : h < 12
      ? ('Good morning', '☀️')
      : h < 18
      ? ('Good afternoon', '🌤️')
      : h < 22
      ? ('Good evening', '🌙')
      : ('Good night', '✨');
  final n = name.trim();
  return n.isEmpty ? '$hello $emoji' : '$hello, $n $emoji';
}

class _HomeViewState extends State<HomeView> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps the countdown to the next puzzle fresh.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final d = widget.daily;
    final stats = widget.storage.stats;
    final today = d?.puzzle.number ?? puzzleNumberFor(now);
    final soft = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.inkSoft);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              // The content sits in the middle; the icons stay at the bottom.
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox.shrink(),
                Column(
                  children: [
                    Text(
                      greeting(now, widget.storage.myName),
                      textAlign: TextAlign.center,
                      style: soft.copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 10),
                    const SecretTaps(child: DroppingLogo()),
                    const SizedBox(height: 26),
                    _TodayCard(game: d, storage: widget.storage, now: now, onPlay: widget.onPlay),
                    const SizedBox(height: 18),
                    StreakFlame(
                      streak: stats.currentStreak(today),
                      litToday: stats.lastSolvedNumber >= today,
                      freezes: stats.freezes,
                      onTap: widget.onStreak,
                    ),
                    const SizedBox(height: 10),
                    WeekDots(storage: widget.storage, today: today, now: now),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: widget.onUnwind,
                      icon: Icon(Icons.spa_rounded, color: Palette.ink),
                      label: Text(
                        'Unwind: endless calm puzzles',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Palette.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _BottomIcons(
                  items: [
                    (Icons.calendar_month_rounded, 'Archive', widget.onArchive),
                    (Icons.palette_rounded, 'Extras', widget.onExtras),
                    (Icons.bar_chart_rounded, 'Stats', widget.onStats),
                    (Icons.help_outline_rounded, 'How to', widget.onHowTo),
                    (Icons.tune_rounded, 'Settings', widget.onSettings),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Today's puzzle and the one big button: Play, Continue or See my result.
class _TodayCard extends StatelessWidget {
  final GameController? game;
  final Storage storage;
  final DateTime now;
  final VoidCallback onPlay;
  const _TodayCard({required this.game, required this.storage, required this.now, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final g = game;
    final soft = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.inkSoft);
    final String label;
    final String status;
    if (g == null) {
      label = 'One moment…';
      status = 'Getting today\'s puzzle ready';
    } else if (g.status == GameStatus.won) {
      label = 'See my result';
      final left = DateTime(now.year, now.month, now.day + 1).difference(now);
      status = '${'⭐' * g.stars} in ${g.movesUsed} moves · next puzzle in ${left.inHours} h ${left.inMinutes % 60} min';
    } else if (g.movesUsed > 0) {
      label = 'Continue';
      status = '${g.movesUsed} ${g.movesUsed == 1 ? 'move' : 'moves'} in · pick up where you left off';
    } else {
      label = 'Play';
      status = 'Same puzzle for everyone today';
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: Palette.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Palette.line, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x22241A10), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(
        children: [
          Text(
            g == null
                ? 'Today'
                : 'Daily #${g.puzzle.number} · ${dayLabel(g.puzzle.day)} · ${difficultyLabel(g.puzzle.difficulty)}',
            textAlign: TextAlign.center,
            style: Palette.display(size: 20),
          ),
          if (g != null && g.puzzle.twist != Twist.classic) ...[
            const SizedBox(height: 10),
            TwistChip(puzzle: g.puzzle),
          ],
          const SizedBox(height: 10),
          Text(status, textAlign: TextAlign.center, style: soft),
          const SizedBox(height: 16),
          BigButton(
            label: label,
            icon: g?.status == GameStatus.won ? Icons.auto_awesome_rounded : Icons.play_arrow_rounded,
            onTap: g == null ? () {} : onPlay,
          ),
        ],
      ),
    );
  }
}

/// This week, Monday to Sunday: a gold dot for each solved daily, a ring
/// around today.
class WeekDots extends StatelessWidget {
  final Storage storage;
  final int today;
  final DateTime now;
  const WeekDots({super.key, required this.storage, required this.today, required this.now});

  @override
  Widget build(BuildContext context) {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final weekday = now.weekday; // 1 = Monday
    return Semantics(
      container: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (_) {
                final n = today - (weekday - 1) + i;
                final isToday = i == weekday - 1;
                final future = i > weekday - 1;
                final solved = !future && n >= 1 && (storage.day(n)?.solved ?? false);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Semantics(
                    label:
                        '${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][i]}'
                        '${solved ? ', solved' : (future ? '' : ', not solved')}',
                    excludeSemantics: true,
                    child: Column(
                      children: [
                        Text(
                          names[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isToday ? Palette.ink : Palette.inkSoft,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: solved ? Palette.gold : (future ? Colors.transparent : Palette.card),
                            border: Border.all(
                              color: isToday ? Palette.ink : (future ? Palette.line : Palette.tubeStroke),
                              width: isToday ? 2.5 : 1.5,
                            ),
                          ),
                          child: solved
                              ? const Icon(Icons.check_rounded, size: 14, color: Palette.navy)
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _BottomIcons extends StatelessWidget {
  final List<(IconData, String, VoidCallback)> items;
  const _BottomIcons({required this.items});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final (icon, label, onTap) in items)
        Squish(
          pressedScale: 0.85,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 26, color: Palette.ink),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Palette.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// "DAILY SORT": each letter drops in as a colored ball, bounces, and turns
/// into its letter. Under a second, once per launch; a tap skips it.
class DroppingLogo extends StatefulWidget {
  const DroppingLogo({super.key});

  /// Played already this launch: later visits show the logo at once.
  static bool played = false;

  @override
  State<DroppingLogo> createState() => _DroppingLogoState();
}

class _DroppingLogoState extends State<DroppingLogo> with SingleTickerProviderStateMixin {
  static const _text = 'DAILY SORT';
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));

  @override
  void initState() {
    super.initState();
    if (DroppingLogo.played || Motion.reduced) {
      _c.value = 1;
    } else {
      DroppingLogo.played = true;
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Palette.display(size: 44, spacing: 2).copyWith(
      shadows: const [
        Shadow(color: Color(0xFFFFC23F), offset: Offset(0, 3)),
        Shadow(color: Color(0x33000000), offset: Offset(0, 5), blurRadius: 6),
      ],
    );
    return GestureDetector(
      onTap: () => _c.value = 1,
      child: Semantics(
        header: true,
        label: 'Daily Sort',
        excludeSemantics: true,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _text.length; i++) _text[i] == ' ' ? const SizedBox(width: 14) : _letter(i, style),
            ],
          ),
        ),
      ),
    );
  }

  Widget _letter(int i, TextStyle style) {
    const step = 0.045, span = 0.5;
    final t = ((_c.value - i * step) / span).clamp(0.0, 1.0);
    final fall = Curves.bounceOut.transform((t / 0.7).clamp(0.0, 1.0));
    final morph = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    final color = Palette.balls[i % Palette.balls.length];
    return Transform.translate(
      offset: Offset(0, -70 * (1 - fall)),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: morph,
            child: Text(_text[i], style: style),
          ),
          if (morph < 1 && t > 0)
            Opacity(
              opacity: 1 - morph,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.4),
                    colors: [Color.lerp(color, Colors.white, 0.55)!, color, Color.lerp(color, Colors.black, 0.25)!],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
