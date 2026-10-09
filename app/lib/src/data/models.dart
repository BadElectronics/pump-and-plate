import 'dart:convert';

import '../calc/calc.dart';

/// Marker meaning "leave this field as it is" in copyWith, so nullable
/// fields can still be cleared by passing null.
const Object _keep = Object();

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

double? _toDouble(Object? v) => v == null ? null : (v as num).toDouble();

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The first day of the week holding [d]: Sunday when [sundayFirst], else Monday.
DateTime weekStartOf(DateTime d, {required bool sundayFirst}) {
  final back = sundayFirst ? d.weekday % 7 : d.weekday - 1;
  return DateTime(d.year, d.month, d.day - back);
}

/// True during the dark hours from [fromMin] to [toMin] (minutes past
/// midnight). The range may cross midnight (8 PM to 7 AM). Equal times
/// mean no dark hours.
bool isNightTime(DateTime now, int fromMin, int toMin) {
  if (fromMin == toMin) return false;
  final m = now.hour * 60 + now.minute;
  return fromMin < toMin ? (m >= fromMin && m < toMin) : (m >= fromMin || m < toMin);
}

/// The next moment the theme flips (at [fromMin] or [toMin]) after [now].
DateTime nextThemeFlip(DateTime now, int fromMin, int toMin) {
  DateTime at(int dayOffset, int minute) => DateTime(now.year, now.month, now.day + dayOffset, minute ~/ 60, minute % 60);
  final candidates = [for (final d in [0, 1]) for (final m in [fromMin, toMin]) at(d, m)]
    ..retainWhere((t) => t.isAfter(now))
    ..sort();
  return candidates.first;
}

/// The weekdays in display order (1 = Monday ... 7 = Sunday).
List<int> weekdayOrder({required bool sundayFirst}) =>
    sundayFirst ? const [7, 1, 2, 3, 4, 5, 6] : const [1, 2, 3, 4, 5, 6, 7];

/// Whole calendar days from [a] to [b] (negative if [b] is earlier).
/// Counts dates, not hours, so clock changes can't make a day 23 or 25
/// hours long and throw the count off by one.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _now() => DateTime.now().toIso8601String();

// ---------------------------------------------------------------- profile

class Profile {
  const Profile({
    this.birthday,
    this.heightCm,
    this.sex = Sex.male,
    this.activity = Activity.light,
    this.waistCm,
  });

  final DateTime? birthday;
  final double? heightCm;
  final Sex sex;
  final Activity activity;
  final double? waistCm;

  Profile copyWith({
    Object? birthday = _keep,
    Object? heightCm = _keep,
    Sex? sex,
    Activity? activity,
    Object? waistCm = _keep,
  }) {
    return Profile(
      birthday:
          identical(birthday, _keep) ? this.birthday : birthday as DateTime?,
      heightCm:
          identical(heightCm, _keep) ? this.heightCm : heightCm as double?,
      sex: sex ?? this.sex,
      activity: activity ?? this.activity,
      waistCm: identical(waistCm, _keep) ? this.waistCm : waistCm as double?,
    );
  }

  Map<String, Object?> toRow() => {
        'id': 1,
        'birthday': birthday == null ? null : dayKey(birthday!),
        'height_cm': heightCm,
        'sex': sex.name,
        'activity': activity.name,
        'waist_cm': waistCm,
        'updated_at': _now(),
      };

  factory Profile.fromRow(Map<String, Object?> r) => Profile(
        birthday: r['birthday'] == null
            ? null
            : DateTime.tryParse(r['birthday'] as String),
        heightCm: _toDouble(r['height_cm']),
        sex: _enumByName(Sex.values, r['sex'], Sex.male),
        activity: _enumByName(Activity.values, r['activity'], Activity.light),
        waistCm: _toDouble(r['waist_cm']),
      );
}

// ---------------------------------------------------------------- goal

class Goal {
  const Goal({
    this.mode = GoalMode.lose,
    this.targetWeightKg,
    this.paceKgPerWeek = 0.34,
    this.bodyFatNowPct,
    this.bodyFatGoalPct,
    this.proteinGPerKg = defaultProteinGPerKg,
    this.proteinBasis = ProteinBasis.current,
  });

  final GoalMode mode;
  final double? targetWeightKg;
  final double paceKgPerWeek;
  final double? bodyFatNowPct;
  final double? bodyFatGoalPct;
  final double proteinGPerKg;
  final ProteinBasis proteinBasis;

  Goal copyWith({
    GoalMode? mode,
    Object? targetWeightKg = _keep,
    double? paceKgPerWeek,
    Object? bodyFatNowPct = _keep,
    Object? bodyFatGoalPct = _keep,
    double? proteinGPerKg,
    ProteinBasis? proteinBasis,
  }) {
    return Goal(
      mode: mode ?? this.mode,
      targetWeightKg: identical(targetWeightKg, _keep)
          ? this.targetWeightKg
          : targetWeightKg as double?,
      paceKgPerWeek: paceKgPerWeek ?? this.paceKgPerWeek,
      bodyFatNowPct: identical(bodyFatNowPct, _keep)
          ? this.bodyFatNowPct
          : bodyFatNowPct as double?,
      bodyFatGoalPct: identical(bodyFatGoalPct, _keep)
          ? this.bodyFatGoalPct
          : bodyFatGoalPct as double?,
      proteinGPerKg: proteinGPerKg ?? this.proteinGPerKg,
      proteinBasis: proteinBasis ?? this.proteinBasis,
    );
  }

  Map<String, Object?> toRow() => {
        'id': 1,
        'mode': mode.name,
        'target_weight_kg': targetWeightKg,
        'pace_kg_per_week': paceKgPerWeek,
        'bf_now_pct': bodyFatNowPct,
        'bf_goal_pct': bodyFatGoalPct,
        'protein_g_per_kg': proteinGPerKg,
        'protein_basis': proteinBasis.name,
        'updated_at': _now(),
      };

  factory Goal.fromRow(Map<String, Object?> r) => Goal(
        mode: _enumByName(GoalMode.values, r['mode'], GoalMode.lose),
        targetWeightKg: _toDouble(r['target_weight_kg']),
        paceKgPerWeek: _toDouble(r['pace_kg_per_week']) ?? 0.34,
        bodyFatNowPct: _toDouble(r['bf_now_pct']),
        bodyFatGoalPct: _toDouble(r['bf_goal_pct']),
        proteinGPerKg:
            _toDouble(r['protein_g_per_kg']) ?? defaultProteinGPerKg,
        proteinBasis: _enumByName(
          ProteinBasis.values,
          r['protein_basis'],
          ProteinBasis.current,
        ),
      );
}

// ---------------------------------------------------------------- settings

class AppSettings {
  const AppSettings({
    this.themeId = 'earth',
    this.followSystem = false,
    this.reduceMotion = false,
    this.units = Units.imperial,
    this.sleepGoalHours = 8.0,
    this.reminderMinute,
    this.onboarded = false,
    this.lastExport,
    this.photoIntervalWeeks = 1,
    this.measurementsOn = false,
    this.restNotification = true,
    this.restAlert = true,
    this.restAlertAsked = false,
    this.maxStores = 3,
    this.useLearnedMaintenance = true,
    this.lockEnabled = false,
    this.lockPinHash,
    this.lockPinSalt,
    this.lockBiometric = false,
    this.lockAfterSec = 30,
    this.summarySeenWeek,
    this.nickname,
    this.nicknameAsked = false,
    this.ownListStore,
    this.barcodeOnline,
    this.tourSeen = false,
    this.aiTier,
    this.autoBackup = false,
    this.backupDays = 7,
    this.backupKeep = 5,
    this.backupPhotos = true,
    this.backupUri,
    this.backupFolder,
    this.lastAutoBackup,
    this.backupError,
    this.backupBytes,
    this.weekStartsSunday = true,
    this.darkSchedule = false,
    this.darkFrom = 20 * 60,
    this.darkTo = 7 * 60,
    this.darkThemeId = 'night',
    this.waterGoalMl = 0,
    this.aiIdleUnload = false,
    this.onlineFoodSearch = false,
    this.aiNoticeOff = false,
    this.restSoundPath,
    this.restSoundName,
    this.supplementsOn = false,
    this.headsMap = false,
  });

  final String themeId;
  final bool followSystem;
  final bool reduceMotion;
  final Units units;
  final double sleepGoalHours;

  /// Morning reminder time in minutes after midnight; null means off.
  final int? reminderMinute;

  /// True once first-run setup is finished or skipped.
  final bool onboarded;

  /// When a backup was last saved from this phone.
  final DateTime? lastExport;

