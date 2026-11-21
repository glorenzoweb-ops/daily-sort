import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';

import '../services/storage.dart';
import 'palette.dart';

/// Light or dark, and colorblind mode. Saved on the device and applied to
/// [Palette], which every screen reads.
class Appearance extends ChangeNotifier {
  final Storage storage;
  ThemeChoice choice;
  bool colorblind;

  Appearance(this.storage)
    : choice = ThemeChoice.values.asNameMap()[storage.theme] ?? ThemeChoice.auto,
      colorblind = storage.colorblind {
    _apply(notify: false);
  }

  bool get systemDark => PlatformDispatcher.instance.platformBrightness == Brightness.dark;

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

  /// The phone switched between light and dark.
  void systemChanged() => _apply();

  void _apply({bool notify = true}) {
    final dark = switch (choice) {
      ThemeChoice.auto => systemDark,
      ThemeChoice.light => false,
      ThemeChoice.dark => true,
    };
    final changed = dark != Palette.dark || colorblind != Palette.colorblind;
    Palette.dark = dark;
    Palette.colorblind = colorblind;
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
