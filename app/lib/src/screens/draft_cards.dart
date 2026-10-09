import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/log_parser.dart';
import '../ai/matcher.dart';
import '../ai/paste_parser.dart';
import '../ai/plan_intents.dart';
import '../calc/calc.dart';
import '../data/models.dart';
import '../data/muscles.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'exercise_library_screen.dart';
import 'food_library.dart';

Future<double?> _askNumber(BuildContext context, String title, double? start, String suffix) async {
  final c = AppColors.of(context);
  final ctrl = TextEditingController(text: start == null ? '' : oneDecimal(start));
  final v = await showDialog<double>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(title),
      content: NumberBox(controller: ctrl, suffix: suffix, semanticLabel: title, onChanged: (_) {}),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(d).pop(parseNumber(ctrl.text)),
          style: TextButton.styleFrom(foregroundColor: c.accent),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 400), ctrl.dispose);
  return v;
}

Widget _cardShell(AppColors c, {required String title, required List<Widget> children}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: c.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title.toUpperCase(),
            style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
        const SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

Widget _nameField(AppColors c, TextEditingController ctrl, String label) {
  return Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
    child: TextField(
      controller: ctrl,
      cursorColor: c.accent,
      textCapitalization: TextCapitalization.sentences,
      style: AppText.body(c).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: label),
    ),
  );
}

Widget _saved(AppColors c, String text) => Row(
      children: [
        Icon(Icons.check_circle_rounded, color: c.accent, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600))),
      ],
    );

Widget _saveButton(String label, bool enabled, VoidCallback onTap) => Opacity(
      opacity: enabled ? 1 : 0.4,
      child: IgnorePointer(ignoring: !enabled, child: SmallButton(label: label, onTap: onTap)),
    );

// ------------------------------------------------------------------ recipe

class _IngRow {
  _IngRow(this.line, this.foodId, this.grams);
  final IngredientLine line;
  String? foodId;
  double? grams;
}

class RecipeDraftCard extends StatefulWidget {
  const RecipeDraftCard({super.key, required this.draft, this.savedAs, this.onSaved});

  final RecipeDraft draft;

  /// Set once saved, so the card stays "Saved" when Chat is reopened.
  final String? savedAs;
  final ValueChanged<String>? onSaved;

  @override
  State<RecipeDraftCard> createState() => _RecipeDraftCardState();
}

class _RecipeDraftCardState extends State<RecipeDraftCard> {
  late final TextEditingController _name = TextEditingController(text: widget.draft.name);
  late double _servings = widget.draft.servings;
  List<_IngRow>? _rows;
  String? _savedName;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<_IngRow> _match(AppState s) {
    final foods = [for (final f in s.foods) if (!f.archived) f];
    return [
      for (final l in widget.draft.ingredients)
        () {
          final f = bestMatch<Food>(l.name, foods, (f) => foodMainName(f.name));
          return _IngRow(l, f?.id, f == null ? null : _gramsFor(l, f));
        }(),
    ];
  }

  double? _gramsFor(IngredientLine l, Food f) => gramsFor(
        l,
        foodName: f.name,
        gramsPerItem: (f.gramsPerItem ?? 0) > 0 ? f.gramsPerItem : f.servingGrams,
      );

  Future<void> _choose(AppState s, _IngRow r) async {
    final id = await FoodPickerScreen.pick(context);
    if (id == null || !mounted) return;
    final f = s.food(id);
    if (f == null) return;
    setState(() {
      r.foodId = id;
      r.grams = _gramsFor(r.line, f) ?? r.grams;
    });
    if (r.grams == null) await _editGrams(r);
  }

  Future<void> _editGrams(_IngRow r) async {
    final v = await _askNumber(context, 'Grams of ${r.line.name}', r.grams, 'g');
    if (v != null && v > 0 && mounted) setState(() => r.grams = v);
  }

