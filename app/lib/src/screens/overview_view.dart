import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'camera_screen.dart';
import 'muscle_heatmap.dart';

/// Progress > Overview: weight, strength, sleep and photos at a glance.
class OverviewView extends StatefulWidget {
  const OverviewView({super.key, required this.onPhotos, this.onTraining});

  /// Opens the Photos section ("All" on the photos card).
  final VoidCallback onPhotos;

  /// Opens the Training section (the muscles card).
  final VoidCallback? onTraining;

  @override
  State<OverviewView> createState() => _OverviewViewState();
}

class _OverviewViewState extends State<OverviewView> {
  String? _lift;

  /// Exercises with an estimated 1RM, most-trained first.
  List<String> _lifts(AppState s) {
    final count = <String, int>{};
    for (final x in s.finishedSessions) {
      final seen = <String>{};
      for (final set in x.sets) {
        if (!set.done || set.warmup || s.isCardio(set.exerciseId)) continue;
        if (s.setE1rm(set, x.date) == null) continue;
        seen.add(set.exerciseId);
      }
      for (final id in seen) {
        count[id] = (count[id] ?? 0) + 1;
      }
    }
    return count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
  }

  /// Best estimated 1RM per session for [id], oldest first.
  List<(DateTime, double)> _history(AppState s, String id) {
    final out = <(DateTime, double)>[];
    final sessions = [...s.finishedSessions]..sort((a, b) => a.date.compareTo(b.date));
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

  Widget _card(AppColors c, String title, Widget? aside, List<Widget> body) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 30,
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: AppText.quiet(c).copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                if (aside != null) aside,
              ],
            ),
          ),
          ...body,
        ],
      ),
    );
  }

  Widget _big(AppColors c, String value, String unit, String? change) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(value, style: AppText.title(c).copyWith(fontSize: 24, fontWeight: FontWeight.w300)),
        const SizedBox(width: 6),
        Flexible(child: Text(unit, style: AppText.quiet(c).copyWith(fontSize: 13))),
        const Spacer(),
        if (change != null)
          Text(change, style: AppText.body(c).copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent)),
      ],
    );
  }

  Widget _empty(AppColors c, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(text, style: AppText.quiet(c)),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    double disp(double kg) => imperial ? kgToLb(kg) : kg;
    final today = dateOnly(DateTime.now());

    // ---- weight: last 12 weeks of weigh-ins
    final from = DateTime(today.year, today.month, today.day - 84);
    final weights = [
      for (final w in s.weighIns)
        if (!w.date.isBefore(from)) w,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final avg = s.weeklyAverageKg;
    final lastWeek = weeklyAverage(s.dayWeights, DateTime(today.year, today.month, today.day - 7));
    final headline = avg ?? s.currentWeightKg;
    String? weekChange;
    if (avg != null && lastWeek != null) {
      final d = disp(avg) - disp(lastWeek);
      weekChange = '${d < 0 ? '−' : '+'}${oneDecimal(d.abs())} this week';
    }

    // ---- strength
    final lifts = _lifts(s);
    final lift = lifts.contains(_lift) ? _lift! : (lifts.isEmpty ? null : lifts.first);
    final history = lift == null ? const <(DateTime, double)>[] : _history(s, lift);
    final shown = history.length > 12 ? history.sublist(history.length - 12) : history;
    String? gain;
    if (shown.length >= 2) {
      final d = disp(shown.last.$2) - disp(shown.first.$2);
      final weeks = math.max(1, daysBetween(shown.first.$1, shown.last.$1) ~/ 7);
      gain = '${d < 0 ? '−' : '+'}${d.abs().round()} in $weeks ${weeks == 1 ? 'week' : 'weeks'}';
    }

    // ---- sleep: the last 7 nights (today's entry is last night)
    final nights = <double?>[
      for (var i = 6; i >= 0; i--)
        () {
          final e = s.sleepOn(DateTime(today.year, today.month, today.day - i));
          final m = e?.durationMin;
          return m == null ? null : m / 60;
        }(),
    ];
    final logged = nights.whereType<double>().toList();
    final sleepAvg = logged.isEmpty ? null : logged.reduce((a, b) => a + b) / logged.length;
    final goal = s.settings.sleepGoalHours;

    // ---- photos: first vs latest front photo
    final dates = s.checkinDates;
    final first = dates.isEmpty ? null : s.photoFor(dates.first, PhotoPose.front);
    final latest = dates.length < 2 ? null : s.photoFor(dates.last, PhotoPose.front);

    Widget photo(PhotoCheckin? p, String label, DateTime? date) {
      final path = p == null ? null : s.pathFor(p);
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 104,
                child: path == null
                    ? Container(color: c.chip, child: Icon(Icons.person_outline_rounded, color: c.muted))
                    : Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        cacheWidth: 240,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => Container(color: c.chip),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(label, style: AppText.body(c).copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (date != null) Text(shortDate(date), style: AppText.quiet(c).copyWith(fontSize: 11)),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(c, 'Weight', Text('12 weeks', style: AppText.quiet(c).copyWith(fontSize: 12)), [
          if (weights.length < 2)
            _empty(c, 'Log your weight on a few mornings to see your trend here.')
          else ...[
            _big(c, headline == null ? '–' : oneDecimal(disp(headline)), avg == null ? '$unit, latest' : '$unit, 7-day avg', weekChange),
            const SizedBox(height: 6),
            SizedBox(
              height: 80,
              child: CustomPaint(
                painter: _Spark(values: [for (final w in weights) disp(w.weightKg)], line: c.accent, fill: c.accent.withAlpha(30)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        MusclesOverviewCard(onOpen: widget.onTraining),
        const SizedBox(height: 10),
        _card(
          c,
          'Estimated 1RM',
          lifts.isEmpty
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'Choose a lift',
                  initialValue: lift,
                  onSelected: (v) => setState(() => _lift = v),
                  color: c.surface,
                  itemBuilder: (_) => [
                    for (final id in lifts) PopupMenuItem<String>(value: id, child: Text(s.exerciseName(id))),
                  ],
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: c.chip,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(
                            s.exerciseName(lift!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(c).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Icon(Icons.expand_more_rounded, size: 16, color: c.muted),
                      ],
                    ),
                  ),
                ),
          [
            if (shown.isEmpty)
              _empty(c, 'Log a few workouts to see your strength trend here.')
            else ...[
              _big(c, disp(shown.last.$2).round().toString(), unit, gain),
              const SizedBox(height: 6),
              SizedBox(
                height: 76,
                child: CustomPaint(
                  painter: _Spark(values: [for (final p in shown) disp(p.$2)], line: c.accent, fill: c.accent.withAlpha(30)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _card(c, 'Sleep', Text('7 nights', style: AppText.quiet(c).copyWith(fontSize: 12)), [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(sleepAvg == null ? '–' : oneDecimal(sleepAvg),
                          style: AppText.title(c).copyWith(fontSize: 22, fontWeight: FontWeight.w300)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('h avg · goal ${oneDecimal(goal)}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.quiet(c).copyWith(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 70,
                    child: CustomPaint(
                      painter: _SleepBars(hours: nights, goal: goal, bar: c.accent, soft: c.accent.withAlpha(60), guide: c.muted),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _card(
                  c,
                  'Photos',
                  dates.isEmpty
                      ? null
                      : GestureDetector(
                          onTap: widget.onPhotos,
                          child: Text('All', style: AppText.body(c).copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent)),
                        ),
                  [
                    if (dates.isEmpty) ...[
                      _empty(c, 'No progress photos yet.'),
                      SmallButton(
                        label: 'Take photos',
                        quiet: true,
                        onTap: () => Navigator.of(context).push(CameraScreen.route()),
                      ),
                    ] else
                      Row(
                        children: [
                          photo(first, 'First', dates.first),
                          if (dates.length >= 2) ...[
                            const SizedBox(width: 6),
                            photo(latest, 'Latest', dates.last),
                          ],
                        ],
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

/// A small line chart with a soft fill, ending in a dot.
class _Spark extends CustomPainter {
  _Spark({required this.values, required this.line, required this.fill});

  final List<double> values;
  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    const pad = 6.0;
    Offset at(int i) => Offset(
          pad + i * (size.width - 2 * pad) / (values.length - 1),
          pad + (1 - (values[i] - lo) / span) * (size.height - 2 * pad),
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(at(values.length - 1).dx, size.height)
      ..lineTo(at(0).dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(values.length - 1), 3.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_Spark old) => old.values != values || old.line != line || old.fill != fill;
}

/// Seven bars (one per night, missing nights left empty) and a dashed goal line.
class _SleepBars extends CustomPainter {
  _SleepBars({required this.hours, required this.goal, required this.bar, required this.soft, required this.guide});

  final List<double?> hours;
  final double goal;
  final Color bar;
  final Color soft;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final top = math.max(9.0, goal + 1);
    final n = hours.length;
    final gap = size.width * 0.05;
    final w = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final h = hours[i];
      if (h == null) continue;
      final bh = (h / top).clamp(0.0, 1.0) * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * (w + gap), size.height - bh, w, bh), const Radius.circular(4)),
        Paint()..color = i == n - 1 ? bar : soft,
      );
    }
    final gy = size.height - (goal / top) * size.height;
    final dash = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, gy), Offset(math.min(x + 3, size.width), gy), dash);
    }
  }

  @override
  bool shouldRepaint(_SleepBars old) => old.hours != hours || old.goal != goal || old.bar != bar;
}
