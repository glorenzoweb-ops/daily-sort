import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'services/feedback.dart';
import 'services/link.dart';
import 'services/premium.dart';
import 'services/sound.dart';
import 'services/sound/ambience.dart';
import 'services/storage.dart';
import 'ui/game_screen.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in assets/google_fonts: never download them.
  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final storage = await Storage.open();
  Haptics.enabled = storage.hapticsOn;
  Sounds.enabled = storage.soundOn;
  Sounds.ambience = Ambience.values.asNameMap()[storage.ambience] ?? Ambience.off;
  Sounds.music = storage.musicOn;
  Sounds.init(); // not awaited: the game never waits on audio
  // Swap for a RevenueCat-backed implementation when payments go live.
  final premium = const bool.fromEnvironment('PREMIUM') ? UnlockedPremium() : ComingSoonPremium();
  runApp(DailySortApp(storage: storage, premium: premium, incomingResult: incomingResultParam()));
}

class DailySortApp extends StatelessWidget {
  final Storage storage;
  final PremiumService premium;

  /// A friend's result from the link that opened the app (`?r=...`).
  final String? incomingResult;
  const DailySortApp({super.key, required this.storage, required this.premium, this.incomingResult});

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
      home: GameScreen(storage: storage, premium: premium, incomingResult: incomingResult),
    );
  }
}
