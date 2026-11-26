import 'dart:ui' as ui;

import 'package:daily_sort/game/daily.dart';
import 'package:daily_sort/game/game_controller.dart';
import 'package:daily_sort/services/storage.dart';
import 'package:daily_sort/ui/share_cards.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a solve renders as a 1080x1920 story image', (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final s = await Storage.open();
      final p = puzzleForDay(DateTime(2026, 11, 26));
      final g = GameController(p, s);
      for (final m in p.solution) {
        g.tap(m.from);
        g.tap(m.to);
      }
      final png = await renderShareCard(
        ShareCardData(
          number: p.number,
          dayLabel: 'Thu, Nov 26',
          moves: g.movesUsed,
          par: p.par,
          stars: g.stars,
          streak: 3,
          pours: g.pours,
          tubeCount: p.start.tubeCount,
          solved: [for (final t in g.board.tubes) List.of(t)],
        ),
      );
      final image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
      expect((image.width, image.height), (1080, 1920));
    });
  });
}
