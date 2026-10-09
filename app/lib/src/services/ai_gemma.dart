import 'dart:async';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../ai/catalog.dart';
import 'ai_engine.dart';

/// Runs the models with flutter_gemma's LiteRT-LM engine (registered in
/// main.dart). Only one model is loaded at a time.
class GemmaAiEngine implements AiEngine {
  GemmaAiEngine({required this.ready});

  /// False if FlutterGemma.initialize failed at startup.
  final bool ready;

  InferenceModel? _model;
  AiTier? _loaded;

  @override
  bool get available => ready;

  ModelType _type(AiModelInfo m) => m.family == 'gemma4' ? ModelType.gemma4 : ModelType.qwen3;

  @override
  Future<bool> isInstalled(AiModelInfo m) async {
    if (!ready) return false;
    try {
      return (await FlutterGemma.listInstalledModels()).contains(m.file);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> download(AiModelInfo m, {required void Function(int percent) onProgress, required AiCancel cancel}) async {
    if (!ready) throw const AiFailure('On-device AI couldn\'t start on this phone.');
    final token = CancelToken();
    cancel.onCancel(() => token.cancel('Cancelled'));
    try {
      await FlutterGemma.installModel(modelType: _type(m), fileType: ModelFileType.litertlm)
          // Large files run as a foreground download (with a notification),
          // so Android doesn't stop them partway.
          .fromNetwork(m.url, foreground: m.sizeBytes > 1000 * 1000 * 1000)
          .withProgress(onProgress)
          .withCancelToken(token)
          .install();
    } catch (e) {
      if (CancelToken.isCancel(e) || cancel.cancelled) throw const AiDownloadCancelled();
      if (e is DownloadException) throw AiFailure(e.error.toUserMessage());
      throw AiFailure('The download didn\'t finish: $e');
    }
  }

  @override
  Future<void> importFile(AiModelInfo m, String path) async {
    if (!ready) throw const AiFailure('On-device AI couldn\'t start on this phone.');
    try {
      await FlutterGemma.installModel(modelType: _type(m), fileType: ModelFileType.litertlm).fromFile(path).install();
    } catch (e) {
      throw AiFailure('That file couldn\'t be used: $e');
    }
  }

  @override
  Future<void> remove(AiModelInfo m) async {
    if (_loaded == m.tier) await unload();
    String? importedPath;
    try {
      // An imported model is our own copy; flutter_gemma leaves those files.
      final f = File('${(await aiImportDir()).path}/${m.file}');
      if (await f.exists()) importedPath = f.path;
    } catch (_) {}
    try {
      if ((await FlutterGemma.listInstalledModels()).contains(m.file)) {
        await FlutterGemma.uninstallModel(m.file);
      }
      // Forget the active model only if none is left; otherwise the one in
      // use (made active when it was installed) stays active.
      if ((await FlutterGemma.listInstalledModels()).isEmpty) {
        await FlutterGemma.clearActiveInferenceIdentity();
      }
    } catch (_) {}
    if (importedPath != null) {
      try {
        await File(importedPath).delete();
      } catch (_) {}
    }
  }

  @override
  AiTier? get loadedTier => _model == null ? null : _loaded;

  Future<void>? _loading;
  AiTier? _loadingTier;

  @override
  Future<void> warmUp(AiModelInfo m) => _ensureLoaded(m);

  /// Loads [m] unless it's already loaded or loading (both callers then wait
  /// on the same load). Loading runs off the UI thread inside the engine.
  Future<void> _ensureLoaded(AiModelInfo m) async {
    if (!ready) throw const AiFailure('On-device AI couldn\'t start on this phone.');
    if (_model != null && _loaded == m.tier) return;
    if (_loading != null && _loadingTier == m.tier) return _loading;
    final f = _load(m);
    _loading = f;
    _loadingTier = m.tier;
    try {
      await f;
    } finally {
      if (identical(_loading, f)) {
        _loading = null;
        _loadingTier = null;
      }
    }
    if (_unloadAfterLoad) {
      _unloadAfterLoad = false;
      await unload();
      throw const AiFailure('The AI was put away.');
    }
  }

  Future<void> _load(AiModelInfo m) async {
    await unload();
    // Makes this model the active one (instant: it's already downloaded).
    if (!await isInstalled(m)) throw const AiFailure('This model isn\'t downloaded yet.');
    await FlutterGemma.installModel(modelType: _type(m), fileType: ModelFileType.litertlm).fromNetwork(m.url).install();
    // The model's preferred chip first, then the other one: some phones'
    // graphics drivers can't run a model, and some can't start one on the
    // processor.
    final first = m.gpu ? PreferredBackend.gpu : PreferredBackend.cpu;
    final second = m.gpu ? PreferredBackend.cpu : PreferredBackend.gpu;
    try {
      _model = await FlutterGemma.getActiveModel(maxTokens: m.maxTokens, preferredBackend: first);
    } catch (firstError) {
      try {
        _model = await FlutterGemma.getActiveModel(maxTokens: m.maxTokens, preferredBackend: second);
      } catch (secondError) {
        String brief(Object e) => '$e'.split('\n').first;
        throw AiFailure(
          'The ${m.tier.label} model couldn\'t start on this phone. Remove it and download it again '
          'in Chat settings (a download can arrive damaged); if it still won\'t start, use '
          '${m.tier == AiTier.light ? 'Medium' : 'Light'}. '
          '(Processor: ${brief(m.gpu ? secondError : firstError)}; graphics chip: ${brief(m.gpu ? firstError : secondError)})',
        );
      }
    }
    _loaded = m.tier;
  }

  @override
  Future<AiChat> openChat(AiModelInfo m, {required String system, List<AiTool> tools = const []}) async {
    await _ensureLoaded(m);
    final chat = await _model!.createChat(
      temperature: m.temperature,
      topK: m.topK,
      topP: m.topP,
      tools: [
        for (final t in tools) Tool(name: t.name, description: t.description, parameters: t.parameters),
      ],
      supportsFunctionCalls: tools.isNotEmpty,
      modelType: _type(m),
      systemInstruction: system,
      maxOutputTokens: 768,
    );
    late final _GemmaChat g;
    g = _GemmaChat(chat, onStart: _generationStarted, onEnd: _generationEnded, onClosed: () => _chats.remove(g));
    _chats.add(g);
    return g;
  }

  // ---- freeing memory without cutting off an answer
  int _generating = 0;
  bool _unloadPending = false;
  Timer? _idleTimer;

  @override
  Future<void> unloadWhenIdle() async {
    if (_generating > 0) {
      _unloadPending = true;
      return;
    }
    await unload();
  }

  @override
  void scheduleIdleUnload(Duration after) {
    _idleTimer?.cancel();
    _idleTimer = Timer(after, () {
      _idleTimer = null;
      unloadWhenIdle();
    });
  }

  @override
  void cancelIdleUnload() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _unloadPending = false;
  }

  final Set<_GemmaChat> _chats = {};
  bool _unloadAfterLoad = false;

  @override
  Future<void> forceUnload() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _unloadPending = false;
    // A load can't be interrupted mid-step: free it the moment it finishes.
    if (_loading != null) _unloadAfterLoad = true;
    for (final c in List.of(_chats)) {
      try {
        await c.stop();
      } catch (_) {}
      try {
        await c.close();
      } catch (_) {}
    }
    _chats.clear();
    _generating = 0;
    await unload();
  }

