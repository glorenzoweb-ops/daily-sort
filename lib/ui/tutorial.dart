import 'package:material_ui/material_ui.dart';

import '../game/board.dart';
import '../game/daily.dart';
import '../game/game_controller.dart';
import '../services/analytics.dart';
import '../services/storage.dart';
import 'board_view.dart';
import 'palette.dart';
import 'sheets.dart';

/// A tiny board for the guided first puzzle: two colors, three tubes,
/// solved in three moves.
DailyPuzzle tutorialPuzzle() => DailyPuzzle(
  number: 0,
  day: dayOf(DateTime.now()),
  spec: weekdaySpecs[DateTime.monday]!,
  start: BoardState([
    [0, 1],
    [1, 0],
    [],
  ], 2),
  solution: const [Move(0, 2), Move(1, 0), Move(1, 2)],
  moveLimit: 99,
);

/// The guided first puzzle: learn by doing, in three steps, instead of
/// reading the rules.
class TutorialView extends StatefulWidget {
  final Storage storage;
  final VoidCallback onDone;
  const TutorialView({super.key, required this.storage, required this.onDone});

  @override
  State<TutorialView> createState() => _TutorialViewState();
}

class _TutorialViewState extends State<TutorialView> {
  late final GameController _game = GameController(tutorialPuzzle(), widget.storage, tutorial: true)
    ..hint = const Move(0, 2);
  bool _celebrated = false;

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  (int, String, String) _step() {
    final g = _game;
    if (g.status == GameStatus.won) {
      return (3, 'That\'s it!', 'Every day brings one new puzzle, the same for everyone. Fewer moves, more stars.');
    }
    if (g.history.isEmpty && g.selected == null) {
      return (1, 'Tap the first tube', 'You pick up its top ball.');
    }
    if (g.history.isEmpty) {
      return (2, 'Now tap the empty tube', 'The ball pours in.');
    }
    return (3, 'Sort each color into its own tube', 'A ball only goes onto the same color, or into an empty tube.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _game,
      builder: (context, _) {
        final (step, title, body) = _step();
        final won = _game.status == GameStatus.won;
        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Analytics.send('Tutorial.skipped', {'step': step});
                  widget.onDone();
                },
                child: Text(
                  'Skip',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Palette.inkSoft),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 3; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == step ? 26 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i <= step ? Palette.gold : Palette.line,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Column(
                  key: ValueKey(title),
                  children: [
                    Text(title, textAlign: TextAlign.center, style: Palette.display(size: 28)),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.inkSoft, height: 1.3),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
                child: BoardView(
                  game: _game,
                  onWinAnimationDone: () {
                    if (!_celebrated) setState(() => _celebrated = true);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: AnimatedOpacity(
                opacity: won ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !won,
                  child: BigButton(
                    label: 'Play today\'s puzzle',
                    icon: Icons.play_arrow_rounded,
                    onTap: () {
                      Analytics.send('Tutorial.completed');
                      widget.onDone();
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
