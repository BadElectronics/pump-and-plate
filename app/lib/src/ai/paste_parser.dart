/// Reads pasted recipes and workouts into structured drafts. The AI only
/// tidies text this can't read; amounts and matching are done here.
/// No Flutter imports: unit-tested.
library;

enum PasteKind { recipe, workout, none }

// ------------------------------------------------------------------ numbers

const _fractions = {
  '½': 0.5, '⅓': 1 / 3, '⅔': 2 / 3, '¼': 0.25, '¾': 0.75,
  '⅛': 0.125, '⅜': 0.375, '⅝': 0.625, '⅞': 0.875, '⅕': 0.2,
};

/// "1 1/2", "1½", "½", "3/4", "1.5", "1,5" -> number.
double? parseQuantity(String s) {
  var t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  var total = 0.0;
  final last = t[t.length - 1];
  if (_fractions.containsKey(last)) {
    total += _fractions[last]!;
    t = t.substring(0, t.length - 1).trim();
    if (t.isEmpty) return total;
  }
  final parts = t.split(RegExp(r'\s+'));
  for (final p in parts) {
    if (p.contains('/')) {
      final ab = p.split('/');
      if (ab.length != 2) return null;
      final a = double.tryParse(ab[0]);
      final b = double.tryParse(ab[1]);
      if (a == null || b == null || b == 0) return null;
      total += a / b;
    } else {
      final v = double.tryParse(p);
      if (v == null) return null;
      total += v;
    }
  }
  return total;
}

const _num = r'(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?\s*[½⅓⅔¼¾⅛⅜⅝⅞⅕]|[½⅓⅔¼¾⅛⅜⅝⅞⅕]|\d+(?:[.,]\d+)?)';

// ------------------------------------------------------------------ units

/// Canonical unit -> grams (weight) or millilitres (volume).
const weightUnits = {'g': 1.0, 'kg': 1000.0, 'oz': 28.3495, 'lb': 453.592};
const volumeUnits = {
  'ml': 1.0, 'l': 1000.0, 'tsp': 4.929, 'tbsp': 14.787, 'cup': 240.0,
  'floz': 29.574, 'pint': 473.2, 'quart': 946.4,
};

/// Spoken unit -> canonical. "t" is a teaspoon and "T" a tablespoon, so the
/// lookup tries the exact spelling before lower case.
const _unitAliases = {
  'g': 'g', 'gr': 'g', 'gram': 'g', 'grams': 'g', 'gramme': 'g', 'grammes': 'g',
  'kg': 'kg', 'kgs': 'kg', 'kilo': 'kg', 'kilos': 'kg', 'kilogram': 'kg', 'kilograms': 'kg',
  'oz': 'oz', 'ounce': 'oz', 'ounces': 'oz',
  'lb': 'lb', 'lbs': 'lb', 'pound': 'lb', 'pounds': 'lb',
  'ml': 'ml', 'milliliter': 'ml', 'milliliters': 'ml', 'millilitre': 'ml', 'millilitres': 'ml',
  'l': 'l', 'liter': 'l', 'liters': 'l', 'litre': 'l', 'litres': 'l',
  't': 'tsp', 'tsp': 'tsp', 'tsps': 'tsp', 'teaspoon': 'tsp', 'teaspoons': 'tsp',
  'T': 'tbsp', 'tbsp': 'tbsp', 'tbsps': 'tbsp', 'tbs': 'tbsp', 'tbl': 'tbsp', 'tablespoon': 'tbsp', 'tablespoons': 'tbsp',
  'c': 'cup', 'cup': 'cup', 'cups': 'cup',
  'floz': 'floz', 'fl oz': 'floz', 'fluid ounce': 'floz', 'fluid ounces': 'floz',
  'pint': 'pint', 'pints': 'pint', 'pt': 'pint',
  'quart': 'quart', 'quarts': 'quart', 'qt': 'quart',
  'pinch': 'pinch', 'pinches': 'pinch', 'dash': 'dash', 'dashes': 'dash',
  'clove': 'clove', 'cloves': 'clove', 'slice': 'slice', 'slices': 'slice',
  'can': 'can', 'cans': 'can', 'tin': 'can', 'tins': 'can',
  'scoop': 'scoop', 'scoops': 'scoop', 'stick': 'stick', 'sticks': 'stick',
  'handful': 'handful', 'handfuls': 'handful', 'piece': 'piece', 'pieces': 'piece',
  'pc': 'piece', 'pcs': 'piece',
};

