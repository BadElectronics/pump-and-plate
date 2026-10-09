import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/weight_chart.dart';
import 'measurements_view.dart';
import 'muscle_heatmap.dart';
import 'overview_view.dart';
import 'photos_view.dart';
import 'sleep_view.dart';
import 'strength_view.dart';
import 'weekly_summary_screen.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int _days = 56;

  /// 5 Overview (the default), 0 Weight, 4 Training, 1 Sleep, 2 Photos, 3 Body.
  int _section = 5;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    double disp(double kg) => imperial ? kgToLb(kg) : kg;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final t = s.targets;
    final data = ChartData.build(
      all: s.dayWeights,
      today: today,
      days: _days,
      changePerDayKg: t == null
          ? null
          : plannedChangeKgPerDay(
              maintenanceKcal: t.maintenanceKcal,
              plannedKcal: t.kcal,
            ),
    );

    final avg = s.weeklyAverageKg;
    final lastWeek = weeklyAverage(
      s.dayWeights,
      DateTime(today.year, today.month, today.day - 7),
    );
    final headline = avg ?? s.currentWeightKg;

    final hasTrend = s.weighIns.length >= 2;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text('Progress', style: AppText.title(c))),
              if (_section == 0 && hasTrend)
                SizedBox(
                  width: 190,
                  child: Segmented<int>(
                    label: 'Range',
                    options: const [(56, '8 wk'), (182, '6 mo'), (365, '1 yr')],
                    value: _days,
                    onChanged: (v) => setState(() => _days = v),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Monday's look back at last week (moved here from Home).
          if (s.summaryToShow != null) ...[
            WeekCard(
              week: s.summaryToShow!,
              title: 'Last week',
              onDismiss: s.dismissSummary,
              onSeeAll: () => Navigator.of(context).push(WeeklySummaryScreen.route()),
            ),
            const SizedBox(height: 14),
          ],
          Builder(builder: (context) {
            // (section, icon, label); Body only when it's turned on.
            final tabs = <(int, IconData, String)>[
              (5, Icons.dashboard_outlined, 'Overview'),
              (0, Icons.monitor_weight_outlined, 'Weight'),
              (4, Icons.fitness_center_rounded, 'Training'),
              (1, Icons.bedtime_outlined, 'Sleep'),
              (2, Icons.photo_camera_outlined, 'Photos'),
              if (s.settings.measurementsOn) (3, Icons.straighten_rounded, 'Body'),
            ];
            final shown = (_section == 3 && !s.settings.measurementsOn) ? 5 : _section;
            final index = tabs.indexWhere((t) => t.$1 == shown);
            return IconTabs(
              label: 'Progress section',
              small: true,
              items: [for (final t in tabs) (t.$2, t.$3)],
              index: index < 0 ? 0 : index,
              onChanged: (i) => setState(() => _section = tabs[i].$1),
            );
          }),
          const SizedBox(height: 14),
          if (_section == 5 || (_section == 3 && !s.settings.measurementsOn))
            OverviewView(onPhotos: () => setState(() => _section = 2), onTraining: () => setState(() => _section = 4))
          else if (_section == 4)
            const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [MuscleHeatmapCard(), SizedBox(height: 14), StrengthView()],
            )
          else if (_section == 1)
            const SleepView()
          else if (_section == 2)
            const PhotosView()
          else if (_section == 3)
            const MeasurementsView()
          else if (!hasTrend)
            SectionCard(
              title: 'Weight trend',
              child: Text(
                'Log your weight on a few mornings and your trend appears '
                'here. The weekly average shows once 4 days in a week are '
                'logged.',
                style: AppText.body(c),
              ),
            )
          else ...[
            Text(
              avg == null ? 'Latest weigh-in' : 'Weekly average',
              style: AppText.quiet(c).copyWith(fontSize: 14),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  oneDecimal(disp(headline!)),
                  style: AppText.title(c).copyWith(
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(width: 8),
                Text(unit, style: AppText.quiet(c).copyWith(fontSize: 18)),
              ],
            ),
            if (avg != null && lastWeek != null)
              Text(
                '${disp(avg) - disp(lastWeek) <= 0 ? '−' : '+'}'
                '${oneDecimal((disp(avg) - disp(lastWeek)).abs())} $unit from last week',
                style: AppText.body(c).copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w500,
                ),
              )
            else if (avg == null)
              Text(
                'Weekly average shows once 4 days this week are logged.',
                style: AppText.quiet(c),
              ),
            const SizedBox(height: 16),
            SectionCard(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WeightChart(
                    key: ValueKey(_days),
                    daily: data.daily,
                    weekly: data.weekly,
                    projection: data.projection,
                    start: data.start,
                    today: today,
                    imperial: imperial,
                    height: 210,
                  ),
                  const SizedBox(height: 10),
                  _Legend(c: c, hasProjection: data.projection.isNotEmpty),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _stats(s, c, disp, unit),
            const SizedBox(height: 14),
            _lastSeven(s, c, disp, today),
          ],
        ],
      ),
    );
  }

  Widget _stats(AppState s, AppColors c, double Function(double) disp, String unit) {
    final start = s.weighIns.first.weightKg;
    final nowKg = s.weeklyAverageKg ?? s.currentWeightKg!;
    final change = disp(nowKg) - disp(start);
    final target = s.goal.targetWeightKg;
    return Row(
      children: [
        Expanded(child: _StatBox(label: 'Start', value: '${oneDecimal(disp(start))} $unit')),
        const SizedBox(width: 8),
        Expanded(
          child: _StatBox(
            label: 'Change',
            value: '${change <= 0 ? '−' : '+'}${oneDecimal(change.abs())} $unit',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatBox(
            label: 'Goal',
            value: target == null ? 'Not set' : '${oneDecimal(disp(target))} $unit',
          ),
        ),
      ],
    );
  }

  Widget _lastSeven(AppState s, AppColors c, double Function(double) disp, DateTime today) {
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SectionCard(
      title: 'Last 7 days',
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Row(
        children: [
          for (var i = 6; i >= 0; i--)
            Expanded(
              child: Builder(builder: (context) {
                final day = DateTime(today.year, today.month, today.day - i);
                final w = s.weighInOn(day);
                final isToday = i == 0;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isToday ? c.accent.withAlpha(36) : c.accent.withAlpha(0),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(letters[day.weekday - 1], style: AppText.quiet(c).copyWith(fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        w == null ? '–' : oneDecimal(disp(w.weightKg)),
                        style: AppText.body(c).copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: w == null ? c.muted : c.text,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.quiet(c).copyWith(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppText.body(c).copyWith(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.c, required this.hasProjection});

  final AppColors c;
  final bool hasProjection;

  @override
  Widget build(BuildContext context) {
    final style = AppText.quiet(c).copyWith(fontSize: 12);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('Daily', style: style),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 16, height: 3, color: c.accent),
          const SizedBox(width: 6),
          Text('Weekly average', style: style),
        ]),
        if (hasProjection)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 16, height: 2, color: c.accent.withAlpha(130)),
            const SizedBox(width: 6),
            Text('Projected at your targets', style: style),
          ]),
      ],
    );
  }
}

