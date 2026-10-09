import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/usda.dart';

const usdaAsset = 'assets/foods/usda_sr28.tsv.gz';

/// The foods built into the app (USDA), loaded once on first search.
class FoodDatabase {
  FoodDatabase._();

  static List<UsdaEntry>? _index;
  static Future<List<UsdaEntry>>? _loading;

  static bool get loaded => _index != null;

  /// All the built-in foods (about 8,000) with their search words, read and
  /// prepared off the UI thread, once.
  static Future<List<UsdaEntry>> index() {
    if (_index != null) return Future.value(_index);
    return _loading ??= () async {
      final data = await rootBundle.load(usdaAsset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final list = await compute(_decode, bytes);
      _index = list;
      return list;
    }();
  }

  static Future<List<UsdaFood>> search(String query, {int limit = 25}) async =>
      searchUsdaIndex(await index(), query, limit: limit);
}

/// The file is UTF-8 (names like "jalapeño"), so it's decoded as UTF-8.
List<UsdaEntry> _decode(Uint8List gz) => indexUsda(parseUsdaFile(utf8.decode(gzip.decode(gz))));
