import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/export.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/services/unlocker.dart';
import 'package:fitapp/src/state/app_state.dart';
import 'package:fitapp/src/state/spreadsheets.dart';

Future<AppState> _state() async {
  final s = AppState(MemoryStore(), NoopReminders());
  await s.load();
  return s;
}

void main() {
  group('export', () {
    test('CSV cells quote only when needed', () {
      expect(csvCell('plain'), 'plain');
      expect(csvCell('a, b'), '"a, b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell(null), '');
      expect(csvCell(82.7), '82.7');
      expect(csvCell(3.0), '3');
      final f = csvFile(['a', 'b'], [
        [1, 'x'],
      ]);
      expect(f.startsWith('\uFEFFa,b\r\n1,x\r\n'), isTrue);
    });

    test('CRC-32 matches the standard check value', () {
      expect(crc32('123456789'.codeUnits), 0xCBF43926);
      expect(crc32(const []), 0);
    });

    test('zip has the right structure', () {
      final z = zipFiles({'a.csv': 'hello'.codeUnits, 'b.csv': 'world!'.codeUnits});
      // Local file header signature first, end-of-central-directory last.
      expect(z.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
      final eocd = z.length - 22;
      expect(z.sublist(eocd, eocd + 4), [0x50, 0x4b, 0x05, 0x06]);
      expect(z[eocd + 10], 2); // two entries
      // Stored data is readable as-is after the 30-byte header + name.
      expect(String.fromCharCodes(z.sublist(30 + 5, 30 + 5 + 5)), 'hello');
    });

    test('spreadsheets cover every log', () async {
      final s = await _state();
      s.logWeight(82.7, day: DateTime(2030, 1, 7));
      s.logQuick(DateTime(2030, 1, 7), Meal.lunch, 'Wrap, chicken', const Macros(kcal: 520, protein: 38));
      final files = buildSpreadsheets(s);
      expect(files.keys.toSet(), {
        'weigh_ins.csv', 'sleep.csv', 'measurements.csv', 'workouts.csv', 'food_log.csv', 'daily_summary.csv',
      });
      final food = String.fromCharCodes(files['food_log.csv']!);
      expect(food.contains('"Wrap, chicken"'), isTrue);
    });
  });

  test('PIN hashing is salted and checkable', () async {
    final a = hashPin('1234', 'salt-a');
    expect(a, hashPin('1234', 'salt-a'));
    expect(a == hashPin('1234', 'salt-b'), isFalse);
    expect(a == hashPin('1235', 'salt-a'), isFalse);

    final s = await _state();
    s.setPin('2468', hashPin, 'pepper');
    expect(s.settings.lockEnabled, isTrue);
    expect(s.settings.lockPinHash == '2468', isFalse); // never stored plainly
    expect(s.checkPin('2468', hashPin), isTrue);
    expect(s.checkPin('1357', hashPin), isFalse);
    s.turnOffLock();
    expect(s.settings.lockEnabled, isFalse);
    expect(s.settings.lockPinHash, isNull);
  });

  test('an active phase sets goal mode and pace', () async {
    final s = await _state();
    s.setGoal(s.goal.copyWith(mode: GoalMode.maintain));
    final today = dateOnly(DateTime.now());
    expect(s.goalNow.mode, GoalMode.maintain);
    s.savePhase(Phase(
      id: 'p1',
      mode: GoalMode.lose,
      paceKgPerWeek: 0.5,
      start: DateTime(today.year, today.month, today.day - 3),
      end: DateTime(today.year, today.month, today.day + 30),
    ));
    expect(s.activePhase?.id, 'p1');
    expect(s.goalNow.mode, GoalMode.lose);
    expect(s.goalNow.paceKgPerWeek, 0.5);
    // A later phase that's already started wins.
    s.savePhase(Phase(
      id: 'p2',
      mode: GoalMode.gain,
      paceKgPerWeek: 0.25,
      start: DateTime(today.year, today.month, today.day - 1),
    ));
    expect(s.activePhase?.id, 'p2');
    // Upcoming phases don't apply yet.
    s.deletePhase(s.phases.firstWhere((p) => p.id == 'p2'));
    s.savePhase(Phase(
      id: 'p3',
      mode: GoalMode.gain,
      paceKgPerWeek: 0.25,
      start: DateTime(today.year, today.month, today.day + 40),
    ));
    expect(s.activePhase?.id, 'p1');
  });

  test('weekly summary adds up last week', () async {
    final s = await _state();
    final mon = s.lastWeekStart;
    for (var i = 0; i < 7; i++) {
      s.logWeight(80.0 - i * 0.1, day: DateTime(mon.year, mon.month, mon.day + i));
      s.logQuick(DateTime(mon.year, mon.month, mon.day + i), Meal.lunch, 'x', const Macros(kcal: 2000, protein: 150));
    }
    final w = s.summaryFor(mon);
    expect(w.hasData, isTrue);
    expect(w.avgWeightKg, closeTo(79.7, 1e-9));
    expect(w.foodDays, 7);
    expect(w.avgKcal, 2000);
    expect(s.summaryToShow, isNotNull);
    s.dismissSummary();
    expect(s.summaryToShow, isNull);
  });

  test('widget data shows today\'s weight and workout', () async {
    final s = await _state();
    s.setSettings(s.settings.copyWith(units: Units.imperial));
    expect(s.widgetData['weight'], '—');
    expect(s.widgetData['workout'], 'Rest day');
    s.logWeight(lbToKg(182.4));
    expect(s.widgetData['weight'], '182.4 lb');
    expect(s.widgetData['weight_sub'], anyOf('Logged', startsWith('Avg')));
  });
}
