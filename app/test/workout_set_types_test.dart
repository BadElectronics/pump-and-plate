import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/workout_editor_screen.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

const _plan = Workout(
  id: 'w-types',
  name: 'Leg day',
  items: [WorkoutItem(exerciseId: 'back_squat', sets: 2)],
);

Future<MemoryStore> _openEditor(WidgetTester tester) async {
  final store = MemoryStore(const StoredData(
    settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true),
    workouts: [_plan],
  ));
  await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  tester.state<NavigatorState>(find.byType(Navigator).first).push(WorkoutEditorScreen.route(_plan));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return store;
}

Future<void> _done(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Done'));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text('Done'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<Workout> _saved(WidgetTester tester, MemoryStore store) async {
  await tester.tap(find.text('Save'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  final s = AppState(store, NoopReminders());
  await s.load();
  return s.workoutById('w-types')!;
}

void main() {
  testWidgets('a set type picked in the workout editor is saved and preset when the workout starts',
      (tester) async {
    final store = await _openEditor(tester);
    expect(find.byKey(const ValueKey('set-type-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('set-type-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('set-type-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Drop set'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Drop set'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('2 D'), findsOneWidget);
    expect(find.textContaining('Set 2: Drop set'), findsOneWidget);

    await _done(tester);
    expect(find.textContaining('set 2 drop set'), findsOneWidget); // the plan's summary line
    final w = await _saved(tester, store);
    expect(w.items.single.setTypes, ['', 'drop']);

    final s = AppState(store, NoopReminders());
    await s.load();
    final x = s.startSession(s.workoutById('w-types'));
    expect(x.sets.map((e) => e.type), [SetType.normal, SetType.drop]);
  });

  testWidgets('dropping a set also drops its set type, and normal sets save as none', (tester) async {
    final store = await _openEditor(tester);
    await tester.tap(find.byKey(const ValueKey('set-type-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Myo-reps'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Myo-reps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.remove_rounded).first); // Sets: 2 → 1
    await tester.pump();
    expect(find.byKey(const ValueKey('set-type-1')), findsNothing);

    await _done(tester);
    final w = await _saved(tester, store);
    expect(w.items.single.sets, 1);
    expect(w.items.single.setTypes, isEmpty);
  });
}
