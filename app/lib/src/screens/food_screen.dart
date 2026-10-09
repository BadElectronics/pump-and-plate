import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'food_add_sheet.dart';
import 'food_library.dart';
import 'groceries_view.dart';
import 'recipes_view.dart';

/// Food tab: Groceries, Recipes, Foods. (Logging food lives in Log, and
/// planning meals on the Plan calendar.)
class FoodScreen extends StatelessWidget {
  const FoodScreen({
    super.key,
    required this.section,
    required this.onSection,
    required this.onAddMeals,
  });

  final int section;
  final ValueChanged<int> onSection;

  /// Opens Plan > Calendar with the Add meals tray.
  final VoidCallback onAddMeals;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Food', style: AppText.title(c)),
                ),
                const SizedBox(height: 12),
                IconTabs(
                  label: 'Food section',
                  items: const [
                    (Icons.shopping_cart_outlined, 'Groceries'),
                    (Icons.menu_book_outlined, 'Recipes'),
                    (Icons.set_meal_outlined, 'Foods'),
                  ],
                  index: section,
                  onChanged: onSection,
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (section) {
              0 => GroceriesView(onRecipes: () => onSection(1), onAddMeals: onAddMeals),
              1 => const RecipesView(),
              _ => const FoodsView(),
            },
          ),
        ],
      ),
    );
  }
}

String amountText(AppState s, FoodEntry e) {
  final a = e.amount;
  if (a == null) return '';
  if (e.kind == 'recipe') return '${oneDecimal(a)} ${a == 1 ? 'serving' : 'servings'}';
  final f = s.food(e.refId ?? '');
  final each = f?.gramsPerItem;
  if (f != null && f.byItem && each != null && each > 0) {
    final n = a / each;
    if ((n - n.roundToDouble()).abs() < 0.05) {
      return '${n.round()} (${a.round()} g)';
    }
  }
  return '${a.round()} g';
}

class FoodLogView extends StatefulWidget {
  const FoodLogView({super.key});

  @override
  State<FoodLogView> createState() => _FoodLogViewState();
}

class _FoodLogViewState extends State<FoodLogView> {
  DateTime _day = dateOnly(DateTime.now());

  String _dayLabel() {
    final today = dateOnly(DateTime.now());
    final diff = daysBetween(today, _day);
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return longDate(_day);
  }

  void _add(Meal meal) => FoodAddSheet.open(context, _day, meal);

