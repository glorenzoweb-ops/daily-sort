import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../game/game_controller.dart';
import '../services/background.dart';
import '../services/backup.dart';
import '../services/feedback.dart';
import '../services/premium.dart';
import '../services/sound.dart';
import '../services/sound/ambience.dart';
import '../services/storage.dart';
import 'board_view.dart';
import 'confetti.dart';
import 'motion.dart';
import 'perf.dart';
import 'palette.dart';
import 'rolling_number.dart';
import 'sky.dart';
import 'squish.dart';
import '../services/friends.dart';
import '../services/link.dart';
import '../services/puzzles.dart';
import '../services/reactions.dart';
import '../services/share.dart';
import 'advent.dart';
import 'appearance.dart';
import 'archive.dart';
import 'sheets.dart';
import 'shop.dart';
import 'social.dart';
import 'streak.dart';
import 'warmup.dart';

class GameScreen extends StatefulWidget {
  final Storage storage;
  final PremiumService premium;
  final Appearance appearance;

  /// A friend's result from the link that opened the app (`?r=...`).
  final String? incomingResult;

  /// A backup code was restored: the app starts over with its data.
  final VoidCallback? onRestored;
  const GameScreen({
    super.key,
    required this.storage,
    required this.premium,
    required this.appearance,
    this.incomingResult,
    this.onRestored,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  // Both modes stay alive, so switching never loses your place.
  GameController? _daily, _unwind;

  /// A past puzzle opened from the archive. It sits in the Daily slot until
  /// you go back to today.
  GameController? _archive;
  bool _inUnwind = false;
  late final Puzzles _puzzles = Puzzles(widget.storage);
  late final Friends _friends = Friends(widget.storage);
  late final Reactions _reactions = Reactions(widget.storage);
  Reaction? _incomingReaction;
  final _confetti = ConfettiController();
  GameController? get _game => _inUnwind ? _unwind : (_archive ?? _daily);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDaily();
    // Compile the graphics effects once the first screen is up, before the
    // first tube completes.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Future<void>.delayed(const Duration(milliseconds: 300), warmUpEffects),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _daily?.dispose();
    _unwind?.dispose();
    _archive?.dispose();
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
    // Missed a day? A trip across time zones is forgiven, and banked streak
    // freezes cover the rest.
    final stats = widget.storage.stats;
    final travel = stats.applyTravelGrace(puzzle.number, DateTime.now().timeZoneOffset.inMinutes);
    final used = stats.applyFreezes(puzzle.number);
    final lost = used == 0 && stats.streak == 0 && widget.storage.stats.streak > 0;
    if (travel || used > 0 || lost) await widget.storage.saveStats(stats);
    if (used > 0) {
      _toastFreezeUsed(used, stats.streak);
    } else if (travel) {
      _toastTravel(stats.streak);
    }
    setState(() {
      _daily?.dispose();
      _daily = GameController(puzzle, widget.storage);
    });
    // Get an Unwind puzzle ready while the player looks at today's board.
    Future<void>.delayed(const Duration(milliseconds: 1500), _puzzles.prefetchUnwind);
    final fromFriend = await _takeIncoming(puzzle.number);
    if (!widget.storage.seenHowTo) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      widget.storage.setSeenHowTo();
      await showCozySheet(context, const HowToSheet());
    }
    if (fromFriend != null) _toastFriend(fromFriend, puzzle.number);
    final x = _incomingReaction;
    if (x != null) {
      _incomingReaction = null;
      _toastReaction(x);
    }
  }

  bool _tookIncoming = false;

  /// Saves the friend's result from the link that opened the app.
  Future<FriendResult?> _takeIncoming(int today) async {
    if (_tookIncoming) return null;
    _tookIncoming = true;
    final r = FriendResult.decode(widget.incomingResult);
    final x = Reaction.decode(incomingReactionParam());
    clearIncomingParam();
    if (x != null && x.number <= today && await _reactions.receive(x, today: today)) _incomingReaction = x;
    if (r == null || r.number > today) return null;
    final added = await _friends.add(r, today: today);
    return added ? r : null;
  }

