import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/services/premium.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/advent.dart';
import 'package:daily_sort/ui/appearance.dart';
import 'package:daily_sort/ui/palette.dart';
import 'package:daily_sort/ui/shop.dart';
import 'package:daily_sort/ui/themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('products', () {
    test('the yearly plan comes first, with a trial; lifetime is a one-time buy', () {
      expect(premiumPlans.first, yearlyPlan);
      expect(yearlyPlan.trialDays, 7);
      expect(lifetimePlan.kind, ProductKind.lifetime);
      expect(lifetimePlan.period, isNull);
      expect({for (final p in allProducts) p.id}.length, allProducts.length, reason: 'ids are unique');
    });

    test('Plus includes every theme and the advent calendar', () async {
      final s = FakeStorePremium();
      expect(s.ownsTheme(themeJewel.id), isFalse);
      expect(s.hasAdvent, isFalse);
      await s.purchase(yearlyPlan);
      expect(s.isPremium, isTrue);
      expect(s.trialEnds!.difference(DateTime.now()).inDays, closeTo(7, 1));
      expect(s.ownsTheme(themeJewel.id), isTrue);
      expect(s.hasAdvent, isTrue);
    });

    test('a theme on its own unlocks only that theme', () async {
      final s = FakeStorePremium();
      await s.purchase(themePastel);
      expect(s.isPremium, isFalse);
      expect(s.ownsTheme(themePastel.id), isTrue);
      expect(s.ownsTheme(themeNeon.id), isFalse);
    });

    test('tips make you a supporter and can be given again', () async {
      final s = FakeStorePremium();
      expect(s.isSupporter, isFalse);
      await s.purchase(tipSmall);
      await s.purchase(tipSmall);
      expect(s.tips, 2);
      expect(s.isSupporter, isTrue);
      expect(s.isPremium, isFalse);
    });
  });

  group('ball themes', () {
    test('every theme has six distinct colors', () {
      for (final t in ballThemes) {
        expect(t.colors.length, 6);
        expect(t.colors.toSet().length, 6, reason: t.id);
      }
    });

    test('a theme you no longer own falls back to Candy', () async {
      SharedPreferences.setMockInitialValues({'ballTheme': 'jewel'});
      final storage = await Storage.open();
      var owned = true;
      final a = Appearance(storage)..owns = (_) => owned;
      a.systemChanged();
      expect(Palette.themeId, 'jewel');
      expect(Palette.balls, jewelTheme.colors);
      owned = false;
      a.systemChanged();
      expect(Palette.themeId, 'candy');
      expect(Palette.balls, Palette.candyBalls);
      a.setColorblind(true);
      expect(Palette.balls, Palette.safeBalls, reason: 'colorblind colors always win');
      a.setColorblind(false);
    });
  });

  group('advent calendar', () {
    test('door n opens on December n and closes after Epiphany', () {
      expect(adventDoorOpen(1, DateTime(2026, 11, 30, 23)), isFalse);
      expect(adventDoorOpen(1, DateTime(2026, 12, 1, 0, 5)), isTrue);
      expect(adventDoorOpen(24, DateTime(2026, 12, 23, 23)), isFalse);
      expect(adventDoorOpen(24, DateTime(2026, 12, 24)), isTrue);
      expect(adventDoorOpen(5, DateTime(2027, 1, 6, 20)), isTrue);
      expect(adventDoorOpen(5, DateTime(2027, 1, 7)), isFalse);
      expect(adventSeason(DateTime(2026, 11, 23)), isTrue);
      expect(adventSeason(DateTime(2026, 11, 1)), isFalse);
    });

    test('each door is the same puzzle for everyone, and doors differ', () {
      final a = adventPuzzle(3), b = adventPuzzle(3), c = adventPuzzle(4);
      expect(encodePuzzleBoard(a), encodePuzzleBoard(b));
      expect(encodePuzzleBoard(a), isNot(encodePuzzleBoard(c)));
      expect(a.par, greaterThan(0));
      expect(a.isPractice, isTrue, reason: 'no move limit, no stats');
    });

    test('solved doors are saved', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await Storage.open();
      await s.addAdventSolved(2);
      await s.addAdventSolved(2);
      await s.addAdventSolved(5);
      expect(s.adventSolved, {2, 5});
    });
  });

  testWidgets('buying a theme in the shop switches to it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await tester.runAsync(Storage.open);
    final premium = FakeStorePremium();
    final appearance = Appearance(storage!)..owns = premium.ownsTheme;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShopSheet(premium: premium, appearance: appearance, onPlus: () {}, onAdvent: () {}),
          ),
        ),
      ),
    );
    expect(find.text(r'$1.99'), findsNWidgets(3));
    await tester.tap(find.text('Neon'));
    await tester.pump();
    expect(premium.ownsTheme(themeNeon.id), isTrue);
    expect(Palette.themeId, 'neon');
    expect(storage.ballTheme, 'neon');
    appearance.setBallTheme('candy');
    // Let the bundled fonts finish loading before the test ends.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}

String encodePuzzleBoard(DailyPuzzle p) => p.start.tubes.toString();
