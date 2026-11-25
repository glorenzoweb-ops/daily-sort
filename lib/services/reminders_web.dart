import 'storage.dart';

class TrialReminder {
  static Future<bool> schedule(DateTime trialEnds) async => false;
  static Future<void> cancel() async {}
}

class DailyReminder {
  static Future<bool> enable(Storage storage) async => false;
  static Future<void> disable(Storage storage) async {}
  static Future<void> reschedule(Storage storage, {DateTime? now}) async {}
}
