import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/muscles.dart';
import 'package:fitapp/src/data/starter.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/theme/app_theme.dart';
import 'package:fitapp/src/theme/tokens.dart';
import 'package:fitapp/src/widgets/muscle_map.dart';

DateTime _day(int ago) {
  final t = dateOnly(DateTime.now());
  return DateTime(t.year, t.month, t.day - ago);
}

Session _session(int ago, List<SetEntry> sets) => Session(
      id: 's$ago',
      date: _day(ago),
      name: 'Workout',
      startedAt: _day(ago).add(const Duration(hours: 9)),
      endedAt: _day(ago).add(const Duration(hours: 10)),
      sets: sets,
    );

const _bench = SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 5, done: true);

Exercise? _lookup(String id) {
  for (final e in starterExercises) {
    if (e.id == id) return e;
  }
  return null;
}

void main() {
  test('every built-in strength exercise has muscles; cardio has none', () {
    for (final e in starterExercises) {
      final w = musclesOf(e);
      if (e.cardio) {
        expect(w.primary, isEmpty, reason: e.name);
      } else {
        expect(w.primary, isNotEmpty, reason: e.name);
      }
    }
    expect(musclesOf(_lookup('bench_press')!).secondary, containsAll([Muscle.frontDelts, Muscle.triceps]));
  });

  test('sets per muscle: primary 1, secondary 1/2, warm-ups 0, partials half', () {
    final sessions = [
      _session(1, [
        const SetEntry(exerciseId: 'bench_press', weightKg: 60, reps: 8, done: true, type: SetType.warmup),
        _bench,
        _bench,
        const SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 3, done: true, type: SetType.partial),
        const SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 5), // not done
      ]),
      _session(20, [_bench]), // outside the last 7 days
    ];
    final m = setsPerMuscle(sessions, from: _day(6), to: _day(0), exercise: _lookup);
    expect(m[Muscle.chest], 2.5);
    expect(m[Muscle.frontDelts], 1.25);
    expect(m[Muscle.triceps], 1.25);
    expect(m[Muscle.quads], 0);
    final parts = setsForMuscle(Muscle.triceps, sessions, from: _day(6), to: _day(0), exercise: _lookup);
    expect(parts.single, ('bench_press', 1.25, true)); // secondary
  });

  test('your own exercises keep their muscles; older ones use their group', () {
    const mine = Exercise(
      id: 'x1', name: 'Landmine press', muscle: 'Shoulders', custom: true,
      primaryMuscles: ['frontDelts'], secondaryMuscles: ['chest', 'triceps'],
    );
    final back = Exercise.fromRow(mine.toRow());
    expect(back.primaryMuscles, ['frontDelts']);
    expect(back.secondaryMuscles, ['chest', 'triceps']);
    expect(musclesOf(back).primary, [Muscle.frontDelts]);
    const old = Exercise(id: 'x2', name: 'Some row', muscle: 'Back', custom: true);
    expect(musclesOf(old).primary, [Muscle.lats, Muscle.upperBack]);
  });

  test('heat levels', () {
    expect([0.0, 1.0, 4.5, 5.0, 9.5, 10.0, 19.5, 20.0].map(heatLevel), [0, 1, 1, 2, 2, 3, 3, 4]);
    expect(setsText(4.5), '4.5');
    expect(setsText(6), '6');
  });

  testWidgets('the Overview card shows trained muscles and opens the heatmap', (tester) async {
    await tester.pumpWidget(FitApp(
      store: MemoryStore(StoredData(
        settings: const AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true),
        sessions: [_session(1, const [_bench, _bench, _bench])],
      )),
      reminders: NoopReminders(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Progress'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('MUSCLES THIS WEEK'), findsOneWidget);
    expect(find.textContaining('Chest', findRichText: true), findsWidgets);
    final card = find.byKey(const ValueKey('muscles-overview'));
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('muscle-map')), findsOneWidget);
    expect(find.text('SETS PER MUSCLE · LAST 7 DAYS'), findsOneWidget); // only in Training
  });

  test('every built-in strength exercise has heads, with a main one', () {
    for (final e in starterExercises) {
      final h = headsOf(e);
      if (e.cardio) {
        expect(h, isEmpty, reason: e.name);
      } else {
        expect(h.values.any((v) => v == 3), isTrue, reason: e.name);
      }
    }
    final incline = headsOf(_lookup('incline_db_press')!);
    expect(incline[MuscleHead.chestUpper], 3);
    expect(incline[MuscleHead.chestMiddle], 2);
    expect(incline[MuscleHead.chestLower], 1);
    // New exercises get their muscles from the heads table.
    expect(musclesOf(_lookup('preacher_curl')!).primary, [Muscle.biceps]);
    expect(musclesOf(_lookup('hip_adduction')!).primary, [Muscle.adductors]);
  });

  test('sets per head: main 1, some 1/2, a little 1/4', () {
    final sessions = [
      _session(1, [_bench, _bench]),
    ];
    final h = setsPerHead(sessions, from: _day(6), to: _day(0), exercise: _lookup);
    expect(h[MuscleHead.chestMiddle], 2);
    expect(h[MuscleHead.chestUpper], 1);
    expect(h[MuscleHead.tricepsLong], 0.5);
    expect(h[MuscleHead.bicepsLong], 0);
    final parts = setsForHead(MuscleHead.chestMiddle, sessions, from: _day(6), to: _day(0), exercise: _lookup);
    expect(parts.single, ('bench_press', 2.0, 3));
  });

  test('your own heads are kept and decide the muscles', () {
    const mine = Exercise(id: 'x3', name: 'Cable Y raise', muscle: 'Shoulders', custom: true, heads: {'trapsLower': 3, 'sideDelt': 2});
    final back = Exercise.fromRow(mine.toRow());
    expect(back.heads, {'trapsLower': 3, 'sideDelt': 2});
    expect(headsOf(back), {MuscleHead.trapsLower: 3, MuscleHead.sideDelt: 2});
    expect(musclesOf(back).primary, [Muscle.traps]);
    expect(musclesOf(back).secondary, [Muscle.sideDelts]);
    expect(parseHeads('chestUpper:3 nonsense:2 tricepsLong:9'), {MuscleHead.chestUpper: 3, MuscleHead.tricepsLong: 3});
    expect(MuscleHead.tricepsLong.label, 'Triceps: Long head');
    expect(MuscleHead.sideDelt.label, 'Side delts');
  });

  test('equipment from the table or the name', () {
    expect(equipmentOf(_lookup('db_curl')!), 'Dumbbell');
    expect(equipmentOf(_lookup('cable_lateral_raise')!), 'Cable');
    expect(equipmentOf(_lookup('pec_deck')!), 'Machine');
    expect(equipmentOf(_lookup('pull_up')!), 'Bodyweight');
    expect(equipmentOf(const Exercise(id: 'x', name: 'Smith machine row')), 'Machine');
  });

  testWidgets('tapping the advanced map picks the head under your finger, on either side', (tester) async {
    MuscleHead? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(AppPalette.earth),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: HeadMap(sets: const {}, width: 160, onTap: (h) => tapped = h),
        ),
      ),
    ));
    final origin = tester.getTopLeft(find.byType(HeadMap));
    // Upper chest sits at about (88, 87) on the drawing grid, which starts at (20, 14).
    await tester.tapAt(origin + const Offset(88 - 20, 87 - 14));
    expect(tapped, MuscleHead.chestUpper);
    tapped = null;
    await tester.tapAt(origin + const Offset(112 - 20, 87 - 14)); // the mirrored side
    expect(tapped, MuscleHead.chestUpper);
    await tester.tapAt(origin + const Offset(56 - 20, 135 - 14)); // short head of the biceps
    expect(tapped, MuscleHead.bicepsShort);
  });

  test('every head is drawn on the front or the back', () {
    final drawn = {...headsOnSide(back: false), ...headsOnSide(back: true)};
    expect(drawn, containsAll(MuscleHead.values));
    final muscles = {...musclesOnSide(back: false), ...musclesOnSide(back: true)};
    expect(muscles, containsAll(Muscle.values));
  });

  test('exercises to try for a muscle work it as a primary muscle, focused ones first', () {
    final chest = exercisesForMuscle(Muscle.chest, starterExercises);
    expect(chest.map((e) => e.id), contains('bench_press'));
    for (final e in chest) {
      expect(musclesOf(e).primary, contains(Muscle.chest));
      expect(e.cardio, isFalse);
    }
    for (var i = 1; i < chest.length; i++) {
      expect(musclesOf(chest[i - 1]).primary.length, lessThanOrEqualTo(musclesOf(chest[i]).primary.length));
    }
  });
}
