/// When the daily reminder rings, in minutes after midnight: the middle of
/// the player's recent solve times, or 9:00 before there are any. Rounded
/// to a quarter hour.
int reminderMinute(List<int> recent) {
  if (recent.isEmpty) return 9 * 60;
  final s = [...recent]..sort();
  final mid = s[s.length ~/ 2];
  return (mid ~/ 15 * 15).clamp(0, 24 * 60 - 15);
}
