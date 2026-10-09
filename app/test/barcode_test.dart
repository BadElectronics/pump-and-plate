import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/calc/barcode.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/backup.dart';
import 'package:fitapp/src/data/food_share.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

void main() {
  test('check digits catch misreads', () {
    expect(validCheckDigit('3017624010701'), isTrue); // EAN-13
    expect(validCheckDigit('737628064502'), isTrue); // UPC-A
    expect(validCheckDigit('96385074'), isTrue); // EAN-8
    expect(validCheckDigit('3017624010702'), isFalse); // last digit wrong
    expect(validCheckDigit('12345'), isFalse);
  });

  test('UPC-E expands to UPC-A, and the same product matches in every form', () {
    expect(upcEToUpcA('04252614'), '042100005264');
    expect(upcEToUpcA('01234565'), '012345000065');
    expect(barcodeVariants('737628064502'), ['0737628064502', '737628064502']);
    expect(barcodeVariants('0737628064502'), ['0737628064502', '737628064502']);
    expect(barcodeVariants('04252614'), contains('0042100005264'));
    expect(barcodeVariants(' 3017-6240 10701 '), ['3017624010701']);
    // An 8-digit code starting 0 or 1 reads as UPC-E too, but its own
    // EAN-8 form must still be among the forms looked up.
    expect(barcodeVariants('04252614'), ['0042100005264', '042100005264', '04252614']);
    expect(barcodeVariants('96385074'), ['96385074']); // EAN-8 only
  });

  test('reads an Open Food Facts product, filling calories from kilojoules', () {
    final p = parseOpenFoodFacts({
      'status': 1,
      'product': {
        'product_name': 'Greek yogurt, plain',
        'brands': 'Fage, Total',
        'serving_quantity': 170,
        'serving_quantity_unit': 'g',
        'nutriments': {'energy-kj_100g': 418.4, 'proteins_100g': 10.3, 'carbohydrates_100g': 3.6},
      },
    }, '5201054017081');
    expect(p, isNotNull);
    expect(p!.name, 'Greek yogurt, plain');
    expect(p.brand, 'Fage');
    expect(p.per100.kcal, 100);
    expect(p.per100.protein, 10.3);
    expect(p.servingGrams, 170);
    expect(p.missing, ['fat']);
    expect(parseOpenFoodFacts({'status': 0}, '1'), isNull);
  });

  test('a scanned UPC finds the food saved under its EAN form', () async {
    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    s.saveFood(const Food(
      id: 'f-snack',
      name: 'Snack bar',
      per100: Macros(kcal: 400),
      barcode: '0737628064502',
      servingGrams: 40,
      custom: true,
    ));
    expect(s.foodByBarcode('737628064502')?.id, 'f-snack');
    expect(s.foodByBarcode('0737628064502')?.id, 'f-snack');
    expect(s.foodByBarcode('3017624010701'), isNull);
  });

  test('barcode, brand and serving survive saving, backups and food shares', () async {
    const f = Food(
      id: 'f1',
      name: 'Oat bar',
      brand: 'Acme',
      per100: Macros(kcal: 410, protein: 9),
      barcode: '3017624010701',
      servingGrams: 45,
      custom: true,
    );
    final row = Food.fromRow(f.toRow());
    expect(row.barcode, '3017624010701');
    expect(row.brand, 'Acme');
    expect(row.servingGrams, 45);

    final back = decodeBackup(encodeBackup(StoredData(
      foods: const [f],
      settings: const AppSettings(barcodeOnline: false),
    )));
    expect(back.foods.single.barcode, '3017624010701');
    expect(back.settings.barcodeOnline, isFalse);
    expect(decodeBackup(encodeBackup(const StoredData())).settings.barcodeOnline, isNull);

    final share = decodeFoodShare(encodeFoodShare(foods: const [f], recipes: const []));
    expect(share.foods.single.barcode, '3017624010701');
    expect(share.foods.single.servingGrams, 45);
  });
}