  /// Weeks between progress photo check-ins; 0 means off.
  final int photoIntervalWeeks;

  /// Optional body measurements (Progress > Body). Off by default.
  final bool measurementsOn;

  /// Show the running rest clock as a notification outside the app.
  final bool restNotification;

  /// Pop-up (heads-up) alert when the rest target is reached.
  final bool restAlert;

  /// Whether we've explained the "Alarms and reminders" permission once.
  final bool restAlertAsked;

  /// Most stores the grocery list may split a trip across.
  final int maxStores;

  /// Use maintenance learned from food and weight logs once it's available.
  final bool useLearnedMaintenance;

  /// App lock (off by default). The PIN is stored only as a salted hash.
  final bool lockEnabled;
  final String? lockPinHash;
  final String? lockPinSalt;

  /// Fingerprint (or face) unlock as well as the PIN.
  final bool lockBiometric;

  /// Lock again after being away this long.
  final int lockAfterSec;

  /// Week (Monday's date key) whose summary was dismissed on Home.
  final String? summarySeenWeek;

  /// What the app calls you (optional).
  final String? nickname;

  /// The one-time nickname question has been shown.
  final bool nicknameAsked;

  /// Store chosen for your own "from your foods" grocery list.
  final String? ownListStore;

  /// Look up new barcodes online (Open Food Facts)? Null until asked:
  /// the app asks the first time you scan something it doesn't know.
  final bool? barcodeOnline;

  /// The one-minute app tour has been shown (or skipped).
  final bool tourSeen;

  /// The on-device AI model chosen and downloaded ('light', 'medium', 'high'),
  /// or null if none is set up.
  final String? aiTier;

  /// Automatic backups into a folder the user picked, when the app opens.
  final bool autoBackup;

  /// How often: 1 (daily) or 7 (weekly).
  final int backupDays;

  /// How many automatic backups to keep (older ones are deleted).
  final int backupKeep;
  final bool backupPhotos;

  /// The chosen folder (an Android document-tree address) and its name.
  final String? backupUri;
  final String? backupFolder;
  final DateTime? lastAutoBackup;

  /// Why the last automatic backup failed, or null.
  final String? backupError;
  final int? backupBytes;

  /// Weeks run Sunday to Saturday (else Monday to Sunday): the calendar,
  /// the weekly summary and the grocery week all follow this.
  final bool weekStartsSunday;

  /// Dark theme during set hours: from [darkFrom] to [darkTo] (minutes past
  /// midnight; the range can cross midnight).
  final bool darkSchedule;
  final int darkFrom;
  final int darkTo;

  /// Which dark theme to use at night (or when following the phone).
  final String darkThemeId;

  /// Daily water goal in ml; 0 means the default (64 oz, or 2 L in metric).
  final double waterGoalMl;

  /// Free the AI model's memory after 5 minutes away from Chat.
  final bool aiIdleUnload;

  /// Food search can also look online (Open Food Facts) for branded
  /// products. Off by default: search uses the foods built into the app.
  final bool onlineFoodSearch;

  /// "Don't remind me again" was ticked on the AI is experimental notice.
  final bool aiNoticeOff;

  /// A sound file the user chose (copied into the app) to play when rest is
  /// up, and its name to show; null for the phone's notification sound.
  final String? restSoundPath;
  final String? restSoundName;

  /// The supplement log is shown (Log screen and Settings).
  final bool supplementsOn;

  /// The muscle map shows muscle heads (the advanced map).
  final bool headsMap;

  AppSettings copyWith({
    String? themeId,
    bool? followSystem,
    bool? reduceMotion,
    Units? units,
    double? sleepGoalHours,
    Object? reminderMinute = _keep,
    bool? onboarded,
    DateTime? lastExport,
    int? photoIntervalWeeks,
    bool? measurementsOn,
    bool? restNotification,
    bool? restAlert,
    bool? restAlertAsked,
    int? maxStores,
    bool? useLearnedMaintenance,
    bool? lockEnabled,
    Object? lockPinHash = _keep,
    Object? lockPinSalt = _keep,
    bool? lockBiometric,
    int? lockAfterSec,
    String? summarySeenWeek,
    Object? nickname = _keep,
    bool? nicknameAsked,
    Object? ownListStore = _keep,
    Object? barcodeOnline = _keep,
    bool? tourSeen,
    Object? aiTier = _keep,
    bool? autoBackup,
    int? backupDays,
    int? backupKeep,
    bool? backupPhotos,
    Object? backupUri = _keep,
    Object? backupFolder = _keep,
    Object? lastAutoBackup = _keep,
    Object? backupError = _keep,
    Object? backupBytes = _keep,
    bool? weekStartsSunday,
    bool? darkSchedule,
    int? darkFrom,
    int? darkTo,
    String? darkThemeId,
    double? waterGoalMl,
    bool? aiIdleUnload,
    bool? onlineFoodSearch,
    bool? aiNoticeOff,
    Object? restSoundPath = _keep,
    Object? restSoundName = _keep,
    bool? supplementsOn,
    bool? headsMap,
  }) {
    return AppSettings(
      themeId: themeId ?? this.themeId,
      followSystem: followSystem ?? this.followSystem,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      units: units ?? this.units,
      sleepGoalHours: sleepGoalHours ?? this.sleepGoalHours,
      reminderMinute: identical(reminderMinute, _keep)
          ? this.reminderMinute
          : reminderMinute as int?,
      onboarded: onboarded ?? this.onboarded,
      lastExport: lastExport ?? this.lastExport,
      photoIntervalWeeks: photoIntervalWeeks ?? this.photoIntervalWeeks,
      measurementsOn: measurementsOn ?? this.measurementsOn,
      restNotification: restNotification ?? this.restNotification,
      restAlert: restAlert ?? this.restAlert,
      restAlertAsked: restAlertAsked ?? this.restAlertAsked,
      maxStores: maxStores ?? this.maxStores,
      useLearnedMaintenance: useLearnedMaintenance ?? this.useLearnedMaintenance,
      lockEnabled: lockEnabled ?? this.lockEnabled,
      lockPinHash: identical(lockPinHash, _keep) ? this.lockPinHash : lockPinHash as String?,
      lockPinSalt: identical(lockPinSalt, _keep) ? this.lockPinSalt : lockPinSalt as String?,
      lockBiometric: lockBiometric ?? this.lockBiometric,
      lockAfterSec: lockAfterSec ?? this.lockAfterSec,
      summarySeenWeek: summarySeenWeek ?? this.summarySeenWeek,
      nickname: identical(nickname, _keep) ? this.nickname : nickname as String?,
      nicknameAsked: nicknameAsked ?? this.nicknameAsked,
      ownListStore: identical(ownListStore, _keep) ? this.ownListStore : ownListStore as String?,
      barcodeOnline: identical(barcodeOnline, _keep) ? this.barcodeOnline : barcodeOnline as bool?,
      tourSeen: tourSeen ?? this.tourSeen,
      aiTier: identical(aiTier, _keep) ? this.aiTier : aiTier as String?,
      autoBackup: autoBackup ?? this.autoBackup,
      backupDays: backupDays ?? this.backupDays,
      backupKeep: backupKeep ?? this.backupKeep,
      backupPhotos: backupPhotos ?? this.backupPhotos,
      backupUri: identical(backupUri, _keep) ? this.backupUri : backupUri as String?,
      backupFolder: identical(backupFolder, _keep) ? this.backupFolder : backupFolder as String?,
      lastAutoBackup: identical(lastAutoBackup, _keep) ? this.lastAutoBackup : lastAutoBackup as DateTime?,
      backupError: identical(backupError, _keep) ? this.backupError : backupError as String?,
      backupBytes: identical(backupBytes, _keep) ? this.backupBytes : backupBytes as int?,
      weekStartsSunday: weekStartsSunday ?? this.weekStartsSunday,
      darkSchedule: darkSchedule ?? this.darkSchedule,
      darkFrom: darkFrom ?? this.darkFrom,
      darkTo: darkTo ?? this.darkTo,
      darkThemeId: darkThemeId ?? this.darkThemeId,
      waterGoalMl: waterGoalMl ?? this.waterGoalMl,
      aiIdleUnload: aiIdleUnload ?? this.aiIdleUnload,
      onlineFoodSearch: onlineFoodSearch ?? this.onlineFoodSearch,
      aiNoticeOff: aiNoticeOff ?? this.aiNoticeOff,
      restSoundPath: identical(restSoundPath, _keep) ? this.restSoundPath : restSoundPath as String?,
      restSoundName: identical(restSoundName, _keep) ? this.restSoundName : restSoundName as String?,
      supplementsOn: supplementsOn ?? this.supplementsOn,
      headsMap: headsMap ?? this.headsMap,
    );
  }

