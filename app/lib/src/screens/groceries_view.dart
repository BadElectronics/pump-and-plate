import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../calc/grocery.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'food_library.dart';
import 'own_lists.dart';

String _money(double v) => '\$${v.toStringAsFixed(2)}';

class GroceriesView extends StatefulWidget {
  const GroceriesView({super.key, this.onRecipes, this.onAddMeals});

  /// Switch to the Recipes tab.
  final VoidCallback? onRecipes;

  /// Open Plan > Calendar with the Add meals tray.
  final VoidCallback? onAddMeals;

  @override
  State<GroceriesView> createState() => _GroceriesViewState();
}

class _GroceriesViewState extends State<GroceriesView> {
  int _range = 2; // 0 this week, 1 next week, 2 next 7 days (default)

  (DateTime, DateTime) _dates() {
    final today = dateOnly(DateTime.now());
    final mon = weekStartOf(today, sundayFirst: AppScope.of(context).settings.weekStartsSunday);
    return switch (_range) {
      0 => (mon, DateTime(mon.year, mon.month, mon.day + 6)),
      1 => (DateTime(mon.year, mon.month, mon.day + 7), DateTime(mon.year, mon.month, mon.day + 13)),
      _ => (today, DateTime(today.year, today.month, today.day + 6)),
    };
  }

  String _qty(AppState s, Food f, double grams) {
    if (f.byItem && (f.gramsPerItem ?? 0) > 0) {
      final n = itemsToBuy(f, grams);
      return '$n ${n == 1 ? 'item' : 'items'}';
    }
    if (s.settings.units == Units.imperial) {
      final lb = kgToLb(grams / 1000);
      if (lb >= 1) return '${lb.toStringAsFixed(lb >= 10 ? 0 : 1)} lb';
      return '${(lb * 16).toStringAsFixed(1)} oz';
    }
    return grams >= 1000 ? '${(grams / 1000).toStringAsFixed(2)} kg' : '${grams.round()} g';
  }

