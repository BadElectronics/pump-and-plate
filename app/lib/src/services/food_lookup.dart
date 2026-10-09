import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../calc/barcode.dart';
import '../config.dart';

enum LookupStatus { found, notFound, offline, failed }

class LookupResult {
  const LookupResult(this.status, [this.product]);
  final LookupStatus status;
  final ScannedProduct? product;
}

/// Why an online food search didn't work.
class FoodSearchFailure implements Exception {
  const FoodSearchFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Looks a barcode up in Open Food Facts. Only the barcode number is sent.
class OpenFoodFactsLookup {
  const OpenFoodFactsLookup();

  static const _fields =
      'product_name,product_name_en,generic_name,brands,nutriments,serving_quantity,serving_quantity_unit';

  /// Branded products matching [query] (only the search words are sent).
  Future<List<ScannedProduct>> search(String query) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.https('world.openfoodfacts.org', '/cgi/search.pl', {
        'search_terms': query,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '20',
        'fields': 'code,$_fields',
      });
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      req.headers.set(HttpHeaders.userAgentHeader, '${appName.replaceAll(' ', '')}/1.0 ($openFoodFactsContact)');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw const FoodSearchFailure('The online search didn\'t work this time.');
      final json = jsonDecode(body);
      final products = json is Map && json['products'] is List ? json['products'] as List : const [];
      return [
        for (final p in products)
          if (p is Map && p['code'] is String)
            if (parseOpenFoodFacts({'status': 1, 'product': p}, p['code'] as String) case final ScannedProduct sp)
              if (!sp.missing.contains('calories')) sp,
      ];
    } on SocketException {
      throw const FoodSearchFailure('You\'re offline, so online search isn\'t available.');
    } on TimeoutException {
      throw const FoodSearchFailure('The online search took too long. Try again.');
    } on FoodSearchFailure {
      rethrow;
    } catch (_) {
      throw const FoodSearchFailure('The online search didn\'t work this time.');
    } finally {
      client.close(force: true);
    }
  }

  Future<LookupResult> byBarcode(String code) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      // The database may hold a product under any of its forms (13-digit
      // EAN, 12-digit UPC, or an 8-digit EAN-8 that also reads as UPC-E).
      for (final variant in barcodeVariants(code)) {
        final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$variant.json?fields=$_fields');
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
        // A user-agent name can't contain spaces ("Pump and Plate" -> "PumpandPlate").
        req.headers.set(HttpHeaders.userAgentHeader, '${appName.replaceAll(' ', '')}/1.0 ($openFoodFactsContact)');
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final res = await req.close().timeout(const Duration(seconds: 10));
        final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
        if (res.statusCode == 404) continue; // not found under this form
        if (res.statusCode != 200) return const LookupResult(LookupStatus.failed);
        final json = jsonDecode(body);
        if (json is! Map<String, Object?>) return const LookupResult(LookupStatus.failed);
        final product = parseOpenFoodFacts(json, variant);
        if (product != null) return LookupResult(LookupStatus.found, product);
      }
      return const LookupResult(LookupStatus.notFound);
    } on SocketException {
      return const LookupResult(LookupStatus.offline);
    } on TimeoutException {
      return const LookupResult(LookupStatus.offline);
    } on HttpException {
      return const LookupResult(LookupStatus.failed);
    } on FormatException {
      return const LookupResult(LookupStatus.failed);
    } catch (_) {
      return const LookupResult(LookupStatus.failed);
    } finally {
      client.close(force: true);
    }
  }
}
