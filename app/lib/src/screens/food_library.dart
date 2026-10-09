import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'barcode_food.dart';
import 'food_search_results.dart';
import 'food_share_screen.dart';

/// Price for display: per lb or per kg for weight foods, per item otherwise.
String priceText(AppState s, Food f, double price) {
  if (f.byItem) return '\$${price.toStringAsFixed(2)} each';
  final imperial = s.settings.units == Units.imperial;
  final shown = imperial ? price * kgPerLb : price;
  return '\$${shown.toStringAsFixed(2)}/${imperial ? 'lb' : 'kg'}';
}

class FoodsView extends StatefulWidget {
  const FoodsView({super.key});

  @override
  State<FoodsView> createState() => _FoodsViewState();
}

class _FoodsViewState extends State<FoodsView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final q = _search.text.trim().toLowerCase();
    final foods = [
      for (final f in s.foods)
        if (!f.archived && (q.isEmpty || f.name.toLowerCase().contains(q))) f,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.surface,
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
                          hintText: 'Search foods',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Add by barcode',
              onPressed: () async {
                final s = AppScope.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final before = s.foods.length;
                final id = await scanFoodBarcode(context);
                if (id == null) return;
                final f = s.food(id);
                if (f == null) return;
                messenger.showSnackBar(SnackBar(
                  content: Text(s.foods.length > before ? 'Added ${f.name} to your foods.' : '${f.name} is already in your foods.'),
                ));
              },
              icon: Icon(Icons.qr_code_scanner_rounded, color: c.accent),
            ),
            SmallButton(label: 'New', onTap: () => Navigator.of(context).push(FoodEditorScreen.route())),
          ],
        ),
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
        Text(
          'Starter foods use typical values per 100 g. Check labels and edit '
          'any that differ. Prices are per store, set in each food.',
          style: AppText.quiet(c).copyWith(fontSize: 12),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              for (var i = 0; i < foods.length; i++)
                InkWell(
                  onTap: () => Navigator.of(context).push(FoodEditorScreen.route(foods[i])),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 56),
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
                              Text(foods[i].name, style: AppText.body(c)),
                              Text(
                                '${foods[i].per100.kcal.round()} kcal · '
                                '${oneDecimal(foods[i].per100.protein)} g protein per 100 g'
                                '${foods[i].prices.isEmpty ? '' : ' · ${foods[i].prices.length} prices'}',
                                style: AppText.quiet(c).copyWith(fontSize: 12),
                              ),
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
        FoodSearchResults(
          query: _search.text,
          onFood: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${f.name} is in your foods.'))),
        ),
      ],
    );
  }
}

class FoodEditorScreen extends StatefulWidget {
  const FoodEditorScreen({super.key, this.food});

  final Food? food;

  static Route<void> route([Food? f]) =>
      MaterialPageRoute<void>(builder: (_) => FoodEditorScreen(food: f));

  @override
  State<FoodEditorScreen> createState() => _FoodEditorScreenState();
}

class _FoodEditorScreenState extends State<FoodEditorScreen> {
  late final _name = TextEditingController(text: widget.food?.name ?? '');
  late final _kcal = TextEditingController(text: _n(widget.food?.per100.kcal));
  late final _protein = TextEditingController(text: _n(widget.food?.per100.protein));
  late final _carbs = TextEditingController(text: _n(widget.food?.per100.carbs));
  late final _fat = TextEditingController(text: _n(widget.food?.per100.fat));
  late bool _byItem = widget.food?.byItem ?? false;
  late final _each = TextEditingController(text: _n(widget.food?.gramsPerItem));
  final Map<String, TextEditingController> _prices = {};
  bool _filled = false;
  bool _imperial = true;