  Widget _step(AppColors c, int n, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.accent.withAlpha(36), shape: BoxShape.circle),
            child: Text('$n', style: TextStyle(color: c.accent, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                Text(sub, style: AppText.quiet(c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Or make your own list": a free checklist, or foods priced at a store.
  Widget _ownLists(BuildContext context, AppState s, AppColors c) {
    final custom = s.customGroceries;
    final foods = s.foodGroceries;
    Widget option(IconData icon, String title, String sub, VoidCallback onTap) {
      return Semantics(
        button: true,
        label: title,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Icon(icon, color: c.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                        Text(sub, style: AppText.quiet(c).copyWith(fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.muted),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SectionCard(
      title: 'Or make your own list',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          option(
            Icons.checklist_rounded,
            'Custom checklist',
            custom.isEmpty
                ? 'Type anything: paper towels, coffee, a birthday cake'
                : '${custom.length} ${custom.length == 1 ? 'item' : 'items'}, ${custom.where((g) => g.done).length} ticked',
            () => Navigator.of(context).push(CustomChecklistScreen.route()),
          ),
          option(
            Icons.set_meal_outlined,
            'From your foods',
            foods.isEmpty
                ? 'Pick foods and a store, with prices and a total'
                : '${foods.length} ${foods.length == 1 ? 'food' : 'foods'} on your list',
            () => Navigator.of(context).push(FoodListScreen.route()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final (from, to) = _dates();
    final allNeeds = s.groceryNeeds(from, to);
    final atHome = {
      for (final e in allNeeds.entries)
        if (s.groceryMark(e.key).atHome) e.key: e.value,
    };
    final needs = {
      for (final e in allNeeds.entries)
        if (!atHome.containsKey(e.key)) e.key: e.value,
    };
    final foods = {for (final f in s.foods) f.id: f};
    final storeIds = [for (final st in s.stores) st.id];
    String storeName(String id) {
      for (final st in s.stores) {
        if (st.id == id) return st.name;
      }
      return 'Store';
    }

    final plan = cheapestPlan(
      needs: needs,
      foods: foods,
      storeIds: storeIds,
      maxStores: s.settings.maxStores,
    );

    final header = <Widget>[
      Segmented<int>(
        label: 'Which days',
        options: const [(0, 'This week'), (1, 'Next week'), (2, 'Next 7 days')],
        value: _range,
        onChanged: (v) => setState(() => _range = v),
      ),
      const SizedBox(height: 6),
      Text(
        'Meals on your calendar ${shortDate(from)} – ${shortDate(to)}.',
        style: AppText.quiet(c).copyWith(fontSize: 12),
      ),
      const SizedBox(height: 12),
    ];

    if (allNeeds.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // Meals planned for other days: let them switch the date range.
          if (s.plannedMeals.isNotEmpty) ...header,
          SectionCard(
            title: 'Let your list fill itself',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Plan meals once and the grocery list adds up every ingredient, '
                  'split across your cheapest stores.',
                  style: AppText.quiet(c).copyWith(fontSize: 14),
                ),
                const SizedBox(height: 6),
                _step(c, 1, 'Add your foods', 'In Foods, with what they cost at your stores.'),
                _step(c, 2, 'Make recipes from them', 'In Recipes, with gram amounts and servings.'),
                _step(c, 3, 'Put recipes on the calendar', 'Plan > Calendar > Add meals, then drag them onto days.'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (widget.onRecipes != null)
                      Expanded(child: SmallButton(label: 'Go to recipes', onTap: widget.onRecipes!)),
                    if (widget.onRecipes != null && widget.onAddMeals != null) const SizedBox(width: 8),
                    if (widget.onAddMeals != null)
                      Expanded(child: SmallButton(label: 'Add meals in Plan', quiet: true, onTap: widget.onAddMeals!)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ownLists(context, s, c),
        ],
      );
    }

    Widget itemRow(String foodId, double grams, {double? cost, bool home = false}) {
      final f = foods[foodId];
      final mark = s.groceryMark(foodId);
      return Container(
        constraints: const BoxConstraints(minHeight: 50),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: Row(
          children: [
            if (!home)
              Checkbox(
                value: mark.inCart,
                activeColor: c.accent,
                onChanged: (v) => s.setGroceryMark(mark.copyWith(inCart: v ?? false)),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    f?.name ?? 'Missing food',
                    style: AppText.body(c).copyWith(
                      fontSize: 14,
                      decoration: mark.inCart && !home ? TextDecoration.lineThrough : null,
                      color: mark.inCart && !home ? c.muted : c.text,
                    ),
                  ),
                  if (f != null) Text(_qty(s, f, grams), style: AppText.quiet(c).copyWith(fontSize: 12)),
                ],
              ),
            ),
            if (cost != null) Text(_money(cost), style: AppText.body(c).copyWith(fontSize: 14)),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, size: 18, color: c.muted),
              color: c.surface,
              onSelected: (v) {
                if (v == 'home') s.setGroceryMark(mark.copyWith(atHome: !mark.atHome, inCart: false));
                if (v == 'prices' && f != null) Navigator.of(context).push(FoodEditorScreen.route(f));
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'home',
                  child: Text(mark.atHome ? 'Need to buy it after all' : 'I have this at home'),
                ),
                const PopupMenuItem(value: 'prices', child: Text('Edit prices')),
              ],
            ),
          ],
        ),
      );
    }

    final body = <Widget>[...header];

    if (s.stores.isEmpty) {
      body.add(SectionCard(
        title: 'Add your stores',
        child: Text(
          'Add the stores you shop at in Settings > Groceries, then set prices on your '
          'foods (Food > Foods). Until then, here\'s the list without prices.',
          style: AppText.body(c),
        ),
      ));
      body.add(const SizedBox(height: 12));
    }

    if (plan != null) {
      // Single-store totals for comparison.
      final singles = <(String, double, int)>[];
      for (final st in storeIds) {
        final p = cheapestPlan(needs: needs, foods: foods, storeIds: [st], maxStores: 1);
        if (p != null) singles.add((st, p.total, p.missing.length));
      }
      final fullSingles = [
        for (final x in singles)
          if (x.$3 == plan.missing.length) x,
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      final bestSingle = fullSingles.isEmpty ? null : fullSingles.first;
      final saves = bestSingle == null ? 0.0 : bestSingle.$2 - plan.total;

      body.add(Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.storeIds.isEmpty
                  ? 'No prices yet'
                  : 'Cheapest: ${plan.storeIds.map(storeName).join(' + ')}',
              style: TextStyle(color: c.background.withAlpha(190), fontSize: 13),
            ),
            Text(
              _money(plan.total),
              style: TextStyle(color: c.background, fontSize: 34, fontWeight: FontWeight.w300),
            ),
            if (bestSingle != null && plan.storeIds.length > 1 && saves >= 0.01)
              Text(
                'Saves ${_money(saves)} vs all at ${storeName(bestSingle.$1)} (${_money(bestSingle.$2)})',
                style: TextStyle(color: c.accent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            if (plan.missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${plan.missing.length} ${plan.missing.length == 1 ? 'item has' : 'items have'} no price yet, so '
                  'the total leaves them out.',
                  style: TextStyle(color: c.background.withAlpha(190), fontSize: 12),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Splits across at most ${s.settings.maxStores} '
                '${s.settings.maxStores == 1 ? 'store' : 'stores'} (change in Settings > Groceries).',
                style: TextStyle(color: c.background.withAlpha(150), fontSize: 11),
              ),
            ),
          ],
        ),
      ));
      body.add(const SizedBox(height: 14));

      for (final st in plan.storeIds) {
        final ids = [
          for (final e in needs.entries)
            if (plan.storeFor[e.key] == st) e.key,
        ]..sort((a, b) => (foods[a]?.name ?? '').compareTo(foods[b]?.name ?? ''));
        var subtotal = 0.0;
        for (final id in ids) {
          subtotal += plan.costs[id] ?? 0;
        }
        body.add(SectionCard(
          padding: const EdgeInsets.fromLTRB(12, 14, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 10, bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(storeName(st), style: AppText.label(c))),
                    Text(_money(subtotal), style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              for (final id in ids) itemRow(id, needs[id]!, cost: plan.costs[id]),
            ],
          ),
        ));
        body.add(const SizedBox(height: 12));
      }

      if (plan.missing.isNotEmpty) {
        body.add(SectionCard(
          padding: const EdgeInsets.fromLTRB(12, 14, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 6),
                child: Text('No price yet', style: AppText.label(c)),
              ),
              for (final id in plan.missing) itemRow(id, needs[id]!),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                child: Text(
                  'Use ⋮ > Edit prices to add what these cost at your stores.',
                  style: AppText.quiet(c).copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ));
        body.add(const SizedBox(height: 12));
      }

      if (singles.length > 1) {
        body.add(SectionCard(
          title: 'All at one store',
          child: Column(
            children: [
              for (final (st, total, missing) in singles..sort((a, b) => a.$2.compareTo(b.$2)))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(storeName(st), style: AppText.body(c))),
                      Text(
                        missing == 0 ? _money(total) : '${_money(total)} + $missing unpriced',
                        style: AppText.body(c),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ));
        body.add(const SizedBox(height: 12));
      }
    } else {
      // No stores: plain list.
      final ids = needs.keys.toList()
        ..sort((a, b) => (foods[a]?.name ?? '').compareTo(foods[b]?.name ?? ''));
      body.add(SectionCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final id in ids) itemRow(id, needs[id]!)],
        ),
      ));
      body.add(const SizedBox(height: 12));
    }

    if (atHome.isNotEmpty) {
      body.add(SectionCard(
        padding: const EdgeInsets.fromLTRB(12, 14, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 6),
              child: Text('Already at home', style: AppText.label(c)),
            ),
            for (final e in atHome.entries) itemRow(e.key, e.value, home: true),
          ],
        ),
      ));
      body.add(const SizedBox(height: 12));
    }

    body.add(_ownLists(context, s, c));
    body.add(const SizedBox(height: 12));
    body.add(Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: s.clearCart,
        style: TextButton.styleFrom(foregroundColor: c.accent),
        icon: const Icon(Icons.remove_done_rounded, size: 18),
        label: const Text('Start a fresh list (clear ticks and at-home)'),
      ),
    ));

    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 40), children: body);
  }
}
