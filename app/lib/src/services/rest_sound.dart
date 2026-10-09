import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Sound files the rest-is-up sound can be.
const restSoundExtensions = {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'};

/// iPhones can't play these.
const restSoundNotOnIPhone = {'ogg', 'opus'};

/// Biggest file accepted (a short clip is plenty).
const restSoundMaxBytes = 5 * 1024 * 1024;

class RestSoundError implements Exception {
  const RestSoundError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Copies a sound the user picked into the app (the picker's copy can be
/// cleared by Android), replacing the previous one. Returns the new path and
/// the file's name to show.
Future<(String path, String name)> importRestSound(String source) async {
  final name = source.split(RegExp(r'[\\/]')).last;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (!restSoundExtensions.contains(ext)) {
    throw RestSoundError('That isn\'t a sound file. Pick an MP3, M4A, WAV${Platform.isIOS ? '' : ' or OGG'}.');
  }
  if (Platform.isIOS && restSoundNotOnIPhone.contains(ext)) {
    throw const RestSoundError('iPhones can\'t play OGG or Opus files. Pick an MP3, M4A or WAV.');
  }
  final src = File(source);
  if (await src.length() > restSoundMaxBytes) {
    throw const RestSoundError('That file is over 5 MB. A short clip works best.');
  }
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/sounds');
  await dir.create(recursive: true);
  await clearRestSounds(dir);
  final dest = '${dir.path}/rest_${DateTime.now().millisecondsSinceEpoch}.$ext';
  await src.copy(dest);
  return (dest, name);
}

/// Deletes the copied sound(s).
Future<void> clearRestSounds([Directory? folder]) async {
  try {
    final dir = folder ?? Directory('${(await getApplicationDocumentsDirectory()).path}/sounds');
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      if (f is File) await f.delete();
    }
  } catch (_) {}
}

/// The saved sound file, found again if the app's folder moved. (On iPhones
/// the app's storage folder gets a new path after an update, so a saved full
/// path can go stale; the file itself is still in the sounds folder.)
Future<String?> resolveRestSound(String? saved) async {
  if (saved == null || saved.isEmpty) return null;
  if (await File(saved).exists()) return saved;
  try {
    final name = saved.split(RegExp(r'[\\/]')).last;
    final again = '${(await getApplicationDocumentsDirectory()).path}/sounds/$name';
    if (await File(again).exists()) return again;
  } catch (_) {}
  return null;
}
