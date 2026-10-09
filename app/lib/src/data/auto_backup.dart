/// Naming, timing and clean-up rules for automatic backups.
/// No Flutter imports: unit-tested.
library;

import 'models.dart';

/// Automatic backups start with this, so clean-up never touches a backup
/// the user saved by hand.
const autoBackupPrefix = 'fitapp-auto-';

String _two(int n) => n.toString().padLeft(2, '0');

/// "fitapp-auto-2026-10-04-0912.json": sorts oldest to newest by name.
String autoBackupName(DateTime t) =>
    '$autoBackupPrefix${t.year}-${_two(t.month)}-${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}.json';

/// Due if there's never been one, or [everyDays] calendar days have passed.
bool backupDue({required DateTime? last, required DateTime now, required int everyDays}) =>
    last == null || daysBetween(last, now) >= (everyDays < 1 ? 1 : everyDays);

class BackupFile {
  const BackupFile({required this.id, required this.name});

  /// The file's id within the folder (Android document id).
  final String id;
  final String name;
}

/// The automatic backups beyond the newest [keep], to delete. Other files in
/// the folder (including backups saved by hand) are never included.
List<BackupFile> backupsToDelete(List<BackupFile> files, int keep) {
  final auto = [
    for (final f in files)
      if (f.name.startsWith(autoBackupPrefix) && f.name.endsWith('.json')) f,
  ]..sort((a, b) => b.name.compareTo(a.name)); // newest first
  final k = keep < 1 ? 1 : keep;
  return auto.length <= k ? const [] : auto.sublist(k);
}
