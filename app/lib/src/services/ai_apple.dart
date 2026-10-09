import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../ai/catalog.dart';
import 'ai_engine.dart';

/// Whether Apple's built-in model can be used on this iPhone.
enum AppleAiStatus {
  available,

  /// Apple Intelligence is switched off in the iPhone's Settings.
  notEnabled,

  /// Apple's model is still downloading in the background.
  notReady,

  /// This iPhone can't run it (older than iPhone 15 Pro).
  notEligible,

  /// Not an iPhone, or iOS older than 26.
  unsupported,
}

AppleAiStatus appleStatusFrom(String? s) => switch (s) {
      'available' => AppleAiStatus.available,
      'notEnabled' => AppleAiStatus.notEnabled,
      'notReady' => AppleAiStatus.notReady,
      'notEligible' => AppleAiStatus.notEligible,
      _ => AppleAiStatus.unsupported,
    };

extension AppleAiStatusText on AppleAiStatus {
  /// Show it as a choice: it works now, or can after a setting or a wait.
  bool get offered => this == AppleAiStatus.available || this == AppleAiStatus.notEnabled || this == AppleAiStatus.notReady;

  /// What to do before it can be used, or null when it's ready.
  String? get help => switch (this) {
        AppleAiStatus.available => null,
        AppleAiStatus.notEnabled =>
          'Turn on Apple Intelligence in the iPhone\'s Settings (Apple Intelligence & Siri), then come back.',
        AppleAiStatus.notReady => 'Apple\'s model is still downloading to this iPhone. Check again in a little while.',
        AppleAiStatus.notEligible => 'This iPhone can\'t run Apple\'s model (it needs an iPhone 15 Pro or newer).',
        AppleAiStatus.unsupported => 'Apple\'s model needs iOS 26 or later.',
      };
}

/// What the AI setup screen asks about Apple's model.
abstract interface class AppleAiInfo {
  AppleAiStatus get appleStatus;
  Future<AppleAiStatus> refreshAppleStatus();

  /// False when the downloadable models can't run here, so only Apple's
  /// model is offered.
  bool get downloadsAvailable;
}

/// The function parameters in the form the iPhone code reads: like JSON
/// Schema, but with properties as an ordered list (a map loses its order on
/// the way), so the model sees them in the order they were written.
Map<String, Object?> appleSchema(Map<String, dynamic> j) {
  final out = <String, Object?>{'type': '${j['type'] ?? 'string'}'};
  final description = j['description'];
  if (description != null) out['description'] = '$description';
  final choices = j['enum'];
  if (choices is List) out['enum'] = [for (final c in choices) '$c'];
  final items = j['items'];
  if (items is Map) out['items'] = appleSchema(Map<String, dynamic>.from(items));
  final properties = j['properties'];
  if (properties is Map) {
    final required = {for (final r in (j['required'] is List ? j['required'] as List : const [])) '$r'};
    out['properties'] = [
      for (final e in properties.entries)
        {
          'name': '${e.key}',
          'required': required.contains('${e.key}'),
          'schema': appleSchema(e.value is Map ? Map<String, dynamic>.from(e.value as Map) : const {}),
        },
    ];
  }
  return out;
}

/// The calls the iPhone code answers ('fitapp/appleai').
abstract class AppleAiBridge {
  Future<String?> status();
  Future<void> open(String session, {required String instructions, required List<Map<String, Object?>> tools, required double temperature});
  Future<void> send(String session, String text, int turn);
  Future<void> toolResult(String session, String json, int turn);
  Future<void> prewarm(String session);
  Future<void> stop(String session);
  Future<void> close(String session);

  /// Every answer's events: {session, turn, type: text|call|error|done, ...}.
  Stream<Map<Object?, Object?>> get events;
}

class ChannelAppleAiBridge implements AppleAiBridge {
  ChannelAppleAiBridge();

  static const _channel = MethodChannel('fitapp/appleai');
  static const _eventChannel = EventChannel('fitapp/appleai/events');

  @override
  late final Stream<Map<Object?, Object?>> events =
      _eventChannel.receiveBroadcastStream().where((e) => e is Map).map((e) => e as Map<Object?, Object?>);

