import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/support_screen.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/services/tips.dart';

class _FakeJar implements TipJar {
  final given = <String>[];
  final _out = StreamController<TipOutcome>.broadcast();

  @override
  Future<List<Tip>> tips() async => const [
        Tip(id: 'tip_1', price: r'$1.00', amount: 1),
        Tip(id: 'tip_3', price: r'$3.00', amount: 3),
        Tip(id: 'tip_5', price: r'$5.00', amount: 5),
        Tip(id: 'tip_10', price: r'$10.00', amount: 10),
        Tip(id: 'tip_50', price: r'$50.00', amount: 50),
      ];

  @override
  Future<bool> give(String id) async {
    given.add(id);
    _out.add(TipOutcome.thanks);
    return true;
  }

  @override
  Stream<TipOutcome> get outcomes => _out.stream;
}

Future<void> _open(WidgetTester tester, TipJar? jar) async {
  await tester.pumpWidget(FitApp(
    store: MemoryStore(const StoredData(settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true))),
    reminders: NoopReminders(),
    tips: jar,
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(SupportScreen.route());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('without a store, the tip jar says tips come later', (tester) async {
    await _open(tester, null);
    expect(find.textContaining('Tips aren\'t available yet'), findsOneWidget);
    expect(find.text('Report a bug or suggest a feature'), findsOneWidget);
  });

  testWidgets('quick tips, and any other amount from the list', (tester) async {
    final jar = _FakeJar();
    await _open(tester, jar);
    expect(find.text(r'$3.00'), findsOneWidget);
    expect(find.text(r'$5.00'), findsOneWidget);
    expect(find.text(r'$10.00'), findsOneWidget);
    expect(find.text(r'$50.00'), findsNothing); // only under Other amount
    await tester.tap(find.text(r'$5.00'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(jar.given, ['tip_5']);
    expect(find.textContaining('Thank you!'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5)); // the thank-you goes away
    await tester.tap(find.byKey(const ValueKey('other-tip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('tip-tip_50')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(jar.given, ['tip_5', 'tip_50']);
  });
}
