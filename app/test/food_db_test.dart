import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/backup.dart';
import 'package:fitapp/src/data/food_share.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/data/usda.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

void main() {
  // The real bundled file, read straight from the project.
  final foods = parseUsdaFile(utf8.decode(gzip.decode(File('assets/foods/usda_sr28.tsv.gz').readAsBytesSync())));

  test('the bundled foods load, accents and all', () {
    expect(foods.length, greaterThan(8000));
    // The data's only accented text is a portion ("1 Entrée"): it must survive.
    expect(foods.any((f) => f.servingLabel.contains('é')), isTrue);
    final chicken = foods.firstWhere((f) => f.name == 'Chicken, broilers or fryers, breast, meat only, cooked, roasted');
    expect([chicken.per100.kcal, chicken.per100.protein], [165, 31]);
    expect(chicken.servingGrams, 140);
  });

  test('a search puts the plain, everyday food first', () {
    String top(String q) => searchUsda(foods, q).first.name;
    expect(top('egg'), 'Egg, whole, raw, fresh');
    expect(top('chicken breast'), allOf(contains('breast'), contains('raw'), isNot(contains('breaded'))));
    expect(top('almonds'), 'Nuts, almonds');
    expect(top('banana'), 'Bananas, raw');
    expect(top('olive oil'), startsWith('Oil, olive'));
    expect(top('greek yogurt'), startsWith('Yogurt, Greek, plain'));
    expect(searchUsda(foods, 'zzzzqx'), isEmpty);
  });

  test('a built-in food becomes yours once, with fiber, sugar and sodium', () async {
    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    final oats = searchUsda(foods, 'rolled oats').first;
    final a = s.foodFromUsda(oats);
    final b = s.foodFromUsda(oats);
    expect(b.id, a.id); // no duplicate
    expect(a.fiber, oats.fiber);
    expect(a.sodiumMg, oats.sodiumMg);
    expect(a.servingGrams, oats.servingGrams);
    expect(a.sourceId, 'usda:${oats.id}');
  });

  test('the new food fields survive saving, backups and sharing', () {
    const f = Food(
      id: 'f1', name: 'Oats', per100: Macros(kcal: 379, protein: 13), fiber: 10.1, sugar: 1, sodiumMg: 6,
      sourceId: 'usda:08120', custom: true,
    );
    final row = Food.fromRow(f.toRow());
    expect([row.fiber, row.sugar, row.sodiumMg, row.sourceId], [10.1, 1.0, 6.0, 'usda:08120']);
    expect(decodeBackup(encodeBackup(const StoredData(foods: [f]))).foods.single.fiber, 10.1);
    expect(decodeFoodShare(encodeFoodShare(foods: const [f], recipes: const [])).foods.single.sodiumMg, 6);
    expect(const AppSettings().onlineFoodSearch, isFalse); // off by default
    expect(AppSettings.fromRow(const AppSettings().copyWith(onlineFoodSearch: true).toRow()).onlineFoodSearch, isTrue);
  });
}