  void _toastFriend(FriendResult r, int today) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isToday = r.number == today;
      final mine = widget.storage.day(r.number);
      final String text;
      if (!isToday) {
        text = '${r.name} solved #${r.number} in ${r.moves} moves. Find it in Past puzzles.';
      } else if (mine?.solved ?? false) {
        final m = mine!.solvedMoves!;
        text = m < r.moves
            ? '${r.name} took ${r.moves} moves. You beat them with $m!'
            : (m == r.moves
                  ? '${r.name} tied you at ${r.moves} moves!'
                  : '${r.name} beat you: ${r.moves} moves vs your $m.');
      } else {
        text = '${r.name} solved today\'s puzzle in ${r.moves} moves. Your turn!';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Palette.navy,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Row(
            children: [
              Avatar(r.name, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                ),
              ),
            ],
          ),
          action: SnackBarAction(label: 'Board', textColor: Palette.gold, onPressed: _openFriends),
          persist: false,
        ),
      );
    });
  }

  void _toastReaction(Reaction x) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mine = widget.storage.day(x.number);
      final what = x.number == _today ? 'today\'s solve' : 'your #${x.number}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Palette.navy,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Row(
            children: [
              Text(x.symbol, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mine?.solved ?? false
                      ? '${x.from} sent ${x.symbol} for $what!'
                      : '${x.from} sent you ${x.symbol}. Solve today\'s puzzle and send yours back!',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                ),
              ),
            ],
          ),
          action: SnackBarAction(label: 'Board', textColor: Palette.gold, onPressed: _openFriends),
          persist: false,
        ),
      );
    });
  }

  /// Shares a reaction to a friend's result today (with your own result
  /// when you've solved, so you land on their board too).
  Future<void> _react(BoardEntry friend, int emoji) async {
    final name = await ensureName(context, widget.storage);
    final d = _daily;
    final today = _today;
    String? mine;
    if (d != null && d.status == GameStatus.won) {
      mine = FriendResult(
        name: name.isEmpty ? 'A friend' : name,
        number: d.puzzle.number,
        moves: d.movesUsed,
        attempts: d.attempts,
        streak: widget.storage.stats.currentStreak(d.puzzle.number),
      ).encode();
    }
    final text = buildReactionText(
      to: friend.name,
      number: today,
      toMoves: friend.moves,
      emoji: emoji,
      from: name.isEmpty ? 'A friend' : name,
      myResult: mine,
    );
    final r = await shareResult(text);
    if (r == ShareOutcome.failed) return;
    await _reactions.markSent(friend.name, today, emoji, today: today);
    if (r == ShareOutcome.copied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied. Paste it to ${friend.name}!'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  int get _today => _daily?.puzzle.number ?? puzzleNumberFor(DateTime.now());

  BoardEntry? _myEntry() {
    final d = _daily;
    if (d == null || d.status != GameStatus.won) return null;
    final rec = widget.storage.day(d.puzzle.number);
    return BoardEntry(
      widget.storage.myName,
      rec?.solvedMoves ?? d.movesUsed,
      rec?.attempts ?? d.attempts,
      widget.storage.stats.currentStreak(d.puzzle.number),
      isMe: true,
    );
  }

  /// Shares today's result (with your link) or, before solving, an invite.
  Future<void> _shareToFriends() async {
    final d = _daily;
    if (d == null) return;
    final plain = plainShareOn(context, widget.storage);
    final name = await ensureName(context, widget.storage);
    final String text;
    if (d.status == GameStatus.won) {
      text = buildShareText(
        puzzle: d.puzzle,
        moves: d.movesUsed,
        stars: d.stars,
        attempts: d.attempts,
        moveColors: d.moveColors,
        streak: widget.storage.stats.currentStreak(d.puzzle.number),
        hints: widget.storage.hintsUsed(d.puzzle.number),
        plain: plain,
        link: resultLink(
          FriendResult(
            name: name.isEmpty ? 'A friend' : name,
            number: d.puzzle.number,
            moves: d.movesUsed,
            attempts: d.attempts,
            streak: widget.storage.stats.currentStreak(d.puzzle.number),
          ).encode(),
        ),
      );
    } else {
      text =
          'I\'m playing Daily Sort: one cozy color puzzle a day, same for everyone. Play today\'s with me: $shareUrl';
    }
    final r = await shareResult(text);
    if (r == ShareOutcome.copied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied. Paste it in your group chat!'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _openFriends() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    showCozySheet(
      context,
      FriendsSheet(
        storage: widget.storage,
        friends: _friends,
        today: _today,
        me: _myEntry(),
        onInvite: _shareToFriends,
        reactions: _reactions,
        onReact: _react,
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openArchive() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    showCozySheet(
      context,
      ArchiveSheet(
        today: _today,
        storage: widget.storage,
        premium: widget.premium,
        onPick: (n) {
          Navigator.of(context).pop();
          _playArchive(n);
        },
        onUnlock: _openPaywall,
      ),
    );
  }

  Future<void> _openPaywall({bool reopenArchive = true}) async {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    final ok = await showCozySheet<bool>(context, PaywallSheet(premium: widget.premium, storage: widget.storage));
    if (ok == true && mounted) {
      setState(() {});
      if (reopenArchive) _openArchive();
    }
  }

  Future<void> _playArchive(int number) async {
    if (number == _today) {
      _setMode(false);
      return;
    }
    setState(() {
      _inUnwind = false;
      _archive?.dispose();
      _archive = null;
      _loadingArchive = true;
    });
    final puzzle = await _puzzles.archive(number);
    if (!mounted) return;
    setState(() {
      _loadingArchive = false;
      _archive = GameController(puzzle, widget.storage, archive: true);
    });
  }

  bool _loadingArchive = false;

  void _backToToday() {
    setState(() {
      _archive?.dispose();
      _archive = null;
    });
  }

  /// The advent door being played in Unwind, if any.
  int? _adventDoor;

  Future<void> _newUnwind() async {
    final puzzle = await _puzzles.unwind();
    if (!mounted) return;
    setState(() {
      _unwind?.dispose();
      _unwind = GameController(puzzle, widget.storage);
      _adventDoor = null;
    });
    Future<void>.delayed(const Duration(milliseconds: 1500), _puzzles.prefetchUnwind);
  }

  /// Daily ⇄ Unwind. Each keeps its board exactly as you left it.
  void _setMode(bool unwind) {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    if (!unwind && !_inUnwind && _archive != null) _backToToday();
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

  void _openShop() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    showCozySheet(
      context,
      ShopSheet(
        premium: widget.premium,
        appearance: widget.appearance,
        onPlus: () => _openPaywall(reopenArchive: false),
        onAdvent: _openAdvent,
      ),
    );
  }

  void _openAdvent() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    showCozySheet(
      context,
      AdventSheet(
        premium: widget.premium,
        storage: widget.storage,
        onPlus: () => _openPaywall(reopenArchive: false),
        onPlay: (n) {
          Navigator.of(context).pop();
          _playAdvent(n);
        },
      ),
    );
  }

  /// Plays advent door [n] in Unwind: no move limit.
  Future<void> _playAdvent(int n) async {
    final puzzle = await runInBackground(() => adventPuzzle(n));
    if (!mounted) return;
    setState(() {
      _inUnwind = true;
      _unwind?.dispose();
      _unwind = GameController(puzzle, widget.storage);
      _adventDoor = n;
    });
  }

  void _openSettings() {
    showCozySheet(
      context,
      SettingsSheet(
        storage: widget.storage,
        appearance: widget.appearance,
        onChanged: () {
          if (mounted) setState(() {});
        },
        onRestored: widget.onRestored,
        onShop: _openShop,
      ),
    );
  }

  void _onWin() {
    if (!Motion.reduced) _confetti.burst();
    final door = _adventDoor;
    if (door != null && _inUnwind) widget.storage.addAdventSolved(door);
    // A calm moment: prepare what comes next.
    if (_inUnwind) {
      _puzzles.prefetchUnwind();
    } else {
      Future<void>.delayed(const Duration(seconds: 2), () => _puzzles.prefetchAhead(DateTime.now()));
    }
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      if (!mounted) return;
      final g = _game;
      if (g != null &&
          !g.puzzle.isPractice &&
          !g.archive &&
          streakMilestones.contains(g.streakAfter) &&
          g.streakAfter > g.streakBefore) {
        if (!Motion.reduced) _confetti.burst();
        await showStreakMilestone(context, g.streakAfter);
        if (!mounted) return;
      }
      _openResults();
    });
  }

  void _toastTravel(int streak) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Palette.navy,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Row(
            children: [
              const Icon(Icons.flight_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'New time zone? You lost a day on the clock, so your $streak-day streak is safe.',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _toastFreezeUsed(int used, int streak) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2F6E95),
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Row(
            children: [
              const Icon(Icons.ac_unit_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  used == 1
                      ? 'A streak freeze saved your $streak-day streak!'
                      : '$used streak freezes saved your $streak-day streak!',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// Free hints are counted on daily puzzles; Unwind and Plus are unlimited.
  bool _hintsMetered(GameController g) => !g.puzzle.isPractice && !widget.premium.isUnlocked(PremiumFeature.hints);

  int _freeHintsLeft(GameController g) =>
      (freeHintsPerDay - widget.storage.hintsUsed(g.puzzle.number)).clamp(0, freeHintsPerDay);

  String _hintLabel(GameController g) {
    if (!_hintsMetered(g)) return 'Hint';
    return _freeHintsLeft(g) > 0 ? 'Free hint' : 'More hints';
  }

  Future<void> _useHint() async {
    final g = _game;
    if (g == null || g.status != GameStatus.playing) return;
    if (_hintsMetered(g) && _freeHintsLeft(g) == 0) {
      _openPaywall(reopenArchive: false);
      return;
    }
    if (!g.findHint()) return;
    if (!g.puzzle.isPractice) await widget.storage.addHint(g.puzzle.number);
    if (!mounted) return;
    setState(() {});
    if (g.hintUndo > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Palette.navy,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          content: Text(
            g.hintUndo == 1
                ? 'Undo 1 move first. From here it can\'t be sorted in the moves left.'
                : 'Undo ${g.hintUndo} moves first. From here it can\'t be sorted in the moves left.',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white),
          ),
        ),
      );
    }
  }

  void _openStreak() {
    final d = _daily;
    if (d == null) return;
    showCozySheet(
      context,
      StreakSheet(
        stats: widget.storage.stats,
        today: d.puzzle.number,
        solvedToday: d.status == GameStatus.won,
        onUnwind: () => _setMode(true),
      ),
    );
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
        friends: _friends.forDay(g.puzzle.number),
        me: g.archive ? null : _myEntry(),
        onFriends: _openFriends,
        onShareToFriends: _shareToFriends,
        onArchive: _openArchive,
        onPlus: _openPaywall,
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
                child: g == null || (_loadingArchive && !_inUnwind)
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
        // Read saved data once per rebuild (it's JSON under the hood).
        final friendsToday = p.isPractice || g.archive ? const <FriendResult>[] : _friends.forDay(p.number);
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
                      _IconBtn(Icons.tune_rounded, 'Settings', _openSettings),
                      const Spacer(),
                      _IconBtn(Icons.people_alt_rounded, 'Friends', _openFriends),
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
            SecretTaps(
              child: Text(
                _adventDoor != null && _inUnwind ? 'DOOR $_adventDoor' : (p.isPractice ? 'UNWIND' : 'DAILY SORT'),
                style: Palette.display(size: 38, spacing: 2).copyWith(
                  shadows: const [
                    Shadow(color: Color(0xFFFFC23F), offset: Offset(0, 3)),
                    Shadow(color: Color(0x33000000), offset: Offset(0, 5), blurRadius: 6),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              p.isPractice
                  ? (_adventDoor != null
                        ? 'Advent calendar · December $_adventDoor'
                        : 'No limits. Just sort and breathe.')
                  : (g.archive
                        ? '#${p.number}  ·  ${dayLabel(p.day)}  ·  from the archive'
                        : '#${p.number}  ·  ${dayLabel(p.day)}  ·  ${difficultyLabel(p.difficulty)}'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.inkSoft),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MovesPill(used: g.movesUsed, limit: p.isPractice ? null : p.moveLimit),
                if (g.archive) ...[
                  const SizedBox(width: 10),
                  _TodayPill(onTap: () => _setMode(false)),
                ] else if (!p.isPractice) ...[
                  const SizedBox(width: 10),
                  Builder(
                    builder: (context) {
                      final stats = widget.storage.stats;
                      return StreakFlame(
                        streak: stats.currentStreak(p.number),
                        litToday: g.status == GameStatus.won,
                        freezes: stats.freezes,
                        onTap: _openStreak,
                      );
                    },
                  ),
                ],
              ],
            ),
            if (p.twist != Twist.classic) ...[const SizedBox(height: 10), TwistChip(puzzle: p)],
            if (!p.isPractice && !g.archive && adventSeason(DateTime.now())) ...[
              const SizedBox(height: 8),
              _AdventChip(onTap: _openAdvent),
            ],
            const SizedBox(height: 8),
            Text(
              switch (g.status) {
                GameStatus.won => 'Solved!  ·  par ${p.par}',
                // Players who run out wonder if it was even possible.
                GameStatus.outOfMoves => 'Proven solvable in ${p.par}  ·  try again?',
                _ => p.isPractice ? 'Par ${p.par}  ·  take your time' : 'Par ${p.par}  ·  ${g.movesLeft} left',
              },
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: !p.isPractice && g.movesLeft <= 2 && g.status == GameStatus.playing
                    ? Palette.danger
                    : Palette.inkSoft,
              ),
            ),
            if (friendsToday.isNotEmpty) ...[
              const SizedBox(height: 8),
              FriendsChip(
                today: friendsToday,
                myMoves: g.status == GameStatus.won ? g.movesUsed : null,
                onTap: _openFriends,
              ),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: BoardView(
                  // A new look means new ball and glass images.
                  key: ValueKey((g, Palette.dark, Palette.ballsKey)),
                  game: g,
                  onWinAnimationDone: _onWin,
                  breathe: p.isPractice,
                ),
              ),
            ),
            _BottomBar(
              game: g,
              onResults: _openResults,
              onNext: _startPractice,
              onHint: _useHint,
              hintLabel: _hintLabel(g),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

/// "Back to today" while replaying an archive puzzle.
/// A small door to the advent calendar, in its season.
class _AdventChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AdventChip({required this.onTap});

  @override
  Widget build(BuildContext context) => Squish(
    child: Material(
      color: Palette.card,
      shape: StadiumBorder(side: BorderSide(color: Palette.line, width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            '🎄  Advent calendar',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.ink),
          ),
        ),
      ),
    ),
  );
}

class _TodayPill extends StatelessWidget {
  final VoidCallback onTap;
  const _TodayPill({required this.onTap});

  @override
  Widget build(BuildContext context) => Squish(
    child: Material(
      color: Palette.card,
      shape: StadiumBorder(side: BorderSide(color: Palette.tubeStroke, width: 2)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.today_rounded, size: 20, color: Palette.ink),
              SizedBox(width: 6),
              Text(
                'Today',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Palette.ink),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MovesPill extends StatelessWidget {
  final int used;
  final int? limit; // null in Unwind: no limit
  const _MovesPill({required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: limit == null ? '$used moves' : '$used of $limit moves used',
      excludeSemantics: true,
      child: _pill(),
    );
  }

  Widget _pill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF34344F), Palette.navy],
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
          RollingNumber(
            used,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Palette.gold),
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
  final VoidCallback onHint;
  final String hintLabel;
  const _BottomBar({
    required this.game,
    required this.onResults,
    required this.onNext,
    required this.onHint,
    required this.hintLabel,
  });

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
                  backgroundColor: Palette.card,
                  foregroundColor: Palette.ink,
                  minimumSize: const Size(120, 56),
                  side: BorderSide(color: Palette.tubeStroke, width: 2),
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
            _RoundAction(
              hintLabel == 'More hints' && g.hint == null && g.hintUndo == 0
                  ? Icons.lock_rounded
                  : Icons.lightbulb_rounded,
              hintLabel,
              onHint,
              glow: g.hint != null || g.hintUndo > 0,
            ),
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

  /// Lit up in gold (a hint is showing).
  final bool glow;
  const _RoundAction(this.icon, this.label, this.onTap, {this.primary = false, this.glow = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // Faded with colors rather than an Opacity layer, which would cost an
    // offscreen pass on every frame.
    final ink = enabled ? Palette.ink : Palette.ink.withValues(alpha: 0.35);
    final soft = enabled ? Palette.inkSoft : Palette.inkSoft.withValues(alpha: 0.45);
    // One button for screen readers: the circle and its label together.
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: _body(ink, soft, enabled),
    );
  }

  Widget _body(Color ink, Color soft, bool enabled) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Squish(
          child: Material(
            elevation: enabled ? 3 : 0,
            shadowColor: const Color(0x66241A10),
            color: primary ? ink : (glow ? Palette.gold : Palette.card),
            shape: CircleBorder(
              side: BorderSide(
                color: enabled ? Palette.tubeStroke : Palette.tubeStroke.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 58,
                height: 58,
                child: Icon(icon, size: 28, color: primary ? Palette.onInk : (glow ? Palette.navy : ink)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: soft),
        ),
      ],
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Palette.inkSoft),
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
    const segW = 84.0, h = 40.0;
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
                Icon(icon, size: 17, color: on ? (unwind ? Colors.white : Palette.onInk) : Palette.ink),
                const SizedBox(width: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: on ? (unwind ? Colors.white : Palette.onInk) : Palette.ink,
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
          color: Palette.card.withValues(alpha: 0.85),
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
        color: Palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
      ),
      child: Text(
        '$icon  $text',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.ink),
      ),
    );
  }
}

String colorName(int c) => const ['red', 'yellow', 'green', 'blue', 'purple', 'orange'][c % 6];

/// Look (light or dark, colorblind mode) and sound (soundscape, music, notes).
class SettingsSheet extends StatefulWidget {
  final Storage storage;
  final Appearance appearance;
  final VoidCallback onChanged;

  /// A backup code was restored.
  final VoidCallback? onRestored;

  /// Opens ball themes and the other extras.
  final VoidCallback? onShop;
  const SettingsSheet({
    super.key,
    required this.storage,
    required this.appearance,
    required this.onChanged,
    this.onRestored,
    this.onShop,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  void _pick(Ambience a) {
    Sounds.setAmbience(a);
    widget.storage.setAmbience(a.name);
    setState(() {});
    widget.onChanged();
  }

  TextStyle get _title => TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.ink);
  TextStyle get _note => TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.inkSoft);

  Widget _switch(String title, String? subtitle, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    title: Text(title, style: _title),
    subtitle: subtitle == null ? null : Text(subtitle, style: _note),
    value: value,
    activeThumbColor: Palette.gold,
    onChanged: (v) {
      onChanged(v);
      setState(() {});
      widget.onChanged();
    },
  );

  /// A volume slider, 0..1.
  Widget _volume(IconData icon, String label, double value, ValueChanged<double> onChanged, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: enabled ? Palette.ink : Palette.inkSoft.withValues(alpha: 0.5)),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: _title.copyWith(
                fontSize: 14,
                color: enabled ? Palette.ink : Palette.inkSoft.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              activeColor: Palette.gold,
              inactiveColor: Palette.line,
              semanticFormatterCallback: (v) => '$label ${(v * 100).round()}%',
              onChanged: enabled
                  ? (v) {
                      onChanged(v);
                      setState(() {});
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, textAlign: TextAlign.center, style: Palette.display(size: 22)),
  );

  Future<void> _saveBackup() async {
    final code = Backup.of(widget.storage).encode();
    final r = await shareResult(backupMessage(code));
    if (!mounted) return;
    if (r == ShareOutcome.copied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Backup code copied. Keep it in your notes, or send it to your new phone.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RestoreDialog(storage: widget.storage),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pop();
    widget.onRestored?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Settings', textAlign: TextAlign.center, style: Palette.display()),
        const SizedBox(height: 16),
        _ThemePicker(
          value: widget.appearance.choice,
          onChanged: (c) {
            widget.appearance.setChoice(c);
            setState(() {});
          },
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text('Colorblind mode', style: _title),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                for (var i = 0; i < 6; i++) Padding(padding: const EdgeInsets.only(right: 6), child: _BallChip(i)),
              ],
            ),
          ),
          value: widget.appearance.colorblind,
          activeThumbColor: Palette.gold,
          onChanged: (v) {
            widget.appearance.setColorblind(v);
            setState(() {});
          },
        ),
        Text('Easier-to-tell colors, and a shape on every ball.', style: _note),
        if (widget.onShop != null) ...[
          const SizedBox(height: 10),
          SmallButton(label: 'Ball themes and extras', icon: Icons.palette_rounded, onTap: widget.onShop!),
        ],
        Divider(height: 32, color: Palette.line),
        _heading('Sound'),
        Text(
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
        _switch('Calm music', 'A soft pad and a wandering kalimba, never the same twice', Sounds.music, (v) {
          Sounds.setMusic(v);
          widget.storage.setMusic(v);
        }),
        const SizedBox(height: 8),
        _volume(Icons.music_note_rounded, 'Pours', Sounds.effectsLevel, (v) {
          Sounds.setEffectsLevel(v);
          widget.storage.setVolume('effects', v);
          widget.storage.setSound(v > 0);
        }),
        _volume(Icons.waves_rounded, 'Soundscape', Sounds.ambienceLevel, (v) {
          Sounds.setAmbienceLevel(v);
          widget.storage.setVolume('ambience', v);
        }, enabled: Sounds.ambience != Ambience.off),
        _volume(Icons.piano_rounded, 'Music', Sounds.musicLevel, (v) {
          Sounds.setMusicLevel(v);
          widget.storage.setVolume('music', v);
        }, enabled: Sounds.music),
        Text(
          'On iPhone, turn off the silent switch to hear sound.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.inkSoft),
        ),
        Divider(height: 32, color: Palette.line),
        _heading('Comfort'),
        _switch('Vibration', 'A soft tap when you pick and pour', Haptics.enabled, (v) {
          Haptics.enabled = v;
          widget.storage.setHaptics(v);
          if (v) Haptics.select();
        }),
        _switch(
          'Reduce motion',
          'No confetti, shaking or bouncing, and a still sky',
          widget.appearance.reduceMotion,
          widget.appearance.setReduceMotion,
        ),
        _switch(
          'Share results as words',
          'No emoji squares, so screen readers read it nicely',
          plainShareOn(context, widget.storage),
          widget.storage.setPlainShare,
        ),
        Divider(height: 32, color: Palette.line),
        _heading('New phone?'),
        Text(
          'Save a backup code to move your streak, stats and history to another phone or browser. Paste it there with Restore.',
          textAlign: TextAlign.center,
          style: _note.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SmallButton(label: 'Save code', icon: Icons.save_alt_rounded, onTap: _saveBackup),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SmallButton(label: 'Restore', icon: Icons.restore_rounded, onTap: _restore),
            ),
          ],
        ),
      ],
    );
  }
}

