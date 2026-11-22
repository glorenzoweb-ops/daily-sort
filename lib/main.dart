import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'services/comfort.dart';
import 'services/link.dart';
import 'services/premium.dart';
import 'services/sound.dart';
import 'services/storage.dart';
import 'ui/appearance.dart';
import 'ui/game_screen.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in assets/google_fonts: never download them.
  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final storage = await Storage.open();
  applySoundAndHaptics(storage);
  Sounds.init(); // not awaited: the game never waits on audio
  // Swap for a RevenueCat-backed implementation when payments go live.
  final premium = const bool.fromEnvironment('PREMIUM') ? UnlockedPremium() : ComingSoonPremium();
  final appearance = Appearance(storage);
  runApp(
    DailySortApp(storage: storage, premium: premium, appearance: appearance, incomingResult: incomingResultParam()),
  );
}

class DailySortApp extends StatefulWidget {
  final Storage storage;
  final PremiumService premium;
  final Appearance appearance;

  /// A friend's result from the link that opened the app (`?r=...`).
  final String? incomingResult;
  const DailySortApp({
    super.key,
    required this.storage,
    required this.premium,
    required this.appearance,
    this.incomingResult,
  });

  @override
  State<DailySortApp> createState() => _DailySortAppState();
}

class _DailySortAppState extends State<DailySortApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.appearance.addListener(_changed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appearance.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => widget.appearance.systemChanged();

  @override
  void didChangeAccessibilityFeatures() => widget.appearance.systemChanged();

  bool _incomingUsed = false;

  /// A new key starts the game screen fresh.
  Key _screenKey = UniqueKey();

  /// A backup was restored: apply its settings and start over with its data.
  void _restored() {
    applySoundAndHaptics(widget.storage);
    Sounds.setAmbience(Sounds.ambience);
    Sounds.setMusic(Sounds.music);
    widget.appearance.reload();
    setState(() {
      _screenKey = UniqueKey();
      _incomingUsed = true;
    });
  }

  void _changed() {
    setState(() {});
    // Many widgets read the palette directly, some of them const: redraw all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rebuildEverything(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Palette.gold,
        brightness: Palette.dark ? Brightness.dark : Brightness.light,
        surface: Palette.background,
      ),
      scaffoldBackgroundColor: Palette.background,
    );
    return MaterialApp(
      title: 'Daily Sort',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(textTheme: GoogleFonts.nunitoTextTheme(base.textTheme)),
      home: GameScreen(
        key: _screenKey,
        onRestored: _restored,
        storage: widget.storage,
        premium: widget.premium,
        appearance: widget.appearance,
        incomingResult: _incomingUsed ? null : widget.incomingResult,
      ),
    );
  }
}
