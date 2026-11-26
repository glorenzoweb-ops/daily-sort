import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'game/game_controller.dart';
import 'services/analytics.dart';
import 'services/cloud_sync.dart';
import 'services/comfort.dart';
import 'services/link.dart';
import 'services/feedback.dart';
import 'services/premium.dart';
import 'services/premium_revenuecat.dart';
import 'services/reminders.dart';
import 'services/sound.dart';
import 'services/storage.dart';
import 'ui/appearance.dart';
import 'ui/game_screen.dart';
import 'ui/palette.dart';
import 'ui/perf.dart';
import 'ui/perf_log.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts are bundled in assets/google_fonts: never download them.
  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final storage = await Storage.open();
  // A new iPhone or a reinstall: bring the streak back from iCloud.
  final fromCloud = await CloudSync.restoreIfNew(storage);
  applySoundAndHaptics(storage);
  Haptics.prepare();
  Analytics.start(storage); // never awaited
  DailyReminder.reschedule(storage); // never awaited
  final premium = _premium();
  final appearance = Appearance(storage)..owns = premium.ownsTheme;
  // A purchase or a lapsed subscription can change which theme shows.
  premium.addListener(appearance.systemChanged);
  appearance.systemChanged();
  // Sounds are built after the first frame, so the board shows first.
  WidgetsBinding.instance.addPostFrameCallback((_) => Sounds.init()); // never awaited
  runApp(
    DailySortApp(
      storage: storage,
      premium: premium,
      appearance: appearance,
      incomingResult: incomingResultParam(),
      restoredFromCloud: fromCloud,
    ),
  );
}

/// Real payments when a RevenueCat key was built in (`--dart-define=
/// RC_IOS_KEY=appl_...`), otherwise the "coming soon" paywall. The web
/// never sells: Plus is bought in the app.
PremiumService _premium() {
  if (const bool.fromEnvironment('PREMIUM')) return UnlockedPremium();
  if (const bool.fromEnvironment('FAKE_STORE')) return FakeStorePremium();
  final key = RevenueCatPremium.keyForPlatform();
  if (key == null) return ComingSoonPremium();
  return RevenueCatPremium(key)..init();
}

class DailySortApp extends StatefulWidget {
  final Storage storage;
  final PremiumService premium;
  final Appearance appearance;

  /// A friend's result from the link that opened the app (`?r=...`).
  final String? incomingResult;

  /// The streak and stats just came back from iCloud (say so once).
  final bool restoredFromCloud;
  const DailySortApp({
    super.key,
    required this.storage,
    required this.premium,
    required this.appearance,
    this.incomingResult,
    this.restoredFromCloud = false,
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
    if (widget.restoredFromCloud) WidgetsBinding.instance.addPostFrameCallback((_) => _toastCloud());
  }

  final _messenger = GlobalKey<ScaffoldMessengerState>();
  DateTime? _leftAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) GameController.flushAll();
    if (state == AppLifecycleState.paused) {
      GameController.flushAll();
      _leftAt = DateTime.now();
      Analytics.flush();
      CloudSync.push(widget.storage);
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      if (left != null && DateTime.now().difference(left) > const Duration(minutes: 5)) Analytics.newSession();
      DailyReminder.reschedule(widget.storage);
      _checkCloud();
    }
  }

  /// iCloud can arrive a little after the first launch on a new phone.
  Future<void> _checkCloud() async {
    if (await CloudSync.restoreIfNew(widget.storage) && mounted) {
      _restored();
      _toastCloud();
    }
  }

  void _toastCloud() {
    final s = widget.storage.stats;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Welcome back! Your ${s.solved} solves${s.streak > 0 ? ' and your ${s.streak}-day streak' : ''} came back from iCloud.',
        ),
      ),
    );
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
    return ValueListenableBuilder(
      valueListenable: showPerformance,
      builder: (context, perf, _) => MaterialApp(
        title: 'Daily Sort',
        scaffoldMessengerKey: _messenger,
        showPerformanceOverlay: perf,
        builder: (context, child) => Stack(children: [child!, if (perf) const PerfLogPanel()]),
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
      ),
    );
  }
}
