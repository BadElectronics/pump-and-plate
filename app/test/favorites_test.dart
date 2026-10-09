import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

void main() {
  DateTime day(int ago) {
    final t = dateOnly(DateTime.now());
    return DateTime(t.year, t.month, t.day - ago);
  }

  test('one meal is copied, into the meal and day chosen', () async {
    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    s.logQuick(day(1), Meal.breakfast, 'Oats', const Macros(kcal: 300, protein: 10));
    s.logQuick(day(1), Meal.breakfast, 'Milk', const Macros(kcal: 120, protein: 8));
    s.logQuick(day(1), Meal.dinner, 'Steak', const Macros(kcal: 600, protein: 50));
    final added = s.copyMeal(day(1), Meal.breakfast, day(0), Meal.lunch);
    expect(added.map((e) => e.name), ['Oats', 'Milk']);
    final today = s.entriesOn(day(0));
    expect(today.map((e) => e.meal).toSet(), {Meal.lunch});
    expect(today.any((e) => e.name == 'Steak'), isFalse); // other meals stay put
    expect(s.copyMeal(day(5), Meal.snack, day(0), Meal.snack), isEmpty);
  });

  test('favourite foods are saved and listed by name', () async {
    final store = MemoryStore();
    final s = AppState(store, NoopReminders());
    await s.load();
    final picks = s.foods.take(2).toList();
    s.setFavorite(picks[1], true);
    s.setFavorite(picks[0], true);
    expect(s.favoriteFoods.map((f) => f.name), [picks[0].name, picks[1].name]..sort());
    s.setFavorite(s.food(picks[0].id)!, false);
    expect(s.favoriteFoods.single.id, picks[1].id);
    await s.settle();
    final again = AppState(store, NoopReminders());
    await again.load();
    expect(again.favoriteFoods.single.id, picks[1].id);
    const f = Food(id: 'f', name: 'X', per100: Macros(kcal: 1), favorite: true);
    expect(Food.fromRow(f.toRow()).favorite, isTrue);
  });
}
