import 'package:material_ui/material_ui.dart';

import '../services/premium.dart';
import 'appearance.dart';
import 'archive.dart';
import 'palette.dart';
import 'squish.dart';
import 'themes.dart';

/// Extras you buy once: ball themes, the advent calendar, and a tip jar.
/// All cosmetic: nothing here makes a puzzle easier.
class ShopSheet extends StatefulWidget {
  final PremiumService premium;
  final Appearance appearance;
  final VoidCallback onPlus;
  final VoidCallback onAdvent;
  const ShopSheet({
    super.key,
    required this.premium,
    required this.appearance,
    required this.onPlus,
    required this.onAdvent,
  });

  @override
  State<ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<ShopSheet> {
  String? _buying;

  @override
  void initState() {
    super.initState();
    widget.premium.addListener(_changed);
  }

  @override
  void dispose() {
    widget.premium.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<bool> _buy(Product p) async {
    final premium = widget.premium;
    if (!premium.canPurchase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Extras are sold in the iPhone app.', style: TextStyle(color: Colors.white)),
        ),
      );
      return false;
    }
    setState(() => _buying = p.id);
    final ok = await premium.purchase(p);
    if (mounted) setState(() => _buying = null);
    return ok;
  }

  Future<void> _theme(BallTheme t) async {
    final pack = t.product;
    if (pack != null && !widget.premium.ownsTheme(pack.id)) {
      if (!await _buy(pack)) return;
    }
    widget.appearance.setBallTheme(t.id);
    if (mounted) setState(() {});
  }

  Future<void> _tip(Product p) async {
    if (!await _buy(p) || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Palette.navy,
        content: const Text(
          'Thank you! That really helps. 💛',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final premium = widget.premium;
    final note = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.inkSoft);
    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(t, style: Palette.display(size: 20)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Extras', textAlign: TextAlign.center, style: Palette.display()),
        Text(
          'Just for looks and fun. Nothing here makes a puzzle easier.',
          textAlign: TextAlign.center,
          style: note.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 14),
        heading('Ball themes'),
        if (Palette.colorblind)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Colorblind mode is on, so its own colors show on the board.', style: note),
          ),
        for (final t in ballThemes)
          _ThemeRow(
            theme: t,
            inUse: widget.appearance.ballTheme == t.id || (t == candyTheme && Palette.themeId == 'candy'),
            owned: t.product == null || premium.ownsTheme(t.product!.id),
            price: t.product == null ? '' : premium.priceOf(t.product!),
            busy: _buying == t.product?.id,
            onTap: () => _theme(t),
          ),
        if (!premium.isPremium)
          TextButton(
            onPressed: widget.onPlus,
            child: Text(
              'Every theme comes with Daily Sort+',
              style: note.copyWith(fontWeight: FontWeight.w800, color: Palette.ink),
            ),
          ),
        const SizedBox(height: 10),
        heading('Advent calendar 🎄'),
        _Card(
          title: '24 winter puzzles',
          sub: premium.hasAdvent
              ? 'Yours. A new door opens every day, Dec 1 to 24.'
              : 'A door a day, Dec 1 to 24, each with its own picture. Door 1 is free. '
                    '${premium.priceOf(adventPack)} once, or included with Plus.',
          action: 'Open',
          onTap: widget.onAdvent,
        ),
        const SizedBox(height: 10),
        heading('Tip jar'),
        Text(
          'Daily Sort is made by one person, with no ads. If it brightens your day, a tip keeps it going.',
          style: note.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 10),
        if (premium.isSupporter)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '💛 You\'re a supporter. Thank you!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Palette.ink),
            ),
          ),
        Row(
          children: [
            for (final (i, t) in tipProducts.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _TipButton(
                  emoji: i == 0 ? '☕' : '🍰',
                  label: t.label,
                  price: premium.priceOf(t),
                  busy: _buying == t.id,
                  onTap: () => _tip(t),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final BallTheme theme;
  final bool inUse, owned, busy;
  final String price;
  final VoidCallback onTap;
  const _ThemeRow({
    required this.theme,
    required this.inUse,
    required this.owned,
    required this.price,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final action = inUse ? 'In use' : (owned ? 'Use' : (busy ? '…' : price));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: !inUse,
        label: '${theme.name} theme, ${theme.blurb}. $action',
        excludeSemantics: true,
        child: Squish(
          child: Material(
            color: inUse ? Palette.picked : Palette.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: inUse ? Palette.gold : Palette.line, width: 2),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: inUse ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    for (final c in theme.colors.take(6))
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            theme.name,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Palette.ink),
                          ),
                          Text(
                            theme.blurb,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.inkSoft),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: inUse ? Colors.transparent : (owned ? Palette.card : Palette.ink),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: inUse ? Colors.transparent : Palette.line),
                      ),
                      child: Text(
                        action,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: inUse ? Palette.inkSoft : (owned ? Palette.ink : Palette.onInk),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title, sub, action;
  final VoidCallback onTap;
  const _Card({required this.title, required this.sub, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) => PlusBanner(text: '$title\n$sub', onTap: onTap);
}

class _TipButton extends StatelessWidget {
  final String emoji, label, price;
  final bool busy;
  final VoidCallback onTap;
  const _TipButton({
    required this.emoji,
    required this.label,
    required this.price,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Squish(
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.ink,
        minimumSize: const Size(0, 60),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        side: BorderSide(color: Palette.tubeStroke, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      onPressed: busy ? null : onTap,
      child: busy
          ? const Text('…')
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$emoji $label', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                Text(
                  price,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.inkSoft),
                ),
              ],
            ),
    ),
  );
}
