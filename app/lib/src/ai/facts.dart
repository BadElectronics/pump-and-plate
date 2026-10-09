/// Plain-sentence facts from the user's own data, handed to the AI so its
/// answers use real numbers (the app does all the maths), plus the checks
/// behind "How am I doing?".
library;

import 'dart:math' as math;

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'matcher.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}';
String _f1(double v) => v.toStringAsFixed(1);

DateTime _today() => dateOnly(DateTime.now());
DateTime _ago(int days) {
  final t = _today();
  return DateTime(t.year, t.month, t.day - days);
}

bool _imperial(AppState s) => s.settings.units == Units.imperial;
String _wt(AppState s, double kg) => _imperial(s) ? '${_f1(kgToLb(kg))} lb' : '${_f1(kg)} kg';
String _signedWt(AppState s, double kg) => '${kg >= 0 ? '+' : '-'}${_wt(s, kg.abs())}';

// ------------------------------------------------------------------ weight

String weightFacts(AppState s) {
  final latest = s.latestWeighIn;
  if (latest == null) return 'Weight: no weigh-ins logged yet.';
  final out = <String>['Latest weigh-in: ${_wt(s, latest.weightKg)} on ${_date(latest.date)}.'];
  final avg = weeklyAverage(s.dayWeights, _today(), minCount: 2);
  final prev = weeklyAverage(s.dayWeights, _ago(7), minCount: 2);
  final month = weeklyAverage(s.dayWeights, _ago(28), minCount: 2);
  if (avg != null) out.add('7-day average weight: ${_wt(s, avg)}.');
  if (avg != null && prev != null) out.add('Change from the week before: ${_signedWt(s, avg - prev)}.');
  if (avg != null && month != null) {
    out.add('Change over 4 weeks: ${_signedWt(s, avg - month)} (about ${_signedWt(s, (avg - month) / 4)} per week).');
  }
  final recent = s.weighIns.where((w) => !w.date.isBefore(_ago(6))).length;
  out.add('Weigh-ins in the last 7 days: $recent.');
  final g = s.goal;
  final mode = switch (g.mode) { GoalMode.lose => 'lose weight', GoalMode.gain => 'gain weight', GoalMode.maintain => 'maintain weight' };
  out.add('Goal: $mode'
      '${g.targetWeightKg == null ? '' : ', target ${_wt(s, g.targetWeightKg!)}'}'
      '${g.mode == GoalMode.maintain ? '' : ', planned pace ${_wt(s, g.paceKgPerWeek.abs())} per week'}.');
  return out.join(' ');
}

// ------------------------------------------------------------------ sleep

String sleepFacts(AppState s) {
  final goal = s.settings.sleepGoalHours;
  final nights = [for (var i = 0; i < 7; i++) s.sleepOn(_ago(i))];
  final mins = [for (final n in nights) if (n?.durationMin != null) n!.durationMin!];
  if (mins.isEmpty) return 'Sleep: none logged in the last 7 nights. Goal ${_f1(goal)} h.';
  final avg = mins.reduce((a, b) => a + b) / mins.length / 60;
  final under = mins.where((m) => m / 60 < goal - 0.25).length;
  final q = [for (final n in nights) if (n?.quality != null) n!.quality!];
  final lastNight = nights.first?.durationMin;
  return [
    'Sleep over the last 7 nights: ${mins.length} logged, average ${_f1(avg)} h, goal ${_f1(goal)} h, $under under goal.',
    if (lastNight != null) 'Last night: ${_f1(lastNight / 60)} h.',
    if (q.isNotEmpty) 'Average sleep quality: ${_f1(q.reduce((a, b) => a + b) / q.length)} out of 5.',
  ].join(' ');
}

// ------------------------------------------------------------------ food

/// Average calories and protein over the last [days] complete days with food logged.
(double kcal, double protein, int days)? _foodAverage(AppState s, int days) {
  var k = 0.0, p = 0.0, n = 0;
  for (var i = 1; i <= days; i++) {
    final m = s.eatenOn(_ago(i));
    if (m.kcal <= 0) continue;
    k += m.kcal;
    p += m.protein;
    n++;
  }
  return n == 0 ? null : (k / n, p / n, n);
}

