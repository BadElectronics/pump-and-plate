import 'dart:io';

import 'package:flutter/widgets.dart';

import '../calc/barcode.dart';
import '../calc/calc.dart';
import '../data/backup.dart';
import '../data/food_share.dart';
import '../data/models.dart';
import '../data/starter.dart';
import '../data/starter_foods.dart';
import '../data/store.dart';
import '../data/usda.dart';
import '../services/photo_files.dart';
import '../services/reminders.dart';

class DailyTargets {
  const DailyTargets({
    required this.bmr,
    required this.maintenanceKcal,
    required this.kcal,
    required this.floored,
    required this.proteinG,
    required this.goalDate,
    this.learned = false,
  });

  final double bmr;
  final double maintenanceKcal;

  /// Maintenance came from your own food and weight logs.
  final bool learned;
  final double kcal;
  final bool floored;
  final double proteinG;
  final DateTime? goalDate;
}

String _one(double v) => v.toStringAsFixed(1);

/// 2.5 -> "2.5", 5.0 -> "5", 2.27 -> "2.27" (two decimals at most).
String _step(double v) =>
    v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

/// One week at a glance (Monday to Sunday).
class WeekSummary {
  const WeekSummary({
    required this.start,
    required this.avgWeightKg,
    required this.prevAvgWeightKg,
    required this.workouts,
    required this.workoutsPlanned,
    required this.avgSleepMin,
    required this.foodDays,
    required this.avgKcal,
    required this.targetKcal,
    required this.proteinDaysHit,
    required this.phase,
  });

  final DateTime start;
  final double? avgWeightKg;
  final double? prevAvgWeightKg;
  final int workouts;
  final int workoutsPlanned;
  final double? avgSleepMin;
  final int foodDays;
  final double? avgKcal;
  final double? targetKcal;
  final int proteinDaysHit;
  final Phase? phase;

  DateTime get end => DateTime(start.year, start.month, start.day + 6);

  double? get weightChangeKg {
    final a = avgWeightKg;
    final b = prevAvgWeightKg;
    return a == null || b == null ? null : a - b;
  }

  bool get hasData => avgWeightKg != null || workouts > 0 || avgSleepMin != null || foodDays > 0;
}

/// Holds everything the screens show. Changes save to the store right away.
class AppState extends ChangeNotifier {
  AppState(this._store, this.reminders);

  final Store _store;
  final Reminders reminders;

  bool loaded = false;
  Profile profile = const Profile();
  Goal goal = const Goal();
  AppSettings settings = const AppSettings();
  List<WeighIn> weighIns = const [];
  List<SleepEntry> sleep = const [];
  List<WaterEntry> water = const [];
  List<Supplement> supplements = const [];
  List<SupplementDose> doses = const [];
  List<PhotoCheckin> photos = const [];
  List<Measurement> measurements = const [];
  List<Exercise> exercises = const [];
  List<Workout> workouts = const [];
  List<Session> sessions = const [];
  List<PlannedWorkout> planned = const [];
  List<Food> foods = const [];
  List<GroceryStore> stores = const [];
  List<Recipe> recipes = const [];
  List<FoodEntry> foodLog = const [];
  List<PlannedMeal> plannedMeals = const [];
  List<GroceryMark> groceryMarks = const [];
  List<Phase> phases = const [];
  List<Mesocycle> mesocycles = const [];
  List<GroceryItem> groceryItems = const [];

  /// Folder holding photo files; null until known (and in tests).
  String? photosDir;

