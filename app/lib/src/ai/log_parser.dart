/// Reads one-line logging messages: "weighed 182.4", "slept 7.5 hours,
/// quality 4", "breakfast: 2 eggs, 1 banana", "had chicken and rice for
/// lunch yesterday". The AI handles anything messier.
/// No Flutter imports: unit-tested.
library;

import 'paste_parser.dart';

sealed class LogIntent {
  const LogIntent({this.daysAgo = 0});

  /// 0 = today (for sleep: last night), 1 = yesterday.
  final int daysAgo;
}

class WeightIntent extends LogIntent {
  const WeightIntent(this.value, {this.unit, super.daysAgo});
  final double value;

  /// 'kg', 'lb', or null (the user's unit).
  final String? unit;
}

class SleepIntent extends LogIntent {
  const SleepIntent(this.minutes, {this.quality, super.daysAgo});
  final int minutes;
  final int? quality;
}

class WaterIntent extends LogIntent {
  const WaterIntent(this.ml, {super.daysAgo});
  final double ml;
}

/// Millilitres in one of each (a glass is taken as 8 oz, a bottle as 500 ml).
const _waterUnits = {
  'ml': 1.0, 'milliliter': 1.0, 'milliliters': 1.0, 'millilitre': 1.0, 'millilitres': 1.0,
  'l': 1000.0, 'liter': 1000.0, 'liters': 1000.0, 'litre': 1000.0, 'litres': 1000.0,
  'oz': 29.5735, 'ounce': 29.5735, 'ounces': 29.5735,
  'cup': 236.588, 'cups': 236.588, 'glass': 236.588, 'glasses': 236.588,
  'bottle': 500.0, 'bottles': 500.0,
};

final _waterAmount = RegExp(
  r'\b(\d+(?:[.,]\d+)?|a|an|one|two|three|four|half a)\s*(ml|millilit(?:er|re)s?|l|lit(?:er|re)s?|oz|ounces?|cups?|glass(?:es)?|bottles?)\s+(?:of\s+)?water\b',
  caseSensitive: false,
);
final _waterLead = RegExp(
  r'^water\s*:?\s*(\d+(?:[.,]\d+)?)\s*(ml|millilit(?:er|re)s?|l|lit(?:er|re)s?|oz|ounces?|cups?|glass(?:es)?|bottles?)\b',
  caseSensitive: false,
);

WaterIntent? _water(String t) {
  final m = _waterAmount.firstMatch(t) ?? _waterLead.firstMatch(t);
  if (m == null) return null;
  final n = m.group(1)!.toLowerCase();
  final qty = double.tryParse(n.replaceAll(',', '.')) ?? _wordNumbers[n] ?? (n == 'half a' ? 0.5 : null);
  final per = _waterUnits[m.group(2)!.toLowerCase()];
  if (qty == null || per == null) return null;
  final ml = qty * per;
  if (ml <= 0 || ml > 6000) return null;
  return WaterIntent(ml, daysAgo: _daysAgo(t));
}

class FoodIntent extends LogIntent {
  const FoodIntent(this.items, {this.meal, super.daysAgo});
  final List<IngredientLine> items;

  /// 'breakfast', 'lunch', 'dinner', 'snack', or null (guess from the time).
  final String? meal;
}

int _daysAgo(String t, {bool sleep = false}) {
  // "Last night" is today's sleep entry, but yesterday's food.
  if (RegExp(r'\byesterday\b', caseSensitive: false).hasMatch(t)) return 1;
  if (!sleep && RegExp(r'\blast night\b', caseSensitive: false).hasMatch(t)) return 1;
  return 0;
}

const _wordNumbers = {
  'a': 1.0, 'an': 1.0, 'one': 1.0, 'two': 2.0, 'three': 3.0, 'four': 4.0, 'five': 5.0,
  'six': 6.0, 'half a': 0.5, 'half': 0.5, 'a couple of': 2.0, 'a couple': 2.0, 'a few': 3.0,
};

/// "2 eggs", "a banana", "chicken" (no amount: one of them / one serving).
IngredientLine? _item(String raw) {
  var t = raw.trim().replaceAll(RegExp(r'^[\-–•*]+\s*'), '').replaceAll(RegExp(r'[.!]+$'), '').trim();
  if (t.isEmpty || !RegExp(r'[a-zA-Z]').hasMatch(t)) return null;
  final parsed = parseIngredientLine(t);
  if (parsed != null) return parsed;
  final lower = t.toLowerCase();
  final words = _wordNumbers.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final w in words) {
    if (lower.startsWith('$w ')) {
      final rest = t.substring(w.length + 1).trim();
      final asNumber = parseIngredientLine('${_wordNumbers[w]} $rest');
      if (asNumber != null) return IngredientLine(raw: raw.trim(), name: asNumber.name, qty: asNumber.qty, unit: asNumber.unit, sizeGrams: asNumber.sizeGrams);
      return IngredientLine(raw: raw.trim(), name: rest, qty: _wordNumbers[w]);
    }
  }
  t = t.replaceFirst(RegExp(r'^(?:some|my|the)\s+', caseSensitive: false), '');
  return IngredientLine(raw: raw.trim(), name: t, qty: null);
}

String? _mealIn(String t) {
  final m = RegExp(r'\b(breakfast|lunch|dinner|supper|snacks?)\b', caseSensitive: false).firstMatch(t);
  if (m == null) return null;
  final w = m.group(1)!.toLowerCase();
  if (w == 'supper') return 'dinner';
  if (w.startsWith('snack')) return 'snack';
  return w;
}

