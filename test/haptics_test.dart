import 'package:daily_sort/services/feedback.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('taps are spaced out, and a weaker one never follows a stronger one', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
        return null;
      },
    );
    Haptics.enabled = true;
    Haptics.tubeComplete();
    Haptics.land(); // right after a stronger tap: dropped
    Haptics.select(); // dropped too
    expect(calls, ['HapticFeedbackType.mediumImpact']);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    Haptics.land();
    expect(calls.length, 2);
  });
}
