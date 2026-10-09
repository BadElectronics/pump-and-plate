/// Barcodes on food packages (EAN-13, EAN-8, UPC-A, UPC-E) and reading
/// product data from Open Food Facts. No Flutter imports: unit-tested.
library;

import 'calc.dart';

/// Just the digits of a scanned or typed code.
String barcodeDigits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

/// True if the last digit is the right check digit (EAN-8, UPC-A, EAN-13
/// and the 14-digit GTIN all use the same rule). Catches misreads and typos.
bool validCheckDigit(String digits) {
  if (!RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(digits)) return false;
  final body = digits.substring(0, digits.length - 1);
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    // Weights 3,1,3,1... starting from the digit next to the check digit.
    final d = int.parse(body[body.length - 1 - i]);
    sum += i.isEven ? d * 3 : d;
  }
  final check = (10 - sum % 10) % 10;
  return check == int.parse(digits[digits.length - 1]);
}

/// Expands an 8-digit UPC-E code to its 12-digit UPC-A form, or null.
String? upcEToUpcA(String e) {
  if (!RegExp(r'^[01]\d{7}$').hasMatch(e)) return null;
  final ns = e[0];
  final d = e.substring(1, 7);
  final check = e[7];
  final last = d[5];
  String body;
  switch (last) {
    case '0':
    case '1':
    case '2':
      body = '${d.substring(0, 2)}${last}0000${d.substring(2, 5)}';
    case '3':
      body = '${d.substring(0, 3)}00000${d.substring(3, 5)}';
    case '4':
      body = '${d.substring(0, 4)}00000${d[4]}';
    default:
      body = '${d.substring(0, 5)}0000$last';
  }
  return '$ns$body$check';
}

/// The forms the same product can be stored under, most standard first:
/// a 12-digit UPC-A is also the 13-digit EAN with a leading 0, and UPC-E is
/// a compressed UPC-A.
List<String> barcodeVariants(String raw) {
  final d = barcodeDigits(raw);
  final out = <String>[];
  void add(String x) {
    if (x.isNotEmpty && !out.contains(x)) out.add(x);
  }

  if (d.length == 8) {
    final a = upcEToUpcA(d);
    if (a != null && validCheckDigit(a)) {
      add('0$a');
      add(a);
    }
    add(d);
  } else if (d.length == 12) {
    add('0$d');
    add(d);
  } else if (d.length == 13 && d.startsWith('0')) {
    add(d);
    add(d.substring(1));
  } else if (d.length == 14 && d.startsWith('0')) {
    add(d.substring(1));
    add(d);
  } else {
    add(d);
  }
  return out;
}

/// A product as read from Open Food Facts, before you review it.
class ScannedProduct {
  const ScannedProduct({
    required this.barcode,
    required this.name,
    this.brand,
    required this.per100,
    this.servingGrams,
    this.missing = const [],
  });

  final String barcode;
  final String name;
  final String? brand;
  final Macros per100;
  final double? servingGrams;

  /// Nutrition values the database didn't have (shown so you can fill them in).
  final List<String> missing;
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

/// Reads an Open Food Facts v2 product response. Returns null if the
/// product wasn't found.
ScannedProduct? parseOpenFoodFacts(Map<String, Object?> json, String barcode) {
  if (json['status'] != 1 && json['status'] != '1') return null;
  final p = json['product'];
  if (p is! Map) return null;
  final n = p['nutriments'] is Map ? p['nutriments'] as Map : const {};
  final missing = <String>[];

  var kcal = _num(n['energy-kcal_100g']);
  if (kcal == null) {
    // Some products only list kilojoules.
    final kj = _num(n['energy-kj_100g']) ?? _num(n['energy_100g']);
    if (kj != null) kcal = kj / 4.184;
  }
  final protein = _num(n['proteins_100g']);
  final carbs = _num(n['carbohydrates_100g']);
  final fat = _num(n['fat_100g']);
  if (kcal == null) missing.add('calories');
  if (protein == null) missing.add('protein');
  if (carbs == null) missing.add('carbs');
  if (fat == null) missing.add('fat');

  String? text(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  final name = text(p['product_name']) ?? text(p['product_name_en']) ?? text(p['generic_name']);
  final brands = text(p['brands']);
  final brand = brands?.split(',').first.trim();
  var serving = _num(p['serving_quantity']);
  final unit = text(p['serving_quantity_unit'])?.toLowerCase();
  if (serving != null && unit != null && unit != 'g' && unit != 'ml') serving = null;
  if (serving != null && (serving <= 0 || serving > 2000)) serving = null;

  return ScannedProduct(
    barcode: barcode,
    name: name ?? (brand == null ? 'Scanned food' : '$brand product'),
    brand: brand,
    per100: Macros(
      kcal: (kcal ?? 0).roundToDouble(),
      protein: _round1(protein ?? 0),
      carbs: _round1(carbs ?? 0),
      fat: _round1(fat ?? 0),
    ),
    servingGrams: serving,
    missing: missing,
  );
}

double _round1(double v) => (v * 10).round() / 10;