  Future<void> _edit(AppState s, FoodEntry e) async {
    final c = AppColors.of(context);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EntrySheet(entry: e),
    );
    if (result == 'deleted' && mounted) {
      showUndo(context, 'Removed ${e.name}.', () => s.restoreEntry(e));
    }
  }

  void _repeatMeal(AppState s, Meal meal) {
    final from = DateTime(_day.year, _day.month, _day.day - 1);
    final added = s.copyMeal(from, meal, _day, meal);
    if (added.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No ${meal.label.toLowerCase()} logged the day before.')),
      );
      return;
    }
    showUndo(context, 'Added ${added.length} ${added.length == 1 ? 'item' : 'items'} from the day before\'s ${meal.label.toLowerCase()}.', () {
      for (final e in added) {
        s.deleteEntry(e);
      }
    });
  }

  /// Copies this meal to a day and meal of your choice.
  Future<void> _copyMealTo(AppState s, Meal meal) async {
    final c = AppColors.of(context);
    var day = DateTime(_day.year, _day.month, _day.day + 1);
    var target = meal;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          backgroundColor: c.surface,
          title: Text('Copy ${meal.label.toLowerCase()}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: d,
                    initialDate: day,
                    firstDate: DateTime(_day.year - 1),
                    lastDate: DateTime(_day.year + 2),
                  );
                  if (picked != null) set(() => day = dateOnly(picked));
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(longDate(day)),
              ),
              const SizedBox(height: 8),
              Segmented<Meal>(
                label: 'Copy into',
                options: [for (final m in Meal.values) (m, m.label)],
                value: target,
                onChanged: (v) => set(() => target = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Copy')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final added = s.copyMeal(_day, meal, day, target);
    showUndo(context, 'Copied ${added.length} ${added.length == 1 ? 'item' : 'items'} to ${target.label.toLowerCase()}, ${longDate(day)}.', () {
      for (final e in added) {
        s.deleteEntry(e);
      }
    });
  }

  void _copyYesterday(AppState s) {
    final from = DateTime(_day.year, _day.month, _day.day - 1);
    final added = s.copyDay(from, _day);
    if (added.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing logged the day before to copy.')),
      );
      return;
    }
    showUndo(context, 'Copied ${added.length} items from the day before.', () {
      for (final e in added) {
        s.deleteEntry(e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final eaten = s.eatenOn(_day);
    final t = s.targets;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day - 1)),
              icon: Icon(Icons.chevron_left_rounded, color: c.text),
            ),
            Expanded(
              child: Text(
                _dayLabel(),
                textAlign: TextAlign.center,
                style: AppText.body(c).copyWith(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            IconButton(
              tooltip: 'Next day',
              onPressed: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day + 1)),
              icon: Icon(Icons.chevron_right_rounded, color: c.text),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bar(
                label: 'Calories',
                value: eaten.kcal,
                target: t?.kcal,
                unit: 'kcal',
                color: c.accent,
              ),
              const SizedBox(height: 14),
              _Bar(
                label: 'Protein',
                value: eaten.protein,
                target: t?.proteinG,
                unit: 'g',
                color: c.protein,
              ),
              const SizedBox(height: 12),
              Text(
                'Carbs ${eaten.carbs.round()} g · Fat ${eaten.fat.round()} g',
                style: AppText.quiet(c),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ..._plannedCard(s, c),
        for (final meal in Meal.values) ...[
          _mealCard(s, c, meal),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _copyYesterday(s),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            label: const Text('Copy the day before'),
          ),
        ),
      ],
    );
  }

  /// Planned items for this day that aren't logged yet, with Log all.
  List<Widget> _plannedCard(AppState s, AppColors c) {
    final open = [
      for (final p in s.plannedMealsOn(_day))
        if (!s.isPlannedLogged(p)) p,
    ];
    if (open.isEmpty) return const [];
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: c.accent.withAlpha(28),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.accent.withAlpha(90)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Planned, not logged yet',
                    style: AppText.body(c).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                SmallButton(
                  label: open.length == 1 ? 'Log it' : 'Log all ${open.length}',
                  onTap: () {
                    final made = <FoodEntry>[];
                    for (final p in open) {
                      final e = s.logPlanned(p);
                      if (e != null) made.add(e);
                    }
                    showUndo(context, 'Logged ${made.length} planned items.', () {
                      for (final e in made) {
                        s.deleteEntry(e);
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final p in open)
              InkWell(
                onTap: () {
                  final e = s.logPlanned(p);
                  if (e != null) showUndo(context, 'Logged ${e.name}.', () => s.deleteEntry(e));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline_rounded, size: 18, color: c.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${p.meal.label}: ${s.plannedName(p)}',
                          style: AppText.body(c).copyWith(fontSize: 14),
                        ),
                      ),
                      Text(
                        '${s.plannedMacros(p).kcal.round()} kcal',
                        style: AppText.quiet(c).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _mealCard(AppState s, AppColors c, Meal meal) {
    final entries = s.entriesOn(_day, meal);
    var total = Macros.zero;
    for (final e in entries) {
      total = total + e.macros;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meal.label,
                  style: AppText.body(c).copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              if (entries.isNotEmpty)
                Text(
                  '${thousands(total.kcal)} kcal · ${total.protein.round()} g',
                  style: AppText.quiet(c).copyWith(fontSize: 12),
                ),
              IconButton(
                tooltip: 'Add to ${meal.label}',
                onPressed: () => _add(meal),
                icon: Icon(Icons.add_circle_outline_rounded, color: c.accent),
              ),
              PopupMenuButton<String>(
                key: ValueKey('meal-menu-${meal.name}'),
                tooltip: '${meal.label} options',
                icon: Icon(Icons.more_vert_rounded, color: c.muted),
                color: c.surface,
                onSelected: (v) => v == 'repeat' ? _repeatMeal(s, meal) : _copyMealTo(s, meal),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'repeat', child: Text('Repeat the day before\'s ${meal.label.toLowerCase()}')),
                  if (entries.isNotEmpty)
                    PopupMenuItem(value: 'copy', child: Text('Copy ${meal.label.toLowerCase()} to...')),
                ],
              ),
            ],
          ),
          for (final e in entries)
            InkWell(
              onTap: () => _edit(s, e),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.name, style: AppText.body(c).copyWith(fontSize: 14)),
                          if (amountText(s, e).isNotEmpty)
                            Text(amountText(s, e), style: AppText.quiet(c).copyWith(fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(
                      '${e.macros.kcal.round()} · ${e.macros.protein.round()} g',
                      style: AppText.quiet(c).copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Nothing logged', style: AppText.quiet(c).copyWith(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.target,
    required this.unit,
    required this.color,
  });

  final String label;
  final double value;
  final double? target;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = target;
    final fraction = t == null || t <= 0 ? 0.0 : (value / t).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(label, style: AppText.quiet(c))),
            Text(
              thousands(value),
              style: AppText.body(c).copyWith(fontSize: 22, fontWeight: FontWeight.w500),
            ),
            Text(
              t == null ? ' $unit' : ' / ${thousands(t)} $unit',
              style: AppText.quiet(c),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            color: color,
            backgroundColor: c.chip,
          ),
        ),
        if (t != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              value <= t
                  ? '${thousands(t - value)} $unit left'
                  : '${thousands(value - t)} $unit over',
              style: AppText.quiet(c).copyWith(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// Change how much was eaten, move it to another meal, or delete it.
class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.entry});

  final FoodEntry entry;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _amount = TextEditingController(
    text: widget.entry.amount == null ? '' : oneDecimal(widget.entry.amount!),
  );
  late Meal _meal = widget.entry.meal;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final e = widget.entry;
    final quick = e.kind == 'quick';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(e.name, style: AppText.title(c).copyWith(fontSize: 22)),
            Text(
              '${e.macros.kcal.round()} kcal · ${e.macros.protein.round()} g protein · '
              '${e.macros.carbs.round()} g carbs · ${e.macros.fat.round()} g fat',
              style: AppText.quiet(c),
            ),
            const SizedBox(height: 16),
            if (!quick) ...[
              FieldLabel(e.kind == 'recipe' ? 'Servings' : 'Amount'),
              NumberBox(
                controller: _amount,
                suffix: e.kind == 'recipe' ? 'servings' : 'g',
                semanticLabel: 'Amount',
                onChanged: (_) {},
              ),
              const SizedBox(height: 14),
            ],
            const FieldLabel('Meal'),
            Segmented<Meal>(
              label: 'Meal',
              options: [for (final m in Meal.values) (m, m.label)],
              value: _meal,
              onChanged: (v) => setState(() => _meal = v),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SmallButton(
                    label: 'Delete',
                    quiet: true,
                    onTap: () {
                      s.deleteEntry(e);
                      Navigator.of(context).pop('deleted');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SmallButton(
                    label: 'Save',
                    onTap: () {
                      final v = parseNumber(_amount.text);
                      if (!quick && v != null && v > 0) {
                        s.updateEntryAmount(e, v, meal: _meal);
                      } else {
                        s.restoreEntry(e.copyWith(meal: _meal));
                      }
                      Navigator.of(context).pop('saved');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// The full food log on its own page (from the Log tab).
class FoodLogPage extends StatelessWidget {
  const FoodLogPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const FoodLogPage());

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  Text('Food log', style: AppText.title(c).copyWith(fontSize: 22)),
                ],
              ),
            ),
            const Expanded(child: FoodLogView()),
          ],
        ),
      ),
    );
  }
}
