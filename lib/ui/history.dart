import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../services/share.dart';
import '../services/storage.dart';
import 'palette.dart';
import 'sheets.dart';

/// One past daily puzzle, as this device remembers it.
class HistoryDay {
  final int number;
  final DayRecord? record;
  final int hints;
  const HistoryDay(this.number, this.record, this.hints);

  bool get solved => record?.solved ?? false;
  bool get played => record != null && (record!.solved || record!.moves.isNotEmpty || record!.attempts > 1);
}

/// Averages over every solved daily.
class HistorySummary {
  final int solved;
  final int firstTry;
  final int hintFree;
  const HistorySummary(this.solved, this.firstTry, this.hintFree);

  int pct(int n) => solved == 0 ? 0 : (n * 100 / solved).round();
}

HistorySummary summarize(Storage storage, int today) {
  var solved = 0, firstTry = 0, hintFree = 0;
  for (var n = 1; n <= today; n++) {
    final r = storage.day(n);
    if (r == null || !r.solved) continue;
    solved++;
    if (r.attempts == 1) firstTry++;
    if (storage.hintsUsed(n) == 0) hintFree++;
  }
  return HistorySummary(solved, firstTry, hintFree);
}

/// Up to the last five weeks of daily puzzles, Monday to Sunday. Solved days glow
/// gold (brighter for more stars), today has a ring. Tap a day for details.
class HistoryCalendar extends StatefulWidget {
  final Storage storage;
  final int today;
  const HistoryCalendar({super.key, required this.storage, required this.today});

  @override
  State<HistoryCalendar> createState() => _HistoryCalendarState();
}

class _HistoryCalendarState extends State<HistoryCalendar> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final todayDate = dayForNumber(widget.today);
    // Up to five weeks, Monday to Sunday, from the week puzzle #1 came out.
    final firstDate = dayForNumber(1);
    final thisMonday = todayDate.subtract(Duration(days: todayDate.weekday - 1));
    final firstMonday = firstDate.subtract(Duration(days: firstDate.weekday - 1));
    final weeks = (thisMonday.difference(firstMonday).inDays ~/ 7 + 1).clamp(1, 5);
    final start = thisMonday.subtract(Duration(days: 7 * (weeks - 1)));
    final summary = summarize(widget.storage, widget.today);
    const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final endDate = start.add(Duration(days: weeks * 7 - 1));
    final range = start.month == endDate.month
        ? '${mo[start.month - 1]} ${start.year}'
        : '${mo[start.month - 1]} – ${mo[endDate.month - 1]} ${endDate.year}';

    Widget cell(int i) {
      final date = start.add(Duration(days: i));
      final n = puzzleNumberFor(date);
      final future = n > widget.today;
      final before = n < 1;
      final day = HistoryDay(n, before || future ? null : widget.storage.day(n), widget.storage.hintsUsed(n));
      final stars = day.solved ? _stars(day) : 0;
      final isToday = n == widget.today;
      final Color fill;
      if (day.solved) {
        fill = Palette.gold.withValues(alpha: stars == 3 ? 1 : (stars == 2 ? 0.62 : 0.34));
      } else {
        fill = before || future ? Colors.transparent : Palette.panel;
      }
      return GestureDetector(
        onTap: before || future ? null : () => setState(() => _picked = _picked == n ? null : n),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _picked == n
                  ? Palette.ink
                  : (isToday ? Palette.gold : (before || future ? Colors.transparent : Palette.line)),
              width: _picked == n || isToday ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            before ? '' : '${date.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: future
                  ? Palette.inkSoft.withValues(alpha: 0.4)
                  : (day.solved && stars >= 2 ? Palette.navy : Palette.inkSoft),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('History', style: Palette.display(size: 20)),
            const Spacer(),
            Text(
              range,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final d in wd)
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Palette.inkSoft),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var w = 0; w < weeks; w++)
          Row(
            children: [
              for (var d = 0; d < 7; d++) Expanded(child: AspectRatio(aspectRatio: 1, child: cell(w * 7 + d))),
            ],
          ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            _detail(),
            key: ValueKey(_picked),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.ink),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Mini('${summary.pct(summary.firstTry)}%', 'First try'),
            _Mini('${summary.pct(summary.hintFree)}%', 'No hints'),
            const _Mini('', 'Stars', legend: true),
          ],
        ),
      ],
    );
  }

  /// Solves saved before par was kept count as 3 stars.
  int _stars(HistoryDay d) {
    final m = d.record?.solvedMoves;
    final par = d.record?.par;
    if (m == null || par == null) return 3;
    return m <= par ? 3 : (m == par + 1 ? 2 : 1);
  }

  String _detail() {
    final n = _picked;
    if (n == null) return 'Tap a day to see how it went.';
    final r = widget.storage.day(n);
    final label = '#$n · ${dayLabel(dayForNumber(n))}';
    if (r == null || (!r.solved && r.moves.isEmpty && r.attempts <= 1)) return '$label · not played';
    if (!r.solved) return '$label · not solved yet';
    final par = r.par;
    final hints = widget.storage.hintsUsed(n);
    return [
      label,
      '${r.solvedMoves} moves${par == null ? '' : ' (par $par)'}',
      r.attempts == 1 ? '1st try' : '${ordinal(r.attempts)} try',
      if (hints > 0) '💡$hints',
    ].join(' · ');
  }
}

class _Mini extends StatelessWidget {
  final String value, label;
  final bool legend;
  const _Mini(this.value, this.label, {this.legend = false});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (legend)
        SizedBox(
          height: 26,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in [0.34, 0.62, 1.0])
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Palette.gold.withValues(alpha: a),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
            ],
          ),
        )
      else
        Text(value, style: Palette.display(size: 20)),
      Text(
        legend ? '1 · 2 · 3 stars' : label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.inkSoft),
      ),
    ],
  );
}