  void _save(AppState s, List<_IngRow> rows) {
    final name = _name.text.trim().isEmpty ? 'Pasted recipe' : _name.text.trim();
    final steps = widget.draft.steps;
    s.saveRecipe(Recipe(
      id: newId('r'),
      name: name,
      servings: _servings <= 0 ? 1 : _servings,
      items: [for (final r in rows) RecipeItem(foodId: r.foodId!, grams: r.grams!)],
      note: steps.isEmpty ? null : [for (var i = 0; i < steps.length; i++) '${i + 1}. ${steps[i]}'].join('\n'),
    ));
    HapticFeedback.mediumImpact();
    widget.onSaved?.call(name);
    setState(() => _savedName = name);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final rows = _rows ??= _match(s);
    final saved = _savedName ?? widget.savedAs;
    if (saved != null) {
      return _cardShell(c, title: 'Recipe', children: [_saved(c, 'Saved "$saved" to Food > Recipes.')]);
    }
    final ready = rows.isNotEmpty && rows.every((r) => r.foodId != null && (r.grams ?? 0) > 0);
    return _cardShell(c, title: 'Recipe draft', children: [
      _nameField(c, _name, 'Recipe name'),
      const SizedBox(height: 8),
      Row(
        children: [
          Text('Servings', style: AppText.body(c)),
          const Spacer(),
          IconButton(
            tooltip: 'Fewer servings',
            onPressed: _servings > 1 ? () => setState(() => _servings -= 1) : null,
            icon: Icon(Icons.remove_rounded, color: c.muted),
          ),
          Text(oneDecimal(_servings), style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'More servings',
            onPressed: () => setState(() => _servings += 1),
            icon: Icon(Icons.add_rounded, color: c.muted),
          ),
        ],
      ),
      for (final r in rows)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.line.raw, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.quiet(c).copyWith(fontSize: 12)),
                    if (r.foodId != null)
                      GestureDetector(
                        onTap: () => _choose(s, r),
                        child: Text(s.food(r.foodId!)?.name ?? '?',
                            style: AppText.body(c).copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                      )
                    else
                      GestureDetector(
                        onTap: () => _choose(s, r),
                        child: Text('No match: choose a food',
                            style: AppText.body(c).copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: c.protein)),
                      ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => r.foodId == null ? _choose(s, r) : _editGrams(r),
                style: TextButton.styleFrom(foregroundColor: c.accent, minimumSize: const Size(48, 40)),
                child: Text(r.foodId == null ? 'Choose' : (r.grams == null ? 'Grams?' : '${r.grams!.round()} g')),
              ),
              IconButton(
                tooltip: 'Remove ${r.line.name}',
                onPressed: () => setState(() => rows.remove(r)),
                icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
              ),
            ],
          ),
        ),
      if (widget.draft.skipped.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Left out (no amount): ${widget.draft.skipped.join('; ')}',
              style: AppText.quiet(c).copyWith(fontSize: 12)),
        ),
      if (widget.draft.steps.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${widget.draft.steps.length} steps are kept in the recipe\'s note.',
              style: AppText.quiet(c).copyWith(fontSize: 12)),
        ),
      const SizedBox(height: 10),
      _saveButton('Save recipe', ready, () => _save(s, rows)),
      if (!ready && rows.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Choose a food and grams for each line (or remove it) to save.',
              style: AppText.quiet(c).copyWith(fontSize: 12)),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ workout

class _ExRow {
  _ExRow(this.line, this.exerciseId);
  final ExerciseLine line;
  String? exerciseId;
}

class WorkoutDraftCard extends StatefulWidget {
  const WorkoutDraftCard({super.key, required this.draft, this.savedAs, this.onSaved});

  final WorkoutDraft draft;

  /// Set once saved, so the card stays "Saved" when Chat is reopened.
  final String? savedAs;
  final ValueChanged<String>? onSaved;

  @override
  State<WorkoutDraftCard> createState() => _WorkoutDraftCardState();
}

class _WorkoutDraftCardState extends State<WorkoutDraftCard> {
  late final TextEditingController _name = TextEditingController(text: widget.draft.name);
  List<_ExRow>? _rows;
  String? _savedName;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<_ExRow> _match(AppState s) {
    final list = [for (final e in s.exercises) if (!e.archived) e];
    return [
      for (final l in widget.draft.items)
        _ExRow(l, bestMatch<Exercise>(exerciseKey(l.name), list, (e) => exerciseKey(e.name))?.id),
    ];
  }

