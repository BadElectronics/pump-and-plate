import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'food_library.dart';
import 'food_share_screen.dart';

class RecipesView extends StatelessWidget {
  const RecipesView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        SmallButton(label: 'New recipe', onTap: () => Navigator.of(context).push(RecipeEditorScreen.route())),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(ShareFoodScreen.route()),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Share with a friend'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => importFoodShareFile(context),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Import'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (s.recipes.isEmpty)
          SectionCard(
            title: 'No recipes yet',
            child: Text(
              'Build a recipe from your foods with gram amounts, say how many '
              'servings it makes, and log it in one tap. Nutrition is worked out '
              'for you.',
              style: AppText.body(c),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                for (var i = 0; i < s.recipes.length; i++)
                  InkWell(
                    onTap: () => Navigator.of(context).push(RecipeEditorScreen.route(s.recipes[i])),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 60),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.recipes[i].name,
                                  style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
                                ),
                                Builder(builder: (context) {
                                  final m = s.recipePerServing(s.recipes[i]);
                                  return Text(
                                    '${m.kcal.round()} kcal · ${m.protein.round()} g protein per serving · '
                                    '${oneDecimal(s.recipes[i].servings)} servings',
                                    style: AppText.quiet(c).copyWith(fontSize: 12),
                                  );
                                }),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.muted),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class RecipeEditorScreen extends StatefulWidget {
  const RecipeEditorScreen({super.key, this.recipe});

  final Recipe? recipe;

  static Route<void> route([Recipe? r]) =>
      MaterialPageRoute<void>(builder: (_) => RecipeEditorScreen(recipe: r));

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  late final _name = TextEditingController(text: widget.recipe?.name ?? '');
  late final _servings = TextEditingController(
    text: oneDecimal(widget.recipe?.servings ?? 1),
  );
  late final _note = TextEditingController(text: widget.recipe?.note ?? '');
  late final List<RecipeItem> _items = [...?widget.recipe?.items];

  @override
  void dispose() {
    for (final c in [_name, _servings, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<double?> _askGrams(String foodName, double? current) async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController(text: current == null ? '' : current.round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(foodName),
        content: NumberBox(controller: ctrl, suffix: 'g', semanticLabel: 'Grams', onChanged: (_) {}),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(parseNumber(ctrl.text)),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return v == null || v <= 0 ? null : v;
  }

  Future<void> _addItem(AppState s) async {
    final id = await FoodPickerScreen.pick(context);
    if (id == null || !mounted) return;
    final f = s.food(id);
    if (f == null) return;
    final g = await _askGrams(f.name, f.byItem ? f.gramsPerItem : 100.0);
    if (g == null) return;
    setState(() => _items.add(RecipeItem(foodId: id, grams: g)));
  }

  Recipe _draft() => Recipe(
        id: widget.recipe?.id ?? 'draft',
        name: _name.text.trim(),
        servings: (parseNumber(_servings.text) ?? 1).clamp(0.25, 100).toDouble(),
        items: _items,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );

  void _save(AppState s) {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the recipe a name.')));
      return;
    }
    final d = _draft();
    final existing = widget.recipe;
    s.saveRecipe(existing == null
        ? Recipe(id: newId('r'), name: d.name, servings: d.servings, items: d.items, note: d.note)
        : existing.copyWith(name: d.name, servings: d.servings, items: d.items, note: d.note));
    Navigator.of(context).pop();
  }

  Future<void> _delete(AppState s) async {
    final r = widget.recipe;
    if (r == null) return;
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Delete ${r.name}?'),
        content: const Text('Days you already logged it keep their numbers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.protein),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    s.deleteRecipe(r);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final d = _draft();
    final total = s.recipeTotals(d);
    final per = s.recipePerServing(d);

    Widget box(TextEditingController ctrl, String hint, {int lines = 1}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: ctrl,
            onChanged: (_) => setState(() {}),
            minLines: 1,
            maxLines: lines,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: c.accent,
            style: AppText.body(c).copyWith(fontSize: 16),
            decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: hint),
          ),
        );

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 40),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back without saving',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.text),
                ),
                Expanded(
                  child: Text(
                    widget.recipe == null ? 'New recipe' : 'Edit recipe',
                    style: AppText.title(c).copyWith(fontSize: 22),
                  ),
                ),
                SmallButton(label: 'Save', onTap: () => _save(s)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  const FieldLabel('Name'),
                  box(_name, 'e.g. Chicken rice bowl'),
                  const SizedBox(height: 12),
                  const FieldLabel('Makes'),
                  NumberBox(
                    controller: _servings,
                    suffix: 'servings',
                    semanticLabel: 'Servings',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Per serving',
                    child: Row(
                      children: [
                        for (final (label, value) in [
                          ('kcal', per.kcal.round().toString()),
                          ('protein', '${per.protein.round()} g'),
                          ('carbs', '${per.carbs.round()} g'),
                          ('fat', '${per.fat.round()} g'),
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
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Whole recipe: ${thousands(total.kcal)} kcal, ${total.protein.round()} g protein.',
                      style: AppText.quiet(c).copyWith(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Ingredients', style: AppText.label(c)),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _items.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.food(_items[i].foodId)?.name ?? 'Missing food',
                              style: AppText.body(c),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final g = await _askGrams(
                                s.food(_items[i].foodId)?.name ?? 'Amount',
                                _items[i].grams,
                              );
                              if (g != null) {
                                setState(() => _items[i] = RecipeItem(foodId: _items[i].foodId, grams: g));
                              }
                            },
                            style: TextButton.styleFrom(foregroundColor: c.accent),
                            child: Text('${_items[i].grams.round()} g'),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () => setState(() => _items.removeAt(i)),
                            icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  SmallButton(label: 'Add ingredient', quiet: true, onTap: () => _addItem(s)),
                  const SizedBox(height: 16),
                  const FieldLabel('Note (optional)'),
                  box(_note, 'Steps, swaps, where it\'s from', lines: 5),
                  if (widget.recipe != null) ...[
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () => _delete(s),
                      style: TextButton.styleFrom(foregroundColor: c.protein),
                      child: const Text('Delete this recipe'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