String nutritionFacts(AppState s) {
  final t = s.targets;
  final today = s.eatenOn(_today());
  final out = <String>[
    'Eaten today so far: ${today.kcal.round()} kcal, ${today.protein.round()} g protein, '
        '${today.carbs.round()} g carbs, ${today.fat.round()} g fat.',
    if (t != null) 'Daily targets: ${t.kcal.round()} kcal and ${t.proteinG.round()} g protein.',
    if (t != null) 'Left today: ${(t.kcal - today.kcal).round()} kcal, ${(t.proteinG - today.protein).round()} g protein.',
  ];
  final avg = _foodAverage(s, 7);
  if (avg != null) {
    out.add('Average over the last ${avg.$3} logged days (before today): ${avg.$1.round()} kcal, ${avg.$2.round()} g protein.');
  } else {
    out.add('No food logged in the 7 days before today.');
  }
  return out.join(' ');
}

// ------------------------------------------------------------------ water

String waterFacts(AppState s) {
  final imperial = _imperial(s);
  final today = s.waterOn(_today());
  final days = [for (var i = 1; i <= 7; i++) s.waterOn(_ago(i))].where((m) => m > 0).toList();
  return [
    'Water today: ${formatWater(today, imperial: imperial)} of a ${formatWater(s.waterGoalMl, imperial: imperial)} goal.',
    if (days.isNotEmpty)
      'Average over the last ${days.length} logged days (before today): ${formatWater(days.reduce((a, b) => a + b) / days.length, imperial: imperial)}.',
  ].join(' ');
}

// ------------------------------------------------------------------ training

String trainingFacts(AppState s) {
  final done = s.finishedSessions;
  final week = done.where((x) => !x.date.isBefore(_ago(6))).length;
  final month = done.where((x) => !x.date.isBefore(_ago(27))).length;
  var planned = 0, missed = 0;
  for (var i = 1; i <= 7; i++) {
    for (final p in s.plannedOn(_ago(i))) {
      planned++;
      if (!s.plannedDone(p)) missed++;
    }
  }
  final last = done.isEmpty ? null : (done.toList()..sort((a, b) => a.date.compareTo(b.date))).last;
  return [
    'Workouts finished: $week in the last 7 days, $month in the last 4 weeks.',
    if (planned > 0) 'Planned workouts in the last 7 days: $planned, missed $missed.',
    if (last != null) 'Last workout: ${last.name} on ${_date(last.date)}.',
  ].join(' ');
}

/// Best estimated 1RM per finished session for [id], oldest first.
List<(DateTime, double)> _e1rmHistory(AppState s, String id) {
  final out = <(DateTime, double)>[];
  final sessions = s.finishedSessions.toList()..sort((a, b) => a.date.compareTo(b.date));
  for (final x in sessions) {
    double? best;
    for (final set in x.sets) {
      if (set.exerciseId != id || !set.done || set.warmup) continue;
      final v = s.setE1rm(set, x.date);
      if (v != null && (best == null || v > best)) best = v;
    }
    if (best != null) out.add((x.date, best));
  }
  return out;
}

double? _bestBetween(List<(DateTime, double)> h, DateTime from, DateTime to) {
  double? best;
  for (final (d, v) in h) {
    if (d.isBefore(from) || d.isAfter(to)) continue;
    if (best == null || v > best) best = v;
  }
  return best;
}

String _liftLine(AppState s, String id) {
  final h = _e1rmHistory(s, id);
  if (h.isEmpty) return '${s.exerciseName(id)}: no logged sets yet.';
  final now = _bestBetween(h, _ago(27), _today());
  final before = _bestBetween(h, _ago(55), _ago(28));
  final parts = <String>['${s.exerciseName(id)}: ${h.length} sessions logged'];
  if (now != null) parts.add('best estimated 1RM in the last 4 weeks ${_wt(s, now)}');
  if (before != null) parts.add('4 to 8 weeks ago ${_wt(s, before)}');
  if (now != null && before != null) parts.add('change ${_signedWt(s, now - before)}');
  parts.add('last trained ${_date(h.last.$1)}');
  return '${parts.join(', ')}.';
}

