import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/facts.dart';
import 'package:fitapp/src/ai/log_parser.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/chat_screen.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

DateTime _ago(int d) {
  final t = dateOnly(DateTime.now());
  return DateTime(t.year, t.month, t.day - d);
}

Future<void> _chat(WidgetTester tester) async {
  ChatScreen.clearHistory();
  await tester.pumpWidget(FitApp(
    store: MemoryStore(const StoredData(settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true))),
    reminders: NoopReminders(),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Chat'), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _say(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapVisible(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(text));
  await tester.pump();
}

void main() {
  group('reading typed logs', () {
    test('weight', () {
      final w = parseLogIntent('weighed 182.4') as WeightIntent;
      expect([w.value, w.unit, w.daysAgo], [182.4, null, 0]);
      expect((parseLogIntent('Weigh-in 82.5 kg') as WeightIntent).unit, 'kg');
      expect((parseLogIntent('182.4 lb this morning') as WeightIntent).value, 182.4);
    });

    test('sleep', () {
      final a = parseLogIntent('slept 7.5 hours, quality 4') as SleepIntent;
      expect([a.minutes, a.quality, a.daysAgo], [450, 4, 0]);
      expect((parseLogIntent('slept 7h 30m') as SleepIntent).minutes, 450);
      expect((parseLogIntent('got 8 hours of sleep last night') as SleepIntent).daysAgo, 0); // last night = today's entry
      final b = parseLogIntent('Slept 6 hours yesterday 3/5') as SleepIntent;
      expect([b.minutes, b.quality, b.daysAgo], [360, 3, 1]);
    });

    test('food', () {
      final a = parseLogIntent('breakfast: 2 eggs, 1 banana and a coffee') as FoodIntent;
      expect(a.meal, 'breakfast');
      expect(a.items.map((i) => (i.name, i.qty)), [('eggs', 2.0), ('banana', 1.0), ('coffee', 1.0)]);
      final b = parseLogIntent('had chicken and rice for lunch yesterday') as FoodIntent;
      expect([b.meal, b.daysAgo], ['lunch', 1]);
      expect(b.items.map((i) => i.name), ['chicken', 'rice']);
      final c = parseLogIntent('I ate 200g chicken breast and 1 cup rice') as FoodIntent;
      expect(c.items.first.unit, 'g');
      expect(parseLogIntent('had 2 eggs'), isA<FoodIntent>());
    });

    test('not logs', () {
      for (final t in [
        'i had a great workout',
        'ate well today',
        'How much protein should I eat?',
        'bench 3x8 @ 185',
        'dinner was great',
        'Push day\nBench press 3x8',
      ]) {
        expect(parseLogIntent(t), isNull, reason: t);
      }
    });
  });

  group('facts and coaching', () {
    Future<AppState> app() async {
      final s = AppState(MemoryStore(), NoopReminders());
      await s.load();
      s.setSettings(s.settings.copyWith(units: Units.metric, sleepGoalHours: 8));
      return s;
    }

    test('weight facts use the averages and changes', () async {
      final s = await app();
      for (var d = 27; d >= 0; d--) {
        s.logWeight(90 - (27 - d) * 0.1, day: _ago(d)); // down 0.1 kg a day
      }
      final f = weightFacts(s);
      expect(f, contains('Latest weigh-in: 87.3 kg'));
      expect(f, contains('7-day average weight: 87.6 kg'));
      expect(f, contains('Change from the week before: -0.7 kg'));
      expect(f, contains('Weigh-ins in the last 7 days: 7'));
    });

    test('short sleep is found, and stale weigh-ins', () async {
      final s = await app();
      for (var d = 0; d < 6; d++) {
        s.logSleep(SleepEntry(date: _ago(d), durationMin: 6 * 60));
      }
      s.logWeight(80, day: _ago(20));
      expect(sleepFacts(s), contains('average 6.0 h, goal 8.0 h, 6 under goal'));
      final found = coachingFindings(s);
      expect(found, contains('Sleep averaged 6.0 h over the last week, under the 8.0 h goal.'));
      expect(found, contains('No weigh-ins in the last 7 days, so the trend is going stale.'));
    });

    test('questions pick the facts they need', () async {
      final s = await app();
      expect(factsFor(s, 'How did I sleep?'), startsWith('Sleep'));
      expect(factsFor(s, 'What is the capital of France'), isEmpty);
      expect(factsFor(s, 'How am I doing?').split('\n').length, greaterThanOrEqualTo(4));
    });
  });

  group('Chat without a model', () {
    testWidgets('a typed weigh-in is checked, then saved', (tester) async {
      await _chat(tester);
      await _say(tester, 'weighed 82.5 kg');
      expect(find.text('WEIGH-IN'), findsOneWidget);
      await _tapVisible(tester, 'Save weigh-in');
      expect(find.textContaining('Weigh-in saved: 82.5 kg, today.'), findsOneWidget);
    });

    testWidgets('a typed breakfast is matched to foods, then saved', (tester) async {
      await _chat(tester);
      await _say(tester, 'breakfast: 2 eggs, 1 banana');
      expect(find.text('FOOD, TODAY'), findsOneWidget);
      expect(find.text('Eggs, large'), findsOneWidget);
      expect(find.text('Banana'), findsOneWidget);
      await _tapVisible(tester, 'Save to Breakfast');
      expect(find.textContaining('Logged 2 items to Breakfast today'), findsOneWidget);
    });

    testWidgets('a question shows the facts from your data', (tester) async {
      await _chat(tester);
      await _say(tester, 'How did I sleep this week?');
      expect(find.text('FROM YOUR DATA'), findsOneWidget);
      expect(find.textContaining('Sleep: none logged'), findsOneWidget);
    });

    testWidgets('How am I doing? lists what needs attention', (tester) async {
      await _chat(tester);
      await tester.tap(find.text('How am I doing?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('HOW YOU\'RE DOING'), findsOneWidget);
    });
  });
}
