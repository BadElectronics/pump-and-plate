import 'package:flutter/services.dart';

import '../data/auto_backup.dart';

class BackupFolderInfo {
  const BackupFolderInfo({required this.uri, required this.name});
  final String uri;
  final String name;
}

/// A folder the user picked once, which the app may write to from then on.
abstract class BackupFolder {
  /// Opens the system folder picker. Null if the user backed out.
  Future<BackupFolderInfo?> pick();

  /// Still there, and still allowed?
  Future<bool> check(String uri);

  /// Copies the file at [path] into the folder as [name]; returns its size.
  Future<int> write(String uri, String name, String path);
  Future<List<BackupFile>> list(String uri);
  Future<void> delete(String uri, String id);
}

/// Android, through the channel in MainActivity (added by the setup script).
class AndroidBackupFolder implements BackupFolder {
  static const _channel = MethodChannel('fitapp/backup');

  @override
  Future<BackupFolderInfo?> pick() async {
    final m = await _channel.invokeMethod<Map<Object?, Object?>>('pick');
    if (m == null) return null;
    return BackupFolderInfo(uri: '${m['uri']}', name: '${m['name'] ?? 'Chosen folder'}');
  }

  @override
  Future<bool> check(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('check', {'tree': uri}) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> write(String uri, String name, String path) async =>
      await _channel.invokeMethod<int>('write', {'tree': uri, 'name': name, 'path': path}) ?? 0;

  @override
  Future<List<BackupFile>> list(String uri) async {
    final raw = await _channel.invokeMethod<List<Object?>>('list', {'tree': uri}) ?? const [];
    return [
      for (final r in raw)
        if (r is Map) BackupFile(id: '${r['id']}', name: '${r['name']}'),
    ];
  }

  @override
  Future<void> delete(String uri, String id) => _channel.invokeMethod<void>('delete', {'tree': uri, 'id': id});
}

/// For tests and platforms without the channel: nothing to pick.
class NoBackupFolder implements BackupFolder {
  const NoBackupFolder();

  @override
  Future<BackupFolderInfo?> pick() async => null;

  @override
  Future<bool> check(String uri) async => false;

  @override
  Future<int> write(String uri, String name, String path) async => throw Exception('No backup folder here.');

  @override
  Future<List<BackupFile>> list(String uri) async => const [];

  @override
  Future<void> delete(String uri, String id) async {}
}
