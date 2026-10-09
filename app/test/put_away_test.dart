import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/catalog.dart';
import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/screens/chat_screen.dart';
import 'package:fitapp/src/services/ai_engine.dart';
import 'package:fitapp/src/services/reminders.dart';

class _FakeChat implements AiChat {
  @override
  Stream<AiEvent> send(String text) => Stream.fromIterable(const [AiText('Hi')]);
  @override
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

/// An engine the test controls; [hang] makes "put away" never finish.
class _FakeEngine implements AiEngine {
  _FakeEngine({this.hang = false});
  final bool hang;
  AiTier? _loaded;
  int forced = 0;

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
    return _FakeChat();
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
  Future<void> forceUnload() {
    forced++;
    if (hang) return Completer<void>().future; // never finishes
    _loaded = null;
    return Future.value();
  }
}

Future<void> _openChat(WidgetTester tester, _FakeEngine ai, {MemoryStore? store}) async {
  ChatScreen.clearHistory();
  await tester.pumpWidget(FitApp(
    store: store ??
        MemoryStore(const StoredData(
          settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true),
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

void main() {
  testWidgets('Chat warns that the AI is experimental until told not to', (tester) async {
    final store = MemoryStore(const StoredData(
      settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light'),
    ));
    await _openChat(tester, _FakeEngine(), store: store);
    expect(find.text('The AI is experimental'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-notice-off')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-notice-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The AI is experimental'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100)); // let the save finish
    final saved = await store.load();
    expect(saved.settings.aiNoticeOff, isTrue);
  });

  testWidgets('Put AI away frees the model and says so', (tester) async {
    final ai = _FakeEngine();
    await _openChat(tester, ai);
    expect(ai.loadedTier, AiTier.light); // warmed up when Chat opened
    await tester.tap(find.byKey(const ValueKey('ai-put-away')));
    await tester.pump();
    await tester.pump();
    expect(ai.forced, 1);
    expect(ai.loadedTier, isNull);
    expect(find.textContaining('AI put away'), findsOneWidget);
  });

  testWidgets('if the engine is stuck, it offers to restart the app', (tester) async {
    final ai = _FakeEngine(hang: true);
    await _openChat(tester, ai);
    await tester.tap(find.byKey(const ValueKey('ai-put-away')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The AI isn\'t responding'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-wait'))); // never "Restart" in a test
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('The AI isn\'t responding'), findsNothing);
  });
}