  Map<String, Object?> toRow() => {
        'id': 1,
        'theme': themeId,
        'follow_system': followSystem ? 1 : 0,
        'reduce_motion': reduceMotion ? 1 : 0,
        'units': units.name,
        'sleep_goal_hours': sleepGoalHours,
        'reminder_minute': reminderMinute,
        'onboarded': onboarded ? 1 : 0,
        'last_export': lastExport?.toIso8601String(),
        'photo_interval_weeks': photoIntervalWeeks,
        'measurements_on': measurementsOn ? 1 : 0,
        'rest_notification': restNotification ? 1 : 0,
        'rest_alert': restAlert ? 1 : 0,
        'rest_alert_asked': restAlertAsked ? 1 : 0,
        'max_stores': maxStores,
        'use_learned': useLearnedMaintenance ? 1 : 0,
        'lock_enabled': lockEnabled ? 1 : 0,
        'lock_pin_hash': lockPinHash,
        'lock_pin_salt': lockPinSalt,
        'lock_biometric': lockBiometric ? 1 : 0,
        'lock_after_sec': lockAfterSec,
        'summary_seen_week': summarySeenWeek,
        'nickname': nickname,
        'nickname_asked': nicknameAsked ? 1 : 0,
        'own_list_store': ownListStore,
        'barcode_online': barcodeOnline == null ? null : (barcodeOnline! ? 1 : 0),
        'tour_seen': tourSeen ? 1 : 0,
        'ai_tier': aiTier,
        'auto_backup': autoBackup ? 1 : 0,
        'backup_days': backupDays,
        'backup_keep': backupKeep,
        'backup_photos': backupPhotos ? 1 : 0,
        'backup_uri': backupUri,
        'backup_folder': backupFolder,
        'last_auto_backup': lastAutoBackup?.toIso8601String(),
        'backup_error': backupError,
        'backup_bytes': backupBytes,
        'week_sunday': weekStartsSunday ? 1 : 0,
        'dark_schedule': darkSchedule ? 1 : 0,
        'dark_from': darkFrom,
        'dark_to': darkTo,
        'dark_theme': darkThemeId,
        'water_goal': waterGoalMl,
        'ai_idle_unload': aiIdleUnload ? 1 : 0,
        'online_food_search': onlineFoodSearch ? 1 : 0,
        'ai_notice_off': aiNoticeOff ? 1 : 0,
        'rest_sound': restSoundPath,
        'rest_sound_name': restSoundName,
        'supplements_on': supplementsOn ? 1 : 0,
        'heads_map': headsMap ? 1 : 0,
        'updated_at': _now(),
      };

  factory AppSettings.fromRow(Map<String, Object?> r) => AppSettings(
        themeId: (r['theme'] as String?) ?? 'earth',
        followSystem: r['follow_system'] == 1,
        reduceMotion: r['reduce_motion'] == 1,
        units: _enumByName(Units.values, r['units'], Units.imperial),
        sleepGoalHours: _toDouble(r['sleep_goal_hours']) ?? 8.0,
        reminderMinute: (r['reminder_minute'] as num?)?.toInt(),
        onboarded: r['onboarded'] == 1,
        lastExport: r['last_export'] is String
            ? DateTime.tryParse(r['last_export'] as String)
            : null,
        photoIntervalWeeks: (r['photo_interval_weeks'] as num?)?.toInt() ?? 1,
        measurementsOn: r['measurements_on'] == 1,
        restNotification: r['rest_notification'] != 0,
        restAlert: r['rest_alert'] != 0,
        restAlertAsked: r['rest_alert_asked'] == 1,
        maxStores: (r['max_stores'] as num?)?.toInt() ?? 3,
        useLearnedMaintenance: r['use_learned'] != 0,
        lockEnabled: r['lock_enabled'] == 1,
        lockPinHash: r['lock_pin_hash'] as String?,
        lockPinSalt: r['lock_pin_salt'] as String?,
        lockBiometric: r['lock_biometric'] == 1,
        lockAfterSec: (r['lock_after_sec'] as num?)?.toInt() ?? 30,
        summarySeenWeek: r['summary_seen_week'] as String?,
        nickname: (r['nickname'] as String?)?.trim().isEmpty ?? true ? null : r['nickname'] as String,
        nicknameAsked: r['nickname_asked'] == 1,
        ownListStore: r['own_list_store'] as String?,
        barcodeOnline: r['barcode_online'] == null ? null : r['barcode_online'] == 1,
        tourSeen: r['tour_seen'] == 1,
        aiTier: r['ai_tier'] as String?,
        autoBackup: r['auto_backup'] == 1,
        backupDays: (r['backup_days'] as int?) ?? 7,
        backupKeep: (r['backup_keep'] as int?) ?? 5,
        backupPhotos: r['backup_photos'] != 0,
        backupUri: r['backup_uri'] as String?,
        backupFolder: r['backup_folder'] as String?,
        lastAutoBackup: r['last_auto_backup'] == null ? null : DateTime.tryParse(r['last_auto_backup'] as String),
        backupError: r['backup_error'] as String?,
        backupBytes: r['backup_bytes'] as int?,
        weekStartsSunday: r['week_sunday'] != 0,
        darkSchedule: r['dark_schedule'] == 1,
        darkFrom: (r['dark_from'] as int?) ?? 20 * 60,
        darkTo: (r['dark_to'] as int?) ?? 7 * 60,
        darkThemeId: (r['dark_theme'] as String?) ?? 'night',
        waterGoalMl: (r['water_goal'] as num?)?.toDouble() ?? 0,
        aiIdleUnload: r['ai_idle_unload'] == 1,
        onlineFoodSearch: r['online_food_search'] == 1,
        aiNoticeOff: r['ai_notice_off'] == 1,
        restSoundPath: r['rest_sound'] as String?,
        restSoundName: r['rest_sound_name'] as String?,
        supplementsOn: r['supplements_on'] == 1,
        headsMap: r['heads_map'] == 1,
      );
}

// ---------------------------------------------------------------- weigh-in

class WeighIn {
  const WeighIn({
    required this.date,
    required this.weightKg,
    this.source = 'manual',
  });

  final DateTime date;
  final double weightKg;
  final String source;

  Map<String, Object?> toRow() => {
        'date': dayKey(date),
        'weight_kg': weightKg,
        'source': source,
        'updated_at': _now(),
      };

  factory WeighIn.fromRow(Map<String, Object?> r) => WeighIn(
        date: DateTime.parse(r['date'] as String),
        weightKg: (r['weight_kg'] as num).toDouble(),
        source: (r['source'] as String?) ?? 'manual',
      );
}

// ---------------------------------------------------------------- sleep

