import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'services/feedback.dart';
import 'services/premium.dart';
import 'services/storage.dart';
import 'ui/game_screen.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final storage = await Storage.open();
  Haptics.enabled = storage.hapticsOn;
  // Swap for a RevenueCat-backed implementation when payments go live.
  final premium = ComingSoonPremium();
  runApp(DailySortApp(storage: storage, premium: premium));
}

class DailySortApp extends StatelessWidget {
  final Storage storage;
  final PremiumService premium;
  const DailySortApp({super.key, required this.storage, required this.premium});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Palette.gold, surface: Palette.background),
      scaffoldBackgroundColor: Palette.background,
    );
    return MaterialApp(
      title: 'Daily Sort',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(textTheme: GoogleFonts.nunitoTextTheme(base.textTheme)),
      home: GameScreen(storage: storage, premium: premium),
    );
  }
}
