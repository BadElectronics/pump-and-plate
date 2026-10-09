import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

Future<AppState> _state() async {
  final s = AppState(MemoryStore(), NoopReminders());
  await s.load();
  return s;
}

void main() {
  test('ticking a meal on the Today widget logs it, and ticking again unlogs it', () async {
    final s = await _state();
    final today = dateOnly(DateTime.now());
    s.planMeal(today, Meal.breakfast, 'food', 'oats', 80);
    s.planMeal(today, Meal.breakfast, 'food', 'banana', 120);
    expect(s.entriesOn(today, Meal.breakfast), isEmpty);
    expect(s.widgetData['meal0_done'], false);

    expect(s.toggleMealSlot(today, Meal.breakfast), true);
    expect(s.entriesOn(today, Meal.breakfast).length, 2);
    expect(s.widgetData['meal0_done'], true);

    expect(s.toggleMealSlot(today, Meal.breakfast), false);
    expect(s.entriesOn(today, Meal.breakfast), isEmpty);
    expect(s.widgetData['meal0_done'], false);

    // Nothing planned for lunch: nothing to tick.
    expect(s.toggleMealSlot(today, Meal.lunch), false);
    expect(s.widgetData['meal1_has'], false);
  });

  test('sleep quality from the Check-in widget', () async {
    final s = await _state();
    final today = dateOnly(DateTime.now());
    s.logSleep(SleepEntry(date: today, durationMin: 440));
    expect(s.widgetData['ask_quality'], true);
    s.setSleepQuality(today, 4);
    expect(s.sleepOn(today)!.quality, 4);
    expect(s.sleepOn(today)!.durationMin, 440);
    expect(s.widgetData['ask_quality'], false);
    expect(s.widgetData['sleep'], '7.3 h');
    expect(s.widgetData['sleep_sub'], 'Quality 4 · good');
  });

  test('widget data for an empty day', () async {
    final s = await _state();
    final d = s.widgetData;
    expect(d['weight'], '—');
    expect(d['weight_sub'], 'Tap to log');
    expect(d['sleep'], '—');
    expect(d['sleep_sub'], 'Tap to log');
    expect(d['workout'], 'Rest day');
    expect(d['workout_action'], '');
    expect(d['meals_empty'], true);
    expect(d['data_day'], dayKey(DateTime.now()));
    await s.settle();
  });
}
