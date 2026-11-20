import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../game/game_controller.dart';
import '../services/premium.dart';
import '../services/sound.dart';
import '../services/sound/ambience.dart';
import '../services/storage.dart';
import 'board_view.dart';
import 'confetti.dart';
import 'palette.dart';
import 'sheets.dart';

class GameScreen extends StatefulWidget {
  final Storage storage;
  final PremiumService premium;
  const GameScreen({super.key, required this.storage, required this.premium});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  GameController? _game;
  final _confetti = ConfettiController();
  bool get _practice => _game?.puzzle.isPractice ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A new day started while the app was in the background.
    if (state == AppLifecycleState.resumed &&
        _game != null &&
        !_practice &&
        puzzleNumberFor(DateTime.now()) != _game!.puzzle.number) {
      _load();
    }
  }

  Future<void> _load({bool practice = false}) async {
    // Let the loading frame paint before the (sub-second) puzzle generation.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final puzzle = practice
        ? practicePuzzle(DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF)
        : puzzleForDay(DateTime.now());
    final game = GameController(puzzle, widget.storage);
    if (!mounted) return;
    setState(() {
      _game?.dispose();
      _game = game;
    });
    if (!widget.storage.seenHowTo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      widget.storage.setSeenHowTo();
      showCozySheet(context, const HowToSheet());
    }
  }

  void _startPractice() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    _load(practice: true);
  }

  void _backToToday() => _load();

  void _openSound() {
    showCozySheet(
      context,
      SoundSheet(
        storage: widget.storage,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _onWin() {
    _confetti.burst();
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _openResults();
    });
  }

  void _openResults({bool statsOnly = false}) {
    final g = _game;
    if (g == null) return;
    showCozySheet(
      context,
      ResultSheet(
        game: g,
        storage: widget.storage,
        premium: widget.premium,
        showResult: !statsOnly,
        onPractice: _startPractice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _game;
    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _PaperPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: g == null ? const _Loading() : _buildGame(g),
              ),
            ),
          ),
          Positioned.fill(child: Confetti(controller: _confetti)),
        ],
      ),
    );
  }

  Widget _buildGame(GameController g) {
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        final p = g.puzzle;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  _IconBtn(Icons.help_outline_rounded, 'How to play', () => showCozySheet(context, const HowToSheet())),
                  _IconBtn(
                    Sounds.ambience != Ambience.off
                        ? Icons.music_note_rounded
                        : (Sounds.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                    'Sound and soundscapes',
                    _openSound,
                  ),
                  const Spacer(),
                  if (p.isPractice)
                    _IconBtn(Icons.today_rounded, "Back to today's puzzle", _backToToday)
                  else
                    _IconBtn(Icons.spa_rounded, 'Unwind: endless calm puzzles', _startPractice),
                  _IconBtn(
                    Icons.bar_chart_rounded,
                    'Statistics',
                    () => _openResults(statsOnly: g.status != GameStatus.won),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.isPractice ? 'UNWIND' : 'DAILY SORT',
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Palette.ink, letterSpacing: 1.5),
            ),
            const SizedBox(height: 2),
            Text(
              p.isPractice
                  ? 'No limits. Just sort and breathe.'
                  : '#${p.number}  ·  ${dayLabel(p.day)}  ·  ${difficultyLabel(p.difficulty)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.inkSoft),
            ),
            const SizedBox(height: 18),
            _MovesPill(used: g.movesUsed, limit: p.isPractice ? null : p.moveLimit),
            if (p.twist != Twist.classic) ...[const SizedBox(height: 10), TwistChip(puzzle: p)],
            const SizedBox(height: 8),
            Text(
              g.status == GameStatus.won
                  ? 'Solved!  ·  par ${p.par}'
                  : (p.isPractice ? 'Par ${p.par}  ·  take your time' : 'Par ${p.par}  ·  ${g.movesLeft} left'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: !p.isPractice && g.movesLeft <= 2 && g.status == GameStatus.playing
                    ? Palette.danger
                    : Palette.inkSoft,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: BoardView(key: ObjectKey(g), game: g, onWinAnimationDone: _onWin, breathe: p.isPractice),
              ),
            ),
            _BottomBar(game: g, onResults: _openResults, onNext: _startPractice),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _MovesPill extends StatelessWidget {
  final int used;
  final int? limit; // null in Unwind: no limit
  const _MovesPill({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'MOVES  ',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, a) => ScaleTransition(
              scale: Tween(begin: 1.5, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Text(
              '$used',
              key: ValueKey(used),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Palette.gold),
            ),
          ),
          if (limit != null)
            Text(
              ' / $limit',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final GameController game;
  final VoidCallback onResults;
  final VoidCallback onNext;
  const _BottomBar({required this.game, required this.onResults, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final g = game;
    Widget child;
    switch (g.status) {
      case GameStatus.won:
        final practice = g.puzzle.isPractice;
        child = Row(
          key: const ValueKey('won'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Palette.gold,
                foregroundColor: Palette.ink,
                minimumSize: const Size(170, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              onPressed: practice ? onNext : onResults,
              icon: Icon(practice ? Icons.arrow_forward_rounded : Icons.brush_rounded),
              label: Text(practice ? 'Next puzzle' : 'My painting'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Palette.ink,
                minimumSize: const Size(120, 56),
                side: const BorderSide(color: Palette.tubeStroke, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              onPressed: practice ? onResults : onNext,
              icon: Icon(practice ? Icons.brush_rounded : Icons.spa_rounded),
              label: Text(practice ? 'Painting' : 'Unwind'),
            ),
          ],
        );
      case GameStatus.outOfMoves:
        child = Column(
          key: const ValueKey('out'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Out of moves!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Palette.danger),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundAction(Icons.undo_rounded, 'Undo', g.undo),
                const SizedBox(width: 18),
                _RoundAction(Icons.refresh_rounded, 'Try again', g.restart, primary: true),
              ],
            ),
          ],
        );
      case GameStatus.playing:
        child = Row(
          key: const ValueKey('play'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundAction(Icons.undo_rounded, 'Undo', g.canUndo ? g.undo : null),
            const SizedBox(width: 18),
            _RoundAction(Icons.refresh_rounded, 'Restart', g.history.isNotEmpty ? g.restart : null),
          ],
        );
    }
    return SizedBox(
      height: 110,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(a),
              child: c,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  const _RoundAction(this.icon, this.label, this.onTap, {this.primary = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: primary ? Palette.ink : Colors.white,
            shape: const CircleBorder(side: BorderSide(color: Palette.tubeStroke, width: 2)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 58,
                height: 58,
                child: Icon(icon, size: 28, color: primary ? Colors.white : Palette.ink),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(icon, size: 28, color: Palette.ink),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      'Mixing today\'s colors…',
      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Palette.inkSoft),
    ),
  );
}

/// Faint ruled-paper background.
class _PaperPainter extends CustomPainter {
  const _PaperPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Palette.gridLine
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Explains today's rule twist in one line.
class TwistChip extends StatelessWidget {
  final DailyPuzzle puzzle;
  const TwistChip({super.key, required this.puzzle});

  @override
  Widget build(BuildContext context) {
    final b = puzzle.start;
    final (String icon, String text, Color color) = switch (puzzle.twist) {
      Twist.pickyTube => (
        '🎯',
        'Picky tube: only takes ${colorName(b.rules.pickyColor)}',
        Palette.balls[b.rules.pickyColor],
      ),
      Twist.lockedTube => ('🔒', 'Locked tube opens after ${b.rules.unlockAfter} moves', Palette.ink),
      Twist.tallTubes => ('📏', 'Tall tubes: 5 balls each', Palette.ink),
      Twist.classic => ('', '', Palette.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: Text(
        '$icon  $text',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.ink),
      ),
    );
  }
}

String colorName(int c) => const ['red', 'yellow', 'green', 'blue', 'purple', 'orange'][c % 6];

/// Notes on/off and the background soundscape picker.
class SoundSheet extends StatefulWidget {
  final Storage storage;
  final VoidCallback onChanged;
  const SoundSheet({super.key, required this.storage, required this.onChanged});

  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  void _pick(Ambience a) {
    Sounds.setAmbience(a);
    widget.storage.setAmbience(a.name);
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Sound',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Palette.ink),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pick a soundscape to play while you sort.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.inkSoft),
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            for (final a in Ambience.values)
              _AmbienceTile(ambience: a, selected: Sounds.ambience == a, onTap: () => _pick(a)),
          ],
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text(
            'Notes and clinks when you pour',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.ink),
          ),
          value: Sounds.enabled,
          activeThumbColor: Palette.gold,
          onChanged: (v) {
            Sounds.enabled = v;
            widget.storage.setSound(v);
            if (v) Sounds.note(4, volume: 0.5);
            setState(() {});
            widget.onChanged();
          },
        ),
        const Text(
          'On iPhone, turn off the silent switch to hear sound.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.inkSoft),
        ),
      ],
    );
  }
}

class _AmbienceTile extends StatelessWidget {
  final Ambience ambience;
  final bool selected;
  final VoidCallback onTap;
  const _AmbienceTile({required this.ambience, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFFF3D6) : Palette.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? Palette.gold : const Color(0xFFEDE6D9), width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(ambienceEmoji(ambience), style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 4),
            Text(
              ambienceLabel(ambience),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.ink),
            ),
          ],
        ),
      ),
    );
  }
}