  /// Sets for a line: its own, else the title's "(2 sets each)", else 3
  /// (1 for timed cardio).
  int _sets(ExerciseLine l) => l.sets ?? (l.minutes != null ? 1 : (widget.draft.defaultSets ?? 3));

  /// Set types by position, from "set 2: partials" ("last set" = the last).
  List<String> _types(ExerciseLine l) {
    final n = _sets(l);
    final out = List.filled(n, '');
    for (final e in l.setTypes.entries) {
      final i = e.key == 0 ? n - 1 : e.key - 1;
      if (i >= 0 && i < n) out[i] = e.value;
    }
    return out;
  }

  /// Makes a new exercise for a line nothing matched, with a best guess at
  /// its muscles (fine-tune them in the exercise editor).
  void _create(AppState s, _ExRow r) {
    final guess = guessMuscles(r.line.name);
    final name = r.line.name.trim();
    final e = Exercise(
      id: newId('x'),
      name: name.isEmpty ? 'New exercise' : name[0].toUpperCase() + name.substring(1),
      muscle: guess == null ? 'Chest' : groupFor(guess),
      custom: true,
      primaryMuscles: [for (final m in guess?.primary ?? const <Muscle>[]) m.name],
      secondaryMuscles: [for (final m in guess?.secondary ?? const <Muscle>[]) m.name],
    );
    s.saveExercise(e);
    HapticFeedback.selectionClick();
    setState(() => r.exerciseId = e.id);
  }

  Future<void> _choose(_ExRow r) async {
    final id = await ExerciseLibraryScreen.pick(context);
    if (id != null && mounted) setState(() => r.exerciseId = id);
  }

  String _detail(_ExRow r, bool imperial) {
    final l = r.line;
    final parts = <String>[];
    if (l.minutes == null || l.repsLow != null) {
      final reps = l.repsLow == null
          ? ''
          : (l.repsHigh != null && l.repsHigh != l.repsLow ? ' × ${l.repsLow}–${l.repsHigh}' : ' × ${l.repsLow}');
      parts.add('${_sets(l)} sets$reps');
    }
    if (l.minutes != null) parts.add('${l.minutes} min');
    final kg = l.loadKg(imperial: imperial);
    if (kg != null) parts.add(imperial ? '${kgToLb(kg).round()} lb' : '${oneDecimal(kg)} kg');
    if (l.restSec != null) parts.add('rest ${l.restSec! ~/ 60}:${(l.restSec! % 60).toString().padLeft(2, '0')}');
    final types = _types(l);
    for (var i = 0; i < types.length; i++) {
      if (types[i].isNotEmpty) parts.add('set ${i + 1}: ${setTypeByName(types[i]).label.toLowerCase()}');
    }
    return parts.join(' · ');
  }

