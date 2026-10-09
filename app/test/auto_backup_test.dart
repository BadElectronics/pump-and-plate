import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/data/auto_backup.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/services/auto_backup.dart';
import 'package:fitapp/src/services/backup_folder.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/state/app_state.dart';

/// A pretend folder kept in memory.
class _Folder implements BackupFolder {
  final files = <String, int>{}; // name -> size
  bool available = true;

  @override
  Future<BackupFolderInfo?> pick() async => const BackupFolderInfo(uri: 'tree', name: 'Docs');

  @override
  Future<bool> check(String uri) async => available;

  @override
  Future<int> write(String uri, String name, String path) async {
    final size = await File(path).length();
    files[name] = size;
    return size;
  }

  @override
  Future<List<BackupFile>> list(String uri) async => [for (final n in files.keys) BackupFile(id: n, name: n)];

  @override
  Future<void> delete(String uri, String id) async => files.remove(id);
}

Future<Uint8List> _encode(StoredData data, List<dynamic> photos) async => Uint8List.fromList([1, 2, 3]);

Future<AppState> _app({bool on = true, int keep = 2, int days = 1, DateTime? last}) async {
  final s = AppState(MemoryStore(), NoopReminders());
  await s.load();
  s.setSettings(s.settings.copyWith(
    autoBackup: on,
    backupUri: 'tree',
    backupFolder: 'Docs',
    backupKeep: keep,
    backupDays: days,
    lastAutoBackup: last,
  ));
  return s;
}

void main() {
  final tmp = () async => Directory.systemTemp.createTemp('fitapp_test');

  test('names sort oldest to newest', () {
    expect(autoBackupName(DateTime(2026, 10, 4, 9, 5)), 'fitapp-auto-2026-10-04-0905.json');
    expect(autoBackupName(DateTime(2026, 1, 2, 23, 59)).compareTo(autoBackupName(DateTime(2026, 10, 4))), lessThan(0));
  });

  test('due daily or weekly, by calendar day', () {
    final now = DateTime(2026, 10, 4, 9);
    expect(backupDue(last: null, now: now, everyDays: 7), isTrue);
    expect(backupDue(last: DateTime(2026, 10, 4, 1), now: now, everyDays: 1), isFalse);
    expect(backupDue(last: DateTime(2026, 10, 3, 23), now: now, everyDays: 1), isTrue);
    expect(backupDue(last: DateTime(2026, 9, 28), now: now, everyDays: 7), isFalse); // 6 days
    expect(backupDue(last: DateTime(2026, 9, 27), now: now, everyDays: 7), isTrue); // 7 days
  });

  test('clean-up keeps the newest and never touches other files', () {
    final files = [
      for (final n in [
        'fitapp-auto-2026-10-01-0900.json',
        'fitapp-auto-2026-10-03-0900.json',
        'fitapp-auto-2026-10-02-0900.json',
        'fitapp-backup-2026-09-01.json', // saved by hand
        'notes.txt',
      ])
        BackupFile(id: n, name: n),
    ];
    expect(backupsToDelete(files, 2).map((f) => f.name), ['fitapp-auto-2026-10-01-0900.json']);
    expect(backupsToDelete(files, 5), isEmpty);
  });

  test('a due backup is written, old ones pruned, the result recorded', () async {
    final folder = _Folder()
      ..files['fitapp-auto-2026-09-30-0900.json'] = 1
      ..files['fitapp-auto-2026-10-01-0900.json'] = 1
      ..files['fitapp-backup-2026-09-01.json'] = 1;
    final s = await _app(keep: 2);
    final now = DateTime(2026, 10, 4, 9, 12);
    final error = await runAutoBackup(s, folder, now: now, encode: _encode, tempDir: tmp);
    expect(error, isNull);
    expect(folder.files.keys, containsAll(['fitapp-auto-2026-10-04-0912.json', 'fitapp-auto-2026-10-01-0900.json']));
    expect(folder.files.containsKey('fitapp-auto-2026-09-30-0900.json'), isFalse); // pruned
    expect(folder.files.containsKey('fitapp-backup-2026-09-01.json'), isTrue); // hand-saved stays
    expect(s.settings.lastAutoBackup, now);
    expect(s.settings.backupBytes, 3);
    expect(s.settings.backupError, isNull);
  });

  test('nothing happens when off or not due, unless asked', () async {
    final folder = _Folder();
    final off = await _app(on: false);
    expect(await runAutoBackup(off, folder, encode: _encode, tempDir: tmp), isNull);
    expect(folder.files, isEmpty);
    final recent = await _app(last: DateTime.now());
    expect(await runAutoBackup(recent, folder, encode: _encode, tempDir: tmp), isNull);
    expect(folder.files, isEmpty);
    expect(await runAutoBackup(recent, folder, force: true, encode: _encode, tempDir: tmp), isNull);
    expect(folder.files, hasLength(1));
  });

  test('a missing folder is reported plainly', () async {
    final folder = _Folder()..available = false;
    final s = await _app();
    final error = await runAutoBackup(s, folder, encode: _encode, tempDir: tmp);
    expect(error, contains('isn\'t available anymore'));
    expect(s.settings.backupError, error);
    expect(folder.files, isEmpty);
  });

  test('backup settings survive saving', () {
    final t = DateTime(2026, 10, 4, 9, 12);
    final a = const AppSettings().copyWith(autoBackup: true, backupDays: 1, backupKeep: 10, backupPhotos: false,
        backupUri: 'content://x', backupFolder: 'Docs', lastAutoBackup: t, backupError: 'oops', backupBytes: 42);
    final b = AppSettings.fromRow(a.toRow());
    expect([b.autoBackup, b.backupDays, b.backupKeep, b.backupPhotos, b.backupUri, b.backupFolder, b.lastAutoBackup, b.backupError, b.backupBytes],
        [true, 1, 10, false, 'content://x', 'Docs', t, 'oops', 42]);
    final d = AppSettings.fromRow(const AppSettings().toRow());
    expect([d.autoBackup, d.backupDays, d.backupKeep, d.backupPhotos], [false, 7, 5, true]);
  });
}