/// Exercises with logged sets, most-trained first.
List<String> _trainedLifts(AppState s) {
  final count = <String, int>{};
  for (final x in s.finishedSessions) {
    final seen = <String>{};
    for (final set in x.sets) {
      if (set.done && !set.warmup && !s.isCardio(set.exerciseId) && s.setE1rm(set, x.date) != null) seen.add(set.exerciseId);
    }
    for (final id in seen) {
      count[id] = (count[id] ?? 0) + 1;
    }
  }
  return count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
}

/// The trained lift best covered by [have] (ties: the more specific name).
(String?, double) _bestLift(AppState s, Set<String> have) {
  String? best;
  var bestScore = 0.0;
  var bestLength = 0;
  for (final id in _trainedLifts(s)) {
    final name = [for (final w in normalizeName(s.exerciseName(id)).split(' ')) if (w.isNotEmpty) w];
    if (name.isEmpty) continue;
    final score = name.where(have.contains).length / name.length;
    if (score > bestScore || (score == bestScore && score > 0 && name.length > bestLength)) {
      bestScore = score;
      bestLength = name.length;
      best = id;
    }
  }
  return (best, bestScore);
}

/// The lift a question is about ("how's my bench going"), if any. The words
/// as typed come first ("front squat"); only if no lift is fully named do
/// short forms expand ("bench" -> bench press, "squat" -> back squat).
String? liftIn(AppState s, String question) {
  final words = {for (final w in normalizeName(question).split(' ')) if (w.isNotEmpty) w};
  final (typed, typedScore) = _bestLift(s, words);
  if (typedScore >= 1) return typed;
  final expanded = <String>{...words};
  for (final w in words) {
    final q = exerciseQuery(w);
    if (q != w) expanded.addAll(normalizeName(q).split(' '));
  }
  final (best, score) = _bestLift(s, expanded);
  return score >= 0.5 ? best : null;
}

String liftFacts(AppState s, String question) {
  final id = liftIn(s, question);
  if (id != null) return _liftLine(s, id);
  final lifts = _trainedLifts(s).take(3).toList();
  if (lifts.isEmpty) return 'Lifts: no strength sets logged yet.';
  return lifts.map((id) => _liftLine(s, id)).join(' ');
}

// ------------------------------------------------------------------ routing

