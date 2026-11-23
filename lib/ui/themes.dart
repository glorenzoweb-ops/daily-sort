import 'package:material_ui/material_ui.dart';

import '../services/premium.dart';
import 'palette.dart';

/// A set of ball colors. Same roles as [Palette.candyBalls] (red, yellow,
/// green, blue, purple, orange), so the share emoji still match. Colorblind
/// mode always uses its own safe set.
class BallTheme {
  final String id;
  final String name;
  final String blurb;
  final List<Color> colors;

  /// The pack that unlocks it, or null for the free default.
  final Product? product;
  const BallTheme(this.id, this.name, this.blurb, this.colors, {this.product});
}

const candyTheme = BallTheme('candy', 'Candy', 'The classic', Palette.candyBalls);

const pastelTheme = BallTheme('pastel', 'Pastel', 'Soft and sleepy', [
  Color(0xFFFF8FA3),
  Color(0xFFFFD966),
  Color(0xFF7FD6A4),
  Color(0xFF86B3FF),
  Color(0xFFC79CF5),
  Color(0xFFFFB074),
], product: themePastel);

const jewelTheme = BallTheme('jewel', 'Jewel', 'Deep and glowing', [
  Color(0xFFD81B4E),
  Color(0xFFF5B301),
  Color(0xFF00916E),
  Color(0xFF2F5BD8),
  Color(0xFF8E2DC9),
  Color(0xFFE8620C),
], product: themeJewel);

const neonTheme = BallTheme('neon', 'Neon', 'Bright night lights', [
  Color(0xFFFF2E63),
  Color(0xFFF7F052),
  Color(0xFF00F5A0),
  Color(0xFF00BBF9),
  Color(0xFFB15CFF),
  Color(0xFFFF8500),
], product: themeNeon);

const ballThemes = [candyTheme, pastelTheme, jewelTheme, neonTheme];

BallTheme themeById(String id) => ballThemes.firstWhere((t) => t.id == id, orElse: () => candyTheme);
