import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/muscles.dart';
import '../theme/tokens.dart';

// The body is drawn on a 200 x 400 grid (the same drawing as the mockups),
// left half only: the right half is its mirror image. Shapes are SVG path
// data (M, L, C and Z, absolute).

const _outline = 'M100 50 L93 50 C93 58 91 64 85 68 C77 73 67 74 58 76 C48 79 43 88 43 100 '
    'C42 112 41 124 40 136 C39 146 38 154 38 162 C36 176 34 192 33 208 C32 218 32 226 35 230 '
    'C38 233 43 231 45 225 C47 218 47 212 48 206 C51 192 55 176 58 160 C61 148 63 138 64 128 '
    'C65 140 66 156 67 172 C68 184 68 194 67 204 C64 230 64 262 70 292 C70 300 70 308 72 316 '
    'C72 336 75 356 80 372 C80 380 78 386 82 389 C88 391 94 389 95 385 C95 377 94 368 95 360 '
    'C97 344 98 324 96 304 C96 296 96 291 97 286 C98 264 99 240 100 214 Z';

// ---------------------------------------------------------------- heads

const _frontDelt = 'M58 77 C64 76 70 76 74 78 C71 90 68 101 64 111 C59 109 54 108 50 111 C52 101 54 91 58 84 Z';
const _sideDelt = 'M58 77 C48 79 43 88 44 100 C45 106 47 109 50 111 C52 101 54 91 58 84 Z';
const _calfInnerFront = 'M90 302 C96 312 98 328 95 346 C92 344 89 336 88 326 C87 316 88 308 90 302 Z';
const _soleusFront = 'M74 316 C73 332 75 348 79 360 C81 356 81 346 80 336 C79 328 77 320 74 316 Z';
const _adductors = 'M87 209 C89 226 91 240 93 252 C96 246 98 232 98 215 C95 211 91 209 87 209 Z';
const _obliques = 'M87 125 C80 126 74 129 71 135 C70 150 72 168 77 182 C81 188 86 191 90 190 C87 178 86 165 86 152 C86 142 86 133 87 125 Z';
const _brachialis = 'M45 134 C42 143 41 152 42 160 L47 160 C47 157 47 154 47 152 C45 146 44 140 45 134 Z';
const _trapsFront = 'M93 56 C91 64 86 69 76 73 L86 74 C92 70 95 64 96 57 Z';
const _infraspinatus = 'M74 80 C71 90 70 98 72 104 C77 106 81 106 85 102 C84 95 80 88 74 80 Z';
const _teres = 'M72 105 C68 109 66 114 67 119 C73 118 78 114 83 109 C79 107 75 106 72 105 Z';
const _rhomboids = 'M86 99 C89 108 93 117 96 125 L91 125 C87 118 85 112 85 103 Z';
const _erectors = 'M100 140 C96 141 94 145 93 151 C92 166 92 182 94 196 L100 197 Z';
const _extensors = 'M41 163 C37 176 36 190 37 204 C38 208 40 212 42 213 L46 213 C49 198 53 180 57 163 Z';

