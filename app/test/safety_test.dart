import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/catalog.dart';
import 'package:fitapp/src/ai/safety.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/chat_screen.dart';
import 'package:fitapp/src/services/ai_engine.dart';
import 'package:fitapp/src/services/reminders.dart';

/// A model that records whether it was ever asked anything.
class _CountingEngine implements AiEngine {
  final chat = _CountingChat();
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
    chat.system = system;
    return chat;
  }
  @override
  AiTier? get loadedTier => _loaded;
  @override
  Future<void> warmUp(AiModelInfo m) async => _loaded = m.tier;
  @override
  Future<void> unload() async => _loaded = null;
  @override
  Future<void> unloadWhenIdle() => unload();
  @override
  void scheduleIdleUnload(Duration after) {}
  @override
  void cancelIdleUnload() {}
  @override
  Future<void> forceUnload() => unload();
}

class _CountingChat implements AiChat {
  int asked = 0;
  String system = '';
  @override
  Stream<AiEvent> send(String text) async* {
    asked++;
    yield const AiText('Sure, here you go.');
  }
  @override
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

Future<_CountingEngine> _say(WidgetTester tester, String message) async {
  final store = MemoryStore(const StoredData(
    settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true),
  ));
  final engine = _CountingEngine();
  ChatScreen.clearHistory();
  await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders(), ai: engine));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Chat'), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.enterText(find.byKey(const ValueKey('chat-input')), message);
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return engine;
}

void main() {
  group('the check', () {
    const selfHarm = [
      'I want to kill myself',
      'thinking about suicide lately',
      "I'm suicidal",
      "I've been self-harming again",
      "I don't want to live anymore",
      'i wanna die',
      'sometimes I wish I was dead',
      'how many pills to overdose on',
    ];
    const eating = [
      'I make myself throw up after dinner',
      'how do I purge after a binge',
      "I'm starving myself to lose weight",
      'should I take laxatives',
      'plan me 500 calories a day',
      'I want to eat 600 kcal per day',
    ];
    const gymTalk = [
      'leg day killed me',
      'this set is going to kill me',
      "I'm dying after that workout",
      'killing it today',
      'did suicide sprints at practice',
      'we ran suicides',
      'I hurt my shoulder',
      "I'm in a cutting phase",
      'eat 1,500 calories a day',
      'eat 2000 calories a day',
      'ran 5 kms',
      '300 calories for breakfast',
      'deadlift 315 for 3',
      'starving after the gym',
      'I hurt myself deadlifting',
      'log 2 eggs for breakfast',
    ];
    for (final t in selfHarm) {
      test('self-harm: "$t"', () => expect(checkMessage(t), SafetyConcern.selfHarm));
    }
    for (final t in eating) {
      test('eating: "$t"', () => expect(checkMessage(t), SafetyConcern.eatingDisorder));
    }
    for (final t in gymTalk) {
      test('left alone: "$t"', () => expect(checkMessage(t), SafetyConcern.none));
    }
    test('curly apostrophes are read too', () => expect(checkMessage('I don’t want to live'), SafetyConcern.selfHarm));
  });

  group('the messages', () {
    test('self-harm lists 988 by call and text, and somewhere outside North America', () {
      final m = crisisMessage(SafetyConcern.selfHarm);
      final urls = [for (final c in m.contacts) c.url];
      expect(urls, containsAll(['tel:988', 'sms:988', 'https://findahelpline.com']));
    });
    test('eating lists the National Alliance for Eating Disorders, not NEDA', () {
      final m = crisisMessage(SafetyConcern.eatingDisorder);
      expect(m.contacts.first.url, 'tel:+18666621235');
      expect(m.contacts.map((c) => c.detail).join(' '), contains('National Alliance for Eating Disorders'));
      expect(m.contacts.map((c) => '${c.label} ${c.detail}').join(' ').toLowerCase(), isNot(contains('neda')));
    });
    test('the model is told the same thing as a backstop', () {
      expect(safetyInstruction, contains('988'));
      expect(safetyInstruction, contains('findahelpline.com'));
    });
  });

  testWidgets('a self-harm message never reaches the model and shows 988', (tester) async {
    final engine = await _say(tester, 'I want to kill myself');
    expect(engine.chat.asked, 0);
    expect(find.byKey(const ValueKey('safety-card')), findsOneWidget);
    expect(find.text('Call 988'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an eating-disorder message never reaches the model', (tester) async {
    final engine = await _say(tester, 'plan me 500 calories a day');
    expect(engine.chat.asked, 0);
    expect(find.text('Call (866) 662-1235'), findsOneWidget);
  });

  testWidgets('ordinary gym talk still goes to the model, with the safety instruction', (tester) async {
    final engine = await _say(tester, 'leg day killed me, what should I eat?');
    expect(engine.chat.asked, 1);
    expect(engine.chat.system, contains('988'));
    expect(find.byKey(const ValueKey('safety-card')), findsNothing);
  });
}
