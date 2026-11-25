import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../game/daily.dart';
import 'reminder_time.dart';
import 'storage.dart';

class TrialReminder {
  static const _id = 7;
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Ask for permission only when a trial starts, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  static Future<bool> _askPermission() async {
    final allowed = switch (defaultTargetPlatform) {
      TargetPlatform.iOS =>
        await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
          alert: true,
          sound: true,
        ),
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission(),
      _ => false,
    };
    return allowed == true;
  }

  /// Schedules the reminder for two days before [trialEnds]. Returns false
  /// if that moment has passed or notifications aren't allowed.
  static Future<bool> schedule(DateTime trialEnds) async {
    try {
      await _init();
      final at = trialEnds.subtract(const Duration(days: 2));
      if (at.isBefore(DateTime.now())) return false;
      if (!await _askPermission()) return false;
      await _plugin.zonedSchedule(
        id: _id,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(),
          android: AndroidNotificationDetails('trial', 'Trial reminder'),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Your Daily Sort+ trial ends in 2 days',
        body: 'Want to keep it? Nothing to do. Not for you? Cancel any time in your App Store subscriptions.',
      );
      return true;
    } catch (e) {
      debugPrint('Trial reminder: $e');
      return false;
    }
  }

  static Future<void> cancel() async {
    try {
      await _init();
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}

/// The opt-in daily nudge, around the time the player usually solves. The
/// next 7 days are scheduled one by one (so each names its puzzle), and
/// today's is dropped once today is solved. Rescheduled at every launch and
/// solve, so it follows the player's habit.
class DailyReminder {
  static const _firstId = 100, _days = 7;
  static const _lines = [
    'Today\'s sort is waiting. Two minutes, one calm puzzle.',
    'Same puzzle for everyone today. How few moves can you do it in?',
    'Keep your streak going.',
    'A fresh board is ready for you.',
  ];

  /// Asks for permission and turns the reminder on. False if not allowed.
  static Future<bool> enable(Storage storage) async {
    try {
      await TrialReminder._init();
      if (!await TrialReminder._askPermission()) return false;
      await storage.setDailyReminder(true);
      await reschedule(storage);
      return true;
    } catch (e) {
      debugPrint('Daily reminder: $e');
      return false;
    }
  }

  static Future<void> disable(Storage storage) async {
    await storage.setDailyReminder(false);
    await _cancelAll();
  }

  static Future<void> _cancelAll() async {
    try {
      await TrialReminder._init();
      for (var i = 0; i < _days; i++) {
        await TrialReminder._plugin.cancel(id: _firstId + i);
      }
    } catch (_) {}
  }

  static Future<void> reschedule(Storage storage, {DateTime? now}) async {
    if (!storage.dailyReminder) return;
    try {
      await _cancelAll();
      final t = now ?? DateTime.now();
      final at = reminderMinute(storage.playMinutes);
      final solvedToday = storage.day(puzzleNumberFor(t))?.solved ?? false;
      for (var i = 0; i < _days; i++) {
        final when = DateTime(t.year, t.month, t.day + i, at ~/ 60, at % 60);
        if (!when.isAfter(t) || (i == 0 && solvedToday)) continue;
        final n = puzzleNumberFor(when);
        await TrialReminder._plugin.zonedSchedule(
          id: _firstId + i,
          scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(),
            android: AndroidNotificationDetails('daily', 'Daily puzzle'),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: 'Daily Sort #$n is ready',
          body: _lines[n % _lines.length],
        );
      }
    } catch (e) {
      debugPrint('Daily reminder: $e');
    }
  }
}
