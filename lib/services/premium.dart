import 'package:flutter/foundation.dart';

/// Features behind "Daily Sort+". Today's puzzle always stays free.
enum PremiumFeature { archive, hints, hardMode }

enum ProductKind { subscription, lifetime, theme, advent, tip }

/// Something the App Store sells. [id] is the product ID in App Store
/// Connect (and RevenueCat). [price] is shown until the store answers with
/// the local price.
class Product {
  final String id;
  final ProductKind kind;
  final String label;
  final String price;

  /// "month" or "year" for subscriptions.
  final String? period;
  final String? badge;
  final int trialDays;
  const Product(this.id, this.kind, this.label, this.price, {this.period, this.badge, this.trialDays = 0});

  bool get isPlus => kind == ProductKind.subscription || kind == ProductKind.lifetime;
}

/// Kept for older code: the plans on the paywall.
typedef PremiumPlan = Product;

/// Prices follow what daily-puzzle apps charge (NYT Games, Puzzmo): a few
/// dollars a month, with the yearly plan as the default and a pay-once
/// option for people who don't want another subscription.
const yearlyPlan = Product(
  'plus_yearly',
  ProductKind.subscription,
  'Yearly',
  r'$19.99',
  period: 'year',
  badge: 'Best value',
  trialDays: 7,
);
const monthlyPlan = Product('plus_monthly', ProductKind.subscription, 'Monthly', r'$2.99', period: 'month');
const lifetimePlan = Product('plus_lifetime', ProductKind.lifetime, 'Lifetime', r'$34.99', badge: 'Pay once');
const premiumPlans = [yearlyPlan, monthlyPlan, lifetimePlan];

/// Ball theme packs. Plus members get them all.
const themePastel = Product('theme_pastel', ProductKind.theme, 'Pastel', r'$1.99');
const themeJewel = Product('theme_jewel', ProductKind.theme, 'Jewel', r'$1.99');
const themeNeon = Product('theme_neon', ProductKind.theme, 'Neon', r'$1.99');
const themeProducts = [themePastel, themeJewel, themeNeon];

/// The December advent calendar: 24 winter puzzles. Plus members get
/// it too.
const adventPack = Product('advent_2026', ProductKind.advent, 'Advent calendar', r'$3.99');

/// Tips: consumable, so they can be given more than once.
const tipSmall = Product('tip_small', ProductKind.tip, 'A coffee', r'$2.99');
const tipLarge = Product('tip_large', ProductKind.tip, 'A cake', r'$4.99');
const tipProducts = [tipSmall, tipLarge];

const allProducts = [...premiumPlans, ...themeProducts, adventPack, ...tipProducts];

/// Past puzzles anyone can replay for free: the last few days.
const freeArchiveDays = 3;

/// Hints anyone gets on each daily puzzle. Unwind hints are always free.
const freeHintsPerDay = 1;

/// The gentle Plus note on the result sheet waits until the player has
/// enjoyed a few dailies. Nothing ever opens the paywall by itself.
const solvesBeforePlusNote = 3;

/// Whether puzzle [number] is locked in the archive on day [today].
bool archiveLocked(int number, int today, PremiumService premium) =>
    number < today - freeArchiveDays && !premium.isUnlocked(PremiumFeature.archive);

/// Single place the app asks "is this unlocked?" and "what does it cost?".
abstract class PremiumService extends ChangeNotifier {
  /// Daily Sort+ is active: a subscription (or its trial) or lifetime.
  bool get isPremium;
  bool isUnlocked(PremiumFeature f) => isPremium;

  /// One-time products bought on this account (themes, advent, lifetime).
  Set<String> get owned => const {};

  /// Tips given so far.
  int get tips => 0;
  bool get isSupporter => tips > 0;

  bool ownsTheme(String productId) => isPremium || owned.contains(productId);
  bool get hasAdvent => isPremium || owned.contains(adventPack.id);
  bool get hasLifetime => owned.contains(lifetimePlan.id);

  /// When the free trial ends, if one is running.
  DateTime? get trialEnds => null;

  /// Whether [purchase] can take money on this platform yet.
  bool get canPurchase;

  /// The store's local price for [p] (e.g. "CHF 2.00"), or the default.
  String priceOf(Product p) => p.price;

  /// Starts the purchase flow. Returns true if it went through.
  Future<bool> purchase(Product p);
  Future<void> restore();
}

/// Pre-launch (and the web): everything premium is locked, and the paywall
/// says payments open with the store release.
class ComingSoonPremium extends PremiumService {
  @override
  bool get isPremium => false;

  @override
  bool get canPurchase => false;

  @override
  Future<bool> purchase(Product p) async => false;

  @override
  Future<void> restore() async {}
}

/// Everything unlocked, for testing: `--dart-define=PREMIUM=true`.
class UnlockedPremium extends PremiumService {
  @override
  bool get isPremium => true;

  @override
  Set<String> get owned => {for (final p in allProducts) p.id};

  @override
  bool get canPurchase => true;

  @override
  Future<bool> purchase(Product p) async => true;

  @override
  Future<void> restore() async {}
}

/// A fake store for tests and screenshots: purchases go through at once.
class FakeStorePremium extends PremiumService {
  bool _plus = false;
  final Set<String> _owned = {};
  int _tips = 0;
  DateTime? _trialEnds;

  @override
  bool get isPremium => _plus;

  @override
  Set<String> get owned => _owned;

  @override
  int get tips => _tips;

  @override
  DateTime? get trialEnds => _trialEnds;

  @override
  bool get canPurchase => true;

  @override
  Future<bool> purchase(Product p) async {
    switch (p.kind) {
      case ProductKind.subscription:
        _plus = true;
        if (p.trialDays > 0) _trialEnds = DateTime.now().add(Duration(days: p.trialDays));
      case ProductKind.lifetime:
        _plus = true;
        _owned.add(p.id);
      case ProductKind.theme || ProductKind.advent:
        _owned.add(p.id);
      case ProductKind.tip:
        _tips++;
    }
    notifyListeners();
    return true;
  }

  @override
  Future<void> restore() async {}
}
