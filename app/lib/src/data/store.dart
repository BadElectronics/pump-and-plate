import 'models.dart';

class StoredData {
  const StoredData({
    this.profile = const Profile(),
    this.goal = const Goal(),
    this.settings = const AppSettings(),
    this.weighIns = const [],
    this.sleep = const [],
    this.water = const [],
    this.supplements = const [],
    this.doses = const [],
    this.photos = const [],
    this.measurements = const [],
    this.exercises = const [],
    this.workouts = const [],
    this.sessions = const [],
    this.planned = const [],
    this.foods = const [],
    this.stores = const [],
    this.recipes = const [],
    this.foodLog = const [],
    this.plannedMeals = const [],
    this.groceryMarks = const [],
    this.phases = const [],
    this.mesocycles = const [],
    this.groceryItems = const [],
  });

  final Profile profile;
  final Goal goal;
  final AppSettings settings;

  /// Oldest first.
  final List<WeighIn> weighIns;

  /// Oldest first.
  final List<SleepEntry> sleep;

  /// Drinks of water.
  final List<WaterEntry> water;

  /// Supplements on your list, and each one taken.
  final List<Supplement> supplements;
  final List<SupplementDose> doses;

  /// Oldest first.
  final List<PhotoCheckin> photos;

  /// Oldest first.
  final List<Measurement> measurements;

  final List<Exercise> exercises;

  /// In display order.
  final List<Workout> workouts;

  /// Oldest first.
  final List<Session> sessions;

  /// Workouts scheduled on the calendar.
  final List<PlannedWorkout> planned;

  final List<Food> foods;
  final List<GroceryStore> stores;
  final List<Recipe> recipes;
  final List<FoodEntry> foodLog;
  final List<PlannedMeal> plannedMeals;
  final List<GroceryMark> groceryMarks;
  final List<Phase> phases;
  final List<Mesocycle> mesocycles;
  final List<GroceryItem> groceryItems;

  StoredData copyWith({
    Profile? profile,
    Goal? goal,
    AppSettings? settings,
    List<WeighIn>? weighIns,
    List<SleepEntry>? sleep,
    List<WaterEntry>? water,
    List<Supplement>? supplements,
    List<SupplementDose>? doses,
    List<PhotoCheckin>? photos,
    List<Measurement>? measurements,
    List<Exercise>? exercises,
    List<Workout>? workouts,
    List<Session>? sessions,
    List<PlannedWorkout>? planned,
    List<Food>? foods,
    List<GroceryStore>? stores,
    List<Recipe>? recipes,
    List<FoodEntry>? foodLog,
    List<PlannedMeal>? plannedMeals,
    List<GroceryMark>? groceryMarks,
    List<Phase>? phases,
    List<Mesocycle>? mesocycles,
    List<GroceryItem>? groceryItems,
  }) {
    return StoredData(
      profile: profile ?? this.profile,
      goal: goal ?? this.goal,
      settings: settings ?? this.settings,
      weighIns: weighIns ?? this.weighIns,
      sleep: sleep ?? this.sleep,
      water: water ?? this.water,
      supplements: supplements ?? this.supplements,
      doses: doses ?? this.doses,
      photos: photos ?? this.photos,
      measurements: measurements ?? this.measurements,
      exercises: exercises ?? this.exercises,
      workouts: workouts ?? this.workouts,
      sessions: sessions ?? this.sessions,
      planned: planned ?? this.planned,
      foods: foods ?? this.foods,
      stores: stores ?? this.stores,
      recipes: recipes ?? this.recipes,
      foodLog: foodLog ?? this.foodLog,
      plannedMeals: plannedMeals ?? this.plannedMeals,
      groceryMarks: groceryMarks ?? this.groceryMarks,
      phases: phases ?? this.phases,
      mesocycles: mesocycles ?? this.mesocycles,
      groceryItems: groceryItems ?? this.groceryItems,
    );
  }
}

/// Where the app keeps its data. The phone uses SqliteStore; tests use
/// MemoryStore so they run without a database.
/// Why saving failed, while it's unresolved.
enum SaveProblem {
  /// The phone's storage is full.
  full,

  /// Anything else.
  other,
}

/// True if [error] means the phone ran out of storage (SQLite's
/// "database or disk is full", or the system's "no space left on device").
bool isStorageFull(Object error) {
  final t = '$error'.toLowerCase();
  return t.contains('sqlite_full') ||
      t.contains('database or disk is full') ||
      t.contains('disk is full') ||
      t.contains('no space left') ||
      t.contains('enospc') ||
      t.contains('(code 13');
}

abstract class Store {
  Future<StoredData> load();
  Future<void> saveProfile(Profile profile);
  Future<void> saveGoal(Goal goal);
  Future<void> saveSettings(AppSettings settings);
  Future<void> saveWeighIn(WeighIn weighIn);
  Future<void> deleteWeighIn(DateTime day);
  Future<void> saveSleep(SleepEntry entry);
  Future<void> saveWater(WaterEntry entry);
  Future<void> deleteSleep(DateTime day);
  Future<void> deleteWater(WaterEntry entry);

