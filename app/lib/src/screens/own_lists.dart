import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../calc/grocery.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'barcode_food.dart';
import 'food_library.dart';

String _money(double v) => '\$${v.toStringAsFixed(2)}';

Widget _header(BuildContext context, String title) {
  final c = AppColors.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_rounded, color: c.text),
        ),
        Expanded(child: Text(title, style: AppText.title(c).copyWith(fontSize: 22))),
      ],
    ),
  );
}

Widget _tickBox(AppColors c, bool done) => AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: done ? c.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: done ? c.accent : c.muted, width: 2),
      ),
      child: done ? Icon(Icons.check_rounded, size: 16, color: c.onAccent) : null,
    );

/// A plain checklist: type anything.
class CustomChecklistScreen extends StatefulWidget {
  const CustomChecklistScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const CustomChecklistScreen());

  @override
  State<CustomChecklistScreen> createState() => _CustomChecklistScreenState();
}

class _CustomChecklistScreenState extends State<CustomChecklistScreen> {
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  void _add(AppState s) {
    final t = _new.text.trim();
    if (t.isEmpty) return;
    s.addGroceryText(t);
    _new.clear();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final items = s.customGroceries;
    final ticked = items.where((g) => g.done).length;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, 'My checklist'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        key: const ValueKey('checklist-new'),
                        controller: _new,
                        onSubmitted: (_) => _add(s),
                        textCapitalization: TextCapitalization.sentences,
                        cursorColor: c.accent,
                        style: AppText.body(c).copyWith(fontSize: 16),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Add an item',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SmallButton(label: 'Add', onTap: () => _add(s)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Anything goes: paper towels, coffee, a birthday cake.',
                        textAlign: TextAlign.center,
                        style: AppText.quiet(c),
                      ),
                    ),
                  for (final g in items)
                    Container(
                      constraints: const BoxConstraints(minHeight: 50),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              button: true,
                              checked: g.done,
                              label: g.label,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => s.saveGroceryItem(g.copyWith(done: !g.done)),
                                child: ExcludeSemantics(
                                  child: Row(
                                    children: [
                                      _tickBox(c, g.done),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          g.label,
                                          style: AppText.body(c).copyWith(
                                            color: g.done ? c.muted : c.text,
                                            decoration: g.done ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove ${g.label}',
                            onPressed: () {
                              s.deleteGroceryItem(g);
                              showUndo(context, 'Removed ${g.label}.', () => s.saveGroceryItem(g));
                            },
                            icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  if (ticked > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          final gone = s.clearDoneGroceries(foods: false);
                          showUndo(context, 'Cleared ${gone.length} ticked.', () {
                            for (final g in gone) {
                              s.saveGroceryItem(g);
                            }
                          });
                        },
                        style: TextButton.styleFrom(foregroundColor: c.accent),
                        child: Text('Clear $ticked ticked'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Foods from your list, priced at one store you pick.
class FoodListScreen extends StatelessWidget {
  const FoodListScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const FoodListScreen());

  /// One step on the quantity buttons, in grams.
  static double step(Food f, bool imperial) {
    final each = f.gramsPerItem ?? 0;
    if (f.byItem && each > 0) return each;
    return imperial ? lbToKg(0.5) * 1000 : 250;
  }

  static String qty(Food f, double grams, bool imperial) {
    final each = f.gramsPerItem ?? 0;
    if (f.byItem && each > 0) {
      final n = itemsToBuy(f, grams);
      return '$n';
    }
    return imperial ? '${oneDecimal(kgToLb(grams / 1000))} lb' : '${oneDecimal(grams / 1000)} kg';
  }

  Future<void> _addFood(BuildContext context, AppState s) async {
    final id = await FoodPickerScreen.pick(context);
    if (id == null) return;
    final f = s.food(id);
    if (f == null) return;
    s.addGroceryFood(f, step(f, s.settings.units == Units.imperial) * (f.byItem ? 1 : 2));
  }

  Future<void> _scanFood(BuildContext context, AppState s) async {
    final id = await scanFoodBarcode(context);
    if (id == null) return;
    final f = s.food(id);
    if (f == null) return;
    s.addGroceryFood(f, step(f, s.settings.units == Units.imperial) * (f.byItem ? 1 : 2));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final stores = s.stores;
    final chosen = stores.any((x) => x.id == s.settings.ownListStore)
        ? s.settings.ownListStore
        : (stores.isEmpty ? null : stores.first.id);
    final items = s.foodGroceries;
    var total = 0.0;
    var unpriced = 0;
    for (final g in items) {
      final f = s.food(g.foodId ?? '');
      final cost = f == null || chosen == null ? null : groceryCost(f, g.amount ?? 0, chosen);
      if (cost == null) {
        unpriced++;
      } else {
        total += cost;
      }
    }
    String storeName(String? id) {
      for (final x in stores) {
        if (x.id == id) return x.name;
      }
      return 'your store';
    }

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, 'From your foods'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Text('Store', style: AppText.label(c)),
                  const SizedBox(height: 8),
                  if (stores.isEmpty)
                    Text('Add your stores in Settings > Groceries to see prices here.', style: AppText.quiet(c))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final st in stores)
                          Semantics(
                            button: true,
                            selected: st.id == chosen,
                            label: st.name,
                            child: GestureDetector(
                              onTap: () => s.setSettings(s.settings.copyWith(ownListStore: st.id)),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                height: 40,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: st.id == chosen ? c.accent : c.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: st.id == chosen ? c.accent : c.line),
                                ),
                                child: Text(
                                  st.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: st.id == chosen ? c.onAccent : c.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      children: [
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text('Add foods from your food list.', style: AppText.quiet(c)),
                          ),
                        for (var i = 0; i < items.length; i++)
                          Builder(builder: (context) {
                            final g = items[i];
                            final f = s.food(g.foodId ?? '');
                            final grams = g.amount ?? 0;
                            final cost = f == null || chosen == null ? null : groceryCost(f, grams, chosen);
                            return Container(
                              constraints: const BoxConstraints(minHeight: 60),
                              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: c.line))),
                              child: Row(
                                children: [
                                  Semantics(
                                    button: true,
                                    checked: g.done,
                                    label: 'In cart: ${g.label}',
                                    child: GestureDetector(
                                      onTap: () => s.saveGroceryItem(g.copyWith(done: !g.done)),
                                      child: _tickBox(c, g.done),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          g.label,
                                          style: AppText.body(c).copyWith(
                                            fontSize: 14,
                                            color: g.done ? c.muted : c.text,
                                            decoration: g.done ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                        Text(
                                          cost == null ? 'No price at ${storeName(chosen)}' : _money(cost),
                                          style: AppText.quiet(c).copyWith(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (f != null) ...[
                                    IconButton(
                                      tooltip: 'Less ${g.label}',
                                      onPressed: () {
                                        final next = grams - step(f, imperial);
                                        if (next <= 0) {
                                          s.deleteGroceryItem(g);
                                          showUndo(context, 'Removed ${g.label}.', () => s.saveGroceryItem(g));
                                        } else {
                                          s.saveGroceryItem(g.copyWith(amount: next));
                                        }
                                      },
                                      icon: Icon(Icons.remove_circle_outline_rounded, color: c.muted),
                                    ),
                                    SizedBox(
                                      width: 54,
                                      child: Text(
                                        qty(f, grams, imperial),
                                        textAlign: TextAlign.center,
                                        style: AppText.body(c).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'More ${g.label}',
                                      onPressed: () => s.saveGroceryItem(g.copyWith(amount: grams + step(f, imperial))),
                                      icon: Icon(Icons.add_circle_rounded, color: c.accent),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: SmallButton(label: 'Add a food', quiet: true, onTap: () => _addFood(context, s))),
                      const SizedBox(width: 8),
                      Expanded(child: SmallButton(label: 'Scan', quiet: true, onTap: () => _scanFood(context, s))),
                    ],
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: Text('Total at ${storeName(chosen)}', style: AppText.quiet(c).copyWith(fontSize: 14))),
                        Text(_money(total), style: AppText.title(c).copyWith(fontSize: 24)),
                      ],
                    ),
                    if (unpriced > 0)
                      Text(
                        '$unpriced ${unpriced == 1 ? 'item has' : 'items have'} no price here, so the total leaves '
                        '${unpriced == 1 ? 'it' : 'them'} out.',
                        style: AppText.quiet(c).copyWith(fontSize: 12),
                      ),
                    if (items.any((g) => g.done))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            final gone = s.clearDoneGroceries(foods: true);
                            showUndo(context, 'Cleared ${gone.length} ticked.', () {
                              for (final g in gone) {
                                s.saveGroceryItem(g);
                              }
                            });
                          },
                          style: TextButton.styleFrom(foregroundColor: c.accent),
                          child: const Text('Clear ticked'),
                        ),
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
