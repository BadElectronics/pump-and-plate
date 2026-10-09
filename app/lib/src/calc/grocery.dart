import '../data/models.dart';

/// Cost of [grams] of [food] at [storeId], or null without a price there.
/// Foods sold by the item are bought in whole items.
double? groceryCost(Food food, double grams, String storeId) {
  final price = food.prices[storeId];
  if (price == null) return null;
  if (food.byItem) {
    final each = food.gramsPerItem ?? 0;
    if (each <= 0) return null;
    return itemsToBuy(food, grams) * price;
  }
  return price * grams / 1000;
}

/// Whole items to buy for [grams] (foods sold by the item).
int itemsToBuy(Food food, double grams) {
  final each = food.gramsPerItem ?? 0;
  if (each <= 0) return 0;
  return (grams / each - 1e-9).ceil();
}

class GroceryPlan {
  const GroceryPlan({
    required this.storeIds,
    required this.storeFor,
    required this.costs,
    required this.total,
    required this.missing,
  });

  /// Stores actually used, in your store order.
  final List<String> storeIds;

  /// Food id -> store to buy it at (absent when no chosen store prices it).
  final Map<String, String> storeFor;

  /// Food id -> cost at its store.
  final Map<String, double> costs;
  final double total;

  /// Food ids with no price at any chosen store.
  final List<String> missing;
}

/// Picks the set of at most [maxStores] stores, and the store for each
/// item, that leaves the fewest items unpriced and then costs the least
/// (ties go to fewer stores). Tries every combination, which is instant
/// for the handful of stores people use.
GroceryPlan? cheapestPlan({
  required Map<String, double> needs,
  required Map<String, Food> foods,
  required List<String> storeIds,
  required int maxStores,
}) {
  if (storeIds.isEmpty || needs.isEmpty) return null;
  final n = storeIds.length;
  final limit = maxStores.clamp(1, n);
  GroceryPlan? best;
  for (var mask = 1; mask < (1 << n); mask++) {
    final chosen = [
      for (var i = 0; i < n; i++)
        if ((mask & (1 << i)) != 0) storeIds[i],
    ];
    if (chosen.length > limit) continue;
    final storeFor = <String, String>{};
    final costs = <String, double>{};
    final missing = <String>[];
    var total = 0.0;
    for (final entry in needs.entries) {
      final f = foods[entry.key];
      String? bestStore;
      double? bestCost;
      if (f != null) {
        for (final st in chosen) {
          final cost = groceryCost(f, entry.value, st);
          if (cost != null && (bestCost == null || cost < bestCost)) {
            bestCost = cost;
            bestStore = st;
          }
        }
      }
      if (bestStore == null || bestCost == null) {
        missing.add(entry.key);
      } else {
        storeFor[entry.key] = bestStore;
        costs[entry.key] = bestCost;
        total += bestCost;
      }
    }
    final used = [
      for (final st in chosen)
        if (storeFor.containsValue(st)) st,
    ];
    final plan = GroceryPlan(
      storeIds: used,
      storeFor: storeFor,
      costs: costs,
      total: total,
      missing: missing,
    );
    final b = best;
    if (b == null ||
        plan.missing.length < b.missing.length ||
        (plan.missing.length == b.missing.length &&
            (plan.total < b.total - 0.005 ||
                ((plan.total - b.total).abs() <= 0.005 && plan.storeIds.length < b.storeIds.length)))) {
      best = plan;
    }
  }
  return best;
}
