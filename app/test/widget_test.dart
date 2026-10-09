import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/screens/chat_screen.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/widgets/common.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

Future<void> _open(WidgetTester tester, {bool onboarded = true}) async {
  await tester.pumpWidget(FitApp(
    store: MemoryStore(StoredData(settings: AppSettings(onboarded: onboarded, nicknameAsked: true, tourSeen: true))),
    reminders: NoopReminders(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Taps a slice on Home and waits for the pie to fold into the tab bar.
/// The labels pass touches through to the pie (which works out the slice
/// from where you tapped), so the "would not hit test" check doesn't apply.
Future<void> _go(WidgetTester tester, String section) async {
  await tester.tap(find.text(section), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Taps a section in the tab bar (when already inside a section).
Future<void> _bar(WidgetTester tester, String section) async {
  await tester.tap(find.text(section).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _home(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.home_rounded));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Scrolls the current screen's list until [target] is built and visible,
/// then lets the scroll settle: a list that's still gliding ignores taps.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 250, scrollable: find.byType(Scrollable).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Finder _field(String key) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));

void main() {
  testWidgets('opens on Home with the pie, the greeting and the check-ins', (tester) async {
    await _open(tester);
    for (final label in ['Log', 'Progress', 'Plan', 'Food', 'Settings', 'Chat']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining(', it is '), findsOneWidget);
    expect(find.text('Weigh-in'), findsOneWidget);
    expect(find.text('Last night'), findsOneWidget);
  });

  testWidgets('a slice opens its section, and Home folds it back', (tester) async {
    await _open(tester);
    await _go(tester, 'Progress');
    // Progress opens on Overview: weight first, then strength, sleep and photos.
    expect(find.text('Estimated 1RM'), findsOneWidget);
    expect(find.text('No progress photos yet.'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    await _home(tester);
    expect(find.textContaining(', it is '), findsOneWidget);
  });

  testWidgets('Chat turns a pasted workout into a draft and saves it', (tester) async {
    ChatScreen.clearHistory();
    await _open(tester);
    await _go(tester, 'Chat');
    expect(find.text('Paste a workout'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Push day\nBench press 3x8 @ 185\nOverhead press 3x10 @ 95\nPush-ups 3x15',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('WORKOUT DRAFT'), findsOneWidget);
    expect(find.text('Bench press'), findsOneWidget);
    expect(find.text('Overhead press'), findsOneWidget);
    expect(find.text('Push-up'), findsOneWidget);
    await tester.ensureVisible(find.text('Save workout'));
    // The scroll lands on the next frame; tap after it, not at the old spot.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save workout'));
    await tester.pump();
    expect(find.text('Saved "Push day" to Plan > Workouts.'), findsOneWidget);
  });

  testWidgets('Chat turns a pasted recipe into a draft with grams', (tester) async {
    ChatScreen.clearHistory();
    await _open(tester);
    await _go(tester, 'Chat');
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Oat bowl\nServes 2\n1 cup rolled oats\n1 cup milk\n1 banana',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('RECIPE DRAFT'), findsOneWidget);
    expect(find.text('Rolled oats, dry'), findsOneWidget);
    expect(find.text('86 g'), findsOneWidget);
    expect(find.text('Milk, 2%'), findsOneWidget);
    expect(find.text('Banana'), findsOneWidget);
    expect(find.text('118 g'), findsOneWidget);
    await tester.ensureVisible(find.text('Save recipe'));
    // The scroll lands on the next frame; tap after it, not at the old spot.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save recipe'));
    await tester.pump();
    expect(find.text('Saved "Oat bowl" to Food > Recipes.'), findsOneWidget);
  });

  testWidgets('Chat explains when on-device AI is unavailable', (tester) async {
    ChatScreen.clearHistory();
    await _open(tester);
    await _go(tester, 'Chat');
    // A general question (not about your data, which gets a facts card instead).
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'What is a good warm-up?');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    // Tests run without an AI engine, like a phone where it can't start.
    expect(find.textContaining('isn\'t available on this phone'), findsOneWidget);
  });

  testWidgets('Settings switches themes, including Emerald, and units', (tester) async {
    await _open(tester);
    await _go(tester, 'Settings');
    expect(find.text('Emerald'), findsOneWidget);
    await tester.tap(find.text('Emerald'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Night'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Night'), findsOneWidget);
    // Units sit further down; once scrolled there, the theme row is no
    // longer built, so check the units switch itself.
    await _scrollTo(tester, find.text('kg, cm'));
    await tester.tap(find.text('kg, cm'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('kg, cm'), findsOneWidget);
  });

  testWidgets('Home weigh-in saves a weight', (tester) async {
    await _open(tester);
    await tester.enterText(_field('home-weight'), '182.4');
    await tester.tap(find.text('Save').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('182.4 lb'), findsOneWidget);
  });

  testWidgets('Home sleep asks how you slept after the hours', (tester) async {
    await _open(tester);
    await tester.enterText(_field('home-sleep'), '7.5');
    await tester.tap(find.text('Save').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('How did you sleep?'), findsOneWidget);
    await tester.tap(find.text('4'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('quality 4 of 5 (good)'), findsOneWidget);
  });

  testWidgets('first run shows setup, and Skip goes to Home', (tester) async {
    await _open(tester, onboarded: false);
    expect(find.text('Skip setup'), findsOneWidget);
    await tester.tap(find.text('Skip setup'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Weigh-in'), findsOneWidget);
  });

  testWidgets('Log opens with weight, sleep and the rest, due items first', (tester) async {
    await _open(tester);
    await _go(tester, 'Log');
    for (final t in ['Weight', 'Sleep', 'Food', 'Workout', 'Progress photos']) {
      expect(find.text(t), findsWidgets);
    }
    expect(find.text('Due now'), findsWidgets);
    expect(find.text('After the bathroom, before eating or drinking.'), findsOneWidget);
  });

  testWidgets('Progress switches to Sleep and Photos', (tester) async {
    await _open(tester);
    await _go(tester, 'Progress');
    await tester.tap(find.descendant(of: find.byType(IconTabs), matching: find.text('Sleep')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('morning check-in'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(IconTabs), matching: find.text('Photos')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start guided photos'), findsOneWidget);
  });

  testWidgets('body measurements are off until turned on', (tester) async {
    await _open(tester);
    await _go(tester, 'Progress');
    expect(find.text('Body'), findsNothing);
    await _bar(tester, 'Settings');
    final toggle = find.byKey(const ValueKey('measurements-toggle'));
    await _scrollTo(tester, toggle);
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 300));
    await _bar(tester, 'Progress');
    await tester.tap(find.descendant(of: find.byType(IconTabs), matching: find.text('Body')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log measurements'), findsOneWidget);
  });

  testWidgets('Plan > Workouts adds the starter plan', (tester) async {
    await _open(tester);
    await _go(tester, 'Plan');
    await tester.tap(find.descendant(of: find.byType(IconTabs), matching: find.text('Workouts')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No workouts yet'), findsOneWidget);
    await tester.tap(find.text('Add the upper/lower plan'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Upper A'), findsOneWidget);
    expect(find.text('Lower B'), findsOneWidget);
  });

  testWidgets('Plan opens on the month calendar, with week and today views', (tester) async {
    await _open(tester);
    await _go(tester, 'Plan');
    final now = DateTime.now();
    expect(find.text('Add workouts'), findsOneWidget);
    expect(find.text('Add meals'), findsOneWidget);
    expect(find.text('${_monthNames[now.month - 1]} ${now.year}'), findsOneWidget);
    await tester.tap(find.text('Week'));
    await tester.pump(const Duration(milliseconds: 300));
    await _scrollTo(tester, find.text('Copy last week'));
    expect(find.text('Copy last week'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byType(IconTabs), matching: find.text('Today')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Meals'), findsOneWidget);
  });

  testWidgets('the month view pages to the next month', (tester) async {
    await _open(tester);
    await _go(tester, 'Plan');
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1, 1);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('${_monthNames[next.month - 1]} ${next.year}'), findsOneWidget);
  });

  testWidgets('a workout from the tray can be tapped onto a day', (tester) async {
    await _open(tester);
    await _go(tester, 'Plan');
    await tester.tap(find.descendant(of: find.byType(IconTabs), matching: find.text('Workouts')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add the upper/lower plan'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(of: find.byType(IconTabs), matching: find.text('Calendar')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Add workouts'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Upper A'));
    await tester.pump(const Duration(milliseconds: 200));
    await _scrollTo(tester, find.text('15'));
    await tester.tap(find.text('15'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Added Upper A'), findsOneWidget);
    // Let the Undo bar's 5-second timer finish before the test ends.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Food opens on Groceries with the guide and your own lists', (tester) async {
    await _open(tester);
    await _go(tester, 'Food');
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Recipes'), findsOneWidget);
    expect(find.text('Foods'), findsOneWidget);
    expect(find.text('Let your list fill itself'), findsOneWidget);
    await _scrollTo(tester, find.text('Custom checklist'));
    expect(find.text('From your foods'), findsOneWidget);
  });

  testWidgets('the custom checklist adds an item', (tester) async {
    await _open(tester);
    await _go(tester, 'Food');
    await _scrollTo(tester, find.text('Custom checklist'));
    await tester.tap(find.text('Custom checklist'));
    // A pushed screen is built hidden for its first frame (so shared-element
    // animations can measure it), then shown on the next: pump twice.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const ValueKey('checklist-new')), 'Paper towels');
    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paper towels'), findsOneWidget);
  });

  testWidgets('existing installs are asked once for an optional nickname', (tester) async {
    await tester.pumpWidget(FitApp(
      store: MemoryStore(StoredData(settings: const AppSettings(onboarded: true))),
      reminders: NoopReminders(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300)); // dialog opens after the first frame
    expect(find.text('What should we call you?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Sam');
    await tester.tap(find.text('Save').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining(' Sam, it is '), findsOneWidget);
    expect(find.textContaining(', Sam'), findsNothing);
  });

  Future<void> settleTour(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  }

  Future<void> openForTour(WidgetTester tester) async {
    await tester.pumpWidget(FitApp(
      store: MemoryStore(StoredData(settings: const AppSettings(onboarded: true, nicknameAsked: true))),
      reminders: NoopReminders(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300)); // the tour starts after the first frame
  }

  testWidgets('the app tour shows once on Home and can be skipped', (tester) async {
    await openForTour(tester);
    expect(find.text('Welcome to Pump and Plate'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await settleTour(tester);
    expect(find.text('Welcome to Pump and Plate'), findsNothing);
  });

  testWidgets('the tour walks through every step, then replays from Settings', (tester) async {
    await openForTour(tester);
    await tester.tap(find.text('Show me'));
    await settleTour(tester);
    expect(find.text('This is Home'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.text('Next'));
      await settleTour(tester);
    }
    expect(find.text('Every morning'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await settleTour(tester);
    expect(find.text('Free for everyone'), findsOneWidget);
    expect(find.byKey(const ValueKey('tour-tip')), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settleTour(tester);
    expect(find.text('Free for everyone'), findsNothing);

    await _go(tester, 'Settings');
    await tester.tap(find.byKey(const ValueKey('replay-tour')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Welcome to Pump and Plate'), findsOneWidget);
  });
}
