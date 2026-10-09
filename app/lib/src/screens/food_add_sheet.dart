import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'barcode_food.dart';
import 'food_search_results.dart';

/// Pick something to log, then say how much.
class FoodAddSheet extends StatefulWidget {
  const FoodAddSheet({super.key, required this.day, required this.meal, this.plan = false});

  final DateTime day;
  final Meal meal;

  /// Adds to the meal plan instead of the food log.
  final bool plan;

  static Future<void> open(BuildContext context, DateTime day, Meal meal, {bool plan = false}) {
    final c = AppColors.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FoodAddSheet(day: day, meal: meal, plan: plan),
    );
  }

  @override
  State<FoodAddSheet> createState() => _FoodAddSheetState();
}

class _FoodAddSheetState extends State<FoodAddSheet> {
  late Meal _meal = widget.meal;
  int _tab = 0; // 0 recent, 1 foods, 2 recipes, 3 quick
  final _search = TextEditingController();

  // Amount step
  Food? _food;
  Recipe? _recipe;
  bool _items = true;
  final _amount = TextEditingController();

  // Quick add
  final _qName = TextEditingController();
  final _qKcal = TextEditingController();
  final _qProtein = TextEditingController();
  final _qCarbs = TextEditingController();
  final _qFat = TextEditingController();

  @override
  void dispose() {
    for (final c in [_search, _amount, _qName, _qKcal, _qProtein, _qCarbs, _qFat]) {
      c.dispose();
    }
    super.dispose();
  }

  /// A unit besides grams for [f]: items (foods bought by the item) or
  /// servings (from a package label). Null if only grams make sense.
  static (double, String)? unitFor(Food f) {
    final each = f.gramsPerItem ?? 0;
    if (f.byItem && each > 0) return (each, 'item');
    final serving = f.servingGrams ?? 0;
    if (serving > 0) return (serving, 'serving');
    return null;
  }

  void _pickFood(Food f) {
    setState(() {
      _food = f;
      _recipe = null;
      _items = unitFor(f) != null;
      _amount.text = _items ? '1' : '100';
    });
  }

  Future<void> _scan() async {
    final id = await scanFoodBarcode(context);
    if (id == null || !mounted) return;
    final f = AppScope.of(context).food(id);
    if (f != null) _pickFood(f);
  }

  void _pickRecipe(Recipe r) {
    setState(() {
      _recipe = r;
      _food = null;
      _amount.text = '1';
    });
  }

  double? _grams() {
    final v = parseNumber(_amount.text);
    final f = _food;
    if (v == null || v <= 0 || f == null) return null;
    final unit = unitFor(f);
    return _items && unit != null ? v * unit.$1 : v;
  }

  Macros? _preview(AppState s) {
    final f = _food;
    final r = _recipe;
    if (f != null) {
      final g = _grams();
      return g == null ? null : macrosForGrams(f.per100, g);
    }
    if (r != null) {
      final v = parseNumber(_amount.text);
      return v == null || v <= 0 ? null : s.recipePerServing(r).scale(v);
    }
    return null;
  }

