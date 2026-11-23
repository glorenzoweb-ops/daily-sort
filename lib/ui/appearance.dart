import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';

import '../services/storage.dart';
import 'motion.dart';
import 'palette.dart';
import 'themes.dart';

/// Light or dark, colorblind mode and reduce motion. Saved on the device and
/// applied to [Palette] and [Motion], which every screen reads.
class Appearance extends ChangeNotifier {
  final Storage storage;
  ThemeChoice choice;
  bool colorblind;

  /// Null: follow the phone.
  bool? reduceMotionChoice;

  /// The chosen ball theme, and who decides if it's still owned (a lapsed
  /// subscription falls back to Candy).
  String ballTheme;
  bool Function(String productId) owns = (_) => true;

  Appearance(this.storage)
    : choice = ThemeChoice.values.asNameMap()[storage.theme] ?? ThemeChoice.auto,
      colorblind = storage.colorblind,
      reduceMotionChoice = storage.reduceMotion,
      ballTheme = storage.ballTheme {
    _apply(notify: false);
  }

  bool get systemDark => PlatformDispatcher.instance.platformBrightness == Brightness.dark;

  bool get systemReduceMotion {
    final f = PlatformDispatcher.instance.accessibilityFeatures;
    return f.disableAnimations || f.reduceMotion;
  }

  bool get reduceMotion => reduceMotionChoice ?? systemReduceMotion;

  void setReduceMotion(bool v) {
    reduceMotionChoice = v;
    storage.setReduceMotion(v);
    _apply();
  }

  void setBallTheme(String id) {
    ballTheme = id;
    storage.setBallTheme(id);
    _apply();
  }

  /// Reads everything again from storage (after a backup is restored).
  void reload() {
    ballTheme = storage.ballTheme;
    choice = ThemeChoice.values.asNameMap()[storage.theme] ?? ThemeChoice.auto;
    colorblind = storage.colorblind;
    reduceMotionChoice = storage.reduceMotion;
    _apply();
  }

  void setChoice(ThemeChoice c) {
    choice = c;
    storage.setTheme(c.name);
    _apply();
  }

  void setColorblind(bool v) {
    colorblind = v;
    storage.setColorblind(v);
    _apply();
  }

  /// The phone switched between light and dark, or changed its motion
  /// setting.
  void systemChanged() => _apply();

  void _apply({bool notify = true}) {
    final dark = switch (choice) {
      ThemeChoice.auto => systemDark,
      ThemeChoice.light => false,
      ThemeChoice.dark => true,
    };
    var theme = themeById(ballTheme);
    final pack = theme.product;
    if (pack != null && !owns(pack.id)) theme = candyTheme;
    final changed =
        dark != Palette.dark ||
        colorblind != Palette.colorblind ||
        reduceMotion != Motion.reduced ||
        theme.id != Palette.themeId;
    Palette.themeId = theme.id;
    Palette.themeBalls = theme.colors;
    Palette.dark = dark;
    Palette.colorblind = colorblind;
    Motion.reduced = reduceMotion;
    if (changed && notify) notifyListeners();
  }
}

/// Rebuilds every widget below [context], including const ones, after the
/// palette changed.
void rebuildEverything(BuildContext context) {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}
