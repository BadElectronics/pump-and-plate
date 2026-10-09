import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Weight over time: daily weigh-ins as dots, weekly averages as a line,
/// and the projection at your current targets as a dashed line.
/// Values are kg; [imperial] only changes the labels.
class WeightChart extends StatelessWidget {
  const WeightChart({
    super.key,
    required this.daily,
    required this.weekly,
    required this.projection,
    required this.start,
    required this.today,
    required this.imperial,
    this.compact = false,
    this.height = 200,
  });

  final List<DayWeight> daily;
  final List<DayWeight> weekly;
  final List<DayWeight> projection;
  final DateTime start;
  final DateTime today;
  final bool imperial;
  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: reduceMotion ? 0 : 400),
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) => CustomPaint(
          size: Size.infinite,
          painter: _WeightChartPainter(
            daily: daily,
            weekly: weekly,
            projection: projection,
            start: start,
            today: today,
            imperial: imperial,
            compact: compact,
            progress: progress,
            colors: c,
          ),
        ),
      ),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  _WeightChartPainter({
    required this.daily,
    required this.weekly,
    required this.projection,
    required this.start,
    required this.today,
    required this.imperial,
    required this.compact,
    required this.progress,
    required this.colors,
  });

  final List<DayWeight> daily;
  final List<DayWeight> weekly;
  final List<DayWeight> projection;
  final DateTime start;
  final DateTime today;
  final bool imperial;
  final bool compact;
  final double progress;
  final AppColors colors;

  double _v(double kg) => imperial ? kgToLb(kg) : kg;

  void _label(Canvas canvas, String text, Offset at, {TextAlign align = TextAlign.left, bool strong = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: 10,
          color: strong ? colors.text : colors.muted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (align == TextAlign.right) dx -= tp.width;
    if (align == TextAlign.center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final values = <double>[
      for (final (_, kg) in daily) _v(kg),
      for (final (_, kg) in weekly) _v(kg),
      for (final (_, kg) in projection) _v(kg),
    ];
    if (values.isEmpty) return;

    final rightGutter = compact ? 0.0 : 36.0;
    final bottomGutter = compact ? 0.0 : 18.0;
    final plot = Rect.fromLTRB(
      6,
      8,
      size.width - rightGutter - 6,
      size.height - bottomGutter - 6,
    );

    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    final pad = math.max((hi - lo) * 0.15, imperial ? 1.0 : 0.5);
    lo -= pad;
    hi += pad;

    final end = projection.isNotEmpty ? projection.last.$1 : today;
    final spanHours = math.max(1, end.difference(start).inHours).toDouble();
    double x(DateTime d) =>
        plot.left + (d.difference(start).inHours / spanHours) * plot.width;
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;

    // Grid and value labels.
    if (!compact) {
      final grid = Paint()
        ..color = colors.line
        ..strokeWidth = 1;
      for (var i = 0; i < 3; i++) {
        final v = lo + pad / 2 + (hi - lo - pad) * i / 2;
        final gy = y(v);
        canvas.drawLine(Offset(plot.left, gy), Offset(plot.right, gy), grid);
        _label(canvas, v.round().toString(), Offset(plot.right + 8, gy));
      }
      // Today marker.
      final tx = x(today);
      final dash = Paint()
        ..color = colors.line
        ..strokeWidth = 1;
      for (var yy = plot.top; yy < plot.bottom; yy += 6) {
        canvas.drawLine(Offset(tx, yy), Offset(tx, math.min(yy + 2, plot.bottom)), dash);
      }
      final labelY = size.height - 8;
      _label(canvas, shortDate(start), Offset(plot.left, labelY));
      _label(canvas, 'Today', Offset(tx, labelY), align: TextAlign.center, strong: true);
      if (projection.isNotEmpty) {
        _label(canvas, shortDate(end), Offset(plot.right, labelY), align: TextAlign.right);
      }
    }

    // Draw-in animation reveals the data left to right.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));

    final dotPaint = Paint()..color = colors.muted.withAlpha(150);
    for (final (d, kg) in daily) {
      canvas.drawCircle(Offset(x(d), y(_v(kg))), compact ? 2 : 2.4, dotPaint);
    }

    // Projection, dashed.
    if (projection.length >= 2) {
      final p = Paint()
        ..color = colors.accent.withAlpha(130)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < projection.length - 1; i++) {
        final a = Offset(x(projection[i].$1), y(_v(projection[i].$2)));
        final b = Offset(x(projection[i + 1].$1), y(_v(projection[i + 1].$2)));
        final len = (b - a).distance;
        if (len == 0) continue;
        final dir = (b - a) / len;
        for (var t = 0.0; t < len; t += 9) {
          canvas.drawLine(a + dir * t, a + dir * math.min(t + 4, len), p);
        }
      }
    }

    // Weekly average line.
    if (weekly.isNotEmpty) {
      final line = Paint()
        ..color = colors.accent
        ..strokeWidth = compact ? 2.2 : 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = Path();
      for (var i = 0; i < weekly.length; i++) {
        final o = Offset(x(weekly[i].$1), y(_v(weekly[i].$2)));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, line);
      final fill = Paint()..color = colors.accent;
      final ring = Paint()
        ..color = colors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      for (var i = 0; i < weekly.length; i++) {
        final o = Offset(x(weekly[i].$1), y(_v(weekly[i].$2)));
        final r = i == weekly.length - 1 ? 5.0 : (compact ? 0.0 : 3.5);
        if (r == 0) continue;
        canvas.drawCircle(o, r, fill);
        canvas.drawCircle(o, r, ring);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WeightChartPainter old) =>
      old.progress != progress ||
      old.daily != daily ||
      old.weekly != weekly ||
      old.projection != projection ||
      old.imperial != imperial ||
      old.colors != colors;
}

/// Weekly averages plus a 3-week projection, ready for [WeightChart].
class ChartData {
  const ChartData({
    required this.start,
    required this.daily,
    required this.weekly,
    required this.projection,
  });

  final DateTime start;
  final List<DayWeight> daily;
  final List<DayWeight> weekly;
  final List<DayWeight> projection;

  /// [days] of history ending today. [changePerDayKg] comes from the
  /// current targets; null means no projection.
  factory ChartData.build({
    required List<DayWeight> all,
    required DateTime today,
    required int days,
    double? changePerDayKg,
  }) {
    final t = DateTime(today.year, today.month, today.day);
    final start = DateTime(t.year, t.month, t.day - days + 1);
    final daily = [
      for (final e in all)
        if (!e.$1.isBefore(start)) e,
    ];
    final weekly = weeklySeries(all, t, (days / 7).ceil(), minCount: 2);
    final projection = <DayWeight>[];
    if (changePerDayKg != null && weekly.isNotEmpty) {
      final last = weekly.last;
      for (var k = 0; k <= 3; k++) {
        final d = DateTime(last.$1.year, last.$1.month, last.$1.day + 7 * k);
        projection.add((d, last.$2 + changePerDayKg * 7 * k));
      }
    }
    return ChartData(
      start: start,
      daily: daily,
      weekly: weekly,
      projection: projection,
    );
  }
}
