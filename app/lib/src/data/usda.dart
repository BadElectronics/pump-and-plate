/// The foods built into the app: USDA FoodData Central, SR Legacy (public
/// domain). Reading the bundled rows and ranking search results.
/// No Flutter imports: unit-tested.
library;

import '../ai/matcher.dart';
import '../calc/calc.dart';

class UsdaFood {
  const UsdaFood({
    required this.id,
    required this.name,
    this.common = '',
    required this.per100,
    this.fiber,
    this.sugar,
    this.sodiumMg,
    this.servingGrams,
    this.servingLabel = '',
  });

  /// The USDA number (NDB), e.g. "05064".
  final String id;
  final String name;

  /// Other names people use, when USDA lists them.
  final String common;
  final Macros per100;
  final double? fiber;
  final double? sugar;
  final double? sodiumMg;

  /// One typical portion, e.g. 140 g = "1 cup, chopped or diced".
  final double? servingGrams;
  final String servingLabel;

  String get sourceId => 'usda:$id';
}

double? _d(String s) => s.isEmpty ? null : double.tryParse(s);

/// One row of the bundled file:
/// id, name, common, kcal, protein, carbs, fat, fiber, sugar, sodium, serving g, serving label.
UsdaFood? parseUsdaLine(String line) {
  final f = line.split('\t');
  if (f.length < 12) return null;
  final kcal = _d(f[3]), protein = _d(f[4]), carbs = _d(f[5]), fat = _d(f[6]);
  if (f[1].isEmpty || kcal == null || protein == null || carbs == null || fat == null) return null;
  return UsdaFood(
    id: f[0],
    name: f[1],
    common: f[2],
    per100: Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat),
    fiber: _d(f[7]),
    sugar: _d(f[8]),
    sodiumMg: _d(f[9]),
    servingGrams: _d(f[10]),
    servingLabel: f[11].trim(),
  );
}

List<UsdaFood> parseUsdaFile(String text) => [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty)
          if (parseUsdaLine(line) case final UsdaFood f) f,
    ];

/// Words in a name, normalised (lower case, singular), for matching.
List<String> _words(String s) => [for (final w in normalizeName(s).split(' ')) if (w.isNotEmpty) w];

/// Forms that rank lower unless asked for ("breaded", "oil"...), and how much.
const _lessLikely = {
  'breaded': 2.0, 'battered': 2.0, 'fried': 2.0, 'nugget': 2.0, 'tender': 2.0, 'patty': 2.0, 'sliced': 2.0,
  'flavor': 2.0, 'flavored': 2.0, 'deli': 2.0, 'imitation': 2.0, 'frozen': 1.0, 'canned': 1.0, 'dried': 1.0,
  'dehydrated': 1.0, 'powder': 1.0, 'oil': 1.0, 'butter': 1.0,
};

/// Less common animals: sheep's milk, duck eggs...
const _unusual = {'sheep', 'goat', 'buffalo', 'human', 'duck', 'goose', 'emu'};

final _brand = RegExp(r'\b[A-Z]{3,}\b'); // USDA writes brands in capitals

/// A food with its search words prepared once (so typing stays smooth).
class UsdaEntry {
  UsdaEntry(this.food)
      : words = _words('${food.name} ${food.common}'),
        head = _words(food.name.split(',').take(3).join(','));

  final UsdaFood food;
  final List<String> words;

  /// USDA puts the food's identity in the first few parts of its name:
  /// "Chicken, broilers or fryers, breast, ...".
  final List<String> head;
}

List<UsdaEntry> indexUsda(List<UsdaFood> foods) => [for (final f in foods) UsdaEntry(f)];

/// The best matches for [query]: every word of the query must start a word
/// of the food's name (or common name). Ranked so the plain, everyday food
/// comes first: the query near the front of the name ("Egg, whole, raw"
/// before "Bread, egg"), whole/raw/plain forms, nothing breaded, branded or
/// unusual unless asked for, then shorter names.
List<UsdaFood> searchUsdaIndex(List<UsdaEntry> index, String query, {int limit = 25}) {
  final q = _words(query);
  if (q.isEmpty) return const [];
  final scored = <(double, UsdaFood)>[];
  for (final e in index) {
    final words = e.words;
    if (!q.every((w) => words.any((n) => n.startsWith(w)))) continue;
    final f = e.food;
    final head = e.head;
    final inHead = q.where((w) => head.any((n) => n.startsWith(w))).length;
    var score = 4 * inHead / q.length;
    if (head.isNotEmpty && q.first == head.first) score += 2;
    score += q.where(words.contains).length / q.length; // "egg" over "eggplant"
    final lower = f.name.toLowerCase();
    if (lower.contains('whole')) score += 0.6;
    if (lower.contains('raw')) score += 0.5;
    if (lower.contains('plain')) score += 0.5;
    if (lower.contains('meat only')) score += 0.5;
    for (final l in _lessLikely.entries) {
      if (words.contains(l.key) && !q.contains(l.key)) score -= l.value;
    }
    if (_unusual.any((w) => words.contains(w) && !q.contains(w))) score -= 1.5;
    if (_brand.hasMatch(f.name)) score -= 1.5;
    score -= 0.3 * (head.length - inHead).clamp(0, 99);
    score -= f.name.length / 200;
    scored.add((score, f));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final s in scored.take(limit)) s.$2];
}

/// The same search over plain foods (prepares the words each time; fine
/// for tests and one-off use).
List<UsdaFood> searchUsda(List<UsdaFood> foods, String query, {int limit = 25}) =>
    searchUsdaIndex(indexUsda(foods), query, limit: limit);