bool _has(String q, String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(q);

/// The facts a question needs, as one block; empty if it isn't about the
/// user's own data.
String factsFor(AppState s, String question) {
  final q = question.toLowerCase();
  final overall = _has(q, r'how am i doing|overall|progress|summary|this week|my week|check.?in|report');
  final parts = <String>[
    if (overall || _has(q, r'\bweigh|\bweight|\bscale\b|\blos(e|ing)\b|\bgain|\bcut\b|\bbulk|\bfat\b|\bgoal\b'))
      weightFacts(s),
    if (overall || _has(q, r'\bsleep|\bslept\b|\bbed\b|\btired|\bnap'))
      sleepFacts(s),
    if (overall || _has(q, r'protein|calori|kcal|\beat|\bate\b|\bfood|\bdiet|\bcarb|macro|\bmeal|\bhungry'))
      nutritionFacts(s),
    if (overall || _has(q, r'\bwater|hydrat|\bdrink|\bthirst'))
      waterFacts(s),
    if (overall || _has(q, r'workout|\btrain|\bgym\b|session|exercis|\bmissed|\bplan\b'))
      trainingFacts(s),
    if (overall || liftIn(s, question) != null || _has(q, r'1rm|\bstrength|\blift|\bstronger|\bpr\b|\bmax\b'))
      liftFacts(s, question),
  ];
  return parts.join('\n');
}

// ------------------------------------------------------------------ coaching

/// Things worth acting on, in plain sentences (most useful first). Each needs
/// enough data to be fair: no conclusions from a day or two.
List<String> coachingFindings(AppState s) {
  final out = <String>[];
  final goal = s.settings.sleepGoalHours;

  // Sleep, over the last 7 nights (at least 4 logged).
  final mins = [
    for (var i = 0; i < 7; i++)
      if (s.sleepOn(_ago(i))?.durationMin case final int m) m,
  ];
  if (mins.length >= 4) {
    final avg = mins.reduce((a, b) => a + b) / mins.length / 60;
    if (avg < goal - 0.5) {
      out.add('Sleep averaged ${_f1(avg)} h over the last week, under the ${_f1(goal)} h goal.');
    }
  }

  // Food, over the last 7 complete days (at least 3 logged).
  final t = s.targets;
  final food = _foodAverage(s, 7);
  if (t != null && food != null && food.$3 >= 3) {
    if (food.$2 < t.proteinG * 0.85) {
      out.add('Protein averaged ${food.$2.round()} g a day, below the ${t.proteinG.round()} g target.');
    }
    final over = food.$1 - t.kcal;
    if (s.goal.mode == GoalMode.lose && over > 200) {
      out.add('Calories averaged ${food.$1.round()} a day, about ${over.round()} above the ${t.kcal.round()} target for losing weight.');
    } else if (s.goal.mode == GoalMode.gain && over < -200) {
      out.add('Calories averaged ${food.$1.round()} a day, about ${(-over).round()} below the ${t.kcal.round()} target for gaining.');
    }
  }

  // Weight trend against the goal, over 2 weeks.
  final avg = weeklyAverage(s.dayWeights, _today(), minCount: 2);
  final twoAgo = weeklyAverage(s.dayWeights, _ago(14), minCount: 2);
  if (avg != null && twoAgo != null) {
    final perWeek = (avg - twoAgo) / 2;
    final pace = s.goal.paceKgPerWeek.abs();
    if (s.goal.mode == GoalMode.lose && perWeek >= 0) {
      out.add('Weight hasn\'t come down over the last 2 weeks (${_signedWt(s, avg - twoAgo)}).');
    } else if (s.goal.mode == GoalMode.lose && pace > 0 && -perWeek > pace * 1.5) {
      out.add('Weight is dropping about ${_wt(s, -perWeek)} a week, faster than the planned ${_wt(s, pace)}.');
    } else if (s.goal.mode == GoalMode.gain && perWeek <= 0) {
      out.add('Weight hasn\'t gone up over the last 2 weeks (${_signedWt(s, avg - twoAgo)}).');
    }
  } else if (s.weighIns.where((w) => !w.date.isBefore(_ago(6))).isEmpty && s.weighIns.isNotEmpty) {
    out.add('No weigh-ins in the last 7 days, so the trend is going stale.');
  }

  // Planned workouts missed in the last 7 days.
  var missed = 0;
  for (var i = 1; i <= 7; i++) {
    for (final p in s.plannedOn(_ago(i))) {
      if (!s.plannedDone(p)) missed++;
    }
  }
  if (missed > 0) out.add('$missed planned ${missed == 1 ? 'workout was' : 'workouts were'} missed in the last 7 days.');

  // A lift that's stalled: trained 4+ times in 6 weeks, no better lately.
  for (final id in _trainedLifts(s).take(4)) {
    final h = _e1rmHistory(s, id).where((p) => !p.$1.isBefore(_ago(41))).toList();
    if (h.length < 4) continue;
    final recent = _bestBetween(h, _ago(20), _today());
    final earlier = _bestBetween(h, _ago(41), _ago(21));
    if (recent != null && earlier != null && recent <= earlier) {
      out.add('${s.exerciseName(id)} hasn\'t improved in about 3 weeks (best ${_wt(s, recent)}).');
      break;
    }
  }

  return out.take(math.min(out.length, 6)).toList();
}
