import 'dart:convert';

import '../calc/calc.dart';
import 'models.dart';

/// Recipes and foods from a share file.
class FoodShare {
  const FoodShare({this.from, this.foods = const [], this.recipes = const []});

  /// The sender's nickname, if they set one.
  final String? from;
  final List<Food> foods;
  final List<Recipe> recipes;
}

class FoodShareError implements Exception {
  const FoodShareError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A small JSON file with [recipes], every food they use, and [foods].
/// Store prices are left out (the other person's stores are different).
String encodeFoodShare({
  required List<Food> foods,
  required List<Recipe> recipes,
  String? from,
  DateTime? now,
}) {
  Map<String, Object?> food(Food f) => {
        'id': f.id,
        'name': f.name,
        'kcal': f.per100.kcal,
        'protein': f.per100.protein,
        'carbs': f.per100.carbs,
        'fat': f.per100.fat,
        'by_item': f.byItem,
        'grams_per_item': f.gramsPerItem,
        'barcode': f.barcode,
        'brand': f.brand,
        'serving_g': f.servingGrams,
        'fiber': f.fiber,
        'sugar': f.sugar,
        'sodium_mg': f.sodiumMg,
      };
  return const JsonEncoder.withIndent('  ').convert({
    'app': 'fitapp',
    'kind': 'food-share',
    'format': 1,
    'from': from,
    'shared_at': (now ?? DateTime.now()).toIso8601String(),
    'foods': [for (final f in foods) food(f)],
    'recipes': [
      for (final r in recipes)
        {
          'id': r.id,
          'name': r.name,
          'servings': r.servings,
          'note': r.note,
          'items': [for (final i in r.items) i.toJson()],
        },
    ],
  });
}

double? _d(Object? v) => v is num ? v.toDouble() : null;

FoodShare decodeFoodShare(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const FoodShareError('This file isn\'t a Pump and Plate food share.');
  }
  if (root is! Map || root['app'] != 'fitapp') {
    throw const FoodShareError('This file isn\'t a Pump and Plate food share.');
  }
  if (root['kind'] != 'food-share') {
    if (root.containsKey('profile')) {
      throw const FoodShareError(
        'That\'s a full Pump and Plate backup. To load it, use Settings > Your data > Restore.',
      );
    }
    throw const FoodShareError('This file isn\'t a Pump and Plate food share.');
  }
  final format = root['format'];
  if (format is! int || format > 1) {
    throw const FoodShareError('This share was made by a newer Pump and Plate. Update the app first.');
  }
  try {
    final foods = <Food>[
      for (final f in (root['foods'] as List? ?? const []))
        if (f is Map && f['id'] is String && f['name'] is String)
          Food(
            id: f['id'] as String,
            name: (f['name'] as String).trim(),
            per100: Macros(
              kcal: _d(f['kcal']) ?? 0,
              protein: _d(f['protein']) ?? 0,
              carbs: _d(f['carbs']) ?? 0,
              fat: _d(f['fat']) ?? 0,
            ),
            byItem: f['by_item'] == true,
            gramsPerItem: _d(f['grams_per_item']),
            barcode: f['barcode'] is String ? f['barcode'] as String : null,
            brand: f['brand'] is String ? f['brand'] as String : null,
            servingGrams: _d(f['serving_g']),
            fiber: _d(f['fiber']),
            sugar: _d(f['sugar']),
            sodiumMg: _d(f['sodium_mg']),
            custom: true,
          ),
    ];
    final recipes = <Recipe>[
      for (final r in (root['recipes'] as List? ?? const []))
        if (r is Map && r['id'] is String && r['name'] is String)
          Recipe(
            id: r['id'] as String,
            name: (r['name'] as String).trim(),
            servings: _d(r['servings']) ?? 1,
            note: r['note'] as String?,
            items: [
              for (final i in (r['items'] as List? ?? const []))
                if (i is Map && i['food_id'] is String) RecipeItem.fromJson(Map<String, Object?>.from(i)),
            ],
          ),
    ];
    final from = root['from'];
    return FoodShare(
      from: from is String && from.trim().isNotEmpty ? from.trim() : null,
      foods: foods,
      recipes: recipes,
    );
  } catch (_) {
    throw const FoodShareError('This share file looks damaged and couldn\'t be read.');
  }
}
