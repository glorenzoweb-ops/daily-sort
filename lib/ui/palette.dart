import 'package:material_ui/material_ui.dart';

/// Cozy paper-and-candy palette (matches the TikTok clips).
class Palette {
  static const background = Color(0xFFFFF7EA);
  static const gridLine = Color(0x09000000);
  static const ink = Color(0xFF1B1B2F);
  static const inkSoft = Color(0xFF8A8070);
  static const tubeFill = Color(0xBFFFFFFF);
  static const tubeStroke = Color(0xFFD8CFC0);
  static const gold = Color(0xFFFFC23F);
  static const danger = Color(0xFFE5484D);
  static const card = Colors.white;

  /// Ball colors, index = color id. Each has a matching emoji square for the
  /// share card, so keep the two lists in sync.
  static const balls = <Color>[
    Color(0xFFFF4D6D), // red
    Color(0xFFFFC23F), // yellow
    Color(0xFF2EC4A0), // green
    Color(0xFF4D7CFF), // blue
    Color(0xFFA066F0), // purple
    Color(0xFFFF8A3D), // orange
  ];

  static const emoji = <String>['🟥', '🟨', '🟩', '🟦', '🟪', '🟧'];
}
