import 'dart:math' as math;

/// All of the app's math lives here, in plain Dart with no Flutter imports,
/// so every formula can be unit-tested. Inputs are metric: kg, cm, years.

// ---------------------------------------------------------------- units

const double kgPerLb = 0.45359237;
const double cmPerInch = 2.54;

double lbToKg(double lb) => lb * kgPerLb;
double kgToLb(double kg) => kg / kgPerLb;
double inchToCm(double inch) => inch * cmPerInch;
double cmToInch(double cm) => cm / cmPerInch;

// ---------------------------------------------------------------- enums

enum Sex { male, female }

enum Activity { sedentary, light, moderate, very }

enum GoalMode { lose, maintain, gain }

enum Units { imperial, metric }

extension ActivityInfo on Activity {
  double get factor => switch (this) {
        Activity.sedentary => 1.2,
        Activity.light => 1.375,
        Activity.moderate => 1.55,
        Activity.very => 1.725,
      };

  String get label => switch (this) {
        Activity.sedentary => 'Mostly sitting',
        Activity.light => 'Lightly active',
        Activity.moderate => 'Moderately active',
        Activity.very => 'Very active',
      };

  String get detail => switch (this) {
        Activity.sedentary => 'Desk job, little walking',
        Activity.light => 'Some walking, on your feet part of the day',
        Activity.moderate => 'On your feet most of the day',
        Activity.very => 'Physical job or lots of daily movement',
      };
}

// ---------------------------------------------------------------- age

int ageOn(DateTime birthday, DateTime today) {
  var age = today.year - birthday.year;
  final beforeBirthday = today.month < birthday.month ||
      (today.month == birthday.month && today.day < birthday.day);
  if (beforeBirthday) age--;
  return age;
}

// ---------------------------------------------------------------- energy

/// Calories per kg of body weight change.
const double kcalPerKg = 7700;

/// Resting burn, Mifflin-St Jeor.
double bmrMifflin({
  required double weightKg,
  required double heightCm,
  required int age,
  required Sex sex,
}) {
  final s = sex == Sex.male ? 5.0 : -161.0;
  return 10 * weightKg + 6.25 * heightCm - 5 * age + s;
}

/// Resting burn from lean mass, Katch-McArdle.
double bmrKatch(double leanKg) => 370 + 21.6 * leanKg;

double maintenance(double bmr, Activity activity) => bmr * activity.factor;

class CalorieTarget {
  const CalorieTarget(this.kcal, {required this.floored});
  final double kcal;

  /// True when the pace asked for would go below the safe minimum,
  /// so the target was raised to it.
  final bool floored;
}

CalorieTarget calorieTarget({
  required double maintenanceKcal,
  required double bmr,
  required GoalMode mode,
  required double paceKgPerWeek,
}) {
  final daily = kcalPerKg * paceKgPerWeek / 7;
  final raw = switch (mode) {
    GoalMode.lose => maintenanceKcal - daily,
    GoalMode.maintain => maintenanceKcal,
    GoalMode.gain => maintenanceKcal + daily,
  };
  final floor = math.max(bmr, 1200.0);
  if (mode == GoalMode.lose && raw < floor) {
    return CalorieTarget(floor, floored: true);
  }
  return CalorieTarget(raw, floored: false);
}

/// Default protein: 0.9 g per lb of body weight. Users choose 0.8–1.2 g/lb.
const double defaultProteinGPerLb = 0.9;
const double defaultProteinGPerKg = defaultProteinGPerLb / kgPerLb;

/// Daily protein in grams: body weight times the chosen grams per kg.
double proteinTarget({required double weightKg, required double gPerKg}) =>
    weightKg * gPerKg;

/// Date a goal weight is reached at a steady pace, or null if it doesn't apply.
DateTime? goalDate({
  required double fromKg,
  required double toKg,
  required double paceKgPerWeek,
  required GoalMode mode,
  required DateTime today,
}) {
  if (mode == GoalMode.maintain || paceKgPerWeek <= 0) return null;
  final diff = mode == GoalMode.lose ? fromKg - toKg : toKg - fromKg;
  if (diff <= 0) return null;
  final days = (diff / paceKgPerWeek * 7).round();
  return DateTime(today.year, today.month, today.day + days);
}

// ---------------------------------------------------------------- body

double bmi(double weightKg, double heightCm) {
  final h = heightCm / 100;
  return weightKg / (h * h);
}