  void setPhotosDir(String dir) {
    photosDir = dir;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final data = await _store.load();
      profile = data.profile;
      goal = data.goal;
      settings = data.settings;
      weighIns = data.weighIns;
      sleep = data.sleep;
      water = data.water;
      supplements = [...data.supplements]..sort((a, b) => a.order.compareTo(b.order));
      doses = data.doses;
      photos = data.photos;
      measurements = data.measurements;
      exercises = data.exercises;
      workouts = data.workouts;
      sessions = data.sessions;
      planned = data.planned;
      foods = data.foods;
      stores = [...data.stores]..sort((a, b) => a.sort.compareTo(b.sort));
      recipes = data.recipes;
      foodLog = data.foodLog;
      plannedMeals = data.plannedMeals;
      groceryMarks = data.groceryMarks;
      phases = [...data.phases]..sort((a, b) => a.start.compareTo(b.start));
      mesocycles = [...data.mesocycles]..sort((a, b) => a.start.compareTo(b.start));
      groceryItems = data.groceryItems;
    } catch (e) {
      debugPrint('Loading saved data failed: $e');
    }
    // Load any starter exercises not yet in the library (all of them on
    // first run; new ones like cardio after an update).
    final have = {for (final e in exercises) e.id};
    final missing = [
      for (final e in starterExercises)
        if (!have.contains(e.id)) e,
    ];
    if (missing.isNotEmpty) {
      exercises = [...exercises, ...missing];
      for (final e in missing) {
        _save(() => _store.saveExercise(e));
      }
    }
    // Starter foods not yet in the list.
    final haveFoods = {for (final f in foods) f.id};
    final newFoods = [
      for (final f in starterFoods)
        if (!haveFoods.contains(f.id)) f,
    ];
    if (newFoods.isNotEmpty) {
      foods = [...foods, ...newFoods];
      for (final f in newFoods) {
        _save(() => _store.saveFood(f));
      }
    }
    // The old waist field on Goals moves into body measurements.
    final oldWaist = profile.waistCm;
    if (oldWaist != null) {
      if (latestMeasurement(MeasureSite.waist) == null) {
        final m = Measurement(
          date: dateOnly(DateTime.now()),
          site: MeasureSite.waist,
          valueCm: oldWaist,
        );
        measurements = [...measurements, m];
        _save(() => _store.saveMeasurement(m));
      }
      profile = profile.copyWith(waistCm: null);
      _save(() => _store.saveProfile(profile));
    }
    // People who set up their profile before first-run setup existed
    // shouldn't see it now.
    if (!settings.onboarded && profile.birthday != null) {
      settings = settings.copyWith(onboarded: true);
      _save(() => _store.saveSettings(settings));
    }
    loaded = true;
    notifyListeners();
    _syncReminder();
  }

  /// Keeps the scheduled reminder in step with settings and today's log.
  void _syncReminder() {
    reminders.schedule(
      settings.reminderMinute,
      skipToday: weighInOn(DateTime.now()) != null,
    );
  }

  final Set<Future<void>> _pendingSaves = {};

  /// Why the last save failed, while it's unresolved (the app shows a
  /// warning). Changes stay in memory meanwhile; [retrySaves] writes them.
  SaveProblem? saveProblem;

  /// Deletions that failed, replayed (in order) by [retrySaves].
  final List<Future<void> Function()> _failedDeletes = [];

  /// [write] is run now, and again by [retrySaves] if it was a deletion.
  /// Every change to stored data goes through [_save], so this counts them
  /// all. Chat checks it around AI tool calls: the AI may only prepare cards;
  /// data changes only when the user taps the card's button.
  int get writeCount => _writeCount;
  int _writeCount = 0;

  void _save(Future<void> Function() write, {bool delete = false}) {
    _writeCount++;
    final f = Future<void>.sync(write).catchError((Object e) {
      debugPrint('Saving failed: $e');
      if (delete) _failedDeletes.add(write);
      _saveFailed(e);
    });
    _pendingSaves.add(f);
    f.whenComplete(() => _pendingSaves.remove(f));
  }

  void _saveFailed(Object e) {
    final p = isStorageFull(e) ? SaveProblem.full : SaveProblem.other;
    if (saveProblem == p) return;
    saveProblem = p;
    notifyListeners();
  }

  /// After a failed save (say, once space is freed): replays failed
  /// deletions, then writes everything currently in memory, so what's saved
  /// matches what's on screen. Deletions go first so something deleted and
  /// then added again (today's weigh-in) ends up saved. True if it all worked.
  Future<bool> retrySaves() async {
    try {
      for (final d in List.of(_failedDeletes)) {
        await d();
        _failedDeletes.remove(d);
      }
      await _store.saveProfile(profile);
      await _store.saveGoal(goal);
      await _store.saveSettings(settings);
      for (final x in weighIns) {
        await _store.saveWeighIn(x);
      }
      for (final x in sleep) {
        await _store.saveSleep(x);
      }
      for (final x in photos) {
        await _store.savePhoto(x);
      }
      for (final x in measurements) {
        await _store.saveMeasurement(x);
      }
      for (final x in exercises) {
        await _store.saveExercise(x);
      }
      for (final x in workouts) {
        await _store.saveWorkout(x);
      }
      for (final x in sessions) {
        await _store.saveSession(x);
      }
      for (final x in planned) {
        await _store.savePlanned(x);
      }
      for (final x in foods) {
        await _store.saveFood(x);
      }
      for (final x in stores) {
        await _store.saveStore(x);
      }
      for (final x in recipes) {
        await _store.saveRecipe(x);
      }
      for (final x in foodLog) {
        await _store.saveEntry(x);
      }
      for (final x in plannedMeals) {
        await _store.savePlannedMeal(x);
      }
      for (final x in groceryMarks) {
        await _store.saveGroceryMark(x);
      }
      for (final x in phases) {
        await _store.savePhase(x);
      }
      for (final x in mesocycles) {
        await _store.saveMeso(x);
      }
      for (final x in groceryItems) {
        await _store.saveGroceryItem(x);
      }
      for (final x in water) {
        await _store.saveWater(x);
      }
      for (final x in supplements) {
        await _store.saveSupplement(x);
      }
      for (final x in doses) {
        await _store.saveDose(x);
      }
    } catch (e) {
      debugPrint('Saving again failed: $e');
      saveProblem = isStorageFull(e) ? SaveProblem.full : SaveProblem.other;
      notifyListeners();
      return false;
    }
    saveProblem = null;
    notifyListeners();
    return true;
  }

  /// Waits until every change made so far has been written. A widget tap
  /// handled in the background must finish saving before it ends.
  Future<void> settle() async {
    while (_pendingSaves.isNotEmpty) {
      await Future.wait(List.of(_pendingSaves));
    }
  }

  void setProfile(Profile value) {
    profile = value;
    notifyListeners();
    _save(() => _store.saveProfile(value));
  }

  void setGoal(Goal value) {
    goal = value;
    notifyListeners();
    _save(() => _store.saveGoal(value));
  }

  void setSettings(AppSettings value) {
    final reminderChanged = value.reminderMinute != settings.reminderMinute;
    settings = value;
    notifyListeners();
    _save(() => _store.saveSettings(value));
    if (reminderChanged) _syncReminder();
  }

  // ------------------------------------------------------------ training

  Exercise? exercise(String id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  String exerciseName(String id) => exercise(id)?.name ?? 'Exercise';

  void saveExercise(Exercise e) {
    exercises = [
      for (final x in exercises)
        if (x.id != e.id) x,
      e,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    _save(() => _store.saveExercise(e));
  }

  void saveWorkout(Workout w) {
    final exists = workouts.any((x) => x.id == w.id);
    workouts = exists
        ? [for (final x in workouts) x.id == w.id ? w : x]
        : [...workouts, w.copyWith(sort: workouts.length)];
    notifyListeners();
    _save(() => _store.saveWorkout(exists ? w : workouts.last));
  }

  void deleteWorkout(Workout w) {
    workouts = [
      for (final x in workouts)
        if (x.id != w.id) x,
    ];
    // Future calendar slots for it go too; past days keep their history.
    final today = dateOnly(DateTime.now());
    final gone = [
      for (final p in planned)
        if (p.workoutId == w.id && !p.date.isBefore(today)) p,
    ];
    planned = [
      for (final p in planned)
        if (!gone.contains(p)) p,
    ];
    notifyListeners();
    _save(() => _store.deleteWorkout(w), delete: true);
    for (final p in gone) {
      _save(() => _store.deletePlanned(p), delete: true);
    }
  }

  void reorderWorkouts(int oldIndex, int newIndex) {
    final list = [...workouts];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    workouts = [for (var i = 0; i < list.length; i++) list[i].copyWith(sort: i)];
    notifyListeners();
    for (final w in workouts) {
      _save(() => _store.saveWorkout(w));
    }
  }

  void addStarterPlan() {
    for (final w in starterPlan()) {
      saveWorkout(w);
    }
  }

  /// For a workout's items: each index's superset position, as
  /// (groupStart, groupEnd) indexes, or null when not in a superset.
  static List<(int, int)?> supersetSpans(List<WorkoutItem> items) {
    final out = List<(int, int)?>.filled(items.length, null);
    var i = 0;
    while (i < items.length) {
      var j = i;
      while (j < items.length - 1 && items[j].linkNext) {
        j++;
      }
      if (j > i) {
        for (var k = i; k <= j; k++) {
          out[k] = (i, j);
        }
      }
      i = j + 1;
    }
    return out;
  }

  bool isCardio(String exerciseId) => exercise(exerciseId)?.cardio ?? false;

  /// Rough length of a workout: lifting sets plus planned cardio minutes.
  int minutesFor(List<WorkoutItem> items) {
    var cardio = 0;
    final lifts = <(int, int)>[];
    for (final i in items) {
      if (isCardio(i.exerciseId)) {
        cardio += i.targetMin ?? 20;
      } else {
        lifts.add((i.sets, i.restSec));
      }
    }
    return estimateMinutes(lifts) + cardio;
  }

  void setExerciseNote(String exerciseId, String? note) {
    final e = exercise(exerciseId);
    if (e == null) return;
    final n = note?.trim();
    saveExercise(e.copyWith(note: n == null || n.isEmpty ? null : n));
  }

  /// The note for [exerciseId] in workout [x]: the one kept with it, or (for
  /// workouts from before notes were kept) none once it's finished, and your
  /// exercise's current note while it's in progress.
  String? sessionNoteFor(Session x, String exerciseId) {
    if (x.exerciseNotes.containsKey(exerciseId)) return x.exerciseNotes[exerciseId];
    return x.finished ? null : exercise(exerciseId)?.note;
  }

  /// Changes the note in workout [x]. In a workout in progress it also
  /// becomes the exercise's note for next time; in one already done, only
  /// that workout changes.
  void setSessionNote(Session x, String exerciseId, String? note) {
    final n = note?.trim();
    final notes = {...x.exerciseNotes};
    if (n == null || n.isEmpty) {
      notes.remove(exerciseId);
    } else {
      notes[exerciseId] = n;
    }
    final fresh = sessions.firstWhere((y) => y.id == x.id, orElse: () => x);
    updateSession(fresh.copyWith(exerciseNotes: notes));
    if (!x.finished) setExerciseNote(exerciseId, n);
  }

  /// A workout started but not finished, if any.
  Session? get activeSession {
    for (final x in sessions.reversed) {
      if (!x.finished) return x;
    }
    return null;
  }

  List<Session> get finishedSessions => [
        for (final x in sessions)
          if (x.finished) x,
      ];

  Session startSession(Workout? w) {
    final now = DateTime.now();
    // A workout that's part of the running mesocycle gets that week's sets.
    final meso = w == null ? null : mesoFor(w.id, now);
    final week = meso?.weekOn(now);
    int setsFor(WorkoutItem item) {
      if (isCardio(item.exerciseId)) return 1;
      if (meso == null || week == null) return item.sets;
      return mesoSets(meso, week, item.sets);
    }

    final x = Session(
      id: newId('s'),
      date: dateOnly(now),
      name: w?.name ?? 'Workout',
      workoutId: w?.id,
      startedAt: now,
      mesoId: meso?.id,
      mesoWeek: week,
      // Notes as they are today, kept with this workout.
      exerciseNotes: {
        if (w != null)
          for (final item in w.items)
            if (exercise(item.exerciseId)?.note case final String n) item.exerciseId: n,
      },
      sets: [
        if (w != null)
          for (final item in w.items)
            for (var i = 0; i < setsFor(item); i++)
              SetEntry(exerciseId: item.exerciseId, type: setTypeByName(item.setTypeAt(i))),
      ],
    );
    sessions = [...sessions, x];
    notifyListeners();
    _save(() => _store.saveSession(x));
    return x;
  }

  void updateSession(Session x) {
    sessions = [for (final y in sessions) y.id == x.id ? x : y];
    notifyListeners();
    _save(() => _store.saveSession(x));
  }

  /// Keeps the done sets. A workout with none is discarded. A rest still
  /// running after the last set isn't recorded.
  void finishSession(Session x) {
    final kept = [
      for (final set in x.sets)
        if (set.done) set.resting ? set.copyWith(restStartedAt: null) : set,
    ];
    if (kept.isEmpty) {
      discardSession(x);
      return;
    }
    // Keep each exercise's note as it was for this workout.
    final notes = {...x.exerciseNotes};
    for (final set in kept) {
      if (notes.containsKey(set.exerciseId)) continue;
      final n = exercise(set.exerciseId)?.note;
      if (n != null) notes[set.exerciseId] = n;
    }
    updateSession(x.copyWith(endedAt: DateTime.now(), sets: kept, exerciseNotes: notes));
  }

  /// Puts back a session that was deleted (Undo).
  void restoreSession(Session x) {
    if (sessions.any((y) => y.id == x.id)) return;
    sessions = [...sessions, x]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    notifyListeners();
    _save(() => _store.saveSession(x));
  }

  void discardSession(Session x) {
    sessions = [
      for (final y in sessions)
        if (y.id != x.id) y,
    ];
    notifyListeners();
    _save(() => _store.deleteSession(x), delete: true);
  }

  /// Body weight to use on [day]: that day's weigh-in, or the latest before.
  double? bodyweightOn(DateTime day) {
    final d = dateOnly(day);
    double? best;
    for (final w in weighIns) {
      if (!w.date.isAfter(d)) best = w.weightKg;
    }
    return best ?? currentWeightKg;
  }

  /// Total load moved in a set: body weight plus added weight for
  /// bodyweight exercises.
  double? loadOf(SetEntry set, DateTime day) {
    final ex = exercise(set.exerciseId);
    if (ex != null && ex.bodyweight) {
      final bw = bodyweightOn(day);
      if (bw == null) return null;
      return bw + (set.weightKg ?? 0);
    }
    return set.weightKg;
  }

  double? setE1rm(SetEntry set, DateTime day) {
    // Warm-ups, drop sets, partials and myo-reps aren't used for records.
    if (!set.done || !set.type.countsForRecords || set.reps == null || isCardio(set.exerciseId)) return null;
    final load = loadOf(set, day);
    return load == null ? null : e1rm(load, set.reps!);
  }

  /// Working sets of [exerciseId] from the most recent finished session
  /// that had any (excluding [exceptSession]).
  List<SetEntry> lastSetsFor(String exerciseId, {String? exceptSession}) {
    for (final x in sessions.reversed) {
      if (!x.finished || x.id == exceptSession) continue;
      final sets = [
        for (final set in x.sets)
          if (set.exerciseId == exerciseId && set.done && !set.warmup) set,
      ];
      if (sets.isNotEmpty) return sets;
    }
    return const [];
  }

  /// Best estimated 1RM for [exerciseId] across finished sessions other
  /// than [exceptSession].
  double? bestE1rm(String exerciseId, {String? exceptSession}) {
    double? best;
    for (final x in sessions) {
      if (!x.finished || x.id == exceptSession) continue;
      for (final set in x.sets) {
        if (set.exerciseId != exerciseId) continue;
        final v = setE1rm(set, x.date);
        if (v != null && (best == null || v > best)) best = v;
      }
    }
    return best;
  }

  /// Exercises with at least one finished working set, most recent first.
  List<String> get trainedExerciseIds {
    final seen = <String>[];
    for (final x in sessions.reversed) {
      if (!x.finished) continue;
      for (final set in x.sets) {
        if (set.done && !set.warmup && !seen.contains(set.exerciseId)) {
          seen.add(set.exerciseId);
        }
      }
    }
    return seen;
  }

  /// Saves changes to a finished workout. Unticked sets are dropped; a
  /// workout left with no sets is deleted. Returns false if it was deleted.
  bool saveEditedSession(Session x) {
    final kept = [
      for (final set in x.sets)
        if (set.done) set,
    ];
    if (kept.isEmpty) {
      discardSession(x);
      return false;
    }
    updateSession(x.copyWith(sets: kept));
    return true;
  }

  Workout? workoutById(String? id) {
    if (id == null) return null;
    for (final w in workouts) {
      if (w.id == id) return w;
    }
    return null;
  }

  // ------------------------------------------------------------ calendar

  List<PlannedWorkout> plannedOn(DateTime day) {
    final key = dayKey(day);
    return [
      for (final p in planned)
        if (dayKey(p.date) == key) p,
    ];
  }

  List<Session> finishedOn(DateTime day) {
    final key = dayKey(day);
    return [
      for (final x in sessions)
        if (x.finished && dayKey(x.date) == key) x,
    ];
  }

  /// True when a planned workout was done that day (a finished session of
  /// the same workout on the same date).
  bool plannedDone(PlannedWorkout p) =>
      finishedOn(p.date).any((x) => x.workoutId == p.workoutId);

  PlannedWorkout schedule(String workoutId, DateTime day) {
    final p = PlannedWorkout(id: newId('p'), date: dateOnly(day), workoutId: workoutId);
    planned = [...planned, p];
    notifyListeners();
    _save(() => _store.savePlanned(p));
    return p;
  }

  /// Puts a planned workout back exactly as it was (used by Undo).
  void restorePlanned(PlannedWorkout p) {
    planned = [
      for (final x in planned)
        if (x.id != p.id) x,
      p,
    ];
    notifyListeners();
    _save(() => _store.savePlanned(p));
  }

  void movePlanned(PlannedWorkout p, DateTime day) =>
      restorePlanned(p.copyWith(date: dateOnly(day)));

  void removePlanned(PlannedWorkout p) {
    planned = [
      for (final x in planned)
        if (x.id != p.id) x,
    ];
    notifyListeners();
    _save(() => _store.deletePlanned(p), delete: true);
  }

  /// Copies the week before [weekStart] onto the week starting [weekStart].
  /// Returns what was added, so it can be undone.
  List<PlannedWorkout> copyPreviousWeek(DateTime weekStart) {
    final start = dateOnly(weekStart);
    final added = <PlannedWorkout>[];
    for (var d = 0; d < 7; d++) {
      final from = DateTime(start.year, start.month, start.day - 7 + d);
      final to = DateTime(start.year, start.month, start.day + d);
      for (final p in plannedOn(from)) {
        final already = plannedOn(to).any((x) => x.workoutId == p.workoutId);
        if (!already) added.add(schedule(p.workoutId, to));
      }
    }
    return added;
  }

  /// Weight expected on a future [day] if current targets are kept,
  /// starting from the weekly average (or latest weight) today.
  double? projectedWeightOn(DateTime day) {
    final t = targets;
    if (t == null) return null;
    final today = dateOnly(DateTime.now());
    if (!dateOnly(day).isAfter(today)) return null;
    // Starts from where your weight is now (recalculated from every
    // weigh-in, old ones added later included), then follows the plan.
    final trend = trendWeight(dayWeights);
    final base = trend?.kg ?? currentWeightKg;
    if (base == null) return null;
    final from = trend?.day ?? today;
    final perDay = plannedChangeKgPerDay(maintenanceKcal: t.maintenanceKcal, plannedKcal: t.kcal);
    var kg = base + perDay * daysBetween(from, day);
    // Stops at the goal weight rather than projecting past it.
    final target = goal.targetWeightKg;
    if (target != null) {
      if (perDay < 0 && kg < target && base >= target) kg = target;
      if (perDay > 0 && kg > target && base <= target) kg = target;
    }
    return kg;
  }

  /// The weight to show on a calendar day: the weigh-in if there is one,
  /// else (for days ahead) the projection, marked as projected.
  ({double kg, bool projected})? calendarWeightOn(DateTime day) {
    final w = weighInOn(day);
    if (w != null) return (kg: w.weightKg, projected: false);
    final p = projectedWeightOn(day);
    return p == null ? null : (kg: p, projected: true);
  }

  // ------------------------------------------------------------ food

  Food? food(String id) {
    for (final f in foods) {
      if (f.id == id) return f;
    }
    return null;
  }

  Recipe? recipe(String id) {
    for (final r in recipes) {
      if (r.id == id) return r;
    }
    return null;
  }

  void saveFood(Food f) {
    foods = [
      for (final x in foods)
        if (x.id != f.id) x,
      f,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    _save(() => _store.saveFood(f));
  }

  void saveStore(GroceryStore x) {
    final exists = stores.any((y) => y.id == x.id);
    stores = exists
        ? [for (final y in stores) y.id == x.id ? x : y]
        : [...stores, x.copyWith(sort: stores.length)];
    notifyListeners();
    _save(() => _store.saveStore(exists ? x : stores.last));
  }

  void deleteStore(GroceryStore x) {
    stores = [
      for (final y in stores)
        if (y.id != x.id) y,
    ];
    // Its prices go too.
    final touched = [
      for (final f in foods)
        if (f.prices.containsKey(x.id)) f,
    ];
    for (final f in touched) {
      saveFood(f.copyWith(prices: {...f.prices}..remove(x.id)));
    }
    notifyListeners();
    _save(() => _store.deleteStore(x), delete: true);
  }

  void saveRecipe(Recipe r) {
    recipes = [
      for (final x in recipes)
        if (x.id != r.id) x,
      r,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    _save(() => _store.saveRecipe(r));
  }

  void deleteRecipe(Recipe r) {
    recipes = [
      for (final x in recipes)
        if (x.id != r.id) x,
    ];
    notifyListeners();
    _save(() => _store.deleteRecipe(r), delete: true);
  }

  /// Whole-recipe totals from its foods' current values.
  Macros recipeTotals(Recipe r) {
    var m = Macros.zero;
    for (final i in r.items) {
      final f = food(i.foodId);
      if (f != null) m = m + macrosForGrams(f.per100, i.grams);
    }
    return m;
  }

  Macros recipePerServing(Recipe r) =>
      recipeTotals(r).scale(1 / (r.servings <= 0 ? 1 : r.servings));

  List<FoodEntry> entriesOn(DateTime day, [Meal? meal]) {
    final key = dayKey(day);
    return [
      for (final e in foodLog)
        if (dayKey(e.date) == key && (meal == null || e.meal == meal)) e,
    ];
  }

  Macros eatenOn(DateTime day) {
    var m = Macros.zero;
    for (final e in entriesOn(day)) {
      m = m + e.macros;
    }
    return m;
  }

  FoodEntry _addEntry(FoodEntry e) {
    foodLog = [...foodLog, e];
    notifyListeners();
    _save(() => _store.saveEntry(e));
    return e;
  }

  FoodEntry logFood(DateTime day, Meal meal, Food f, double grams) => _addEntry(FoodEntry(
        id: newId('e'),
        date: dateOnly(day),
        meal: meal,
        kind: 'food',
        refId: f.id,
        amount: grams,
        name: f.name,
        macros: macrosForGrams(f.per100, grams),
      ));

  FoodEntry logRecipe(DateTime day, Meal meal, Recipe r, double servings) => _addEntry(FoodEntry(
        id: newId('e'),
        date: dateOnly(day),
        meal: meal,
        kind: 'recipe',
        refId: r.id,
        amount: servings,
        name: r.name,
        macros: recipePerServing(r).scale(servings),
      ));

  FoodEntry logQuick(DateTime day, Meal meal, String name, Macros m) => _addEntry(FoodEntry(
        id: newId('e'),
        date: dateOnly(day),
        meal: meal,
        kind: 'quick',
        name: name.trim().isEmpty ? 'Quick add' : name.trim(),
        macros: m,
      ));

  /// Changes how much was eaten, recalculating from the food or recipe.
  void updateEntryAmount(FoodEntry e, double amount, {Meal? meal}) {
    var m = e.macros;
    if (e.kind == 'food') {
      final f = food(e.refId ?? '');
      if (f != null) m = macrosForGrams(f.per100, amount);
    } else if (e.kind == 'recipe') {
      final r = recipe(e.refId ?? '');
      if (r != null) m = recipePerServing(r).scale(amount);
    }
    restoreEntry(e.copyWith(amount: amount, macros: m, meal: meal));
  }

  /// Saves an entry as given (edits, and Undo after delete).
  void restoreEntry(FoodEntry e) {
    foodLog = [
      for (final x in foodLog)
        if (x.id != e.id) x,
      e,
    ];
    notifyListeners();
    _save(() => _store.saveEntry(e));
  }

  /// Moves a logged item to another day and/or meal.
  void moveEntry(FoodEntry e, DateTime day, Meal meal) {
    if (dateOnly(day) == dateOnly(e.date)) {
      // Same day: only the meal changes (works for calories-only entries too).
      restoreEntry(e.copyWith(meal: meal));
      return;
    }
    final copy = FoodEntry(
      id: newId('e'),
      date: dateOnly(day),
      meal: meal,
      kind: e.kind,
      refId: e.refId,
      amount: e.amount,
      name: e.name,
      macros: e.macros,
    );
    foodLog = [...foodLog, copy];
    _save(() => _store.saveEntry(copy));
    deleteEntry(e);
  }

  void deleteEntry(FoodEntry e) {
    foodLog = [
      for (final x in foodLog)
        if (x.id != e.id) x,
    ];
    notifyListeners();
    _save(() => _store.deleteEntry(e), delete: true);
  }

  /// Copies everything from [from] onto [to]. Returns the copies (for Undo).
  List<FoodEntry> copyDay(DateTime from, DateTime to) {
    final out = <FoodEntry>[];
    for (final e in entriesOn(from)) {
      final copy = FoodEntry(
        id: newId('e'),
        date: dateOnly(to),
        meal: e.meal,
        kind: e.kind,
        refId: e.refId,
        amount: e.amount,
        name: e.name,
        macros: e.macros,
      );
      foodLog = [...foodLog, copy];
      _save(() => _store.saveEntry(copy));
      out.add(copy);
    }
    notifyListeners();
    return out;
  }

  /// Copies one meal to another day (and meal, if different), for
  /// "Repeat the day before's breakfast" and "Copy to...".
  List<FoodEntry> copyMeal(DateTime from, Meal fromMeal, DateTime to, Meal toMeal) {
    final out = <FoodEntry>[];
    for (final e in entriesOn(from)) {
      if (e.meal != fromMeal) continue;
      final copy = FoodEntry(
        id: newId('e'),
        date: dateOnly(to),
        meal: toMeal,
        kind: e.kind,
        refId: e.refId,
        amount: e.amount,
        name: e.name,
        macros: e.macros,
      );
      foodLog = [...foodLog, copy];
      _save(() => _store.saveEntry(copy));
      out.add(copy);
    }
    notifyListeners();
    return out;
  }

  /// Stars or un-stars a food (favourites are shown first when picking).
  void setFavorite(Food f, bool on) => saveFood(f.copyWith(favorite: on));

  /// Starred foods, by name.
  List<Food> get favoriteFoods =>
      [for (final f in foods) if (f.favorite && !f.archived) f]..sort((a, b) => a.name.compareTo(b.name));

  /// Recently logged foods and recipes, most recent first, for quick picks.
  List<FoodEntry> get recentPicks {
    final seen = <String>{};
    final out = <FoodEntry>[];
    for (final e in foodLog.reversed) {
      if (e.kind == 'quick') continue;
      final key = '${e.kind}:${e.refId}';
      if (seen.add(key)) out.add(e);
      if (out.length >= 12) break;
    }
    return out;
  }

  // ------------------------------------------------------------ built-in foods

  /// The food for a USDA entry: yours if you've used it before, else a new
  /// copy in your foods (so you can rename it or set prices).
  Food foodFromUsda(UsdaFood u) {
    for (final existing in foods) {
      if (existing.sourceId == u.sourceId) return existing;
    }
    final f = Food(
      id: newId('f'),
      name: u.name,
      per100: u.per100,
      servingGrams: (u.servingGrams ?? 0) > 0 ? u.servingGrams : null,
      fiber: u.fiber,
      sugar: u.sugar,
      sodiumMg: u.sodiumMg,
      sourceId: u.sourceId,
      custom: true,
    );
    saveFood(f);
    return f;
  }

  // ------------------------------------------------------------ barcodes

  /// One of your foods with this barcode (matching UPC and EAN forms of
  /// the same code), or null.
  Food? foodByBarcode(String code) {
    final wanted = barcodeVariants(code).toSet();
    for (final f in foods) {
      final b = f.barcode;
      if (b == null || f.archived) continue;
      if (barcodeVariants(b).any(wanted.contains)) return f;
    }
    return null;
  }

  // ------------------------------------------------------------ sharing food

  /// [recipes] plus every food they use, plus [extraFoods], as share-file text.
  String shareFoods({required List<Recipe> recipes, List<Food> extraFoods = const []}) {
    final foodsOut = <String, Food>{for (final f in extraFoods) f.id: f};
    for (final r in recipes) {
      for (final i in r.items) {
        final f = food(i.foodId);
        if (f != null) foodsOut[f.id] = f;
      }
    }
    return encodeFoodShare(
      foods: foodsOut.values.toList(),
      recipes: recipes,
      from: settings.nickname,
    );
  }

  /// Adds a friend's foods and recipes. Foods with a name you already have
  /// are reused; recipes with a name you already have are skipped, so
  /// nothing of yours is changed. Returns what was added and skipped.
  ({int foods, int recipes, int skippedRecipes}) importFoodShare(FoodShare share) {
    String key(String name) => name.trim().toLowerCase();
    final byName = {for (final f in foods) key(f.name): f.id};
    final idMap = <String, String>{};
    var addedFoods = 0;
    for (final f in share.foods) {
      final existing = byName[key(f.name)];
      if (existing != null) {
        idMap[f.id] = existing;
        continue;
      }
      final copy = Food(
        id: newId('f'),
        name: f.name,
        per100: f.per100,
        byItem: f.byItem,
        gramsPerItem: f.gramsPerItem,
        custom: true,
      );
      saveFood(copy);
      byName[key(copy.name)] = copy.id;
      idMap[f.id] = copy.id;
      addedFoods++;
    }
    final recipeNames = {for (final r in recipes) key(r.name)};
    var addedRecipes = 0;
    var skipped = 0;
    for (final r in share.recipes) {
      if (recipeNames.contains(key(r.name))) {
        skipped++;
        continue;
      }
      final items = [
        for (final i in r.items)
          if (idMap[i.foodId] != null) RecipeItem(foodId: idMap[i.foodId]!, grams: i.grams),
      ];
      saveRecipe(Recipe(
        id: newId('r'),
        name: r.name,
        servings: r.servings,
        items: items,
        note: r.note,
      ));
      recipeNames.add(key(r.name));
      addedRecipes++;
    }
    return (foods: addedFoods, recipes: addedRecipes, skippedRecipes: skipped);
  }

  // ------------------------------------------------------------ meal plan

  List<PlannedMeal> plannedMealsOn(DateTime day) {
    final key = dayKey(day);
    return [
      for (final p in plannedMeals)
        if (dayKey(p.date) == key) p,
    ]..sort((a, b) => a.meal.index.compareTo(b.meal.index));
  }

  String plannedName(PlannedMeal p) =>
      p.kind == 'recipe' ? (recipe(p.refId)?.name ?? 'Recipe') : (food(p.refId)?.name ?? 'Food');

  Macros plannedMacros(PlannedMeal p) {
    if (p.kind == 'recipe') {
      final r = recipe(p.refId);
      return r == null ? Macros.zero : recipePerServing(r).scale(p.amount);
    }
    final f = food(p.refId);
    return f == null ? Macros.zero : macrosForGrams(f.per100, p.amount);
  }

  Macros plannedTotal(DateTime day) {
    var m = Macros.zero;
    for (final p in plannedMealsOn(day)) {
      m = m + plannedMacros(p);
    }
    return m;
  }

  /// Logged, and the log entry still exists.
  bool isPlannedLogged(PlannedMeal p) {
    final id = p.loggedId;
    return id != null && foodLog.any((e) => e.id == id);
  }

  PlannedMeal planMeal(DateTime day, Meal meal, String kind, String refId, double amount) {
    final p = PlannedMeal(
      id: newId('pm'),
      date: dateOnly(day),
      meal: meal,
      kind: kind,
      refId: refId,
      amount: amount,
    );
    plannedMeals = [...plannedMeals, p];
    notifyListeners();
    _save(() => _store.savePlannedMeal(p));
    return p;
  }

  void savePlannedMeal(PlannedMeal p) {
    plannedMeals = [
      for (final x in plannedMeals)
        if (x.id != p.id) x,
      p,
    ];
    notifyListeners();
    _save(() => _store.savePlannedMeal(p));
  }

  void removePlannedMeal(PlannedMeal p) {
    plannedMeals = [
      for (final x in plannedMeals)
        if (x.id != p.id) x,
    ];
    notifyListeners();
    _save(() => _store.deletePlannedMeal(p), delete: true);
  }

  /// Logs a planned item on its own day and meal. Returns the entry.
  FoodEntry? logPlanned(PlannedMeal p) {
    FoodEntry? e;
    if (p.kind == 'recipe') {
      final r = recipe(p.refId);
      if (r != null) e = logRecipe(p.date, p.meal, r, p.amount);
    } else {
      final f = food(p.refId);
      if (f != null) e = logFood(p.date, p.meal, f, p.amount);
    }
    if (e != null) savePlannedMeal(p.copyWith(loggedId: e.id));
    return e;
  }

  /// Copies last week's meal plan onto the week starting [weekStart].
  List<PlannedMeal> copyPreviousMealWeek(DateTime weekStart) {
    final start = dateOnly(weekStart);
    final added = <PlannedMeal>[];
    for (var d = 0; d < 7; d++) {
      final from = DateTime(start.year, start.month, start.day - 7 + d);
      final to = DateTime(start.year, start.month, start.day + d);
      final there = plannedMealsOn(to);
      for (final p in plannedMealsOn(from)) {
        final dup = there.any((x) => x.meal == p.meal && x.kind == p.kind && x.refId == p.refId);
        if (!dup) added.add(planMeal(to, p.meal, p.kind, p.refId, p.amount));
      }
    }
    return added;
  }

  // ------------------------------------------------------------ groceries

  /// Grams of each food needed for the meals planned from [from] through
  /// [to] (inclusive).
  Map<String, double> groceryNeeds(DateTime from, DateTime to) {
    final a = dateOnly(from);
    final b = dateOnly(to);
    final out = <String, double>{};
    void add(String foodId, double grams) {
      if (grams <= 0) return;
      out[foodId] = (out[foodId] ?? 0) + grams;
    }

    for (final p in plannedMeals) {
      final d = dateOnly(p.date);
      if (d.isBefore(a) || d.isAfter(b)) continue;
      if (p.kind == 'food') {
        add(p.refId, p.amount);
      } else {
        final r = recipe(p.refId);
        if (r == null || r.servings <= 0) continue;
        for (final i in r.items) {
          add(i.foodId, i.grams * p.amount / r.servings);
        }
      }
    }
    return out;
  }

  GroceryMark groceryMark(String foodId) {
    for (final m in groceryMarks) {
      if (m.foodId == foodId) return m;
    }
    return GroceryMark(foodId: foodId);
  }

  void setGroceryMark(GroceryMark m) {
    groceryMarks = [
      for (final x in groceryMarks)
        if (x.foodId != m.foodId) x,
      m,
    ];
    notifyListeners();
    _save(() => _store.saveGroceryMark(m));
  }

  /// Starts a fresh list: clears cart ticks and "at home" marks, so items
  /// you've since run out of come back.
  void clearCart() {
    for (final m in [...groceryMarks]) {
      if (m.inCart || m.atHome) setGroceryMark(m.copyWith(inCart: false, atHome: false));
    }
  }

  // ------------------------------------------------------------ your own grocery lists

  List<GroceryItem> get customGroceries => [
        for (final g in groceryItems)
          if (!g.isFood) g,
      ];

  List<GroceryItem> get foodGroceries => [
        for (final g in groceryItems)
          if (g.isFood) g,
      ];

  void saveGroceryItem(GroceryItem g) {
    final exists = groceryItems.any((x) => x.id == g.id);
    groceryItems = exists
        ? [for (final x in groceryItems) x.id == g.id ? g : x]
        : [...groceryItems, g];
    notifyListeners();
    _save(() => _store.saveGroceryItem(g));
  }

  void deleteGroceryItem(GroceryItem g) {
    groceryItems = [
      for (final x in groceryItems)
        if (x.id != g.id) x,
    ];
    notifyListeners();
    _save(() => _store.deleteGroceryItem(g), delete: true);
  }

  GroceryItem addGroceryText(String label) {
    final g = GroceryItem(id: newId('g'), label: label.trim());
    saveGroceryItem(g);
    return g;
  }

  /// Adds [f] to your foods list, or adds [amount] to it if it's there.
  void addGroceryFood(Food f, double amount) {
    for (final g in foodGroceries) {
      if (g.foodId == f.id) {
        saveGroceryItem(g.copyWith(amount: (g.amount ?? 0) + amount));
        return;
      }
    }
    saveGroceryItem(GroceryItem(id: newId('g'), label: f.name, foodId: f.id, amount: amount));
  }

  /// Removes ticked items from one of your lists. Returns them (for Undo).
  List<GroceryItem> clearDoneGroceries({required bool foods}) {
    final gone = [
      for (final g in groceryItems)
        if (g.done && g.isFood == foods) g,
    ];
    for (final g in gone) {
      deleteGroceryItem(g);
    }
    return gone;
  }

  // ------------------------------------------------------------ learned maintenance

  /// Food totals per day, for days with anything logged.
  List<(DateTime, double)> get intakeDays {
    final byDay = <String, (DateTime, double)>{};
    for (final e in foodLog) {
      final k = dayKey(e.date);
      final prev = byDay[k];
      byDay[k] = (dateOnly(e.date), (prev?.$2 ?? 0) + e.macros.kcal);
    }
    return byDay.values.toList();
  }

  /// Progress toward learned maintenance, counted in the same window the
  /// calculation uses: (days with food logged, weigh-ins).
  (int, int) get learnedProgress {
    final end = dateOnly(DateTime.now());
    final start = DateTime(end.year, end.month, end.day - adaptiveWindowDays);
    bool inWindow(DateTime d) {
      final x = dateOnly(d);
      return !x.isBefore(start) && x.isBefore(end);
    }

    final food = intakeDays.where((p) => inWindow(p.$1) && p.$2 > 0).length;
    final weights = weighIns.where((w) => inWindow(w.date)).length;
    return (food, weights);
  }

  LearnedMaintenance? get learnedMaintenance => adaptiveMaintenance(
        intakeDays: intakeDays,
        weights: [for (final w in weighIns) (w.date, w.weightKg)],
        today: DateTime.now(),
      );

  // ------------------------------------------------------------ mesocycles

  Mesocycle? mesoById(String? id) {
    if (id == null) return null;
    for (final m in mesocycles) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The block running on [day] (started, not past its end), if any.
  Mesocycle? mesoOn(DateTime day) {
    for (final m in mesocycles.reversed) {
      if (m.weekOn(day) != null) return m;
    }
    return null;
  }

  Mesocycle? get activeMeso => mesoOn(DateTime.now());

  /// The running block if [workoutId] is one of its workouts.
  Mesocycle? mesoFor(String workoutId, DateTime day) {
    final m = mesoOn(day);
    return m != null && m.schedule.containsValue(workoutId) ? m : null;
  }

  /// Blocks that have finished (or were ended early), newest first.
  /// Blocks cancelled before they started are left out.
  List<Mesocycle> get pastMesos {
    final today = dateOnly(DateTime.now());
    return [
      for (final m in mesocycles.reversed)
        if (m.endDay.isBefore(today) && !m.endDay.isBefore(m.start)) m,
    ];
  }

  /// A block scheduled to start after today (and not cancelled).
  Mesocycle? get upcomingMeso {
    final today = dateOnly(DateTime.now());
    for (final m in mesocycles) {
      if (m.start.isAfter(today) && !m.endDay.isBefore(m.start)) return m;
    }
    return null;
  }

  /// Sets for an exercise in [week] of [m], given the planned [base].
  int mesoSets(Mesocycle m, int week, int base) {
    if (m.isDeloadWeek(week)) return (base / 2).ceil().clamp(1, 99);
    if (m.progression == MesoProgression.sets) {
      return base + (week - 1).clamp(0, 4);
    }
    return base;
  }

  /// Reps-in-reserve target for effort progression: 3 in week 1 down to 0
  /// in the last working week. Null for other progressions and deloads.
  int? mesoRir(Mesocycle m, int week) {
    if (m.progression != MesoProgression.effort || m.isDeloadWeek(week)) return null;
    if (m.weeks <= 1) return 0;
    return (3 - 3 * (week - 1) / (m.weeks - 1)).round().clamp(0, 3);
  }

  /// One line describing what [week] asks for.
  String mesoInstruction(Mesocycle m, int week) {
    if (m.isDeloadWeek(week)) {
      return 'Deload: half the sets, about 10% lighter, stop well short of failure';
    }
    final imperial = settings.units == Units.imperial;
    final step = imperial ? kgToLb(m.weightStepKg) : m.weightStepKg;
    final unit = imperial ? 'lb' : 'kg';
    return switch (m.progression) {
      MesoProgression.weight => week == 1
          ? 'Set your starting weights this week'
          : 'Add ${_step(step)} $unit to last week\'s weights',
      MesoProgression.sets => week == 1
          ? 'Baseline sets this week'
          : '+${(week - 1).clamp(0, 4)} ${week == 2 ? 'set' : 'sets'} per exercise vs week 1',
      MesoProgression.effort => 'Leave about ${mesoRir(m, week)} '
          '${mesoRir(m, week) == 1 ? 'rep' : 'reps'} in reserve',
    };
  }

  /// Working sets of [exerciseId] done in [week] of [m] (latest session).
  List<SetEntry> mesoWeekSets(Mesocycle m, int week, String exerciseId) {
    for (final x in sessions.reversed) {
      if (!x.finished || x.mesoId != m.id || x.mesoWeek != week) continue;
      final sets = [
        for (final set in x.sets)
          if (set.exerciseId == exerciseId && set.done && !set.warmup) set,
      ];
      if (sets.isNotEmpty) return sets;
    }
    return const [];
  }

  /// The weight to suggest for working set [k] of [exerciseId] in [week]:
  /// last week's weight plus the step (weight progression), about 10% less
  /// in a deload, otherwise [fallback] (last time or the plan).
  double? mesoWeightHint(Mesocycle m, int week, String exerciseId, int k, double? fallback) {
    if (m.isDeloadWeek(week)) {
      if (fallback == null || fallback <= 0) return fallback;
      final half = m.weightStepKg / 2;
      return ((fallback * 0.9) / half).round() * half;
    }
    if (m.progression != MesoProgression.weight || week <= 1) return fallback;
    final prev = mesoWeekSets(m, week - 1, exerciseId);
    if (prev.isEmpty) return fallback;
    final w = (k < prev.length ? prev[k] : prev.last).weightKg;
    return w == null ? fallback : w + m.weightStepKg;
  }

  /// Starts a block: saves it and schedules every week on the calendar.
  /// Returns how many workouts were scheduled.
  int startMeso(Mesocycle m) {
    mesocycles = [...mesocycles, m]..sort((a, b) => a.start.compareTo(b.start));
    _save(() => _store.saveMeso(m));
    final added = <PlannedWorkout>[];
    for (var week = 1; week <= m.totalWeeks; week++) {
      for (var d = 0; d < 7; d++) {
        final day = DateTime(m.start.year, m.start.month, m.start.day + (week - 1) * 7 + d);
        final workoutId = m.schedule[day.weekday];
        if (workoutId == null || workoutById(workoutId) == null) continue;
        final p = PlannedWorkout(
          id: newId('p'),
          date: day,
          workoutId: workoutId,
          mesoId: m.id,
          mesoWeek: week,
        );
        added.add(p);
        _save(() => _store.savePlanned(p));
      }
    }
    planned = [...planned, ...added];
    notifyListeners();
    return added.length;
  }

  /// Ends a block today (or cancels one that hasn't started) and clears
  /// its calendar slots after today.
  void endMeso(Mesocycle m) {
    final today = dateOnly(DateTime.now());
    final DateTime? endedEarly;
    if (today.isBefore(m.start)) {
      // Cancelled: ends the day before it would have started.
      endedEarly = DateTime(m.start.year, m.start.month, m.start.day - 1);
    } else {
      endedEarly = today.isBefore(m.lastDay) ? today : null;
    }
    final ended = m.copyWith(endedEarly: endedEarly);
    mesocycles = [for (final x in mesocycles) x.id == m.id ? ended : x];
    _save(() => _store.saveMeso(ended));
    final gone = [
      for (final p in planned)
        if (p.mesoId == m.id && p.date.isAfter(today)) p,
    ];
    planned = [
      for (final p in planned)
        if (!gone.contains(p)) p,
    ];
    for (final p in gone) {
      _save(() => _store.deletePlanned(p), delete: true);
    }
    notifyListeners();
  }

  /// Per exercise: best estimated 1RM in the first and last working week
  /// it was done, plus sessions done vs scheduled.
  ({List<(String, double?, double?)> lifts, int done, int scheduled}) mesoReport(Mesocycle m) {
    final ses = [
      for (final x in sessions)
        if (x.finished && x.mesoId == m.id) x,
    ];
    final scheduled = [
      for (final p in planned)
        if (p.mesoId == m.id) p,
    ].length;
    final ids = <String>[];
    for (final x in ses) {
      for (final set in x.sets) {
        if (!ids.contains(set.exerciseId) && !isCardio(set.exerciseId)) ids.add(set.exerciseId);
      }
    }
    final lifts = <(String, double?, double?)>[];
    for (final id in ids) {
      double? first;
      double? last;
      int? firstWeek;
      int? lastWeek;
      for (final x in ses) {
        final wk = x.mesoWeek;
        if (wk == null || m.isDeloadWeek(wk)) continue;
        double? best;
        for (final set in x.sets) {
          if (set.exerciseId != id) continue;
          final v = setE1rm(set, x.date);
          if (v != null && (best == null || v > best)) best = v;
        }
        if (best == null) continue;
        if (firstWeek == null || wk < firstWeek) {
          firstWeek = wk;
          first = best;
        } else if (wk == firstWeek && best > (first ?? 0)) {
          first = best;
        }
        if (lastWeek == null || wk > lastWeek) {
          lastWeek = wk;
          last = best;
        } else if (wk == lastWeek && best > (last ?? 0)) {
          last = best;
        }
      }
      lifts.add((id, first, last));
    }
    return (lifts: lifts, done: ses.length, scheduled: scheduled);
  }

  // ------------------------------------------------------------ phases

  /// The phase covering [day], if any (the latest-starting one wins).
  Phase? phaseOn(DateTime day) {
    Phase? hit;
    for (final p in phases) {
      if (p.coversDay(day) && (hit == null || !p.start.isBefore(hit.start))) hit = p;
    }
    return hit;
  }

  Phase? get activePhase => phaseOn(DateTime.now());

  /// The goal as it applies today: an active phase sets mode and pace.
  Goal get goalNow {
    final p = activePhase;
    return p == null ? goal : goal.copyWith(mode: p.mode, paceKgPerWeek: p.paceKgPerWeek);
  }

  void savePhase(Phase p) {
    phases = [
      for (final x in phases)
        if (x.id != p.id) x,
      p,
    ]..sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
    _save(() => _store.savePhase(p));
  }

  void deletePhase(Phase p) {
    phases = [
      for (final x in phases)
        if (x.id != p.id) x,
    ];
    notifyListeners();
    _save(() => _store.deletePhase(p), delete: true);
  }

  // ------------------------------------------------------------ weekly summary

  /// The first day of the week before the current one (Sunday or Monday,
  /// per settings).
  DateTime get lastWeekStart {
    final w = weekStartOf(dateOnly(DateTime.now()), sundayFirst: settings.weekStartsSunday);
    return DateTime(w.year, w.month, w.day - 7);
  }

  WeekSummary summaryFor(DateTime weekStart) {
    final start = dateOnly(weekStart);
    final end = DateTime(start.year, start.month, start.day + 6);
    bool inWeek(DateTime d) {
      final x = dateOnly(d);
      return !x.isBefore(start) && !x.isAfter(end);
    }

    final avg = weeklyAverage(dayWeights, end, minCount: 2);
    final prev = weeklyAverage(dayWeights, DateTime(end.year, end.month, end.day - 7), minCount: 2);
    final workouts = [
      for (final x in sessions)
        if (x.finished && inWeek(x.date)) x,
    ].length;
    final plannedCount = [
      for (final p in planned)
        if (inWeek(p.date)) p,
    ].length;
    final sleepMins = [
      for (final e in sleep)
        if (inWeek(e.date) && e.durationMin != null) e.durationMin!,
    ];
    final t = targets;
    var foodDays = 0;
    var kcalSum = 0.0;
    var proteinHit = 0;
    for (var i = 0; i < 7; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      if (entriesOn(d).isEmpty) continue;
      final m = eatenOn(d);
      foodDays++;
      kcalSum += m.kcal;
      if (t != null && m.protein >= t.proteinG * 0.95) proteinHit++;
    }
    return WeekSummary(
      start: start,
      avgWeightKg: avg,
      prevAvgWeightKg: prev,
      workouts: workouts,
      workoutsPlanned: plannedCount,
      avgSleepMin: averageMinutes(sleepMins),
      foodDays: foodDays,
      avgKcal: foodDays == 0 ? null : kcalSum / foodDays,
      targetKcal: t?.kcal,
      proteinDaysHit: proteinHit,
      phase: phaseOn(end),
    );
  }

  /// Past weeks with anything logged, newest first.
  List<WeekSummary> recentSummaries({int weeks = 12}) {
    final out = <WeekSummary>[];
    for (var w = 0; w < weeks; w++) {
      final m = DateTime(lastWeekStart.year, lastWeekStart.month, lastWeekStart.day - 7 * w);
      final x = summaryFor(m);
      if (x.hasData) out.add(x);
    }
    return out;
  }

  /// Last week's summary, until it's dismissed on Home.
  WeekSummary? get summaryToShow {
    final m = lastWeekStart;
    if (settings.summarySeenWeek == dayKey(m)) return null;
    final x = summaryFor(m);
    return x.hasData ? x : null;
  }

  void dismissSummary() =>
      setSettings(settings.copyWith(summarySeenWeek: dayKey(lastWeekStart)));

  // ------------------------------------------------------------ app lock

  void setPin(String pin, String Function(String pin, String salt) hash, String salt) {
    setSettings(settings.copyWith(
      lockEnabled: true,
      lockPinHash: hash(pin, salt),
      lockPinSalt: salt,
    ));
  }

  bool checkPin(String pin, String Function(String pin, String salt) hash) {
    final h = settings.lockPinHash;
    final salt = settings.lockPinSalt;
    if (h == null || salt == null) return false;
    return hash(pin, salt) == h;
  }

  void turnOffLock() => setSettings(settings.copyWith(
        lockEnabled: false,
        lockPinHash: null,
        lockPinSalt: null,
        lockBiometric: false,
      ));

  // ------------------------------------------------------------ home screen widget

  /// Ticks or unticks a meal on today's plan (from the Today widget): logs
  /// every planned item for [meal] on [day], or, if they're all logged
  /// already, removes those log entries again. Returns true if now ticked.
  bool toggleMealSlot(DateTime day, Meal meal) {
    final items = [
      for (final p in plannedMealsOn(day))
        if (p.meal == meal) p,
    ];
    if (items.isEmpty) return false;
    final allLogged = items.every(isPlannedLogged);
    if (allLogged) {
      for (final p in items) {
        final id = p.loggedId;
        for (final e in [...foodLog]) {
          if (e.id == id) deleteEntry(e);
        }
        savePlannedMeal(p.copyWith(loggedId: null));
      }
      return false;
    }
    for (final p in items) {
      if (!isPlannedLogged(p)) logPlanned(p);
    }
    return true;
  }

  /// Sets how last night went (1 to 5), from the Check-in widget.
  void setSleepQuality(DateTime day, int quality) {
    final e = sleepOn(day);
    if (e == null) return;
    logSleep(SleepEntry(
      date: e.date,
      bedMinute: e.bedMinute,
      wakeMinute: e.wakeMinute,
      durationMin: e.durationMin,
      quality: quality.clamp(1, 5),
      source: e.source,
    ));
  }

  /// Everything the two home screen widgets show, as key/value pairs.
  Map<String, Object> get widgetData {
    final imperial = settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    String w(double kg) => '${_one(imperial ? kgToLb(kg) : kg)} $unit';
    final now = DateTime.now();
    final today = dateOnly(now);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const quality = ['', 'poor', 'fair', 'okay', 'good', 'great'];

    // Check-in widget.
    final weigh = weighInOn(today);
    final avg = weeklyAverage(dayWeights, now, minCount: 2);
    final night = sleepOn(today);
    final mins = night?.durationMin;
    final q = night?.quality;

    // Today widget.
    final active = activeSession;
    final plan = [
      for (final p in plannedOn(today))
        if (!plannedDone(p) && workoutById(p.workoutId) != null) p,
    ];
    final done = finishedOn(today);
    String workout;
    var action = '';
    var workoutId = '';
    if (active != null) {
      workout = '${active.name} is in progress';
      action = 'Resume';
      workoutId = active.workoutId ?? '';
    } else if (plan.isNotEmpty) {
      workout = plan.map((p) => workoutById(p.workoutId)!.name).join(' + ');
      action = 'Start';
      workoutId = plan.first.workoutId;
    } else if (done.isNotEmpty) {
      workout = '✓ ${done.last.name} done';
    } else {
      workout = 'Rest day';
    }
    final meals = plannedMealsOn(today);
    var plannedKcal = 0.0;
    for (final m in meals) {
      plannedKcal += plannedMacros(m).kcal;
    }
    final t = targets;

    final data = <String, Object>{
      'data_day': dayKey(today),
      // Short lines: each sits in a half-width box on the Check-In widget.
      'weight': weigh == null ? '—' : w(weigh.weightKg),
      'weight_sub': weigh == null ? 'Tap to log' : (avg == null ? 'Logged' : 'Avg ${w(avg)}'),
      'sleep': night == null ? '—' : (mins == null ? 'Logged' : '${_one(mins / 60)} h'),
      'sleep_sub': night == null ? 'Tap to log' : (q == null ? 'How did you sleep?' : 'Quality $q · ${quality[q]}'),
      'ask_quality': night != null && q == null,
      'day_title': '${days[today.weekday - 1]}, ${months[today.month - 1]} ${today.day}',
      'workout': workout,
      'workout_action': action,
      'workout_id': workoutId,
      'kcal': meals.isEmpty
          ? ''
          : (t == null
              ? '${plannedKcal.round()} kcal planned'
              : '${plannedKcal.round()} of ${t.kcal.round()} kcal planned'),
      'meals_empty': meals.isEmpty,
    };
    for (var i = 0; i < Meal.values.length; i++) {
      final meal = Meal.values[i];
      final items = [
        for (final p in meals)
          if (p.meal == meal) p,
      ];
      data['meal${i}_label'] = meal.label;
      data['meal${i}_text'] = items.map(plannedName).join(', ');
      data['meal${i}_has'] = items.isNotEmpty;
      data['meal${i}_done'] = items.isNotEmpty && items.every(isPlannedLogged);
    }
    return data;
  }

  // ------------------------------------------------------------ measurements

  /// Dates with any measurement, oldest first.
  List<DateTime> get measurementDates {
    final seen = <String, DateTime>{};
    for (final m in measurements) {
      seen[dayKey(m.date)] = dateOnly(m.date);
    }
    return seen.values.toList()..sort();
  }

  List<Measurement> measurementsFor(MeasureSite site) => [
        for (final m in measurements)
          if (m.site == site) m,
      ];

  Measurement? latestMeasurement(MeasureSite site) {
    final list = measurementsFor(site);
    return list.isEmpty ? null : list.last;
  }

  Measurement? measurementOn(DateTime date, MeasureSite site) {
    final key = dayKey(date);
    for (final m in measurements) {
      if (m.site == site && dayKey(m.date) == key) return m;
    }
    return null;
  }

  /// Saves one day's measurements. A null value removes that site's entry
  /// for the day.
  void logMeasurements(DateTime date, Map<MeasureSite, double?> values) {
    final day = dateOnly(date);
    final key = dayKey(day);
    final next = [
      for (final m in measurements)
        if (dayKey(m.date) != key || !values.containsKey(m.site)) m,
    ];
    for (final entry in values.entries) {
      final old = measurementOn(day, entry.key);
      final v = entry.value;
      if (v == null) {
        if (old != null) _save(() => _store.deleteMeasurement(old), delete: true);
        continue;
      }
      final m = Measurement(date: day, site: entry.key, valueCm: v);
      next.add(m);
      _save(() => _store.saveMeasurement(m));
    }
    measurements = next..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
  }

  // ------------------------------------------------------------ photos

  /// Check-in dates, oldest first.
  List<DateTime> get checkinDates {
    final seen = <String, DateTime>{};
    for (final p in photos) {
      seen[dayKey(p.date)] = dateOnly(p.date);
    }
    return seen.values.toList()..sort();
  }

  DateTime? get lastCheckin {
    final d = checkinDates;
    return d.isEmpty ? null : d.last;
  }

  bool get photosAreDue => photosDue(
        lastCheckin: lastCheckin,
        intervalWeeks: settings.photoIntervalWeeks,
        today: DateTime.now(),
      );

  PhotoCheckin? photoFor(DateTime date, PhotoPose pose) {
    final key = dayKey(date);
    for (final p in photos) {
      if (p.pose == pose && dayKey(p.date) == key) return p;
    }
    return null;
  }

  /// Most recent photo of [pose] taken before [before].
  PhotoCheckin? previousPhoto(PhotoPose pose, DateTime before) {
    final b = dateOnly(before);
    PhotoCheckin? best;
    for (final p in photos) {
      if (p.pose == pose && p.date.isBefore(b)) {
        if (best == null || p.date.isAfter(best.date)) best = p;
      }
    }
    return best;
  }

  String? pathFor(PhotoCheckin p) {
    final dir = photosDir;
    return dir == null ? null : '$dir/${p.fileName}';
  }

  void savePhoto(PhotoCheckin photo) {
    final old = photoFor(photo.date, photo.pose);
    final dir = photosDir;
    if (old != null && old.fileName != photo.fileName && dir != null) {
      PhotoFiles.remove(dir, old.fileName);
    }
    photos = [
      for (final p in photos)
        if (p.key != photo.key) p,
      photo,
    ]..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    _save(() => _store.savePhoto(photo));
  }

  void deleteCheckin(DateTime date) {
    final key = dayKey(date);
    final gone = [
      for (final p in photos)
        if (dayKey(p.date) == key) p,
    ];
    photos = [
      for (final p in photos)
        if (dayKey(p.date) != key) p,
    ];
    notifyListeners();
    final dir = photosDir;
    for (final p in gone) {
      if (dir != null) PhotoFiles.remove(dir, p.fileName);
      _save(() => _store.deletePhoto(p), delete: true);
    }
  }

  /// Everything, for a backup.
  StoredData get snapshot => StoredData(
        profile: profile,
        goal: goal,
        settings: settings,
        weighIns: weighIns,
        sleep: sleep,
        measurements: measurements,
        exercises: exercises,
        workouts: workouts,
        sessions: sessions,
        planned: planned,
        foods: foods,
        stores: stores,
        recipes: recipes,
        foodLog: foodLog,
        plannedMeals: plannedMeals,
        phases: phases,
        mesocycles: mesocycles,
        groceryItems: groceryItems,
        water: water,
        supplements: supplements,
        doses: doses,
      );

  void markExported() =>
      setSettings(settings.copyWith(lastExport: DateTime.now()));

  /// Restores a backup. Profile, goal and settings are replaced; weigh-ins
  /// and sleep are merged by date, with the backup winning on the same day.
  /// This phone's reminder stays as it is, since it depends on this phone's
  /// notification permission.
  void importBackup(StoredData data) {
    profile = data.profile;
    goal = data.goal;
    // This phone's reminder and app lock stay as they are.
    settings = data.settings.copyWith(
      onboarded: true,
      reminderMinute: settings.reminderMinute,
      lockEnabled: settings.lockEnabled,
      lockPinHash: settings.lockPinHash,
      lockPinSalt: settings.lockPinSalt,
      lockBiometric: settings.lockBiometric,
      lockAfterSec: settings.lockAfterSec,
    );
    final w = {for (final x in weighIns) dayKey(x.date): x};
    for (final x in data.weighIns) {
      w[dayKey(x.date)] = x;
    }
    weighIns = w.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final sl = {for (final x in sleep) dayKey(x.date): x};
    for (final x in data.sleep) {
      sl[dayKey(x.date)] = x;
    }
    sleep = sl.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final ms = {for (final x in measurements) x.key: x};
    for (final x in data.measurements) {
      ms[x.key] = x;
    }
    measurements = ms.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    final ex = {for (final x in exercises) x.id: x};
    for (final x in data.exercises) {
      ex[x.id] = x;
    }
    exercises = ex.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final wk = {for (final x in workouts) x.id: x};
    for (final x in data.workouts) {
      wk[x.id] = x;
    }
    workouts = wk.values.toList()..sort((a, b) => a.sort.compareTo(b.sort));
    final ss = {for (final x in sessions) x.id: x};
    for (final x in data.sessions) {
      ss[x.id] = x;
    }
    sessions = ss.values.toList()..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final pl = {for (final x in planned) x.id: x};
    for (final x in data.planned) {
      pl[x.id] = x;
    }
    planned = pl.values.toList();
    final fd = {for (final x in foods) x.id: x};
    for (final x in data.foods) {
      fd[x.id] = x;
    }
    foods = fd.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final st = {for (final x in stores) x.id: x};
    for (final x in data.stores) {
      st[x.id] = x;
    }
    stores = st.values.toList()..sort((a, b) => a.sort.compareTo(b.sort));
    final rc = {for (final x in recipes) x.id: x};
    for (final x in data.recipes) {
      rc[x.id] = x;
    }
    recipes = rc.values.toList();
    final fl = {for (final x in foodLog) x.id: x};
    for (final x in data.foodLog) {
      fl[x.id] = x;
    }
    foodLog = fl.values.toList();
    final pm = {for (final x in plannedMeals) x.id: x};
    for (final x in data.plannedMeals) {
      pm[x.id] = x;
    }
    plannedMeals = pm.values.toList();
    final ph = {for (final x in phases) x.id: x};
    for (final x in data.phases) {
      ph[x.id] = x;
    }
    phases = ph.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    final meso = {for (final x in mesocycles) x.id: x};
    for (final x in data.mesocycles) {
      meso[x.id] = x;
    }
    mesocycles = meso.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    final gi = {for (final x in groceryItems) x.id: x};
    for (final x in data.groceryItems) {
      gi[x.id] = x;
    }
    groceryItems = gi.values.toList();
    final wa = {for (final x in water) x.id: x};
    for (final x in data.water) {
      wa[x.id] = x;
    }
    water = wa.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    final su = {for (final x in supplements) x.id: x};
    for (final x in data.supplements) {
      su[x.id] = x;
    }
    supplements = su.values.toList()..sort((a, b) => a.order.compareTo(b.order));
    final do_ = {for (final x in doses) x.id: x};
    for (final x in data.doses) {
      do_[x.id] = x;
    }
    doses = do_.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    notifyListeners();
    for (final x in data.water) {
      _save(() => _store.saveWater(x));
    }
    for (final x in data.supplements) {
      _save(() => _store.saveSupplement(x));
    }
    for (final x in data.doses) {
      _save(() => _store.saveDose(x));
    }
    _save(() => _store.saveProfile(profile));
    _save(() => _store.saveGoal(goal));
    _save(() => _store.saveSettings(settings));
    for (final x in data.weighIns) {
      _save(() => _store.saveWeighIn(x));
    }
    for (final x in data.sleep) {
      _save(() => _store.saveSleep(x));
    }
    for (final x in data.measurements) {
      _save(() => _store.saveMeasurement(x));
    }
    for (final x in data.exercises) {
      _save(() => _store.saveExercise(x));
    }
    for (final x in data.workouts) {
      _save(() => _store.saveWorkout(x));
    }
    for (final x in data.sessions) {
      _save(() => _store.saveSession(x));
    }
    for (final x in data.planned) {
      _save(() => _store.savePlanned(x));
    }
    for (final x in data.foods) {
      _save(() => _store.saveFood(x));
    }
    for (final x in data.stores) {
      _save(() => _store.saveStore(x));
    }
    for (final x in data.recipes) {
      _save(() => _store.saveRecipe(x));
    }
    for (final x in data.foodLog) {
      _save(() => _store.saveEntry(x));
    }
    for (final x in data.plannedMeals) {
      _save(() => _store.savePlannedMeal(x));
    }
    for (final x in data.phases) {
      _save(() => _store.savePhase(x));
    }
    for (final x in data.mesocycles) {
      _save(() => _store.saveMeso(x));
    }
    for (final x in data.groceryItems) {
      _save(() => _store.saveGroceryItem(x));
    }
    _syncReminder();
  }

  /// Writes a backup's progress photos into the photos folder and adds
  /// them, replacing any photo of the same day and pose. Returns how many
  /// were restored.
  Future<int> importPhotos(List<BackupPhoto> backupPhotos) async {
    final dir = photosDir;
    if (dir == null) return 0;
    var restored = 0;
    for (final p in backupPhotos) {
      try {
        await File('$dir/${p.checkin.fileName}').writeAsBytes(p.bytes, flush: true);
        savePhoto(p.checkin);
        restored++;
      } catch (e) {
        debugPrint('Restoring photo ${p.checkin.key} failed: $e');
      }
    }
    return restored;
  }

  /// Reads every progress photo file, for a backup. Missing files are skipped.
  Future<List<BackupPhoto>> photosForBackup() async {
    final out = <BackupPhoto>[];
    for (final p in photos) {
      final path = pathFor(p);
      if (path == null) continue;
      try {
        final f = File(path);
        if (await f.exists()) out.add(BackupPhoto(p, await f.readAsBytes()));
      } catch (_) {}
    }
    return out;
  }

  /// One weigh-in per day; logging again replaces that day's entry.
  void logWeight(double kg, {DateTime? day, String source = 'manual'}) {
    final date = dateOnly(day ?? DateTime.now());
    final entry = WeighIn(date: date, weightKg: kg, source: source);
    final key = dayKey(date);
    weighIns = [
      for (final w in weighIns)
        if (dayKey(w.date) != key) w,
      entry,
    ]..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    _save(() => _store.saveWeighIn(entry));
    if (dayKey(date) == dayKey(DateTime.now())) _syncReminder();
  }

  void deleteWeighIn(DateTime day) {
    final key = dayKey(day);
    weighIns = [
      for (final w in weighIns)
        if (dayKey(w.date) != key) w,
    ];
    notifyListeners();
    _save(() => _store.deleteWeighIn(day), delete: true);
    if (key == dayKey(DateTime.now())) _syncReminder();
  }

  /// One sleep entry per morning; saving again replaces it.
  void deleteSleep(DateTime day) {
    final d = dateOnly(day);
    sleep = [for (final x in sleep) if (dateOnly(x.date) != d) x];
    notifyListeners();
    _save(() => _store.deleteSleep(d), delete: true);
  }

  void logSleep(SleepEntry entry) {
    final key = dayKey(entry.date);
    sleep = [
      for (final e in sleep)
        if (dayKey(e.date) != key) e,
      entry,
    ]..sort((a, b) => a.date.compareTo(b.date));
    notifyListeners();
    _save(() => _store.saveSleep(entry));
  }

  WeighIn? weighInOn(DateTime day) {
    final key = dayKey(day);
    for (final w in weighIns.reversed) {
      if (dayKey(w.date) == key) return w;
    }
    return null;
  }

  SleepEntry? sleepOn(DateTime day) {
    final key = dayKey(day);
    for (final e in sleep.reversed) {
      if (dayKey(e.date) == key) return e;
    }
    return null;
  }

  SleepEntry? get latestSleep => sleep.isEmpty ? null : sleep.last;

  List<DayWeight> get dayWeights =>
      [for (final w in weighIns) (w.date, w.weightKg)];

  /// Mean of the last 7 days, once at least 4 days are logged.
  double? get weeklyAverageKg => weeklyAverage(dayWeights, DateTime.now());

  int get streak => streakDays(weighIns.map((w) => w.date), DateTime.now());

  /// The note written for [exerciseId] in the workout [x] was started from.
  String? workoutNoteFor(Session x, String exerciseId) {
    final w = workoutById(x.workoutId);
    if (w == null) return null;
    for (final i in w.items) {
      if (i.exerciseId == exerciseId && (i.note ?? '').isNotEmpty) return i.note;
    }
    return null;
  }

  WeighIn? get latestWeighIn => weighIns.isEmpty ? null : weighIns.last;

  // ------------------------------------------------------------ water

  /// Daily goal in ml (the default depends on units: 64 oz or 2 L).
  double get waterGoalMl => settings.waterGoalMl > 0
      ? settings.waterGoalMl
      : (settings.units == Units.imperial ? 8 * mlPerCup : 2000);

  List<WaterEntry> waterEntriesOn(DateTime day) {
    final d = dateOnly(day);
    return [for (final w in water) if (w.date == d) w];
  }

  double waterOn(DateTime day) => waterEntriesOn(day).fold(0.0, (t, w) => t + w.ml);

  void addWater(double ml, {DateTime? day}) {
    if (ml <= 0) return;
    final now = DateTime.now();
    final e = WaterEntry(id: newId('wa'), date: dateOnly(day ?? now), ml: ml, at: now);
    water = [...water, e];
    notifyListeners();
    _save(() => _store.saveWater(e));
  }

  void removeWater(WaterEntry e) {
    water = [for (final w in water) if (w.id != e.id) w];
    notifyListeners();
    _save(() => _store.deleteWater(e), delete: true);
  }

  // ------------------------------------------------------------ supplements

  /// The supplements on the daily list, in order.
  List<Supplement> get activeSupplements => [for (final x in supplements) if (x.active) x];

  Supplement? supplement(String id) {
    for (final x in supplements) {
      if (x.id == id) return x;
    }
    return null;
  }

  List<SupplementDose> dosesOn(DateTime day) {
    final d = dateOnly(day);
    return [for (final x in doses) if (x.date == d) x];
  }

  /// Taken today (or on [day]), if it was.
  SupplementDose? doseOf(Supplement x, DateTime day) {
    final d = dateOnly(day);
    for (final e in doses) {
      if (e.supplementId == x.id && e.date == d) return e;
    }
    return null;
  }

  /// Adds or updates a supplement; a new one goes to the end of the list.
  void saveSupplement(Supplement x) {
    final exists = supplement(x.id) != null;
    final item = exists
        ? x
        : x.copyWith(order: supplements.isEmpty ? 0 : supplements.map((e) => e.order).reduce((a, b) => a > b ? a : b) + 1);
    supplements = [for (final e in supplements) if (e.id != x.id) e, item]..sort((a, b) => a.order.compareTo(b.order));
    notifyListeners();
    _save(() => _store.saveSupplement(item));
  }

  /// Off the daily list. Days it was taken keep it in their history.
  void removeSupplement(Supplement x) {
    if (doses.any((d) => d.supplementId == x.id)) {
      saveSupplement(x.copyWith(active: false));
      return;
    }
    supplements = [for (final e in supplements) if (e.id != x.id) e];
    notifyListeners();
    _save(() => _store.deleteSupplement(x), delete: true);
  }

  /// Marks [x] taken on [day] (today by default) at its usual amount, or
  /// [amount] when given.
  SupplementDose takeSupplement(Supplement x, {DateTime? day, double? amount}) {
    final now = DateTime.now();
    final e = SupplementDose(
      id: newId('sd'),
      supplementId: x.id,
      name: x.name,
      date: dateOnly(day ?? now),
      at: now,
      amount: amount ?? x.amount,
      unit: x.unit,
    );
    doses = [...doses, e];
    notifyListeners();
    _save(() => _store.saveDose(e));
    return e;
  }

  void removeDose(SupplementDose e) {
    doses = [for (final x in doses) if (x.id != e.id) x];
    notifyListeners();
    _save(() => _store.deleteDose(e), delete: true);
  }

  /// Weight protein is based on: target weight when chosen and set,
  /// otherwise current weight.
  double? get proteinBasisKg {
    if (goal.proteinBasis == ProteinBasis.target &&
        goal.targetWeightKg != null) {
      return goal.targetWeightKg;
    }
    return currentWeightKg;
  }

  /// Sleep entries from the last [nights] mornings, oldest first.
  List<SleepEntry> recentSleep(int nights) {
    final n = DateTime.now();
    final start = DateTime(n.year, n.month, n.day - nights + 1);
    return [
      for (final e in sleep)
        if (!e.date.isBefore(start)) e,
    ];
  }

  double? get currentWeightKg => latestWeighIn?.weightKg;

  /// Null until birthday, height and a weight exist.
  DailyTargets? get targets {
    final weight = currentWeightKg;
    final birthday = profile.birthday;
    final height = profile.heightCm;
    if (weight == null || birthday == null || height == null) return null;
    final today = DateTime.now();
    final bmr = bmrMifflin(
      weightKg: weight,
      heightCm: height,
      age: ageOn(birthday, today),
      sex: profile.sex,
    );
    final learned = settings.useLearnedMaintenance ? learnedMaintenance : null;
    final maint = learned?.kcal ?? maintenance(bmr, profile.activity);
    final cal = calorieTarget(
      maintenanceKcal: maint,
      bmr: bmr,
      mode: goalNow.mode,
      paceKgPerWeek: goalNow.paceKgPerWeek,
    );
    final target = goal.targetWeightKg;
    return DailyTargets(
      learned: learned != null,
      bmr: bmr,
      maintenanceKcal: maint,
      kcal: cal.kcal,
      floored: cal.floored,
      proteinG: proteinTarget(
        weightKg: proteinBasisKg ?? weight,
        gPerKg: goal.proteinGPerKg,
      ),
      goalDate: target == null
          ? null
          : goalDate(
              fromKg: weight,
              toKg: target,
              paceKgPerWeek: goalNow.paceKgPerWeek,
              mode: goalNow.mode,
              today: today,
            ),
    );
  }
}

/// Makes [AppState] reachable from any screen; widgets that read it
/// rebuild when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