  @override
  Future<String?> status() async {
    try {
      return await _channel.invokeMethod<String>('status');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> open(String session, {required String instructions, required List<Map<String, Object?>> tools, required double temperature}) =>
      _channel.invokeMethod<void>('open', {
        'session': session,
        'instructions': instructions,
        'tools': tools,
        'temperature': temperature,
      });

  @override
  Future<void> send(String session, String text, int turn) =>
      _channel.invokeMethod<void>('send', {'session': session, 'text': text, 'turn': turn});

  @override
  Future<void> toolResult(String session, String json, int turn) =>
      _channel.invokeMethod<void>('toolResult', {'session': session, 'json': json, 'turn': turn});

  @override
  Future<void> prewarm(String session) => _channel.invokeMethod<void>('prewarm', {'session': session});

  @override
  Future<void> stop(String session) => _channel.invokeMethod<void>('stop', {'session': session});

  @override
  Future<void> close(String session) => _channel.invokeMethod<void>('close', {'session': session});
}

/// Apple's on-device model. Nothing to download; the iPhone keeps it ready
/// and frees its memory itself, so "loading" here only means a conversation
/// is open.
class AppleAiEngine implements AiEngine, AppleAiInfo {
  AppleAiEngine({AppleAiBridge? bridge}) : _bridge = bridge ?? ChannelAppleAiBridge();

  final AppleAiBridge _bridge;
  AppleAiStatus _status = AppleAiStatus.unsupported;
  StreamSubscription<Map<Object?, Object?>>? _sub;
  final _chats = <String, _AppleChat>{};
  var _nextId = 0;
  bool _loaded = false;
  int _busy = 0;
  bool _unloadWhenIdle = false;
  Timer? _idleTimer;

  @override
  AppleAiStatus get appleStatus => _status;

  @override
  Future<AppleAiStatus> refreshAppleStatus() async {
    _status = appleStatusFrom(await _bridge.status());
    return _status;
  }

  @override
  bool get downloadsAvailable => false;

  @override
  bool get available => _status.offered;

  bool _isApple(AiModelInfo m) => m.family == 'apple';

  /// True while this iPhone offers it, even if it's waiting on a setting or
  /// a download: a choice of Apple's model is kept, and opening a chat says
  /// what to do first.
  @override
  Future<bool> isInstalled(AiModelInfo m) async {
    if (!_isApple(m)) return false;
    return (await refreshAppleStatus()).offered;
  }

  @override
  Future<void> download(AiModelInfo m, {required void Function(int percent) onProgress, required AiCancel cancel}) async {
    throw const AiFailure('Apple\'s model is built into the iPhone: there\'s nothing to download.');
  }

  @override
  Future<void> importFile(AiModelInfo m, String path) async {
    throw const AiFailure('Apple\'s model is built into the iPhone: there\'s nothing to import.');
  }

  @override
  Future<void> remove(AiModelInfo m) async {}

  void _listen() {
    _sub ??= _bridge.events.listen((e) => _chats['${e['session']}']?._deliver(e));
  }

  @override
  Future<AiChat> openChat(AiModelInfo m, {required String system, List<AiTool> tools = const []}) async {
    final status = await refreshAppleStatus();
    if (status != AppleAiStatus.available) {
      throw AiFailure(status.help ?? 'Apple\'s model isn\'t available right now.');
    }
    _listen();
    final id = 'chat${_nextId++}';
    final chat = _AppleChat(this, id);
    _chats[id] = chat;
    try {
      await _bridge.open(
        id,
        instructions: system,
        tools: [
          for (final t in tools) {'name': t.name, 'description': t.description, 'schema': appleSchema(t.parameters)},
        ],
        temperature: m.temperature,
      );
      await _bridge.prewarm(id);
    } catch (e) {
      _chats.remove(id);
      throw AiFailure(e is PlatformException ? (e.message ?? 'Apple\'s model couldn\'t start.') : 'Apple\'s model couldn\'t start: $e');
    }
    _loaded = true;
    return chat;
  }

  @override
  AiTier? get loadedTier => _loaded ? AiTier.apple : null;

  @override
  Future<void> warmUp(AiModelInfo m) async {}

  @override
  Future<void> unload() async {
    _idleTimer?.cancel();
    for (final c in List.of(_chats.values)) {
      await c.close();
    }
    _loaded = false;
  }

  @override
  Future<void> unloadWhenIdle() async {
    if (_busy == 0) {
      await unload();
    } else {
      _unloadWhenIdle = true;
    }
  }

  @override
  void scheduleIdleUnload(Duration after) {
    _idleTimer?.cancel();
    _idleTimer = Timer(after, () => unloadWhenIdle());
  }

  @override
  void cancelIdleUnload() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  @override
  Future<void> forceUnload() async {
    _unloadWhenIdle = false;
    for (final c in List.of(_chats.values)) {
      await c.stop();
    }
    await unload();
  }

  void _started() => _busy++;

  void _ended() {
    if (_busy > 0) _busy--;
    if (_busy == 0 && _unloadWhenIdle) {
      _unloadWhenIdle = false;
      unload();
    }
  }
}

/// Events for one conversation, waiting to be read.
class _EventQueue {
  final _items = <Map<Object?, Object?>>[];
  Completer<Map<Object?, Object?>>? _waiting;

  void add(Map<Object?, Object?> e) {
    final w = _waiting;
    if (w != null) {
      _waiting = null;
      w.complete(e);
    } else {
      _items.add(e);
    }
  }

  Future<Map<Object?, Object?>> next() {
    if (_items.isNotEmpty) return Future.value(_items.removeAt(0));
    return (_waiting = Completer<Map<Object?, Object?>>()).future;
  }

  void clear() => _items.clear();
}

class _AppleChat implements AiChat {
  _AppleChat(this._engine, this.id);

  final AppleAiEngine _engine;
  final String id;
  final _queue = _EventQueue();

  /// The answer being read. Events from an earlier one are dropped.
  int _turn = 0;
  bool _closed = false;

  void _deliver(Map<Object?, Object?> e) {
    if (e['turn'] == _turn) _queue.add(e);
  }

  @override
  Stream<AiEvent> send(String text) => _answer((turn) => _engine._bridge.send(id, text, turn));

  @override
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result) =>
      _answer((turn) => _engine._bridge.toolResult(id, jsonEncode(result), turn));

  Stream<AiEvent> _answer(Future<void> Function(int turn) start) async* {
    if (_closed) throw const AiFailure('This conversation was closed. Send your message again.');
    final turn = ++_turn;
    _queue.clear();
    _engine._started();
    try {
      try {
        await start(turn);
      } on PlatformException catch (e) {
        throw AiFailure(e.message ?? 'Apple\'s model stopped.');
      }
      while (true) {
        final e = await _queue.next();
        switch (e['type']) {
          case 'text':
            yield AiText('${e['text'] ?? ''}');
          case 'call':
            yield AiCall('${e['name']}', _args(e['args']));
            // The model waits for the app's answer (sendToolResult).
            return;
          case 'error':
            throw AiFailure('${e['message'] ?? 'Apple\'s model stopped.'}');
          default:
            return;
        }
      }
    } finally {
      _engine._ended();
    }
  }

  static Map<String, dynamic> _args(Object? raw) {
    try {
      final v = raw is String ? jsonDecode(raw) : raw;
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return <String, dynamic>{};
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    try {
      await _engine._bridge.stop(id);
    } catch (_) {}
    // Whatever happens on the iPhone side, end the answer being read.
    _queue.add({'session': id, 'turn': _turn, 'type': 'done'});
  }

  /// Safe to call more than once.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _engine._chats.remove(id);
    _queue.add({'session': id, 'turn': _turn, 'type': 'done'});
    try {
      await _engine._bridge.close(id);
    } catch (_) {}
  }
}

/// Apple's model and the downloadable ones together: each call goes to
/// whichever runs the model it's about. Switching models frees the other.
class CombinedAiEngine implements AiEngine, AppleAiInfo {
  CombinedAiEngine({required this.downloads, required this.apple});

