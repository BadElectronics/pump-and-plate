import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/backup.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';

void main() {
  group('units', () {
    test('pounds and kilograms round-trip', () {
      expect(lbToKg(182.4), closeTo(82.735, 0.001));
      expect(kgToLb(lbToKg(182.4)), closeTo(182.4, 1e-9));
      expect(inchToCm(71), closeTo(180.34, 1e-9));
    });
  });

  group('age', () {
    test('counts birthdays correctly', () {
      expect(ageOn(DateTime(1994, 5, 12), DateTime(2026, 10, 1)), 32);
      expect(ageOn(DateTime(1994, 10, 2), DateTime(2026, 10, 1)), 31);
      expect(ageOn(DateTime(1994, 10, 1), DateTime(2026, 10, 1)), 32);
    });
  });

  group('energy', () {
    final bmrMale = bmrMifflin(
      weightKg: 82.74,
      heightCm: 180.34,
      age: 32,
      sex: Sex.male,
    );

    test('Mifflin-St Jeor matches a hand calculation', () {
      // 827.4 + 1127.125 - 160 + 5
      expect(bmrMale, closeTo(1799.525, 0.001));
      final female = bmrMifflin(
        weightKg: 82.74,
        heightCm: 180.34,
        age: 32,
        sex: Sex.female,
      );
      expect(female, closeTo(1633.525, 0.001));
    });

    test('maintenance uses the activity factor', () {
      expect(maintenance(bmrMale, Activity.light), closeTo(2474.35, 0.01));
      expect(maintenance(1000, Activity.very), closeTo(1725, 1e-9));
    });

    test('losing 0.75 lb a week takes about 374 kcal a day', () {
      final t = calorieTarget(
        maintenanceKcal: 2474.35,
        bmr: bmrMale,
        mode: GoalMode.lose,
        paceKgPerWeek: lbToKg(0.75),
      );
      expect(t.kcal, closeTo(2100.1, 0.2));
      expect(t.floored, isFalse);
    });

    test('target never drops below BMR or 1,200', () {
      final t = calorieTarget(
        maintenanceKcal: 1800,
        bmr: 1500,
        mode: GoalMode.lose,
        paceKgPerWeek: 1.0,
      );
      expect(t.kcal, 1500);
      expect(t.floored, isTrue);
    });

    test('maintain and gain', () {
      expect(
        calorieTarget(
          maintenanceKcal: 2400,
          bmr: 1700,
          mode: GoalMode.maintain,
          paceKgPerWeek: 0.5,
        ).kcal,
        2400,
      );
      expect(
        calorieTarget(
          maintenanceKcal: 2400,
          bmr: 1700,
          mode: GoalMode.gain,
          paceKgPerWeek: 0.25,
        ).kcal,
        closeTo(2675, 0.001),
      );
    });

    test('protein is body weight times the chosen grams', () {
      expect(defaultProteinGPerKg * kgPerLb, closeTo(0.9, 1e-9));
      expect(
        proteinTarget(weightKg: lbToKg(182.4), gPerKg: defaultProteinGPerKg),
        closeTo(164.16, 0.01),
      );
      expect(
        proteinTarget(weightKg: lbToKg(200), gPerKg: 1.2 / kgPerLb),
        closeTo(240, 1e-6),
      );
    });

    test('goal date at a steady pace', () {
      final d = goalDate(
        fromKg: 83.1,
        toKg: 79.4,
        paceKgPerWeek: 0.37,
        mode: GoalMode.lose,
        today: DateTime(2026, 10, 1),
      );
      // 3.7 kg / 0.37 kg per week = 10 weeks = 70 days
      expect(d, DateTime(2026, 12, 10));
      expect(
        goalDate(
          fromKg: 80,
          toKg: 85,
          paceKgPerWeek: 0.3,
          mode: GoalMode.lose,
          today: DateTime(2026, 10, 1),
        ),
        isNull,
      );
    });
  });

  group('body metrics', () {
    test('BMI', () {
      expect(bmi(82.74, 180.34), closeTo(25.44, 0.01));
      expect(bmiCategory(25.44), '25–29.9 range');
      expect(bmiCategory(22), '18.5–24.9 range');
    });

    test('lean mass, FFMI and weight at goal body fat', () {
      final lean = leanMassKg(82.74, 20);
      expect(lean, closeTo(66.192, 0.001));
      expect(ffmiNormalized(lean, 180.34), closeTo(20.33, 0.01));
      expect(ffmiCategory(20.33), 'Above average');
      expect(weightAtBodyFat(lean, 15), closeTo(77.873, 0.001));
    });

    test('Katch-McArdle and waist-to-height', () {
      expect(bmrKatch(66.192), closeTo(1799.75, 0.01));
      expect(waistToHeight(86.36, 180.34), closeTo(0.479, 0.001));
    });
  });

  group('trend', () {
    final d = DateTime(2026, 10, 1);
    DateTime day(int back) => DateTime(d.year, d.month, d.day - back);

    test('weekly average needs 4 days in the window', () {
      final three = <DayWeight>[(day(0), 80), (day(1), 81), (day(2), 82)];
      expect(weeklyAverage(three, d), isNull);
      final four = [...three, (day(6), 83.0)];
      expect(weeklyAverage(four, d), closeTo(81.5, 1e-9));
      // Day 7 back is outside the 7-day window.
      expect(weeklyAverage([...three, (day(7), 99.0)], d), isNull);
    });

    test('weekly series skips thin weeks and runs oldest first', () {
      final entries = <DayWeight>[
        (day(0), 80), (day(1), 80.4),
        (day(7), 81), (day(8), 81.4),
        (day(14), 90),
      ];
      final series = weeklySeries(entries, d, 3, minCount: 2);
      expect(series.length, 2);
      expect(series.first.$1, day(7));
      expect(series.first.$2, closeTo(81.2, 1e-9));
      expect(series.last.$2, closeTo(80.2, 1e-9));
    });

    test('streak counts back from today, or yesterday if today is empty', () {
      expect(streakDays([day(0), day(1), day(2), day(4)], d), 3);
      expect(streakDays([day(1), day(2)], d), 2);
      expect(streakDays([day(3)], d), 0);
    });

    test('planned change from the calorie gap', () {
      expect(
        plannedChangeKgPerDay(maintenanceKcal: 2474, plannedKcal: 2100),
        closeTo(-374 / 7700, 1e-12),
      );
    });
  });

  group('sleep', () {
    test('duration crosses midnight', () {
      expect(sleepMinutes(23 * 60 + 15, 6 * 60 + 45), 450);
      expect(sleepMinutes(1 * 60, 8 * 60), 420);
      expect(sleepMinutes(22 * 60, 22 * 60), isNull);
    });

    test('formatting', () {
      expect(formatSleep(450), '7 h 30 m');
      expect(formatSleep(420), '7 h');
      expect(formatSleep(425), '7 h 05 m');
    });
  });

  group('sleep stats', () {
    test('average minutes', () {
      expect(averageMinutes([420, 480]), 450);
      expect(averageMinutes([]), isNull);
    });

    test('bedtime spread treats midnight as continuous', () {
      final spread = bedtimeSpreadMinutes([23 * 60 + 30, 30, 23 * 60 + 30, 30]);
      expect(spread, closeTo(30.04, 0.05));
      expect(bedtimeSpreadMinutes([22 * 60, 22 * 60, 22 * 60]), closeTo(0, 0.01));
      expect(bedtimeSpreadMinutes([22 * 60, 23 * 60]), isNull);
    });
  });

  group('backup', () {
    test('round-trips everything', () {
      final data = StoredData(
        profile: Profile(
          birthday: DateTime(1994, 5, 12),
          heightCm: 180.34,
          sex: Sex.male,
          activity: Activity.moderate,
          waistCm: 86.4,
        ),
        goal: const Goal(
          mode: GoalMode.lose,
          targetWeightKg: 79.4,
          paceKgPerWeek: 0.45,
          bodyFatNowPct: 20,
          bodyFatGoalPct: 15,
          proteinGPerKg: 2.2,
          proteinBasis: ProteinBasis.target,
        ),
        settings: const AppSettings(
          themeId: 'night',
          units: Units.metric,
          sleepGoalHours: 7.5,
          reminderMinute: 390,
          onboarded: true,
        ),
        weighIns: [
          WeighIn(date: DateTime(2026, 9, 30), weightKg: 82.9),
          WeighIn(date: DateTime(2026, 10, 1), weightKg: 82.7, source: 'keypad'),
        ],
        sleep: [
          SleepEntry(
            date: DateTime(2026, 10, 1),
            bedMinute: 23 * 60 + 15,
            wakeMinute: 6 * 60 + 45,
            durationMin: 450,
            quality: 4,
          ),
        ],
      );
      final withMeasurements = data.copyWith(measurements: [
        Measurement(date: DateTime(2026, 10, 1), site: MeasureSite.bicepLeft, valueCm: 38.1),
        Measurement(date: DateTime(2026, 10, 1), site: MeasureSite.waist, valueCm: 86.4),
      ]);
      final back = decodeBackup(encodeBackup(withMeasurements));
      expect(back.measurements.length, 2);
      expect(
        back.measurements.firstWhere((m) => m.site == MeasureSite.bicepLeft).valueCm,
        38.1,
      );
      expect(back.profile.birthday, DateTime(1994, 5, 12));
      expect(back.profile.heightCm, 180.34);
      expect(back.profile.activity, Activity.moderate);
      expect(back.goal.targetWeightKg, 79.4);
      expect(back.goal.proteinGPerKg, 2.2);
      expect(back.goal.proteinBasis, ProteinBasis.target);
      expect(back.settings.themeId, 'night');
      expect(back.settings.units, Units.metric);
      expect(back.settings.sleepGoalHours, 7.5);
      expect(back.weighIns.length, 2);
      expect(back.weighIns.last.weightKg, 82.7);
      expect(back.weighIns.last.source, 'keypad');
      expect(back.sleep.single.durationMin, 450);
      expect(back.sleep.single.bedMinute, 23 * 60 + 15);
      expect(back.sleep.single.quality, 4);
    });

    test('carries progress photos when included', () {
      final bytes = Uint8List.fromList([255, 216, 255, 224, 1, 2, 3, 250]);
      final photo = PhotoCheckin(
        date: DateTime(2026, 10, 1),
        pose: PhotoPose.side,
        fileName: '2026-10-01_side_1.jpg',
        weightKg: 82.7,
      );
      final text = encodeBackup(
        const StoredData(),
        photos: [BackupPhoto(photo, bytes)],
      );
      final back = decodeBackupWithPhotos(text);
      expect(back.photos.single.checkin.pose, PhotoPose.side);
      expect(back.photos.single.checkin.fileName, '2026-10-01_side_1.jpg');
      expect(back.photos.single.checkin.weightKg, 82.7);
      expect(back.photos.single.bytes, bytes);
      expect(back.data.photos.single.date, DateTime(2026, 10, 1));
      // Without photos the key is left out entirely.
      expect(encodeBackup(const StoredData()).contains('"photos"'), isFalse);
    });

    test('encodes and decodes on a real background isolate', () async {
      // Catches the "object is unsendable" class of bug: compute() fails
      // if the work or its data drags anything unsendable along.
      final photo = PhotoCheckin(
        date: DateTime(2026, 10, 1),
        pose: PhotoPose.front,
        fileName: 'a.jpg',
      );
      final data = StoredData(
        weighIns: [WeighIn(date: DateTime(2026, 10, 1), weightKg: 82.7)],
      );
      final bytes = await compute(
        encodeBackupBytes,
        (data, [BackupPhoto(photo, Uint8List.fromList([1, 2, 3]))]),
      );
      final back = await compute(decodeBackupBytes, bytes);
      expect(back.data.weighIns.single.weightKg, 82.7);
      expect(back.photos.single.bytes, [1, 2, 3]);
    });

    test('rejects files that are not backups', () {
      expect(() => decodeBackup('hello'), throwsA(isA<BackupError>()));
      expect(() => decodeBackup('{"app":"other"}'), throwsA(isA<BackupError>()));
      expect(
        () => decodeBackup('{"app":"fitapp","format":99}'),
        throwsA(isA<BackupError>()),
      );
    });
  });

  group('photos due', () {
    final today = DateTime(2026, 10, 1);
    test('due when never taken, off when interval is 0', () {
      expect(photosDue(lastCheckin: null, intervalWeeks: 1, today: today), isTrue);
      expect(photosDue(lastCheckin: null, intervalWeeks: 0, today: today), isFalse);
    });
    test('due once the interval has passed', () {
      expect(
        photosDue(lastCheckin: DateTime(2026, 9, 24), intervalWeeks: 1, today: today),
        isTrue,
      );
      expect(
        photosDue(lastCheckin: DateTime(2026, 9, 25), intervalWeeks: 1, today: today),
        isFalse,
      );
      expect(
        photosDue(lastCheckin: DateTime(2026, 9, 17), intervalWeeks: 2, today: today),
        isTrue,
      );
      expect(
        photosDue(lastCheckin: DateTime(2026, 9, 24), intervalWeeks: 2, today: today),
        isFalse,
      );
    });
  });

  group('strength', () {
    test('Epley e1RM with a single counting as itself', () {
      expect(e1rm(100, 1), 100);
      expect(e1rm(100, 10), closeTo(133.33, 0.01));
      expect(e1rm(lbToKg(190), 8)! / kgPerLb, closeTo(240.67, 0.01));
      expect(e1rm(100, 11), isNull);
      expect(e1rm(0, 5), isNull);
    });

    test('workout length estimate', () {
      // 4 sets: 160 s of work + 3 rests of 150 s = 610 s, about 10 min.
      expect(estimateMinutes([(4, 150)]), 10);
      expect(estimateMinutes([(3, 90), (3, 60)]), 9);
    });
  });

  group('training backup', () {
    test('round-trips exercises, workouts and sessions', () {
      final data = StoredData(
        exercises: const [Exercise(id: 'x1', name: 'Zercher squat', muscle: 'Legs', custom: true)],
        workouts: const [
          Workout(id: 'w1', name: 'Legs', items: [
            WorkoutItem(exerciseId: 'x1', sets: 4, repsLow: 6, repsHigh: 8, loadKg: 100, restSec: 150),
          ]),
        ],
        sessions: [
          Session(
            id: 's1',
            date: DateTime(2026, 10, 1),
            name: 'Legs',
            workoutId: 'w1',
            startedAt: DateTime(2026, 10, 1, 7, 0),
            endedAt: DateTime(2026, 10, 1, 7, 50),
            sets: const [
              SetEntry(exerciseId: 'x1', weightKg: 60, reps: 8, warmup: true, done: true),
              SetEntry(exerciseId: 'x1', weightKg: 100, reps: 7, restSec: 140, done: true),
            ],
          ),
        ],
      );
      final back = decodeBackup(encodeBackup(data));
      expect(back.exercises.single.name, 'Zercher squat');
      expect(back.exercises.single.custom, isTrue);
      final item = back.workouts.single.items.single;
      expect(item.sets, 4);
      expect(item.repsHigh, 8);
      expect(item.loadKg, 100);
      expect(item.restSec, 150);
      final x = back.sessions.single;
      expect(x.finished, isTrue);
      expect(x.sets.first.warmup, isTrue);
      expect(x.sets.last.reps, 7);
      expect(x.sets.last.restSec, 140);
    });
  });

  group('cardio', () {
    test('clock text and parsing', () {
      expect(clockText(95), '1:35');
      expect(clockText(3725), '1:02:05');
      expect(parseClock('30'), 1800);
      expect(parseClock('22.5'), 1350);
      expect(parseClock('30:15'), 1815);
      expect(parseClock('1:02:05'), 3725);
      expect(parseClock(''), isNull);
      expect(parseClock('a:b'), isNull);
    });

    test('pace and distance units', () {
      expect(paceSecPer(3.1, 1800), closeTo(580.65, 0.01));
      expect(paceSecPer(null, 1800), isNull);
      expect(kmToMi(5), closeTo(3.107, 0.001));
      expect(miToKm(kmToMi(10)), closeTo(10, 1e-9));
    });
  });
}
