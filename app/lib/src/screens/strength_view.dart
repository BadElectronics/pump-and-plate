import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

class _Point {
  const _Point(this.date, this.e1rm, this.topLoad, this.topReps, this.volume, this.sets);
  final DateTime date;
  final double? e1rm;
  final double? topLoad;
  final int? topReps;
  final double volume;
  final List<SetEntry> sets;
}

/// Strength part of the Progress tab.
class StrengthView extends StatefulWidget {
  const StrengthView({super.key});

  @override
  State<StrengthView> createState() => _StrengthViewState();
}

class _StrengthViewState extends State<StrengthView> {
  String? _exercise;
  int _metric = 0; // 0 e1RM, 1 top set, 2 volume

  List<_Point> _history(AppState s, String id) {
    final out = <_Point>[];
    for (final x in s.finishedSessions) {
      final sets = [
        for (final set in x.sets)
          if (set.exerciseId == id && set.done && !set.warmup) set,
      ];
      if (sets.isEmpty) continue;
      double? best;
      double? topLoad;
      int? topReps;
      var volume = 0.0;
      for (final set in sets) {
        final v = s.setE1rm(set, x.date);
        if (v != null && (best == null || v > best)) best = v;
        final load = s.loadOf(set, x.date);
        if (load != null) {
          if (topLoad == null ||
              load > topLoad ||
              (load == topLoad && (set.reps ?? 0) > (topReps ?? 0))) {
            topLoad = load;
            topReps = set.reps;
          }
          volume += load * (set.reps ?? 0) * set.type.volumeShare;
        }
      }
      out.add(_Point(x.date, best, topLoad, topReps, volume, sets));
    }
    return out;
  }

