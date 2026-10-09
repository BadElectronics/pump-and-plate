import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/matcher.dart';
import 'package:fitapp/src/ai/paste_parser.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/muscles.dart';
import 'package:fitapp/src/data/starter.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/chat_screen.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

const _paste = '''Workout A — Full body (2 sets each)
Zercher Squat — 6–10 reps — rest 4:00 — set 2: partials
Your "squat". Full depth.
Flat DB Bench Press — 6–10 reps — rest 3:00 — set 2: drop set
Your "bench".
Weighted Pull-Ups — 5–8 reps — rest 3:00 — set 2: rest-pause
Belt or DB between feet.
DB Romanian Deadlift — 8–12 reps — rest 4:00 — set 2: tech fail
Your "deadlift". Use straps.
Seated DB Overhead Press — 6–10 reps — rest 3:00 — set 2: rest-pause
Bench at about 80°.
Seated Cable Row — 8–12 reps — rest 3:00 — set 2: partials
Skip if short on time.
Set 1: to true failure inside the rep range.
Set 2: to failure, then past it with the tag.
Add weight when you hit the top of the range on both sets.''';

String? _match(String name) {
  final e = bestMatch(exerciseKey(name), starterExercises, (x) => exerciseKey(x.name));
  return e?.id;
}

void main() {
  test('a workout written with dashes, rest and techniques is read fully', () {
    expect(classifyPaste(_paste), PasteKind.workout);
    final d = parseWorkout(_paste);
    expect(d.name, 'Workout A — Full body');
    expect(d.defaultSets, 2);
    expect(d.items.map((i) => i.name), [
      'Zercher Squat', 'Flat DB Bench Press', 'Weighted Pull-Ups', 'DB Romanian Deadlift', 'Seated DB Overhead Press', 'Seated Cable Row',
    ]);
    final squat = d.items.first;
    expect([squat.repsLow, squat.repsHigh, squat.restSec, squat.setTypes], [6, 10, 240, {2: 'partial'}]);
    expect(squat.note, 'Your "squat". Full depth.');
    expect(d.items[1].setTypes, {2: 'drop'});
    expect(d.items[2].setTypes, {2: 'restPause'});
    expect(d.items[3].setTypes, {2: 'failure'}); // "tech fail"
    expect(d.items[5].note, 'Skip if short on time.');
    expect(d.note!.split('\n'), hasLength(3));
    expect(d.note, startsWith('Set 1: to true failure'));
    expect(d.skipped, isEmpty);
  });

  test('exercise names match despite "Flat", "Seated", "Weighted" and "DB"', () {
    expect(_match('Flat DB Bench Press'), 'db_bench');
    expect(_match('Weighted Pull-Ups'), 'pull_up');
    expect(_match('DB Romanian Deadlift'), 'db_rdl');
    expect(_match('Hack Squat'), 'hack_squat'); // built in since 5.14
    expect(_match('Seated DB Overhead Press'), 'db_shoulder_press');
    expect(_match('Seated Cable Row'), 'cable_row');
    expect(_match('OHP'), 'ohp');
    expect(_match('Zercher Squat'), isNull); // not built in: offered to create
    final guess = guessMuscles('Zercher Squat')!;
    expect(guess.primary, [Muscle.quads, Muscle.glutes]);
    expect(groupFor(guess), 'Legs');
  });

  test('notes and set types are kept, and starting the workout presets them', () async {
    const item = WorkoutItem(exerciseId: 'back_squat', sets: 2, note: 'Full depth.', setTypes: ['', 'partial']);
    final back = WorkoutItem.fromJson(item.toJson());
    expect([back.note, back.setTypes], ['Full depth.', ['', 'partial']]);
    expect(item.copyWith(repsLow: 6).setTypes, ['', 'partial']); // editing keeps them
    const w = Workout(id: 'w1', name: 'A', items: [item], note: 'Add weight at the top of the range.');
    expect(Workout.fromRow(w.toRow()).note, w.note);
    expect(w.copyWith(name: 'B').note, w.note);

    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    s.saveWorkout(w);
    final x = s.startSession(s.workoutById('w1'));
    expect(x.sets.map((e) => e.type), [SetType.normal, SetType.partial]);
    expect(s.workoutNoteFor(x, 'back_squat'), 'Full depth.');
  });

  testWidgets('pasted in Chat: matched, Zercher Squat created, saved with everything', (tester) async {
    ChatScreen.clearHistory();
    final store = MemoryStore(const StoredData(settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true)));
    await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Chat'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const ValueKey('chat-input')), _paste);
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The pasted message is tall: bring the card into view first.
    await tester.ensureVisible(find.text('Dumbbell bench press', skipOffstage: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dumbbell bench press', skipOffstage: false), findsOneWidget);
    expect(find.text('Dumbbell shoulder press', skipOffstage: false), findsOneWidget);
    final create = find.byKey(const ValueKey('create-Zercher Squat'), skipOffstage: false);
    await tester.ensureVisible(create);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(create);
    await tester.pump();
    await tester.ensureVisible(find.text('Save workout', skipOffstage: false));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save workout'));
    await tester.pump();
    expect(find.textContaining('Saved "Workout A — Full body"'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100)); // let the saves finish
    final s = AppState(store, NoopReminders());
    await s.load();
    final w = s.workouts.firstWhere((w) => w.name == 'Workout A — Full body');
    expect(w.items, hasLength(6));
    expect(w.items.first.restSec, 240);
    expect(w.items.first.setTypes, ['', 'partial']);
    expect(w.note, contains('Add weight'));
    expect(s.exercises.any((e) => e.name == 'Zercher Squat' && e.custom), isTrue);
  });
}
