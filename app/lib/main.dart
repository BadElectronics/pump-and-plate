import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import 'src/app.dart';
import 'src/data/sqlite_store.dart';
import 'src/services/ai_apple.dart';
import 'src/services/ai_engine.dart';
import 'src/services/ai_gemma.dart';
import 'src/services/backup_folder.dart';
import 'src/services/device_probe.dart';
import 'src/services/photo_files.dart';
import 'src/services/reminders.dart';
import 'src/services/tips.dart';
import 'src/services/unlocker.dart';
import 'src/services/widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app is designed for portrait; this also keeps it from rotating
  // whatever the phone's auto-rotate setting is.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // On-device AI engine. If it can't start, the app still opens; Chat then
  // works without AI (pasted recipes and workouts still become drafts).
  var aiReady = false;
  try {
    await FlutterGemma.initialize(inferenceEngines: const [LiteRtLmEngine()]);
    aiReady = true;
  } catch (_) {}
  AiEngine ai = GemmaAiEngine(ready: aiReady);
  // On iPhones, Apple's built-in model is offered next to the downloads.
  if (Platform.isIOS) {
    final apple = AppleAiEngine();
    await apple.refreshAppleStatus();
    ai = CombinedAiEngine(downloads: ai, apple: apple);
  }
  runApp(FitApp(
    store: SqliteStore(),
    reminders: LocalReminders(),
    photosDir: PhotoFiles.directory,
    unlocker: LocalUnlocker(),
    // Home-screen widgets are Android-only for now.
    homeWidget: Platform.isIOS ? NoHomeWidget() : AndroidWidgetSync(),
    ai: ai,
    device: AndroidDeviceProbe(),
    // Automatic backups to a folder you pick (this was missing, so the
    // folder picker did nothing on the phone).
    backups: AndroidBackupFolder(),
    tips: StoreTipJar(),
  ));
}
