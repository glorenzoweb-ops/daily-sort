# Selling Daily Sort on the App Store

Everything the code expects, in order. You do this once in App Store Connect and RevenueCat.

## 1. Business (App Store Connect → Business)

- Sign the **Paid Apps** agreement and fill in bank and tax details. Nothing sells until this is done.
- Join the **App Store Small Business Program** (developer.apple.com/app-store/small-business-program). Apple takes 15% instead of 30%.

## 2. The app (App Store Connect → Apps → +)

- Platform iOS, name **Daily Sort** (or the closest free name), bundle ID `com.glorenzoweb.dailySort`, SKU `dailysort`.
- Privacy Policy URL: `https://glorenzoweb-ops.github.io/daily-sort/privacy.html`
- Support URL: `https://glorenzoweb-ops.github.io/daily-sort/support.html`
- App Privacy: **Data Not Collected**, except "Purchases" if Apple asks about RevenueCat. It is not used for tracking.

## 3. Products (App Store Connect → your app → Monetization)

### Subscriptions

Create one subscription group named **Daily Sort+**, with:

| Product ID | Name | Duration | Price (US) | Extra |
| --- | --- | --- | --- | --- |
| `plus_yearly` | Daily Sort+ Yearly | 1 year | $19.99 | Introductory offer: **Free, 1 week**, new subscribers |
| `plus_monthly` | Daily Sort+ Monthly | 1 month | $4.99 | none |

- Turn on **Family Sharing** for both. The paywall promises it.
- Put `plus_yearly` at a higher level than monthly in the group, so switching is an upgrade.

### In-App Purchases

| Product ID | Type | Name | Price (US) |
| --- | --- | --- | --- |
| `plus_lifetime` | Non-Consumable | Daily Sort+ Lifetime | $34.99 |
| `theme_pastel` | Non-Consumable | Pastel balls | $1.99 |
| `theme_jewel` | Non-Consumable | Jewel balls | $1.99 |
| `theme_neon` | Non-Consumable | Neon balls | $1.99 |
| `advent_2026` | Non-Consumable | Advent calendar 2026 | $3.99 |
| `tip_small` | Consumable | A coffee for the developer | $2.99 |
| `tip_large` | Consumable | A cake for the developer | $4.99 |

- Turn on **Family Sharing** for `plus_lifetime`, the themes and the advent pack.
- Each product needs a short description and a review screenshot. The paywall and the Extras sheet screenshots work.

### Local prices

Apple fills in every country from the US price. Check a few big markets by hand (Switzerland, Euro area, UK, India, Brazil) and round to friendly local prices. Lower tiers in India, Brazil and Turkey sell much better.

### Win-back offers (after launch)

Once there are past subscribers: Subscriptions → Daily Sort+ Yearly → **Win-Back Offers** → for example "50% off the first year, for people who left at least 2 months ago". iOS shows these by itself in the App Store and in Settings, and RevenueCat handles the purchase. The app needs no change.

## 4. RevenueCat (app.revenuecat.com, free under $2.5k/month)

1. Create a project and add an **App Store** app with bundle ID `com.glorenzoweb.dailySort`.
2. Upload the **In-App Purchase key** (App Store Connect → Users and Access → Integrations → In-App Purchase) so RevenueCat can check purchases.
3. **Products:** import all 9 product IDs above.
4. **Entitlements:** create one called `plus` and attach `plus_monthly`, `plus_yearly` and `plus_lifetime`. The other products need no entitlement.
5. Copy the **public iOS API key** (starts with `appl_`) from Project settings → API keys.

## 5. Build with payments on

```
flutter build ipa --dart-define=RC_IOS_KEY=appl_xxxxxxxx
```

Without the key, the app still works and shows "coming soon" on the paywall, which is what the web version does.

To try everything without the store (screenshots, demos), use `--dart-define=FAKE_STORE=true`: every purchase goes through at once.

## 6. Test before review

- In TestFlight, purchases use a sandbox account (App Store Connect → Users and Access → Sandbox). Nothing is charged.
- Check: start the yearly trial (allow the notification, which should arrive 2 days before the end, about 5 days later in sandbox time), buy lifetime, buy a theme and switch to it, open the advent calendar, give a tip, delete the app, reinstall, and **Restore purchases**.

## What the app does, and why

| Idea | Where |
| --- | --- |
| Daily stays free, Plus adds the archive, unlimited hints, themes and the advent calendar | `lib/services/premium.dart` |
| Lifetime purchase next to the plans | `lifetimePlan`, paywall in `lib/ui/archive.dart` |
| Yearly is pre-selected, with "Save 66%" next to monthly | `yearlyPlan`, `PaywallSheet` |
| 7-day trial, with a local reminder 2 days before it ends | `lib/services/reminders_native.dart` |
| Family Sharing promised on the paywall | turn it on in step 3 |
| Ball themes as one-time buys | `lib/ui/themes.dart`, `lib/ui/shop.dart` |
| Advent calendar, Dec 1 to 24, door 1 free | `lib/ui/advent.dart` |
| Tip jar with a supporter thank-you | `lib/ui/shop.dart` |
| The paywall opens only when you tap something that needs Plus; the result-sheet note waits for 3 solves | `solvesBeforePlusNote` |
| Win-back offers and local prices | App Store Connect, step 3 |

Never: ads, energy or lives, selling hints for coins, or a hidden close button.
