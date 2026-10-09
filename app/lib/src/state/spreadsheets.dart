import 'dart:convert';

import '../calc/calc.dart';
import '../data/export.dart';
import '../data/models.dart';
import 'app_state.dart';

String _hm(int? minute) => minute == null
    ? ''
    : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

/// Every log as CSV files, in your units. Name -> UTF-8 bytes.
Map<String, List<int>> buildSpreadsheets(AppState s) {
  final imperial = s.settings.units == Units.imperial;
  final wUnit = imperial ? 'lb' : 'kg';
  final lUnit = imperial ? 'in' : 'cm';
  final dUnit = imperial ? 'mi' : 'km';
  double? w(double? kg) => kg == null ? null : (imperial ? kgToLb(kg) : kg);
  double? len(double? cm) => cm == null ? null : (imperial ? cmToInch(cm) : cm);
  double? dist(double? km) => km == null ? null : (imperial ? kmToMi(km) : km);

  final files = <String, String>{};

  files['weigh_ins.csv'] = csvFile(
    ['date', 'weight_$wUnit', 'source'],
    [for (final x in s.weighIns) [dayKey(x.date), w(x.weightKg), x.source]],
  );

  files['sleep.csv'] = csvFile(
    ['night_ending', 'bedtime', 'wake_time', 'hours', 'quality_1_to_5'],
    [
      for (final e in s.sleep)
        [
          dayKey(e.date),
          _hm(e.bedMinute),
          _hm(e.wakeMinute),
          e.durationMin == null ? null : e.durationMin! / 60,
          e.quality,
        ],
    ],
  );

  files['measurements.csv'] = csvFile(
    ['date', 'spot', 'value_$lUnit'],
    [for (final m in s.measurements) [dayKey(m.date), m.site.label, len(m.valueCm)]],
  );

  files['workouts.csv'] = csvFile(
    [
      'date', 'workout', 'exercise', 'set', 'warm_up', 'set_type', 'weight_$wUnit', 'reps',
      'rest_after_sec', 'time_sec', 'distance_$dUnit', 'avg_heart_rate', 'calories',
    ],
    [
      for (final x in s.finishedSessions)
        for (var i = 0; i < x.sets.length; i++)
          [
            dayKey(x.date),
            x.name,
            s.exerciseName(x.sets[i].exerciseId),
            // Set number within its exercise: 1, 2, 3... for each exercise.
            x.sets.take(i + 1).where((e) => e.exerciseId == x.sets[i].exerciseId).length,
            x.sets[i].warmup ? 'yes' : '',
            x.sets[i].type == SetType.normal ? '' : x.sets[i].type.label,
            w(x.sets[i].weightKg),
            x.sets[i].reps,
            x.sets[i].restSec,
            x.sets[i].durationSec,
            dist(x.sets[i].distanceKm),
            x.sets[i].heartRate,
            x.sets[i].calories,
          ],
    ],
  );

  files['food_log.csv'] = csvFile(
    ['date', 'meal', 'item', 'amount', 'unit', 'kcal', 'protein_g', 'carbs_g', 'fat_g'],
    [
      for (final e in [...s.foodLog]..sort((a, b) => a.date.compareTo(b.date)))
        [
          dayKey(e.date),
          e.meal.label,
          e.name,
          e.amount,
          e.kind == 'recipe' ? 'servings' : (e.kind == 'food' ? 'g' : ''),
          e.macros.kcal,
          e.macros.protein,
          e.macros.carbs,
          e.macros.fat,
        ],
    ],
  );

  // One row per day that has anything.
  final days = <String>{
    for (final x in s.weighIns) dayKey(x.date),
    for (final e in s.sleep) dayKey(e.date),
    for (final e in s.foodLog) dayKey(e.date),
    for (final x in s.finishedSessions) dayKey(x.date),
  }.toList()
    ..sort();
  files['daily_summary.csv'] = csvFile(
    ['date', 'weight_$wUnit', 'kcal', 'protein_g', 'sleep_hours', 'workouts'],
    [
      for (final k in days)
        () {
          final d = DateTime.parse(k);
          final food = s.entriesOn(d);
          final m = s.eatenOn(d);
          SleepEntry? night;
          for (final e in s.sleep) {
            if (dayKey(e.date) == k) night = e;
          }
          final mins = night?.durationMin;
          return <Object?>[
            k,
            w(s.weighInOn(d)?.weightKg),
            food.isEmpty ? null : m.kcal,
            food.isEmpty ? null : m.protein,
            mins == null ? null : mins / 60,
            s.finishedOn(d).length,
          ];
        }(),
    ],
  );

  return {for (final e in files.entries) e.key: utf8.encode(e.value)};
}
