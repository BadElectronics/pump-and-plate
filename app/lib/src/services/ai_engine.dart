import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ai/catalog.dart';

/// Where imported model files are kept, inside the app's own storage.
Future<Directory> aiImportDir() async {
  final d = Directory('${(await getApplicationDocumentsDirectory()).path}/models');
  await d.create(recursive: true);
  return d;
}

/// A function the model may call. [parameters] is a JSON Schema object.
class AiTool {
  const AiTool({required this.name, required this.description, required this.parameters});

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
}

/// What a model sends back while it answers.
sealed class AiEvent {
  const AiEvent();
}

class AiText extends AiEvent {
  const AiText(this.text);
  final String text;
}

class AiCall extends AiEvent {
  const AiCall(this.name, this.args);
  final String name;
  final Map<String, dynamic> args;
}

/// Cancels a download in progress.
class AiCancel {
  final _listeners = <void Function()>[];
  bool cancelled = false;

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() l) => _listeners.add(l);
}

class AiDownloadCancelled implements Exception {
  const AiDownloadCancelled();
}

/// A readable reason a download or model start failed.
class AiFailure implements Exception {
  const AiFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One conversation with a loaded model.
abstract class AiChat {
  Stream<AiEvent> send(String text);

  /// The app's answer to a function call; the model then continues.
  Stream<AiEvent> sendToolResult(String name, Map<String, dynamic> result);
  Future<void> stop();
  Future<void> close();
}

/// Downloads, removes and runs the on-device models.
abstract class AiEngine {
  /// False where models can't run at all (tests, unsupported builds).
  bool get available;
  Future<bool> isInstalled(AiModelInfo m);
  Future<void> download(AiModelInfo m, {required void Function(int percent) onProgress, required AiCancel cancel});

  /// Installs a model file the user copied to the phone (already in app storage).
  Future<void> importFile(AiModelInfo m, String path);
  Future<void> remove(AiModelInfo m);
  Future<AiChat> openChat(AiModelInfo m, {required String system, List<AiTool> tools = const []});

  /// The model loaded in memory right now, if any.
  AiTier? get loadedTier;

  /// Loads [m] ahead of the first message (does nothing if it's loaded).
  Future<void> warmUp(AiModelInfo m);

  /// Frees the loaded model's memory.
  Future<void> unload();

  /// Frees the model's memory now, or as soon as an answer being written
  /// finishes (so an answer is never cut off).
  Future<void> unloadWhenIdle();

  /// Frees the model's memory after [after], unless cancelled first.
  void scheduleIdleUnload(Duration after);
  void cancelIdleUnload();

  /// "Put AI away": stops any answer at once, closes every conversation and
  /// frees the model (right after loading, if it's loading now).
  Future<void> forceUnload();
}

/// No AI: the Chat tab still turns pasted recipes and workouts into drafts.
class NoAiEngine implements AiEngine {
  const NoAiEngine();

  @override
  bool get available => false;

  @override
  Future<bool> isInstalled(AiModelInfo m) async => false;

  @override
  Future<void> download(AiModelInfo m, {required void Function(int percent) onProgress, required AiCancel cancel}) async {
    throw const AiFailure('On-device AI isn\'t available in this build.');
  }

  @override
  Future<void> importFile(AiModelInfo m, String path) async {
    throw const AiFailure('On-device AI isn\'t available in this build.');
  }

  @override
  Future<void> remove(AiModelInfo m) async {}

  @override
  Future<AiChat> openChat(AiModelInfo m, {required String system, List<AiTool> tools = const []}) async {
    throw const AiFailure('On-device AI isn\'t available in this build.');
  }

  @override
  AiTier? get loadedTier => null;

  @override
  Future<void> warmUp(AiModelInfo m) async {}

  @override
  Future<void> unload() async {}

  @override
  Future<void> unloadWhenIdle() async {}

  @override
  void scheduleIdleUnload(Duration after) {}

  @override
  void cancelIdleUnload() {}

  @override
  Future<void> forceUnload() async {}
}