  void _save(AppState s, List<_ExRow> rows) {
    final imperial = s.settings.units == Units.imperial;
    final name = _name.text.trim().isEmpty ? 'Pasted workout' : _name.text.trim();
    s.saveWorkout(Workout(
      id: newId('w'),
      name: name,
      items: [
        for (final r in rows)
          WorkoutItem(
            exerciseId: r.exerciseId!,
            sets: _sets(r.line),
            repsLow: r.line.repsLow ?? 8,
            repsHigh: r.line.repsHigh ?? r.line.repsLow ?? 10,
            loadKg: r.line.loadKg(imperial: imperial),
            restSec: r.line.restSec ?? 90,
            targetMin: r.line.minutes,
            note: r.line.note,
            setTypes: _types(r.line),
          ),
      ],
      sort: s.workouts.length,
      note: widget.draft.note,
    ));
    HapticFeedback.mediumImpact();
    widget.onSaved?.call(name);
    setState(() => _savedName = name);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final rows = _rows ??= _match(s);
    final saved = _savedName ?? widget.savedAs;
    if (saved != null) {
      return _cardShell(c, title: 'Workout', children: [_saved(c, 'Saved "$saved" to Plan > Workouts.')]);
    }
    final ready = rows.isNotEmpty && rows.every((r) => r.exerciseId != null);
    return _cardShell(c, title: 'Workout draft', children: [
      _nameField(c, _name, 'Workout name'),
      const SizedBox(height: 4),
      for (final r in rows)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _choose(r),
                      child: Text(
                        r.exerciseId == null ? 'No match: choose an exercise' : (s.exercise(r.exerciseId!)?.name ?? '?'),
                        style: AppText.body(c).copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: r.exerciseId == null ? c.protein : null,
                        ),
                      ),
                    ),
                    Text('${r.line.name} · ${_detail(r, imperial)}',
                        maxLines: 3, overflow: TextOverflow.ellipsis, style: AppText.quiet(c).copyWith(fontSize: 12)),
                    if (r.line.note != null)
                      Text(r.line.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.quiet(c).copyWith(fontSize: 12, fontStyle: FontStyle.italic)),
                    if (r.exerciseId == null)
                      Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => _choose(r),
                            style: TextButton.styleFrom(foregroundColor: c.accent, padding: EdgeInsets.zero),
                            child: const Text('Choose'),
                          ),
                          TextButton(
                            key: ValueKey('create-${r.line.name}'),
                            onPressed: () => _create(s, r),
                            style: TextButton.styleFrom(foregroundColor: c.accent, padding: EdgeInsets.zero),
                            child: Text('Create "${r.line.name}"'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove ${r.line.name}',
                onPressed: () => setState(() => rows.remove(r)),
                icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
              ),
            ],
          ),
        ),
      if (widget.draft.note != null)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(10)),
          child: Text(widget.draft.note!, style: AppText.body(c).copyWith(fontSize: 13)),
        ),
      if (widget.draft.skipped.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Not read: ${widget.draft.skipped.join('; ')}', style: AppText.quiet(c).copyWith(fontSize: 12)),
        ),
      const SizedBox(height: 10),
      _saveButton('Save workout', ready, () => _save(s, rows)),
      if (!ready && rows.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Choose or create an exercise for each line (or remove it) to save.',
              style: AppText.quiet(c).copyWith(fontSize: 12)),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ typed logs

Meal _mealFor(String? name, DateTime now) {
  for (final m in Meal.values) {
    if (m.name == name) return m;
  }
  final h = now.hour;
  if (h < 11) return Meal.breakfast;
  if (h < 15) return Meal.lunch;
  if (h < 21) return Meal.dinner;
  return Meal.snack;
}

/// A weigh-in, a night's sleep or some food, typed in Chat: check, then save.
class LogDraftCard extends StatefulWidget {
  const LogDraftCard({super.key, required this.intent, this.savedAs, this.onSaved});

  final LogIntent intent;
  final String? savedAs;
  final ValueChanged<String>? onSaved;

  @override
  State<LogDraftCard> createState() => _LogDraftCardState();
}

class _LogDraftCardState extends State<LogDraftCard> {
  String? _savedText;
  late Meal _meal = _mealFor(widget.intent is FoodIntent ? (widget.intent as FoodIntent).meal : null, DateTime.now());
  late int? _quality = widget.intent is SleepIntent ? (widget.intent as SleepIntent).quality : null;
  List<_IngRow>? _rows;

  DateTime get _day {
    final t = dateOnly(DateTime.now());
    return DateTime(t.year, t.month, t.day - widget.intent.daysAgo);
  }

  String get _dayLabel => widget.intent.daysAgo == 0 ? 'today' : 'yesterday';

  void _done(String text) {
    HapticFeedback.mediumImpact();
    widget.onSaved?.call(text);
    setState(() => _savedText = text);
  }

  // ---- food rows, matched like a recipe; no amount means one item or serving
  double? _gramsFor(IngredientLine l, Food f) {
    final each = (f.gramsPerItem ?? 0) > 0 ? f.gramsPerItem : f.servingGrams;
    if (l.qty == null) return each;
    return gramsFor(l, foodName: f.name, gramsPerItem: each);
  }