String _hhmm(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:'
    '${(minuteOfDay % 60).toString().padLeft(2, '0')}';

int? _parseHhmm(Object? v) {
  if (v is! String) return null;
  final parts = v.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// One night of sleep, filed under the morning you woke up.
/// Times are minutes after midnight; every field but the date is optional.
/// A drink of water, added through the day.
class WaterEntry {
  const WaterEntry({required this.id, required this.date, required this.ml, required this.at});

  final String id;

  /// The day it counts toward.
  final DateTime date;
  final double ml;

  /// When it was added.
  final DateTime at;

  Map<String, Object?> toRow() => {
        'id': id,
        'date': dayKey(date),
        'ml': ml,
        'at': at.toIso8601String(),
      };

  factory WaterEntry.fromRow(Map<String, Object?> r) => WaterEntry(
        id: r['id'] as String,
        date: DateTime.parse(r['date'] as String),
        ml: (r['ml'] as num).toDouble(),
        at: DateTime.tryParse('${r['at']}') ?? DateTime.parse(r['date'] as String),
      );
}

/// A supplement you take, with its usual amount ("Vitamin D, 2000 IU").
class Supplement {
  const Supplement({
    required this.id,
    required this.name,
    this.amount,
    this.unit = '',
    this.order = 0,
    this.active = true,
  });

  final String id;
  final String name;

  /// The usual amount per dose, in [unit]; null when it isn't measured.
  final double? amount;

  /// mg, mcg, g, IU, ml, capsule, tablet, scoop, drop... ('' for none).
  final String unit;
  final int order;

  /// False once removed from the daily list (past doses keep its name).
  final bool active;

  Supplement copyWith({String? name, Object? amount = _keep, String? unit, int? order, bool? active}) => Supplement(
        id: id,
        name: name ?? this.name,
        amount: identical(amount, _keep) ? this.amount : (amount as num?)?.toDouble(),
        unit: unit ?? this.unit,
        order: order ?? this.order,
        active: active ?? this.active,
      );

  /// "2000 IU", "2 capsules", or '' when there's no amount.
  String get dose => doseText(amount, unit);

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'amount': amount,
        'unit': unit,
        'sort': order,
        'active': active ? 1 : 0,
        'updated_at': _now(),
      };

  factory Supplement.fromRow(Map<String, Object?> r) => Supplement(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Supplement',
        amount: (r['amount'] as num?)?.toDouble(),
        unit: (r['unit'] as String?) ?? '',
        order: (r['sort'] as num?)?.toInt() ?? 0,
        active: r['active'] != 0,
      );
}

/// Units offered for supplements. Counted ones get a plural ("2 capsules").
const supplementUnits = ['mg', 'mcg', 'g', 'IU', 'ml', 'capsule', 'tablet', 'softgel', 'scoop', 'drop'];

/// "500 mg", "2 capsules", "1 scoop".
String doseText(double? amount, String unit) {
  if (amount == null) return unit;
  final n = amount == amount.roundToDouble() ? '${amount.round()}' : '$amount';
  if (unit.isEmpty) return n;
  const counted = {'capsule', 'tablet', 'softgel', 'scoop', 'drop'};
  return '$n ${counted.contains(unit) && amount != 1 ? '${unit}s' : unit}';
}

/// One supplement taken on a day. The name and amount are copied from the
/// supplement at the time, so changing it later doesn't rewrite history.
class SupplementDose {
  const SupplementDose({
    required this.id,
    required this.supplementId,
    required this.name,
    required this.date,
    required this.at,
    this.amount,
    this.unit = '',
  });

  final String id;
  final String supplementId;
  final String name;
  final DateTime date;
  final DateTime at;
  final double? amount;
  final String unit;

  String get dose => doseText(amount, unit);

  Map<String, Object?> toRow() => {
        'id': id,
        'supplement_id': supplementId,
        'name': name,
        'date': dayKey(date),
        'at': at.toIso8601String(),
        'amount': amount,
        'unit': unit,
      };

  factory SupplementDose.fromRow(Map<String, Object?> r) => SupplementDose(
        id: r['id'] as String,
        supplementId: (r['supplement_id'] as String?) ?? '',
        name: (r['name'] as String?) ?? 'Supplement',
        date: DateTime.parse(r['date'] as String),
        at: DateTime.tryParse('${r['at']}') ?? DateTime.parse(r['date'] as String),
        amount: (r['amount'] as num?)?.toDouble(),
        unit: (r['unit'] as String?) ?? '',
      );
}

const mlPerCup = 236.588;

/// "3 cups" / "750 ml" / "1.5 L".
String formatWater(double ml, {required bool imperial}) {
  if (imperial) {
    final cups = ml / mlPerCup;
    final t = (cups * 10).round() / 10;
    final text = t == t.roundToDouble() ? '${t.round()}' : '$t';
    return '$text ${t == 1 ? 'cup' : 'cups'}';
  }
  if (ml < 1000) return '${ml.round()} ml';
  final l = (ml / 100).round() / 10;
  return '${l == l.roundToDouble() ? l.round() : l} L';
}

/// One tap of "+": a cup (8 oz), or 250 ml.
double waterStepMl({required bool imperial}) => imperial ? mlPerCup : 250;

class SleepEntry {
  const SleepEntry({
    required this.date,
    this.bedMinute,
    this.wakeMinute,
    this.durationMin,
    this.quality,
    this.source = 'manual',
  });

  final DateTime date;
  final int? bedMinute;
  final int? wakeMinute;
  final int? durationMin;
  final int? quality;
  final String source;

  Map<String, Object?> toRow() => {
        'date': dayKey(date),
        'bed_time': bedMinute == null ? null : _hhmm(bedMinute!),
        'wake_time': wakeMinute == null ? null : _hhmm(wakeMinute!),
        'duration_min': durationMin,
        'quality': quality,
        'source': source,
        'updated_at': _now(),
      };

  factory SleepEntry.fromRow(Map<String, Object?> r) => SleepEntry(
        date: DateTime.parse(r['date'] as String),
        bedMinute: _parseHhmm(r['bed_time']),
        wakeMinute: _parseHhmm(r['wake_time']),
        durationMin: (r['duration_min'] as num?)?.toInt(),
        quality: (r['quality'] as num?)?.toInt(),
        source: (r['source'] as String?) ?? 'manual',
      );
}

// ---------------------------------------------------------------- photos

enum PhotoPose { front, side, back }

extension PhotoPoseInfo on PhotoPose {
  String get label => switch (this) {
        PhotoPose.front => 'Front',
        PhotoPose.side => 'Side',
        PhotoPose.back => 'Back',
      };

  String get tip => switch (this) {
        PhotoPose.front =>
          'Face the camera. Arms relaxed and slightly away from your sides, '
              'feet hip-width apart.',
        PhotoPose.side =>
          'Turn to your left. Arms at your sides, stand tall, breathe normally.',
        PhotoPose.back =>
          'Face away from the camera. Same stance as your front photo.',
      };
}

/// One progress photo. The image file lives in the app's photos folder.
class PhotoCheckin {
  const PhotoCheckin({
    required this.date,
    required this.pose,
    required this.fileName,
    this.weightKg,
  });

  final DateTime date;
  final PhotoPose pose;
  final String fileName;
  final double? weightKg;

  String get key => '${dayKey(date)}_${pose.name}';

  Map<String, Object?> toRow() => {
        'id': key,
        'date': dayKey(date),
        'pose': pose.name,
        'file_name': fileName,
        'weight_kg': weightKg,
        'updated_at': _now(),
      };

  factory PhotoCheckin.fromRow(Map<String, Object?> r) => PhotoCheckin(
        date: DateTime.parse(r['date'] as String),
        pose: _enumByName(PhotoPose.values, r['pose'], PhotoPose.front),
        fileName: r['file_name'] as String,
        weightKg: _toDouble(r['weight_kg']),
      );
}

// ---------------------------------------------------------------- measurements

enum MeasureSite {
  neck,
  shoulders,
  chest,
  waist,
  hips,
  bicepLeft,
  bicepRight,
  forearmLeft,
  forearmRight,
  thighLeft,
  thighRight,
  calfLeft,
  calfRight,
}

extension MeasureSiteInfo on MeasureSite {
  String get label => switch (this) {
        MeasureSite.neck => 'Neck',
        MeasureSite.shoulders => 'Shoulders',
        MeasureSite.chest => 'Chest',
        MeasureSite.waist => 'Waist',
        MeasureSite.hips => 'Hips',
        MeasureSite.bicepLeft => 'Left bicep',
        MeasureSite.bicepRight => 'Right bicep',
        MeasureSite.forearmLeft => 'Left forearm',
        MeasureSite.forearmRight => 'Right forearm',
        MeasureSite.thighLeft => 'Left thigh',
        MeasureSite.thighRight => 'Right thigh',
        MeasureSite.calfLeft => 'Left calf',
        MeasureSite.calfRight => 'Right calf',
      };

  /// Where and how to measure, so it's the same every time.
  String get hint => switch (this) {
        MeasureSite.neck => 'Around the middle of the neck, below the Adam\'s apple',
        MeasureSite.shoulders => 'Around the widest part, arms relaxed at your sides',
        MeasureSite.chest => 'Across the nipples, after a normal breath out',
        MeasureSite.waist => 'At the navel, relaxed, after a normal breath out',
        MeasureSite.hips => 'Around the widest part of the buttocks, feet together',
        MeasureSite.bicepLeft || MeasureSite.bicepRight =>
          'Widest point. Relaxed or flexed, just the same way every time',
        MeasureSite.forearmLeft || MeasureSite.forearmRight =>
          'Widest point, arm relaxed and straight',
        MeasureSite.thighLeft || MeasureSite.thighRight =>
          'Widest point, just below the glutes, standing',
        MeasureSite.calfLeft || MeasureSite.calfRight =>
          'Widest point, standing with weight on both feet',
      };
}

/// One measurement, in cm, filed under the day it was taken.
class Measurement {
  const Measurement({
    required this.date,
    required this.site,
    required this.valueCm,
  });

  final DateTime date;
  final MeasureSite site;
  final double valueCm;

  String get key => '${dayKey(date)}_${site.name}';

  Map<String, Object?> toRow() => {
        'id': key,
        'date': dayKey(date),
        'site': site.name,
        'value_cm': valueCm,
        'updated_at': _now(),
      };

  factory Measurement.fromRow(Map<String, Object?> r) => Measurement(
        date: DateTime.parse(r['date'] as String),
        site: _enumByName(MeasureSite.values, r['site'], MeasureSite.waist),
        valueCm: (r['value_cm'] as num).toDouble(),
      );
}

// ---------------------------------------------------------------- training

int _idCounter = 0;

/// Short unique id, e.g. "w_lx3k9a2b0".
String newId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_idCounter++}';

