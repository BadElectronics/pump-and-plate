import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

void main() {
  test('the week starts on Sunday or Monday', () {
    final wed = DateTime(2026, 10, 7); // a Wednesday
    expect(weekStartOf(wed, sundayFirst: true), DateTime(2026, 10, 4));
    expect(weekStartOf(wed, sundayFirst: false), DateTime(2026, 10, 5));
    final sun = DateTime(2026, 10, 4); // a Sunday
    expect(weekStartOf(sun, sundayFirst: true), sun);
    expect(weekStartOf(sun, sundayFirst: false), DateTime(2026, 9, 28));
    // Across the clock change (US: Sunday Nov 1, 2026).
    expect(weekStartOf(DateTime(2026, 11, 3, 23, 30), sundayFirst: true), DateTime(2026, 11, 1));
    expect(weekdayOrder(sundayFirst: true).first, DateTime.sunday);
    expect(weekdayOrder(sundayFirst: false).first, DateTime.monday);
  });

  test('Sunday is the default, and the choice is saved', () {
    expect(const AppSettings().weekStartsSunday, isTrue);
    expect(AppSettings.fromRow(const AppSettings().toRow()).weekStartsSunday, isTrue);
    final monday = const AppSettings().copyWith(weekStartsSunday: false);
    expect(AppSettings.fromRow(monday.toRow()).weekStartsSunday, isFalse);
  });

  test('last week follows the setting', () async {
    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    expect(s.lastWeekStart.weekday, DateTime.sunday);
    s.setSettings(s.settings.copyWith(weekStartsSunday: false));
    expect(s.lastWeekStart.weekday, DateTime.monday);
  });
}