  List<_IngRow> _match(AppState s, FoodIntent i) {
    final foods = [for (final f in s.foods) if (!f.archived) f];
    return [
      for (final l in i.items)
        () {
          final f = bestMatch<Food>(l.name, foods, (f) => foodMainName(f.name));
          return _IngRow(l, f?.id, f == null ? null : _gramsFor(l, f));
        }(),
    ];
  }

  Future<void> _choose(AppState s, _IngRow r) async {
    final id = await FoodPickerScreen.pick(context);
    if (id == null || !mounted) return;
    final f = s.food(id);
    if (f == null) return;
    setState(() {
      r.foodId = id;
      r.grams = _gramsFor(r.line, f) ?? r.grams;
    });
    if (r.grams == null) await _editGrams(r);
  }

  Future<void> _editGrams(_IngRow r) async {
    final v = await _askNumber(context, 'Grams of ${r.line.name}', r.grams, 'g');
    if (v != null && v > 0 && mounted) setState(() => r.grams = v);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final saved = _savedText ?? widget.savedAs;
    if (saved != null) return _cardShell(c, title: 'Logged', children: [_saved(c, saved)]);
    final imperial = s.settings.units == Units.imperial;
    switch (widget.intent) {
      case WeightIntent(:final value, :final unit):
        final lb = unit == 'lb' || (unit == null && imperial);
        final kg = lb ? lbToKg(value) : value;
        final shown = '${oneDecimal(value)} ${lb ? 'lb' : 'kg'}';
        final earlierWeight = s.weighInOn(_day);
        return _cardShell(c, title: 'Weigh-in', children: [
          Text('$shown, $_dayLabel', style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
          if (earlierWeight != null)
            Text('Replaces ${imperial ? '${oneDecimal(kgToLb(earlierWeight.weightKg))} lb' : '${oneDecimal(earlierWeight.weightKg)} kg'} logged $_dayLabel.',
                style: AppText.quiet(c).copyWith(fontSize: 12)),
          const SizedBox(height: 10),
          _saveButton('Save weigh-in', true, () {
            s.logWeight(kg, day: _day);
            _done('Weigh-in saved: $shown, $_dayLabel.');
          }),
        ]);
      case SleepIntent(:final minutes):
        final night = widget.intent.daysAgo == 0 ? 'last night' : 'the night before';
        final hours = '${oneDecimal(minutes / 60)} h';
        final earlierSleep = s.sleepOn(_day);
        return _cardShell(c, title: 'Sleep', children: [
          Text('$hours, $night', style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
          if (earlierSleep?.durationMin != null)
            Text('Replaces ${oneDecimal(earlierSleep!.durationMin! / 60)} h logged for $night.', style: AppText.quiet(c).copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          Text('Quality', style: AppText.quiet(c).copyWith(fontSize: 13)),
          const SizedBox(height: 4),
          Segmented<int>(
            label: 'Sleep quality',
            options: const [(1, '1'), (2, '2'), (3, '3'), (4, '4'), (5, '5')],
            value: _quality ?? 0,
            onChanged: (v) => setState(() => _quality = v),
          ),
          const SizedBox(height: 10),
          _saveButton('Save sleep', true, () {
            s.logSleep(SleepEntry(date: _day, durationMin: minutes, quality: _quality ?? earlierSleep?.quality));
            _done('Sleep saved: $hours, $night${_quality == null ? '' : ', quality $_quality'}.');
          }),
        ]);
      case WaterIntent(:final ml):
        final amount = formatWater(ml, imperial: imperial);
        return _cardShell(c, title: 'Water', children: [
          Text('$amount, $_dayLabel', style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
          Text('${formatWater(s.waterOn(_day), imperial: imperial)} so far $_dayLabel, goal ${formatWater(s.waterGoalMl, imperial: imperial)}.',
              style: AppText.quiet(c).copyWith(fontSize: 12)),
          const SizedBox(height: 10),
          _saveButton('Save water', true, () {
            s.addWater(ml, day: _day);
            _done('Water saved: $amount, $_dayLabel.');
          }),
        ]);
      case FoodIntent():
        final i = widget.intent as FoodIntent;
        final rows = _rows ??= _match(s, i);
        final ready = rows.isNotEmpty && rows.every((r) => r.foodId != null && (r.grams ?? 0) > 0);
        return _cardShell(c, title: 'Food, $_dayLabel', children: [
          Segmented<Meal>(
            label: 'Meal',
            options: [for (final m in Meal.values) (m, m.label)],
            value: _meal,
            onChanged: (v) => setState(() => _meal = v),
          ),
          const SizedBox(height: 4),
          for (final r in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.line.raw, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.quiet(c).copyWith(fontSize: 12)),
                        GestureDetector(
                          onTap: () => _choose(s, r),
                          child: Text(
                            r.foodId == null ? 'No match: choose a food' : (s.food(r.foodId!)?.name ?? '?'),
                            style: AppText.body(c).copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: r.foodId == null ? c.protein : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => r.foodId == null ? _choose(s, r) : _editGrams(r),
                    style: TextButton.styleFrom(foregroundColor: c.accent, minimumSize: const Size(48, 40)),
                    child: Text(r.foodId == null ? 'Choose' : (r.grams == null ? 'Grams?' : '${r.grams!.round()} g')),
                  ),
                  IconButton(
                    tooltip: 'Remove ${r.line.name}',
                    onPressed: () => setState(() => rows.remove(r)),
                    icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          _saveButton('Save to ${_meal.label}', ready, () {
            var kcal = 0.0;
            for (final r in rows) {
              final f = s.food(r.foodId!)!;
              s.logFood(_day, _meal, f, r.grams!);
              kcal += macrosForGrams(f.per100, r.grams!).kcal;
            }
            _done('Logged ${rows.length} ${rows.length == 1 ? 'item' : 'items'} to ${_meal.label} $_dayLabel, about ${kcal.round()} kcal.');
          }),
          if (!ready && rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Choose a food and grams for each line (or remove it) to save.', style: AppText.quiet(c).copyWith(fontSize: 12)),
            ),
        ]);
    }
  }
}

// ------------------------------------------------------------------ planning

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dayName(DateTime day, int daysAhead) => switch (daysAhead) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => '${_weekdayShort[day.weekday - 1]}, ${shortDate(day)}',
    };

/// For a sentence: "today", "tomorrow", "on Fri, Oct 9".
String _dayPhrase(DateTime day, int daysAhead) =>
    daysAhead <= 1 ? _dayName(day, daysAhead).toLowerCase() : 'on ${_dayName(day, daysAhead)}';

/// A workout or a meal to put on a day: pick the day, check, then plan it.
class PlanDraftCard extends StatefulWidget {
  const PlanDraftCard({super.key, required this.intent, this.savedAs, this.onSaved});

  final PlanIntent intent;
  final String? savedAs;
  final ValueChanged<String>? onSaved;

  @override
  State<PlanDraftCard> createState() => _PlanDraftCardState();
}

class _PlanDraftCardState extends State<PlanDraftCard> {
  late int _ahead = widget.intent.daysAhead.clamp(0, 365);
  String? _savedText;
  String? _workoutId;
  bool _matched = false;
  late Meal _meal = () {
    final i = widget.intent;
    for (final m in Meal.values) {
      if (i is PlanMealIntent && m.name == i.meal) return m;
    }
    return Meal.lunch;
  }();
  String? _recipeId;
  List<_IngRow>? _rows;

  DateTime get _day {
    final t = dateOnly(DateTime.now());
    return DateTime(t.year, t.month, t.day + _ahead);
  }

  void _done(String text) {
    HapticFeedback.mediumImpact();
    widget.onSaved?.call(text);
    setState(() => _savedText = text);
  }

  double? _gramsFor(IngredientLine l, Food f) {
    final each = (f.gramsPerItem ?? 0) > 0 ? f.gramsPerItem : f.servingGrams;
    if (l.qty == null) return each;
    return gramsFor(l, foodName: f.name, gramsPerItem: each);
  }

  Future<void> _choose(AppState s, _IngRow r) async {
    final id = await FoodPickerScreen.pick(context);
    if (id == null || !mounted) return;
    final f = s.food(id);
    if (f == null) return;
    setState(() {
      r.foodId = id;
      r.grams = _gramsFor(r.line, f) ?? r.grams;
    });
    if (r.grams == null) {
      final v = await _askNumber(context, 'Grams of ${r.line.name}', r.grams, 'g');
      if (v != null && v > 0 && mounted) setState(() => r.grams = v);
    }
  }

  /// Picks a food and its grams and adds it to the meal.
  Future<void> _addFood(AppState s) async {
    final id = await FoodPickerScreen.pick(context);
    if (id == null || !mounted) return;
    final f = s.food(id);
    if (f == null) return;
    final start = (f.servingGrams ?? 0) > 0 ? f.servingGrams : ((f.gramsPerItem ?? 0) > 0 ? f.gramsPerItem : 100.0);
    final grams = await _askNumber(context, 'Grams of ${f.name}', start, 'g');
    if (grams == null || grams <= 0 || !mounted) return;
    setState(() => (_rows ??= []).add(_IngRow(IngredientLine(raw: f.name, name: f.name), id, grams)));
  }

  Widget _dayRow(AppColors c) => Row(
        children: [
          IconButton(
            tooltip: 'Day before',
            onPressed: _ahead > 0 ? () => setState(() => _ahead--) : null,
            icon: Icon(Icons.chevron_left_rounded, color: c.muted),
          ),
          Expanded(
            child: Text(_dayName(_day, _ahead),
                textAlign: TextAlign.center, style: AppText.body(c).copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Day after',
            onPressed: () => setState(() => _ahead++),
            icon: Icon(Icons.chevron_right_rounded, color: c.muted),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final saved = _savedText ?? widget.savedAs;
    if (saved != null) return _cardShell(c, title: 'Planned', children: [_saved(c, saved)]);
    switch (widget.intent) {
      case PlanWorkoutIntent(:final name):
        final workouts = [...s.workouts]..sort((a, b) => a.sort.compareTo(b.sort));
        if (!_matched) {
          _matched = true;
          _workoutId = bestMatch<Workout>(name, workouts, (w) => w.name, threshold: 0.5)?.id;
        }
        if (workouts.isEmpty) {
          return _cardShell(c, title: 'Plan a workout', children: [
            Text('There are no workouts yet. Make one in Plan > Workouts (or paste one here), then try again.',
                style: AppText.body(c).copyWith(fontSize: 14)),
          ]);
        }
        return _cardShell(c, title: 'Plan a workout', children: [
          _dayRow(c),
          DropdownButton<String>(
            isExpanded: true,
            value: _workoutId,
            hint: Text('Choose a workout (no match for "$name")', style: AppText.quiet(c)),
            dropdownColor: c.surface,
            items: [
              for (final w in workouts) DropdownMenuItem(value: w.id, child: Text(w.name, style: AppText.body(c))),
            ],
            onChanged: (v) => setState(() => _workoutId = v),
          ),
          const SizedBox(height: 10),
          _saveButton('Plan it', _workoutId != null, () {
            final w = s.workoutById(_workoutId);
            if (w == null) return;
            s.schedule(w.id, _day);
            _done('Planned ${w.name} ${_ahead <= 1 ? 'for ' : ''}${_dayPhrase(_day, _ahead)}.');
          }),
        ]);
      case PlanMealIntent(:final items, :final recipe):
        if (!_matched) {
          _matched = true;
          if (recipe != null) {
            _recipeId = bestMatch<Recipe>(recipe, s.recipes, (x) => x.name, threshold: 0.5)?.id;
          }
          if (_recipeId == null) {
            final foods = [for (final f in s.foods) if (!f.archived) f];
            _rows = [
              for (final l in items)
                () {
                  final f = bestMatch<Food>(l.name, foods, (f) => foodMainName(f.name));
                  return _IngRow(l, f?.id, f == null ? null : _gramsFor(l, f));
                }(),
            ];
          }
        }
        final r = _recipeId == null ? null : s.recipe(_recipeId!);
        final rows = _rows ?? <_IngRow>[];
        final ready = r != null || (rows.isNotEmpty && rows.every((x) => x.foodId != null && (x.grams ?? 0) > 0));
        return _cardShell(c, title: 'Plan a meal', children: [
          _dayRow(c),
          Segmented<Meal>(
            label: 'Meal',
            options: [for (final m in Meal.values) (m, m.label)],
            value: _meal,
            onChanged: (v) => setState(() => _meal = v),
          ),
          const SizedBox(height: 6),
          if (r != null)
            Text('${r.name} (1 serving)', style: AppText.body(c).copyWith(fontSize: 15, fontWeight: FontWeight.w600))
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                recipe == null ? 'No foods yet. Add what you\'d like to eat.' : 'No recipe called "$recipe". Add foods instead.',
                style: AppText.quiet(c).copyWith(fontSize: 14),
              ),
            )
          else
            for (final row in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _choose(s, row),
                        child: Text(
                          row.foodId == null ? 'No match for "${row.line.name}": choose a food' : (s.food(row.foodId!)?.name ?? '?'),
                          style: AppText.body(c).copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: row.foodId == null ? c.protein : null,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        if (row.foodId == null) return _choose(s, row);
                        final v = await _askNumber(context, 'Grams of ${row.line.name}', row.grams, 'g');
                        if (v != null && v > 0 && mounted) setState(() => row.grams = v);
                      },
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      child: Text(row.foodId == null ? 'Choose' : (row.grams == null ? 'Grams?' : '${row.grams!.round()} g')),
                    ),
                    IconButton(
                      tooltip: 'Remove ${row.line.name}',
                      onPressed: () => setState(() => rows.remove(row)),
                      icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                    ),
                  ],
                ),
              ),
          if (r == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('plan-add-food'),
                onPressed: () => _addFood(s),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add a food'),
              ),
            ),
          const SizedBox(height: 6),
          _saveButton('Plan it', ready, () {
            final when = _dayPhrase(_day, _ahead);
            if (r != null) {
              s.planMeal(_day, _meal, 'recipe', r.id, 1);
              _done('Planned ${r.name} for ${_meal.label.toLowerCase()} $when.');
              return;
            }
            for (final row in rows) {
              s.planMeal(_day, _meal, 'food', row.foodId!, row.grams!);
            }
            _done('Planned ${rows.length} ${rows.length == 1 ? 'food' : 'foods'} for ${_meal.label.toLowerCase()} $when.');
          }),
        ]);
    }
  }
}

// ------------------------------------------------------------------ actions

/// An action the AI prepared ("Delete lunch, yesterday"): exactly what will
/// change, then Confirm or Cancel. Nothing changes until Confirm.
class ActionCard extends StatefulWidget {
  const ActionCard({
    super.key,
    required this.title,
    required this.lines,
    required this.confirmLabel,
    required this.onConfirm,
    this.warning,
    this.onUndo,
    this.savedAs,
    this.onSaved,
  });

  final String title;
  final List<String> lines;
  final String confirmLabel;

  /// Does it; returns what to say ("Deleted 2 items.").
  final String Function() onConfirm;
  final String? warning;
  final VoidCallback? onUndo;
  final String? savedAs;
  final ValueChanged<String>? onSaved;

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  String? _done;
  bool _undone = false;

  void _finish(String text) {
    widget.onSaved?.call(text);
    setState(() => _done = text);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final done = _done ?? widget.savedAs;
    if (done != null) {
      return _cardShell(c, title: widget.title, children: [
        _saved(c, _undone ? 'Undone.' : done),
        if (widget.onUndo != null && !_undone && _done != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                widget.onUndo!();
                widget.onSaved?.call('Undone.');
                setState(() => _undone = true);
              },
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: const Text('Undo'),
            ),
          ),
      ]);
    }
    return _cardShell(c, title: widget.title, children: [
      for (final l in widget.lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(l, style: AppText.body(c).copyWith(fontSize: 14)),
        ),
      if (widget.warning != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(widget.warning!, style: AppText.quiet(c).copyWith(fontSize: 12, color: c.protein)),
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          TextButton(
            onPressed: () => _finish('Canceled. Nothing changed.'),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _saveButton(widget.confirmLabel, true, () {
              HapticFeedback.mediumImpact();
              _finish(widget.onConfirm());
            }),
          ),
        ],
      ),
    ]);
  }
}
