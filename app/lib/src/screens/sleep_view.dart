import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/sleep_editor.dart';

/// Sleep half of the Progress tab.
class SleepView extends StatelessWidget {
  const SleepView({super.key});

  static const _nights = 14;

  void _edit(BuildContext context, DateTime morning) {
    final c = AppColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(sheet).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: SleepEditor(
            date: morning,
            title: 'Night before ${shortDate(morning)}',
            onClose: () => Navigator.of(sheet).pop(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final goalMin = (s.settings.sleepGoalHours * 60).round();

    if (s.sleep.isEmpty) {
      return SectionCard(
        title: 'Sleep',
        child: Text(
          'Add last night\'s sleep in the morning check-in on Home. '
          'Averages and trends appear here as nights are logged.',
          style: AppText.body(c),
        ),
      );
    }

    final recent = s.recentSleep(_nights);
    final week = s.recentSleep(7);
    final weekMins = [
      for (final e in week)
        if (e.durationMin != null) e.durationMin!,
    ];
    final avg = averageMinutes(weekMins);
    final spread = bedtimeSpreadMinutes([
      for (final e in recent)
        if (e.bedMinute != null) e.bedMinute!,
    ]);
    final qualities = [
      for (final e in recent)
        if (e.quality != null) e.quality!,
    ];
    final avgQuality = qualities.isEmpty
        ? null
        : qualities.reduce((a, b) => a + b) / qualities.length;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bars = <int?>[
      for (var i = _nights - 1; i >= 0; i--)
        s.sleepOn(DateTime(today.year, today.month, today.day - i))?.durationMin,
    ];

    String? vsGoal;
    if (avg != null) {
      final diff = avg - goalMin;
      vsGoal = diff.abs() < 5
          ? 'Right on your ${oneDecimal(s.settings.sleepGoalHours)} h goal'
          : '${formatSleep(diff.abs().round())} ${diff < 0 ? 'under' : 'over'} '
              'your ${oneDecimal(s.settings.sleepGoalHours)} h goal';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          avg == null ? 'Sleep' : '7-night average',
          style: AppText.quiet(c).copyWith(fontSize: 14),
        ),
        Text(
          avg == null ? 'No nights this week' : formatSleep(avg.round()),
          style: AppText.title(c).copyWith(fontSize: 40, fontWeight: FontWeight.w300),
        ),
        if (vsGoal != null)
          Text(
            vsGoal,
            style: AppText.body(c).copyWith(
              color: c.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Last 14 nights',
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 150,
                child: CustomPaint(
                  painter: _SleepBarsPainter(
                    nights: bars,
                    goalMin: goalMin,
                    colors: c,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    shortDate(DateTime(today.year, today.month, today.day - _nights + 1)),
                    style: AppText.quiet(c).copyWith(fontSize: 11),
                  ),
                  const Spacer(),
                  Text('Today', style: AppText.quiet(c).copyWith(fontSize: 11)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Dashed line: your ${oneDecimal(s.settings.sleepGoalHours)} h goal. '
                'Change it in Settings.',
                style: AppText.quiet(c).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: 'Bedtime consistency',
                value: spread == null ? '—' : '± ${spread.round()} min',
                note: spread == null ? 'Needs 3 nights with times' : 'Lower is steadier',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                label: 'Average quality',
                value: avgQuality == null ? '—' : '${avgQuality.toStringAsFixed(1)} / 5',
                note: '${qualities.length} rated of ${recent.length} nights',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Nightly log',
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            children: [
              for (final e in recent.reversed)
                _LogRow(entry: e, onEdit: () => _edit(context, e.date)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.note});

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
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
            style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(note, style: AppText.quiet(c).copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.onEdit});

  final SleepEntry entry;
  final VoidCallback onEdit;

  String _time(BuildContext context, int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final details = <String>[];
    if (entry.bedMinute != null && entry.wakeMinute != null) {
      details.add('${_time(context, entry.bedMinute!)} to ${_time(context, entry.wakeMinute!)}');
    }
    if (entry.quality != null) details.add('quality ${entry.quality}/5');
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(shortDate(entry.date), style: AppText.quiet(c)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.durationMin == null ? 'Logged' : formatSleep(entry.durationMin!),
                  style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
                ),
                if (details.isNotEmpty)
                  Text(details.join(', '), style: AppText.quiet(c).copyWith(fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: onEdit,
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

class _SleepBarsPainter extends CustomPainter {
  _SleepBarsPainter({
    required this.nights,
    required this.goalMin,
    required this.colors,
  });

  final List<int?> nights;
  final int goalMin;
  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final logged = nights.whereType<int>();
    final top = math.max(
      goalMin + 60,
      logged.isEmpty ? 0 : logged.reduce(math.max) + 30,
    ).toDouble();
    final n = nights.length;
    const gap = 6.0;
    final w = (size.width - gap * (n - 1)) / n;
    double y(num minutes) => size.height - (minutes / top) * size.height;

    final bar = Paint()..color = colors.accent;
    final under = Paint()..color = colors.accent.withAlpha(110);
    final empty = Paint()..color = colors.line;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final m = nights[i];
      if (m == null) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - 3, w, 3),
            const Radius.circular(2),
          ),
          empty,
        );
        continue;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, y(m), x + w, size.height),
          const Radius.circular(4),
        ),
        m >= goalMin ? bar : under,
      );
    }

    // Goal line, dashed.
    final gy = y(goalMin);
    final dash = Paint()
      ..color = colors.text.withAlpha(120)
      ..strokeWidth = 1.2;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, gy), Offset(math.min(x + 4, size.width), gy), dash);
    }
  }

  @override
  bool shouldRepaint(_SleepBarsPainter old) =>
      old.nights != nights || old.goalMin != goalMin || old.colors != colors;
}
