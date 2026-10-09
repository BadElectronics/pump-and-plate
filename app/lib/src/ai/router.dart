/// Which part of the app a message is about, so the AI is only shown that
/// part's tools (a small phone model chooses well from a handful, not from
/// dozens, and every tool's description takes up its limited memory).
/// No Flutter imports: unit-tested.
library;

enum AiArea { general, training, food, goals, data }

final _training = RegExp(
  r'\b(workouts?|exercises?|sets?|reps?|meso(?:cycle)?s?|blocks?|deload|programs?|routines?|splits?|train(?:ing)?|lift(?:s|ing)?|'
  r'squats?|bench|deadlifts?|press(?:es)?|rows?|curls?|pull[\s-]?ups?|chin[\s-]?ups?|dips?|lunges?|raises?|flys?|extensions?|'
  r'push day|pull day|leg day|upper|lower|full body|warm[\s-]?ups?|rest time|superset)\b',
  caseSensitive: false,
);
final _food = RegExp(
  r'\b(food|foods|ate|eat|eaten|eating|meals?|breakfast|lunch|dinner|supper|snacks?|calories|kcal|protein|carbs|fat|'
  r'grocer(?:y|ies)|shopping|recipes?|servings?|grams?|cups?|water|drink|logged|eggs?|chicken|rice|oats|banana|yogurt)\b',
  caseSensitive: false,
);

final _goals = RegExp(
  r'\b(goals?|targets?|pace|units?|metric|imperial|themes?|dark mode|light mode|remind(?:ers?)?|notifications?|settings?|'
  r'week starts?|starts? on (?:sunday|monday)|lose weight|gain weight|maintain|bulk(?:ing)?|cut(?:ting)?|'
  r'calorie (?:target|goal)|protein (?:target|goal)|water goal|sleep goal)\b',
  caseSensitive: false,
);

// Fixing something already logged: a correcting word, a logged thing, a past day.
final _fix = RegExp(r'\b(delete|remove|edit|fix|change|correct|wrong|mistake|update|actually)\b', caseSensitive: false);
final _logged = RegExp(r'\b(weigh[\s-]?ins?|weights?|weighed|sleep|slept|sets?|sessions?|workouts?)\b', caseSensitive: false);
final _pastDay = RegExp(
  r"\b(yesterday|last night|last week|ago|this morning|today|today's|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d{4}-\d{2}-\d{2})\b",
  caseSensitive: false,
);

/// The area a message is about; general when it's unclear (the general set
/// covers logging, planning and making recipes and workouts).
AiArea routeMessage(String text) {
  if (_fix.hasMatch(text) && _logged.hasMatch(text) && _pastDay.hasMatch(text) && !_food.hasMatch(text)) {
    return AiArea.data;
  }
  final counts = {
    AiArea.training: _training.allMatches(text).length,
    AiArea.food: _food.allMatches(text).length,
    AiArea.goals: _goals.allMatches(text).length * 2, // few words, each decisive
  };
  final best = counts.values.fold(0, (a, b) => a > b ? a : b);
  if (best == 0) return AiArea.general;
  final top = [for (final e in counts.entries) if (e.value == best) e.key];
  return top.length == 1 ? top.single : AiArea.general;
}

const _weekdays = {
  'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'tues': 2, 'wednesday': 3, 'wed': 3,
  'thursday': 4, 'thu': 4, 'thur': 4, 'thurs': 4, 'friday': 5, 'fri': 5,
  'saturday': 6, 'sat': 6, 'sunday': 7, 'sun': 7,
};

/// Days from [today] for a day already logged: "today" 0, "yesterday" -1,
/// "the day before yesterday" -2, "Monday" the most recent Monday (0 if it's
/// today), "3 days ago", or "2026-10-01". Null if none.
int? pastDayOffset(String? text, DateTime today) {
  if (text == null) return null;
  final t = text.toLowerCase().trim();
  if (t.isEmpty) return null;
  if (RegExp(r'\bday before yesterday\b').hasMatch(t)) return -2;
  if (RegExp(r'\byesterday\b|\blast night\b').hasMatch(t)) return -1;
  if (RegExp(r'\btoday\b|\btonight\b|\bthis (?:morning|afternoon|evening)\b').hasMatch(t)) return 0;
  final ago = RegExp(r'\b(\d+) days? ago\b').firstMatch(t);
  if (ago != null) return -int.parse(ago.group(1)!);
  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(t);
  if (iso != null) {
    final d = DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    final base = DateTime(today.year, today.month, today.day);
    return (d.difference(base).inHours + (d.isBefore(base) ? -12 : 12)) ~/ 24;
  }
  for (final e in _weekdays.entries) {
    if (RegExp('\\b${e.key}\\b').hasMatch(t)) return -((today.weekday - e.value + 7) % 7);
  }
  return null;
}