const muscleGroups = ['Chest', 'Back', 'Shoulders', 'Arms', 'Legs', 'Core', 'Cardio', 'Other'];

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    this.muscle = 'Other',
    this.bodyweight = false,
    this.custom = false,
    this.archived = false,
    this.cardio = false,
    this.note,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.heads = const {},
  });

  final String id;
  final String name;
  final String muscle;

  /// Load is body weight plus any added weight (pull-ups, dips...).
  final bool bodyweight;
  final bool custom;
  final bool archived;

  /// Logged as time and distance instead of weight and reps.
  final bool cardio;

  /// Shown in the logger whenever this exercise comes up ("seat height 4").
  final String? note;

  /// Muscles worked, by name (see Muscle): set for your own exercises;
  /// empty means the built-in table (or a guess from [muscle]).
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;

  /// Muscle heads worked, by name, 1-3 (a little / some / main), when you've
  /// changed them; empty means the built-in table (see muscles.dart).
  final Map<String, int> heads;

  Exercise copyWith({
    String? name,
    String? muscle,
    bool? bodyweight,
    bool? archived,
    bool? cardio,
    Object? note = _keep,
    List<String>? primaryMuscles,
    List<String>? secondaryMuscles,
    Map<String, int>? heads,
  }) =>
      Exercise(
        id: id,
        name: name ?? this.name,
        muscle: muscle ?? this.muscle,
        bodyweight: bodyweight ?? this.bodyweight,
        custom: custom,
        archived: archived ?? this.archived,
        cardio: cardio ?? this.cardio,
        note: identical(note, _keep) ? this.note : note as String?,
        primaryMuscles: primaryMuscles ?? this.primaryMuscles,
        secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
        heads: heads ?? this.heads,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'muscle': muscle,
        'bodyweight': bodyweight ? 1 : 0,
        'custom': custom ? 1 : 0,
        'archived': archived ? 1 : 0,
        'kind': cardio ? 'cardio' : 'strength',
        'note': note,
        'muscles_primary': primaryMuscles.join(','),
        'muscles_secondary': secondaryMuscles.join(','),
        'heads': heads.isEmpty ? null : jsonEncode(heads),
        'updated_at': _now(),
      };

  factory Exercise.fromRow(Map<String, Object?> r) => Exercise(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Exercise',
        muscle: (r['muscle'] as String?) ?? 'Other',
        bodyweight: r['bodyweight'] == 1,
        custom: r['custom'] == 1,
        archived: r['archived'] == 1,
        cardio: r['kind'] == 'cardio',
        note: (r['note'] as String?)?.trim().isEmpty ?? true ? null : r['note'] as String,
        primaryMuscles: _names(r['muscles_primary']),
        secondaryMuscles: _names(r['muscles_secondary']),
        heads: {
          for (final e in _stringMap(r['heads']).entries)
            if (int.tryParse(e.value) case final int v) e.key: v,
        },
      );

  static List<String> _names(Object? v) =>
      [for (final n in '${v ?? ''}'.split(',')) if (n.trim().isNotEmpty) n.trim()];
}

/// One exercise inside a workout plan.
class WorkoutItem {
  const WorkoutItem({
    required this.exerciseId,
    this.sets = 3,
    this.repsLow = 8,
    this.repsHigh = 10,
    this.loadKg,
    this.restSec = 90,
    this.linkNext = false,
    this.targetMin,
    this.note,
    this.setTypes = const [],
  });

  final String exerciseId;
  final int sets;
  final int repsLow;
  final int repsHigh;
  final double? loadKg;
  final int restSec;

  /// Linked with the next exercise as a superset.
  final bool linkNext;

  /// Cardio: planned minutes.
  final int? targetMin;

  /// Written for this exercise in this workout ("Full depth.").
  final String? note;

  /// Set type per set, by position ('' = normal): ['', 'partial'] makes set 2
  /// partial reps when the workout starts.
  final List<String> setTypes;

  String setTypeAt(int i) => i < setTypes.length ? setTypes[i] : '';

  WorkoutItem copyWith({
    int? sets,
    int? repsLow,
    int? repsHigh,
    Object? loadKg = _keep,
    int? restSec,
    bool? linkNext,
    Object? targetMin = _keep,
    Object? note = _keep,
    List<String>? setTypes,
  }) =>
      WorkoutItem(
        exerciseId: exerciseId,
        sets: sets ?? this.sets,
        repsLow: repsLow ?? this.repsLow,
        repsHigh: repsHigh ?? this.repsHigh,
        loadKg: identical(loadKg, _keep) ? this.loadKg : loadKg as double?,
        restSec: restSec ?? this.restSec,
        linkNext: linkNext ?? this.linkNext,
        targetMin: identical(targetMin, _keep) ? this.targetMin : targetMin as int?,
        note: identical(note, _keep) ? this.note : note as String?,
        setTypes: setTypes ?? this.setTypes,
      );

  Map<String, Object?> toJson() => {
        'exercise_id': exerciseId,
        'sets': sets,
        'reps_low': repsLow,
        'reps_high': repsHigh,
        'load_kg': loadKg,
        'rest_sec': restSec,
        if (linkNext) 'link_next': true,
        if (targetMin != null) 'target_min': targetMin,
        if (note != null) 'note': note,
        if (setTypes.any((t) => t.isNotEmpty)) 'set_types': setTypes,
      };

  factory WorkoutItem.fromJson(Map<String, Object?> j) => WorkoutItem(
        exerciseId: j['exercise_id'] as String,
        sets: (j['sets'] as num?)?.toInt() ?? 3,
        repsLow: (j['reps_low'] as num?)?.toInt() ?? 8,
        repsHigh: (j['reps_high'] as num?)?.toInt() ?? 10,
        loadKg: _toDouble(j['load_kg']),
        restSec: (j['rest_sec'] as num?)?.toInt() ?? 90,
        linkNext: j['link_next'] == true,
        targetMin: (j['target_min'] as num?)?.toInt(),
        note: j['note'] as String?,
        setTypes: [for (final t in (j['set_types'] as List?) ?? const []) '$t'],
      );
}

List<Map<String, Object?>> _jsonList(Object? v) {
  if (v is! String || v.isEmpty) return const [];
  try {
    final decoded = jsonDecode(v);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map) Map<String, Object?>.from(e),
    ];
  } catch (_) {
    return const [];
  }
}

class Workout {
  const Workout({
    required this.id,
    required this.name,
    this.items = const [],
    this.sort = 0,
    this.note,
  });

  final String id;
  final String name;
  final List<WorkoutItem> items;
  final int sort;

  /// The workout's own rules ("Add weight when you hit the top of the range").
  final String? note;

  Workout copyWith({String? name, List<WorkoutItem>? items, int? sort, Object? note = _keep}) => Workout(
        id: id,
        name: name ?? this.name,
        items: items ?? this.items,
        sort: sort ?? this.sort,
        note: identical(note, _keep) ? this.note : note as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'sort': sort,
        'note': note,
        'items': jsonEncode([for (final i in items) i.toJson()]),
        'updated_at': _now(),
      };

  factory Workout.fromRow(Map<String, Object?> r) => Workout(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Workout',
        sort: (r['sort'] as num?)?.toInt() ?? 0,
        note: (r['note'] as String?)?.trim().isEmpty ?? true ? null : r['note'] as String,
        items: [for (final j in _jsonList(r['items'])) WorkoutItem.fromJson(j)],
      );
}

/// One logged set. Every value is optional.
/// What kind of set it was; decides how it counts in records and volume.
enum SetType { normal, warmup, drop, failure, partial, restPause, amrap, myo }

extension SetTypeInfo on SetType {
  String get label => switch (this) {
        SetType.normal => 'Normal',
        SetType.warmup => 'Warm-up',
        SetType.drop => 'Drop set',
        SetType.failure => 'To failure',
        SetType.partial => 'Partial reps',
        SetType.restPause => 'Rest-pause',
        SetType.amrap => 'AMRAP',
        SetType.myo => 'Myo-reps',
      };

