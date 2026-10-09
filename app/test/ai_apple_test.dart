import 'dart:async';
import 'dart:convert';

import 'package:fitapp/src/ai/catalog.dart';
import 'package:fitapp/src/services/ai_apple.dart';
import 'package:fitapp/src/services/ai_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the iPhone code: records calls and plays back events.
class _FakeBridge implements AppleAiBridge {
  _FakeBridge({this.statusText = 'available'});

  String? statusText;
  final calls = <String>[];
  final _events = StreamController<Map<Object?, Object?>>.broadcast();
  Map<String, Object?>? openedWith;

  /// What to play back after a send or tool result: (session, turn) → events.
  List<Map<String, Object?>> Function(String session, int turn, String what)? script;

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  void _play(String session, int turn, String what) {
    final events = script?.call(session, turn, what) ?? const [];
    scheduleMicrotask(() {
      for (final e in events) {
        _events.add({'session': session, 'turn': turn, ...e});
      }
    });
  }

  void push(Map<Object?, Object?> e) => _events.add(e);

  @override
  Future<String?> status() async => statusText;

  @override
  Future<void> open(String session, {required String instructions, required List<Map<String, Object?>> tools, required double temperature}) async {
    calls.add('open $session');
    openedWith = {'instructions': instructions, 'tools': tools, 'temperature': temperature};
  }

  @override
  Future<void> prewarm(String session) async => calls.add('prewarm $session');

  @override
  Future<void> send(String session, String text, int turn) async {
    calls.add('send $session $turn $text');
    _play(session, turn, text);
  }

  @override
  Future<void> toolResult(String session, String json, int turn) async {
    calls.add('toolResult $session $turn $json');
    _play(session, turn, 'tool');
  }

  @override
  Future<void> stop(String session) async => calls.add('stop $session');

  @override
  Future<void> close(String session) async => calls.add('close $session');
}

Future<List<AiEvent>> _all(Stream<AiEvent> s) => s.toList();