String? canonicalUnit(String word) {
  final w = word.replaceAll('.', '').trim();
  return _unitAliases[w] ?? _unitAliases[w.toLowerCase()];
}

// The unit words, longest first so "fl oz" wins over "fl" and "oz".
final _unitPattern = () {
  final words = _unitAliases.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  return words.map(RegExp.escape).join('|');
}();

// ------------------------------------------------------------------ lines

final _bullet = RegExp(r'^\s*(?:[-–•*·▪◦]+|\d+[.)])\s+');

String stripBullet(String line) => line.replaceFirst(_bullet, '').trim();

/// One ingredient line, as read.
class IngredientLine {
  const IngredientLine({
    required this.raw,
    required this.name,
    this.qty,
    this.unit,
    this.sizeGrams,
    this.note,
  });

  final String raw;
  final String name;
  final double? qty;

  /// Canonical unit, or null for a plain count ("2 eggs").
  final String? unit;

  /// For "1 (14 oz) can": the grams in one of them.
  final double? sizeGrams;
  final String? note;
}

final _ingredientRe = RegExp(
  '^($_num)(?:\\s*(?:-|–|to)\\s*($_num))?' // 2, 1 1/2, 2-3
  '\\s*(?:\\(\\s*($_num)\\s*($_unitPattern)\\.?\\s*\\))?' // (14 oz)
  '\\s*(?:($_unitPattern)\\.?(?=\\s|\$))?' // cups
  '\\s*(?:of\\s+)?(.*)\$',
  // Case-insensitive so "Tbsp" and "Cups" match; canonicalUnit() still tells
  // "t" (teaspoon) from "T" (tablespoon) by trying the exact spelling first.
  caseSensitive: false,
);

/// "1 1/2 cups rolled oats, divided" -> qty 1.5, cup, "rolled oats".
/// Null if the line doesn't start with an amount.
IngredientLine? parseIngredientLine(String line) {
  final s = stripBullet(line).replaceAllMapped(RegExp(r'(\d)([a-zA-Z])'), (m) => '${m[1]} ${m[2]}');
  final m = _ingredientRe.firstMatch(s);
  if (m == null) return null;
  var qty = parseQuantity(m.group(1)!);
  if (qty == null) return null;
  final hi = m.group(2) == null ? null : parseQuantity(m.group(2)!);
  if (hi != null && hi > qty) qty = (qty + hi) / 2;
  double? size;
  if (m.group(3) != null) {
    final n = parseQuantity(m.group(3)!);
    final u = canonicalUnit(m.group(4)!);
    if (n != null && u != null && weightUnits.containsKey(u)) size = n * weightUnits[u]!;
    if (n != null && u != null && volumeUnits.containsKey(u)) size = n * volumeUnits[u]!;
  }
  final unit = m.group(5) == null ? null : canonicalUnit(m.group(5)!);
  var rest = m.group(6)!.trim();
  String? note;
  final comma = rest.indexOf(',');
  if (comma > 0) {
    note = rest.substring(comma + 1).trim();
    rest = rest.substring(0, comma).trim();
  }
  rest = rest.replaceAll(RegExp(r'\s+'), ' ');
  if (rest.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(rest)) return null;
  return IngredientLine(raw: line.trim(), name: rest, qty: qty, unit: unit, sizeGrams: size, note: note);
}

// ------------------------------------------------------------------ grams

