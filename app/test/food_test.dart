import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/backup.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

Future<AppState> _state() async {
  final s = AppState(MemoryStore(), NoopReminders());
  await s.load();
  return s;
}

void main() {
  test('macros scale with grams', () {
    const chicken = Macros(kcal: 120, protein: 22.5, carbs: 0, fat: 2.6);
    final m = macrosForGrams(chicken, 200);
    expect(m.kcal, 240);
    expect(m.protein, 45);
    expect((m + m).kcal, 480);
  });

  test('starter foods load and logging adds up the day', () async {
    final s = await _state();
    expect(s.food('chicken_breast'), isNotNull);
    final day = DateTime(2030, 1, 7);
    s.logFood(day, Meal.lunch, s.food('chicken_breast')!, 200);
    s.logFood(day, Meal.breakfast, s.food('eggs')!, 100); // two eggs
    s.logQuick(day, Meal.snack, 'Coffee', const Macros(kcal: 40, protein: 2));
    final total = s.eatenOn(day);
    expect(total.kcal, closeTo(240 + 143 + 40, 0.01));
    expect(total.protein, closeTo(45 + 12.6 + 2, 0.01));
    expect(s.entriesOn(day, Meal.lunch).length, 1);
  });

  test('recipes: totals, per serving, logging and editing amounts', () async {
    final s = await _state();
    final r = Recipe(id: 'r1', name: 'Bowl', servings: 2, items: const [
      RecipeItem(foodId: 'chicken_breast', grams: 400),
      RecipeItem(foodId: 'white_rice', grams: 180),
    ]);
    s.saveRecipe(r);
    final total = s.recipeTotals(r);
    expect(total.kcal, closeTo(480 + 657, 0.01));
    expect(s.recipePerServing(r).kcal, closeTo((480 + 657) / 2, 0.01));
    final day = DateTime(2030, 1, 7);
    final e = s.logRecipe(day, Meal.dinner, r, 1);
    expect(e.macros.kcal, closeTo(568.5, 0.01));
    s.updateEntryAmount(e, 1.5);
    expect(s.eatenOn(day).kcal, closeTo(852.75, 0.01));
  });

  test('copy the day before, and delete', () async {
    final s = await _state();
    final mon = DateTime(2030, 1, 7);
    final tue = DateTime(2030, 1, 8);
    s.logFood(mon, Meal.lunch, s.food('banana')!, 118);
    s.logQuick(mon, Meal.snack, 'Bar', const Macros(kcal: 200, protein: 20));
    final added = s.copyDay(mon, tue);
    expect(added.length, 2);
    expect(s.eatenOn(tue).kcal, closeTo(s.eatenOn(mon).kcal, 1e-9));
    s.deleteEntry(added.first);
    expect(s.entriesOn(tue).length, 1);
  });

  test('stores and prices; removing a store removes its prices', () async {
    final s = await _state();
    s.saveStore(const GroceryStore(id: 'st1', name: 'Aldi'));
    final f = s.food('chicken_breast')!;
    s.saveFood(f.copyWith(prices: {'st1': 6.37}));
    expect(s.food('chicken_breast')!.prices['st1'], 6.37);
    s.deleteStore(s.stores.single);
    expect(s.stores, isEmpty);
    expect(s.food('chicken_breast')!.prices, isEmpty);
  });

  test('food data survives a backup', () {
    final data = StoredData(
      foods: const [Food(id: 'f1', name: 'Oats', per100: Macros(kcal: 389, protein: 16.9), prices: {'st1': 4.4})],
      stores: const [GroceryStore(id: 'st1', name: 'Aldi')],
      recipes: const [Recipe(id: 'r1', name: 'Porridge', servings: 1, items: [RecipeItem(foodId: 'f1', grams: 80)])],
      foodLog: [
        FoodEntry(
          id: 'e1',
          date: DateTime(2030, 1, 7),
          meal: Meal.breakfast,
          kind: 'recipe',
          refId: 'r1',
          amount: 1,
          name: 'Porridge',
          macros: const Macros(kcal: 311, protein: 13.5),
        ),
      ],
    );
    final back = decodeBackup(encodeBackup(data));
    expect(back.foods.single.per100.kcal, 389);
    expect(back.foods.single.prices['st1'], 4.4);
    expect(back.stores.single.name, 'Aldi');
    expect(back.recipes.single.items.single.grams, 80);
    expect(back.foodLog.single.meal, Meal.breakfast);
    expect(back.foodLog.single.macros.kcal, 311);
  });
}
