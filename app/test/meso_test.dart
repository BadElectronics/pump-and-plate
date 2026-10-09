import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/backup.dart';
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

Mesocycle _meso(AppState s, DateTime start, MesoProgression p, {int weeks = 4, bool deload = true}) =>
    Mesocycle(
      id: 'm1',
      name: 'Block 1',
      start: start,
      weeks: weeks,
      deload: deload,
      progression: p,
      weightStepKg: lbToKg(5),
      schedule: {1: s.workouts[0].id, 3: s.workouts[1].id, 5: s.workouts[2].id},
    );

void main() {
  test('weeks, deload and the calendar', () async {
    final s = await _state();
    final mon = DateTime(2030, 1, 7); // a Monday
    final m = _meso(s, mon, MesoProgression.weight);
    expect(m.totalWeeks, 5);
    expect(m.lastDay, DateTime(2030, 2, 10));
    expect(m.weekOn(mon), 1);
    expect(m.weekOn(DateTime(2030, 1, 20)), 2);
    expect(m.weekOn(DateTime(2030, 2, 4)), 5);
    expect(m.isDeloadWeek(5), isTrue);
    expect(m.weekOn(DateTime(2030, 2, 11)), isNull);

    final count = s.startMeso(m);
    expect(count, 15); // 3 a week for 5 weeks
    final wed2 = s.plannedOn(DateTime(2030, 1, 16)).single;
    expect(wed2.workoutId, s.workouts[1].id);
    expect(wed2.mesoWeek, 2);
    expect(s.plannedOn(DateTime(2030, 1, 8)), isEmpty); // Tuesday is rest
  });

  test('sets, effort and deload targets', () async {
    final s = await _state();
    final sets = _meso(s, DateTime(2030, 1, 7), MesoProgression.sets);
    expect(s.mesoSets(sets, 1, 3), 3);
    expect(s.mesoSets(sets, 3, 3), 5);
    expect(s.mesoSets(sets, 5, 4), 2); // deload: half of 4
    final effort = _meso(s, DateTime(2030, 1, 7), MesoProgression.effort);
    expect([for (var w = 1; w <= 4; w++) s.mesoRir(effort, w)], [3, 2, 1, 0]);
    expect(s.mesoRir(effort, 5), isNull); // deload
    final weight = _meso(s, DateTime(2030, 1, 7), MesoProgression.weight);
    expect(s.mesoSets(weight, 3, 3), 3);
  });

  test('weight progression adds the step to last week', () async {
    final s = await _state();
    final m = _meso(s, DateTime(2030, 1, 7), MesoProgression.weight);
    s.startMeso(m);
    final bench = s.workouts[0].items.first.exerciseId;
    // A finished week-1 session at 185 lb.
    s.sessions = [
      Session(
        id: 'x1',
        date: DateTime(2030, 1, 7),
        name: 'Upper A',
        workoutId: s.workouts[0].id,
        startedAt: DateTime(2030, 1, 7, 7),
        endedAt: DateTime(2030, 1, 7, 8),
        mesoId: 'm1',
        mesoWeek: 1,
        sets: [SetEntry(exerciseId: bench, weightKg: lbToKg(185), reps: 8, done: true)],
      ),
    ];
    final hint = s.mesoWeightHint(m, 2, bench, 0, lbToKg(185));
    expect(kgToLb(hint!), closeTo(190, 1e-6));
    // Deload: about 10% lighter, rounded to 2.5 lb.
    final deload = s.mesoWeightHint(m, 5, bench, 0, lbToKg(200));
    expect(kgToLb(deload!), closeTo(180, 1e-6));
  });

  test('ending early clears future slots; cancelled blocks are not "past"', () async {
    final s = await _state();
    final today = dateOnly(DateTime.now());
    final started = DateTime(today.year, today.month, today.day - 3);
    final m = Mesocycle(
      id: 'm2',
      name: 'Block 2',
      start: started,
      weeks: 4,
      progression: MesoProgression.sets,
      schedule: {for (var d = 1; d <= 7; d++) d: s.workouts[0].id},
    );
    s.startMeso(m);
    expect(s.activeMeso?.id, 'm2');
    s.endMeso(s.activeMeso!);
    expect(s.planned.where((p) => p.mesoId == 'm2' && p.date.isAfter(today)), isEmpty);
    expect(s.planned.where((p) => p.mesoId == 'm2' && !p.date.isAfter(today)).length, 4);

    final future = Mesocycle(
      id: 'm3',
      name: 'Block 3',
      start: DateTime(today.year, today.month, today.day + 10),
      weeks: 3,
      progression: MesoProgression.weight,
      schedule: {1: s.workouts[0].id},
    );
    s.startMeso(future);
    expect(s.upcomingMeso?.id, 'm3');
    s.endMeso(future);
    expect(s.upcomingMeso, isNull);
    expect(s.pastMesos.any((x) => x.id == 'm3'), isFalse);
    expect(s.planned.where((p) => p.mesoId == 'm3'), isEmpty);
  });

  test('mesocycles survive a backup', () async {
    final s = await _state();
    final m = _meso(s, DateTime(2030, 1, 7), MesoProgression.effort, weeks: 6, deload: false);
    final back = decodeBackup(encodeBackup(StoredData(mesocycles: [m])));
    final b = back.mesocycles.single;
    expect(b.weeks, 6);
    expect(b.deload, isFalse);
    expect(b.progression, MesoProgression.effort);
    expect(b.schedule[3], s.workouts[1].id);
  });

  test('weeks and day counts are right across a clock change', () async {
    // US clocks spring forward on Sunday, March 14, 2027: that day is 23 hours.
    expect(daysBetween(DateTime(2027, 3, 13), DateTime(2027, 3, 15)), 2);
    expect(daysBetween(DateTime(2027, 3, 15), DateTime(2027, 3, 13)), -2);
    expect(daysBetween(DateTime(2027, 11, 6), DateTime(2027, 11, 8)), 2); // fall back
    final s = await _state();
    final m = _meso(s, DateTime(2027, 3, 8), MesoProgression.weight); // a Monday
    expect(m.weekOn(DateTime(2027, 3, 14)), 1); // the Sunday of the change
    expect(m.weekOn(DateTime(2027, 3, 15)), 2); // the next Monday is week 2
    expect(m.weekOn(DateTime(2027, 3, 22)), 3);
  });
}