  /// The tag after the set number ("2D"); warm-ups show just "W".
  String get short => switch (this) {
        SetType.normal => '',
        SetType.warmup => 'W',
        SetType.drop => 'D',
        SetType.failure => 'F',
        SetType.partial => 'P',
        SetType.restPause => 'RP',
        SetType.amrap => 'A',
        SetType.myo => 'M',
      };

  String get hint => switch (this) {
        SetType.normal => 'A regular working set',
        SetType.warmup => 'Left out of records, volume and muscle sets',
        SetType.drop => 'Lighter weight right after another set; not used for records',
        SetType.failure => 'Taken until no more reps were possible',
        SetType.partial => 'Part of the range of motion; half credit, not used for records',
        SetType.restPause => 'Short breaks within one set',
        SetType.amrap => 'As many reps as possible',
        SetType.myo => 'Activation set then mini-sets; not used for records',
      };

  /// Used for estimated 1RM and personal records.
  bool get countsForRecords =>
      this == SetType.normal || this == SetType.failure || this == SetType.restPause || this == SetType.amrap;

  /// Share of a set counted toward volume and sets per muscle.
  double get volumeShare => switch (this) {
        SetType.warmup => 0,
        SetType.partial => 0.5,
        _ => 1,
      };
}

SetType setTypeByName(String? name) {
  for (final t in SetType.values) {
    if (t.name == name) return t;
  }
  return SetType.normal;
}

class SetEntry {
  const SetEntry({
    required this.exerciseId,
    this.weightKg,
    this.reps,
    this.restSec,
    bool warmup = false,
    SetType? type,
    this.done = false,
    this.restStartedAt,
    this.durationSec,
    this.distanceKm,
    this.heartRate,
    this.calories,
  }) : type = type ?? (warmup ? SetType.warmup : SetType.normal);

  final String exerciseId;

  /// For bodyweight exercises this is the added weight.
  final double? weightKg;
  final int? reps;

  /// Rest taken after this set, from "Rest started" to "End rest".
  final int? restSec;
  /// Normal, warm-up, drop set and so on.
  final SetType type;

  /// A warm-up set (kept for older code and backups).
  bool get warmup => type == SetType.warmup;
  final bool done;

  /// Set while the rest after this set is still running.
  final DateTime? restStartedAt;

  bool get resting => restStartedAt != null && restSec == null;

  // Cardio (all optional).
  final int? durationSec;
  final double? distanceKm;
  final int? heartRate;
  final int? calories;

  SetEntry copyWith({
    Object? weightKg = _keep,
    Object? reps = _keep,
    Object? restSec = _keep,
    bool? warmup,
    SetType? type,
    bool? done,
    Object? restStartedAt = _keep,
    Object? durationSec = _keep,
    Object? distanceKm = _keep,
    Object? heartRate = _keep,
    Object? calories = _keep,
  }) =>
      SetEntry(
        exerciseId: exerciseId,
        weightKg: identical(weightKg, _keep) ? this.weightKg : weightKg as double?,
        reps: identical(reps, _keep) ? this.reps : reps as int?,
        restSec: identical(restSec, _keep) ? this.restSec : restSec as int?,
        type: type ??
            (warmup == null
                ? this.type
                : (warmup ? SetType.warmup : (this.type == SetType.warmup ? SetType.normal : this.type))),
        done: done ?? this.done,
        restStartedAt: identical(restStartedAt, _keep)
            ? this.restStartedAt
            : restStartedAt as DateTime?,
        durationSec: identical(durationSec, _keep) ? this.durationSec : durationSec as int?,
        distanceKm: identical(distanceKm, _keep) ? this.distanceKm : distanceKm as double?,
        heartRate: identical(heartRate, _keep) ? this.heartRate : heartRate as int?,
        calories: identical(calories, _keep) ? this.calories : calories as int?,
      );

  Map<String, Object?> toJson() => {
        'exercise_id': exerciseId,
        'weight_kg': weightKg,
        'reps': reps,
        'rest_sec': restSec,
        'warmup': warmup,
        'type': type.name,
        'done': done,
        if (restStartedAt != null) 'rest_started_at': restStartedAt!.toIso8601String(),
        if (durationSec != null) 'duration_sec': durationSec,
        if (distanceKm != null) 'distance_km': distanceKm,
        if (heartRate != null) 'heart_rate': heartRate,
        if (calories != null) 'calories': calories,
      };

  factory SetEntry.fromJson(Map<String, Object?> j) => SetEntry(
        exerciseId: j['exercise_id'] as String,
        weightKg: _toDouble(j['weight_kg']),
        reps: (j['reps'] as num?)?.toInt(),
        restSec: (j['rest_sec'] as num?)?.toInt(),
        type: j['type'] is String ? setTypeByName(j['type'] as String) : (j['warmup'] == true ? SetType.warmup : SetType.normal),
        done: j['done'] == true,
        restStartedAt: j['rest_started_at'] is String
            ? DateTime.tryParse(j['rest_started_at'] as String)
            : null,
        durationSec: (j['duration_sec'] as num?)?.toInt(),
        distanceKm: _toDouble(j['distance_km']),
        heartRate: (j['heart_rate'] as num?)?.toInt(),
        calories: (j['calories'] as num?)?.toInt(),
      );
}

/// One workout as performed. Sets are in the order they were logged.
class Session {
  const Session({
    required this.id,
    required this.date,
    required this.name,
    required this.startedAt,
    this.workoutId,
    this.endedAt,
    this.sets = const [],
    this.note,
    this.mesoId,
    this.mesoWeek,
    this.exerciseNotes = const {},
  });

  final String id;
  final DateTime date;
  final String? note;

  /// Each exercise's note as it was in this workout (exercise id -> note).
  /// Changing a note later updates your exercise for next time, but not the
  /// workouts already done.
  final Map<String, String> exerciseNotes;

  /// The mesocycle and week this workout belonged to, if any.
  final String? mesoId;
  final int? mesoWeek;
  final String name;
  final String? workoutId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<SetEntry> sets;

  bool get finished => endedAt != null;

  Session copyWith({
    Object? endedAt = _keep,
    List<SetEntry>? sets,
    DateTime? date,
    Object? note = _keep,
    Map<String, String>? exerciseNotes,
  }) =>
      Session(
        id: id,
        mesoId: mesoId,
        mesoWeek: mesoWeek,
        exerciseNotes: exerciseNotes ?? this.exerciseNotes,
        note: identical(note, _keep) ? this.note : note as String?,
        date: date ?? this.date,
        name: name,
        workoutId: workoutId,
        startedAt: startedAt,
        endedAt: identical(endedAt, _keep) ? this.endedAt : endedAt as DateTime?,
        sets: sets ?? this.sets,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'date': dayKey(date),
        'name': name,
        'workout_id': workoutId,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'sets': jsonEncode([for (final x in sets) x.toJson()]),
        'note': note,
        'meso_id': mesoId,
        'meso_week': mesoWeek,
        'exercise_notes': exerciseNotes.isEmpty ? null : jsonEncode(exerciseNotes),
        'updated_at': _now(),
      };

  factory Session.fromRow(Map<String, Object?> r) => Session(
        id: r['id'] as String,
        date: DateTime.parse(r['date'] as String),
        name: (r['name'] as String?) ?? 'Workout',
        workoutId: r['workout_id'] as String?,
        startedAt: DateTime.tryParse((r['started_at'] as String?) ?? '') ??
            DateTime.parse(r['date'] as String),
        endedAt: r['ended_at'] is String ? DateTime.tryParse(r['ended_at'] as String) : null,
        sets: [for (final j in _jsonList(r['sets'])) SetEntry.fromJson(j)],
        note: r['note'] as String?,
        mesoId: r['meso_id'] as String?,
        mesoWeek: (r['meso_week'] as num?)?.toInt(),
        exerciseNotes: _stringMap(r['exercise_notes']),
      );
}

/// A JSON object of strings stored as text ('{"bench": "Pause 1s"}').
Map<String, String> _stringMap(Object? v) {
  if (v is! String || v.isEmpty) return const {};
  try {
    final m = jsonDecode(v);
    if (m is! Map) return const {};
    return {for (final e in m.entries) '${e.key}': '${e.value}'};
  } catch (_) {
    return const {};
  }
}

/// A workout scheduled on the calendar.
class PlannedWorkout {
  const PlannedWorkout({
    required this.id,
    required this.date,
    required this.workoutId,
    this.mesoId,
    this.mesoWeek,
  });

  final String id;
  final DateTime date;
  final String workoutId;

  /// Set when a mesocycle scheduled this workout.
  final String? mesoId;
  final int? mesoWeek;