/// Paste a backup code, see what's in it, and restore it.
class _RestoreDialog extends StatefulWidget {
  final Storage storage;
  const _RestoreDialog({required this.storage});

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _text = TextEditingController();
  Backup? _backup;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed(String v) => setState(() => _backup = Backup.parse(v));

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final v = data?.text ?? '';
    _text.text = v;
    _changed(v);
  }

  Future<void> _go() async {
    final b = _backup;
    if (b == null) return;
    setState(() => _busy = true);
    await b.restoreTo(widget.storage);
    if (mounted) Navigator.of(context).pop(true);
  }

  String _summary(Stats s) {
    final days = s.streak == 1 ? '1-day' : '${s.streak}-day';
    return '${s.solved} solved · $days streak · best ${s.maxStreak}';
  }

  @override
  Widget build(BuildContext context) {
    final b = _backup;
    final here = widget.storage.stats;
    final style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.ink);
    return AlertDialog(
      backgroundColor: Palette.card,
      title: Text('Restore from a code', style: Palette.display(size: 22)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            onChanged: _changed,
            maxLines: 3,
            style: TextStyle(fontSize: 13, color: Palette.ink),
            decoration: InputDecoration(
              hintText: 'Paste your backup code (it starts with DS1-)',
              hintStyle: TextStyle(color: Palette.inkSoft),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: Icon(Icons.content_paste_rounded, color: Palette.ink),
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (b != null) ...[
            Text('In the code: ${_summary(b.stats)}', style: style),
            const SizedBox(height: 4),
            Text('On this device: ${_summary(here)}', style: style.copyWith(color: Palette.inkSoft)),
            const SizedBox(height: 8),
            Text(
              'Restoring replaces the progress and settings on this device.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.inkSoft),
            ),
          ] else if (_text.text.trim().isNotEmpty)
            const Text(
              "That doesn't look like a backup code. Copy the whole code and try again.",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.danger),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: Palette.inkSoft, fontWeight: FontWeight.w800),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Palette.gold, foregroundColor: Palette.navy),
          onPressed: b == null || _busy ? null : _go,
          child: const Text('Restore', style: TextStyle(fontWeight: FontWeight.w900)),
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
      color: selected ? Palette.picked : Palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? Palette.gold : Palette.line, width: 2),
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
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// Auto / Light / Dark.
class _ThemePicker extends StatelessWidget {
  final ThemeChoice value;
  final ValueChanged<ThemeChoice> onChanged;
  const _ThemePicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(ThemeChoice c, IconData icon, String label) {
      final on = c == value;
      return Expanded(
        child: Squish(
          child: Material(
            color: on ? Palette.picked : Palette.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: on ? Palette.gold : Palette.line, width: 2),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChanged(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    Icon(icon, color: Palette.ink, size: 22),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg(ThemeChoice.auto, Icons.brightness_auto_rounded, 'Auto'),
        const SizedBox(width: 8),
        seg(ThemeChoice.light, Icons.wb_sunny_rounded, 'Light'),
        const SizedBox(width: 8),
        seg(ThemeChoice.dark, Icons.dark_mode_rounded, 'Dark'),
      ],
    );
  }
}

/// A small ball in the current colors (with its shape in colorblind mode).
class _BallChip extends StatelessWidget {
  final int color;
  const _BallChip(this.color);

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(22, 22), painter: _BallChipPainter(color));
}

class _BallChipPainter extends CustomPainter {
  final int color;
  final bool shape;
  final String key;
  _BallChipPainter(this.color) : shape = Palette.colorblind, key = Palette.ballsKey;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, size.width / 2, Paint()..color = Palette.balls[color]);
    if (shape) {
      paintBallShape(
        canvas,
        c,
        size.width * 0.42,
        Palette.shapes[color],
        Colors.white,
        Palette.navy.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BallChipPainter old) => old.color != color || old.shape != shape || old.key != key;
}
