import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

  /// Schedules the reminder for two days before [trialEnds]. Returns false
  /// if that moment has passed or notifications aren't allowed.
  static Future<bool> schedule(DateTime trialEnds) async {
    try {
      await _init();
      final at = trialEnds.subtract(const Duration(days: 2));
      if (at.isBefore(DateTime.now())) return false;
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
      if (allowed != true) return false;
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
