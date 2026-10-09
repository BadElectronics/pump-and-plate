import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/logger_screen.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

const _plan = Workout(
  id: 'w1',
  name: 'Push',
  items: [WorkoutItem(exerciseId: 'bench_press', sets: 3, repsLow: 6, repsHigh: 10, loadKg: 100, restSec: 120)],
);

Session _live({List<SetEntry>? sets}) => Session(
      id: 's1',
      date: dateOnly(DateTime.now()),
      name: 'Push',
      workoutId: 'w1',
      startedAt: DateTime.now(),
      sets: sets ?? const [
        SetEntry(exerciseId: 'bench_press'),
        SetEntry(exerciseId: 'bench_press'),
        SetEntry(exerciseId: 'bench_press'),
      ],
    );

Future<MemoryStore> _open(WidgetTester tester, Session x, {Units units = Units.metric}) async {
  // A tall screen, so the whole exercise card is on screen.
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final store = MemoryStore(StoredData(
    settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, units: units),
    workouts: const [_plan],
    sessions: [x],
  ));
  await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  tester.state<NavigatorState>(find.byType(Navigator).first).push(LoggerScreen.route(x.id));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return store;
}

Future<Session> _saved(WidgetTester tester, MemoryStore store) async {
  await tester.pump(const Duration(milliseconds: 100));
  return (await store.load()).sessions.single;
}

void main() {
  testWidgets('Add warm-up adds one warm-up set, before the working sets', (tester) async {
    final store = await _open(tester, _live());
    await tester.tap(find.byKey(const ValueKey('warmup-bench_press')));
    await tester.pump();
    var x = await _saved(tester, store);
    expect(x.sets.map((e) => e.type), [SetType.warmup, SetType.normal, SetType.normal, SetType.normal]);
    await tester.tap(find.byKey(const ValueKey('warmup-bench_press')));
    await tester.pump();
    x = await _saved(tester, store);
    expect(x.sets.where((e) => e.warmup), hasLength(2));
    expect(x.sets.take(2).every((e) => e.warmup), isTrue);
    expect(x.sets.first.weightKg, isNull); // you choose the weight
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the target shows, and the weight you use sticks to the next set', (tester) async {
    await _open(tester, _live());
    expect(find.text('Target 100 kg × 6–10 reps'), findsOneWidget);
    expect(find.text('Rest 2:00'), findsOneWidget);
    // Boxes in order: set 1 weight, set 1 reps, set 2 weight...
    expect(tester.widget<TextField>(find.byType(TextField).at(2)).decoration!.hintText, '100');
    await tester.enterText(find.byType(TextField).at(0), '105');
    await tester.pump();
    // Set 2's box now suggests 105, not the plan's 100.
    expect(tester.widget<TextField>(find.byType(TextField).at(2)).decoration!.hintText, '105');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rest taken after a set shows small, during the workout', (tester) async {
    await _open(
      tester,
      _live(sets: const [
        SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 8, done: true, restSec: 125),
        SetEntry(exerciseId: 'bench_press'),
      ]),
    );
    expect(find.text('Rest 2:05'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('locked: taps do nothing until slid open', (tester) async {
    final store = await _open(tester, _live());
    await tester.tap(find.byKey(const ValueKey('lock-workout')));
    await tester.pump();
    expect(find.text('Slide to unlock'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('warmup-bench_press')), warnIfMissed: false);
    await tester.pump();
    expect((await _saved(tester, store)).sets, hasLength(3)); // nothing added
    await tester.drag(find.byKey(const ValueKey('unlock-handle')), const Offset(900, 0));
    await tester.pump();
    expect(find.text('Slide to unlock'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('warmup-bench_press')));
    await tester.pump();
    expect((await _saved(tester, store)).sets, hasLength(4));
    await tester.pump(const Duration(seconds: 1));
  });

  test('notes: kept with each workout; a change carries forward, not back', () async {
    final store = MemoryStore(const StoredData(workouts: [_plan]));
    final s = AppState(store, NoopReminders());
    await s.load();
    s.setExerciseNote('bench_press', 'Pause 1s');
    final a = s.startSession(s.workoutById('w1'));
    expect(a.exerciseNotes, {'bench_press': 'Pause 1s'});
    s.updateSession(a.copyWith(sets: [for (final e in a.sets) e.copyWith(done: true, weightKg: 100.0, reps: 8)]));
    s.finishSession(s.sessions.last);

    final b = s.startSession(s.workoutById('w1'));
    expect(s.sessionNoteFor(b, 'bench_press'), 'Pause 1s'); // defaults to last time
    s.setSessionNote(b, 'bench_press', 'Pause 2s, wider grip');
    expect(s.exercise('bench_press')!.note, 'Pause 2s, wider grip'); // for next time
    final first = s.sessions.first;
    expect(s.sessionNoteFor(first, 'bench_press'), 'Pause 1s'); // the past keeps its note

    // Changing an old workout's note changes only that workout.
    s.setSessionNote(first, 'bench_press', 'Felt heavy');
    expect(s.sessionNoteFor(s.sessions.first, 'bench_press'), 'Felt heavy');
    expect(s.exercise('bench_press')!.note, 'Pause 2s, wider grip');
  });
}
