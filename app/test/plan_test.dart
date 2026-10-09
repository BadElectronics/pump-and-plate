import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/catalog.dart';
import 'package:fitapp/src/ai/plan_intents.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/chat_screen.dart';
import 'package:fitapp/src/services/ai_engine.dart';
import 'package:fitapp/src/services/reminders.dart';

void main() {
  final sunday = DateTime(2026, 10, 4); // a Sunday

  test('day words', () {
    expect(daysAheadFrom('today', sunday), 0);
    expect(daysAheadFrom('tomorrow', sunday), 1);
    expect(daysAheadFrom('the day after tomorrow', sunday), 2);
    expect(daysAheadFrom('friday', sunday), 5);
    expect(daysAheadFrom('on Monday', sunday), 1);
    expect(daysAheadFrom('sunday', sunday), 0);
    expect(daysAheadFrom('next sunday', sunday), 7);
    expect(daysAheadFrom('in 3 days', sunday), 3);
    expect(daysAheadFrom('2026-10-09', sunday), 5);
    expect(daysAheadFrom('2026-10-01', sunday), isNull); // in the past
    expect(daysAheadFrom('soon', sunday), isNull);
  });

  test('typed plan commands', () {
    var c = parsePlanCommand('plan push day for tomorrow', sunday)!;
    expect([c.subject, c.daysAhead, c.meal], ['push day', 1, null]);
    c = parsePlanCommand('schedule chicken and rice for dinner on friday', sunday)!;
    expect([c.subject, c.daysAhead, c.meal], ['chicken and rice', 5, 'dinner']);
    c = parsePlanCommand('add oatmeal for breakfast tomorrow', sunday)!;
    expect([c.subject, c.daysAhead, c.meal], ['oatmeal', 1, 'breakfast']);
    c = parsePlanCommand('Add leg day to my calendar for Friday.', sunday)!;
    expect([c.subject, c.daysAhead], ['leg day', 5]);
    expect(parsePlanCommand('add 2 eggs', sunday), isNull); // no day
    expect(parsePlanCommand('should I plan a deload tomorrow?', sunday), isNull);
  });

  testWidgets('a typed plan becomes a card, and planning it confirms', (tester) async {
    ChatScreen.clearHistory();
    await tester.pumpWidget(FitApp(
      store: MemoryStore(const StoredData(
        settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true),
        workouts: [Workout(id: 'w-push', name: 'Push day')],
      )),
      reminders: NoopReminders(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Chat'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'plan push day for tomorrow');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PLAN A WORKOUT'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Push day'), findsOneWidget); // matched and selected
    await tester.ensureVisible(find.text('Plan it'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Plan it'));
    await tester.pump();
    expect(find.text('Planned Push day for tomorrow.'), findsOneWidget);
  });

  group('planning meals', () {
    testWidgets('typed "add an egg tomorrow" plans the egg', (tester) async {
      await _chat(tester);
      await _say(tester, 'add an egg tomorrow');
      expect(find.text('PLAN A MEAL'), findsOneWidget);
      expect(find.text('Eggs, large'), findsOneWidget);
    });

    testWidgets('"plan a meal for tomorrow" opens an empty card to add foods', (tester) async {
      await _chat(tester);
      await _say(tester, 'plan a meal for tomorrow');
      expect(find.text('PLAN A MEAL'), findsOneWidget);
      expect(find.textContaining('No foods yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('plan-add-food')), findsOneWidget);
    });

    testWidgets('the AI sends foods as objects: still a card with the food', (tester) async {
      await _chat(tester, ai: _CallingEngine(const AiCall('plan_meal', {
        'day': 'tomorrow',
        'foods': [
          {'name': 'egg', 'amount': 1},
        ],
      })));
      await _say(tester, 'add an egg to my meal plan for tomorrow please, thanks');
      expect(find.text('PLAN A MEAL'), findsOneWidget);
      expect(find.text('Eggs, large'), findsOneWidget);
      expect(find.textContaining('couldn\'t tell'), findsNothing);
    });

    testWidgets('the AI leaves the foods out: taken from what was typed', (tester) async {
      await _chat(tester, ai: _CallingEngine(const AiCall('plan_meal', {'day': 'tomorrow'})));
      await _say(tester, 'can you add an egg?');
      expect(find.text('PLAN A MEAL'), findsOneWidget);
      expect(find.text('Eggs, large'), findsOneWidget);
    });
  });
}

/// An AI engine whose every answer is one function call.
class _CallingEngine implements AiEngine {
  _CallingEngine(this.call);
  final AiCall call;
  AiTier? _loaded;

  @override
  bool get available => true;
  @override
  Future<bool> isInstalled(AiModelInfo m) async => true;
  @override
  Future<void> download(AiModelInfo m, {required void Function(int percent) onProgress, required AiCancel cancel}) async {}
  @override
  Future<void> importFile(AiModelInfo m, String path) async {}
  @override
  Future<void> remove(AiModelInfo m) async {}
  @override
  Future<AiChat> openChat(AiModelInfo m, {required String system, List<AiTool> tools = const []}) async {
    _loaded = m.tier;
    return _CallingChat(call);
  }
  @override
  AiTier? get loadedTier => _loaded;
  @override
  Future<void> warmUp(AiModelInfo m) async {
    _loaded = m.tier;
  }
  @override
  Future<void> unload() async {
    _loaded = null;
  }
  @override
  Future<void> unloadWhenIdle() => unload();
  @override
  void scheduleIdleUnload(Duration after) {}
  @override
  void cancelIdleUnload() {}
  @override
  Future<void> forceUnload() => unload();
}

class _CallingChat implements AiChat {
  _CallingChat(this.call);
  final AiCall call;
  @override
  Stream<AiEvent> send(String text) => Stream.fromIterable([call]);
  @override
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

Future<void> _chat(WidgetTester tester, {AiEngine? ai}) async {
  ChatScreen.clearHistory();
  await tester.pumpWidget(FitApp(
    store: MemoryStore(StoredData(
      settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiNoticeOff: true, aiTier: ai == null ? null : 'light'),
    )),
    reminders: NoopReminders(),
    ai: ai,
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
  await tester.pump(const Duration(milliseconds: 300));
}
