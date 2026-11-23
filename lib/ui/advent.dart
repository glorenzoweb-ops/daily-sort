import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../services/premium.dart';
import '../services/storage.dart';
import 'palette.dart';
import 'sheets.dart';
import 'squish.dart';

/// The advent calendar runs in this December, and stays open to replay
/// until Epiphany.
const adventYear = 2026;

/// Door [n] opens on December n (the player's local date).
bool adventDoorOpen(int n, DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  final opens = DateTime(adventYear, 12, n);
  final closes = DateTime(adventYear + 1, 1, 6);
  return !day.isBefore(opens) && !day.isAfter(closes);
}

/// The calendar shows from mid-November until it closes.
bool adventSeason(DateTime now) =>
    !now.isBefore(DateTime(adventYear, 11, 15)) && now.isBefore(DateTime(adventYear + 1, 1, 7));

/// Same puzzle for everyone behind door [n]: an Unwind puzzle (no move
/// limit) from a fixed seed. The daily generator is not touched.
DailyPuzzle adventPuzzle(int n) => practicePuzzle(0xAD7E00 + n * 7919);

/// Door 1 is a free taste. The rest come with the pack or Plus.
bool adventDoorFree(int n) => n == 1;

/// 24 doors, one a day in December. Each opens a cozy puzzle with its own
/// picture.
class AdventSheet extends StatefulWidget {
  final PremiumService premium;
  final Storage storage;
  final ValueChanged<int> onPlay;
  final VoidCallback onPlus;
  final DateTime? now;
  const AdventSheet({
    super.key,
    required this.premium,
    required this.storage,
    required this.onPlay,
    required this.onPlus,
    this.now,
  });

  @override
  State<AdventSheet> createState() => _AdventSheetState();
}

class _AdventSheetState extends State<AdventSheet> {
  bool _busy = false;

  Future<void> _buy() async {
    final premium = widget.premium;
    if (!premium.canPurchase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('The advent calendar is sold in the iPhone app.', style: TextStyle(color: Colors.white)),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    await premium.purchase(adventPack);
    if (mounted) setState(() => _busy = false);
  }

  void _tap(int n, bool open, bool unlocked) {
    if (!open) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Door $n opens on December $n.', style: const TextStyle(color: Colors.white)),
        ),
      );
      return;
    }
    if (!unlocked) {
      _buy();
      return;
    }
    widget.onPlay(n);
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final owned = widget.premium.hasAdvent;
    final solved = widget.storage.adventSolved;
    final note = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.inkSoft);
    final started = adventDoorOpen(1, now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle('Advent calendar'),
        Text(
          started
              ? '${solved.length} of 24 opened · a new door every day until the 24th'
              : 'Starts December 1. A door a day, each with a cozy puzzle and its own picture.',
          textAlign: TextAlign.center,
          style: note.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 6,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (var n = 1; n <= 24; n++)
              _Door(
                n: n,
                open: adventDoorOpen(n, now),
                unlocked: owned || adventDoorFree(n),
                solved: solved.contains(n),
                onTap: () => _tap(n, adventDoorOpen(n, now), owned || adventDoorFree(n)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (!owned) ...[
          BigButton(
            label: _busy ? 'One moment…' : 'Unlock all 24 · ${widget.premium.priceOf(adventPack)}',
            onTap: _buy,
          ),
          TextButton(
            onPressed: widget.onPlus,
            child: Text(
              'Included with Daily Sort+',
              style: note.copyWith(fontWeight: FontWeight.w800, color: Palette.ink),
            ),
          ),
        ] else
          Text('All 24 doors are yours. Merry sorting! 🎄', textAlign: TextAlign.center, style: note),
      ],
    );
  }
}

class _Door extends StatelessWidget {
  final int n;
  final bool open, unlocked, solved;
  final VoidCallback onTap;
  const _Door({required this.n, required this.open, required this.unlocked, required this.solved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final playable = open && unlocked;
    final Color fill = solved
        ? Palette.gold
        : (playable ? const Color(0xFFC8553D) : (open ? const Color(0xFF8E4A3A) : Palette.panel));
    final label = solved
        ? 'Door $n, solved'
        : (!open ? 'Door $n, opens December $n' : (unlocked ? 'Door $n, open' : 'Door $n, locked'));
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Squish(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: open ? const Color(0x33FFFFFF) : Palette.line, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$n',
                  style: Palette.display(
                    size: 16,
                    color: solved ? Palette.navy : (open ? Colors.white : Palette.inkSoft),
                  ),
                ),
                if (solved || (open && !unlocked))
                  Text(solved ? '✓' : '🔒', style: TextStyle(fontSize: 10, color: Palette.navy)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
