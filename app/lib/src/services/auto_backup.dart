import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/auto_backup.dart';
import '../data/backup.dart';
import '../data/store.dart';
import '../state/app_state.dart';
import 'backup_folder.dart';

typedef BackupEncoder = Future<Uint8List> Function(StoredData data, List<BackupPhoto> photos);

/// Encodes off the UI thread, like the manual backup.
Future<Uint8List> _encode(StoredData data, List<BackupPhoto> photos) =>
    compute(encodeBackupBytes, (data, photos));

class _Problem implements Exception {
  const _Problem(this.text);
  final String text;
}

bool _running = false;

/// Saves an automatic backup if one is due (or now, if [force]), then
/// deletes automatic backups beyond the number to keep. Returns null when it
/// worked or wasn't needed, else a plain reason (also kept in settings).
Future<String?> runAutoBackup(
  AppState s,
  BackupFolder folder, {
  bool force = false,
  DateTime? now,
  BackupEncoder encode = _encode,
  Future<Directory> Function() tempDir = getTemporaryDirectory,
}) async {
  final cfg = s.settings;
  final time = now ?? DateTime.now();
  final uri = cfg.backupUri;
  if (_running) return null;
  if (!force && (!cfg.autoBackup || uri == null || !backupDue(last: cfg.lastAutoBackup, now: time, everyDays: cfg.backupDays))) {
    return null;
  }
  if (uri == null) return 'Choose a folder for backups first.';
  _running = true;
  File? tmp;
  try {
    if (!await folder.check(uri)) {
      throw const _Problem('The backup folder isn\'t available anymore. Choose it again in Settings.');
    }
    final photos = cfg.backupPhotos ? await s.photosForBackup() : const <BackupPhoto>[];
    final bytes = await encode(s.snapshot, photos);
    final name = autoBackupName(time);
    tmp = File('${(await tempDir()).path}/$name');
    await tmp.writeAsBytes(bytes, flush: true);
    await folder.write(uri, name, tmp.path);
    // Keep only the newest few automatic backups (never ones saved by hand).
    try {
      final files = await folder.list(uri);
      for (final f in backupsToDelete(files, cfg.backupKeep)) {
        await folder.delete(uri, f.id);
      }
    } catch (_) {}
    s.setSettings(s.settings.copyWith(
      lastAutoBackup: time,
      lastExport: time,
      backupError: null,
      backupBytes: bytes.length,
    ));
    return null;
  } catch (e) {
    final text = switch (e) {
      _Problem(:final text) => text,
      _ when isStorageFull(e) =>
        'There wasn\'t enough space for the backup. Free some space on the phone (or wherever the backup folder is).',
      _ => 'The backup didn\'t work: ${'$e'.split('\n').first}',
    };
    s.setSettings(s.settings.copyWith(backupError: text));
    return text;
  } finally {
    _running = false;
    try {
      await tmp?.delete();
    } catch (_) {}
  }
}
