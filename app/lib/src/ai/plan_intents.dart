/// Putting a workout or a meal on a day: "plan push day for tomorrow",
/// "schedule chicken and rice for dinner on Friday". The AI's plan_workout
/// and plan_meal calls become the same intents.
/// No Flutter imports: unit-tested.
library;

import 'paste_parser.dart';

sealed class PlanIntent {
  const PlanIntent(this.daysAhead);

  /// 0 = today, 1 = tomorrow...
  final int daysAhead;
}

class PlanWorkoutIntent extends PlanIntent {
  const PlanWorkoutIntent(this.name, int daysAhead) : super(daysAhead);

  /// The workout as named (matched to the user's workouts on the card).
  final String name;
}

class PlanMealIntent extends PlanIntent {
  const PlanMealIntent({this.items = const [], this.recipe, this.meal, required int daysAhead}) : super(daysAhead);
  final List<IngredientLine> items;

  /// A recipe's name, when planning a recipe rather than single foods.
  final String? recipe;

  /// 'breakfast', 'lunch', 'dinner' or 'snack'.
  final String? meal;
}

const _weekdays = {
  'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'tues': 2, 'wednesday': 3, 'wed': 3,
  'thursday': 4, 'thu': 4, 'thur': 4, 'thurs': 4, 'friday': 5, 'fri': 5,
  'saturday': 6, 'sat': 6, 'sunday': 7, 'sun': 7,
};

/// Days from [today] for "today", "tomorrow", "the day after tomorrow",
/// "Friday", "next Monday", "in 3 days" or "2026-10-09". Null if none.
int? daysAheadFrom(String? text, DateTime today) {
  if (text == null) return null;
  final t = text.toLowerCase().trim();
  if (t.isEmpty) return null;
  if (RegExp(r'\bday after tomorrow\b').hasMatch(t)) return 2;
  if (RegExp(r'\btomorrow\b').hasMatch(t)) return 1;
  if (RegExp(r'\btoday\b|\btonight\b|\bthis (?:morning|afternoon|evening)\b').hasMatch(t)) return 0;
  final inDays = RegExp(r'\bin (\d+) days?\b').firstMatch(t);
  if (inDays != null) return int.parse(inDays.group(1)!);
  final iso = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(t);
  if (iso != null) {
    final d = DateTime(int.parse(iso.group(1)!), int.parse(iso.group(2)!), int.parse(iso.group(3)!));
    final base = DateTime(today.year, today.month, today.day);
    final diff = ((d.difference(base).inHours + 12) ~/ 24); // whole days, safe across clock changes
    return diff < 0 ? null : diff;
  }
  for (final e in _weekdays.entries) {
    if (RegExp('\\b${e.key}\\b').hasMatch(t)) {
      var n = (e.value - today.weekday + 7) % 7;
      if (n == 0 && RegExp(r'\bnext\b').hasMatch(t)) n = 7;
      return n;
    }
  }
  return null;
}

String? _mealIn(String t) {
  final m = RegExp(r'\b(breakfast|lunch|dinner|supper|snacks?)\b', caseSensitive: false).firstMatch(t);
  if (m == null) return null;
  final w = m.group(1)!.toLowerCase();
  if (w == 'supper') return 'dinner';
  return w.startsWith('snack') ? 'snack' : w;
}

/// A typed plan command, split into what to plan, the day and any meal.
class PlanCommand {
  const PlanCommand(this.subject, this.daysAhead, this.meal);
  final String subject;
  final int daysAhead;
  final String? meal;
}

final _dayWords =
    r'(?:today|tonight|tomorrow|the day after tomorrow|day after tomorrow|(?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|in \d+ days?|\d{4}-\d{2}-\d{2})';

/// "plan push day for tomorrow", "schedule leg day on Friday", "add oatmeal
/// for breakfast tomorrow". Null unless it starts with plan/schedule/add
/// and names a day.
PlanCommand? parsePlanCommand(String text, DateTime today) {
  final t = text.trim().replaceAll(RegExp(r'[.!]+$'), '');
  if (t.contains('?') || t.contains('\n')) return null;
  final m = RegExp(r'^(?:please\s+)?(?:can you\s+)?(?:plan|schedule|add|put)\s+(.+)$', caseSensitive: false).firstMatch(t);
  if (m == null) return null;
  var rest = m.group(1)!;
  final day = RegExp('\\b(?:for|on)?\\s*$_dayWords\\b', caseSensitive: false).firstMatch(rest);
  if (day == null) return null;
  final days = daysAheadFrom(day.group(0), today);
  if (days == null) return null;
  final meal = _mealIn(rest);
  rest = rest.replaceRange(day.start, day.end, ' ');
  final subject = rest
      .replaceAll(RegExp(r'\b(?:for|as|at)\s+(?:breakfast|lunch|dinner|supper|snacks?|a snack)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(?:to|on|in|into)\s+(?:my\s+)?(?:calendar|plan|schedule)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(?:workout|a workout)\b$', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^(?:a|an|my|the)\s+', caseSensitive: false), '')
      .trim();
  if (subject.isEmpty) return null;
  return PlanCommand(subject, days, meal);
}
