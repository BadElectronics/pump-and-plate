import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../config.dart';

/// One tip amount, as the store prices it ("$5.00", or the local currency).
class Tip {
  const Tip({required this.id, required this.price, required this.amount});

  final String id;
  final String price;

  /// For sorting cheapest first.
  final double amount;
}

enum TipOutcome { thanks, pending, failed, cancelled }

/// The tip jar. Tips go through Google Play (or the App Store); the app
/// never sees card details.
abstract class TipJar {
  /// The tips the store offers, cheapest first. Empty when the store isn't
  /// reachable or no tips are set up yet.
  Future<List<Tip>> tips();

  /// Opens the store's payment sheet. False if it couldn't open.
  Future<bool> give(String id);

  /// What happened after [give]: thanks once it's paid, and so on.
  Stream<TipOutcome> get outcomes;
}

/// Through Google Play Billing / StoreKit.
///
/// Nothing here touches the store until the tip jar is opened: the first
/// [tips] call starts Google Play Billing (or StoreKit). Google's billing
/// library sends Google its own diagnostics once it starts, so people who
/// never open the tip jar never start it. A tip left unfinished (the app
/// closed mid-payment) is completed the next time the tip jar opens.
class StoreTipJar implements TipJar {
  StoreTipJar();

  final _out = StreamController<TipOutcome>.broadcast();
  final _details = <String, ProductDetails>{};
  // Kept for the life of the app once the tip jar has been opened.
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Whether the store has been started (for tests).
  bool get started => _sub != null;

  /// Starts the store the first time it's needed.
  InAppPurchase _store() {
    final store = InAppPurchase.instance;
    _sub ??= store.purchaseStream.listen(_onUpdate, onError: (Object _) {});
    return store;
  }

  @override
  Stream<TipOutcome> get outcomes => _out.stream;

  @override
  Future<List<Tip>> tips() async {
    try {
      final store = _store();
      if (!await store.isAvailable()) return const [];
      final r = await store.queryProductDetails(tipProductIds.toSet());
      final list = <Tip>[];
      for (final p in r.productDetails) {
        _details[p.id] = p;
        list.add(Tip(id: p.id, price: p.price, amount: p.rawPrice));
      }
      list.sort((a, b) => a.amount.compareTo(b.amount));
      return list;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> give(String id) async {
    final p = _details[id];
    if (p == null) return false;
    try {
      // A tip can be given again, so it's used up right away.
      return await _store().buyConsumable(purchaseParam: PurchaseParam(productDetails: p));
    } catch (_) {
      return false;
    }
  }

  Future<void> _onUpdate(List<PurchaseDetails> updates) async {
    for (final p in updates) {
      final status = p.status;
      if (status == PurchaseStatus.purchased) {
        _out.add(TipOutcome.thanks);
      } else if (status == PurchaseStatus.pending) {
        _out.add(TipOutcome.pending);
      } else if (status == PurchaseStatus.error) {
        _out.add(TipOutcome.failed);
      } else if (status == PurchaseStatus.canceled) {
        _out.add(TipOutcome.cancelled);
      }
      if (p.pendingCompletePurchase) {
        try {
          await _store().completePurchase(p);
        } catch (_) {}
      }
    }
  }
}

/// For tests and builds without a store: no tips on offer.
class NoTipJar implements TipJar {
  const NoTipJar();

  @override
  Future<List<Tip>> tips() async => const [];

  @override
  Future<bool> give(String id) async => false;

  @override
  Stream<TipOutcome> get outcomes => const Stream.empty();
}
