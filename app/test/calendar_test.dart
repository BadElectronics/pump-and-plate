import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

Future<AppState> _state() async {
  final s = AppState(MemoryStore(), NoopReminders());
  await s.load();
  s.addStarterPlan();
  return s;
}

void main() {
  test('schedule, move and remove a planned workout', () async {
    final s = await _state();
    final upper = s.workouts.first;
    final mon = DateTime(2030, 1, 7);
    final p = s.schedule(upper.id, mon);
    expect(s.plannedOn(mon).single.workoutId, upper.id);

    s.movePlanned(p, DateTime(2030, 1, 8));
    expect(s.plannedOn(mon), isEmpty);
    expect(s.plannedOn(DateTime(2030, 1, 8)).length, 1);

    // Undo puts it back exactly.
    s.restorePlanned(p);
    expect(s.plannedOn(mon).length, 1);

    s.removePlanned(p);
    expect(s.planned, isEmpty);
  });

  test('copy last week skips workouts already planned', () async {
    final s = await _state();
    final a = s.workouts[0];
    final b = s.workouts[1];
    s.schedule(a.id, DateTime(2030, 1, 7));
    s.schedule(b.id, DateTime(2030, 1, 9));
    s.schedule(a.id, DateTime(2030, 1, 14)); // already there next week
    final added = s.copyPreviousWeek(DateTime(2030, 1, 14));
    expect(added.length, 1);
    expect(s.plannedOn(DateTime(2030, 1, 16)).single.workoutId, b.id);
    expect(s.plannedOn(DateTime(2030, 1, 14)).length, 1);
  });

  test('a finished session marks the planned workout done', () async {
    final s = await _state();
    final w = s.workouts.first;
    final today = dateOnly(DateTime.now());
    final p = s.schedule(w.id, today);
    expect(s.plannedDone(p), isFalse);
    final x = s.startSession(w);
    s.updateSession(x.copyWith(sets: [
      SetEntry(exerciseId: w.items.first.exerciseId, weightKg: 100, reps: 5, done: true),
    ]));
    s.finishSession(s.sessions.single);
    expect(s.plannedDone(p), isTrue);
  });

  test('editing keeps ticked sets and deletes empty workouts', () async {
    final s = await _state();
    final w = s.workouts.first;
    final x = s.startSession(w);
    final id = w.items.first.exerciseId;
    s.updateSession(x.copyWith(sets: [
      SetEntry(exerciseId: id, weightKg: 100, reps: 5, done: true),
      SetEntry(exerciseId: id, weightKg: 100, reps: 5, done: true),
    ]));
    s.finishSession(s.sessions.single);
    final finished = s.sessions.single;
    expect(finished.finished, isTrue);

    final edited = finished.copyWith(sets: [
      finished.sets.first,
      finished.sets.last.copyWith(done: false),
    ]);
    expect(s.saveEditedSession(edited), isTrue);
    expect(s.sessions.single.sets.length, 1);

    final emptied = s.sessions.single.copyWith(sets: [
      s.sessions.single.sets.single.copyWith(done: false),
    ]);
    expect(s.saveEditedSession(emptied), isFalse);
    expect(s.sessions, isEmpty);
  });

  test('deleting a workout clears its future calendar slots', () async {
    final s = await _state();
    final w = s.workouts.first;
    s.schedule(w.id, DateTime(2099, 1, 1));
    s.deleteWorkout(w);
    expect(s.planned, isEmpty);
  });

  test('a running rest is saved, then recorded or dropped at finish', () async {
    final s = await _state();
    final w = s.workouts.first;
    final id = w.items.first.exerciseId;
    final start = DateTime(2030, 1, 7, 7, 0, 0);
    final running = SetEntry(exerciseId: id, weightKg: 100, reps: 5, done: true, restStartedAt: start);
    expect(running.resting, isTrue);
    // Survives the database round-trip (sets are stored as JSON).
    final back = SetEntry.fromJson(running.toJson());
    expect(back.restStartedAt, start);
    expect(back.resting, isTrue);
    // Ended rest is recorded and no longer running.
    final ended = running.copyWith(restSec: 125, restStartedAt: null);
    expect(ended.resting, isFalse);
    expect(SetEntry.fromJson(ended.toJson()).restSec, 125);
    // Finishing drops a rest still running after the last set.
    final x = s.startSession(w);
    s.updateSession(x.copyWith(sets: [ended, running]));
    s.finishSession(s.sessions.single);
    final saved = s.sessions.single.sets;
    expect(saved.first.restSec, 125);
    expect(saved.last.restStartedAt, isNull);
    expect(saved.last.restSec, isNull);
  });

  test('past weigh-ins can be added, changed and deleted', () async {
    final s = await _state();
    final day = DateTime(2026, 9, 1);
    s.logWeight(82.0, day: day);
    expect(s.weighInOn(day)!.weightKg, 82.0);
    s.logWeight(81.5, day: day);
    expect(s.weighIns.where((w) => dayKey(w.date) == dayKey(day)).length, 1);
    expect(s.weighInOn(day)!.weightKg, 81.5);
    s.deleteWeighIn(day);
    expect(s.weighInOn(day), isNull);
  });

  test('superset spans group linked exercises', () {
    const items = [
      WorkoutItem(exerciseId: 'a', linkNext: true),
      WorkoutItem(exerciseId: 'b'),
      WorkoutItem(exerciseId: 'c'),
      WorkoutItem(exerciseId: 'd', linkNext: true),
      WorkoutItem(exerciseId: 'e', linkNext: true),
      WorkoutItem(exerciseId: 'f'),
    ];
    final spans = AppState.supersetSpans(items);
    expect(spans[0], (0, 1));
    expect(spans[1], (0, 1));
    expect(spans[2], isNull);
    expect(spans[3], (3, 5));
    expect(spans[5], (3, 5));
  });

  test('cardio: starter exercises, one interval, notes and minutes', () async {
    final s = await _state();
    expect(s.isCardio('run'), isTrue);
    expect(s.isCardio('bench_press'), isFalse);
    final w = Workout(id: 'w-cardio', name: 'Run day', items: const [
      WorkoutItem(exerciseId: 'run', targetMin: 30),
      WorkoutItem(exerciseId: 'bench_press', sets: 3, restSec: 90),
    ]);
    s.saveWorkout(w);
    expect(s.minutesFor(w.items), 30 + 5);
    final x = s.startSession(s.workoutById('w-cardio'));
    expect(x.sets.where((e) => e.exerciseId == 'run').length, 1);
    expect(x.sets.where((e) => e.exerciseId == 'bench_press').length, 3);
    s.setExerciseNote('bench_press', '  Seat 4  ');
    expect(s.exercise('bench_press')!.note, 'Seat 4');
    s.setExerciseNote('bench_press', '');
    expect(s.exercise('bench_press')!.note, isNull);
  });

  test('new fields survive storage round-trips', () {
    const item = WorkoutItem(exerciseId: 'run', linkNext: true, targetMin: 25);
    final back = WorkoutItem.fromJson(item.toJson());
    expect(back.linkNext, isTrue);
    expect(back.targetMin, 25);
    const set = SetEntry(exerciseId: 'run', durationSec: 1815, distanceKm: 5.2, heartRate: 148, calories: 410, done: true);
    final b = SetEntry.fromJson(set.toJson());
    expect(b.durationSec, 1815);
    expect(b.distanceKm, 5.2);
    expect(b.heartRate, 148);
    expect(b.calories, 410);
    const ex = Exercise(id: 'x', name: 'Rower', cardio: true, note: 'Damper 5');
    final e = Exercise.fromRow(ex.toRow());
    expect(e.cardio, isTrue);
    expect(e.note, 'Damper 5');
  });
}
