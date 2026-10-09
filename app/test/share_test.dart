import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/food_share.dart';
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
  test('a share carries recipes, their foods and extra foods, without prices', () async {
    final s = await _state();
    s.setSettings(s.settings.copyWith(nickname: 'Sam'));
    final sauce = Food(
      id: 'f-sauce',
      name: 'Peanut sauce',
      per100: const Macros(kcal: 400, protein: 12),
      prices: const {'st1': 9.99},
      custom: true,
    );
    s.saveFood(sauce);
    final r = Recipe(id: 'r1', name: 'Satay bowl', servings: 2, items: const [
      RecipeItem(foodId: 'chicken_breast', grams: 400),
      RecipeItem(foodId: 'f-sauce', grams: 60),
    ]);
    s.saveRecipe(r);
    final text = s.shareFoods(recipes: [r]);
    expect(text.contains('9.99'), isFalse);
    final share = decodeFoodShare(text);
    expect(share.from, 'Sam');
    expect(share.recipes.single.items.length, 2);
    expect(share.foods.map((f) => f.name).toSet(), {'Chicken breast, raw', 'Peanut sauce'});
  });

  test('importing reuses foods by name and skips recipes you already have', () async {
    final friend = await _state();
    friend.saveFood(const Food(id: 'x1', name: 'Peanut sauce', per100: Macros(kcal: 400), custom: true));
    final r1 = Recipe(id: 'a', name: 'Satay bowl', servings: 2, items: const [
      RecipeItem(foodId: 'chicken_breast', grams: 400),
      RecipeItem(foodId: 'x1', grams: 60),
    ]);
    const r2 = Recipe(id: 'b', name: 'Oats', servings: 1, items: [RecipeItem(foodId: 'oats', grams: 80)]);
    friend.saveRecipe(r1);
    friend.saveRecipe(r2);
    final share = decodeFoodShare(friend.shareFoods(recipes: [r1, r2]));

    final me = await _state();
    me.saveRecipe(const Recipe(id: 'mine', name: 'oats', servings: 1)); // same name, different case
    final foodsBefore = me.foods.length;
    final result = me.importFoodShare(share);
    expect(result.recipes, 1);
    expect(result.skippedRecipes, 1);
    expect(result.foods, 1); // only the peanut sauce is new
    expect(me.foods.length, foodsBefore + 1);
    final bowl = me.recipes.firstWhere((x) => x.name == 'Satay bowl');
    expect(bowl.items.first.foodId, 'chicken_breast'); // reused my starter food
    expect(me.food(bowl.items.last.foodId)!.name, 'Peanut sauce');
    expect(me.recipes.firstWhere((x) => x.id == 'mine').items, isEmpty); // mine untouched
  });

  test('friendly errors for the wrong kind of file', () {
    expect(() => decodeFoodShare('nope'), throwsA(isA<FoodShareError>()));
    expect(
      () => decodeFoodShare('{"app":"fitapp","format":1,"profile":{}}'),
      throwsA(isA<FoodShareError>().having((e) => e.message, 'message', contains('full Pump and Plate backup'))),
    );
  });
}
