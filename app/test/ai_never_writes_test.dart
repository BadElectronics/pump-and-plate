import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/catalog.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/chat_screen.dart';
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

/// Everything stored, reduced to what an action could change.
String _fingerprint(StoredData d) => [
      // Settings as stored, minus the time stamped each time they're written out.
      ({...d.settings.toRow()}..remove('updated_at')),
      '${d.goal.mode}/${d.goal.targetWeightKg}/${d.goal.paceKgPerWeek}/${d.goal.proteinGPerKg}',
      for (final w in d.weighIns) '${w.date}:${w.weightKg}',
      for (final e in d.sleep) '${e.date}:${e.durationMin}:${e.quality}',
      for (final x in d.sessions) '${x.id}:${[for (final e in x.sets) '${e.exerciseId}/${e.weightKg}/${e.reps}']}',
      d.weighIns.length, d.sleep.length, d.water.length, d.photos.length, d.measurements.length,
      d.stores.length, d.recipes.length, d.groceryMarks.length, d.phases.length, d.foods.length,
      for (final e in d.exercises) e.id,
      for (final w in d.workouts) '${w.id}:${w.name}:${[for (final i in w.items) '${i.exerciseId}/${i.sets}/${i.repsLow}/${i.repsHigh}/${i.restSec}']}',
      for (final x in d.sessions) x.id,
      for (final p in d.planned) p.id,
      for (final e in d.foodLog) '${e.id}:${e.meal}:${e.amount}:${e.date}',
      for (final p in d.plannedMeals) p.id,
      for (final m in d.mesocycles) m.id,
      for (final g in d.groceryItems) g.id,
    ].join('|');

/// Every AI tool, asked to do something real.
const _calls = [
  AiCall('make_recipe', {'name': 'Overnight oats', 'servings': 2, 'ingredients': ['100 g oats', '300 ml milk']}),
  AiCall('make_workout', {'name': 'Arms', 'exercises': ['Barbell curl 3x10', 'Dip 3x8']}),
  AiCall('log_food', {'items': ['2 eggs'], 'meal': 'breakfast'}),
  AiCall('log_weight', {'value': 80, 'unit': 'kg'}),
  AiCall('log_sleep', {'hours': 7.5, 'quality': 4}),
  AiCall('log_water', {'amount': 500, 'unit': 'ml'}),
  AiCall('plan_workout', {'workout': 'Push day', 'day': 'tomorrow'}),
  AiCall('plan_meal', {'items': ['1 egg'], 'meal': 'breakfast', 'day': 'tomorrow'}),
  AiCall('start_workout', {'workout': 'push'}),
  AiCall('add_exercise_to_workout', {'workout': 'push', 'exercise': 'Lateral raise 3x12'}),
  AiCall('remove_exercise_from_workout', {'workout': 'push', 'exercise': 'overhead press'}),
  AiCall('change_exercise_in_workout', {'workout': 'push', 'exercise': 'bench', 'sets': 5, 'rest_seconds': 240}),
  AiCall('start_mesocycle', {'workouts': ['push'], 'weeks': 4, 'progression': 'weight'}),
  AiCall('move_food', {'day': 'yesterday', 'meal': 'lunch', 'to_meal': 'dinner'}),
  AiCall('delete_food', {'day': 'yesterday'}),
  AiCall('change_food_amount', {'day': 'yesterday', 'food': 'rice', 'servings': 2}),
  AiCall('add_groceries', {'items': ['12 eggs', 'paper towels']}),
  AiCall('set_goal', {'mode': 'gain', 'target_weight': 190, 'pace_per_week': 0.5}),
  AiCall('set_protein_target', {'grams_per_lb': 1}),
  AiCall('set_units', {'units': 'metric'}),
  AiCall('set_theme', {'theme': 'night', 'dark_at_night': 'phone'}),
  AiCall('set_reminder', {'time': '6:45 am'}),
  AiCall('set_water_goal', {'amount': 3, 'unit': 'l'}),
  AiCall('set_sleep_goal', {'hours': 8.5}),
  AiCall('set_week_start', {'day': 'monday'}),
  AiCall('change_weight', {'day': 'yesterday', 'value': 181}),
  AiCall('delete_weight', {'day': 'yesterday'}),
  AiCall('change_sleep', {'day': 'yesterday', 'hours': 8, 'quality': 5}),
  AiCall('delete_sleep', {'day': 'yesterday'}),
  AiCall('change_set', {'day': 'yesterday', 'exercise': 'bench', 'set_number': 1, 'weight': 230, 'reps': 5}),
  AiCall('delete_set', {'day': 'yesterday', 'exercise': 'bench', 'set_number': 1}),
  AiCall('delete_workout_session', {'day': 'yesterday'}),
];

void main() {
  for (final call in _calls) {
    testWidgets('${call.name}: shows a card and changes nothing on its own', (tester) async {
      final store = MemoryStore(const StoredData(
        settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true),
        workouts: [
          Workout(id: 'w-push', name: 'Push day', items: [
            WorkoutItem(exerciseId: 'bench_press', sets: 3),
            WorkoutItem(exerciseId: 'ohp', sets: 3),
          ]),
        ],
      ));
      final seed = AppState(store, NoopReminders());
      await seed.load();
      final t = dateOnly(DateTime.now());
      final y = DateTime(t.year, t.month, t.day - 1);
      seed.logQuick(y, Meal.lunch, 'Rice bowl', const Macros(kcal: 600, protein: 30));
      seed.logWeight(82, day: y);
      seed.logSleep(SleepEntry(date: y, durationMin: 420, quality: 3));
      seed.restoreSession(Session(
        id: 's1', date: y, name: 'Push day', startedAt: y.add(const Duration(hours: 9)), endedAt: y.add(const Duration(hours: 10)),
        sets: const [SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 5, done: true)],
      ));
      await seed.settle();
      final before = _fingerprint(await store.load());

      ChatScreen.clearHistory();
      await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders(), ai: _CallingEngine(call)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Chat'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const ValueKey('chat-input')), 'please do it');
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // A card (or a question back) is on screen, and the data is untouched.
      expect(tester.takeException(), isNull);
      expect(_fingerprint(await store.load()), before);
    });
  }
}
