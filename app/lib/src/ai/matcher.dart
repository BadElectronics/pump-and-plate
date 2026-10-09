/// Matches pasted names to the user's own foods and exercises. Deliberately
/// cautious: a wrong match is worse than asking the user to pick.
/// No Flutter imports: unit-tested.
library;

/// Words that describe rather than name ("2 large eggs, beaten").
const _filler = {
  'a', 'an', 'the', 'of', 'and', 'or', 'with', 'to', 'taste', 'fresh', 'large', 'medium',
  'small', 'chopped', 'diced', 'sliced', 'minced', 'grated', 'shredded', 'raw', 'cooked',
  'dry', 'boneless', 'skinless', 'organic', 'whole', 'finely', 'roughly', 'peeled',
  'optional', 'about', 'heaping', 'level', 'packed', 'softened', 'melted', 'cold', 'warm',
  'room', 'temperature', 'plus', 'more', 'extra', 'divided',
};

/// Common short forms, applied to whole phrases before matching.
const _exerciseSynonyms = {
  'bench': 'bench press', 'squat': 'back squat', 'squats': 'back squat', 'rdl': 'romanian deadlift',
  'rdls': 'romanian deadlift', 'ohp': 'overhead press', 'military press': 'overhead press',
  'pullup': 'pull up', 'pullups': 'pull up', 'chinup': 'chin up', 'chinups': 'chin up',
  'pushup': 'push up', 'pushups': 'push up', 'dips': 'dip', 'run': 'running', 'jog': 'running',
  'jogging': 'running', 'bike': 'cycling', 'biking': 'cycling', 'row machine': 'rowing machine',
  'rower': 'rowing machine', 'skullcrusher': 'skull crusher', 'skullcrushers': 'skull crusher',
  'lat pull down': 'lat pulldown', 'pulldown': 'lat pulldown', 'lunges': 'walking lunge',
  'hip thrusts': 'hip thrust', 'rope jump': 'jump rope', 'skipping': 'jump rope',
};

const _wordSynonyms = {'db': 'dumbbell', 'bb': 'barbell', 'tricep': 'triceps', 'bicep': 'biceps'};

String _singular(String w) {
  if (w.length <= 2) return w;
  if (w.length > 3 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.length > 3 && (w.endsWith('oes') || w.endsWith('ches') || w.endsWith('shes'))) {
    return w.substring(0, w.length - 2);
  }
  // Three letters counts too, so "pull-ups" matches "pull-up".
  if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us')) return w.substring(0, w.length - 1);
  return w;
}

/// Lower case, no punctuation or bracketed notes, singular words.
String normalizeName(String s) {
  var t = s.toLowerCase().replaceAll(RegExp(r'\([^)]*\)'), ' ');
  t = t.replaceAll(RegExp(r"[^a-z0-9%/ ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.split(' ').map((w) => _wordSynonyms[w] ?? w).map(_singular).join(' ');
}

Set<String> _tokens(String normalized) => {
      for (final w in normalized.split(' '))
        if (w.isNotEmpty && !_filler.contains(w)) w,
    };

/// How well [query] names the same thing as [candidate], 0..1. Both sides'
/// coverage counts, so "flour" vs "flour tortilla" scores only 0.5.
double nameScore(String query, String candidate) {
  final a = _tokens(normalizeName(query));
  final b = _tokens(normalizeName(candidate));
  if (a.isEmpty || b.isEmpty) return 0;
  if (a.length == b.length && a.containsAll(b)) return 1;
  final shared = a.intersection(b).length;
  return (shared / a.length) * (shared / b.length);
}

/// The best-scoring item, if it clears [threshold] (ties: the earlier item).
T? bestMatch<T>(String query, Iterable<T> items, String Function(T) nameOf, {double threshold = 0.6}) {
  T? best;
  var bestScore = threshold;
  for (final item in items) {
    final s = nameScore(query, nameOf(item));
    if (s > bestScore || (best == null && s >= threshold)) {
      best = item;
      bestScore = s;
      if (s >= 1) break;
    }
  }
  return best;
}

/// A food's name without its details ("Chicken breast, raw" -> "Chicken breast").
String foodMainName(String name) {
  final i = name.indexOf(',');
  return i > 0 ? name.substring(0, i) : name;
}

/// Exercise names as people write them, mapped to library wording first.
String exerciseQuery(String name) {
  final n = normalizeName(name);
  for (final e in _exerciseSynonyms.entries) {
    final from = normalizeName(e.key);
    if (n == from) return e.value;
  }
  return name;
}

/// Words that describe how an exercise is done, not which one it is.
const _exerciseFiller = {'flat', 'seated', 'standing', 'weighted', 'strict', 'paused', 'pause', 'tempo', 'heavy', 'light'};

/// For matching exercise names: short forms expanded ("DB", "RDL"),
/// describing words dropped ("Flat", "Seated", "Weighted"), and overhead,
/// military and shoulder presses treated alike.
String exerciseKey(String name) {
  final n = normalizeName(exerciseQuery(name));
  final words = [for (final w in n.split(' ')) if (w.isNotEmpty && !_exerciseFiller.contains(w)) w];
  return words.join(' ').replaceAll('overhead press', 'shoulder press').replaceAll('military press', 'shoulder press');
}
