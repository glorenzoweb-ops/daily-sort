import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../game/game_controller.dart';
import '../services/friends.dart';
import '../services/premium.dart';
import '../services/share.dart';
import '../services/storage.dart';
import 'archive.dart';
import 'history.dart';
import 'palette.dart';
import 'social.dart';
import 'solve_art.dart';
import 'squish.dart';
import 'streak.dart';

import 'package:google_fonts/google_fonts.dart';

Future<T?> showCozySheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x55241A10),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      reverseDuration: Duration(milliseconds: 240),
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (_) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Palette.card, Palette.cardLow],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: const [BoxShadow(color: Color(0x33241A10), blurRadius: 30, offset: Offset(0, -6))],
          ),
          padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.paddingOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Palette.line, borderRadius: BorderRadius.circular(3)),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SheetTitle extends StatelessWidget {
  final String text;
  const SheetTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text, textAlign: TextAlign.center, style: Palette.display());
}

// ---------------------------------------------------------------------------
// How to play

class HowToSheet extends StatelessWidget {
  const HowToSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(String emoji, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 36, child: Text(emoji, style: const TextStyle(fontSize: 22))),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 16, height: 1.35, color: Palette.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle('How to play'),
        const SizedBox(height: 16),
        row('👆', 'Tap a tube to pick up its top ball, then tap another tube to pour it in.'),
        row('🎨', 'You can only pour onto the same color, or into an empty tube.'),
        row('🧪', 'Sort every color into its own tube before you run out of moves.'),
        row('⭐', 'Par is the fewest moves possible. Hit par for three stars.'),
        row(
          '✅',
          'Every puzzle is proven solvable. A solver finds the best solution before the puzzle reaches you, so par is always possible.',
        ),
        row('🌍', 'Everyone in the world gets the same puzzle. A new one drops at midnight.'),
        row('🎯', 'Some days add a twist: a picky tube, a locked tube or tall tubes.'),
        row('🎵', 'Every pour plays a note. Your solve becomes a song and a painting to share.'),
        row(
          '🌿',
          'Want more? Tap the leaf for Unwind: endless puzzles with no move limit, a breathing glow and soundscapes.',
        ),
        const SizedBox(height: 20),
        BigButton(label: "Let's sort", onTap: () => Navigator.pop(context)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Result + stats

class ResultSheet extends StatefulWidget {
  final GameController game;
  final Storage storage;
  final PremiumService premium;
  final bool showResult;
  final VoidCallback onPractice;

  /// Friends' results for this puzzle, and yours (null if not solved).
  final List<FriendResult> friends;
  final BoardEntry? me;
  final VoidCallback onFriends;
  final Future<void> Function() onShareToFriends;
  final VoidCallback onArchive;
  final VoidCallback onPlus;

  const ResultSheet({
    super.key,
    required this.game,
    required this.storage,
    required this.premium,
    required this.onPractice,
    required this.onFriends,
    required this.onShareToFriends,
    required this.onArchive,
    required this.onPlus,
    this.friends = const [],
    this.me,
    this.showResult = true,
  });

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

  bool _sharing = false;

  String _text() {
    final g = widget.game;
    final stats = widget.storage.stats;
    final streak = g.archive ? 0 : stats.currentStreak(g.puzzle.number);
    final name = widget.storage.myName;
    return buildShareText(
      puzzle: g.puzzle,
      moves: g.movesUsed,
      stars: g.stars,
      attempts: g.attempts,
      moveColors: g.moveColors,
      streak: streak,
      hints: g.puzzle.isPractice ? 0 : widget.storage.hintsUsed(g.puzzle.number),
      plain: plainShareOn(context, widget.storage),
      link: g.puzzle.isPractice
          ? null
          : resultLink(
              FriendResult(
                name: name.isEmpty ? 'A friend' : name,
                number: g.puzzle.number,
                moves: g.movesUsed,
                attempts: g.attempts,
                streak: streak,
              ).encode(),
            ),
    );
  }

  Future<void> _shareImage() async {
    if (_sharing) return;
    final g = widget.game;
    final p = g.puzzle;
    if (!p.isPractice) await ensureName(context, widget.storage);
    if (!mounted) return;
    setState(() => _sharing = true);
    try {
      final png = await renderSolveCard(
        pours: g.pours,
        tubeCount: p.start.tubeCount,
        title: p.isPractice ? 'Daily Sort · Unwind' : 'Daily Sort #${p.number}',
        subtitle: '${g.movesUsed} moves · par ${p.par}${p.isPractice ? '' : ' · ${dayLabel(p.day)}'}',
        stars: g.stars,
        footer: shareUrl.replaceFirst('https://', '').replaceAll(RegExp(r'/$'), ''),
        fontFamily: GoogleFonts.nunito().fontFamily,
      );
      final r = await shareImage(png, 'daily-sort-${p.isPractice ? 'practice' : p.number}.png', _text());
      _toast(r);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  bool _copied = false;

  Future<void> _copy() async {
    if (!widget.game.puzzle.isPractice) await ensureName(context, widget.storage);
    await Clipboard.setData(ClipboardData(text: _text()));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _toast(ShareOutcome r) {
    if (!mounted) return;
    if (r == ShareOutcome.copied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Result copied. Paste it anywhere!'), behavior: SnackBarBehavior.floating),
      );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showResult) ...[
          SheetTitle(perfect ? 'Perfect sort!' : 'Sorted!'),
          const SizedBox(height: 8),
          _Stars(count: g.stars),
          const SizedBox(height: 8),
          Text(
            '${g.movesUsed} moves · par ${g.puzzle.par}${g.attempts > 1 ? ' · ${ordinal(g.attempts)} try' : ''}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Palette.inkSoft, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1.6,
            child: Container(
              decoration: BoxDecoration(
                color: Palette.background,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Palette.line, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: SolveArtPlayer(pours: g.pours, tubeCount: g.puzzle.start.tubeCount),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your solve, painted. Every solution makes a different picture and song.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Palette.inkSoft, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          BigButton(
            label: _sharing ? 'Painting…' : 'Share my painting',
            icon: Icons.ios_share_rounded,
            onTap: _shareImage,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SmallButton(
                  label: _copied ? 'Copied!' : 'Copy emoji',
                  icon: _copied ? Icons.check_rounded : Icons.grid_view_rounded,
                  onTap: _copy,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SmallButton(
                  label: g.puzzle.isPractice ? 'Next puzzle' : 'Unwind',
                  icon: Icons.spa_rounded,
                  onTap: widget.onPractice,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
        ] else ...[
          const SheetTitle('Statistics'),
          const SizedBox(height: 18),
        ],
        if (g.puzzle.isPractice) ...[
          FreezeProgress(stats: stats, justEarned: g.earnedFreeze),
          const SizedBox(height: 12),
          Text(
            'Unwind puzzles solved: ${widget.storage.practiceSolved}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Palette.inkSoft, fontWeight: FontWeight.w800),
          ),
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat('${stats.solved}', 'Solved'),
              _Stat('${stats.currentStreak(g.puzzle.number)}', 'Streak'),
              _Stat('${stats.maxStreak}', 'Best'),
              _Stat('$perfectPct%', 'Perfect'),
            ],
          ),
        if (!g.puzzle.isPractice) ...[
          const SizedBox(height: 22),
          HistoryCalendar(storage: widget.storage, today: puzzleNumberFor(DateTime.now())),
        ],
        if (!g.puzzle.isPractice && !g.archive) ...[
          const SizedBox(height: 22),
          _FriendsPreview(
            rows: rankDay(widget.friends, me: widget.me),
            onSeeAll: widget.onFriends,
            onShare: widget.onShareToFriends,
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SmallButton(label: 'Past puzzles', icon: Icons.calendar_month_rounded, onTap: widget.onArchive),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SmallButton(label: 'Friends', icon: Icons.people_alt_rounded, onTap: widget.onFriends),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (solved && !g.puzzle.isPractice && !g.archive) ...[
          Text(
            'Next daily puzzle in',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Palette.inkSoft, fontWeight: FontWeight.w700),
          ),
          Text(
            _fmt(_left),
            textAlign: TextAlign.center,
            style: Palette.display(size: 34).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 18),
        ],
        // A gentle note, only once the player has enjoyed a few dailies.
        if (!widget.premium.isPremium && widget.storage.stats.solved >= solvesBeforePlusNote)
          PlusBanner(text: 'Daily Sort+: every past puzzle, any time', onTap: widget.onPlus),
      ],
    );
  }
}

/// Top of today's friends board inside the result sheet.
class _FriendsPreview extends StatelessWidget {
  final List<BoardEntry> rows;
  final VoidCallback onSeeAll;
  final Future<void> Function() onShare;
  const _FriendsPreview({required this.rows, required this.onSeeAll, required this.onShare});

  @override
  Widget build(BuildContext context) {
    final friendsOnly = rows.where((r) => !r.isMe).isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Friends today', style: Palette.display(size: 20)),
            const Spacer(),
            if (!friendsOnly)
              TextButton(
                onPressed: onSeeAll,
                child: Text(
                  'See all',
                  style: TextStyle(fontWeight: FontWeight.w900, color: Palette.ink),
                ),
              ),
          ],
        ),
        if (friendsOnly)
          Squish(
            child: Material(
              color: Palette.background,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onShare,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Text('👋', style: TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          rows.isEmpty
                              ? 'Invite friends to play. When they share their result, you\'ll see who sorted it in fewer moves.'
                              : 'Send your result to friends. When they share back, you\'ll see who sorted it in fewer moves.',
                          style: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w700, color: Palette.ink),
                        ),
                      ),
                      Icon(Icons.ios_share_rounded, color: Palette.ink),
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < rows.length && i < 3; i++) BoardRow(rank: i + 1, e: rows[i]),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  final int count;
  const _Stars({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 380 + i * 160),
            curve: Interval(i * 0.25, 1, curve: Curves.elasticOut),
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.star_rounded, size: 46, color: i < count ? Palette.gold : Palette.line),
            ),
          ),
      ],
    );
  }
}

class SmallButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const SmallButton({super.key, required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Squish(
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.ink,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: Palette.tubeStroke, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Palette.display(size: 28)),
      Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.inkSoft),
      ),
    ],
  );
}

class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const BigButton({super.key, required this.label, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Squish(
      child: SizedBox(
        height: 56,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Palette.ink,
            foregroundColor: Palette.onInk,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          onPressed: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: 10)],
              Text(label),
            ],
          ),
        ),
      ),
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
