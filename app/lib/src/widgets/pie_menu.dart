import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class PieItem {
  const PieItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Five slices around a centre button, with two slowly turning gradient
/// rings. [fold] runs from 0 to 1 as the pie gives way to the tab bar: the
/// chosen slice lights up, the others fade, the rings spin up and fade, and
/// the whole pie folds down out of sight.
class PieMenu extends StatefulWidget {
  const PieMenu({
    super.key,
    required this.items,
    required this.centre,
    required this.selected,
    required this.fold,
    required this.onPick,
    this.reduceMotion = false,
    this.returning = false,
    this.spotlight,
  });

  /// For the app tour: lights up slice 0 to 4 (5 is the centre) and fades
  /// the rest, without opening anything. -1 fades them all.
  final int? spotlight;

  /// True while folding back from a section to Home: no slice is
  /// highlighted, and the rings spin fast and then settle.
  final bool returning;

  /// Exactly five, clockwise from the top.
  final List<PieItem> items;
  final PieItem centre;

  /// 0 to 4 for a slice, 5 for the centre, null for none.
  final int? selected;
  final Animation<double> fold;
  final ValueChanged<int> onPick;
  final bool reduceMotion;

  @override
  State<PieMenu> createState() => _PieMenuState();
}

class _PieMenuState extends State<PieMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _spin.repeat();
  }

  @override
  void didUpdateWidget(PieMenu old) {
    super.didUpdateWidget(old);
    if (widget.reduceMotion && _spin.isAnimating) {
      _spin.stop();
    } else if (!widget.reduceMotion && !_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  static const _slices = 5;
  static const _step = 2 * math.pi / _slices;
  static const _base = -math.pi / 2 - _step / 2;

  int? _hit(Offset local, double size) {
    final c = Offset(size / 2, size / 2);
    final d = local - c;
    final dist = d.distance;
    final geo = _Geo(size);
    if (dist <= geo.chat) return 5;
    if (dist < geo.inner || dist > geo.outer + 6) return null;
    var rel = (math.atan2(d.dy, d.dx) - _base) % (2 * math.pi);
    if (rel < 0) rel += 2 * math.pi;
    return (rel / _step).floor() % _slices;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final size = math.min(box.maxWidth, box.maxHeight);
      return Center(
        child: SizedBox.square(
          dimension: size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, widget.fold]),
            builder: (context, _) => _pie(context, c, size),
          ),
        ),
      );
    });
  }

  Widget _pie(BuildContext context, AppColors c, double size) {
    final t = widget.fold.value;
    final back = widget.returning;
    // Opening: the chosen slice lights up first. Returning: nothing lights up.
    final spot = widget.spotlight;
    final h = back
        ? 0.0
        : (spot != null && t == 0 ? 1.0 : Curves.easeOut.transform((t / 0.35).clamp(0.0, 1.0)));
    final f = Curves.easeInOutCubic.transform(((t - 0.3) / 0.7).clamp(0.0, 1.0));
    // Extra turns on top of the slow drift, always in the same direction.
    // Opening: speed builds up (ease in) and the rings fade once they're
    // flying. Returning: they come in fast and slow down (ease out). Both
    // add whole turns, so nothing jumps when the transition ends.
    // With reduced motion the rings just fade: no extra spin.
    double boost;
    final double ringFade;
    if (back) {
      final r = 1 - t;
      boost = Curves.easeOutCubic.transform(r);
      ringFade = (r / 0.3).clamp(0.0, 1.0);
    } else {
      boost = Curves.easeInQuad.transform(t);
      ringFade = (1 - (t - 0.25) / 0.35).clamp(0.0, 1.0);
    }
    if (widget.reduceMotion) boost = 0;
    final base = _spin.value * 2 * math.pi;
    final spin = base + boost * 10 * math.pi;
    // The chat ring turns exactly twice per drift cycle (opposite way): a
    // whole number, so it doesn't jump when the cycle starts over.
    final chatSpin = -(base * 2) - boost * 12 * math.pi;
    final geo = _Geo(size);
    final sel = back ? null : (spot != null && t == 0 ? spot : widget.selected);
    final centreOn = sel == 5;

    final children = <Widget>[
      CustomPaint(
        size: Size.square(size),
        painter: _RingPainter(
          radius: geo.outer + geo.ringGap,
          band: 3,
          colors: [c.accent, c.ringA, c.ringB, c.accent],
          angle: spin,
          opacity: ringFade,
          scale: 1 + 0.08 * t,
        ),
      ),
      CustomPaint(
        size: Size.square(size),
        painter: _SlicesPainter(
          geo: geo,
          selected: sel,
          highlight: h,
          surface: c.surface,
          accent: c.accent,
        ),
      ),
    ];

    for (var i = 0; i < _slices; i++) {
      final a = -math.pi / 2 + i * _step;
      final r = (geo.outer + geo.inner) / 2 + size * 0.015;
      final on = sel == i;
      final fade = sel == null || on ? 1.0 : 1 - 0.85 * h;
      final fg = on ? Color.lerp(c.text, c.onAccent, h)! : c.text;
      final icon = on ? Color.lerp(c.accent, c.onAccent, h)! : c.accent;
      children.add(Positioned(
        left: size / 2 + r * math.cos(a) - 44,
        top: size / 2 + r * math.sin(a) - 30,
        width: 88,
        height: 60,
        child: IgnorePointer(
          child: Opacity(
            opacity: fade,
            child: Transform.scale(
              scale: on ? 1 + 0.05 * h : 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.items[i].icon, size: 24, color: icon),
                  const SizedBox(height: 4),
                  Text(
                    widget.items[i].label,
                    maxLines: 1,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    final chatFade = sel == null || centreOn ? 1.0 : 1 - 0.85 * h;
    children.add(Positioned(
      left: size / 2 - geo.chat,
      top: size / 2 - geo.chat,
      width: geo.chat * 2,
      height: geo.chat * 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: chatFade,
          child: Transform.scale(
            scale: centreOn ? 1 + 0.06 * h : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: centreOn ? Color.lerp(c.text, c.accent, h) : c.text,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.centre.icon,
                    size: 24,
                    color: centreOn ? Color.lerp(c.background, c.onAccent, h) : c.background,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.centre.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: centreOn ? Color.lerp(c.background, c.onAccent, h) : c.background,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    children.add(CustomPaint(
      size: Size.square(size),
      painter: _RingPainter(
        radius: geo.chat + 8,
        band: 2.5,
        colors: [c.ringA, c.accent, c.ringB, c.ringA],
        angle: chatSpin,
        opacity: ringFade,
        scale: 1 + 0.08 * t,
      ),
    ));

    // Taps go by position; each slice also has its own label for screen readers.
    children.add(Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) {
          if (widget.fold.value > 0) return;
          final i = _hit(d.localPosition, size);
          if (i != null) widget.onPick(i);
        },
      ),
    ));
    for (var i = 0; i <= _slices; i++) {
      final isCentre = i == _slices;
      final a = -math.pi / 2 + i * _step;
      final r = (geo.outer + geo.inner) / 2;
      children.add(Positioned(
        left: isCentre ? size / 2 - 28 : size / 2 + r * math.cos(a) - 28,
        top: isCentre ? size / 2 - 28 : size / 2 + r * math.sin(a) - 28,
        width: 56,
        height: 56,
        child: Semantics(
          button: true,
          label: isCentre ? widget.centre.label : widget.items[i].label,
          onTap: () => widget.onPick(i),
          child: const SizedBox.expand(),
        ),
      ));
    }

    return Opacity(
      opacity: (1 - f).clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(0.0, f * size * 1.1)
          ..scale(1 + 0.15 * f, 1 - 0.8 * f),
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
}

/// Sizes of the pie's parts for a given overall size.
class _Geo {
  _Geo(this.size)
      : ringGap = size * 0.035,
        outer = size / 2 - size * 0.06,
        inner = (size / 2 - size * 0.06) * 0.345,
        chat = (size / 2 - size * 0.06) * 0.345 - 6;

  final double size;
  final double ringGap;
  final double outer;
  final double inner;
  final double chat;
}

class _SlicesPainter extends CustomPainter {
  _SlicesPainter({
    required this.geo,
    required this.selected,
    required this.highlight,
    required this.surface,
    required this.accent,
  });

  final _Geo geo;
  final int? selected;
  final double highlight;
  final Color surface;
  final Color accent;

  static const _step = 2 * math.pi / 5;
  static const _base = -math.pi / 2 - _step / 2;

  Path _slice(Offset c, int i) {
    const gap = 1.6 * math.pi / 180;
    final innerGap = gap * geo.outer / geo.inner * 0.55;
    final a0 = _base + i * _step + gap;
    final sweep = _step - 2 * gap;
    final b0 = _base + i * _step + innerGap;
    final innerSweep = _step - 2 * innerGap;
    return Path()
      ..arcTo(Rect.fromCircle(center: c, radius: geo.outer), a0, sweep, true)
      ..arcTo(Rect.fromCircle(center: c, radius: geo.inner), b0 + innerSweep, -innerSweep, false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 5; i++) {
      final on = selected == i;
      final fade = selected == null || on ? 1.0 : 1 - 0.85 * highlight;
      final color = on ? Color.lerp(surface, accent, highlight)! : surface;
      final paint = Paint()..color = color.withAlpha((fade * 255).round());
      if (on) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(1 + 0.05 * highlight);
        canvas.translate(-c.dx, -c.dy);
        canvas.drawPath(_slice(c, i), paint);
        canvas.restore();
      } else {
        canvas.drawPath(_slice(c, i), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SlicesPainter old) =>
      old.selected != selected || old.highlight != highlight || old.surface != surface || old.accent != accent;
}

/// A thin band of colour that fades out across its width, with a faint
/// blurred glow behind it so it melts into its surroundings.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.radius,
    required this.band,
    required this.colors,
    required this.angle,
    required this.opacity,
    required this.scale,
  });

  final double radius;
  final double band;
  final List<Color> colors;
  final double angle;
  final double opacity;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;
    final c = size.center(Offset.zero);
    final r = radius * scale;
    final rect = Rect.fromCircle(center: c, radius: r);
    final shader = SweepGradient(colors: colors, transform: GradientRotation(angle)).createShader(rect);
    final glow = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = band * 3.2
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, band * 1.6)
      ..color = Color.fromRGBO(0, 0, 0, 0.45 * opacity);
    final core = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = band
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9)
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    canvas.drawCircle(c, r, glow);
    canvas.drawCircle(c, r, core);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.angle != angle || old.opacity != opacity || old.scale != scale || old.colors != colors;
}