  Future<void> saveSupplement(Supplement x);
  Future<void> deleteSupplement(Supplement x);
  Future<void> saveDose(SupplementDose x);
  Future<void> deleteDose(SupplementDose x);
  Future<void> savePhoto(PhotoCheckin photo);
  Future<void> deletePhoto(PhotoCheckin photo);
  Future<void> saveMeasurement(Measurement m);
  Future<void> deleteMeasurement(Measurement m);
  Future<void> saveExercise(Exercise e);
  Future<void> saveWorkout(Workout w);
  Future<void> deleteWorkout(Workout w);
  Future<void> saveSession(Session x);
  Future<void> deleteSession(Session x);
  Future<void> savePlanned(PlannedWorkout p);
  Future<void> deletePlanned(PlannedWorkout p);
  Future<void> saveFood(Food f);
  Future<void> saveStore(GroceryStore x);
  Future<void> deleteStore(GroceryStore x);
  Future<void> saveRecipe(Recipe r);
  Future<void> deleteRecipe(Recipe r);
  Future<void> saveEntry(FoodEntry e);
  Future<void> deleteEntry(FoodEntry e);
  Future<void> savePlannedMeal(PlannedMeal p);
  Future<void> deletePlannedMeal(PlannedMeal p);
  Future<void> saveGroceryMark(GroceryMark m);
  Future<void> savePhase(Phase p);
  Future<void> deletePhase(Phase p);
  Future<void> saveMeso(Mesocycle m);
  Future<void> saveGroceryItem(GroceryItem g);
  Future<void> deleteGroceryItem(GroceryItem g);
}

class MemoryStore implements Store {
  MemoryStore([this._data = const StoredData()]);

  StoredData _data;

  @override
  Future<StoredData> load() async => _data;

  @override
  Future<void> saveProfile(Profile profile) async {
    _data = _data.copyWith(profile: profile);
  }

  @override
  Future<void> saveGoal(Goal goal) async {
    _data = _data.copyWith(goal: goal);
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _data = _data.copyWith(settings: settings);
  }

  @override
  Future<void> saveWeighIn(WeighIn weighIn) async {
    final key = dayKey(weighIn.date);
    final list = [
      for (final w in _data.weighIns)
        if (dayKey(w.date) != key) w,
      weighIn,
    ]..sort((a, b) => a.date.compareTo(b.date));
    _data = _data.copyWith(weighIns: list);
  }

  @override
  Future<void> saveSleep(SleepEntry entry) async {
    final key = dayKey(entry.date);
    final list = [
      for (final e in _data.sleep)
        if (dayKey(e.date) != key) e,
      entry,
    ]..sort((a, b) => a.date.compareTo(b.date));
    _data = _data.copyWith(sleep: list);
  }

  @override
  Future<void> savePhoto(PhotoCheckin photo) async {
    _data = _data.copyWith(photos: [
      for (final p in _data.photos)
        if (p.key != photo.key) p,
      photo,
    ]..sort((a, b) => a.date.compareTo(b.date)));
  }

  @override
  Future<void> deletePhoto(PhotoCheckin photo) async {
    _data = _data.copyWith(photos: [
      for (final p in _data.photos)
        if (p.key != photo.key) p,
    ]);
  }

  @override
  Future<void> saveMeasurement(Measurement m) async {
    _data = _data.copyWith(measurements: [
      for (final x in _data.measurements)
        if (x.key != m.key) x,
      m,
    ]..sort((a, b) => a.date.compareTo(b.date)));
  }

  @override
  Future<void> deleteMeasurement(Measurement m) async {
    _data = _data.copyWith(measurements: [
      for (final x in _data.measurements)
        if (x.key != m.key) x,
    ]);
  }

  List<T> _upsert<T>(List<T> list, T item, String Function(T) id) => [
        for (final x in list)
          if (id(x) != id(item)) x,
        item,
      ];

  @override
  Future<void> saveExercise(Exercise e) async {
    _data = _data.copyWith(exercises: _upsert(_data.exercises, e, (x) => x.id));
  }

  @override
  Future<void> saveWorkout(Workout w) async {
    _data = _data.copyWith(workouts: _upsert(_data.workouts, w, (x) => x.id));
  }

  @override
  Future<void> deleteWorkout(Workout w) async {
    _data = _data.copyWith(workouts: [
      for (final x in _data.workouts)
        if (x.id != w.id) x,
    ]);
  }

  @override
  Future<void> saveSession(Session x) async {
    _data = _data.copyWith(sessions: _upsert(_data.sessions, x, (y) => y.id));
  }