double leanMassKg(double weightKg, double bodyFatPct) =>
    weightKg * (1 - bodyFatPct / 100);

/// Fat-free mass index, normalized to 1.8 m height.
double ffmiNormalized(double leanKg, double heightCm) {
  final h = heightCm / 100;
  return leanKg / (h * h) + 6.1 * (1.8 - h);
}

/// Body weight at a body fat % while keeping today's lean mass.
double weightAtBodyFat(double leanKg, double bodyFatPct) =>
    leanKg / (1 - bodyFatPct / 100);

double waistToHeight(double waistCm, double heightCm) => waistCm / heightCm;

String bmiCategory(double v) {
  if (v < 18.5) return 'Under 18.5';
  if (v < 25) return '18.5–24.9 range';
  if (v < 30) return '25–29.9 range';
  return '30+ range';
}

String ffmiCategory(double v) {
  if (v < 18) return 'Below average';
  if (v < 20) return 'Average';
  if (v < 22) return 'Above average';
  if (v < 23) return 'Excellent';
  if (v < 25) return 'Very high';
  return 'Exceptional';
}

// ---------------------------------------------------------------- trend

/// One weigh-in: the day and the weight in kg.
typedef DayWeight = (DateTime day, double kg);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _dayNumber(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// Mean of the weigh-ins in the 7 days ending on [endDay], or null when
/// there are fewer than [minCount] of them.
double? weeklyAverage(
  List<DayWeight> entries,
  DateTime endDay, {
  int minCount = 4,
}) {
  final end = _day(endDay);
  final start = DateTime(end.year, end.month, end.day - 6);
  var sum = 0.0;
  var n = 0;
  for (final (day, kg) in entries) {
    final d = _day(day);
    if (!d.isBefore(start) && !d.isAfter(end)) {
      sum += kg;
      n++;
    }
  }
  return n > 0 && n >= minCount ? sum / n : null;
}

/// Weekly averages for [weeks] weeks ending on [endDay], oldest first.
/// Weeks with fewer than [minCount] weigh-ins are left out.
List<DayWeight> weeklySeries(
  List<DayWeight> entries,
  DateTime endDay,
  int weeks, {
  int minCount = 2,
}) {
  final end = _day(endDay);
  final out = <DayWeight>[];
  for (var w = weeks - 1; w >= 0; w--) {
    final weekEnd = DateTime(end.year, end.month, end.day - 7 * w);
    final avg = weeklyAverage(entries, weekEnd, minCount: minCount);
    if (avg != null) out.add((weekEnd, avg));
  }
  return out;
}

/// Where your weight is now, for projecting ahead: a straight line fitted
/// through the weigh-ins in the 14 days up to the newest one, read at that
/// newest day. Unlike a 7-day average it doesn't trail a few days behind
/// while you're losing or gaining, and one salty day moves it only a little.
/// With fewer than 3 weigh-ins (or all on one day) it is the newest one.
/// Null with no weigh-ins.
({DateTime day, double kg})? trendWeight(List<DayWeight> entries) {
  if (entries.isEmpty) return null;
  var last = _day(entries.first.$1);
  for (final (d, _) in entries) {
    if (_day(d).isAfter(last)) last = _day(d);
  }
  final xs = <double>[];
  final ys = <double>[];
  double? newest;
  for (final (d, kg) in entries) {
    // Whole days before the newest weigh-in (UTC dates: clock changes can't
    // make a day 23 or 25 hours long).
    final age = DateTime.utc(last.year, last.month, last.day)
        .difference(DateTime.utc(d.year, d.month, d.day))
        .inDays;
    if (age < 0 || age > 13) continue;
    xs.add(-age.toDouble());
    ys.add(kg);
    if (age == 0) newest = kg;
  }
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var sxx = 0.0;
  var sxy = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  if (xs.length < 3 || sxx == 0) return (day: last, kg: newest!);
  return (day: last, kg: my + sxy / sxx * (0 - mx));
}

/// Days in a row with a weigh-in, counting back from today, or from
/// yesterday when today isn't logged yet.
int streakDays(Iterable<DateTime> days, DateTime today) {
  final logged = {for (final d in days) _dayNumber(d)};
  var cur = _day(today);
  if (!logged.contains(_dayNumber(cur))) {
    cur = DateTime(cur.year, cur.month, cur.day - 1);
  }
  var n = 0;
  while (logged.contains(_dayNumber(cur))) {
    n++;
    cur = DateTime(cur.year, cur.month, cur.day - 1);
  }
  return n;
}

/// Expected weight change per day at the planned intake; negative = losing.
double plannedChangeKgPerDay({
  required double maintenanceKcal,
  required double plannedKcal,
}) =>
    (plannedKcal - maintenanceKcal) / kcalPerKg;

// ---------------------------------------------------------------- sleep

/// Minutes asleep from bedtime and wake time, each given as minutes after
/// midnight. Crossing midnight is handled. Null when the times are equal.
int? sleepMinutes(int bedMinuteOfDay, int wakeMinuteOfDay) {
  final m = (wakeMinuteOfDay - bedMinuteOfDay) % 1440;
  return m == 0 ? null : m;
}

/// 450 -> "7 h 30 m"
String formatSleep(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '$h h';
  return '$h h ${m.toString().padLeft(2, '0')} m';
}

/// Mean of the given sleep durations in minutes, or null if empty.
double? averageMinutes(List<int> minutes) {
  if (minutes.isEmpty) return null;
  return minutes.reduce((a, b) => a + b) / minutes.length;
}

/// How much bedtimes vary, in minutes (circular standard deviation, so
/// 11:30 pm and 12:30 am count as an hour apart). Null for fewer than 3.
double? bedtimeSpreadMinutes(List<int> bedMinutesOfDay) {
  if (bedMinutesOfDay.length < 3) return null;
  var sx = 0.0;
  var sy = 0.0;
  for (final m in bedMinutesOfDay) {
    final a = 2 * math.pi * m / 1440;
    sx += math.cos(a);
    sy += math.sin(a);
  }
  final r = math.sqrt(sx * sx + sy * sy) / bedMinutesOfDay.length;
  if (r >= 1) return 0;
  if (r <= 0) return 720;
  final radians = math.sqrt(-2 * math.log(r));
  return radians * 1440 / (2 * math.pi);
}

enum ProteinBasis { current, target }

// ---------------------------------------------------------------- photos

/// True when progress photos are due: never taken, or the last check-in
/// was at least [intervalWeeks] weeks ago. Off when [intervalWeeks] is 0.
bool photosDue({
  required DateTime? lastCheckin,
  required int intervalWeeks,
  required DateTime today,
}) {
  if (intervalWeeks <= 0) return false;
  if (lastCheckin == null) return true;
  final last = _day(lastCheckin);
  final next = DateTime(last.year, last.month, last.day + 7 * intervalWeeks);
  return !_day(today).isBefore(next);
}

// ---------------------------------------------------------------- strength

/// Estimated one-rep max (Epley). A single counts as its own weight;
/// sets above 10 reps are too unreliable and return null.
double? e1rm(double loadKg, int reps) {
  if (reps < 1 || reps > 10 || loadKg <= 0) return null;
  if (reps == 1) return loadKg;
  return loadKg * (1 + reps / 30);
}

/// Rough workout length: about 40 s per set plus the planned rest.
int estimateMinutes(Iterable<(int sets, int restSec)> items) {
  var seconds = 0;
  for (final (sets, rest) in items) {
    seconds += sets * 40 + (sets > 1 ? sets - 1 : 0) * rest;
  }
  return (seconds / 60).round();
}

// ---------------------------------------------------------------- cardio

const double kmPerMile = 1.609344;

double kmToMi(double km) => km / kmPerMile;
double miToKm(double mi) => mi * kmPerMile;

/// 95 -> "1:35", 3725 -> "1:02:05"
String clockText(int totalSec) {
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = (totalSec % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Reads "30" (minutes), "30:15" (m:ss), "1:02:05" (h:mm:ss) or "22.5"
/// (minutes) as seconds. Null if it can't be read.
int? parseClock(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (!t.contains(':')) {
    final minutes = double.tryParse(t.replaceAll(',', '.'));
    return minutes == null || minutes < 0 ? null : (minutes * 60).round();
  }
  final parts = t.split(':').map((p) => int.tryParse(p.trim())).toList();
  if (parts.any((p) => p == null || p < 0)) return null;
  if (parts.length == 2) return parts[0]! * 60 + parts[1]!;
  if (parts.length == 3) return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
  return null;
}

/// Seconds per unit of distance, or null when either is missing.
double? paceSecPer(double? distance, int? durationSec) {
  if (distance == null || durationSec == null || distance <= 0) return null;
  return durationSec / distance;
}

// ---------------------------------------------------------------- food

/// Calories and macros. Values are totals for whatever they describe.
class Macros {
  const Macros({this.kcal = 0, this.protein = 0, this.carbs = 0, this.fat = 0});

  static const zero = Macros();

  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  Macros operator +(Macros o) => Macros(
        kcal: kcal + o.kcal,
        protein: protein + o.protein,
        carbs: carbs + o.carbs,
        fat: fat + o.fat,
      );

  Macros scale(double f) =>
      Macros(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f);
}

/// Macros for [grams] of a food given per-100 g values.
Macros macrosForGrams(Macros per100, double grams) => per100.scale(grams / 100);

// ---------------------------------------------------------------- adaptive maintenance

/// Maintenance learned from what you ate and how your weight moved.
class LearnedMaintenance {
  const LearnedMaintenance({required this.kcal, required this.foodDays, required this.weighIns});
  final double kcal;
  final int foodDays;
  final int weighIns;
}

/// How much data adaptive maintenance needs before it trusts itself.
const int adaptiveMinFoodDays = 14;
const int adaptiveMinWeighIns = 8;
const int adaptiveMinSpanDays = 21;
const int adaptiveWindowDays = 28;

/// Over the last [adaptiveWindowDays] days (today excluded, since it's not
/// over yet): average intake on days with food logged, minus the energy in
/// the weight trend (least-squares slope x 7,700 kcal/kg). Null until there
/// are enough food days and weigh-ins spanning at least
/// [adaptiveMinSpanDays] days, or if the result is implausible.
LearnedMaintenance? adaptiveMaintenance({
  required List<(DateTime, double)> intakeDays,
  required List<(DateTime, double)> weights,
  required DateTime today,
}) {
  final end = _day(today);
  final start = DateTime(end.year, end.month, end.day - adaptiveWindowDays);
  bool inWindow(DateTime d) => !_day(d).isBefore(start) && _day(d).isBefore(end);

  final food = [
    for (final (d, k) in intakeDays)
      if (inWindow(d) && k > 0) k,
  ];
  final w = [
    for (final (d, kg) in weights)
      if (inWindow(d)) (_day(d), kg),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (food.length < adaptiveMinFoodDays || w.length < adaptiveMinWeighIns) return null;
  final first = w.first.$1, last = w.last.$1;
  // Count calendar days (not 24-hour periods) so a clock change can't shave one off.
  final span = DateTime.utc(last.year, last.month, last.day)
      .difference(DateTime.utc(first.year, first.month, first.day))
      .inDays;
  if (span < adaptiveMinSpanDays) return null;

  final avgIntake = food.reduce((a, b) => a + b) / food.length;
  final xs = [for (final p in w) p.$1.difference(w.first.$1).inHours / 24];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = w.map((p) => p.$2).reduce((a, b) => a + b) / w.length;
  var sxy = 0.0;
  var sxx = 0.0;
  for (var i = 0; i < w.length; i++) {
    sxy += (xs[i] - mx) * (w[i].$2 - my);
    sxx += (xs[i] - mx) * (xs[i] - mx);
  }
  if (sxx == 0) return null;
  final slopeKgPerDay = sxy / sxx;
  final kcal = avgIntake - slopeKgPerDay * kcalPerKg;
  if (kcal < 1000 || kcal > 6000) return null;
  return LearnedMaintenance(kcal: kcal, foodDays: food.length, weighIns: w.length);
}

/// Warm-up sets before a working weight: 40%, 60% and 80% of it for 8, 5 and
/// 3 reps, rounded to loadable steps (5 lb or 2.5 kg). Empty when the weight
/// is too light to need a ramp.
List<(double kg, int reps)> warmupSets(double workingKg, {required bool imperial}) {
  final working = imperial ? kgToLb(workingKg) : workingKg;
  final step = imperial ? 5.0 : 2.5;
  // Under 30 lb (15 kg) there's nothing to warm up for: just start.
  // (A hair of tolerance: a weight converted lb -> kg -> lb can come back as
  // 29.999999.)
  if (working < step * 6 - 1e-6) return const [];
  final out = <(double, int)>[];
  var last = 0.0;
  for (final (pct, reps) in const [(0.4, 8), (0.6, 5), (0.8, 3)]) {
    final w = (working * pct / step).round() * step;
    if (w < step * 2 || w <= last || w >= working) continue;
    out.add((imperial ? lbToKg(w) : w, reps));
    last = w;
  }
  return out;
}
