import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

/// A store that fails like a full phone while [full] is set.
class _FullStore extends MemoryStore {
  _FullStore([super.data]);

  bool full = false;

  void _check() {
    if (full) throw Exception('DatabaseException(database or disk is full (code 13 SQLITE_FULL))');
  }

  @override
  Future<void> saveWeighIn(WeighIn weighIn) async {
    _check();
    return super.saveWeighIn(weighIn);
  }

  @override
  Future<void> deleteWeighIn(DateTime day) async {
    _check();
    return super.deleteWeighIn(day);
  }
}

void main() {
  test('recognises a full phone', () {
    expect(isStorageFull(Exception('database or disk is full (code 13 SQLITE_FULL)')), isTrue);
    expect(isStorageFull('FileSystemException: No space left on device, errno = 28'), isTrue);
    expect(isStorageFull('ENOSPC'), isTrue);
    expect(isStorageFull('database is locked (code 5)'), isFalse);
  });

  test('a failed save is kept, warned about, and written by Try again', () async {
    final store = _FullStore();
    final s = AppState(store, NoopReminders());
    await s.load();
    store.full = true;
    s.logWeight(80);
    await s.settle();
    expect(s.saveProblem, SaveProblem.full);
    expect(s.weighIns, hasLength(1)); // still there in the app

    expect(await s.retrySaves(), isFalse); // still full
    expect(s.saveProblem, SaveProblem.full);

    store.full = false;
    expect(await s.retrySaves(), isTrue);
    expect(s.saveProblem, isNull);
    final again = AppState(store, NoopReminders());
    await again.load();
    expect(again.weighIns, hasLength(1)); // really saved
  });

  test('a deletion made while full is replayed before re-saving', () async {
    final store = _FullStore();
    final s = AppState(store, NoopReminders());
    await s.load();
    final today = DateTime.now();
    s.logWeight(80);
    await s.settle();
    store.full = true;
    s.deleteWeighIn(today); // fails
    s.logWeight(81); // a new one, same day; fails too
    await s.settle();
    store.full = false;
    expect(await s.retrySaves(), isTrue);
    final again = AppState(store, NoopReminders());
    await again.load();
    expect(again.weighIns, hasLength(1));
    expect(again.weighIns.single.weightKg, 81); // the newer one, not the deleted one
  });

  testWidgets('a full phone shows a warning, and Try again saves', (tester) async {
    final store = _FullStore(const StoredData(settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true)));
    await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    store.full = true;
    await tester.enterText(find.byKey(const ValueKey('home-weight')), '180');
    await tester.tap(find.text('Save').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your phone is full'), findsOneWidget);

    store.full = false;
    await tester.tap(find.byKey(const ValueKey('save-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your phone is full'), findsNothing);
    expect(find.text('Saved. Everything is up to date.'), findsOneWidget);
  });
}