const _frontHeads = <MuscleHead, String>{
  MuscleHead.trapsUpper: _trapsFront,
  MuscleHead.chestUpper: 'M99 80 L75 78 C72 84 70 89 69 95 C80 93 90 93 99 94 Z',
  MuscleHead.chestMiddle: 'M99 94 C90 93 80 93 69 95 C68 101 67 106 66 110 C76 108 88 108 99 109 Z',
  MuscleHead.chestLower: 'M99 109 C88 108 76 108 66 110 C70 116 76 120 84 121 C90 121 95 120 99 119 Z',
  MuscleHead.frontDelt: _frontDelt,
  MuscleHead.sideDelt: _sideDelt,
  MuscleHead.bicepsLong: 'M48 114 C44 128 44 142 47 152 C49 154 51 155 53 155 C53 140 53 126 54 112 C52 112 50 113 48 114 Z',
  MuscleHead.bicepsShort: 'M54 112 C53 126 53 140 53 155 C55 155 56 153 57 150 C60 140 61 126 60 114 C58 112.5 56 112 54 112 Z',
  MuscleHead.brachialis: _brachialis,
  MuscleHead.brachioradialis: 'M42 161 C38 172 36 184 35 196 L40 198 C43 186 46 174 50 162 Z',
  MuscleHead.forearmFlexors: 'M50 162 C46 174 43 186 40 198 C39 204 39 209 40 213 L46 213 C49 200 53 182 58 163 C55 160 52 160 50 162 Z',
  MuscleHead.absUpper: 'M100 123 L89 124 C87 132 87 142 87 152 L100 152 Z',
  MuscleHead.absLower: 'M100 152 L87 152 C87 165 88 178 92 188 C95 191 98 192 100 192 Z',
  MuscleHead.obliques: _obliques,
  MuscleHead.vastusLateralis: 'M70 206 C66 232 67 262 73 290 C76 292 79 291 80 288 C78 262 77 236 78 210 Z',
  MuscleHead.rectusFemoris: 'M78 207 C77 236 78 262 80 288 C83 290 86 290 88 286 C90 262 90 236 87 209 C84 206 81 206 78 207 Z',
  MuscleHead.vastusMedialis: 'M88 286 C89 272 91 260 93 252 C97 260 98 276 96 290 C93 292 90 291 88 286 Z',
  MuscleHead.adductors: _adductors,
  MuscleHead.calfInner: _calfInnerFront,
  MuscleHead.soleus: _soleusFront,
};

const _backHeads = <MuscleHead, String>{
  MuscleHead.trapsUpper: 'M100 54 C96 62 88 70 72 76 C82 81 92 84 100 86 Z',
  MuscleHead.trapsMiddle: 'M100 86 C92 84 82 81 72 76 C74 84 79 92 86 98 C92 100 96 102 100 104 Z',
  MuscleHead.trapsLower: 'M100 104 C96 102 92 100 86 98 C90 110 95 124 100 136 Z',
  MuscleHead.rearDelt: _frontDelt,
  MuscleHead.sideDelt: _sideDelt,
  MuscleHead.infraspinatus: _infraspinatus,
  MuscleHead.teres: _teres,
  MuscleHead.rhomboids: _rhomboids,
  MuscleHead.latsUpper: 'M67 120 C68 130 70 142 74 152 C82 146 90 139 96 128 L91 126 C88 120 85 114 84 110 C78 115 73 118 67 120 Z',
  MuscleHead.latsLower: 'M74 152 C78 164 84 176 91 184 C93 170 95 150 96 128 C90 139 82 146 74 152 Z',
  MuscleHead.erectors: _erectors,
  MuscleHead.tricepsLateral: 'M47 112 C43 124 42 138 44 150 C47 146 50 138 51 128 C52 122 52 116 52 112 Z',
  MuscleHead.tricepsLong: 'M52 112 C52 116 52 122 51 128 C50 138 47 146 44 150 C46 156 52 156 56 152 C60 140 62 126 62 114 C58 111 55 111 52 112 Z',
  MuscleHead.tricepsMedial: 'M44 151 C44 156 45 160 47 162 L55 162 C56 158 56 155 56 153 C52 157 46 156 44 151 Z',
  MuscleHead.forearmExtensors: _extensors,
  MuscleHead.gluteMed: 'M73 192 C69 196 67 202 68 210 C70 207 72 205 75 204 C82 199 90 197 98 197 C92 191 82 189 73 192 Z',
  MuscleHead.gluteMax: 'M100 199 C92 197 82 199 75 205 C72 214 74 226 80 232 C88 236 96 234 100 230 Z',
  MuscleHead.hamOuter: 'M75 238 C71 256 72 274 76 290 C79 292 82 291 84 288 C84 270 84 252 86 237 C82 236 78 236 75 238 Z',
  MuscleHead.hamInner: 'M86 237 C84 252 84 270 84 288 C87 291 91 291 94 288 C97 272 98 254 97 238 C93 235 89 235 86 237 Z',
  MuscleHead.calfOuter: 'M76 304 C72 316 72 330 76 342 C80 344 83 340 85 334 C86 324 86 312 86 304 C82 302 79 302 76 304 Z',
  MuscleHead.calfInner: 'M86 304 C86 312 86 324 85 334 C87 342 91 346 95 342 C98 330 98 316 94 304 C91 302 89 302 86 304 Z',
  MuscleHead.soleus: 'M76 343 C76 353 79 362 83 369 L93 369 C95 361 96 351 95 343 C91 347 87 343 85 335 C83 341 80 345 76 343 Z',
};