  Widget _chips(AppState s, AppColors c, List<String> ids, String id) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final e in ids)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  _exercise = e;
                  _metric = 0;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e == id ? c.text : c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    s.exerciseName(e),
                    style: TextStyle(fontSize: 14, color: e == id ? c.background : c.text),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Cardio: distance, time and pace per session, plus bests.
  Widget _cardio(AppState s, AppColors c, String id, bool imperial) {
    final dUnit = imperial ? 'mi' : 'km';
    double dist(double km) => imperial ? kmToMi(km) : km;
    final points = <(DateTime, double?, int?, String)>[];
    for (final x in s.finishedSessions) {
      double? km;
      int? sec;
      for (final set in x.sets) {
        if (set.exerciseId != id || !set.done) continue;
        if (set.distanceKm != null) km = (km ?? 0) + set.distanceKm!;
        if (set.durationSec != null) sec = (sec ?? 0) + set.durationSec!;
      }
      if (km == null && sec == null) continue;
      points.add((x.date, km, sec, x.id));
    }
    double? value((DateTime, double?, int?, String) p) => switch (_metric) {
          0 => p.$2 == null ? null : dist(p.$2!),
          1 => p.$3 == null ? null : p.$3! / 60,
          _ => paceSecPer(p.$2 == null ? null : dist(p.$2!), p.$3),
        };
    final series = [
      for (final p in points)
        if (value(p) != null) (p.$1, value(p)!),
    ];
    String fmt(double v) => switch (_metric) {
          0 => '${v.toStringAsFixed(2)} $dUnit',
          1 => clockText((v * 60).round()),
          _ => '${clockText(v.round())} /$dUnit',
        };

    (DateTime, double)? longest;
    (DateTime, int)? longestTime;
    (DateTime, double)? fastest;
    for (final p in points) {
      final d = p.$2;
      final t = p.$3;
      if (d != null && (longest == null || d > longest.$2)) longest = (p.$1, d);
      if (t != null && (longestTime == null || t > longestTime.$2)) longestTime = (p.$1, t);
      final pace = paceSecPer(d == null ? null : dist(d), t);
      if (pace != null && (fastest == null || pace < fastest.$2)) fastest = (p.$1, pace);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Segmented<int>(
                label: 'Measure',
                options: const [(0, 'Distance'), (1, 'Time'), (2, 'Pace')],
                value: _metric,
                onChanged: (v) => setState(() => _metric = v),
              ),
              const SizedBox(height: 14),
              Text(
                series.isEmpty ? '—' : fmt(series.last.$2),
                style: AppText.title(c).copyWith(fontSize: 32, fontWeight: FontWeight.w300),
              ),
              Text(
                switch (_metric) {
                  0 => 'Distance, latest session',
                  1 => 'Time, latest session',
                  _ => 'Average pace, latest session (lower is faster)',
                },
                style: AppText.quiet(c),
              ),
              const SizedBox(height: 12),
              if (series.length >= 2)
                SizedBox(height: 150, child: CustomPaint(painter: _LinePainter(series, c)))
              else
                Text('The chart appears after two sessions with this exercise.', style: AppText.quiet(c)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Personal records',
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            children: [
              for (final (label, val, date) in <(String, String, DateTime)>[
                if (longest != null)
                  ('Longest distance', '${dist(longest.$2).toStringAsFixed(2)} $dUnit', longest.$1),
                if (longestTime != null)
                  ('Longest time', clockText(longestTime.$2), longestTime.$1),
                if (fastest != null)
                  ('Fastest pace', '${clockText(fastest.$2.round())} /$dUnit', fastest.$1),
              ])
                Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(label, style: AppText.quiet(c).copyWith(fontSize: 12)),
                            Text(val, style: AppText.body(c).copyWith(fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Text(shortDate(date), style: AppText.quiet(c).copyWith(fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    double disp(double kg) => imperial ? kgToLb(kg) : kg;
    final ids = s.trainedExerciseIds;

    if (ids.isEmpty) {
      return SectionCard(
        title: 'Strength',
        child: Text(
          'Finish a workout and your lifts and cardio show up here: estimated '
          '1-rep max, top sets and volume for lifts; distance, time and pace '
          'for cardio; and personal records for each.',
          style: AppText.body(c),
        ),
      );
    }

    final id = (_exercise != null && ids.contains(_exercise)) ? _exercise! : ids.first;
    if (s.isCardio(id)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _chips(s, c, ids, id),
          const SizedBox(height: 14),
          _cardio(s, c, id, imperial),
        ],
      );
    }
    final history = _history(s, id);
    double? valueOf(_Point p) => switch (_metric) {
          0 => p.e1rm == null ? null : disp(p.e1rm!),
          1 => p.topLoad == null ? null : disp(p.topLoad!),
          _ => p.volume <= 0 ? null : disp(p.volume),
        };
    final series = [
      for (final p in history)
        if (valueOf(p) != null) (p.date, valueOf(p)!),
    ];

    String fmt(double v) => _metric == 2 ? thousands(v) : oneDecimal(v);
    String statText() {
      if (series.isEmpty) return '—';
      final last = history.lastWhere((p) => valueOf(p) != null);
      if (_metric == 1) return '${fmt(disp(last.topLoad!))} × ${last.topReps ?? '–'}';
      return '${fmt(series.last.$2)} $unit';
    }

    String? delta() {
      if (series.length < 2) return null;
      final d = series.last.$2 - series.first.$2;
      return '${d >= 0 ? '+' : '−'}${fmt(d.abs())} $unit since ${shortDate(series.first.$1)}';
    }

    // Records.
    _Point? bestE1rm;
    _Point? heaviest;
    _Point? bestVolume;
    var mostReps = 0;
    DateTime? mostRepsDate;
    for (final p in history) {
      if (p.e1rm != null && (bestE1rm == null || p.e1rm! > bestE1rm.e1rm!)) bestE1rm = p;
      if (p.topLoad != null && (heaviest == null || p.topLoad! > heaviest.topLoad!)) heaviest = p;
      if (p.volume > 0 && (bestVolume == null || p.volume > bestVolume.volume)) bestVolume = p;
      for (final set in p.sets) {
        if ((set.reps ?? 0) > mostReps) {
          mostReps = set.reps!;
          mostRepsDate = p.date;
        }
      }
    }
    final records = <(String, String, DateTime)>[
      if (bestE1rm != null)
        ('Best estimated 1RM', '${oneDecimal(disp(bestE1rm.e1rm!))} $unit', bestE1rm.date),
      if (heaviest != null)
        ('Heaviest set', '${oneDecimal(disp(heaviest.topLoad!))} $unit × ${heaviest.topReps ?? '–'}', heaviest.date),
      if (bestVolume != null)
        ('Best session volume', '${thousands(disp(bestVolume.volume))} $unit', bestVolume.date),
      if (mostRepsDate != null) ('Most reps in a set', '$mostReps reps', mostRepsDate),
    ];
    final bodyweight = s.exercise(id)?.bodyweight ?? false;
    String setText(SetEntry e) {
      final w = e.weightKg;
      final ws = bodyweight
          ? (w == null || w == 0 ? 'BW' : '+${oneDecimal(disp(w))}')
          : (w == null ? '–' : oneDecimal(disp(w)));
      return '$ws×${e.reps ?? '–'}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chips(s, c, ids, id),
        const SizedBox(height: 14),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Segmented<int>(
                label: 'Measure',
                options: const [(0, 'Est. 1RM'), (1, 'Top set'), (2, 'Volume')],
                value: _metric,
                onChanged: (v) => setState(() => _metric = v),
              ),
              const SizedBox(height: 14),
              Text(
                switch (_metric) {
                  0 => 'Estimated 1-rep max',
                  1 => 'Heaviest working set',
                  _ => 'Session volume, working sets',
                },
                style: AppText.quiet(c),
              ),
              Text(statText(), style: AppText.title(c).copyWith(fontSize: 32, fontWeight: FontWeight.w300)),
              if (delta() != null)
                Text(
                  delta()!,
                  style: AppText.body(c).copyWith(color: c.accent, fontWeight: FontWeight.w500),
                ),
              const SizedBox(height: 12),
              if (series.length >= 2)
                SizedBox(
                  height: 150,
                  child: CustomPaint(painter: _LinePainter(series, c)),
                )
              else
                Text(
                  'The chart appears after two sessions with this exercise.',
                  style: AppText.quiet(c),
                ),
              const SizedBox(height: 8),
              Text(
                switch (_metric) {
                  0 => 'Best set each session (Epley), from sets of 1–10 reps. Warm-ups left out.',
                  1 => 'Heaviest load lifted for a working set each session.',
                  _ => 'Load × reps added up across working sets.',
                },
                style: AppText.quiet(c).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Personal records',
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            children: [
              for (final (label, value, date) in records)
                Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(label, style: AppText.quiet(c).copyWith(fontSize: 12)),
                            Text(value, style: AppText.body(c).copyWith(fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Text(shortDate(date), style: AppText.quiet(c).copyWith(fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Recent sessions',
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            children: [
              for (final p in history.reversed.take(6))
                Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                  child: Row(
                    children: [
                      SizedBox(width: 56, child: Text(shortDate(p.date), style: AppText.quiet(c))),
                      Expanded(
                        child: Text(
                          p.sets.map(setText).join('  '),
                          style: const TextStyle(fontFamily: 'GeistMono', fontSize: 13),
                        ),
                      ),
                      if (p.e1rm != null)
                        Text(
                          oneDecimal(disp(p.e1rm!)),
                          style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points, this.c);

  final List<(DateTime, double)> points;
  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final p in points) p.$2];
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    final pad = math.max((hi - lo) * 0.15, 1.0);
    lo -= pad;
    hi += pad;
    const right = 40.0;
    final w = size.width - right;
    final h = size.height - 6;
    final t0 = points.first.$1;
    final span = math.max(1, points.last.$1.difference(t0).inHours).toDouble();
    Offset at(int i) => Offset(
          points[i].$1.difference(t0).inHours / span * w,
          3 + (1 - (points[i].$2 - lo) / (hi - lo)) * h,
        );

    final grid = Paint()
      ..color = c.line
      ..strokeWidth = 1;
    for (var k = 0; k < 3; k++) {
      final v = lo + pad / 2 + (hi - lo - pad) * k / 2;
      final y = 3 + (1 - (v - lo) / (hi - lo)) * h;
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: v.round().toString(),
          style: TextStyle(fontFamily: 'Geist', fontSize: 10, color: c.muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w + 8, y - tp.height / 2));
    }

    final area = Path()..moveTo(at(0).dx, h + 3);
    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final o = at(i);
      area.lineTo(o.dx, o.dy);
      if (i == 0) {
        line.moveTo(o.dx, o.dy);
      } else {
        line.lineTo(o.dx, o.dy);
      }
    }
    area
      ..lineTo(at(points.length - 1).dx, h + 3)
      ..close();
    canvas.drawPath(area, Paint()..color = c.accent.withAlpha(36));
    canvas.drawPath(
      line,
      Paint()
        ..color = c.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final last = at(points.length - 1);
    canvas.drawCircle(last, 5, Paint()..color = c.accent);
    canvas.drawCircle(
      last,
      5,
      Paint()
        ..color = c.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.points != points || old.c != c;
}
