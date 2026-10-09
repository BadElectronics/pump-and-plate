import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/exercise_library_screen.dart';
import 'package:fitapp/src/services/reminders.dart';

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FitApp(
    store: MemoryStore(const StoredData(settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true))),
    reminders: NoopReminders(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  tester.state<NavigatorState>(find.byType(Navigator).first).push(ExerciseLibraryScreen.route());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('groups start closed and open with a tap', (tester) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('group-Chest')), findsOneWidget);
    expect(find.text('Pec deck'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-Chest')));
    await tester.pump();
    expect(find.text('Pec deck'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-Chest')));
    await tester.pump();
    expect(find.text('Pec deck'), findsNothing);
  });

  testWidgets('search and the equipment filter open every group', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField).first, 'preacher');
    await tester.pump();
    expect(find.text('Preacher curl'), findsOneWidget);
    expect(find.text('Dumbbell preacher curl'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('kit-Cable')));
    await tester.pump();
    expect(find.text('Cable curl'), findsOneWidget);
    expect(find.text('Barbell curl'), findsNothing);
  });
}
