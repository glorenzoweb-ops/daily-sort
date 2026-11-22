import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/main.dart';
import 'package:daily_sort/services/premium.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/appearance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The board animates forever (idle life), so never pumpAndSettle. Puzzles
  // are generated in a background isolate, which needs real time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('app boots, shows today, and switches to Unwind and back', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false; // fonts are bundled
    SharedPreferences.setMockInitialValues({'seenHowTo': true});
    final storage = await Storage.open();
    await tester.pumpWidget(
      DailySortApp(storage: storage, premium: ComingSoonPremium(), appearance: Appearance(storage)),
    );
    await settle(tester);
    expect(find.text('DAILY SORT'), findsOneWidget);
    expect(find.text('MOVES  '), findsOneWidget);
    // Today's puzzle is now saved on the device.
    expect(storage.cachedPuzzle(puzzleNumberFor(DateTime.now())), isNotNull);

    await tester.tap(find.text('Unwind').first);
    await settle(tester);
    expect(find.text('UNWIND'), findsOneWidget);

    await tester.tap(find.text('Daily'));
    await settle(tester);
    expect(find.text('DAILY SORT'), findsOneWidget);
  });
}
