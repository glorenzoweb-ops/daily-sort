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
import 'sky.dart';
import 'squish.dart';
import '../services/puzzles.dart';
import 'sheets.dart';

class GameScreen extends StatefulWidget {
  final Storage storage;
  final PremiumService premium;
  const GameScreen({super.key, required this.storage, required this.premium});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  // Both modes stay alive, so switching never loses your place.
  GameController? _daily, _unwind;
  bool _inUnwind = false;
  late final Puzzles _puzzles = Puzzles(widget.storage);
  final _confetti = ConfettiController();
  GameController? get _game => _inUnwind ? _unwind : _daily;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDaily();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _daily?.dispose();
    _unwind?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A new day started while the app was in the background.
    if (state == AppLifecycleState.resumed &&
        _daily != null &&
        puzzleNumberFor(DateTime.now()) != _daily!.puzzle.number) {
      _loadDaily();
    }
  }

  Future<void> _loadDaily() async {
    final puzzle = await _puzzles.daily(DateTime.now());
    if (!mounted) return;
    setState(() {
      _daily?.dispose();
      _daily = GameController(puzzle, widget.storage);
    });
    // Get an Unwind puzzle ready while the player looks at today's board.
    Future<void>.delayed(const Duration(milliseconds: 1500), _puzzles.prefetchUnwind);
    if (!widget.storage.seenHowTo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      widget.storage.setSeenHowTo();
      showCozySheet(context, const HowToSheet());
    }
  }

  Future<void> _newUnwind() async {
    final puzzle = await _puzzles.unwind();
    if (!mounted) return;
    setState(() {
      _unwind?.dispose();
      _unwind = GameController(puzzle, widget.storage);
    });
    Future<void>.delayed(const Duration(milliseconds: 1500), _puzzles.prefetchUnwind);
  }

  /// Daily ⇄ Unwind. Each keeps its board exactly as you left it.
  void _setMode(bool unwind) {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    if (unwind == _inUnwind) return;
    setState(() => _inUnwind = unwind);
    if (unwind && (_unwind == null || _unwind!.status == GameStatus.won)) _newUnwind();
  }

  /// "Unwind" from the daily result, or "Next puzzle" inside Unwind.
  void _startPractice() {
    if (_inUnwind) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      _newUnwind();
    } else {
      _setMode(true);
    }
  }

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
    // A calm moment: prepare what comes next.
    if (_inUnwind) {
      _puzzles.prefetchUnwind();
    } else {
      Future<void>.delayed(const Duration(seconds: 2), () => _puzzles.prefetchTomorrow(DateTime.now()));
    }
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
          const Positioned.fill(child: SkyBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: g == null
                    ? _Loading(unwind: _inUnwind, onBack: _daily == null ? null : () => _setMode(false))
                    : _buildGame(g),
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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      _IconBtn(
                        Icons.help_outline_rounded,
                        'How to play',
                        () => showCozySheet(context, const HowToSheet()),
                      ),
                      _IconBtn(
                        Sounds.ambience != Ambience.off || Sounds.music
                            ? Icons.music_note_rounded
                            : (Sounds.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                        'Sound and soundscapes',
                        _openSound,
                      ),
                      const Spacer(),
                      _IconBtn(
                        Icons.bar_chart_rounded,
                        'Statistics',
                        () => _openResults(statsOnly: g.status != GameStatus.won),
                      ),
                    ],
                  ),
                  ModeSwitch(unwind: _inUnwind, onChanged: _setMode),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.isPractice ? 'UNWIND' : 'DAILY SORT',
              style: Palette.display(size: 38, spacing: 2).copyWith(
                shadows: const [
                  Shadow(color: Color(0xFFFFC23F), offset: Offset(0, 3)),
                  Shadow(color: Color(0x33000000), offset: Offset(0, 5), blurRadius: 6),
                ],
              ),
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
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF34344F), Palette.ink],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x40241A10), blurRadius: 14, offset: Offset(0, 6))],
      ),
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
            Squish(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  elevation: 4,
                  shadowColor: const Color(0x66C08A1E),
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
            ),
            const SizedBox(width: 12),
            Squish(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
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
          Squish(
            child: Material(
              elevation: enabled ? 3 : 0,
              shadowColor: const Color(0x66241A10),
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
  Widget build(BuildContext context) => Squish(
    pressedScale: 0.82,
    child: IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 28, color: Palette.ink),
    ),
  );
}

class _Loading extends StatelessWidget {
  final bool unwind;
  final VoidCallback? onBack;
  const _Loading({this.unwind = false, this.onBack});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (onBack != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ModeSwitch(unwind: unwind, onChanged: (u) => u ? null : onBack!()),
        ),
      Expanded(
        child: Center(
          child: Text(
            unwind ? 'Mixing a calm puzzle…' : 'Mixing today\'s colors…',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Palette.inkSoft),
          ),
        ),
      ),
    ],
  );
}

/// The Daily / Unwind switch at the top: a pill with a sliding highlight.
class ModeSwitch extends StatelessWidget {
  final bool unwind;
  final ValueChanged<bool> onChanged;
  const ModeSwitch({super.key, required this.unwind, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const segW = 88.0, h = 40.0;
    Widget seg(bool isUnwind, IconData icon, String label) {
      final on = unwind == isUnwind;
      return Semantics(
        button: true,
        selected: on,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(isUnwind),
          child: SizedBox(
            width: segW,
            height: h,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: on ? Colors.white : Palette.ink),
                const SizedBox(width: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: on ? Colors.white : Palette.ink,
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Squish(
      pressedScale: 0.95,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(h),
          border: Border.all(color: Palette.tubeStroke, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x22241A10), blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              left: unwind ? segW : 0,
              top: 0,
              width: segW,
              height: h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: unwind ? const Color(0xFF2EA383) : Palette.ink,
                  borderRadius: BorderRadius.circular(h),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [seg(false, Icons.wb_sunny_rounded, 'Daily'), seg(true, Icons.spa_rounded, 'Unwind')],
            ),
          ],
        ),
      ),
    );
  }
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
        Text('Sound', textAlign: TextAlign.center, style: Palette.display()),
        const SizedBox(height: 6),
        const Text(
          'Pick a soundscape. It softens as your tubes fill.',
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
              Squish(
                child: _AmbienceTile(ambience: a, selected: Sounds.ambience == a, onTap: () => _pick(a)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text(
            'Calm music',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.ink),
          ),
          subtitle: const Text(
            'A soft pad and a wandering kalimba, never the same twice',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.inkSoft),
          ),
          value: Sounds.music,
          activeThumbColor: Palette.gold,
          onChanged: (v) {
            Sounds.setMusic(v);
            widget.storage.setMusic(v);
            setState(() {});
            widget.onChanged();
          },
        ),
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
