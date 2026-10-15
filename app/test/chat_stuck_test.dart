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

/// A model that answers with the given stream of text pieces.
class _TextEngine implements AiEngine {
  _TextEngine(this.pieces);
  final List<String> pieces;
  final chat = _TextChat();
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
    chat.pieces = pieces;
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

class _TextChat implements AiChat {
  List<String> pieces = const [];
  bool stopped = false;
  int sent = 0;
  @override
  Stream<AiEvent> send(String text) async* {
    for (final p in pieces) {
      if (stopped) return;
      sent++;
      yield AiText(p);
    }
  }
  @override
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result) => const Stream.empty();
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> close() async {}
}

Future<_TextChat> _ask(WidgetTester tester, List<String> pieces) async {
  final store = MemoryStore(const StoredData(
    settings: AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, aiTier: 'light', aiNoticeOff: true),
  ));
  final engine = _TextEngine(pieces);
  ChatScreen.clearHistory();
  await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders(), ai: engine));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('Chat'), warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.enterText(find.byKey(const ValueKey('chat-input')), 'add a snack tomorrow');
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return engine.chat;
}

void main() {
  testWidgets('a model stuck repeating a token is stopped and explained', (tester) async {
    final chat = await _ask(tester, List.filled(400, '<channel>'));
    expect(chat.stopped, isTrue);
    expect(chat.sent, lessThan(400), reason: 'stopped early');
    expect(find.textContaining('got stuck repeating itself'), findsOneWidget);
    expect(find.textContaining('<channel>'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stray control tokens are hidden from a normal answer', (tester) async {
    final chat = await _ask(tester, ['<|channel>', 'Sure, ', 'a snack ', 'tomorrow.', '<end_of_turn>']);
    expect(chat.stopped, isFalse);
    expect(find.textContaining('Sure, a snack tomorrow.'), findsOneWidget);
    expect(find.textContaining('channel'), findsNothing);
    expect(find.textContaining('end_of_turn'), findsNothing);
  });

  testWidgets('an ordinary long answer is left alone', (tester) async {
    final chat = await _ask(tester, [for (var i = 0; i < 60; i++) 'Word$i ']);
    expect(chat.stopped, isFalse);
    expect(find.textContaining('got stuck'), findsNothing);
  });
}
