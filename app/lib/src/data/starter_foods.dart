import '../calc/calc.dart';
import 'models.dart';

Food _f(String id, String name, double kcal, double p, double c, double f,
        {double? each}) =>
    Food(
      id: id,
      name: name,
      per100: Macros(kcal: kcal, protein: p, carbs: c, fat: f),
      byItem: each != null,
      gramsPerItem: each,
    );

/// Common foods with typical values per 100 g (raw unless noted).
/// Brands vary, so labels win when they differ.
final starterFoods = <Food>[
  // Protein
  _f('chicken_breast', 'Chicken breast, raw', 120, 22.5, 0, 2.6),
  _f('chicken_thigh', 'Chicken thigh, skinless, raw', 121, 19.7, 0, 4.1),
  _f('ground_beef_90', 'Ground beef 90/10, raw', 176, 20, 0, 10),
  _f('ground_turkey_93', 'Ground turkey 93/7, raw', 150, 18.7, 0, 8.3),
  _f('salmon', 'Salmon fillet, raw', 208, 20.4, 0, 13.4),
  _f('shrimp', 'Shrimp, raw', 85, 20.1, 0, 0.5),
  _f('tuna_can', 'Tuna, canned in water, drained', 116, 25.5, 0, 0.8),
  _f('pork_loin', 'Pork loin, raw', 143, 21.1, 0, 5.9),
  _f('eggs', 'Eggs, large', 143, 12.6, 0.7, 9.5, each: 50),
  _f('egg_whites', 'Egg whites', 52, 10.9, 0.7, 0.2),
  _f('tofu_firm', 'Tofu, firm', 144, 17.3, 2.8, 8.7),
  _f('whey', 'Whey protein powder', 400, 80, 8, 6),
  // Dairy
  _f('greek_yogurt_0', 'Greek yogurt, nonfat', 59, 10.3, 3.6, 0.4),
  _f('milk_2', 'Milk, 2%', 50, 3.3, 4.8, 2),
  _f('cottage_cheese_2', 'Cottage cheese, 2%', 81, 10.5, 4.8, 2.3),
  _f('cheddar', 'Cheddar cheese', 403, 24.9, 1.3, 33.1),
  _f('butter', 'Butter', 717, 0.9, 0.1, 81.1),
  // Grains and starches (dry unless noted)
  _f('oats', 'Rolled oats, dry', 389, 16.9, 66.3, 6.9),
  _f('white_rice', 'White rice, dry', 365, 7.1, 80, 0.7),
  _f('jasmine_rice', 'Jasmine rice, dry', 360, 7, 79, 0.6),
  _f('brown_rice', 'Brown rice, dry', 370, 7.9, 77.2, 2.9),
  _f('pasta', 'Pasta, dry', 371, 13, 74.7, 1.5),
  _f('bread_ww', 'Whole wheat bread', 252, 12.5, 42.7, 3.5),
  _f('tortilla', 'Flour tortilla', 304, 8, 50, 7.5),
  _f('potato', 'Potatoes (Yukon or russet)', 77, 2, 17.5, 0.1),
  _f('sweet_potato', 'Sweet potato', 86, 1.6, 20.1, 0.1),
  _f('granola', 'Granola', 471, 10, 64, 20),
  _f('lentils', 'Lentils, dry', 352, 24.6, 63.4, 1.1),
  _f('black_beans', 'Black beans, canned, drained', 91, 6, 16.6, 0.3),
  // Vegetables
  _f('broccoli', 'Broccoli', 34, 2.8, 6.6, 0.4),
  _f('green_beans', 'Green beans', 31, 1.8, 7, 0.2),
  _f('spinach', 'Spinach', 23, 2.9, 3.6, 0.4),
  _f('bell_pepper', 'Bell pepper', 31, 1, 6, 0.3),
  _f('onion', 'Onion', 40, 1.1, 9.3, 0.1),
  _f('tomato', 'Tomato', 18, 0.9, 3.9, 0.2),
  _f('cucumber', 'Cucumber', 15, 0.7, 3.6, 0.1),
  // Fruit
  _f('banana', 'Banana', 89, 1.1, 22.8, 0.3, each: 118),
  _f('apple', 'Apple', 52, 0.3, 13.8, 0.2, each: 182),
  _f('orange', 'Orange', 47, 0.9, 11.8, 0.1, each: 131),
  _f('blueberries', 'Blueberries', 57, 0.7, 14.5, 0.3),
  _f('strawberries', 'Strawberries', 32, 0.7, 7.7, 0.3),
  _f('avocado', 'Avocado', 160, 2, 8.5, 14.7, each: 150),
  // Fats, nuts, extras
  _f('olive_oil', 'Olive oil', 884, 0, 0, 100),
  _f('peanut_butter', 'Peanut butter', 588, 25.1, 20, 50.4),
  _f('almonds', 'Almonds', 579, 21.2, 21.6, 49.9),
  _f('honey', 'Honey', 304, 0.3, 82.4, 0),
];
