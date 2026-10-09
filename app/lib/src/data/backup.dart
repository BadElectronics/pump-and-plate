import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';
import 'store.dart';

/// Bump when the backup layout changes in a way older apps can't read.
const int backupFormat = 1;

class BackupError implements Exception {
  const BackupError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A progress photo travelling inside a backup.
class BackupPhoto {
  const BackupPhoto(this.checkin, this.bytes);
  final PhotoCheckin checkin;
  final Uint8List bytes;
}

/// A decoded backup: the data, plus any progress photos it carried.
class Backup {
  const Backup(this.data, this.photos);
  final StoredData data;
  final List<BackupPhoto> photos;
}

/// Everything in one JSON file. Photos, when included, are stored as
/// base64 text inside it, so a backup is always a single file.
String encodeBackup(
  StoredData data, {
  DateTime? now,
  List<BackupPhoto> photos = const [],
}) {
  return const JsonEncoder.withIndent('  ').convert({
    'app': 'fitapp',
    'format': backupFormat,
    'exported_at': (now ?? DateTime.now()).toIso8601String(),
    'profile': data.profile.toRow(),
    'goal': data.goal.toRow(),
    'settings': data.settings.toRow(),
    'weigh_ins': [for (final w in data.weighIns) w.toRow()],
    'sleep': [for (final e in data.sleep) e.toRow()],
    'measurements': [for (final m in data.measurements) m.toRow()],
    'exercises': [for (final e in data.exercises) e.toRow()],
    'workouts': [for (final w in data.workouts) w.toRow()],
    'sessions': [for (final x in data.sessions) x.toRow()],
    'planned': [for (final p in data.planned) p.toRow()],
    'foods': [for (final f in data.foods) f.toRow()],
    'stores': [for (final x in data.stores) x.toRow()],
    'recipes': [for (final r in data.recipes) r.toRow()],
    'food_log': [for (final e in data.foodLog) e.toRow()],
    'planned_meals': [for (final p in data.plannedMeals) p.toRow()],
    'phases': [for (final p in data.phases) p.toRow()],
    'mesocycles': [for (final m in data.mesocycles) m.toRow()],
    'grocery_items': [for (final g in data.groceryItems) g.toRow()],
    'water': [for (final w in data.water) w.toRow()],
    'supplements': [for (final x in data.supplements) x.toRow()],
    'supplement_doses': [for (final x in data.doses) x.toRow()],
    if (photos.isNotEmpty)
      'photos': [
        for (final p in photos) {...p.checkin.toRow(), 'data': base64Encode(p.bytes)},
      ],
  });
}

/// Reads a backup made by [encodeBackup]. Throws [BackupError] with a
/// plain-language message if the file isn't a usable backup.
StoredData decodeBackup(String text) => decodeBackupWithPhotos(text).data;

/// Like [decodeBackup], plus any progress photos in the file.
Backup decodeBackupWithPhotos(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const BackupError('This file isn\'t a Pump and Plate backup.');
  }
  if (root is! Map || root['app'] != 'fitapp') {
    throw const BackupError('This file isn\'t a Pump and Plate backup.');
  }
  final format = root['format'];
  if (format is! int || format > backupFormat) {
    throw const BackupError(
      'This backup was made by a newer version of Pump and Plate. Update the app, '
      'then import it again.',
    );
  }

  Map<String, Object?> obj(Object? v) =>
      v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  List<Map<String, Object?>> rows(Object? v) => v is List
      ? [
          for (final e in v)
            if (e is Map) Map<String, Object?>.from(e),
        ]
      : <Map<String, Object?>>[];

  try {
    final photos = <BackupPhoto>[
      for (final r in rows(root['photos']))
        if (r['data'] is String)
          BackupPhoto(PhotoCheckin.fromRow(r), base64Decode(r['data'] as String)),
    ];
    final data = StoredData(
      profile: Profile.fromRow(obj(root['profile'])),
      goal: Goal.fromRow(obj(root['goal'])),
      settings: AppSettings.fromRow(obj(root['settings'])),
      weighIns: [for (final r in rows(root['weigh_ins'])) WeighIn.fromRow(r)]
        ..sort((a, b) => a.date.compareTo(b.date)),
      sleep: [for (final r in rows(root['sleep'])) SleepEntry.fromRow(r)]
        ..sort((a, b) => a.date.compareTo(b.date)),
      photos: [for (final p in photos) p.checkin],
      measurements: [
        for (final r in rows(root['measurements'])) Measurement.fromRow(r),
      ]..sort((a, b) => a.date.compareTo(b.date)),
      exercises: [for (final r in rows(root['exercises'])) Exercise.fromRow(r)],
      workouts: [for (final r in rows(root['workouts'])) Workout.fromRow(r)]
        ..sort((a, b) => a.sort.compareTo(b.sort)),
      sessions: [for (final r in rows(root['sessions'])) Session.fromRow(r)]
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
      planned: [for (final r in rows(root['planned'])) PlannedWorkout.fromRow(r)],
      foods: [for (final r in rows(root['foods'])) Food.fromRow(r)],
      stores: [for (final r in rows(root['stores'])) GroceryStore.fromRow(r)],
      recipes: [for (final r in rows(root['recipes'])) Recipe.fromRow(r)],
      foodLog: [for (final r in rows(root['food_log'])) FoodEntry.fromRow(r)],
      plannedMeals: [for (final r in rows(root['planned_meals'])) PlannedMeal.fromRow(r)],
      phases: [for (final r in rows(root['phases'])) Phase.fromRow(r)],
      mesocycles: [for (final r in rows(root['mesocycles'])) Mesocycle.fromRow(r)],
      groceryItems: [for (final r in rows(root['grocery_items'])) GroceryItem.fromRow(r)],
      water: [for (final r in rows(root['water'])) WaterEntry.fromRow(r)],
      supplements: [for (final r in rows(root['supplements'])) Supplement.fromRow(r)],
      doses: [for (final r in rows(root['supplement_doses'])) SupplementDose.fromRow(r)],
    );
    return Backup(data, photos);
  } catch (_) {
    throw const BackupError(
      'This backup looks damaged and couldn\'t be read.',
    );
  }
}

// ---------------------------------------------------------------- workers
// Top-level so they can run on a background isolate via compute(). They
// receive only plain data, never widgets or app state.

/// Encodes a backup to file bytes. Arguments: (data, photos).
Uint8List encodeBackupBytes((StoredData, List<BackupPhoto>) args) =>
    Uint8List.fromList(utf8.encode(encodeBackup(args.$1, photos: args.$2)));

/// Decodes backup file bytes.
Backup decodeBackupBytes(Uint8List bytes) =>
    decodeBackupWithPhotos(utf8.decode(bytes, allowMalformed: true));