// ---------------------------------------------------------------- whole muscles

const _frontMuscles = <Muscle, List<String>>{
  Muscle.traps: [_trapsFront],
  Muscle.chest: ['M99 80 L75 78 C72 84 70 89 69 95 C68 101 67 106 66 110 C70 116 76 120 84 121 C90 121 95 120 99 119 Z'],
  Muscle.frontDelts: [_frontDelt],
  Muscle.sideDelts: [_sideDelt],
  Muscle.biceps: [
    'M48 114 C44 128 44 142 47 152 C49 154 51 155 53 155 C55 155 56 153 57 150 C60 140 61 126 60 114 C58 112.5 56 112 54 112 C52 112 50 113 48 114 Z',
    _brachialis,
  ],
  Muscle.forearms: ['M42 161 C38 172 36 184 35 196 L40 198 C39 204 39 209 40 213 L46 213 C49 200 53 182 58 163 C55 160 52 160 50 162 Z'],
  Muscle.abs: ['M100 123 L89 124 C87 132 87 142 87 152 C87 165 88 178 92 188 C95 191 98 192 100 192 Z'],
  Muscle.obliques: [_obliques],
  Muscle.quads: [
    'M70 206 C66 232 67 262 73 290 C78 293 84 292 88 288 C91 292 94 292 96 290 C98 276 97 260 93 252 '
        'C91 238 89 222 87 209 C84 206 81 206 78 207 Z',
  ],
  Muscle.adductors: [_adductors],
  Muscle.calves: [_calfInnerFront, _soleusFront],
};

const _backMuscles = <Muscle, List<String>>{
  Muscle.traps: ['M100 54 C96 62 88 70 72 76 C74 84 79 92 86 98 C90 110 95 124 100 136 Z'],
  Muscle.rearDelts: [_frontDelt],
  Muscle.sideDelts: [_sideDelt],
  Muscle.upperBack: [_infraspinatus, _teres, _rhomboids],
  Muscle.lats: [
    'M67 120 C68 130 70 142 74 152 C78 164 84 176 91 184 C93 170 95 150 96 128 L91 126 C88 120 85 114 84 110 C78 115 73 118 67 120 Z',
  ],
  Muscle.lowerBack: [_erectors],
  Muscle.triceps: [
    'M47 112 C43 124 42 138 44 150 C44 156 45 160 47 162 L55 162 C56 158 56 155 56 152 C60 140 62 126 62 114 C58 111 55 111 52 112 Z',
  ],
  Muscle.forearms: [_extensors],
  Muscle.glutes: [
    'M73 192 C69 196 67 202 68 210 C70 207 72 205 75 205 C72 214 74 226 80 232 C88 236 96 234 100 230 L100 197 C92 191 82 189 73 192 Z',
  ],
  Muscle.hamstrings: [
    'M75 238 C71 256 72 274 76 290 C79 292 82 291 84 288 C87 291 91 291 94 288 C97 272 98 254 97 238 C93 235 89 235 86 237 C82 236 78 236 75 238 Z',
  ],
  Muscle.calves: [
    'M76 304 C72 316 72 330 76 342 C76 353 79 362 83 369 L93 369 C95 361 96 351 95 343 C98 330 98 316 94 304 C91 302 89 302 86 304 C82 302 79 302 76 304 Z',
  ],
};