/// Grams per millilitre for common foods (water when unknown).
const _densities = <String, double>{
  'peanut butter': 1.08, 'almond butter': 1.08, 'brown sugar': 0.93,
  'powdered sugar': 0.5, 'icing sugar': 0.5, 'protein powder': 0.42, 'whey': 0.42,
  'chocolate chip': 0.72, 'baking powder': 0.9, 'baking soda': 1.2, 'soy sauce': 1.15,
  'maple syrup': 1.33, 'tomato sauce': 1.03, 'flour': 0.53, 'sugar': 0.85, 'rice': 0.78,
  'oat': 0.36, 'milk': 1.03, 'water': 1.0, 'oil': 0.92, 'butter': 0.96, 'honey': 1.42,
  'syrup': 1.33, 'yogurt': 1.03, 'yoghurt': 1.03, 'cheese': 0.45, 'salt': 1.2,
  'cocoa': 0.42, 'berry': 0.6, 'spinach': 0.13, 'lettuce': 0.2, 'broth': 1.0, 'stock': 1.0,
  'cream': 1.0, 'bean': 0.75, 'lentil': 0.8, 'pasta': 0.45, 'quinoa': 0.75, 'almond': 0.6,
  'nut': 0.55, 'granola': 0.45, 'broccoli': 0.37, 'raisin': 0.65, 'vanilla': 1.0,
  'vinegar': 1.0, 'juice': 1.04, 'salsa': 1.0,
};

/// Typical grams for one of something counted.
const _itemGrams = <String, double>{
  'sweet potato': 130, 'chicken breast': 174, 'chicken thigh': 110, 'bell pepper': 119,
  'english muffin': 57, 'egg white': 33, 'egg': 50, 'banana': 118, 'apple': 182,
  'avocado': 150, 'onion': 110, 'tomato': 123, 'potato': 213, 'lemon': 58, 'lime': 44,
  'carrot': 61, 'tortilla': 45, 'bagel': 100, 'orange': 131, 'cucumber': 300,
  'zucchini': 196, 'shallot': 25, 'jalapeno': 14, 'peach': 150, 'pear': 178, 'kiwi': 75,
  'mushroom': 18, 'strawberry': 12, 'date': 7, 'garlic': 3, 'bread': 30,
};

/// Grams for one of these units, whatever the food.
const _unitGrams = <String, double>{
  'pinch': 0.4, 'dash': 0.6, 'clove': 3, 'slice': 25, 'can': 400,
  'scoop': 30, 'stick': 113, 'handful': 30,
};

double? _lookup(Map<String, double> table, String text) {
  final t = text.toLowerCase();
  final keys = table.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    if (t.contains(k)) return table[k];
  }
  return null;
}

/// Grams for [line], using what's known about the matched food (name, grams
/// per item or serving). Null when it can't be worked out.
double? gramsFor(IngredientLine line, {String foodName = '', double? gramsPerItem}) {
  final qty = line.qty;
  if (qty == null) return null;
  final words = '${line.name} $foodName';
  if (line.sizeGrams != null) return qty * line.sizeGrams!;
  final u = line.unit;
  if (u != null && weightUnits.containsKey(u)) return qty * weightUnits[u]!;
  if (u != null && volumeUnits.containsKey(u)) {
    return qty * volumeUnits[u]! * (_lookup(_densities, words) ?? 1.0);
  }
  if (u != null && _unitGrams.containsKey(u)) {
    if (u == 'slice' && gramsPerItem != null) return qty * gramsPerItem;
    return qty * _unitGrams[u]!;
  }
  // A plain count, or "pieces".
  if (gramsPerItem != null && gramsPerItem > 0) return qty * gramsPerItem;
  final each = _lookup(_itemGrams, words);
  return each == null ? null : qty * each;
}

// ------------------------------------------------------------------ recipes

class RecipeDraft {
  RecipeDraft({
    required this.name,
    required this.servings,
    required this.ingredients,
    required this.steps,
    required this.skipped,
  });

  String name;
  double servings;
  final List<IngredientLine> ingredients;
  final List<String> steps;

