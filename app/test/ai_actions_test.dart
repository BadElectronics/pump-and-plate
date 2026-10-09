import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/catalog.dart';
import 'package:fitapp/src/ai/router.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/chat_screen.dart';
import 'package:fitapp/src/screens/logger_screen.dart';
import 'package:fitapp/src/services/ai_engine.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

/// An AI engine whose every answer is one function call.
class _CallingEngine implements AiEngine {
  _CallingEngine(this.call);
  final AiCall call;
  AiTier? _loaded;
  @override
  bool get available => true;
  @override
  Future<bool> isInstalled(AiModelInfo m) async => true;
  @override
  Future<void> download(AiModelInfo m, {required void Function(int percent) onProgress, required AiCancel cancel}) async {}
  @override
  Future<void> importFile(AiModelInfo m, String path) async {}
  @override
  Future<void> remove(AiModelInfo m) async {}
  @override
  Future<AiChat> openChat(AiModelInfo m, {required String system, List<AiTool> tools = const []}) async {
    _loaded = m.tier;
    return _CallingChat(call);
  }
  @override
  AiTier? get loadedTier => _loaded;
  @override
  Future<void> warmUp(AiModelInfo m) async {
    _loaded = m.tier;
  }
  @override
  Future<void> unload() async {
    _loaded = null;
  }
  @override
  Future<void> unloadWhenIdle() => unload();
  @override
  void scheduleIdleUnload(Duration after) {}
  @override
  void cancelIdleUnload() {}
  @override
  Future<void> forceUnload() => unload();
}

