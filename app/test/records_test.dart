import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

/// A finished session [daysAgo] days back with the given sets.
Session _session(String id, int daysAgo, List<SetEntry> sets) {
  final t = dateOnly(DateTime.now());
  final d = DateTime(t.year, t.month, t.day - daysAgo);
  return Session(
    id: id, date: d, name: 'Workout',
    startedAt: d.add(const Duration(hours: 9)), endedAt: d.add(const Duration(hours: 10)),
    sets: sets,
  );
}

Future<AppState> _state(List<Session> sessions) async {
  final s = AppState(MemoryStore(const StoredData(settings: AppSettings(onboarded: true))), NoopReminders());
  await s.load();
  for (final x in sessions) {
    s.restoreSession(x);
  }
  await s.settle();
  return s;
}

void main() {
  test('high-rep sets count toward e1RM, so a heavier set raises it (seated row)', () async {
    final s = await _state([
      _session('last', 7, [SetEntry(exerciseId: 'seated_row', weightKg: lbToKg(100), reps: 19, done: true)]),
      _session('this', 0, [SetEntry(exerciseId: 'seated_row', weightKg: lbToKg(115), reps: 15, done: true)]),
    ]);
    final before = s.bestE1rm('seated_row', exceptSession: 'this')!;
    final now = s.setE1rm(s.sessions.firstWhere((x) => x.id == 'this').sets.single, DateTime.now())!;
    expect(before / kgPerLb, closeTo(133.33, 0.01));
    expect(now / kgPerLb, closeTo(153.33, 0.01));
    expect(now, greaterThan(before));
  });

  test('best reps at a weight finds the earlier 12 at 45 lb, ignoring other weights and warm-ups', () async {
    final s = await _state([
      _session('a', 14, [
        SetEntry(exerciseId: 'db_bench', weightKg: lbToKg(45), reps: 12, done: true),
        SetEntry(exerciseId: 'db_bench', weightKg: lbToKg(50), reps: 20, done: true),
        SetEntry(exerciseId: 'db_bench', weightKg: lbToKg(45), reps: 25, done: true, type: SetType.warmup),
      ]),
      _session('b', 0, [SetEntry(exerciseId: 'db_bench', weightKg: lbToKg(45), reps: 18, done: true)]),
    ]);
    expect(s.bestRepsAt('db_bench', lbToKg(45), exceptSession: 'b'), 12);
    expect(s.bestRepsAt('db_bench', lbToKg(40), exceptSession: 'b'), isNull);
    // 45 x 18 and 45 x 12 give the same e1RM, which is why the rep record is
    // what celebrates it.
    expect(s.setE1rm(s.sessions.firstWhere((x) => x.id == 'b').sets.single, DateTime.now()),
        closeTo(e1rm(lbToKg(45), 12)!, 1e-9));
  });

  test('bodyweight with nothing added matches an empty weight', () async {
    final s = await _state([
      _session('a', 7, [const SetEntry(exerciseId: 'pull_up', reps: 5, done: true)]),
    ]);
    expect(s.bestRepsAt('pull_up', 0), 5);
    expect(s.bestRepsAt('pull_up', null), 5);
  });
}
