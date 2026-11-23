import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import 'premium.dart';

/// Real App Store / Google Play payments through RevenueCat.
///
/// RevenueCat setup (see `docs/app-store-setup.md`):
/// - one entitlement, `plus`, attached to `plus_monthly`, `plus_yearly` and
///   `plus_lifetime`;
/// - the other products (themes, advent, tips) need no entitlement: the app
///   reads them from the purchase history.
class RevenueCatPremium extends PremiumService {
  static const entitlement = 'plus';

  final String apiKey;
  RevenueCatPremium(this.apiKey);

  bool _ready = false;
  bool _plus = false;
  Set<String> _owned = {};
  int _tips = 0;
  DateTime? _trialEnds;
  final Map<String, rc.StoreProduct> _products = {};

  /// The key for this platform, from `--dart-define=RC_IOS_KEY=appl_...`
  /// (and `RC_ANDROID_KEY=goog_...`). Null when payments aren't set up.
  static String? keyForPlatform() {
    if (kIsWeb) return null;
    const ios = String.fromEnvironment('RC_IOS_KEY');
    const android = String.fromEnvironment('RC_ANDROID_KEY');
    final key = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => ios,
      TargetPlatform.android => android,
      _ => '',
    };
    return key.isEmpty ? null : key;
  }

  /// Connects to the store. Never throws: without a connection the app keeps
  /// working with everything premium locked.
  Future<void> init() async {
    try {
      await rc.Purchases.configure(rc.PurchasesConfiguration(apiKey));
      rc.Purchases.addCustomerInfoUpdateListener(_apply);
      _apply(await rc.Purchases.getCustomerInfo());
      _ready = true;
      final subs = await rc.Purchases.getProducts([
        for (final p in allProducts)
          if (p.kind == ProductKind.subscription) p.id,
      ]);
      final others = await rc.Purchases.getProducts([
        for (final p in allProducts)
          if (p.kind != ProductKind.subscription) p.id,
      ], productCategory: rc.ProductCategory.nonSubscription);
      for (final p in [...subs, ...others]) {
        _products[p.identifier] = p;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('RevenueCat: $e');
    }
  }

  void _apply(rc.CustomerInfo info) {
    final plus = info.entitlements.active[entitlement];
    _plus = plus != null;
    _trialEnds = plus != null && plus.periodType == rc.PeriodType.trial && plus.expirationDate != null
        ? DateTime.tryParse(plus.expirationDate!)?.toLocal()
        : null;
    _owned = {...info.allPurchasedProductIdentifiers.where((id) => !tipProducts.any((t) => t.id == id))};
    _tips = info.nonSubscriptionTransactions.where((t) => tipProducts.any((p) => p.id == t.productIdentifier)).length;
    notifyListeners();
  }

  @override
  bool get isPremium => _plus;

  @override
  Set<String> get owned => _owned;

  @override
  int get tips => _tips;

  @override
  DateTime? get trialEnds => _trialEnds;

  @override
  bool get canPurchase => _ready;

  @override
  String priceOf(Product p) => _products[p.id]?.priceString ?? p.price;

  @override
  Future<bool> purchase(Product p) async {
    final product = _products[p.id];
    if (product == null) return false;
    try {
      final r = await rc.Purchases.purchase(rc.PurchaseParams.storeProduct(product));
      _apply(r.customerInfo);
      return switch (p.kind) {
        ProductKind.subscription || ProductKind.lifetime => _plus,
        ProductKind.theme || ProductKind.advent => _owned.contains(p.id),
        ProductKind.tip => true,
      };
    } on PlatformException catch (e) {
      // Cancelling is not an error worth showing.
      if (rc.PurchasesErrorHelper.getErrorCode(e) != rc.PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('Purchase failed: $e');
      }
      return false;
    }
  }

  @override
  Future<void> restore() async {
    try {
      _apply(await rc.Purchases.restorePurchases());
    } catch (e) {
      debugPrint('Restore failed: $e');
    }
  }
}