  final AiEngine downloads;
  final AppleAiEngine apple;

  AiEngine _for(AiModelInfo m) => m.family == 'apple' ? apple : downloads;

  @override
  AppleAiStatus get appleStatus => apple.appleStatus;

  @override
  Future<AppleAiStatus> refreshAppleStatus() => apple.refreshAppleStatus();

  @override
  bool get downloadsAvailable => downloads.available;

  @override
  bool get available => downloads.available || apple.available;

  @override
  Future<bool> isInstalled(AiModelInfo m) => _for(m).isInstalled(m);

  @override
  Future<void> download(AiModelInfo m, {required void Function(int percent) onProgress, required AiCancel cancel}) =>
      _for(m).download(m, onProgress: onProgress, cancel: cancel);

  @override
  Future<void> importFile(AiModelInfo m, String path) => _for(m).importFile(m, path);

  @override
  Future<void> remove(AiModelInfo m) => _for(m).remove(m);

  @override
  Future<AiChat> openChat(AiModelInfo m, {required String system, List<AiTool> tools = const []}) async {
    // Only one model in memory at a time.
    if (m.family == 'apple') {
      if (downloads.loadedTier != null) await downloads.unload();
    } else if (apple.loadedTier != null) {
      await apple.unload();
    }
    return _for(m).openChat(m, system: system, tools: tools);
  }

  @override
  AiTier? get loadedTier => apple.loadedTier ?? downloads.loadedTier;

  @override
  Future<void> warmUp(AiModelInfo m) => _for(m).warmUp(m);

  @override
  Future<void> unload() async {
    await apple.unload();
    await downloads.unload();
  }

  @override
  Future<void> unloadWhenIdle() async {
    await apple.unloadWhenIdle();
    await downloads.unloadWhenIdle();
  }

  @override
  void scheduleIdleUnload(Duration after) {
    apple.scheduleIdleUnload(after);
    downloads.scheduleIdleUnload(after);
  }

  @override
  void cancelIdleUnload() {
    apple.cancelIdleUnload();
    downloads.cancelIdleUnload();
  }

  @override
  Future<void> forceUnload() async {
    await apple.forceUnload();
    await downloads.forceUnload();
  }
}