  static String _n(double? v) => v == null ? '' : oneDecimal(v);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final s = AppScope.of(context);
    _imperial = s.settings.units == Units.imperial;
    for (final st in s.stores) {
      final p = widget.food?.prices[st.id];
      String text = '';
      if (p != null) {
        final shown = (widget.food?.byItem ?? false) ? p : (_imperial ? p * kgPerLb : p);
        text = shown.toStringAsFixed(2);
      }
      _prices[st.id] = TextEditingController(text: text);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _kcal, _protein, _carbs, _fat, _each, ..._prices.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save(AppState s, {bool hide = false}) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the food a name.')));
      return;
    }
    final each = parseNumber(_each.text);
    final prices = <String, double>{};
    for (final entry in _prices.entries) {
      final v = parseNumber(entry.value.text);
      if (v == null || v <= 0) continue;
      prices[entry.key] = _byItem ? v : (_imperial ? v / kgPerLb : v);
    }
    final per100 = Macros(
      kcal: parseNumber(_kcal.text) ?? 0,
      protein: parseNumber(_protein.text) ?? 0,
      carbs: parseNumber(_carbs.text) ?? 0,
      fat: parseNumber(_fat.text) ?? 0,
    );
    final existing = widget.food;
    s.saveFood(existing == null
        ? Food(
            id: newId('f'),
            name: name,
            per100: per100,
            byItem: _byItem && each != null && each > 0,
            gramsPerItem: each,
            prices: prices,
            custom: true,
          )
        : existing.copyWith(
            name: name,
            per100: per100,
            byItem: _byItem && each != null && each > 0,
            gramsPerItem: each,
            prices: prices,
            archived: hide,
          ));
    Navigator.of(context).pop();
  }

  Widget _text(AppColors c, TextEditingController ctrl, String hint) => Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: c.surface,
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

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final unit = _imperial ? 'lb' : 'kg';

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
                    widget.food == null ? 'New food' : 'Edit food',
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
                  _text(c, _name, 'e.g. Chicken breast, raw'),
                  const SizedBox(height: 16),
                  Text('Per 100 g', style: AppText.label(c)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: NumberBox(controller: _kcal, suffix: 'kcal', semanticLabel: 'Calories per 100 g', onChanged: (_) {})),
                      const SizedBox(width: 8),
                      Expanded(child: NumberBox(controller: _protein, suffix: 'g protein', semanticLabel: 'Protein per 100 g', onChanged: (_) {})),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: NumberBox(controller: _carbs, suffix: 'g carbs', semanticLabel: 'Carbs per 100 g', onChanged: (_) {})),
                      const SizedBox(width: 8),
                      Expanded(child: NumberBox(controller: _fat, suffix: 'g fat', semanticLabel: 'Fat per 100 g', onChanged: (_) {})),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Labels usually list a serving: divide by the serving\'s grams, '
                    'then multiply by 100.',
                    style: AppText.quiet(c).copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  SettingRow(
                    label: 'Counted by the item',
                    note: 'Eggs, bananas: log "2" instead of grams',
                    trailing: Toggle(
                      label: 'Counted by the item',
                      value: _byItem,
                      onChanged: (v) => setState(() => _byItem = v),
                    ),
                  ),
                  if (_byItem)
                    NumberBox(
                      controller: _each,
                      suffix: 'g each',
                      semanticLabel: 'Grams per item',
                      hint: 'e.g. 50',
                      onChanged: (_) {},
                    ),
                  const SizedBox(height: 18),
                  Text('Prices', style: AppText.label(c)),
                  const SizedBox(height: 8),
                  if (s.stores.isEmpty)
                    Text(
                      'Add your stores in Settings > Groceries, then set what this costs at each.',
                      style: AppText.quiet(c),
                    )
                  else
                    for (final st in s.stores) ...[
                      Row(
                        children: [
                          Expanded(child: Text(st.name, style: AppText.body(c))),
                          SizedBox(
                            width: 150,
                            child: NumberBox(
                              controller: _prices[st.id] ??= TextEditingController(),
                              suffix: _byItem ? '\$ each' : '\$/$unit',
                              semanticLabel: 'Price at ${st.name}',
                              onChanged: (_) {},
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  if (widget.food != null) ...[
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () => _save(s, hide: true),
                      style: TextButton.styleFrom(foregroundColor: c.protein),
                      child: const Text('Hide this food'),
                    ),
                    Text(
                      'Hidden foods leave the list and pickers. Past logs and recipes keep working.',
                      style: AppText.quiet(c).copyWith(fontSize: 12),
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

/// Pick a food (returns its id).
class FoodPickerScreen extends StatefulWidget {
  const FoodPickerScreen({super.key});

  static Future<String?> pick(BuildContext context) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const FoodPickerScreen()),
      );

  @override
  State<FoodPickerScreen> createState() => _FoodPickerScreenState();
}

class _FoodPickerScreenState extends State<FoodPickerScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final q = _search.text.trim().toLowerCase();
    final foods = [
      for (final f in s.foods)
        if (!f.archived && (q.isEmpty || f.name.toLowerCase().contains(q))) f,
    ]; // (favourites go first, below)
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
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
                  Expanded(child: Text('Pick a food', style: AppText.title(c).copyWith(fontSize: 22))),
                  SmallButton(
                    label: 'New',
                    quiet: true,
                    onTap: () => Navigator.of(context).push(FoodEditorScreen.route()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.surface,
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
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        cursorColor: c.accent,
                        style: AppText.body(c),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search foods',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  for (final f in [...foods.where((f) => f.favorite), ...foods.where((f) => !f.favorite)])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.name, style: AppText.body(c)),
                      subtitle: Text(
                        '${f.per100.kcal.round()} kcal · ${oneDecimal(f.per100.protein)} g protein per 100 g',
                        style: AppText.quiet(c).copyWith(fontSize: 12),
                      ),
                      onTap: () => Navigator.of(context).pop(f.id),
                      trailing: IconButton(
                        tooltip: f.favorite ? 'Remove from favorites' : 'Add to favorites',
                        onPressed: () => s.setFavorite(f, !f.favorite),
                        icon: Icon(f.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: f.favorite ? c.accent : c.muted),
                      ),
                    ),
                  FoodSearchResults(query: _search.text, onFood: (f) => Navigator.of(context).pop(f.id)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