// ---------------------------------------------------------------- paths

/// Reads SVG path data made of absolute M, L, C and Z commands.
Path svgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLCZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = '';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final t = tokens[i];
    if (t == 'M' || t == 'L' || t == 'C' || t == 'Z') {
      cmd = t;
      i++;
      if (cmd == 'Z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        path.moveTo(next(), next());
        cmd = 'L'; // more pairs after M are lines
      case 'L':
        path.lineTo(next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      default:
        i++; // unknown: skip
    }
  }
  return path;
}

/// The left-half shape as the right half too (x -> 200 - x).
final _mirror = Float64List.fromList([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 200, 0, 0, 1]);

Path _both(Path half) => Path()
  ..addPath(half, Offset.zero)
  ..addPath(half.transform(_mirror), Offset.zero);

Path _halfOf(List<String> parts) {
  final p = Path();
  for (final d in parts) {
    p.addPath(svgPath(d), Offset.zero);
  }
  return p;
}

final Path _silhouette = _both(svgPath(_outline))
  ..addOval(Rect.fromCircle(center: const Offset(100, 33), radius: 17));

final Map<MuscleHead, Path> _frontHeadHalves = {for (final e in _frontHeads.entries) e.key: svgPath(e.value)};
final Map<MuscleHead, Path> _backHeadHalves = {for (final e in _backHeads.entries) e.key: svgPath(e.value)};
final Map<Muscle, Path> _frontMuscleHalves = {for (final e in _frontMuscles.entries) e.key: _halfOf(e.value)};
final Map<Muscle, Path> _backMuscleHalves = {for (final e in _backMuscles.entries) e.key: _halfOf(e.value)};

final Map<MuscleHead, Path> _frontHeadPaths = {for (final e in _frontHeadHalves.entries) e.key: _both(e.value)};
final Map<MuscleHead, Path> _backHeadPaths = {for (final e in _backHeadHalves.entries) e.key: _both(e.value)};
final Map<Muscle, Path> _frontMusclePaths = {for (final e in _frontMuscleHalves.entries) e.key: _both(e.value)};
final Map<Muscle, Path> _backMusclePaths = {for (final e in _backMuscleHalves.entries) e.key: _both(e.value)};

/// The muscles shown on each side.
Iterable<Muscle> musclesOnSide({required bool back}) => (back ? _backMuscles : _frontMuscles).keys;

/// The heads shown on each side.
Iterable<MuscleHead> headsOnSide({required bool back}) => (back ? _backHeads : _frontHeads).keys;

/// The colour for a heat level (0 untrained ... 4 for 20+ sets), from the theme.
Color heatColor(AppColors c, int level) =>
    level <= 0 ? c.line : Color.lerp(c.line, c.accent, const [0.3, 0.55, 0.8, 1.0][(level - 1).clamp(0, 3)])!;

// The drawing's frame inside the 200 x 400 grid (the figure, cropped).
const _left = 20.0;
const _top = 14.0;
const _w = 160.0;
const _h = 382.0;

/// A body figure, front or back, each muscle shaded by its sets.
class MuscleMap extends StatelessWidget {
  const MuscleMap({
    super.key,
    required this.sets,
    this.back = false,
    this.selected,
    this.onTap,
    this.width = 200,
  });

  final Map<Muscle, double> sets;
  final bool back;
  final Muscle? selected;
  final ValueChanged<Muscle>? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final shapes = back ? _backMusclePaths : _frontMusclePaths;
    final halves = back ? _backMuscleHalves : _frontMuscleHalves;
    final trained = [
      for (final m in shapes.keys)
        if ((sets[m] ?? 0) > 0) '${m.label} ${setsText(sets[m]!)}',
    ];
    return _BodyMap<Muscle>(
      label: '${back ? 'Back' : 'Front'} muscles. ${trained.isEmpty ? 'None trained.' : trained.join(', ')}',
      shapes: shapes,
      halves: halves,
      level: (m) => heatLevel(sets[m] ?? 0),
      selected: selected,
      onTap: onTap,
      width: width,
      repaintKey: sets,
    );
  }
}

