import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/data/backup.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/supplements_screen.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';
import 'package:fitapp/src/theme/app_theme.dart';
import 'package:fitapp/src/theme/tokens.dart';

void main() {
  test('doses: amounts as you take them, history kept when removed', () async {
    final store = MemoryStore();
    final s = AppState(store, NoopReminders());
    await s.load();
    s.saveSupplement(const Supplement(id: 'd', name: 'Vitamin D', amount: 2000, unit: 'IU'));
    s.saveSupplement(const Supplement(id: 'c', name: 'Creatine', amount: 5, unit: 'g'));
    expect(s.activeSupplements.map((x) => x.name), ['Vitamin D', 'Creatine']);
    expect(s.supplement('d')!.dose, '2000 IU');
    expect(doseText(2, 'capsule'), '2 capsules');
    expect(doseText(1, 'scoop'), '1 scoop');
    expect(doseText(null, ''), '');

    final today = DateTime.now();
    final d = s.takeSupplement(s.supplement('d')!);
    expect(s.doseOf(s.supplement('d')!, today), isNotNull);
    expect(s.dosesOn(today), hasLength(1));

    // Changing the amount later doesn't rewrite what was taken.
    s.saveSupplement(s.supplement('d')!.copyWith(amount: 4000.0));
    expect(s.dosesOn(today).single.dose, '2000 IU');

    // Removed with history: off the list, but the day still shows it.
    s.removeSupplement(s.supplement('d')!);
    expect(s.activeSupplements.map((x) => x.name), ['Creatine']);
    expect(s.dosesOn(today).single.name, 'Vitamin D');
    s.removeDose(d);
    expect(s.dosesOn(today), isEmpty);

    // Removed without history: gone.
    s.removeSupplement(s.supplement('c')!);
    expect(s.supplement('c'), isNull);

    await Future<void>.delayed(Duration.zero);
    final saved = await store.load();
    expect(saved.supplements.single.active, isFalse);
  });

  test('supplements survive a backup', () async {
    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    s.saveSupplement(const Supplement(id: 'm', name: 'Magnesium', amount: 400, unit: 'mg'));
    s.takeSupplement(s.supplement('m')!);
    final back = decodeBackup(encodeBackup(s.snapshot));
    expect(back.supplements.single.name, 'Magnesium');
    expect(back.doses.single.dose, '400 mg');
  });

  testWidgets('add one and tick it off', (tester) async {
    final s = AppState(MemoryStore(), NoopReminders());
    await s.load();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(AppPalette.earth),
      home: AppScope(state: s, child: const Scaffold(body: SupplementsScreen())),
    ));
    await tester.tap(find.byKey(const ValueKey('add-supplement')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byKey(const ValueKey('supplement-name')), 'Fish oil');
    await tester.tap(find.text('capsule'));
    await tester.pump();
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('supplement-amount')), matching: find.byType(TextField)), '2');
    await tester.tap(find.byKey(const ValueKey('save-supplement')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final x = s.activeSupplements.single;
    expect([x.name, x.dose], ['Fish oil', '2 capsules']);
    await tester.tap(find.byKey(ValueKey('supplement-${x.id}')));
    await tester.pump();
    expect(s.doseOf(x, DateTime.now()), isNotNull);
  });
}
