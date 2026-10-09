import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'store.dart';

/// The on-phone database. Schema changes must bump [_version] and add a
/// step in [_upgrade] so updates never lose data.
class SqliteStore implements Store {
  static const _version = 30;

  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'fitapp.db'),
      version: _version,
      onCreate: (db, version) async {
        await _createV1(db);
        await _upgrade(db, 1, version);
      },
      onUpgrade: _upgrade,
    );
    _db = db;
    return db;
  }

  static Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE profile (
        id INTEGER PRIMARY KEY,
        birthday TEXT,
        height_cm REAL,
        sex TEXT,
        activity TEXT,
        waist_cm REAL,
        updated_at TEXT
      )''');
    await db.execute('''
      CREATE TABLE goal (
        id INTEGER PRIMARY KEY,
        mode TEXT,
        target_weight_kg REAL,
        pace_kg_per_week REAL,
        bf_now_pct REAL,
        bf_goal_pct REAL,
        updated_at TEXT
      )''');
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY,
        theme TEXT,
        follow_system INTEGER,
        reduce_motion INTEGER,
        units TEXT,
        updated_at TEXT
      )''');
    await db.execute('''
      CREATE TABLE weigh_in (
        date TEXT PRIMARY KEY,
        weight_kg REAL NOT NULL,
        source TEXT,
        updated_at TEXT
      )''');
  }

  /// One step per schema version. Never edit a step once it has shipped.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE goal ADD COLUMN protein_g_per_kg REAL');
      await db.execute(
        'ALTER TABLE settings ADD COLUMN sleep_goal_hours REAL',
      );
      await db.execute('''
        CREATE TABLE sleep_log (
          date TEXT PRIMARY KEY,
          bed_time TEXT,
          wake_time TEXT,
          duration_min INTEGER,
          quality INTEGER,
          source TEXT,
          updated_at TEXT
        )''');
    }
    if (from < 3) {
      await db.execute('ALTER TABLE goal ADD COLUMN protein_basis TEXT');
      await db.execute(
        'ALTER TABLE settings ADD COLUMN reminder_minute INTEGER',
      );
      await db.execute('ALTER TABLE settings ADD COLUMN onboarded INTEGER');
    }
    if (from < 4) {
      await db.execute('ALTER TABLE settings ADD COLUMN last_export TEXT');
    }
    if (from < 5) {
      await db.execute(
        'ALTER TABLE settings ADD COLUMN photo_interval_weeks INTEGER',
      );
      await db.execute('''
        CREATE TABLE photo_checkin (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          pose TEXT NOT NULL,
          file_name TEXT NOT NULL,
          weight_kg REAL,
          updated_at TEXT
        )''');
    }
    if (from < 6) {
      await db.execute('ALTER TABLE settings ADD COLUMN measurements_on INTEGER');
      await db.execute('''
        CREATE TABLE measurement (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          site TEXT NOT NULL,
          value_cm REAL NOT NULL,
          updated_at TEXT
        )''');
    }
    if (from < 7) {
      await db.execute('''
        CREATE TABLE exercise (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          muscle TEXT,
          bodyweight INTEGER,
          custom INTEGER,
          archived INTEGER,
          updated_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE workout (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          sort INTEGER,
          items TEXT,
          updated_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE session (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          name TEXT,
          workout_id TEXT,
          started_at TEXT,
          ended_at TEXT,
          sets TEXT,
          updated_at TEXT
        )''');
    }
    if (from < 8) {
      await db.execute('''
        CREATE TABLE planned_workout (
          id TEXT PRIMARY KEY,
          date TEXT NOT NULL,
          workout_id TEXT NOT NULL,
          updated_at TEXT
        )''');
    }
    if (from < 9) {
      await db.execute('ALTER TABLE settings ADD COLUMN rest_notification INTEGER');
      await db.execute('ALTER TABLE settings ADD COLUMN rest_alert INTEGER');
    }
    if (from < 10) {
      await db.execute('ALTER TABLE settings ADD COLUMN rest_alert_asked INTEGER');
      // The rest pop-up is now on by default, for existing users too.
      await db.execute('UPDATE settings SET rest_alert = 1');
    }
    if (from < 11) {
      await db.execute('ALTER TABLE exercise ADD COLUMN kind TEXT');
      await db.execute('ALTER TABLE exercise ADD COLUMN note TEXT');
      await db.execute('ALTER TABLE session ADD COLUMN note TEXT');
    }
    if (from < 12) {
      await db.execute('''
        CREATE TABLE food (
          id TEXT PRIMARY KEY, name TEXT NOT NULL,
          kcal REAL, protein REAL, carbs REAL, fat REAL,
          by_item INTEGER, grams_per_item REAL, prices TEXT,
          custom INTEGER, archived INTEGER, updated_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE store (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, sort INTEGER, updated_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE recipe (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, servings REAL,
          items TEXT, note TEXT, updated_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE food_log (
          id TEXT PRIMARY KEY, date TEXT NOT NULL, meal TEXT, kind TEXT,
          ref_id TEXT, amount REAL, name TEXT,
          kcal REAL, protein REAL, carbs REAL, fat REAL, updated_at TEXT
        )''');
      await db.execute('CREATE INDEX food_log_date ON food_log (date)');
    }
    if (from < 13) {
      await db.execute('ALTER TABLE settings ADD COLUMN max_stores INTEGER');
      await db.execute('ALTER TABLE settings ADD COLUMN use_learned INTEGER');
      await db.execute('''
        CREATE TABLE planned_meal (
          id TEXT PRIMARY KEY, date TEXT NOT NULL, meal TEXT, kind TEXT,
          ref_id TEXT, amount REAL, logged_id TEXT, updated_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE grocery_mark (
          id TEXT PRIMARY KEY, in_cart INTEGER, at_home INTEGER, updated_at TEXT
        )''');
    }
    if (from < 14) {
      for (final col in [
        'lock_enabled INTEGER',
        'lock_pin_hash TEXT',
        'lock_pin_salt TEXT',
        'lock_biometric INTEGER',
        'lock_after_sec INTEGER',
        'summary_seen_week TEXT',
      ]) {
        await db.execute('ALTER TABLE settings ADD COLUMN $col');
      }
      await db.execute('''
        CREATE TABLE phase (
          id TEXT PRIMARY KEY, mode TEXT, pace REAL, start_day TEXT NOT NULL,
          end_day TEXT, updated_at TEXT
        )''');
    }
    if (from < 15) {
      await db.execute('ALTER TABLE planned_workout ADD COLUMN meso_id TEXT');
      await db.execute('ALTER TABLE planned_workout ADD COLUMN meso_week INTEGER');
      await db.execute('ALTER TABLE session ADD COLUMN meso_id TEXT');
      await db.execute('ALTER TABLE session ADD COLUMN meso_week INTEGER');
      await db.execute('''
        CREATE TABLE mesocycle (
          id TEXT PRIMARY KEY, name TEXT, start_day TEXT NOT NULL, weeks INTEGER,
          deload INTEGER, progression TEXT, weight_step_kg REAL, schedule TEXT,
          ended_early TEXT, updated_at TEXT
        )''');
    }
    if (from < 16) {
      await db.execute('ALTER TABLE settings ADD COLUMN nickname TEXT');
      await db.execute('ALTER TABLE settings ADD COLUMN nickname_asked INTEGER');
    }
    if (from < 17) {
      await db.execute('ALTER TABLE settings ADD COLUMN own_list_store TEXT');
      await db.execute('''
        CREATE TABLE grocery_item (
          id TEXT PRIMARY KEY, label TEXT, food_id TEXT, amount REAL,
          done INTEGER, updated_at TEXT
        )''');
    }
    if (from < 18) {
      await db.execute('ALTER TABLE food ADD COLUMN barcode TEXT');
      await db.execute('ALTER TABLE food ADD COLUMN brand TEXT');
      await db.execute('ALTER TABLE food ADD COLUMN serving_g REAL');
      await db.execute('ALTER TABLE settings ADD COLUMN barcode_online INTEGER');
    }
    if (from < 19) {
      await db.execute('ALTER TABLE settings ADD COLUMN tour_seen INTEGER');
    }
    if (from < 20) {
      await db.execute('ALTER TABLE settings ADD COLUMN ai_tier TEXT');
    }
    if (from < 21) {
      for (final col in [
        'auto_backup INTEGER', 'backup_days INTEGER', 'backup_keep INTEGER', 'backup_photos INTEGER',
        'backup_uri TEXT', 'backup_folder TEXT', 'last_auto_backup TEXT', 'backup_error TEXT',
        'backup_bytes INTEGER',
      ]) {
        await db.execute('ALTER TABLE settings ADD COLUMN $col');
      }
    }
    if (from < 22) {
      await db.execute('ALTER TABLE settings ADD COLUMN week_sunday INTEGER');
    }
    if (from < 23) {
      for (final col in ['dark_schedule INTEGER', 'dark_from INTEGER', 'dark_to INTEGER', 'dark_theme TEXT']) {
        await db.execute('ALTER TABLE settings ADD COLUMN $col');
      }
    }
    if (from < 24) {
      await db.execute('''
        CREATE TABLE water (
          id TEXT PRIMARY KEY, date TEXT NOT NULL, ml REAL NOT NULL, at TEXT
        )''');
      await db.execute('ALTER TABLE settings ADD COLUMN water_goal REAL');
    }
    if (from < 25) {
      await db.execute('ALTER TABLE settings ADD COLUMN ai_idle_unload INTEGER');
    }
    if (from < 26) {
      for (final col in ['fiber REAL', 'sugar REAL', 'sodium_mg REAL', 'source_id TEXT']) {
        await db.execute('ALTER TABLE food ADD COLUMN $col');
      }
      await db.execute('ALTER TABLE settings ADD COLUMN online_food_search INTEGER');
    }
    if (from < 27) {
      await db.execute('ALTER TABLE exercise ADD COLUMN muscles_primary TEXT');
      await db.execute('ALTER TABLE exercise ADD COLUMN muscles_secondary TEXT');
    }
    if (from < 28) {
      await db.execute('ALTER TABLE food ADD COLUMN favorite INTEGER');
    }
    if (from < 29) {
      await db.execute('ALTER TABLE workout ADD COLUMN note TEXT');
    }
    if (from < 30) {
      for (final col in [
        'ai_notice_off INTEGER', 'rest_sound TEXT', 'rest_sound_name TEXT', 'supplements_on INTEGER', 'heads_map INTEGER',
      ]) {
        await db.execute('ALTER TABLE settings ADD COLUMN $col');
      }
      await db.execute('''
        CREATE TABLE supplement (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, amount REAL, unit TEXT, sort INTEGER, active INTEGER,
          updated_at TEXT
        )''');
      await db.execute('''
        CREATE TABLE supplement_dose (
          id TEXT PRIMARY KEY, supplement_id TEXT, name TEXT, date TEXT NOT NULL, at TEXT, amount REAL, unit TEXT
        )''');
      // Each workout keeps the exercise notes as they were that day.
      await db.execute('ALTER TABLE session ADD COLUMN exercise_notes TEXT');
      // Which muscle heads an exercise works, when you've changed it.
      await db.execute('ALTER TABLE exercise ADD COLUMN heads TEXT');
    }
  }

  Future<Map<String, Object?>?> _single(Database db, String table) async {
    final rows = await db.query(table, where: 'id = 1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<StoredData> load() async {
    final db = await _open();
    final profile = await _single(db, 'profile');
    final goal = await _single(db, 'goal');
    final settings = await _single(db, 'settings');
    final weighIns = await db.query('weigh_in', orderBy: 'date ASC');
    final sleep = await db.query('sleep_log', orderBy: 'date ASC');
    final photos = await db.query('photo_checkin', orderBy: 'date ASC');
    final measurements = await db.query('measurement', orderBy: 'date ASC');
    final exercises = await db.query('exercise', orderBy: 'name ASC');
    final workouts = await db.query('workout', orderBy: 'sort ASC');
    final sessions = await db.query('session', orderBy: 'started_at ASC');
    final planned = await db.query('planned_workout', orderBy: 'date ASC');
    final foods = await db.query('food', orderBy: 'name ASC');
    final stores = await db.query('store', orderBy: 'sort ASC');
    final recipes = await db.query('recipe', orderBy: 'name ASC');
    final foodLog = await db.query('food_log', orderBy: 'date ASC');
    final plannedMeals = await db.query('planned_meal', orderBy: 'date ASC');
    final groceryMarks = await db.query('grocery_mark');
    final phases = await db.query('phase', orderBy: 'start_day ASC');
    final mesocycles = await db.query('mesocycle', orderBy: 'start_day ASC');
    final groceryItems = await db.query('grocery_item', orderBy: 'updated_at ASC');
    final water = await db.query('water', orderBy: 'at ASC');
    final supplements = await db.query('supplement', orderBy: 'sort ASC');
    final doses = await db.query('supplement_dose', orderBy: 'at ASC');
    return StoredData(
      profile: profile == null ? const Profile() : Profile.fromRow(profile),
      goal: goal == null ? const Goal() : Goal.fromRow(goal),
      settings: settings == null
          ? const AppSettings()
          : AppSettings.fromRow(settings),
      weighIns: [for (final r in weighIns) WeighIn.fromRow(r)],
      sleep: [for (final r in sleep) SleepEntry.fromRow(r)],
      photos: [for (final r in photos) PhotoCheckin.fromRow(r)],
      measurements: [for (final r in measurements) Measurement.fromRow(r)],
      exercises: [for (final r in exercises) Exercise.fromRow(r)],
      workouts: [for (final r in workouts) Workout.fromRow(r)],
      sessions: [for (final r in sessions) Session.fromRow(r)],
      planned: [for (final r in planned) PlannedWorkout.fromRow(r)],
      foods: [for (final r in foods) Food.fromRow(r)],
      stores: [for (final r in stores) GroceryStore.fromRow(r)],
      recipes: [for (final r in recipes) Recipe.fromRow(r)],
      foodLog: [for (final r in foodLog) FoodEntry.fromRow(r)],
      plannedMeals: [for (final r in plannedMeals) PlannedMeal.fromRow(r)],
      groceryMarks: [for (final r in groceryMarks) GroceryMark.fromRow(r)],
      phases: [for (final r in phases) Phase.fromRow(r)],
      mesocycles: [for (final r in mesocycles) Mesocycle.fromRow(r)],
      groceryItems: [for (final r in groceryItems) GroceryItem.fromRow(r)],
      water: [for (final r in water) WaterEntry.fromRow(r)],
      supplements: [for (final r in supplements) Supplement.fromRow(r)],
      doses: [for (final r in doses) SupplementDose.fromRow(r)],
    );
  }

  Future<void> _put(String table, Map<String, Object?> row) async {
    final db = await _open();
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> saveProfile(Profile profile) => _put('profile', profile.toRow());

  @override
  Future<void> saveGoal(Goal goal) => _put('goal', goal.toRow());

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _put('settings', settings.toRow());

  @override
  Future<void> saveWeighIn(WeighIn weighIn) =>
      _put('weigh_in', weighIn.toRow());

  @override
  Future<void> saveSleep(SleepEntry entry) => _put('sleep_log', entry.toRow());

  @override
  Future<void> deleteWeighIn(DateTime day) async {
    final db = await _open();
    await db.delete('weigh_in', where: 'date = ?', whereArgs: [dayKey(day)]);
  }

  @override
  Future<void> savePhoto(PhotoCheckin photo) =>
      _put('photo_checkin', photo.toRow());

  @override
  Future<void> saveMeasurement(Measurement m) => _put('measurement', m.toRow());

  @override
  Future<void> deleteMeasurement(Measurement m) async {
    final db = await _open();
    await db.delete('measurement', where: 'id = ?', whereArgs: [m.key]);
  }

  @override
  Future<void> saveExercise(Exercise e) => _put('exercise', e.toRow());

  @override
  Future<void> saveWorkout(Workout w) => _put('workout', w.toRow());

  @override
  Future<void> deleteWorkout(Workout w) async {
    final db = await _open();
    await db.delete('workout', where: 'id = ?', whereArgs: [w.id]);
  }

  @override
  Future<void> saveSession(Session x) => _put('session', x.toRow());

  @override
  Future<void> deleteSession(Session x) async {
    final db = await _open();
    await db.delete('session', where: 'id = ?', whereArgs: [x.id]);
  }

  @override
  Future<void> savePlanned(PlannedWorkout p) => _put('planned_workout', p.toRow());

  @override
  Future<void> deletePlanned(PlannedWorkout p) async {
    final db = await _open();
    await db.delete('planned_workout', where: 'id = ?', whereArgs: [p.id]);
  }

  Future<void> _delete(String table, String id) async {
    final db = await _open();
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> saveFood(Food f) => _put('food', f.toRow());

  @override
  Future<void> saveStore(GroceryStore x) => _put('store', x.toRow());

  @override
  Future<void> deleteStore(GroceryStore x) => _delete('store', x.id);

  @override
  Future<void> saveRecipe(Recipe r) => _put('recipe', r.toRow());

  @override
  Future<void> deleteRecipe(Recipe r) => _delete('recipe', r.id);

  @override
  Future<void> saveEntry(FoodEntry e) => _put('food_log', e.toRow());

  @override
  Future<void> deleteEntry(FoodEntry e) => _delete('food_log', e.id);

  @override
  Future<void> savePlannedMeal(PlannedMeal p) => _put('planned_meal', p.toRow());

  @override
  Future<void> deletePlannedMeal(PlannedMeal p) => _delete('planned_meal', p.id);

  @override
  Future<void> saveGroceryMark(GroceryMark m) => _put('grocery_mark', m.toRow());

  @override
  Future<void> savePhase(Phase p) => _put('phase', p.toRow());

  @override
  Future<void> deletePhase(Phase p) => _delete('phase', p.id);

  @override
  Future<void> saveMeso(Mesocycle m) => _put('mesocycle', m.toRow());

  @override
  Future<void> saveGroceryItem(GroceryItem g) => _put('grocery_item', g.toRow());

  @override
  Future<void> deleteGroceryItem(GroceryItem g) => _delete('grocery_item', g.id);

  @override
  Future<void> deleteSleep(DateTime day) async {
    final db = await _open();
    await db.delete('sleep_log', where: 'date = ?', whereArgs: [dayKey(day)]);
  }

  @override
  Future<void> saveWater(WaterEntry entry) => _put('water', entry.toRow());

  @override
  Future<void> deleteWater(WaterEntry entry) => _delete('water', entry.id);

  @override
  Future<void> saveSupplement(Supplement x) => _put('supplement', x.toRow());

  @override
  Future<void> deleteSupplement(Supplement x) => _delete('supplement', x.id);

  @override
  Future<void> saveDose(SupplementDose x) => _put('supplement_dose', x.toRow());

  @override
  Future<void> deleteDose(SupplementDose x) => _delete('supplement_dose', x.id);

  @override
  Future<void> deletePhoto(PhotoCheckin photo) async {
    final db = await _open();
    await db.delete('photo_checkin', where: 'id = ?', whereArgs: [photo.key]);
  }
}
