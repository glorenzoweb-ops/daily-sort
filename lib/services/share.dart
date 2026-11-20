import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../game/daily.dart';
import '../ui/palette.dart';

/// Public URL of the web build. Change after you pick a custom domain.
const String shareUrl = 'https://glorenzoweb-ops.github.io/daily-sort/';

String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

/// Wordle-style result. Spoiler-free: shows which color you moved each turn,
/// not where.
///
/// Daily Sort #1 ⭐⭐⭐
/// 10/12 moves · par 10 · 1st try
/// 🟥🟦🟦🟨🟩
/// 🟥🟨🟩🟦🟥
String buildShareText({
  required DailyPuzzle puzzle,
  required int moves,
  required int stars,
  required int attempts,
  required List<int> moveColors,
  int streak = 0,
}) {
  final b = StringBuffer()
    ..writeln('Daily Sort #${puzzle.number} ${'⭐' * stars}${'☆' * (3 - stars)}')
    ..write('$moves/${puzzle.moveLimit} moves · par ${puzzle.par}');
  b.write(' · ${attempts == 1 ? '1st try' : '${ordinal(attempts)} try'}');
  if (streak >= 2) b.write(' · 🔥$streak');
  b.writeln();
  for (var i = 0; i < moveColors.length; i++) {
    b.write(Palette.emoji[moveColors[i] % Palette.emoji.length]);
    if (i % 5 == 4 && i != moveColors.length - 1) b.writeln();
  }
  b
    ..writeln()
    ..write(shareUrl);
  return b.toString();
}

enum ShareOutcome { shared, copied, failed }

/// Opens the native share sheet (iOS/Android/mobile web), or copies to the
/// clipboard where there is none (desktop web).
Future<ShareOutcome> shareResult(String text) async {
  try {
    // On web without the Web Share API this throws, and we fall back below.
    await SharePlus.instance.share(ShareParams(text: text, mailToFallbackEnabled: false));
    return ShareOutcome.shared;
  } catch (_) {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return ShareOutcome.copied;
    } catch (_) {
      return ShareOutcome.failed;
    }
  }
}