class _CallingChat implements AiChat {
  _CallingChat(this.call);
  final AiCall call;
  @override
  Stream<AiEvent> send(String text) => Stream.fromIterable([call]);
  @override
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

const _push = Workout(id: 'w-push', name: 'Push day', items: [
  WorkoutItem(exerciseId: 'bench_press', sets: 3, repsLow: 6, repsHigh: 8),
  WorkoutItem(exerciseId: 'ohp', sets: 3),
]);

Future<MemoryStore> _openChat(WidgetTester tester, AiCall call, {MemoryStore? store}) async {
  ChatScreen.clearHistory();
  final st = store ??
      MemoryStore(const StoredData(
        settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true),
        workouts: [_push],
      ));
  await tester.pumpWidget(FitApp(store: st, reminders: NoopReminders(), ai: _CallingEngine(call)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Chat'), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 200));
  return st;
}

Future<void> _say(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(text));
  await tester.pump();
}

void main() {
  test('messages go to the right part of the app', () {
    expect(routeMessage('start push day'), AiArea.training);
    expect(routeMessage('add another set of bench to my workout'), AiArea.training);
    expect(routeMessage("delete yesterday's lunch"), AiArea.food);
    expect(routeMessage('add eggs and rice to my grocery list'), AiArea.food);
    expect(routeMessage('how am I doing?'), AiArea.general);
    expect(routeMessage('set my goal to 175 lb'), AiArea.goals);
    expect(routeMessage('switch to metric units'), AiArea.goals);
    expect(routeMessage('remind me to weigh in at 7am'), AiArea.goals);
    expect(routeMessage("fix yesterday's weigh-in, it was 181"), AiArea.data);
    expect(routeMessage("delete monday's sleep"), AiArea.data);
    expect(routeMessage('change set 2 of bench on monday to 230 for 5'), AiArea.data);
    expect(routeMessage('change bench to 4 sets in push day'), AiArea.training); // the plan, not a logged set
    expect(routeMessage("delete yesterday's lunch"), AiArea.food);
  });

  test('days already logged', () {
    final sunday = DateTime(2026, 10, 4);
    expect(pastDayOffset('yesterday', sunday), -1);
    expect(pastDayOffset('the day before yesterday', sunday), -2);
    expect(pastDayOffset('monday', sunday), -6); // the most recent Monday
    expect(pastDayOffset('sunday', sunday), 0);
    expect(pastDayOffset('3 days ago', sunday), -3);
    expect(pastDayOffset('2026-10-01', sunday), -3);
    expect(pastDayOffset('whenever', sunday), isNull);
  });

  testWidgets('start a workout: a card, then the workout opens', (tester) async {
    await _openChat(tester, const AiCall('start_workout', {'workout': 'push'}));
    await _say(tester, 'start push day');
    expect(find.text('START A WORKOUT'), findsOneWidget);
    expect(find.textContaining('Bench press'), findsOneWidget);
    await _tap(tester, 'Start');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LoggerScreen), findsOneWidget);
  });

  testWidgets("delete yesterday's lunch, then undo", (tester) async {
    final store = MemoryStore(const StoredData(
      settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true),
    ));
    final seed = AppState(store, NoopReminders());
    await seed.load();
    final t = dateOnly(DateTime.now());
    final yesterday = DateTime(t.year, t.month, t.day - 1);
    seed.logQuick(yesterday, Meal.lunch, 'Rice bowl', const Macros(kcal: 600, protein: 30));
    seed.logQuick(yesterday, Meal.lunch, 'Iced tea', const Macros(kcal: 90));
    seed.logQuick(yesterday, Meal.dinner, 'Steak', const Macros(kcal: 700, protein: 60));
    await seed.settle();
    await _openChat(tester, const AiCall('delete_food', {'day': 'yesterday', 'meal': 'lunch'}), store: store);
    await _say(tester, "delete yesterday's lunch");
    expect(find.text('DELETE FOOD'), findsOneWidget);
    expect(find.textContaining('Rice bowl'), findsOneWidget);
    expect(find.textContaining('Steak'), findsNothing); // dinner isn't touched
    await _tap(tester, 'Delete 2');
    expect(find.text('Deleted 2 items.'), findsOneWidget);
    await _tap(tester, 'Undo');
    expect(find.text('Undone.'), findsOneWidget);
  });

  testWidgets('change an exercise in a workout', (tester) async {
    final store = await _openChat(
      tester,
      const AiCall('change_exercise_in_workout', {'workout': 'push day', 'exercise': 'bench', 'sets': 4}),
    );
    await _say(tester, 'make bench 4 sets in my push workout');
    expect(find.text('CHANGE BENCH PRESS IN PUSH DAY'), findsOneWidget);
    expect(find.text('Sets: 3 → 4'), findsOneWidget);
    await _tap(tester, 'Change');
    expect(find.text('Updated Bench press in Push day.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    final s = AppState(store, NoopReminders());
    await s.load();
    expect(s.workoutById('w-push')!.items.first.sets, 4);
    expect(s.workoutById('w-push')!.items, hasLength(2)); // nothing else changed
  });

  testWidgets('change the goal, then undo', (tester) async {
    final store = await _openChat(tester, const AiCall('set_goal', {'mode': 'gain', 'target_weight': 190}));
    await _say(tester, 'change my goal to gaining up to 190');
    expect(find.text('CHANGE YOUR GOAL'), findsOneWidget);
    expect(find.text('Goal: lose → gain weight'), findsOneWidget);
    await _tap(tester, 'Change');
    await tester.pump(const Duration(milliseconds: 100));
    var s = AppState(store, NoopReminders());
    await s.load();
    expect(s.goal.mode, GoalMode.gain);
    await _tap(tester, 'Undo');
    await tester.pump(const Duration(milliseconds: 100));
    s = AppState(store, NoopReminders());
    await s.load();
    expect(s.goal.mode, GoalMode.lose);
  });

  testWidgets('fix a logged set', (tester) async {
    final store = MemoryStore(const StoredData(
      settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true, units: Units.metric),
    ));
    final seed = AppState(store, NoopReminders());
    await seed.load();
    final t = dateOnly(DateTime.now());
    final y = DateTime(t.year, t.month, t.day - 1);
    seed.restoreSession(Session(
      id: 's1', date: y, name: 'Push day', startedAt: y.add(const Duration(hours: 9)), endedAt: y.add(const Duration(hours: 10)),
      sets: const [
        SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 5, done: true),
        SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 4, done: true),
      ],
    ));
    await seed.settle();
    await _openChat(tester, const AiCall('change_set', {'day': 'yesterday', 'exercise': 'bench', 'set_number': 2, 'weight': 102.5, 'reps': 5}),
        store: store);
    await _say(tester, "fix yesterday's second bench set: 102.5 for 5");
    expect(find.textContaining('100 kg × 4 → 102.5 kg × 5'), findsOneWidget);
    await _tap(tester, 'Fix');
    await tester.pump(const Duration(milliseconds: 100));
    final s = AppState(store, NoopReminders());
    await s.load();
    final sets = s.sessions.single.sets;
    expect([sets[0].weightKg, sets[0].reps, sets[1].weightKg, sets[1].reps], [100, 5, 102.5, 5]);
  });

  testWidgets("delete a night's sleep, then undo", (tester) async {
    final store = MemoryStore(const StoredData(
      settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true),
    ));
    final seed = AppState(store, NoopReminders());
    await seed.load();
    seed.logSleep(SleepEntry(date: dateOnly(DateTime.now()), durationMin: 400, quality: 3));
    await seed.settle();
    await _openChat(tester, const AiCall('delete_sleep', {'day': 'last night'}), store: store);
    await _say(tester, "delete last night's sleep");
    expect(find.text('DELETE SLEEP'), findsOneWidget);
    await _tap(tester, 'Delete');
    await tester.pump(const Duration(milliseconds: 100));
    expect((await store.load()).sleep, isEmpty);
    await _tap(tester, 'Undo');
    await tester.pump(const Duration(milliseconds: 100));
    expect((await store.load()).sleep.single.durationMin, 400);
  });
}
