import 'package:daily_sort/main.dart';
import 'package:daily_sort/services/premium.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app boots and shows today\'s puzzle', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'seenHowTo': true});
    final storage = await Storage.open();
    await tester.pumpWidget(DailySortApp(storage: storage, premium: ComingSoonPremium()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('DAILY SORT'), findsOneWidget);
    expect(find.text('MOVES  '), findsOneWidget);
  });
}
