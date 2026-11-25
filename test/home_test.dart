import 'package:daily_sort/ui/home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('greeting follows the hour and uses the name when known', () {
    expect(greeting(DateTime(2026, 11, 25, 8), 'Gio'), 'Good morning, Gio ☀️');
    expect(greeting(DateTime(2026, 11, 25, 14), ''), 'Good afternoon 🌤️');
    expect(greeting(DateTime(2026, 11, 25, 19), ' Leo '), 'Good evening, Leo 🌙');
    expect(greeting(DateTime(2026, 11, 25, 23), 'Gio'), 'Good night, Gio ✨');
    expect(greeting(DateTime(2026, 11, 25, 3), 'Gio'), 'Good night, Gio 🌙');
  });
}