  void _generationStarted() => _generating++;

  void _generationEnded() {
    if (_generating > 0) _generating--;
    if (_generating == 0 && _unloadPending) {
      _unloadPending = false;
      unload();
    }
  }

  @override
  Future<void> unload() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    _unloadPending = false;
    // Conversations first, so nothing is left pointing at the freed model.
    for (final c in List.of(_chats)) {
      await c.close();
    }
    final m = _model;
    _model = null;
    _loaded = null;
    if (m != null) {
      try {
        await m.close();
      } catch (_) {}
    }
  }
}

class _GemmaChat implements AiChat {
  _GemmaChat(this._chat, {required this.onStart, required this.onEnd, required this.onClosed});

  final void Function() onClosed;

  final InferenceChat _chat;

  /// Tell the engine an answer is being written (and when it's done).
  final void Function() onStart;
  final void Function() onEnd;

  @override
  Stream<AiEvent> send(String text) async* {
    await _chat.addQueryChunk(Message.text(text: text, isUser: true));
    yield* _pump();
  }

  @override
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result) async* {
    await _chat.addQueryChunk(Message.toolResponse(toolName: name, response: result));
    yield* _pump();
  }

  Stream<AiEvent> _pump() async* {
    onStart();
    try {
      yield* _responses();
    } finally {
      onEnd();
    }
  }

  Stream<AiEvent> _responses() async* {
    await for (final r in _chat.generateChatResponseAsync()) {
      if (r is TextResponse) {
        yield AiText(r.token);
      } else if (r is FunctionCallResponse) {
        yield AiCall(r.name, r.args);
      } else if (r is ParallelFunctionCallResponse) {
        for (final c in r.calls) {
          yield AiCall(c.name, c.args);
        }
      }
      // Thinking text isn't shown.
    }
  }

  bool _closed = false;

  @override
  Future<void> stop() async {
    if (_closed) return;
    try {
      await _chat.stopGeneration();
    } catch (_) {}
  }

  /// Safe to call more than once: a conversation is never freed twice.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    onClosed();
    try {
      await _chat.close();
    } catch (_) {}
  }
}
