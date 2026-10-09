import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/log_parser.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/backup.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

void main() {
  group('warm-up sets', () {
    List<(int, int)> lb(double workingLb) =>
        [for (final (kg, r) in warmupSets(lbToKg(workingLb), imperial: true)) (kgToLb(kg).round(), r)];
    test('a ramp of 40, 60 and 80 percent, rounded to loadable weights', () {
      expect(lb(225), [(90, 8), (135, 5), (180, 3)]);
      expect([for (final (kg, r) in warmupSets(100, imperial: false)) (kg, r)], [(40.0, 8), (60.0, 5), (80.0, 3)]);
      expect(warmupSets(lbToKg(15), imperial: true), isEmpty); // too light to need warm-ups
      expect(warmupSets(10, imperial: false), isEmpty);
      expect(lb(30), [(10, 8), (20, 5), (25, 3)]); // the lightest that gets a ramp
    });
  });

  group('set types', () {
    test('saved and read back, and old warm-ups still read as warm-ups', () {
      const drop = SetEntry(exerciseId: 'x', weightKg: 60, reps: 8, done: true, type: SetType.drop);
      expect(SetEntry.fromJson(drop.toJson()).type, SetType.drop);
      final old = SetEntry.fromJson({'exercise_id': 'x', 'warmup': true, 'done': true});
      expect(old.type, SetType.warmup);
      expect(old.warmup, isTrue);
      expect(old.copyWith(warmup: false).type, SetType.normal);
      expect(const SetEntry(exerciseId: 'x', warmup: true).type, SetType.warmup);
    });

    test('drop sets, partials and myo-reps are left out of records', () async {
      final s = AppState(MemoryStore(), NoopReminders());
      await s.load();
      final day = DateTime(2026, 10, 1);
      SetEntry set(SetType t) => SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 5, done: true, type: t);
      expect(s.setE1rm(set(SetType.normal), day), isNotNull);
      expect(s.setE1rm(set(SetType.failure), day), isNotNull);
      for (final t in [SetType.warmup, SetType.drop, SetType.partial, SetType.myo]) {
        expect(s.setE1rm(set(t), day), isNull, reason: t.name);
      }
      expect(SetType.partial.volumeShare, 0.5);
      expect(SetType.warmup.volumeShare, 0);
    });
  });

  group('water', () {
    test('amounts read naturally', () {
      expect(formatWater(mlPerCup * 3, imperial: true), '3 cups');
      expect(formatWater(mlPerCup, imperial: true), '1 cup');
      expect(formatWater(750, imperial: false), '750 ml');
      expect(formatWater(1500, imperial: false), '1.5 L');
    });

    test('added, removed, totalled, saved and backed up', () async {
      final store = MemoryStore();
      final s = AppState(store, NoopReminders());
      await s.load();
      s.setSettings(s.settings.copyWith(units: Units.metric));
      expect(s.waterGoalMl, 2000);
      s.addWater(250);
      s.addWater(500);
      expect(s.waterOn(DateTime.now()), 750);
      s.removeWater(s.waterEntriesOn(DateTime.now()).first);
      expect(s.waterOn(DateTime.now()), 500);
      await s.settle();
      final again = AppState(store, NoopReminders());
      await again.load();
      expect(again.waterOn(DateTime.now()), 500);
      final restored = decodeBackup(encodeBackup(again.snapshot));
      expect(restored.water.single.ml, 500);
    });

    test('typed in Chat', () {
      expect((parseLogIntent('drank 500 ml water') as WaterIntent).ml, 500);
      expect((parseLogIntent('had 2 cups of water') as WaterIntent).ml, closeTo(473.2, 0.1)); // not a food
      expect((parseLogIntent('water: 1.5 l') as WaterIntent).ml, 1500);
      expect(parseLogIntent('I drank some water'), isNull);
    });

    testWidgets('+1 cup on Home', (tester) async {
      await tester.pumpWidget(FitApp(
        store: MemoryStore(const StoredData(settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true))),
        reminders: NoopReminders(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('0 cups of 8 cups'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-water')));
      await tester.pump();
      expect(find.text('1 cup of 8 cups'), findsOneWidget);
    });
  });

  test('"Free memory when Chat isn\'t used" is off by default, and saved', () {
    expect(const AppSettings().aiIdleUnload, isFalse);
    expect(AppSettings.fromRow(const AppSettings().toRow()).aiIdleUnload, isFalse);
    expect(AppSettings.fromRow(const AppSettings().copyWith(aiIdleUnload: true).toRow()).aiIdleUnload, isTrue);
  });
}
