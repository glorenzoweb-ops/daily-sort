import 'package:flutter/foundation.dart';

/// Features that will sit behind "Daily Sort+" ($2.99/mo).
enum PremiumFeature { archive, hints, hardMode }

/// Single place the app asks "is this unlocked?".
///
/// Payments are not wired in yet. When they are, implement a
/// [PremiumService] backed by RevenueCat (one SDK for App Store + Play +
/// Stripe on web) and swap it in `main.dart`. Nothing else needs to change.
abstract class PremiumService extends ChangeNotifier {
  bool get isPremium;
  bool isUnlocked(PremiumFeature f) => isPremium;

  /// Starts the purchase flow. Returns true if the user is now premium.
  Future<bool> purchase();
  Future<void> restore();
}

/// Pre-launch stub: everything premium is locked and shows "coming soon".
class ComingSoonPremium extends PremiumService {
  @override
  bool get isPremium => false;

  @override
  Future<bool> purchase() async => false;

  @override
  Future<void> restore() async {}
}