  PlannedWorkout copyWith({DateTime? date}) => PlannedWorkout(
        id: id,
        date: date ?? this.date,
        workoutId: workoutId,
        mesoId: mesoId,
        mesoWeek: mesoWeek,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'date': dayKey(date),
        'workout_id': workoutId,
        'meso_id': mesoId,
        'meso_week': mesoWeek,
        'updated_at': _now(),
      };

  factory PlannedWorkout.fromRow(Map<String, Object?> r) => PlannedWorkout(
        id: r['id'] as String,
        date: DateTime.parse(r['date'] as String),
        workoutId: r['workout_id'] as String,
        mesoId: r['meso_id'] as String?,
        mesoWeek: (r['meso_week'] as num?)?.toInt(),
      );
}

// ---------------------------------------------------------------- food

enum Meal { breakfast, lunch, dinner, snack }

extension MealInfo on Meal {
  String get label => switch (this) {
        Meal.breakfast => 'Breakfast',
        Meal.lunch => 'Lunch',
        Meal.dinner => 'Dinner',
        Meal.snack => 'Snacks',
      };
}

Map<String, double> _priceMap(Object? v) {
  if (v is! String || v.isEmpty) return const {};
  try {
    final m = jsonDecode(v);
    if (m is! Map) return const {};
    return {
      for (final e in m.entries)
        if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
    };
  } catch (_) {
    return const {};
  }
}

/// A food with nutrition per 100 g. Foods bought by the item (eggs,
/// bananas) also know how much one weighs.
class Food {
  const Food({
    required this.id,
    required this.name,
    this.per100 = Macros.zero,
    this.byItem = false,
    this.gramsPerItem,
    this.prices = const {},
    this.custom = false,
    this.archived = false,
    this.barcode,
    this.brand,
    this.servingGrams,
    this.fiber,
    this.sugar,
    this.sodiumMg,
    this.sourceId,
    this.favorite = false,
  });

  final String id;
  final String name;
  final Macros per100;
  final bool byItem;
  final double? gramsPerItem;

  /// The package barcode (EAN/UPC digits), for scanning.
  final String? barcode;
  final String? brand;

  /// One serving, in grams, from the package label (separate from
  /// [gramsPerItem], which is for foods bought by the item).
  final double? servingGrams;

  /// Per 100 g, when known (grams, grams, milligrams).
  final double? fiber;
  final double? sugar;
  final double? sodiumMg;

  /// Where it came from, e.g. "usda:05064" (so it's only added once).
  final String? sourceId;

  /// Starred: shown first when picking a food.
  final bool favorite;

  /// Store id -> price per kg, or per item when [byItem].
  final Map<String, double> prices;
  final bool custom;
  final bool archived;

  Food copyWith({
    String? name,
    Macros? per100,
    bool? byItem,
    Object? gramsPerItem = _keep,
    Map<String, double>? prices,
    bool? archived,
    Object? barcode = _keep,
    Object? brand = _keep,
    Object? servingGrams = _keep,
    Object? fiber = _keep,
    Object? sugar = _keep,
    Object? sodiumMg = _keep,
    bool? favorite,
  }) =>
      Food(
        id: id,
        name: name ?? this.name,
        per100: per100 ?? this.per100,
        byItem: byItem ?? this.byItem,
        gramsPerItem: identical(gramsPerItem, _keep) ? this.gramsPerItem : gramsPerItem as double?,
        prices: prices ?? this.prices,
        custom: custom,
        archived: archived ?? this.archived,
        barcode: identical(barcode, _keep) ? this.barcode : barcode as String?,
        brand: identical(brand, _keep) ? this.brand : brand as String?,
        servingGrams: identical(servingGrams, _keep) ? this.servingGrams : servingGrams as double?,
        fiber: identical(fiber, _keep) ? this.fiber : fiber as double?,
        sugar: identical(sugar, _keep) ? this.sugar : sugar as double?,
        sodiumMg: identical(sodiumMg, _keep) ? this.sodiumMg : sodiumMg as double?,
        sourceId: sourceId,
        favorite: favorite ?? this.favorite,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'kcal': per100.kcal,
        'protein': per100.protein,
        'carbs': per100.carbs,
        'fat': per100.fat,
        'by_item': byItem ? 1 : 0,
        'grams_per_item': gramsPerItem,
        'prices': jsonEncode(prices),
        'custom': custom ? 1 : 0,
        'archived': archived ? 1 : 0,
        'barcode': barcode,
        'brand': brand,
        'serving_g': servingGrams,
        'fiber': fiber,
        'sugar': sugar,
        'sodium_mg': sodiumMg,
        'source_id': sourceId,
        'favorite': favorite ? 1 : 0,
        'updated_at': _now(),
      };

  factory Food.fromRow(Map<String, Object?> r) => Food(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Food',
        per100: Macros(
          kcal: _toDouble(r['kcal']) ?? 0,
          protein: _toDouble(r['protein']) ?? 0,
          carbs: _toDouble(r['carbs']) ?? 0,
          fat: _toDouble(r['fat']) ?? 0,
        ),
        byItem: r['by_item'] == 1,
        gramsPerItem: _toDouble(r['grams_per_item']),
        prices: _priceMap(r['prices']),
        custom: r['custom'] == 1,
        archived: r['archived'] == 1,
        barcode: r['barcode'] as String?,
        brand: r['brand'] as String?,
        servingGrams: _toDouble(r['serving_g']),
        fiber: _toDouble(r['fiber']),
        sugar: _toDouble(r['sugar']),
        sodiumMg: _toDouble(r['sodium_mg']),
        sourceId: r['source_id'] as String?,
        favorite: r['favorite'] == 1,
      );
}

class GroceryStore {
  const GroceryStore({required this.id, required this.name, this.sort = 0});

  final String id;
  final String name;
  final int sort;

  GroceryStore copyWith({String? name, int? sort}) =>
      GroceryStore(id: id, name: name ?? this.name, sort: sort ?? this.sort);

  Map<String, Object?> toRow() => {'id': id, 'name': name, 'sort': sort, 'updated_at': _now()};

  factory GroceryStore.fromRow(Map<String, Object?> r) => GroceryStore(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Store',
        sort: (r['sort'] as num?)?.toInt() ?? 0,
      );
}

class RecipeItem {
  const RecipeItem({required this.foodId, required this.grams});

  final String foodId;
  final double grams;

  Map<String, Object?> toJson() => {'food_id': foodId, 'grams': grams};

  factory RecipeItem.fromJson(Map<String, Object?> j) => RecipeItem(
        foodId: j['food_id'] as String,
        grams: _toDouble(j['grams']) ?? 0,
      );
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    this.servings = 1,
    this.items = const [],
    this.note,
  });

  final String id;
  final String name;
  final double servings;
  final List<RecipeItem> items;
  final String? note;

  Recipe copyWith({String? name, double? servings, List<RecipeItem>? items, Object? note = _keep}) =>
      Recipe(
        id: id,
        name: name ?? this.name,
        servings: servings ?? this.servings,
        items: items ?? this.items,
        note: identical(note, _keep) ? this.note : note as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'servings': servings,
        'items': jsonEncode([for (final i in items) i.toJson()]),
        'note': note,
        'updated_at': _now(),
      };

  factory Recipe.fromRow(Map<String, Object?> r) => Recipe(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? 'Recipe',
        servings: _toDouble(r['servings']) ?? 1,
        items: [for (final j in _jsonList(r['items'])) RecipeItem.fromJson(j)],
        note: r['note'] as String?,
      );
}

/// One thing eaten. Nutrition is stored with the entry so editing a food
/// later doesn't rewrite history.
class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.kind,
    required this.name,
    required this.macros,
    this.refId,
    this.amount,
  });

  final String id;
  final DateTime date;
  final Meal meal;

  /// 'food' (amount = grams), 'recipe' (amount = servings) or 'quick'.
  final String kind;
  final String? refId;
  final double? amount;
  final String name;
  final Macros macros;

  FoodEntry copyWith({DateTime? date, Meal? meal, double? amount, Macros? macros, String? name}) =>
      FoodEntry(
        id: id,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        kind: kind,
        refId: refId,
        amount: amount ?? this.amount,
        name: name ?? this.name,
        macros: macros ?? this.macros,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'date': dayKey(date),
        'meal': meal.name,
        'kind': kind,
        'ref_id': refId,
        'amount': amount,
        'name': name,
        'kcal': macros.kcal,
        'protein': macros.protein,
        'carbs': macros.carbs,
        'fat': macros.fat,
        'updated_at': _now(),
      };

  factory FoodEntry.fromRow(Map<String, Object?> r) => FoodEntry(
        id: r['id'] as String,
        date: DateTime.parse(r['date'] as String),
        meal: _enumByName(Meal.values, r['meal'], Meal.snack),
        kind: (r['kind'] as String?) ?? 'quick',
        refId: r['ref_id'] as String?,
        amount: _toDouble(r['amount']),
        name: (r['name'] as String?) ?? 'Food',
        macros: Macros(
          kcal: _toDouble(r['kcal']) ?? 0,
          protein: _toDouble(r['protein']) ?? 0,
          carbs: _toDouble(r['carbs']) ?? 0,
          fat: _toDouble(r['fat']) ?? 0,
        ),
      );
}

