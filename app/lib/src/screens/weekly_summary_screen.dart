import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

String _phaseName(Phase p) => switch (p.mode) {
      GoalMode.lose => 'Cut',
      GoalMode.gain => 'Lean bulk',
      GoalMode.maintain => 'Maintain',
    };

/// The stats for one week, as rows of (label, value).
List<(String, String)> weekRows(AppState s, WeekSummary w) {
  final imperial = s.settings.units == Units.imperial;
  final unit = imperial ? 'lb' : 'kg';
  String kg(double v) => '${oneDecimal(imperial ? kgToLb(v) : v)} $unit';
  final change = w.weightChangeKg;
  final avg = w.avgWeightKg;
  return [
    if (avg != null)
      (
        'Average weight',
        change == null
            ? kg(avg)
            : '${kg(avg)} (${change < 0 ? '−' : '+'}${kg(change.abs())})',
      ),
    (
      'Workouts',
      w.workoutsPlanned > 0 ? '${w.workouts} of ${w.workoutsPlanned} planned' : '${w.workouts}',
    ),
    if (w.avgSleepMin != null) ('Average sleep', formatSleep(w.avgSleepMin!.round())),
    if (w.foodDays > 0)
      (
        'Calories',
        w.targetKcal == null
            ? '${thousands(w.avgKcal!)} a day'
            : '${thousands(w.avgKcal!)} a day (target ${thousands(w.targetKcal!)})',
      ),
    if (w.foodDays > 0) ('Protein target hit', '${w.proteinDaysHit} of ${w.foodDays} days logged'),
    if (w.phase != null) ('Phase', _phaseName(w.phase!)),
  ];
}

class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.week, this.title, this.onDismiss, this.onSeeAll});

  final WeekSummary week;
  final String? title;
  final VoidCallback? onDismiss;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final rows = weekRows(s, week);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? 'Week of ${shortDate(week.start)}',
                      style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${shortDate(week.start)} – ${shortDate(week.end)}',
                      style: AppText.quiet(c).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: onDismiss,
                  icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 5, bottom: 5),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: AppText.quiet(c))),
                  Text(value, style: AppText.body(c).copyWith(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          if (onSeeAll != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: const Text('See past weeks'),
              ),
            ),
        ],
      ),
    );
  }
}

class WeeklySummaryScreen extends StatelessWidget {
  const WeeklySummaryScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const WeeklySummaryScreen());

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final weeks = s.recentSummaries();
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_rounded, color: c.text),
                ),
                Text('Weekly summaries', style: AppText.title(c).copyWith(fontSize: 22)),
              ],
            ),
            const SizedBox(height: 10),
            if (weeks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Finished weeks show up here once you\'ve logged something.',
                  style: AppText.quiet(c),
                ),
              ),
            for (final w in weeks)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 12),
                child: WeekCard(week: w),
              ),
          ],
        ),
      ),
    );
  }
}
