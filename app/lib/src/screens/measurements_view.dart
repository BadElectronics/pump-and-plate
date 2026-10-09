import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Rows on the logging sheet: single sites, or left/right pairs.
const _layout = <(String, MeasureSite, MeasureSite?)>[
  ('Neck', MeasureSite.neck, null),
  ('Shoulders', MeasureSite.shoulders, null),
  ('Chest', MeasureSite.chest, null),
  ('Waist', MeasureSite.waist, null),
  ('Hips', MeasureSite.hips, null),
  ('Biceps', MeasureSite.bicepLeft, MeasureSite.bicepRight),
  ('Forearms', MeasureSite.forearmLeft, MeasureSite.forearmRight),
  ('Thighs', MeasureSite.thighLeft, MeasureSite.thighRight),
  ('Calves', MeasureSite.calfLeft, MeasureSite.calfRight),
];

/// Body half of the Progress tab (shown when measurements are turned on).
class MeasurementsView extends StatelessWidget {
  const MeasurementsView({super.key});

  static void openSheet(BuildContext context, DateTime date) {
    final c = AppColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => _MeasureSheet(date: date),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'in' : 'cm';
    double disp(double cm) => imperial ? cmToInch(cm) : cm;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dates = s.measurementDates;

    final logButton = SmallButton(
      label: s.measurementDates.any((d) => d == today)
          ? 'Edit today\'s measurements'
          : 'Log measurements',
      onTap: () => openSheet(context, today),
    );

    if (dates.isEmpty) {
      return SectionCard(
        title: 'Body measurements',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Measure whichever spots you like: neck, chest, waist, arms, '
              'legs and more. Every one is optional. Once a month, or with '
              'your progress photos, is plenty.',
              style: AppText.body(c),
            ),
            const SizedBox(height: 8),
            Text(
              'Use a soft tape, snug but not squeezing, in the morning before '
              'eating. Each field shows exactly where to measure.',
              style: AppText.quiet(c),
            ),
            const SizedBox(height: 14),
            logButton,
          ],
        ),
      );
    }

    final rows = <Widget>[];
    for (final site in MeasureSite.values) {
      final list = s.measurementsFor(site);
      if (list.isEmpty) continue;
      final latest = list.last;
      final first = list.first;
      final change = disp(latest.valueCm) - disp(first.valueCm);
      rows.add(Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          border: rows.isEmpty ? null : Border(top: BorderSide(color: c.line)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(site.label, style: AppText.body(c)),
                  Text(
                    list.length < 2
                        ? shortDate(latest.date)
                        : '${change.abs() < 0.05 ? '±0' : '${change > 0 ? '+' : '−'}${oneDecimal(change.abs())}'} $unit '
                            'since ${shortDate(first.date)}',
                    style: AppText.quiet(c).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (list.length >= 2)
              SizedBox(
                width: 64,
                height: 26,
                child: CustomPaint(
                  painter: _Sparkline(
                    [for (final m in list) m.valueCm],
                    c.accent,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: Text(
                '${oneDecimal(disp(latest.valueCm))} $unit',
                textAlign: TextAlign.right,
                style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        logButton,
        const SizedBox(height: 14),
        SectionCard(
          title: 'Latest',
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(children: rows),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'History',
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            children: [
              for (final d in dates.reversed)
                Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    border: d == dates.last
                        ? null
                        : Border(top: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(longDate(d), style: AppText.body(c))),
                      Text(
                        '${s.measurements.where((m) => m.date == d).length} spots',
                        style: AppText.quiet(c),
                      ),
                      TextButton(
                        onPressed: () => openSheet(context, d),
                        style: TextButton.styleFrom(foregroundColor: c.accent),
                        child: const Text('Edit'),
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

class _MeasureSheet extends StatefulWidget {
  const _MeasureSheet({required this.date});

  final DateTime date;

  @override
  State<_MeasureSheet> createState() => _MeasureSheetState();
}

class _MeasureSheetState extends State<_MeasureSheet> {
  final Map<MeasureSite, TextEditingController> _fields = {
    for (final site in MeasureSite.values) site: TextEditingController(),
  };
  bool _filled = false;
  bool _imperial = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final s = AppScope.of(context);
    _imperial = s.settings.units == Units.imperial;
    for (final site in MeasureSite.values) {
      final m = s.measurementOn(widget.date, site);
      _fields[site]!.text = m == null
          ? ''
          : oneDecimal(_imperial ? cmToInch(m.valueCm) : m.valueCm);
    }
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _save() {
    final s = AppScope.of(context);
    final values = <MeasureSite, double?>{};
    for (final site in MeasureSite.values) {
      final text = _fields[site]!.text.trim();
      if (text.isEmpty) {
        values[site] = null;
        continue;
      }
      final v = parseNumber(text);
      if (v == null) continue;
      final cm = _imperial ? inchToCm(v) : v;
      if (cm < 5 || cm > 250) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${site.label} looks off. Check it and try again.')),
        );
        return;
      }
      values[site] = cm;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    s.logMeasurements(widget.date, values);
    Navigator.of(context).pop();
  }

  Widget _box(MeasureSite site, String suffix) {
    return NumberBox(
      controller: _fields[site]!,
      suffix: suffix,
      semanticLabel: site.label,
      onChanged: (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final unit = _imperial ? 'in' : 'cm';
    final now = DateTime.now();
    final isToday = widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text(
              isToday ? 'Today\'s measurements' : 'Measurements, ${longDate(widget.date)}',
              style: AppText.title(c).copyWith(fontSize: 22),
            ),
            const SizedBox(height: 6),
            Text(
              'Fill in any you measured and leave the rest blank. Clearing a '
              'field removes it.',
              style: AppText.quiet(c),
            ),
            const SizedBox(height: 16),
            for (final (title, left, right) in _layout) ...[
              Text(title, style: AppText.body(c).copyWith(fontWeight: FontWeight.w500)),
              Text(left.hint, style: AppText.quiet(c).copyWith(fontSize: 12)),
              const SizedBox(height: 6),
              if (right == null)
                _box(left, unit)
              else
                Row(
                  children: [
                    Expanded(child: _box(left, 'L $unit')),
                    const SizedBox(width: 8),
                    Expanded(child: _box(right, 'R $unit')),
                  ],
                ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SmallButton(
                    label: 'Cancel',
                    quiet: true,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: SmallButton(label: 'Save', onTap: _save)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final span = math.max(hi - lo, 0.5);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - 2 - (values[i] - lo) / span * (size.height - 4);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.values != values || old.color != color;
}
