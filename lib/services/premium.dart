import 'package:flutter/foundation.dart';

/// Features behind "Daily Sort+". Today's puzzle always stays free.
enum PremiumFeature { archive, hints, hardMode }

/// A subscription option on the paywall.
class PremiumPlan {
  final String id;
  final String label;
  final String price;
  final String period;
  final String? badge;
  final int trialDays;
  const PremiumPlan(this.id, this.label, this.price, this.period, {this.badge, this.trialDays = 0});
}

/// Prices follow what daily-puzzle apps charge (NYT Games, Puzzmo): a few
/// dollars a month, with the yearly plan as the default.
const yearlyPlan = PremiumPlan('plus_yearly', 'Yearly', r'$19.99', 'year', badge: 'Save 44%', trialDays: 7);
const monthlyPlan = PremiumPlan('plus_monthly', 'Monthly', r'$2.99', 'month');
const premiumPlans = [yearlyPlan, monthlyPlan];

/// Past puzzles anyone can replay for free: the last few days.
const freeArchiveDays = 3;

/// Hints anyone gets on each daily puzzle. Unwind hints are always free.
const freeHintsPerDay = 1;

/// Whether puzzle [number] is locked in the archive on day [today].
bool archiveLocked(int number, int today, PremiumService premium) =>
    number < today - freeArchiveDays && !premium.isUnlocked(PremiumFeature.archive);

/// Single place the app asks "is this unlocked?".
///
/// Payments are not wired in yet. When they are, implement a
/// [PremiumService] backed by RevenueCat (one SDK for App Store + Play +
/// Stripe on web) and swap it in `main.dart`. Nothing else needs to change.
abstract class PremiumService extends ChangeNotifier {
  bool get isPremium;
  bool isUnlocked(PremiumFeature f) => isPremium;

  /// Whether [purchase] can take money on this platform yet.
  bool get canPurchase;

  /// Starts the purchase flow. Returns true if the user is now premium.
  Future<bool> purchase(PremiumPlan plan);
  Future<void> restore();
}

/// Pre-launch: everything premium is locked, and the paywall says payments
/// open with the store release.
class ComingSoonPremium extends PremiumService {
  @override
  bool get isPremium => false;

  @override
  bool get canPurchase => false;

  @override
  Future<bool> purchase(PremiumPlan plan) async => false;

  @override
  Future<void> restore() async {}
}

/// Everything unlocked, for testing: `--dart-define=PREMIUM=true`.
class UnlockedPremium extends PremiumService {
  @override
  bool get isPremium => true;

  @override
  bool get canPurchase => true;

  @override
  Future<bool> purchase(PremiumPlan plan) async => true;

  @override
  Future<void> restore() async {}
}