final _weightRe = RegExp(
  r'^(?:i\s+)?(?:weighed(?:\s+in)?(?:\s+at)?|weigh[\s-]?in(?:\s+(?:at|of))?|weight(?:\s+(?:is|was|today))?|scale(?:\s+says)?|my\s+weight\s+(?:is|was))\s*:?\s*(\d+(?:[.,]\d+)?)\s*(kgs?|kilos?|lbs?|pounds?)?\b',
  caseSensitive: false,
);
final _weightBare = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(kgs?|lbs?|pounds?)\s*(?:this morning|today|yesterday)?\s*$', caseSensitive: false);

final _sleepHours = RegExp(
  r'\b(?:slept|sleep(?:\s+was)?|got)\s*:?\s*(?:for\s+|about\s+|around\s+)?(\d+(?:[.,]\d+)?)\s*(?:h|hrs?|hours?)\b(?:\s*(?:and\s*)?(\d+)\s*(?:m|mins?|minutes?)\b)?',
  caseSensitive: false,
);
final _sleepHm = RegExp(r'\b(\d+)\s*h\s*(\d+)\s*m?\b.*\bsleep', caseSensitive: false);
final _quality = RegExp(r'\bquality\s*(?:was|of|:)?\s*([1-5])\b|\b([1-5])\s*/\s*5\b', caseSensitive: false);

/// A logging message, or null if it isn't one (a question, a paste, chat).
LogIntent? parseLogIntent(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains('?') || t.contains('\n') || t.length > 220) return null;

  // ---- weight
  final w = _weightRe.firstMatch(t) ?? _weightBare.firstMatch(t);
  if (w != null) {
    final v = double.tryParse(w.group(1)!.replaceAll(',', '.'));
    if (v != null && v > 20 && v < 700) {
      final u = w.group(2)?.toLowerCase();
      return WeightIntent(v, unit: u == null ? null : (u.startsWith('k') ? 'kg' : 'lb'), daysAgo: _daysAgo(t));
    }
  }

  // ---- sleep
  final sh = _sleepHours.firstMatch(t);
  final hm = sh == null ? _sleepHm.firstMatch(t) : null;
  if (sh != null && (RegExp(r'\bslept\b|\bsleep\b', caseSensitive: false).hasMatch(t))) {
    final h = double.tryParse(sh.group(1)!.replaceAll(',', '.')) ?? 0;
    final m = int.tryParse(sh.group(2) ?? '') ?? 0;
    final minutes = (h * 60).round() + m;
    if (minutes > 0 && minutes <= 16 * 60) {
      final q = _quality.firstMatch(t);
      return SleepIntent(minutes, quality: int.tryParse(q?.group(1) ?? q?.group(2) ?? ''), daysAgo: _daysAgo(t, sleep: true));
    }
  } else if (hm != null) {
    final minutes = int.parse(hm.group(1)!) * 60 + int.parse(hm.group(2)!);
    if (minutes > 0 && minutes <= 16 * 60) {
      final q = _quality.firstMatch(t);
      return SleepIntent(minutes, quality: int.tryParse(q?.group(1) ?? q?.group(2) ?? ''), daysAgo: _daysAgo(t, sleep: true));
    }
  }

  // ---- water (before food, so "had 2 cups of water" isn't a food)
  final water = _water(t);
  if (water != null) return water;

  // ---- food: "breakfast: ...", "had/ate ... (for lunch)", "log ... for dinner"
  final meal = _mealIn(t);
  final lead = RegExp(r'^(?:breakfast|lunch|dinner|supper|snacks?)\s*[:\-–]\s*', caseSensitive: false).firstMatch(t);
  final verb = RegExp(r'^(?:i\s+)?(?:just\s+)?(?:had|ate|eaten|log(?:ged)?|for\s+(?:breakfast|lunch|dinner|supper|snacks?)\s+i\s+had)\b', caseSensitive: false)
      .firstMatch(t);
  if (lead == null && verb == null) return null;
  var body = t.substring((lead ?? verb)!.end);
  body = body
      .replaceAll(RegExp(r'\b(?:for|at|with)\s+(?:breakfast|lunch|dinner|supper|snacks?|a snack)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(?:as\s+a\s+)?snack\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(?:yesterday|today|this morning|tonight|last night)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final pieces = body.split(RegExp(r',|;|\+|&|\band\b|\bplus\b', caseSensitive: false));
  final items = [
    for (final p in pieces)
      if (_item(p) case final IngredientLine i) i,
  ];
  if (items.isEmpty) return null;
  // Without a meal word, only a message with an amount counts as food:
  // "had 2 eggs" does, "had a great workout" doesn't (the AI can still log it).
  if (meal == null && lead == null && !items.any((i) => RegExp(r'\d').hasMatch(i.raw))) return null;
  return FoodIntent(items, meal: meal, daysAgo: _daysAgo(t));
}

/// A food log from a list of items (the AI's log_food call).
FoodIntent? foodIntentFrom(List<String> items, {String? meal, int daysAgo = 0}) {
  final lines = [
    for (final p in items)
      if (_item(p) case final IngredientLine i) i,
  ];
  if (lines.isEmpty) return null;
  final m = meal == null ? null : _mealIn(meal);
  return FoodIntent(lines, meal: m, daysAgo: daysAgo);
}
