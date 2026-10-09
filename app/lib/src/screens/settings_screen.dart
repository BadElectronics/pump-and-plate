import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/catalog.dart';
import '../calc/calc.dart';
import '../config.dart';
import '../data/backup.dart';
import '../data/export.dart';
import '../data/models.dart';
import '../data/store.dart';
import '../services/auto_backup.dart';
import '../services/phone.dart';
import '../services/rest_sound.dart';
import '../services/services_scope.dart';
import '../services/unlocker.dart';
import '../state/app_state.dart';
import '../state/spreadsheets.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'ai_setup_screen.dart';
import 'support_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.onReplayTour});

  /// Goes back to Home and shows the app tour again.
  final VoidCallback? onReplayTour;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final cfg = s.settings;
    final scheduled = cfg.darkSchedule || cfg.followSystem;
    final dayThemes = [for (final p in AppPalette.all) if (!scheduled || !p.isDark) p];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
        children: [
          Text('Settings', style: AppText.title(c)),
          const SizedBox(height: 20),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
            child: SettingRow(
              divider: false,
              label: 'Nickname',
              note: s.settings.nickname ?? 'Optional; used to greet you and on food you share',
              trailing: TextButton(
                onPressed: () async {
                  final n = await askNickname(context, current: s.settings.nickname);
                  if (n == null) return;
                  s.setSettings(s.settings.copyWith(
                    nickname: n.isEmpty ? null : n,
                    nicknameAsked: true,
                  ));
                },
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: Text(s.settings.nickname == null ? 'Add' : 'Change'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
            child: SettingRow(
              divider: false,
              label: 'On-device AI',
              note: switch (tierByName(s.settings.aiTier)) {
                null => 'Not set up. Runs privately on your phone.',
                final AiTier t => '${t.label}: ${modelFor(t).name}, ${modelFor(t).sizeLabel}',
              },
              trailing: TextButton(
                key: const ValueKey('ai-settings'),
                onPressed: () => Navigator.of(context).push(AiSetupScreen.route()),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: Text(s.settings.aiTier == null ? 'Set up' : 'Change'),
              ),
            ),
          ),
          if (onReplayTour != null) ...[
            const SizedBox(height: 10),
            SectionCard(
              padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
              child: SettingRow(
                divider: false,
                label: 'App tour',
                note: 'A one-minute look around',
                trailing: TextButton(
                  key: const ValueKey('replay-tour'),
                  onPressed: onReplayTour,
                  style: TextButton.styleFrom(foregroundColor: c.accent),
                  child: const Text('Show'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SectionCard(
            title: 'Theme',
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (scheduled) ...[
                  Text('Day theme', style: AppText.body(c)),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    for (var i = 0; i < AppPalette.all.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: i < dayThemes.length
                            ? _ThemeSwatch(
                                palette: dayThemes[i],
                                selected: dayThemes[i].id == cfg.themeId ||
                                    (scheduled && AppPalette.byId(cfg.themeId).isDark && dayThemes[i].id == AppPalette.earth.id),
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  s.setSettings(cfg.copyWith(themeId: dayThemes[i].id));
                                },
                              )
                            // Keeps the swatches the same size in both rows.
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Text('Dark at night', style: AppText.body(c)),
                const SizedBox(height: 6),
                Segmented<int>(
                  label: 'Dark at night',
                  options: const [(0, 'Off'), (1, 'Phone setting'), (2, 'Set hours')],
                  value: cfg.darkSchedule ? 2 : (cfg.followSystem ? 1 : 0),
                  onChanged: (v) {
                    var next = cfg.copyWith(followSystem: v == 1, darkSchedule: v == 2);
                    // A dark main theme becomes the night theme, and the day gets a light one.
                    if (v != 0 && AppPalette.byId(cfg.themeId).isDark) {
                      next = next.copyWith(darkThemeId: cfg.themeId, themeId: AppPalette.earth.id);
                    }
                    s.setSettings(next);
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  cfg.darkSchedule
                      ? 'Your theme during the day, a dark one during these hours.'
                      : cfg.followSystem
                          ? 'A dark theme whenever your phone is in dark mode (most phones can schedule it).'
                          : 'Always uses the theme above.',
                  style: AppText.quiet(c).copyWith(fontSize: 13),
                ),
                if (cfg.darkSchedule) ...[
                  for (final (label, minute, isFrom) in [('Dark from', cfg.darkFrom, true), ('Light from', cfg.darkTo, false)])
                    SettingRow(
                      label: label,
                      trailing: TextButton(
                        key: ValueKey(isFrom ? 'dark-from' : 'dark-to'),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
                          );
                          if (picked == null) return;
                          final m = picked.hour * 60 + picked.minute;
                          s.setSettings(isFrom ? s.settings.copyWith(darkFrom: m) : s.settings.copyWith(darkTo: m));
                        },
                        style: TextButton.styleFrom(foregroundColor: c.accent),
                        child: Text(TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context)),
                      ),
                    ),
                ],
                if (cfg.darkSchedule || cfg.followSystem) ...[
                  const SizedBox(height: 10),
                  Text('Night theme', style: AppText.body(c)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final p in AppPalette.all.where((p) => p.isDark)) ...[
                        Expanded(
                          child: _ThemeSwatch(
                            palette: p,
                            selected: p.id == cfg.darkThemeId || (!AppPalette.byId(cfg.darkThemeId).isDark && p.id == 'night'),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              s.setSettings(cfg.copyWith(darkThemeId: p.id));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Keeps the swatches the same size as the five above.
                      for (var i = AppPalette.all.where((p) => p.isDark).length; i < AppPalette.all.length; i++) ...[
                        const Expanded(child: SizedBox()),
                        if (i < AppPalette.all.length - 1) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                SettingRow(
                  label: 'Reduce motion',
                  note: 'Shorter fades instead of moving animations',
                  trailing: Toggle(
                    label: 'Reduce motion',
                    value: cfg.reduceMotion,
                    onChanged: (v) => s.setSettings(cfg.copyWith(reduceMotion: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Units',
            child: Segmented<Units>(
              label: 'Units',
              options: const [
                (Units.imperial, 'lb, ft, in'),
                (Units.metric, 'kg, cm'),
              ],
              value: cfg.units,
              onChanged: (v) => s.setSettings(cfg.copyWith(units: v)),
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Week starts on',
            child: Segmented<bool>(
              label: 'Week starts on',
              options: const [(true, 'Sunday'), (false, 'Monday')],
              value: cfg.weekStartsSunday,
              onChanged: (v) => s.setSettings(cfg.copyWith(weekStartsSunday: v)),
            ),
          ),
          const SizedBox(height: 14),
          const _ReminderAndSleep(),
          const SizedBox(height: 14),
          const _StoresCard(),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Optional tracking',
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            child: Column(
              children: [
                SettingRow(
                  divider: false,
                  label: 'Body measurements',
                  note: 'Neck, chest, waist, hips, arms and legs, in Progress > Body',
                  trailing: Toggle(
                    key: const ValueKey('measurements-toggle'),
                    label: 'Body measurements',
                    value: cfg.measurementsOn,
                    onChanged: (v) => s.setSettings(cfg.copyWith(measurementsOn: v)),
                  ),
                ),
                SettingRow(
                  label: 'Supplements',
                  note: 'A daily checklist of what you take and how much, in Log',
                  trailing: Toggle(
                    key: const ValueKey('supplements-toggle'),
                    label: 'Supplements',
                    value: cfg.supplementsOn,
                    onChanged: (v) => s.setSettings(cfg.copyWith(supplementsOn: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _LockCard(),
          const SizedBox(height: 14),
          const _YourData(),
          const SizedBox(height: 14),
          const _AutoBackups(),
          const SizedBox(height: 14),
          SectionCard(
            title: 'Support',
            padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
            child: Column(
              children: [
                SettingRow(
                  divider: false,
                  label: 'Please consider a tip',
                  note: '$appName is free with no ads. Tips keep it going.',
                  trailing: TextButton(
                    key: const ValueKey('open-support'),
                    onPressed: () => Navigator.of(context).push(SupportScreen.route()),
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: const Text('Tip jar'),
                  ),
                ),
                SettingRow(
                  label: 'Privacy policy',
                  note: 'Your data stays on this phone',
                  trailing: TextButton(
                    key: const ValueKey('privacy-policy'),
                    onPressed: () => openPrivacyPolicy(context),
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: const Text('Open'),
                  ),
                ),
                SettingRow(
                  label: 'Report a bug or suggest a feature',
                  note: 'Opens an email; nothing is sent until you tap Send',
                  trailing: TextButton(
                    onPressed: () => reportBug(context),
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: const Text('Email'),
                  ),
                ),
                if (youtubeUrl.isNotEmpty)
                  SettingRow(
                    label: 'Watch on YouTube',
                    trailing: TextButton(
                      onPressed: () => openYouTube(context),
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      child: const Text('Open'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'About',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appName, style: AppText.body(c)),
                Text(buildLabel, style: AppText.quiet(c)),
                const SizedBox(height: 8),
                Text(
                  'Everything is saved on this phone only. Nothing is sent '
                  'anywhere unless you export a backup yourself. Tips are '
                  'handled by the app store.',
                  style: AppText.quiet(c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name} theme',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 60,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? c.accent : c.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: 0.7,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FractionallySizedBox(
                      widthFactor: 0.4,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                palette.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: c.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderAndSleep extends StatelessWidget {
  const _ReminderAndSleep();

  String _time(BuildContext context, int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

  Future<void> _toggle(BuildContext context, AppState s, bool on) async {
    if (!on) {
      s.setSettings(s.settings.copyWith(reminderMinute: null));
      return;
    }
    final allowed = await s.reminders.requestPermission();
    if (!allowed) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications are off for this app. Allow them in your phone\'s '
              'Settings > Apps to get the reminder.',
            ),
          ),
        );
      }
      return;
    }
    s.setSettings(s.settings.copyWith(reminderMinute: 6 * 60 + 30));
  }

  Future<void> _pickTime(BuildContext context, AppState s) async {
    final current = s.settings.reminderMinute ?? 6 * 60 + 30;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: 'Reminder time',
    );
    if (picked == null) return;
    s.setSettings(
      s.settings.copyWith(reminderMinute: picked.hour * 60 + picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final minute = s.settings.reminderMinute;
    final goal = s.settings.sleepGoalHours;

    return SectionCard(
      title: 'Reminders, sleep and photos',
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            divider: false,
            label: 'Morning weigh-in reminder',
            note: minute == null
                ? 'Off'
                : 'Every day at ${_time(context, minute)}. Skipped once you\'ve weighed in.',
            trailing: Toggle(
              label: 'Morning weigh-in reminder',
              value: minute != null,
              onChanged: (v) => _toggle(context, s, v),
            ),
          ),
          SettingRow(
            label: 'Rest timer notification',
            note: 'Shows the running rest clock when you leave the app',
            trailing: Toggle(
              label: 'Rest timer notification',
              value: s.settings.restNotification,
              onChanged: (v) => s.setSettings(
                s.settings.copyWith(restNotification: v, restAlert: v ? null : false),
              ),
            ),
          ),
          if (s.settings.restNotification || s.settings.reminderMinute != null)
            FutureBuilder<bool>(
              future: s.reminders.notificationsAllowed(),
              builder: (context, snap) {
                if (snap.data != false) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: c.protein.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notifications are blocked for Pump and Plate, so the rest '
                          'timer and reminder can\'t show.',
                          style: AppText.body(c).copyWith(fontSize: 14),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          final ok = await s.reminders.requestPermission();
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                Theme.of(context).platform == TargetPlatform.iOS
                                    ? 'Notifications are off. Open the iPhone\'s Settings > Apps > '
                                        'Pump and Plate > Notifications and turn them on.'
                                    : 'Android didn\'t show the prompt. Open your phone\'s '
                                        'Settings > Apps > Pump and Plate > Notifications and turn them on.',
                              ),
                            ));
                          }
                          if (context.mounted) (context as Element).markNeedsBuild();
                        },
                        style: TextButton.styleFrom(foregroundColor: c.protein),
                        child: const Text('Allow'),
                      ),
                    ],
                  ),
                );
              },
            ),
          if (s.settings.restNotification)
            SettingRow(
              label: 'Test the rest timer',
              note: 'Shows a 10-second rest. Leave the app to see it.',
              trailing: TextButton(
                onPressed: () async {
                  if (!await s.reminders.notificationsAllowed()) {
                    await s.reminders.requestPermission();
                  }
                  await s.reminders.showRest(
                    startedAt: DateTime.now(),
                    targetSec: 10,
                    label: 'Test',
                    alert: s.settings.restAlert,
                  );
                  // Clear the test, unless a real workout has started meanwhile
                  // (cancelling then would remove its rest timer too).
                  Future<void>.delayed(const Duration(seconds: 30), () {
                    if (s.activeSession == null) s.reminders.cancelRest();
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Test sent. Leave the app to see the clock and the pop-up.'),
                    ));
                  }
                },
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: const Text('Send a test'),
              ),
            ),
          if (s.settings.restNotification)
            SettingRow(
              label: 'Pop-up when rest is up',
              note: 'A banner drops down when you reach the rest target',
              trailing: Toggle(
                label: 'Pop-up when rest is up',
                value: s.settings.restAlert,
                onChanged: (v) async {
                  if (v) {
                    final onTime = await s.reminders.requestExactAlarms();
                    if (!onTime && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                          'Turned on, but without "Alarms and reminders" permission '
                          'the pop-up can arrive a little late.',
                        ),
                      ));
                    }
                  }
                  s.setSettings(s.settings.copyWith(restAlert: v));
                },
              ),
            ),
          const _RestSoundRow(),
          if (minute != null)
            SettingRow(
              label: 'Reminder time',
              trailing: TextButton(
                onPressed: () => _pickTime(context, s),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: Text(_time(context, minute)),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Progress photos', style: AppText.body(c)),
                Text(
                  'How often Home reminds you to take them',
                  style: AppText.quiet(c),
                ),
                const SizedBox(height: 10),
                Segmented<int>(
                  label: 'Progress photo interval',
                  options: const [(1, 'Weekly'), (2, '2 wks'), (4, '4 wks'), (0, 'Off')],
                  value: s.settings.photoIntervalWeeks,
                  onChanged: (v) => s.setSettings(s.settings.copyWith(photoIntervalWeeks: v)),
                ),
              ],
            ),
          ),
          SettingRow(
            label: 'Sleep goal',
            note: 'Shown on the Sleep chart',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoundButton(
                  icon: Icons.remove_rounded,
                  label: 'Less sleep goal',
                  onTap: goal <= 5
                      ? null
                      : () => s.setSettings(s.settings.copyWith(sleepGoalHours: goal - 0.5)),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${oneDecimal(goal)} h',
                    textAlign: TextAlign.center,
                    style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                _RoundButton(
                  icon: Icons.add_rounded,
                  label: 'More sleep goal',
                  onTap: goal >= 11
                      ? null
                      : () => s.setSettings(s.settings.copyWith(sleepGoalHours: goal + 0.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: onTap == null ? c.muted : c.text),
        ),
      ),
    );
  }
}

class _YourData extends StatefulWidget {
  const _YourData();

  @override
  State<_YourData> createState() => _YourDataState();
}

class _YourDataState extends State<_YourData> {
  bool _withPhotos = true;
  bool _working = false;

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// First line of an error, kept short enough for a message bar.
  String _brief(Object e) {
    final line = e.toString().split('\n').first.trim();
    return line.length > 140 ? '${line.substring(0, 140)}…' : line;
  }

  Future<void> _export(AppState s) async {
    setState(() => _working = true);
    try {
      final photos =
          _withPhotos ? await s.photosForBackup() : const <BackupPhoto>[];
      // Encoding a backup with photos is heavy, so it runs off the UI thread.
      final bytes = await compute(encodeBackupBytes, (s.snapshot, photos));
      final name = 'fitapp-backup-${dayKey(DateTime.now())}.json';
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save your Pump and Plate backup',
        fileName: name,
        bytes: bytes,
      );
      if (saved == null) return;
      s.markExported();
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      if (mounted) {
        _toast(photos.isEmpty
            ? 'Backup saved as $name.'
            : 'Backup saved as $name with ${photos.length} photos ($mb MB).');
      }
    } catch (e) {
      if (mounted) _toast('Couldn\'t save the backup. ${_brief(e)}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _exportCsv(AppState s) async {
    try {
      final bytes = zipFiles(buildSpreadsheets(s));
      final name = 'fitapp-spreadsheets-${dayKey(DateTime.now())}.zip';
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save spreadsheets',
        fileName: name,
        bytes: bytes,
      );
      if (saved != null && mounted) {
        _toast('Saved $name: six CSV files that open in Excel or Google Sheets.');
      }
    } catch (e) {
      if (mounted) _toast('Couldn\'t save the spreadsheets. ${_brief(e)}');
    }
  }

  Future<void> _import(AppState s) async {
    final Backup backup;
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      setState(() => _working = true);
      final bytes = await file.readAsBytes();
      backup = await compute(decodeBackupBytes, bytes);
    } on BackupError catch (e) {
      if (mounted) {
        setState(() => _working = false);
        _toast(e.message);
      }
      return;
    } catch (e) {
      if (mounted) {
        setState(() => _working = false);
        _toast('Couldn\'t open that file. ${_brief(e)}');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _working = false);
    final data = backup.data;
    final c = AppColors.of(context);
    final photoNote = backup.photos.isEmpty
        ? ''
        : ' It also has ${backup.photos.length} progress photos, which are '
            'added alongside yours (same day and pose: the backup\'s is kept).';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Restore this backup?'),
        content: Text(
          'It has ${data.weighIns.length} weigh-ins and ${data.sleep.length} '
          'nights of sleep. Your profile, goal and settings will be replaced '
          'by the backup\'s. Weigh-ins and sleep are merged by date; where '
          'both have the same day, the backup\'s entry is kept.$photoNote',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    s.importBackup(data);
    var restored = 0;
    if (backup.photos.isNotEmpty) {
      setState(() => _working = true);
      restored = await s.importPhotos(backup.photos);
      if (mounted) setState(() => _working = false);
    }
    if (mounted) {
      _toast(restored == 0
          ? 'Backup restored.'
          : 'Backup restored, including $restored photos.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final last = s.settings.lastExport;
    final days = last == null ? null : daysBetween(last, DateTime.now());
    final status = last == null
        ? 'No backup saved yet.'
        : 'Last backup ${longDate(last)}'
            '${days != null && days > 0 ? ', $days ${days == 1 ? 'day' : 'days'} ago' : ', today'}.';
    final photoCount = s.photos.length;

    return SectionCard(
      title: 'Your data',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Everything lives on this phone. Uninstalling the app deletes it, '
            'so save a backup now and then, especially before switching phones.',
            style: AppText.body(c),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: AppText.quiet(c).copyWith(
              color: last == null || (days ?? 0) > 30 ? c.protein : c.muted,
            ),
          ),
          if (photoCount > 0)
            SettingRow(
              label: 'Include progress photos',
              note: '$photoCount photos, about '
                  '${(photoCount * 0.5).toStringAsFixed(photoCount < 4 ? 1 : 0)} MB more',
              trailing: Toggle(
                label: 'Include progress photos',
                value: _withPhotos,
                onChanged: (v) => setState(() => _withPhotos = v),
              ),
            ),
          const SizedBox(height: 14),
          if (_working)
            Container(
              height: 48,
              alignment: Alignment.center,
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SmallButton(label: 'Save backup', onTap: () => _export(s)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SmallButton(
                    label: 'Restore',
                    quiet: true,
                    onTap: () => _import(s),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          SmallButton(
            label: 'Export spreadsheets (CSV)',
            quiet: true,
            onTap: () => _exportCsv(s),
          ),
          const SizedBox(height: 8),
          Text(
            'The backup is one .json file you can keep in Downloads, Google '
            'Drive or anywhere else. It includes your profile, goals, '
            'settings, weigh-ins, sleep, measurements, workouts, foods, '
            'recipes, your food log and meal plan and, if you choose, your '
            'progress photos.',
            style: AppText.quiet(c).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StoresCard extends StatelessWidget {
  const _StoresCard();

  Future<String?> _askName(BuildContext context, String title, String initial) async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          cursorColor: c.accent,
          decoration: const InputDecoration(hintText: 'e.g. Aldi'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(ctrl.text.trim()),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return name == null || name.isEmpty ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    return SectionCard(
      title: 'Groceries',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your stores. Set prices per store in each food (Food > Foods); '
            'Food > Groceries finds the cheapest way to shop them.',
            style: AppText.quiet(c),
          ),
          const SizedBox(height: 10),
          Text('Most stores per trip', style: AppText.body(c)),
          const SizedBox(height: 6),
          Segmented<int>(
            label: 'Most stores per trip',
            options: const [(1, '1'), (2, '2'), (3, '3'), (4, '4'), (5, '5')],
            value: s.settings.maxStores.clamp(1, 5),
            onChanged: (v) => s.setSettings(s.settings.copyWith(maxStores: v)),
          ),
          const SizedBox(height: 4),
          SettingRow(
            label: 'Search online for branded foods',
            note: s.settings.onlineFoodSearch
                ? 'Open Food Facts; only your search words are sent'
                : 'Off: food search uses the 8,000+ foods built into the app',
            trailing: Toggle(
              key: const ValueKey('online-food-search'),
              label: 'Search online for branded foods',
              value: s.settings.onlineFoodSearch,
              onChanged: (v) => s.setSettings(s.settings.copyWith(onlineFoodSearch: v)),
            ),
          ),
          SettingRow(
            label: 'Look up scanned barcodes online',
            note: switch (s.settings.barcodeOnline) {
              null => 'Asks the first time you scan something new',
              true => 'Open Food Facts; only the barcode number is sent',
              false => 'Off: new products are typed in from the label',
            },
            trailing: Toggle(
              key: const ValueKey('barcode-online-toggle'),
              label: 'Look up scanned barcodes online',
              value: s.settings.barcodeOnline == true,
              onChanged: (v) => s.setSettings(s.settings.copyWith(barcodeOnline: v)),
            ),
          ),
          const SizedBox(height: 8),
          for (final st in s.stores)
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Row(
                children: [
                  Expanded(child: Text(st.name, style: AppText.body(c))),
                  TextButton(
                    onPressed: () async {
                      final n = await _askName(context, 'Rename store', st.name);
                      if (n != null) s.saveStore(st.copyWith(name: n));
                    },
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: const Text('Rename'),
                  ),
                  IconButton(
                    tooltip: 'Remove ${st.name}',
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          backgroundColor: c.surface,
                          title: Text('Remove ${st.name}?'),
                          content: const Text('Its prices are removed from your foods too.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dialog).pop(false),
                              style: TextButton.styleFrom(foregroundColor: c.muted),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(dialog).pop(true),
                              style: TextButton.styleFrom(foregroundColor: c.protein),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) s.deleteStore(st);
                    },
                    icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SmallButton(
            label: 'Add a store',
            quiet: true,
            onTap: () async {
              final n = await _askName(context, 'New store', '');
              if (n != null) s.saveStore(GroceryStore(id: newId('st'), name: n));
            },
          ),
        ],
      ),
    );
  }
}

/// Asks for a PIN in a dialog. Returns null when cancelled.
Future<String?> _askPin(BuildContext context, String title, {String? note}) {
  final c = AppColors.of(context);
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) ...[
            Text(note, style: AppText.quiet(c)),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            cursorColor: c.accent,
            style: const TextStyle(fontSize: 22, letterSpacing: 6),
            decoration: const InputDecoration(hintText: '4 to 8 digits', counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (ctrl.text.length >= 4) Navigator.of(dialog).pop(ctrl.text);
          },
          style: TextButton.styleFrom(foregroundColor: c.accent),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _LockCard extends StatelessWidget {
  const _LockCard();

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// New PIN entered twice. Null if cancelled or they didn't match.
  Future<String?> _newPin(BuildContext context) async {
    final first = await _askPin(
      context,
      'Choose a PIN',
      note: 'You\'ll enter it to open Pump and Plate. It can\'t be recovered, so pick '
          'one you\'ll remember, and keep a recent backup.',
    );
    if (first == null || !context.mounted) return null;
    final again = await _askPin(context, 'Enter it again');
    if (again == null || !context.mounted) return null;
    if (again != first) {
      _toast(context, 'The PINs didn\'t match. Nothing was changed.');
      return null;
    }
    return first;
  }

  Future<bool> _confirmCurrent(BuildContext context, AppState s) async {
    final pin = await _askPin(context, 'Enter your current PIN');
    if (pin == null || !context.mounted) return false;
    if (s.checkPin(pin, hashPin)) return true;
    _toast(context, 'That PIN isn\'t right.');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final cfg = s.settings;
    return SectionCard(
      title: 'App lock',
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            divider: false,
            label: 'Lock Pump and Plate',
            note: 'Ask for a PIN, or your fingerprint, to open the app',
            trailing: Toggle(
              key: const ValueKey('lock-toggle'),
              label: 'Lock Pump and Plate',
              value: cfg.lockEnabled,
              onChanged: (v) async {
                if (v) {
                  final pin = await _newPin(context);
                  if (pin != null) {
                    s.setPin(pin, hashPin, newSalt());
                    if (context.mounted) _toast(context, 'App lock is on.');
                  }
                } else if (await _confirmCurrent(context, s)) {
                  s.turnOffLock();
                  if (context.mounted) _toast(context, 'App lock is off.');
                }
              },
            ),
          ),
          if (cfg.lockEnabled) ...[
            SettingRow(
              label: 'Unlock with fingerprint',
              note: 'The PIN always works too',
              trailing: Toggle(
                label: 'Unlock with fingerprint',
                value: cfg.lockBiometric,
                onChanged: (v) async {
                  if (!v) {
                    s.setSettings(s.settings.copyWith(lockBiometric: false));
                    return;
                  }
                  final u = LocalUnlocker();
                  if (!await u.available()) {
                    if (context.mounted) {
                      _toast(context, 'No fingerprint or face is set up on this phone.');
                    }
                    return;
                  }
                  if (await u.authenticate()) {
                    s.setSettings(s.settings.copyWith(lockBiometric: true));
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            Text('Lock again after leaving the app for', style: AppText.body(c)),
            const SizedBox(height: 6),
            Segmented<int>(
              label: 'Lock again after',
              options: const [(30, '30 sec'), (300, '5 min'), (1800, '30 min')],
              value: const [30, 300, 1800].contains(cfg.lockAfterSec) ? cfg.lockAfterSec : 30,
              onChanged: (v) => s.setSettings(s.settings.copyWith(lockAfterSec: v)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  if (!await _confirmCurrent(context, s)) return;
                  if (!context.mounted) return;
                  final pin = await _newPin(context);
                  if (pin != null) {
                    s.setPin(pin, hashPin, newSalt());
                    if (context.mounted) _toast(context, 'PIN changed.');
                  }
                },
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: const Text('Change PIN'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Automatic backups into a folder the user picks once.
class _AutoBackups extends StatefulWidget {
  const _AutoBackups();

  @override
  State<_AutoBackups> createState() => _AutoBackupsState();
}

class _AutoBackupsState extends State<_AutoBackups> {
  bool _working = false;

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Opens the folder picker; true if a folder was chosen.
  Future<bool> _choose(AppState s) async {
    final folder = ServicesScope.of(context).backups;
    try {
      final picked = await folder.pick();
      if (picked == null) return false;
      s.setSettings(s.settings.copyWith(backupUri: picked.uri, backupFolder: picked.name, backupError: null));
      return true;
    } catch (e) {
      if (mounted) _toast('Couldn\'t open the folder picker. ${'$e'.split('\n').first}');
      return false;
    }
  }

  Future<void> _backUpNow(AppState s) async {
    final folder = ServicesScope.of(context).backups;
    setState(() => _working = true);
    final error = await runAutoBackup(s, folder, force: true);
    if (!mounted) return;
    setState(() => _working = false);
    _toast(error ?? 'Backup saved to ${s.settings.backupFolder ?? 'your folder'}.');
  }

  Future<void> _toggle(AppState s, bool on) async {
    if (!on) {
      s.setSettings(s.settings.copyWith(autoBackup: false));
      return;
    }
    if (s.settings.backupUri == null && !await _choose(s)) return;
    if (!mounted) return;
    s.setSettings(s.settings.copyWith(autoBackup: true));
    await _backUpNow(s); // the first one right away, so you know it works
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final cfg = s.settings;
    final last = cfg.lastAutoBackup;
    final size = cfg.backupBytes == null ? '' : ' · ${(cfg.backupBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
    final status = cfg.backupError ??
        (last == null
            ? 'No automatic backup yet.'
            : 'Last one ${longDate(last)}, ${TimeOfDay.fromDateTime(last).format(context)}$size.');
    return SectionCard(
      title: 'Automatic backups',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Saves a backup to a folder you choose whenever you open Pump and Plate and one is due. Pick a '
            'folder another app syncs (like OneDrive, Dropbox or Syncthing) to keep a copy off the phone.',
            style: AppText.quiet(c).copyWith(fontSize: 14),
          ),
          SettingRow(
            label: 'Automatic backups',
            note: cfg.autoBackup ? (cfg.backupDays == 1 ? 'Daily' : 'Weekly') : 'Off',
            trailing: Toggle(
              key: const ValueKey('auto-backup-toggle'),
              label: 'Automatic backups',
              value: cfg.autoBackup,
              onChanged: (v) => _toggle(s, v),
            ),
          ),
          if (cfg.autoBackup || cfg.backupUri != null) ...[
            SettingRow(
              label: 'Folder',
              note: cfg.backupFolder ?? 'None chosen',
              trailing: TextButton(
                onPressed: _working ? null : () => _choose(s),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: Text(cfg.backupUri == null ? 'Choose' : 'Change'),
              ),
            ),
            const SizedBox(height: 10),
            Text('How often', style: AppText.body(c)),
            const SizedBox(height: 6),
            Segmented<int>(
              label: 'How often',
              options: const [(1, 'Daily'), (7, 'Weekly')],
              value: cfg.backupDays == 1 ? 1 : 7,
              onChanged: (v) => s.setSettings(s.settings.copyWith(backupDays: v)),
            ),
            const SizedBox(height: 10),
            Text('Keep the newest', style: AppText.body(c)),
            const SizedBox(height: 6),
            Segmented<int>(
              label: 'Backups to keep',
              options: const [(3, '3'), (5, '5'), (10, '10')],
              value: const [3, 5, 10].contains(cfg.backupKeep) ? cfg.backupKeep : 5,
              onChanged: (v) => s.setSettings(s.settings.copyWith(backupKeep: v)),
            ),
            if (s.photos.isNotEmpty)
              SettingRow(
                label: 'Include progress photos',
                note: '${s.photos.length} photos make each backup bigger',
                trailing: Toggle(
                  label: 'Include progress photos in automatic backups',
                  value: cfg.backupPhotos,
                  onChanged: (v) => s.setSettings(s.settings.copyWith(backupPhotos: v)),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              status,
              style: AppText.quiet(c).copyWith(color: cfg.backupError != null ? c.protein : c.muted),
            ),
            const SizedBox(height: 10),
            if (_working)
              Container(
                height: 48,
                alignment: Alignment.center,
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
              )
            else
              SmallButton(
                label: 'Back up now',
                quiet: true,
                onTap: () => cfg.backupUri == null ? _choose(s) : _backUpNow(s),
              ),
          ],
        ],
      ),
    );
  }
}

/// The sound played when a rest is up: the phone's, or one you pick.
class _RestSoundRow extends StatelessWidget {
  const _RestSoundRow();

  Future<void> _pick(BuildContext context, AppState s) async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    final String? path = picked.path;
    if (path == null || path.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open that file.')));
      }
      return;
    }
    try {
      final (saved, name) = await importRestSound(path);
      s.setSettings(s.settings.copyWith(restSoundPath: saved, restSoundName: name));
      await Phone.playSound(saved);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is RestSoundError ? e.message : 'Couldn\'t use that file.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final path = s.settings.restSoundPath;
    return SettingRow(
      label: 'Rest-up sound',
      note: path == null
          ? 'The phone\'s notification sound. Pick any sound file to play yours instead.'
          : '${s.settings.restSoundName ?? 'Your sound'}. Plays when rest is up while the app is open.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (path != null) ...[
            IconButton(
              tooltip: 'Play it',
              onPressed: () => Phone.playSound(path),
              icon: Icon(Icons.play_arrow_rounded, color: c.accent),
            ),
            IconButton(
              tooltip: 'Back to the phone\'s sound',
              onPressed: () {
                clearRestSounds();
                s.setSettings(s.settings.copyWith(restSoundPath: null, restSoundName: null));
              },
              icon: Icon(Icons.close_rounded, color: c.muted),
            ),
          ],
          TextButton(
            key: const ValueKey('pick-rest-sound'),
            onPressed: () => _pick(context, s),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: Text(path == null ? 'Choose' : 'Change'),
          ),
        ],
      ),
    );
  }
}
