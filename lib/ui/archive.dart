import 'package:material_ui/material_ui.dart';

import '../game/daily.dart';
import '../services/premium.dart';
import '../services/storage.dart';
import 'palette.dart';
import 'picture.dart';
import 'sheets.dart';
import 'squish.dart';

/// Every past daily puzzle, each with its picture: colored if you solved it,
/// a pencil sketch if not. The last few days are free; the rest is Daily
/// Sort+.
class ArchiveSheet extends StatelessWidget {
  final int today;
  final Storage storage;
  final PremiumService premium;
  final ValueChanged<int> onPick;
  final VoidCallback onUnlock;

  const ArchiveSheet({
    super.key,
    required this.today,
    required this.storage,
    required this.premium,
    required this.onPick,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final past = [for (var n = today - 1; n >= 1; n--) n];
    final colored =
        past.where((n) => storage.day(n)?.solved ?? false).length + (storage.day(today)?.solved ?? false ? 1 : 0);
    // Puzzles you already played stay open: they're yours.
    bool isLocked(int n) => archiveLocked(n, today, premium) && storage.day(n) == null;
    final locked = past.where(isLocked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle('Past puzzles'),
        const SizedBox(height: 6),
        Text(
          'Pictures colored: $colored of $today',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.inkSoft),
        ),
        const SizedBox(height: 14),
        if (past.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Palette.background, borderRadius: BorderRadius.circular(20)),
            child: Text(
              'The archive starts tomorrow. Every day\'s puzzle and picture will wait for you here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w700, color: Palette.ink),
            ),
          )
        else
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.18,
            children: [
              for (final n in past)
                _Tile(
                  number: n,
                  record: storage.day(n),
                  locked: isLocked(n),
                  onTap: () => isLocked(n) ? onUnlock() : onPick(n),
                ),
            ],
          ),
        if (locked > 0 || (!premium.isPremium && past.isNotEmpty)) ...[
          const SizedBox(height: 16),
          PlusBanner(
            text: locked > 0
                ? 'Unlock $locked more ${locked == 1 ? 'puzzle' : 'puzzles'} and every picture with Daily Sort+'
                : 'The last $freeArchiveDays days are free. Daily Sort+ keeps every puzzle forever.',
            onTap: onUnlock,
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final int number;
  final DayRecord? record;
  final bool locked;
  final VoidCallback onTap;
  const _Tile({required this.number, required this.record, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final day = dayForNumber(number);
    final solved = record?.solved ?? false;
    final started = !solved && (record?.moves.isNotEmpty ?? false);
    final scene = sceneForNumber(number);
    final status = solved
        ? '✓ ${record!.solvedMoves} moves'
        : (started ? 'In progress' : (locked ? 'Daily Sort+' : 'Not played'));
    return Squish(
      child: Material(
        color: Palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: solved ? Palette.gold : Palette.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Opacity(
                          opacity: locked ? 0.55 : 1,
                          child: CustomPaint(
                            painter: ScenePainter(scene, solved ? const [1.0, 1, 1, 1, 1] : const [0.0, 0, 0, 0, 0]),
                          ),
                        ),
                      ),
                      if (locked)
                        Center(
                          child: CircleAvatar(
                            radius: 17,
                            backgroundColor: Palette.ink,
                            child: Icon(Icons.lock_rounded, size: 18, color: Palette.onInk),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('#$number', style: Palette.display(size: 16)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dayLabel(day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.inkSoft),
                      ),
                    ),
                  ],
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: solved ? const Color(0xFF1F9A7A) : Palette.inkSoft,
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

/// A tappable gold "Daily Sort+" strip.
class PlusBanner extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const PlusBanner({super.key, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => Squish(
    child: Material(
      color: Palette.picked,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w800, color: Palette.ink),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Palette.ink),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The Daily Sort+ paywall. Today's puzzle is always free; the subscription
/// is for the archive and the extras.
class PaywallSheet extends StatefulWidget {
  final PremiumService premium;
  final Storage storage;
  const PaywallSheet({super.key, required this.premium, required this.storage});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  PremiumPlan _plan = yearlyPlan;
  bool _busy = false;
  bool _waitlisted = false;

  Future<void> _buy() async {
    if (_busy) return;
    if (!widget.premium.canPurchase) {
      await widget.storage.addPremiumInterest();
      setState(() => _waitlisted = true);
      return;
    }
    setState(() => _busy = true);
    final ok = await widget.premium.purchase(_plan);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    Widget perk(String emoji, String title, String sub) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Palette.background, borderRadius: BorderRadius.circular(14)),
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Palette.ink),
                ),
                Text(
                  sub,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 92,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final (i, n) in const [(0, 3), (1, 5), (2, 6)])
                Transform.translate(
                  offset: Offset((i - 1) * 74.0, i == 1 ? -4 : 6),
                  child: Transform.rotate(
                    angle: (i - 1) * 0.12,
                    child: Container(
                      width: 116,
                      height: 62,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A574),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [BoxShadow(color: Color(0x33241A10), blurRadius: 8, offset: Offset(0, 3))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: CustomPaint(painter: ScenePainter(scenes[n], const [1.0, 1, 1, 1, 1])),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('Daily Sort+', textAlign: TextAlign.center, style: Palette.display(size: 32)),
        Text(
          'Today\'s puzzle is always free. Plus keeps every day.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.inkSoft),
        ),
        const SizedBox(height: 14),
        perk('🗓️', 'The whole archive', 'Every past puzzle, any time, at your pace'),
        perk('🖼️', 'Every picture', 'Color in the full gallery, one puzzle at a time'),
        perk('💡', 'Unlimited hints', 'One free hint a day for everyone, as many as you like with Plus'),
        perk('📈', 'Coming next', 'A par-or-bust hard mode'),
        perk('💛', 'Support a tiny studio', 'No ads, ever. Keeps Daily Sort calm and free for everyone'),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final p in premiumPlans) ...[
              if (p != premiumPlans.first) const SizedBox(width: 10),
              Expanded(
                child: _PlanCard(plan: p, selected: p == _plan, onTap: () => setState(() => _plan = p)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _waitlisted
              ? Container(
                  key: const ValueKey('wait'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F7F1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2EC4A0), width: 1.5),
                  ),
                  child: Text(
                    'You\'re early! Daily Sort+ opens with the App Store and Google Play release. '
                    'Until then, the last few days of the archive are free for everyone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w800, color: Palette.ink),
                  ),
                )
              : SizedBox(
                  key: const ValueKey('buy'),
                  width: double.infinity,
                  child: BigButton(
                    label: _busy
                        ? 'One moment…'
                        : (_plan.trialDays > 0 ? 'Start ${_plan.trialDays}-day free trial' : 'Subscribe'),
                    onTap: _buy,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          _plan.trialDays > 0
              ? 'Free for ${_plan.trialDays} days, then ${_plan.price}/${_plan.period}. Cancel anytime.'
              : '${_plan.price}/${_plan.period}. Cancel anytime.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.inkSoft),
        ),
        if (widget.premium.canPurchase)
          TextButton(
            onPressed: widget.premium.restore,
            child: Text(
              'Restore purchases',
              style: TextStyle(fontWeight: FontWeight.w800, color: Palette.inkSoft),
            ),
          ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PremiumPlan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Squish(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: selected ? Palette.picked : Palette.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Palette.gold : Palette.line, width: selected ? 2.5 : 1.5),
          ),
          child: Column(
            children: [
              Text(
                plan.label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Palette.inkSoft),
              ),
              const SizedBox(height: 2),
              Text(plan.price, style: Palette.display(size: 24)),
              Text(
                'per ${plan.period}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.inkSoft),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: plan.badge == null ? Colors.transparent : Palette.ink,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  plan.badge ?? ' ',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
