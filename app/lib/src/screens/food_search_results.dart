import 'package:flutter/material.dart';

import '../calc/barcode.dart';
import '../data/models.dart';
import '../data/usda.dart';
import '../services/food_db.dart';
import '../services/food_lookup.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'barcode_food.dart';

/// Built-in (USDA) foods matching [query], below your own foods, and, when
/// turned on in Settings, a button to search online for branded products.
/// Picking one hands back a food in your library.
class FoodSearchResults extends StatefulWidget {
  const FoodSearchResults({super.key, required this.query, required this.onFood});

  final String query;
  final ValueChanged<Food> onFood;

  @override
  State<FoodSearchResults> createState() => _FoodSearchResultsState();
}

class _FoodSearchResultsState extends State<FoodSearchResults> {
  String _for = '';
  List<UsdaFood>? _results;
  List<ScannedProduct>? _online;
  String _onlineFor = '';
  bool _onlineBusy = false;
  String? _onlineError;

  String get _q => widget.query.trim();

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(FoodSearchResults old) {
    super.didUpdateWidget(old);
    if (old.query.trim() != _q) _search();
  }

  Future<void> _search() async {
    final q = _q;
    _for = q;
    if (q.length < 2) {
      if (mounted) setState(() => _results = null);
      return;
    }
    final found = await FoodDatabase.search(q);
    // A newer search may have started while this one ran.
    if (!mounted || _for != q) return;
    setState(() => _results = found);
  }

  Future<void> _searchOnline() async {
    final q = _q;
    setState(() {
      _onlineBusy = true;
      _onlineError = null;
    });
    try {
      final found = await const OpenFoodFactsLookup().search(q);
      if (!mounted) return;
      setState(() {
        _online = found;
        _onlineFor = q;
      });
    } on FoodSearchFailure catch (e) {
      if (mounted) setState(() => _onlineError = e.message);
    } finally {
      if (mounted) setState(() => _onlineBusy = false);
    }
  }

  Future<void> _pickOnline(ScannedProduct p) async {
    final s = AppScope.of(context);
    final known = s.foodByBarcode(p.barcode);
    if (known != null) {
      widget.onFood(known);
      return;
    }
    // The same check-before-saving screen as a scanned barcode.
    final id = await Navigator.of(context).push<String>(ProductReviewScreen.route(code: p.barcode, product: p));
    if (id == null || !mounted) return;
    final f = s.food(id);
    if (f != null) widget.onFood(f);
  }

  Widget _tile(AppColors c, String title, String sub, VoidCallback onTap, {Key? key}) => InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.body(c)),
              Text(sub, style: AppText.quiet(c).copyWith(fontSize: 12)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    if (_q.length < 2) return const SizedBox.shrink();
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Text('BUILT-IN FOODS', style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
        if (results == null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No built-in foods match "$_q".', style: AppText.quiet(c)),
          )
        else
          for (final u in results)
            _tile(
              c,
              u.name,
              '${u.per100.kcal.round()} kcal · ${oneDecimal(u.per100.protein)} g protein per 100 g'
                  '${(u.servingGrams ?? 0) > 0 && u.servingLabel.isNotEmpty ? ' · ${u.servingLabel} = ${u.servingGrams!.round()} g' : ''}',
              () => widget.onFood(s.foodFromUsda(u)),
              key: ValueKey('usda-${u.id}'),
            ),
        if (s.settings.onlineFoodSearch) ...[
          const SizedBox(height: 12),
          Text('ONLINE (BRANDED PRODUCTS)', style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
          if (_onlineBusy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_online != null && _onlineFor == _q) ...[
            if (_online!.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Nothing found online for "$_q".', style: AppText.quiet(c)),
              ),
            for (final p in _online!)
              _tile(
                c,
                p.brand == null ? p.name : '${p.name} (${p.brand})',
                '${p.per100.kcal.round()} kcal · ${oneDecimal(p.per100.protein)} g protein per 100 g',
                () => _pickOnline(p),
              ),
            Text('Online results from Open Food Facts, added by volunteers: check them against the label.',
                style: AppText.quiet(c).copyWith(fontSize: 11)),
          ] else ...[
            if (_onlineError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_onlineError!, style: AppText.quiet(c).copyWith(color: c.protein)),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('search-online'),
                onPressed: _searchOnline,
                style: TextButton.styleFrom(foregroundColor: c.accent),
                icon: const Icon(Icons.public_rounded, size: 18),
                label: Text('Search online for "$_q"'),
              ),
            ),
          ],
        ],
        const SizedBox(height: 8),
        Text('Built-in foods: USDA FoodData Central (SR Legacy), per 100 g.',
            style: AppText.quiet(c).copyWith(fontSize: 11)),
      ],
    );
  }
}
