import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/catalog.dart';
import 'package:fitapp/src/ai/matcher.dart';
import 'package:fitapp/src/ai/paste_parser.dart';

const _gb = 1000 * 1000 * 1000;

DeviceSpecs phone(double reportedGb, String soc, {bool arm64 = true, int free = 50 * _gb}) => DeviceSpecs(
      totalRam: (reportedGb * _gb).round(),
      freeStorage: free,
      soc: soc,
      abis: arm64 ? const ['arm64-v8a', 'armeabi-v7a'] : const ['armeabi-v7a'],
    );

void main() {
  group('choosing a model', () {
    test('memory decides the tier, a fast chip unlocks High', () {
      expect(recommendTier(phone(3.7, 'MT6765')).tier, AiTier.light); // "4 GB" budget phone
      expect(recommendTier(phone(7.6, 'SM7450')).tier, AiTier.medium); // "8 GB" mid-range
      expect(recommendTier(phone(11.4, 'SM8650')).tier, AiTier.high); // "12 GB", 8 Gen 3
      expect(recommendTier(phone(11.4, 'SM7450')).tier, AiTier.medium); // "12 GB", mid-range chip
      expect(recommendTier(phone(15.5, 'unknown')).tier, AiTier.high); // "16 GB"
      final old = recommendTier(phone(3.7, 'MT6765', arm64: false));
      expect(old.tier, isNull);
      expect(old.reason, contains('64-bit'));
    });

    test('flagship chips by the codes phones report', () {
      for (final soc in ['SM8550', 'SM8650', 'SM8750', 'Tensor G3', 'Tensor G4', 'MT6989', 's5e9945']) {
        expect(isFlagshipChip(soc), isTrue, reason: soc);
      }
      for (final soc in ['SM8450', 'SM7450', 'Tensor G2', 'MT6877', 's5e8835', '']) {
        expect(isFlagshipChip(soc), isFalse, reason: soc);
      }
      expect(chipName('SM8650', 'QTI'), 'Snapdragon 8 Gen 3');
    });

    test('warns about slow picks and missing space', () {
      expect(tierWarning(AiTier.high, phone(7.6, 'SM7450')), 'Likely slow on this phone.');
      expect(tierWarning(AiTier.medium, phone(7.6, 'SM7450')), isNull);
      expect(tierWarning(AiTier.medium, phone(7.6, 'SM7450', free: 1 * _gb)), contains('Needs about'));
      expect(modelFor(AiTier.medium).sizeLabel, '2.6 GB');
      expect(modelFor(AiTier.light).sizeLabel, '586 MB');
      // Light asks for less context (less memory); the others the full 4096.
      expect([for (final t in downloadTiers) modelFor(t).maxTokens], [2048, 4096, 4096]);
    });
  });

  group('reading pasted recipes', () {
    test('ingredient lines', () {
      var l = parseIngredientLine('1 1/2 cups rolled oats, divided')!;
      expect([l.qty, l.unit, l.name, l.note], [1.5, 'cup', 'rolled oats', 'divided']);
      expect(parseIngredientLine('2 Tbsp butter')!.unit, 'tbsp');
      expect(parseIngredientLine('1 T honey')!.unit, 'tbsp');
      expect(parseIngredientLine('1 t salt')!.unit, 'tsp');
      expect(parseIngredientLine('½ cup milk')!.qty, 0.5);
      expect(parseIngredientLine('1½ cups flour')!.qty, 1.5);
      l = parseIngredientLine('200g chicken breast')!;
      expect([l.qty, l.unit, l.name], [200.0, 'g', 'chicken breast']);
      l = parseIngredientLine('2-3 cloves garlic, minced')!;
      expect([l.qty, l.unit, l.name], [2.5, 'clove', 'garlic']);
      l = parseIngredientLine('1 (14 oz) can diced tomatoes')!;
      expect(l.unit, 'can');
      expect(l.sizeGrams, closeTo(396.9, 0.1));
      expect(parseIngredientLine('2 large eggs')!.unit, isNull);
      expect(parseIngredientLine('Salt to taste'), isNull);
    });

    test('grams, using what is known about the food', () {
      double g(String line, {String food = '', double? each}) =>
          gramsFor(parseIngredientLine(line)!, foodName: food, gramsPerItem: each)!;
      expect(g('1 cup rolled oats', food: 'Rolled oats, dry'), closeTo(86.4, 0.1));
      expect(g('2 tbsp butter'), closeTo(28.4, 0.1));
      expect(g('200 g chicken breast'), 200);
      expect(g('1 (14 oz) can diced tomatoes'), closeTo(396.9, 0.1));
      expect(g('2 eggs'), 100);
      expect(g('1 banana', each: 118), 118);
      expect(gramsFor(parseIngredientLine('10 almonds')!), isNull);
    });

    test('a whole recipe: title, servings, ingredients, steps', () {
      final d = parseRecipe('''
Overnight oats
Serves 2
Ingredients
- 1 cup rolled oats
- 1 cup milk
- 1 banana
- Cinnamon to taste
Directions
1. Mix everything in a jar.
2. Leave in the fridge overnight.
''');
      expect(d.name, 'Overnight oats');
      expect(d.servings, 2);
      expect(d.ingredients.map((i) => i.name), ['rolled oats', 'milk', 'banana']);
      expect(d.skipped, ['Cinnamon to taste']);
      expect(d.steps, ['Mix everything in a jar.', 'Leave in the fridge overnight.']);
    });
  });

  group('reading pasted workouts', () {
    test('exercise lines', () {
      var e = parseExerciseLine('Bench press 3x8 @ 185')!;
      expect([e.name, e.sets, e.repsLow, e.repsHigh, e.load, e.loadUnit], ['Bench press', 3, 8, 8, 185.0, null]);
      e = parseExerciseLine('Bench press: 4 x 6-8 @ 80kg')!;
      expect([e.sets, e.repsLow, e.repsHigh, e.load, e.loadUnit], [4, 6, 8, 80.0, 'kg']);
      e = parseExerciseLine('3 sets of 10 pull-ups')!;
      expect([e.name, e.sets, e.repsLow], ['pull-ups', 3, 10]);
      e = parseExerciseLine('Run 20 min')!;
      expect([e.name, e.minutes, e.sets], ['Run', 20, null]);
      e = parseExerciseLine('Plank 3 x 60s')!;
      expect([e.name, e.sets, e.repsLow], ['Plank', 3, 60]);
      e = parseExerciseLine('Dips 3 x AMRAP')!;
      expect([e.name, e.sets], ['Dips', 3]);
      e = parseExerciseLine('Bench 3x8 185')!; // a plain number after sets x reps is the load
      expect([e.name, e.sets, e.repsLow, e.load], ['Bench', 3, 8, 185.0]);
      expect(parseExerciseLine('T-bar row 3x10 90')!.name, 'T-bar row');
      expect(parseExerciseLine('Upper A'), isNull);
      expect(parseExerciseLine('Squat 5x5 225lb')!.loadKg(imperial: false), closeTo(102.06, 0.01));
      expect(parseExerciseLine('Bench 3x8 @ 100')!.loadKg(imperial: false), 100);
    });

    test('which kind of paste', () {
      expect(classifyPaste('Push day\nBench press 3x8\nDips 3x10'), PasteKind.workout);
      expect(classifyPaste('Oats\n1 cup rolled oats\n1 cup milk'), PasteKind.recipe);
      expect(classifyPaste('How much protein should I eat?'), PasteKind.none);
      expect(classifyPaste('should I do 3 sets of 10?'), PasteKind.none);
      // One line: a pasted exercise, unless it's an instruction for the AI.
      expect(classifyPaste('Bench press 3x8 @ 185'), PasteKind.workout);
      expect(classifyPaste('make bench 4 sets in my push workout'), PasteKind.none);
      expect(classifyPaste('add lateral raises 3x12 to push day'), PasteKind.none);
      expect(parseWorkout('Push day\nBench press 3x8\nDips 3x10').name, 'Push day');
    });
  });

  group('matching names to the library', () {
    final foods = ['Chicken breast', 'Eggs', 'Egg whites', 'Milk', 'Rolled oats', 'Flour tortilla', 'Whey protein powder'];
    final exercises = ['Bench press', 'Incline bench press', 'Pull-up', 'Back squat', 'Romanian deadlift', 'Barbell curl', 'Hammer curl'];
    String? food(String q) => bestMatch<String>(q, foods, (f) => f);
    String? ex(String q) => bestMatch<String>(exerciseQuery(q), exercises, (e) => e);

    test('clear matches are found, unclear ones left to the user', () {
      expect(food('rolled oats'), 'Rolled oats');
      expect(food('large eggs'), 'Eggs');
      expect(food('egg whites'), 'Egg whites');
      expect(food('whey protein'), 'Whey protein powder');
      expect(food('flour'), isNull); // not "Flour tortilla"
      expect(food('chicken'), isNull);
      expect(ex('Bench press'), 'Bench press');
      expect(ex('squats'), 'Back squat');
      expect(ex('Pull-ups'), 'Pull-up');
      expect(ex('RDL'), 'Romanian deadlift');
      expect(ex('hammer curls'), 'Hammer curl');
      expect(ex('Curls'), isNull); // which curl?
      expect(foodMainName('Chicken breast, raw'), 'Chicken breast');
    });
  });
}
