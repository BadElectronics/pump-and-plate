import 'package:flutter/widgets.dart';

import 'ai_engine.dart';
import 'backup_folder.dart';
import 'device_probe.dart';
import 'tips.dart';

/// The on-device AI engine and device check, for any screen below the app.
class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.ai,
    required this.device,
    this.backups = const NoBackupFolder(),
    this.tips = const NoTipJar(),
    required super.child,
  });

  final AiEngine ai;
  final DeviceProbe device;

  /// The folder automatic backups go to.
  final BackupFolder backups;

  /// The tip jar (Settings > Support).
  final TipJar tips;

  static ServicesScope of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(s != null, 'ServicesScope missing');
    return s!;
  }

  @override
  bool updateShouldNotify(ServicesScope old) => old.ai != ai || old.device != device || old.backups != backups || old.tips != tips;
}