/// A food or recipe planned for a day and meal.
class PlannedMeal {
  const PlannedMeal({
    required this.id,
    required this.date,
    required this.meal,
    required this.kind,
    required this.refId,
    required this.amount,
    this.loggedId,
  });

  final String id;
  final DateTime date;
  final Meal meal;

  /// 'recipe' (amount = servings) or 'food' (amount = grams).
  final String kind;
  final String refId;
  final double amount;

  /// The food-log entry made from this, once logged.
  final String? loggedId;

  PlannedMeal copyWith({DateTime? date, Meal? meal, double? amount, Object? loggedId = _keep}) =>
      PlannedMeal(
        id: id,
        date: date ?? this.date,
        meal: meal ?? this.meal,
        kind: kind,
        refId: refId,
        amount: amount ?? this.amount,
        loggedId: identical(loggedId, _keep) ? this.loggedId : loggedId as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'date': dayKey(date),
        'meal': meal.name,
        'kind': kind,
        'ref_id': refId,
        'amount': amount,
        'logged_id': loggedId,
        'updated_at': _now(),
      };

  factory PlannedMeal.fromRow(Map<String, Object?> r) => PlannedMeal(
        id: r['id'] as String,
        date: DateTime.parse(r['date'] as String),
        meal: _enumByName(Meal.values, r['meal'], Meal.dinner),
        kind: (r['kind'] as String?) ?? 'recipe',
        refId: r['ref_id'] as String,
        amount: _toDouble(r['amount']) ?? 1,
        loggedId: r['logged_id'] as String?,
      );
}

/// Grocery list checkmarks for one food.
class GroceryMark {
  const GroceryMark({required this.foodId, this.inCart = false, this.atHome = false});

  final String foodId;
  final bool inCart;
  final bool atHome;

  GroceryMark copyWith({bool? inCart, bool? atHome}) =>
      GroceryMark(foodId: foodId, inCart: inCart ?? this.inCart, atHome: atHome ?? this.atHome);

  Map<String, Object?> toRow() => {
        'id': foodId,
        'in_cart': inCart ? 1 : 0,
        'at_home': atHome ? 1 : 0,
        'updated_at': _now(),
      };

  factory GroceryMark.fromRow(Map<String, Object?> r) => GroceryMark(
        foodId: r['id'] as String,
        inCart: r['in_cart'] == 1,
        atHome: r['at_home'] == 1,
      );
}

/// A stretch of cutting, maintaining or bulking. While a phase is active it
/// sets the goal mode and pace.
class Phase {
  const Phase({
    required this.id,
    required this.mode,
    required this.paceKgPerWeek,
    required this.start,
    this.end,
  });

  final String id;
  final GoalMode mode;
  final double paceKgPerWeek;
  final DateTime start;

  /// Last day of the phase; open-ended when null.
  final DateTime? end;

  bool coversDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final e = end;
    return !d.isBefore(start) && (e == null || !d.isAfter(e));
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'mode': mode.name,
        'pace': paceKgPerWeek,
        'start_day': dayKey(start),
        'end_day': end == null ? null : dayKey(end!),
        'updated_at': _now(),
      };

  factory Phase.fromRow(Map<String, Object?> r) => Phase(
        id: r['id'] as String,
        mode: _enumByName(GoalMode.values, r['mode'], GoalMode.maintain),
        paceKgPerWeek: _toDouble(r['pace']) ?? 0,
        start: DateTime.parse(r['start_day'] as String),
        end: r['end_day'] is String ? DateTime.tryParse(r['end_day'] as String) : null,
      );
}

// ---------------------------------------------------------------- mesocycles

/// How a mesocycle progresses from week to week.
enum MesoProgression { weight, sets, effort }

extension MesoProgressionInfo on MesoProgression {
  String get label => switch (this) {
        MesoProgression.weight => 'Weight',
        MesoProgression.sets => 'Sets',
        MesoProgression.effort => 'Effort',
      };
}

/// A training block: a weekly schedule of workouts run for some weeks,
/// progressing each week, optionally ending with a deload week.
class Mesocycle {
  const Mesocycle({
    required this.id,
    required this.name,
    required this.start,
    required this.weeks,
    required this.progression,
    required this.schedule,
    this.deload = true,
    this.weightStepKg = 2.26796,
    this.endedEarly,
  });

  final String id;
  final String name;

  /// First day of week 1.
  final DateTime start;

  /// Working weeks, not counting the deload.
  final int weeks;
  final bool deload;
  final MesoProgression progression;

  /// Added each week when progressing by weight.
  final double weightStepKg;

  /// Weekday (1 = Monday ... 7 = Sunday) -> workout id.
  final Map<int, String> schedule;

  /// Set when the block was ended before its last day.
  final DateTime? endedEarly;

  int get totalWeeks => weeks + (deload ? 1 : 0);

  DateTime get lastDay => DateTime(start.year, start.month, start.day + totalWeeks * 7 - 1);

  /// Last day it actually ran (an early end, or its planned last day).
  DateTime get endDay => endedEarly ?? lastDay;

  bool isDeloadWeek(int week) => deload && week == weeks + 1;

  /// Week number (1-based) that [day] falls in, or null outside the block.
  int? weekOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(start) || d.isAfter(endDay)) return null;
    return daysBetween(start, d) ~/ 7 + 1;
  }

  Mesocycle copyWith({Object? endedEarly = _keep}) => Mesocycle(
        id: id,
        name: name,
        start: start,
        weeks: weeks,
        deload: deload,
        progression: progression,
        weightStepKg: weightStepKg,
        schedule: schedule,
        endedEarly: identical(endedEarly, _keep) ? this.endedEarly : endedEarly as DateTime?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'start_day': dayKey(start),
        'weeks': weeks,
        'deload': deload ? 1 : 0,
        'progression': progression.name,
        'weight_step_kg': weightStepKg,
        'schedule': jsonEncode({for (final e in schedule.entries) '${e.key}': e.value}),
        'ended_early': endedEarly == null ? null : dayKey(endedEarly!),
        'updated_at': _now(),
      };

  factory Mesocycle.fromRow(Map<String, Object?> r) {
    final schedule = <int, String>{};
    final raw = r['schedule'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) {
          for (final e in m.entries) {
            final day = int.tryParse(e.key.toString());
            if (day != null && e.value is String) schedule[day] = e.value as String;
          }
        }
      } catch (_) {}
    }
    return Mesocycle(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? 'Block',
      start: DateTime.parse(r['start_day'] as String),
      weeks: (r['weeks'] as num?)?.toInt() ?? 4,
      deload: r['deload'] != 0,
      progression: _enumByName(MesoProgression.values, r['progression'], MesoProgression.weight),
      weightStepKg: _toDouble(r['weight_step_kg']) ?? 2.26796,
      schedule: schedule,
      endedEarly: r['ended_early'] is String ? DateTime.tryParse(r['ended_early'] as String) : null,
    );
  }
}

/// An item on your own grocery list: free text, or one of your foods.
class GroceryItem {
  const GroceryItem({
    required this.id,
    required this.label,
    this.foodId,
    this.amount,
    this.done = false,
  });

  final String id;

  /// What it says on the list (the food's name for food items).
  final String label;

  /// Set for "from your foods" items.
  final String? foodId;

  /// Grams, or a count for foods sold by the item.
  final double? amount;
  final bool done;

  bool get isFood => foodId != null;

  GroceryItem copyWith({double? amount, bool? done}) => GroceryItem(
        id: id,
        label: label,
        foodId: foodId,
        amount: amount ?? this.amount,
        done: done ?? this.done,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'label': label,
        'food_id': foodId,
        'amount': amount,
        'done': done ? 1 : 0,
        'updated_at': _now(),
      };

  factory GroceryItem.fromRow(Map<String, Object?> r) => GroceryItem(
        id: r['id'] as String,
        label: (r['label'] as String?) ?? '',
        foodId: r['food_id'] as String?,
        amount: _toDouble(r['amount']),
        done: r['done'] == 1,
      );
}