  void _done(String name) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.plan
            ? 'Planned $name for ${_meal.label}, ${shortDate(widget.day)}.'
            : 'Added $name to ${_meal.label}.'),
      ),
    );
  }

  void _logPicked(AppState s) {
    final f = _food;
    final r = _recipe;
    if (f != null) {
      final g = _grams();
      if (g == null) return;
      if (widget.plan) {
        s.planMeal(widget.day, _meal, 'food', f.id, g);
      } else {
        s.logFood(widget.day, _meal, f, g);
      }
      _done(f.name);
    } else if (r != null) {
      final v = parseNumber(_amount.text);
      if (v == null || v <= 0) return;
      if (widget.plan) {
        s.planMeal(widget.day, _meal, 'recipe', r.id, v);
      } else {
        s.logRecipe(widget.day, _meal, r, v);
      }
      _done(r.name);
    }
  }

  void _logQuick(AppState s) {
    final kcal = parseNumber(_qKcal.text);
    if (kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least the calories.')),
      );
      return;
    }
    s.logQuick(
      widget.day,
      _meal,
      _qName.text,
      Macros(
        kcal: kcal,
        protein: parseNumber(_qProtein.text) ?? 0,
        carbs: parseNumber(_qCarbs.text) ?? 0,
        fat: parseNumber(_qFat.text) ?? 0,
      ),
    );
    _done(_qName.text.trim().isEmpty ? 'Quick add' : _qName.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final height = MediaQuery.of(context).size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: (_food != null || _recipe != null) ? _amountStep(s, c) : _pickStep(s, c),
        ),
      ),
    );
  }

  Widget _mealPicker() => Segmented<Meal>(
        label: 'Meal',
        options: [for (final m in Meal.values) (m, m.label)],
        value: _meal,
        onChanged: (v) => setState(() => _meal = v),
      );

  Widget _pickStep(AppState s, AppColors c) {
    final q = _search.text.trim().toLowerCase();
    Widget list;
    if (_tab == 3) {
      list = ListView(
        children: [
          const FieldLabel('Name (optional)'),
          _textBox(c, _qName, 'e.g. Coffee with milk'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: NumberBox(controller: _qKcal, suffix: 'kcal', semanticLabel: 'Calories', onChanged: (_) {})),
              const SizedBox(width: 8),
              Expanded(child: NumberBox(controller: _qProtein, suffix: 'g protein', semanticLabel: 'Protein', onChanged: (_) {})),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: NumberBox(controller: _qCarbs, suffix: 'g carbs', semanticLabel: 'Carbs', onChanged: (_) {})),
              const SizedBox(width: 8),
              Expanded(child: NumberBox(controller: _qFat, suffix: 'g fat', semanticLabel: 'Fat', onChanged: (_) {})),
            ],
          ),
          const SizedBox(height: 16),
          SmallButton(label: 'Add to ${_meal.label}', onTap: () => _logQuick(s)),
        ],
      );
    } else if (_tab == 0) {
      final recent = s.recentPicks;
      final favorites = s.favoriteFoods;
      list = recent.isEmpty && favorites.isEmpty
          ? Center(
              child: Text(
                'Foods and recipes you log show up here for one-tap adding.',
                textAlign: TextAlign.center,
                style: AppText.quiet(c),
              ),
            )
          : ListView(
              children: [
                if (favorites.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text('FAVORITES', style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
                  ),
                  for (final f in favorites)
                    _row(
                      c,
                      f.name,
                      '${f.per100.kcal.round()} kcal · ${oneDecimal(f.per100.protein)} g protein per 100 g',
                      () => _pickFood(f),
                      trailing: _star(s, c, f),
                    ),
                  if (recent.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 2),
                      child: Text('RECENT', style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
                    ),
                ],
                for (final e in recent)
                  _row(
                    c,
                    e.name,
                    e.kind == 'recipe' ? 'Recipe' : 'Food',
                    () {
                      if (e.kind == 'recipe') {
                        final r = s.recipe(e.refId ?? '');
                        if (r != null) _pickRecipe(r);
                      } else {
                        final f = s.food(e.refId ?? '');
                        if (f != null) _pickFood(f);
                      }
                    },
                  ),
              ],
            );
    } else if (_tab == 1) {
      final foods = [
        for (final f in s.foods)
          if (!f.archived && (q.isEmpty || f.name.toLowerCase().contains(q))) f,
      ]; // (favourites go first, below)
      final ordered = [...foods.where((f) => f.favorite), ...foods.where((f) => !f.favorite)];
      list = ListView(
        children: [
          for (final f in ordered)
            _row(
              c,
              f.name,
              '${f.per100.kcal.round()} kcal · ${oneDecimal(f.per100.protein)} g protein per 100 g',
              () => _pickFood(f),
              trailing: _star(s, c, f),
            ),
          FoodSearchResults(query: _search.text, onFood: _pickFood),
        ],
      );
    } else {
      final recipes = [
        for (final r in s.recipes)
          if (q.isEmpty || r.name.toLowerCase().contains(q)) r,
      ];
      list = recipes.isEmpty
          ? Center(
              child: Text('No recipes yet. Make one in Food > Recipes.', style: AppText.quiet(c)),
            )
          : ListView(
              children: [
                for (final r in recipes)
                  _row(
                    c,
                    r.name,
                    () {
                      final m = s.recipePerServing(r);
                      return '${m.kcal.round()} kcal · ${m.protein.round()} g protein per serving';
                    }(),
                    () => _pickRecipe(r),
                  ),
              ],
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.plan ? 'Plan for ${shortDate(widget.day)}' : 'Add food',
          style: AppText.title(c).copyWith(fontSize: 22),
        ),
        const SizedBox(height: 12),
        _mealPicker(),
        const SizedBox(height: 10),
        SmallButton(label: 'Scan barcode', quiet: true, onTap: _scan),
        const SizedBox(height: 10),
        Segmented<int>(
          label: 'Add from',
          options: [
            (0, 'Recent'),
            (1, 'Foods'),
            (2, 'Recipes'),
            if (!widget.plan) (3, 'Quick'),
          ],
          value: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
        if (_tab == 1 || _tab == 2) ...[
          const SizedBox(height: 10),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.background,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: c.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    cursorColor: c.accent,
                    style: AppText.body(c),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(child: list),
      ],
    );
  }

  Widget _textBox(AppColors c, TextEditingController ctrl, String hint) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: c.background,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: ctrl,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: c.accent,
        style: AppText.body(c).copyWith(fontSize: 16),
        decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: hint),
      ),
    );
  }

  /// A star to favourite (or un-favourite) a food.
  Widget _star(AppState s, AppColors c, Food f) => IconButton(
        tooltip: f.favorite ? 'Remove from favorites' : 'Add to favorites',
        onPressed: () => s.setFavorite(f, !f.favorite),
        icon: Icon(f.favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: f.favorite ? c.accent : c.muted),
      );

  Widget _row(AppColors c, String title, String subtitle, VoidCallback onTap, {Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppText.body(c)),
                  Text(subtitle, style: AppText.quiet(c).copyWith(fontSize: 12)),
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: c.muted),
          ],
        ),
      ),
    );
  }

  Widget _amountStep(AppState s, AppColors c) {
    final f = _food;
    final r = _recipe;
    final m = _preview(s);
    final unit = f == null ? null : unitFor(f);
    return ListView(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => setState(() {
                _food = null;
                _recipe = null;
              }),
              icon: Icon(Icons.arrow_back_rounded, color: c.text),
            ),
            Expanded(
              child: Text(
                f?.name ?? r?.name ?? '',
                style: AppText.title(c).copyWith(fontSize: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _mealPicker(),
        const SizedBox(height: 14),
        if (unit != null) ...[
          Segmented<bool>(
            label: 'Measure by',
            options: [
              (true, unit.$2 == 'item' ? 'Items (${unit.$1.round()} g each)' : 'Servings (${unit.$1.round()} g)'),
              (false, 'Grams'),
            ],
            value: _items,
            onChanged: (v) => setState(() {
              final g = _grams();
              _items = v;
              if (g != null) {
                _amount.text = v ? oneDecimal(g / unit.$1) : g.round().toString();
              }
            }),
          ),
          const SizedBox(height: 10),
        ],
        NumberBox(
          controller: _amount,
          suffix: r != null ? 'servings' : (_items && unit != null ? '${unit.$2}s' : 'g'),
          semanticLabel: 'Amount',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        SectionCard(
          child: m == null
              ? Text('Enter an amount.', style: AppText.quiet(c))
              : Row(
                  children: [
                    for (final (label, value) in [
                      ('kcal', m.kcal.round().toString()),
                      ('protein', '${m.protein.round()} g'),
                      ('carbs', '${m.carbs.round()} g'),
                      ('fat', '${m.fat.round()} g'),
                    ])
                      Expanded(
                        child: Column(
                          children: [
                            Text(value, style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w500)),
                            Text(label, style: AppText.quiet(c).copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        if (r != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The recipe makes ${oneDecimal(r.servings)} servings.',
              style: AppText.quiet(c),
            ),
          ),
        const SizedBox(height: 16),
        SmallButton(
          label: widget.plan ? 'Plan for ${_meal.label}' : 'Add to ${_meal.label}',
          onTap: () => _logPicked(s),
        ),
      ],
    );
  }
}