  @override
  Future<void> deleteSession(Session x) async {
    _data = _data.copyWith(sessions: [
      for (final y in _data.sessions)
        if (y.id != x.id) y,
    ]);
  }

  @override
  Future<void> savePlanned(PlannedWorkout p) async {
    _data = _data.copyWith(planned: _upsert(_data.planned, p, (x) => x.id));
  }

  @override
  Future<void> deletePlanned(PlannedWorkout p) async {
    _data = _data.copyWith(planned: [
      for (final x in _data.planned)
        if (x.id != p.id) x,
    ]);
  }

  @override
  Future<void> deleteWeighIn(DateTime day) async {
    final key = dayKey(day);
    _data = _data.copyWith(weighIns: [
      for (final w in _data.weighIns)
        if (dayKey(w.date) != key) w,
    ]);
  }

  List<T> _without<T>(List<T> list, T item, String Function(T) id) => [
        for (final x in list)
          if (id(x) != id(item)) x,
      ];

  @override
  Future<void> saveFood(Food f) async {
    _data = _data.copyWith(foods: _upsert(_data.foods, f, (x) => x.id));
  }

  @override
  Future<void> saveStore(GroceryStore x) async {
    _data = _data.copyWith(stores: _upsert(_data.stores, x, (y) => y.id));
  }

  @override
  Future<void> deleteStore(GroceryStore x) async {
    _data = _data.copyWith(stores: _without(_data.stores, x, (y) => y.id));
  }

  @override
  Future<void> saveRecipe(Recipe r) async {
    _data = _data.copyWith(recipes: _upsert(_data.recipes, r, (x) => x.id));
  }

  @override
  Future<void> deleteRecipe(Recipe r) async {
    _data = _data.copyWith(recipes: _without(_data.recipes, r, (x) => x.id));
  }

  @override
  Future<void> saveEntry(FoodEntry e) async {
    _data = _data.copyWith(foodLog: _upsert(_data.foodLog, e, (x) => x.id));
  }

  @override
  Future<void> deleteEntry(FoodEntry e) async {
    _data = _data.copyWith(foodLog: _without(_data.foodLog, e, (x) => x.id));
  }

  @override
  Future<void> savePlannedMeal(PlannedMeal p) async {
    _data = _data.copyWith(plannedMeals: _upsert(_data.plannedMeals, p, (x) => x.id));
  }

  @override
  Future<void> deletePlannedMeal(PlannedMeal p) async {
    _data = _data.copyWith(plannedMeals: _without(_data.plannedMeals, p, (x) => x.id));
  }

  @override
  Future<void> saveGroceryMark(GroceryMark m) async {
    _data = _data.copyWith(groceryMarks: _upsert(_data.groceryMarks, m, (x) => x.foodId));
  }

  @override
  Future<void> savePhase(Phase p) async {
    _data = _data.copyWith(phases: _upsert(_data.phases, p, (x) => x.id));
  }

  @override
  Future<void> deletePhase(Phase p) async {
    _data = _data.copyWith(phases: _without(_data.phases, p, (x) => x.id));
  }

  @override
  Future<void> saveMeso(Mesocycle m) async {
    _data = _data.copyWith(mesocycles: _upsert(_data.mesocycles, m, (x) => x.id));
  }

  @override
  Future<void> saveGroceryItem(GroceryItem g) async {
    _data = _data.copyWith(groceryItems: _upsert(_data.groceryItems, g, (x) => x.id));
  }

  @override
  Future<void> deleteGroceryItem(GroceryItem g) async {
    _data = _data.copyWith(groceryItems: _without(_data.groceryItems, g, (x) => x.id));
  }

  @override
  Future<void> deleteSleep(DateTime day) async {
    final d = dateOnly(day);
    _data = _data.copyWith(sleep: [for (final x in _data.sleep) if (dateOnly(x.date) != d) x]);
  }

  @override
  Future<void> saveWater(WaterEntry entry) async {
    _data = _data.copyWith(water: _upsert(_data.water, entry, (x) => x.id));
  }

  @override
  Future<void> saveSupplement(Supplement x) async {
    _data = _data.copyWith(supplements: _upsert(_data.supplements, x, (e) => e.id));
  }

  @override
  Future<void> deleteSupplement(Supplement x) async {
    _data = _data.copyWith(supplements: _without(_data.supplements, x, (e) => e.id));
  }

  @override
  Future<void> saveDose(SupplementDose x) async {
    _data = _data.copyWith(doses: _upsert(_data.doses, x, (e) => e.id));
  }

  @override
  Future<void> deleteDose(SupplementDose x) async {
    _data = _data.copyWith(doses: _without(_data.doses, x, (e) => e.id));
  }

  @override
  Future<void> deleteWater(WaterEntry entry) async {
    _data = _data.copyWith(water: _without(_data.water, entry, (x) => x.id));
  }
}