void main() {
  group('Apple model status', () {
    test('reads every status the iPhone code sends', () {
      expect(appleStatusFrom('available'), AppleAiStatus.available);
      expect(appleStatusFrom('notEnabled'), AppleAiStatus.notEnabled);
      expect(appleStatusFrom('notReady'), AppleAiStatus.notReady);
      expect(appleStatusFrom('notEligible'), AppleAiStatus.notEligible);
      expect(appleStatusFrom('unsupported'), AppleAiStatus.unsupported);
      expect(appleStatusFrom(null), AppleAiStatus.unsupported);
    });

    test('offered only where it works now or can after a setting or a wait', () {
      expect(AppleAiStatus.available.offered, isTrue);
      expect(AppleAiStatus.notEnabled.offered, isTrue);
      expect(AppleAiStatus.notReady.offered, isTrue);
      expect(AppleAiStatus.notEligible.offered, isFalse);
      expect(AppleAiStatus.unsupported.offered, isFalse);
      expect(AppleAiStatus.available.help, isNull);
      expect(AppleAiStatus.notEnabled.help, contains('Apple Intelligence'));
    });

    test('Apple\'s model is a built-in tier that is never downloaded', () {
      final m = modelFor(AiTier.apple);
      expect(m.family, 'apple');
      expect(m.builtIn, isTrue);
      expect(m.sizeLabel, 'built in');
      expect(downloadTiers, isNot(contains(AiTier.apple)));
      expect(tierByName('apple'), AiTier.apple);
    });
  });

  group('Function parameters for Apple', () {
    test('properties become an ordered list with required flags', () {
      final s = appleSchema({
        'type': 'object',
        'properties': {
          'workout': {'type': 'string', 'description': 'The name'},
          'day': {'type': 'string'},
          'sets': {'type': 'integer'},
        },
        'required': ['workout', 'day'],
      });
      expect(s['type'], 'object');
      final props = s['properties']! as List;
      expect([for (final p in props) (p as Map)['name']], ['workout', 'day', 'sets']);
      expect([for (final p in props) (p as Map)['required']], [true, true, false]);
      expect(((props.first as Map)['schema'] as Map)['description'], 'The name');
      expect(((props.last as Map)['schema'] as Map)['type'], 'integer');
    });

    test('enums and arrays carry over', () {
      final s = appleSchema({
        'type': 'object',
        'properties': {
          'meal': {'type': 'string', 'enum': ['breakfast', 'lunch']},
          'items': {'type': 'array', 'items': {'type': 'string'}},
        },
      });
      final props = s['properties']! as List;
      expect(((props.first as Map)['schema'] as Map)['enum'], ['breakfast', 'lunch']);
      expect((((props.last as Map)['schema'] as Map)['items'] as Map)['type'], 'string');
      // Nothing listed as required: all optional.
      expect([for (final p in props) (p as Map)['required']], [false, false]);
    });
  });

  group('Chatting with Apple\'s model', () {
    test('streams text and ends on done', () async {
      final bridge = _FakeBridge()
        ..script = (s, t, what) => [
              {'type': 'text', 'text': 'Hi'},
              {'type': 'text', 'text': ' there'},
              {'type': 'done'},
            ];
      final engine = AppleAiEngine(bridge: bridge);
      await engine.refreshAppleStatus();
      final chat = await engine.openChat(modelFor(AiTier.apple), system: 'Be brief.', tools: const [
        AiTool(name: 'log_water', description: 'Log water', parameters: {
          'type': 'object',
          'properties': {'ml': {'type': 'integer'}},
          'required': ['ml'],
        }),
      ]);
      expect(engine.loadedTier, AiTier.apple);
      expect(bridge.openedWith!['instructions'], 'Be brief.');
      final tools = bridge.openedWith!['tools']! as List;
      expect((tools.single as Map)['name'], 'log_water');
      final events = await _all(chat.send('hello'));
      expect([for (final e in events) (e as AiText).text].join(), 'Hi there');
    });

    test('a function call ends the stream; the tool result continues the answer', () async {
      final bridge = _FakeBridge()
        ..script = (s, t, what) => what == 'tool'
            ? [
                {'type': 'text', 'text': 'Ready to confirm.'},
                {'type': 'done'},
              ]
            : [
                {'type': 'call', 'name': 'log_water', 'args': jsonEncode({'ml': 500})},
              ];
      final engine = AppleAiEngine(bridge: bridge);
      await engine.refreshAppleStatus();
      final chat = await engine.openChat(modelFor(AiTier.apple), system: '');
      final first = await _all(chat.send('I drank 500 ml'));
      final call = first.single as AiCall;
      expect(call.name, 'log_water');
      expect(call.args, {'ml': 500});
      final second = await _all(chat.sendToolResult('log_water', {'status': 'shown'}));
      expect((second.single as AiText).text, 'Ready to confirm.');
      expect(bridge.calls.where((c) => c.startsWith('toolResult')).single, contains('"status":"shown"'));
    });

    test('events from an earlier answer are ignored', () async {
      final bridge = _FakeBridge()
        ..script = (s, t, what) => [
              {'type': 'text', 'text': 'new'},
              {'type': 'done'},
            ];
      final engine = AppleAiEngine(bridge: bridge);
      await engine.refreshAppleStatus();
      final chat = await engine.openChat(modelFor(AiTier.apple), system: '');
      // A late event from turn 0 (before this chat's first message).
      bridge.push({'session': 'chat0', 'turn': 0, 'type': 'text', 'text': 'stale'});
      final events = await _all(chat.send('hi'));
      expect([for (final e in events) (e as AiText).text], ['new']);
    });

    test('an error becomes a readable failure', () async {
      final bridge = _FakeBridge()
        ..script = (s, t, what) => [
              {'type': 'error', 'message': 'This conversation got too long for Apple\'s model.'},
            ];
      final engine = AppleAiEngine(bridge: bridge);
      await engine.refreshAppleStatus();
      final chat = await engine.openChat(modelFor(AiTier.apple), system: '');
      await expectLater(chat.send('hi').toList(), throwsA(isA<AiFailure>()));
    });

    test('stop ends the answer being read', () async {
      final bridge = _FakeBridge()..script = (s, t, what) => const [];
      final engine = AppleAiEngine(bridge: bridge);
      await engine.refreshAppleStatus();
      final chat = await engine.openChat(modelFor(AiTier.apple), system: '');
      final pending = chat.send('hi').toList();
      await Future<void>.delayed(Duration.zero);
      await chat.stop();
      expect(await pending, isEmpty);
      expect(bridge.calls, contains('stop chat0'));
    });

    test('opening fails with the reason when Apple Intelligence is off', () async {
      final engine = AppleAiEngine(bridge: _FakeBridge(statusText: 'notEnabled'));
      await engine.refreshAppleStatus();
      expect(engine.available, isTrue);
      // Still counts as set up, so the choice isn't forgotten.
      expect(await engine.isInstalled(modelFor(AiTier.apple)), isTrue);
      await expectLater(
        engine.openChat(modelFor(AiTier.apple), system: ''),
        throwsA(isA<AiFailure>().having((e) => e.message, 'message', contains('Apple Intelligence'))),
      );
    });

    test('unload closes every conversation', () async {
      final bridge = _FakeBridge();
      final engine = AppleAiEngine(bridge: bridge);
      await engine.refreshAppleStatus();
      await engine.openChat(modelFor(AiTier.apple), system: '');
      await engine.unload();
      expect(engine.loadedTier, isNull);
      expect(bridge.calls, contains('close chat0'));
    });
  });

  group('Apple plus downloads', () {
    test('each model goes to its own engine', () async {
      final apple = AppleAiEngine(bridge: _FakeBridge());
      await apple.refreshAppleStatus();
      final combined = CombinedAiEngine(downloads: const NoAiEngine(), apple: apple);
      expect(combined.available, isTrue);
      expect(combined.downloadsAvailable, isFalse);
      expect(combined.appleStatus, AppleAiStatus.available);
      expect(await combined.isInstalled(modelFor(AiTier.apple)), isTrue);
      expect(await combined.isInstalled(modelFor(AiTier.medium)), isFalse);
      await combined.openChat(modelFor(AiTier.apple), system: '');
      expect(combined.loadedTier, AiTier.apple);
    });

    test('an older iPhone offers only the downloads', () async {
      final apple = AppleAiEngine(bridge: _FakeBridge(statusText: 'notEligible'));
      await apple.refreshAppleStatus();
      final combined = CombinedAiEngine(downloads: const NoAiEngine(), apple: apple);
      expect(combined.appleStatus.offered, isFalse);
      expect(combined.available, isFalse);
    });
  });

  group('iPhone details', () {
    test('model codes become names and chips', () {
      final d = DeviceSpecs.fromMap({
        'totalRam': 8 * 1024 * 1024 * 1024,
        'freeStorage': 50 * 1000 * 1000 * 1000,
        'soc': '',
        'socMaker': 'Apple',
        'model': 'iPhone16,1',
        'brand': 'Apple',
        'abis': ['arm64'],
      });
      expect(d.model, 'iPhone 15 Pro');
      expect(d.chipLabel, 'Apple A17 Pro');
      expect(d.supported, isTrue);
      expect(isFlagshipChip(d.soc), isTrue);
      expect(recommendTier(d).tier, AiTier.medium);
    });

    test('newer iPhones than the list still count as fast', () {
      final info = iPhoneFor('iPhone19,2')!;
      expect(info.name, 'iPhone (iPhone19,2)');
      expect(isFlagshipChip(info.chip), isTrue);
      expect(iPhoneFor('SM-S928B'), isNull);
    });

    test('a 12 GB recent iPhone can run High; a 6 GB one gets Light', () {
      DeviceSpecs phone(String code, int gb) => DeviceSpecs.fromMap({
            'totalRam': gb * 1000 * 1000 * 1000,
            'freeStorage': 0,
            'socMaker': 'Apple',
            'model': code,
            'brand': 'Apple',
            'abis': ['arm64'],
          });
      expect(recommendTier(phone('iPhone18,1', 12)).tier, AiTier.high);
      expect(recommendTier(phone('iPhone15,2', 6)).tier, AiTier.light);
      expect(isFlagshipChip('Apple A16'), isFalse);
    });

    test('Android chips are unchanged', () {
      expect(isFlagshipChip('SM8650'), isTrue);
      expect(isFlagshipChip('SM7450'), isFalse);
    });
  });
}
