import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

DateTime _day(int offset) {
  final t = dateOnly(DateTime.now());
  return DateTime(t.year, t.month, t.day + offset);
}

Future<AppState> _losing({double? target}) async {
  final s = AppState(MemoryStore(), NoopReminders());
  await s.load();
  s.setProfile(Profile(birthday: DateTime(1995, 1, 1), heightCm: 180));
  s.setGoal(Goal(mode: GoalMode.lose, targetWeightKg: target, paceKgPerWeek: 0.5));
  for (var i = 6; i >= 0; i--) {
    s.logWeight(90, day: _day(-i));
  }
  return s;
}

void main() {
  test('the projection follows the plan and stops at the goal weight', () async {
    final s = await _losing(target: 88);
    final week = s.projectedWeightOn(_day(7))!;
    expect(week, lessThan(90));
    expect(week, closeTo(89.5, 0.3)); // about the planned 0.5 kg a week
    expect(s.projectedWeightOn(_day(200)), 88); // never past the goal
    expect(s.projectedWeightOn(_day(0)), isNull); // only days ahead
  });

  test('the projection starts from your weight now, not last week\'s average', () async {
    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    s.setProfile(Profile(birthday: DateTime(1995, 1, 1), heightCm: 180));
    s.setGoal(const Goal(mode: GoalMode.lose, paceKgPerWeek: 0.5));
    // Losing 0.2 kg a day: the 7-day average (89.4) is well above today (88.8).
    for (var i = 6; i >= 0; i--) {
      s.logWeight(88.8 + 0.2 * i, day: _day(-i));
    }
    final perDay = s.projectedWeightOn(_day(2))! - s.projectedWeightOn(_day(1))!;
    expect(s.projectedWeightOn(_day(1))! - perDay, closeTo(88.8, 0.01));
  });

  test('weigh-ins added for past days update the projection', () async {
    final s = await _losing();
    final before = s.projectedWeightOn(_day(3))!;
    // Older, heavier weights typed in from a spreadsheet: the trend is now
    // coming down to 90, so where it starts is no longer 90 flat.
    for (var i = 13; i >= 7; i--) {
      s.logWeight(90 + 0.3 * (i - 6), day: _day(-i));
    }
    expect(s.projectedWeightOn(_day(3)), isNot(before));
  });

  test('trend weight: newest day, a fitted line, a lone weigh-in', () {
    final now = DateTime(2026, 10, 8);
    expect(trendWeight(const []), isNull);
    expect(trendWeight([(now, 80.0)]), (day: now, kg: 80.0));
    final line = [for (var i = 0; i < 5; i++) (DateTime(2026, 10, 8 - i), 80.0 + i)];
    expect(trendWeight(line)!.kg, closeTo(80, 1e-9));
    // Weigh-ins over two weeks before the newest one are left out.
    final old = [...line, (DateTime(2026, 9, 1), 120.0)];
    expect(trendWeight(old)!.kg, closeTo(80, 1e-9));
  });

  test('calendar days: real weigh-ins, nothing on empty past days, projections ahead', () async {
    final s = await _losing();
    expect(s.calendarWeightOn(_day(0)), (kg: 90.0, projected: false));
    expect(s.calendarWeightOn(_day(-30)), isNull);
    final ahead = s.calendarWeightOn(_day(10))!;
    expect(ahead.projected, isTrue);
    expect(ahead.kg, lessThan(90));
  });

  testWidgets('the calendar explains projected weights with a legend', (tester) async {
    // A tall screen, so the legend under the month grid is on screen.
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(FitApp(
      store: MemoryStore(const StoredData(settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true))),
      reminders: NoopReminders(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Plan'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Weigh-in'), findsWidgets);
    expect(find.text('Projected weight (at your calorie target)'), findsOneWidget);
  });
}