  /// Lines that weren't an ingredient with an amount ("salt to taste").
  final List<String> skipped;
}

final _servingsRe = RegExp(r'\b(?:serves|servings?|makes|yields?)\s*:?\s*(\d+(?:\.\d+)?)', caseSensitive: false);
const _ingredientHeadings = {'ingredients', 'ingredient list', 'you will need', 'what you need'};
const _stepHeadings = {
  'directions', 'instructions', 'method', 'steps', 'preparation', 'how to make it', 'how to make',
};
const _otherHeadings = {'notes', 'note', 'nutrition', 'tips'};

String _heading(String line) =>
    line.toLowerCase().replaceAll(RegExp(r'[:#*_]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

RecipeDraft parseRecipe(String text) {
  String? name;
  double servings = 1;
  final ingredients = <IngredientLine>[];
  final steps = <String>[];
  final skipped = <String>[];
  String? section;
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final h = _heading(line);
    if (_ingredientHeadings.contains(h)) {
      section = 'ing';
      continue;
    }
    if (_stepHeadings.contains(h)) {
      section = 'steps';
      continue;
    }
    if (_otherHeadings.contains(h)) {
      section = 'other';
      continue;
    }
    final sv = _servingsRe.firstMatch(line);
    if (sv != null) {
      servings = double.tryParse(sv.group(1)!) ?? servings;
      if (line.length <= 30) continue;
    }
    if (section == 'other') continue;
    if (section == 'steps') {
      steps.add(stripBullet(line));
      continue;
    }
    final ing = parseIngredientLine(line);
    if (ing != null) {
      ingredients.add(ing);
      continue;
    }
    if (section == 'ing') {
      skipped.add(stripBullet(line));
      continue;
    }
    // A numbered line that reads like a sentence is a step ("1. Preheat oven").
    if (RegExp(r'^\d+[.)]\s').hasMatch(line) && stripBullet(line).length >= 12) {
      steps.add(stripBullet(line));
      continue;
    }
    if (name == null && ingredients.isEmpty && line.length <= 60 && !line.endsWith('.')) {
      name = line.replaceFirst(RegExp(r'^recipe\s*:\s*', caseSensitive: false), '').replaceAll(RegExp(r'[#*_]'), '').trim();
    } else if (line.length > 40) {
      steps.add(stripBullet(line));
    } else {
      skipped.add(stripBullet(line));
    }
  }
  return RecipeDraft(
    name: (name == null || name.isEmpty) ? 'Pasted recipe' : name,
    servings: servings <= 0 ? 1 : servings,
    ingredients: ingredients,
    steps: steps,
    skipped: skipped,
  );
}

// ------------------------------------------------------------------ workouts

class ExerciseLine {
  const ExerciseLine({
    required this.raw,
    required this.name,
    this.sets,
    this.repsLow,
    this.repsHigh,
    this.load,
    this.loadUnit,
    this.minutes,
    this.restSec,
    this.setTypes = const {},
    this.note,
  });

  final String raw;
  final String name;
  final int? sets;
  final int? repsLow;
  final int? repsHigh;

  /// As written, in [loadUnit] ('kg', 'lb', or null if no unit was given).
  final double? load;
  final String? loadUnit;
  final int? minutes;

  /// "rest 4:00" -> 240.
  final int? restSec;

  /// Techniques by set number ("set 2: partials" -> {2: 'partial'}); 0 means
  /// the last set. Values are set type names (partial, drop, restPause...).
  final Map<int, String> setTypes;

  /// Lines written under the exercise ("Full depth.").
  final String? note;

  ExerciseLine withNote(String more) => ExerciseLine(
        raw: raw,
        name: name,
        sets: sets,
        repsLow: repsLow,
        repsHigh: repsHigh,
        load: load,
        loadUnit: loadUnit,
        minutes: minutes,
        restSec: restSec,
        setTypes: setTypes,
        note: note == null ? more : '$note $more',
      );

  /// Kilograms, taking a bare number in the user's unit.
  double? loadKg({required bool imperial}) {
    final l = load;
    if (l == null) return null;
    final lb = loadUnit == 'lb' || (loadUnit == null && imperial);
    return lb ? l * 0.45359237 : l;
  }
}

class WorkoutDraft {
  WorkoutDraft({required this.name, required this.items, required this.skipped, this.note, this.defaultSets});

  String name;
  final List<ExerciseLine> items;
  final List<String> skipped;

  /// General rules written with the workout ("Add weight when...").
  final String? note;

  /// "(2 sets each)" in the title: sets for exercises that don't say.
  final int? defaultSets;
}

/// A set technique as written ("partials", "tech fail", "rest-pause") ->
/// a set type name, or null.
String? setTypeFromWords(String words) {
  final w = words.toLowerCase();
  if (RegExp(r'partial').hasMatch(w)) return 'partial';
  if (RegExp(r'drop').hasMatch(w)) return 'drop';
  if (RegExp(r'rest[\s-]*pause').hasMatch(w)) return 'restPause';
  if (RegExp(r'myo').hasMatch(w)) return 'myo';
  if (RegExp(r'amrap|as many').hasMatch(w)) return 'amrap';
  if (RegExp(r'warm').hasMatch(w)) return 'warmup';
  if (RegExp(r'fail').hasMatch(w)) return 'failure';
  return null;
}

final _setTag = RegExp(
  r'\b(last set|set\s*(\d+))\s*[:=-]\s*([a-z][a-z \-]*?)(?=\s*(?:$|[—–|,;.(]))',
  caseSensitive: false,
);
final _restRe = RegExp(
  r'\brest\s*:?\s*(\d+):(\d{2})\b|\brest\s*:?\s*(\d+(?:\.\d+)?)\s*(s|secs?|seconds?|m|mins?|minutes?)\b|\b(\d+):(\d{2})\s*rest\b',
  caseSensitive: false,
);
final _repsOnly = RegExp(r'(\d+)\s*(?:-|–|—|to)\s*(\d+)\s*reps?\b|(\d+)\s*reps?\b', caseSensitive: false);

final _loadAt = RegExp(r'(?:@|\bat\b)\s*(\d+(?:\.\d+)?)\s*(kgs?|lbs?|pounds?)?\b', caseSensitive: false);
final _loadUnit = RegExp(r'(\d+(?:\.\d+)?)\s*(kgs?|lbs?|pounds?)\b', caseSensitive: false);
final _minutesRe = RegExp(r'(\d+(?:\.\d+)?)\s*(?:min|mins|minutes?)\b', caseSensitive: false);
final _setsReps = RegExp(r'(\d+)\s*x\s*(\d+)(?:\s*(?:-|–|to)\s*(\d+))?\s*(?:reps?\b|seconds?\b|secs?\b|s\b)?', caseSensitive: false);
final _setsOf = RegExp(r'(\d+)\s*sets?\s*(?:of|x)?\s*(\d+)(?:\s*(?:-|–|to)\s*(\d+))?\s*(?:reps?\b)?', caseSensitive: false);
final _setsOnly = RegExp(r'(\d+)\s*(?:sets?\b|x\s*(?:amrap|max)\b)', caseSensitive: false);

/// "Bench press 3x8 @ 185", "3 sets of 10 pull-ups", "Run 20 min".
/// Null if the line isn't an exercise with sets or minutes.
ExerciseLine? parseExerciseLine(String line) {
  var s = stripBullet(line).replaceAllMapped(RegExp(r'(\d)\s*[xX×]\s*(\d)'), (m) => '${m[1]}x${m[2]}');
  // "set 2: partials", "last set: drop set"
  final types = <int, String>{};
  for (final m in _setTag.allMatches(s).toList().reversed) {
    final t = setTypeFromWords(m.group(3)!);
    if (t == null) continue;
    types[m.group(2) == null ? 0 : int.parse(m.group(2)!)] = t;
    s = s.replaceRange(m.start, m.end, ' ');
  }
  // Rest before minutes, so "rest 4 min" isn't read as 4 minutes of cardio.
  int? restSec;
  final r = _restRe.firstMatch(s);
  if (r != null) {
    if (r.group(1) != null) {
      restSec = int.parse(r.group(1)!) * 60 + int.parse(r.group(2)!);
    } else if (r.group(3) != null) {
      final v = double.parse(r.group(3)!);
      restSec = (r.group(4)!.toLowerCase().startsWith('m') ? v * 60 : v).round();
    } else {
      restSec = int.parse(r.group(5)!) * 60 + int.parse(r.group(6)!);
    }
    s = s.replaceRange(r.start, r.end, ' ');
  }
  double? load;
  String? unit;
  String unitOf(String? u) {
    final w = (u ?? '').toLowerCase();
    if (w.startsWith('kg')) return 'kg';
    return 'lb';
  }

  final at = _loadAt.firstMatch(s);
  if (at != null) {
    load = double.tryParse(at.group(1)!);
    unit = at.group(2) == null ? null : unitOf(at.group(2));
    s = s.replaceRange(at.start, at.end, ' ');
  } else {
    final lu = _loadUnit.firstMatch(s);
    if (lu != null) {
      load = double.tryParse(lu.group(1)!);
      unit = unitOf(lu.group(2));
      s = s.replaceRange(lu.start, lu.end, ' ');
    }
  }
  s = s.replaceAll(RegExp(r'\b(?:bw|body\s*weight)\b', caseSensitive: false), ' ');
  int? minutes;
  final mm = _minutesRe.firstMatch(s);
  if (mm != null) {
    minutes = double.tryParse(mm.group(1)!)?.round();
    s = s.replaceRange(mm.start, mm.end, ' ');
  }
  int? sets, lo, hi;
  final sr = _setsReps.firstMatch(s) ?? _setsOf.firstMatch(s);
  if (sr != null) {
    sets = int.tryParse(sr.group(1)!);
    lo = int.tryParse(sr.group(2)!);
    hi = sr.group(3) == null ? lo : int.tryParse(sr.group(3)!);
    s = s.replaceRange(sr.start, sr.end, ' ');
  } else {
    final so = _setsOnly.firstMatch(s);
    if (so != null) {
      sets = int.tryParse(so.group(1)!);
      s = s.replaceRange(so.start, so.end, ' ');
    }
  }
  // "Hack squat — 6–10 reps": reps without sets (sets come from the title).
  if (sets == null && minutes == null) {
    final ro = _repsOnly.firstMatch(s);
    if (ro == null) return null;
    lo = int.tryParse(ro.group(1) ?? ro.group(3)!);
    hi = ro.group(2) == null ? lo : int.tryParse(ro.group(2)!);
    s = s.replaceRange(ro.start, ro.end, ' ');
  }
  // A plain number left after sets x reps is the load ("Bench 3x8 185").
  if (load == null && sets != null) {
    final bare = RegExp(r'(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])').firstMatch(s);
    if (bare != null) {
      load = double.tryParse(bare.group(1)!);
      s = s.replaceRange(bare.start, bare.end, ' ');
    }
  }
  final name = s
      .replaceAll(RegExp(r'\b(?:sets?|reps?|of|for)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'[:@,;()\[\]]'), ' ')
      .replaceAll(RegExp(r'\s[-–—|]\s|[—|]'), ' ')
      .replaceAll(RegExp(r'\b\d+\s*s(?:ec(?:onds?)?)?\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–.]+|[\s\-–.]+$'), '')
      .trim();
  if (name.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(name)) return null;
  if (hi != null && lo != null && hi < lo) hi = lo;
  return ExerciseLine(
    raw: line.trim(),
    name: name,
    sets: sets,
    repsLow: lo,
    repsHigh: hi,
    load: load,
    loadUnit: unit,
    minutes: minutes,
    restSec: restSec,
    setTypes: types,
  );
}

/// General rules rather than a note on one exercise.
final _ruleLine = RegExp(
  r'^(?:set\s*\d+\s*[:=-]|sets?\b|all sets|each set|last set\b|add weight|progress|progression|deload|rest\b|notes?\s*:|tips?\s*:|when you|every\b|week\b)',
  caseSensitive: false,
);

/// "(2 sets each)", "2 sets per exercise".
final _setsEach = RegExp(r'\(?\s*(\d+)\s*sets?\s*(?:each|per exercise|per movement|for each)\s*\)?', caseSensitive: false);

WorkoutDraft parseWorkout(String text) {
  String? name;
  int? defaultSets;
  final items = <ExerciseLine>[];
  final skipped = <String>[];
  final rules = <String>[];
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    // The title, possibly with "(2 sets each)".
    if (name == null && items.isEmpty) {
      final each = _setsEach.firstMatch(line);
      if (each != null) {
        defaultSets = int.tryParse(each.group(1)!);
        final title = line.replaceRange(each.start, each.end, ' ').replaceAll(RegExp(r'[#*_:]|\s+$'), '').trim();
        name = title.replaceAll(RegExp(r'\s*[—–-]\s*$'), '').trim();
        continue;
      }
    }
    final ex = parseExerciseLine(line);
    if (ex != null) {
      items.add(ex);
    } else if (name == null && items.isEmpty && line.length <= 60) {
      name = line.replaceAll(RegExp(r'[#*_:]'), '').trim();
    } else if (_ruleLine.hasMatch(line)) {
      rules.add(stripBullet(line));
    } else if (items.isNotEmpty && line.length <= 120) {
      // Written under an exercise: its note.
      items[items.length - 1] = items.last.withNote(stripBullet(line));
    } else {
      skipped.add(stripBullet(line));
    }
  }
  return WorkoutDraft(
    name: (name == null || name.isEmpty) ? 'Pasted workout' : name,
    items: items,
    skipped: skipped,
    note: rules.isEmpty ? null : rules.join('\n'),
    defaultSets: defaultSets,
  );
}

// ------------------------------------------------------------------ classify

/// Is this text a recipe, a workout, or neither (a chat message)?
final _instruction = RegExp(
  r"^(?:make|change|add|remove|delete|set|put|plan|schedule|fix|update|log|start|move|replace|swap|edit|"
  r"can|could|would|please|i|i'm|im|my|let|lets|let's|do|give|show|what|how|should|is|are|use|turn)\b",
  caseSensitive: false,
);
final _notation = RegExp(r'\d+\s*[xX×]\s*\d+|\d+\s*sets?\s*(?:of|x)\s*\d+|\d+\s*(?:min|mins|minutes)\b', caseSensitive: false);

PasteKind classifyPaste(String text) {
  final lines = [
    for (final l in text.split(RegExp(r'\r?\n')))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  if (lines.isEmpty) return PasteKind.none;
  // One line is a paste only if it reads like one ("Bench press 3x8 @ 185"):
  // workout notation, and not an instruction or question. "Make bench 4 sets
  // in my push workout" is a request for the AI, not a pasted workout.
  if (lines.length == 1) {
    final l = lines.first;
    if (l.contains('?') ||
        l.split(RegExp(r'\s+')).length > 8 ||
        _instruction.hasMatch(l) ||
        !_notation.hasMatch(l)) {
      return PasteKind.none;
    }
  }
  var workout = 0;
  var recipe = 0;
  for (final l in lines) {
    if (parseExerciseLine(l) != null) workout++;
    if (parseIngredientLine(l) != null) recipe++;
    final h = _heading(l);
    if (_ingredientHeadings.contains(h)) recipe += 2;
    if (_servingsRe.hasMatch(l)) recipe++;
  }
  if (workout >= 1 && workout >= recipe) return PasteKind.workout;
  if (recipe >= 2) return PasteKind.recipe;
  return PasteKind.none;
}

/// Share of a draft's lines that couldn't be read (0 = all read).
double unreadShare(int read, int unread) => read + unread == 0 ? 1 : unread / (read + unread);
