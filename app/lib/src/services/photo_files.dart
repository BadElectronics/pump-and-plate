import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Progress photos live in a private folder inside the app's storage.
/// Other apps can't see them, and uninstalling the app removes them.
class PhotoFiles {
  static Future<String> directory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// Moves a freshly taken photo into the photos folder as [fileName].
  static Future<void> keep(String sourcePath, String dir, String fileName) async {
    final source = File(sourcePath);
    await source.copy(p.join(dir, fileName));
    try {
      await source.delete();
    } catch (_) {
      // The camera's temp file is cleaned up by the system anyway.
    }
  }

  static Future<void> remove(String dir, String fileName) async {
    final f = File(p.join(dir, fileName));
    if (await f.exists()) await f.delete();
  }

  static Future<void> discard(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