/// The advanced map: each muscle head shaded by its sets.
class HeadMap extends StatelessWidget {
  const HeadMap({
    super.key,
    required this.sets,
    this.back = false,
    this.selected,
    this.onTap,
    this.width = 200,
  });

  final Map<MuscleHead, double> sets;
  final bool back;
  final MuscleHead? selected;
  final ValueChanged<MuscleHead>? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final shapes = back ? _backHeadPaths : _frontHeadPaths;
    final halves = back ? _backHeadHalves : _frontHeadHalves;
    final trained = [
      for (final h in shapes.keys)
        if ((sets[h] ?? 0) > 0) '${h.label} ${setsText(sets[h]!)}',
    ];
    return _BodyMap<MuscleHead>(
      label: '${back ? 'Back' : 'Front'} muscle heads. ${trained.isEmpty ? 'None trained.' : trained.join(', ')}',
      shapes: shapes,
      halves: halves,
      level: (h) => heatLevel(sets[h] ?? 0),
      selected: selected,
      onTap: onTap,
      width: width,
      repaintKey: sets,
    );
  }
}

class _BodyMap<T> extends StatelessWidget {
  const _BodyMap({
    super.key,
    required this.label,
    required this.shapes,
    required this.halves,
    required this.level,
    required this.selected,
    required this.onTap,
    required this.width,
    required this.repaintKey,
  });

  final String label;
  final Map<T, Path> shapes;
  final Map<T, Path> halves;
  final int Function(T) level;
  final T? selected;
  final ValueChanged<T>? onTap;
  final double width;
  final Object repaintKey;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final k = width / _w;
    return Semantics(
      label: label,
      child: GestureDetector(
        onTapUp: onTap == null
            ? null
            : (d) {
                var p = d.localPosition / k + const Offset(_left, _top);
                // The right half is the left half mirrored.
                if (p.dx > 100) p = Offset(200 - p.dx, p.dy);
                for (final e in halves.entries.toList().reversed) {
                  if (e.value.contains(p)) {
                    onTap!(e.key);
                    return;
                  }
                }
              },
        child: CustomPaint(
          size: Size(width, width * _h / _w),
          painter: _MapPainter<T>(
            shapes: shapes,
            colors: {for (final key in shapes.keys) key: heatColor(c, level(key))},
            selected: selected,
            c: c,
            repaintKey: repaintKey,
          ),
        ),
      ),
    );
  }
}

class _MapPainter<T> extends CustomPainter {
  _MapPainter({required this.shapes, required this.colors, required this.selected, required this.c, required this.repaintKey});

  final Map<T, Path> shapes;
  final Map<T, Color> colors;
  final T? selected;
  final AppColors c;
  final Object repaintKey;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _w;
    canvas.save();
    canvas.scale(k);
    canvas.translate(-_left, -_top);
    canvas.drawPath(_silhouette, Paint()..color = c.chip);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      // Grid units (the canvas is scaled): thicker on small maps so the
      // outlines still show.
      ..strokeWidth = k < 0.6 ? 1.6 : 0.9
      ..color = c.surface;
    for (final e in shapes.entries) {
      canvas.drawPath(e.value, Paint()..color = colors[e.key]!);
      canvas.drawPath(e.value, edge);
    }
    final sel = selected;
    if (sel != null && shapes[sel] != null) {
      canvas.drawPath(
        shapes[sel]!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2
          ..color = c.text,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter<T> old) =>
      old.repaintKey != repaintKey || old.selected != selected || old.c != c || old.shapes != shapes;
}
