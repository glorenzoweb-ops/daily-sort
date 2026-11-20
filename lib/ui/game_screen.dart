import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../game/game_controller.dart';
import '../services/premium.dart';
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
    if (state == AppLifecycleState.resumed && _game != null &&
        puzzleNumberFor(DateTime.now()) != _game!.puzzle.number) {
      _load();
    }
  }

  Future<void> _load() async {
    // Let the loading frame paint before the (sub-second) puzzle generation.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final puzzle = puzzleForDay(DateTime.now());
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
        context, ResultSheet(game: g, storage: widget.storage, premium: widget.premium, showResult: !statsOnly));
  }

  @override
  Widget build(BuildContext context) {
    final g = _game;
    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(children: [
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
      ]),
    );
  }

  Widget _buildGame(GameController g) {
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        final p = g.puzzle;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              _IconBtn(Icons.help_outline_rounded, 'How to play', () => showCozySheet(context, const HowToSheet())),
              const Spacer(),
              _IconBtn(Icons.bar_chart_rounded, 'Statistics',
                  () => _openResults(statsOnly: g.status != GameStatus.won)),
            ]),
          ),
          const SizedBox(height: 4),
          const Text('DAILY SORT',
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Palette.ink, letterSpacing: 1.5)),
          const SizedBox(height: 2),
          Text('#${p.number}  ·  ${dayLabel(p.day)}  ·  ${difficultyLabel(p.difficulty)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.inkSoft)),
          const SizedBox(height: 18),
          _MovesPill(used: g.movesUsed, limit: p.moveLimit),
          const SizedBox(height: 8),
          Text(g.status == GameStatus.won ? 'Solved!  ·  par ${p.par}' : 'Par ${p.par}  ·  ${g.movesLeft} left',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: g.movesLeft <= 2 && g.status == GameStatus.playing ? Palette.danger : Palette.inkSoft)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: BoardView(game: g, onWinAnimationDone: _onWin),
            ),
          ),
          _BottomBar(game: g, onResults: _openResults),
          const SizedBox(height: 16),
        ]);
      },
    );
  }
}

class _MovesPill extends StatelessWidget {
  final int used, limit;
  const _MovesPill({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(color: Palette.ink, borderRadius: BorderRadius.circular(30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('MOVES  ',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1)),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, a) => ScaleTransition(
            scale: Tween(begin: 1.5, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
            child: FadeTransition(opacity: a, child: child),
          ),
          child: Text('$used',
              key: ValueKey(used),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Palette.gold)),
        ),
        Text(' / $limit', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final GameController game;
  final VoidCallback onResults;
  const _BottomBar({required this.game, required this.onResults});

  @override
  Widget build(BuildContext context) {
    final g = game;
    Widget child;
    switch (g.status) {
      case GameStatus.won:
        child = FilledButton.icon(
          key: const ValueKey('won'),
          style: FilledButton.styleFrom(
            backgroundColor: Palette.gold,
            foregroundColor: Palette.ink,
            minimumSize: const Size(220, 56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          onPressed: onResults,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('Share result'),
        );
      case GameStatus.outOfMoves:
        child = Column(key: const ValueKey('out'), mainAxisSize: MainAxisSize.min, children: [
          const Text('Out of moves!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Palette.danger)),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _RoundAction(Icons.undo_rounded, 'Undo', g.undo),
            const SizedBox(width: 18),
            _RoundAction(Icons.refresh_rounded, 'Try again', g.restart, primary: true),
          ]),
        ]);
      case GameStatus.playing:
        child = Row(key: const ValueKey('play'), mainAxisAlignment: MainAxisAlignment.center, children: [
          _RoundAction(Icons.undo_rounded, 'Undo', g.canUndo ? g.undo : null),
          const SizedBox(width: 18),
          _RoundAction(Icons.refresh_rounded, 'Restart', g.history.isNotEmpty ? g.restart : null),
        ]);
    }
    return SizedBox(
      height: 110,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(a), child: c)),
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: primary ? Palette.ink : Colors.white,
          shape: const CircleBorder(side: BorderSide(color: Palette.tubeStroke, width: 2)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
                width: 58, height: 58, child: Icon(icon, size: 28, color: primary ? Colors.white : Palette.ink)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.inkSoft)),
      ]),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) =>
      IconButton(onPressed: onTap, tooltip: tooltip, icon: Icon(icon, size: 28, color: Palette.ink));
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Mixing today\'s colors…',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Palette.inkSoft)),
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
