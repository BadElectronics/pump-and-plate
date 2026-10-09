import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// The daily weigh-in reminder.
abstract class Reminders {
  /// [onOpen] runs when the user taps a notification, with its payload:
  /// 'rest' for the rest timer, null for the morning reminder.
  Future<void> init({required void Function(String? payload) onOpen});

  /// If the app was opened by tapping a notification: its payload, or
  /// 'reminder' for the morning reminder. Null otherwise.
  Future<String?> launchPayload();

  /// Asks for permission to show notifications (Android 13+, iPhones). True if allowed.
  Future<bool> requestPermission();

  /// Whether notifications are currently allowed for the app.
  Future<bool> notificationsAllowed();

  /// Whether pop-ups can be scheduled to the second.
  Future<bool> exactAlarmsAllowed();

  /// Schedules the daily reminder at [minuteOfDay], or cancels it when null.
  /// With [skipToday], the first reminder is tomorrow (already weighed in).
  Future<void> schedule(int? minuteOfDay, {bool skipToday = false});

  /// Shows the running rest as an ongoing notification with a live clock,
  /// and optionally a pop-up alert at [startedAt] + [targetSec] (plus
  /// [alertDelaySec]: with your own rest sound the app plays it on time and
  /// the pop-up is only the backup for when you've left the app).
  Future<void> showRest({
    required DateTime startedAt,
    required int targetSec,
    required String label,
    required bool alert,
    int alertDelaySec = 0,
  });

  Future<void> cancelRest();

  /// Cancels only the pop-up (the app already played the rest sound).
  Future<void> cancelRestAlert();

  /// Asks for the "alarms and reminders" permission needed for the
  /// pop-up to arrive on time. True if granted.
  Future<bool> requestExactAlarms();
}

/// Used by tests: does nothing.
class NoopReminders implements Reminders {
  @override
  Future<void> init({required void Function(String? payload) onOpen}) async {}

  @override
  Future<void> showRest({
    required DateTime startedAt,
    required int targetSec,
    required String label,
    required bool alert,
    int alertDelaySec = 0,
  }) async {}

  @override
  Future<void> cancelRest() async {}

  @override
  Future<void> cancelRestAlert() async {}

  @override
  Future<bool> requestExactAlarms() async => true;

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notificationsAllowed() async => true;

  @override
  Future<bool> exactAlarmsAllowed() async => true;

  @override
  Future<void> schedule(int? minuteOfDay, {bool skipToday = false}) async {}
}

class LocalReminders implements Reminders {
  static const _id = 1;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

  /// On iPhones, show these even while the app is open (like Android does).
  static const _iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBanner: true,
    presentList: true,
    presentSound: true,
  );

  @override
  Future<void> init({required void Function(String? payload) onOpen}) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Asked for later, when a reminder or rest alert is turned on.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => onOpen(r.payload),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Reminder setup failed: $e');
    }
  }

  static const _restId = 2;
  static const _restAlertId = 3;

  @override
  Future<void> showRest({
    required DateTime startedAt,
    required int targetSec,
    required String label,
    required bool alert,
    int alertDelaySec = 0,
  }) async {
    if (!_ready) return;
    final ios = _ios;
    if (ios != null) {
      // iPhones have no ongoing clock notification: only the pop-up when
      // the rest is up.
      try {
        await ios.cancel(id: _restAlertId);
        final at = startedAt.add(Duration(seconds: targetSec + alertDelaySec));
        if (alert && at.isAfter(DateTime.now())) {
          await ios.zonedSchedule(
            id: _restAlertId,
            title: 'Rest target reached',
            body: '$label. Ready for your next set.',
            scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
            notificationDetails: _iosDetails,
            payload: 'rest',
          );
        }
      } catch (e) {
        debugPrint('Rest notification failed: $e');
      }
      return;
    }
    try {
      await _plugin.cancel(id: _restAlertId);
      await _plugin.show(
        id: _restId,
        title: 'Resting: $label',
        body: 'Target ${targetSec ~/ 60}:${(targetSec % 60).toString().padLeft(2, '0')}. '
            'Tap to go back to your workout.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'rest_timer',
            'Rest timer',
            channelDescription: 'The running rest clock during a workout',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: true,
            usesChronometer: true,
            when: startedAt.millisecondsSinceEpoch,
          ),
        ),
        payload: 'rest',
      );
      final at = startedAt.add(Duration(seconds: targetSec + alertDelaySec));
      if (alert && at.isAfter(DateTime.now())) {
        final exact = await _android?.canScheduleExactNotifications() ?? false;
        await _android?.zonedSchedule(
          id: _restAlertId,
          title: 'Rest target reached',
          body: '$label. Ready for your next set.',
          scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
          notificationDetails: const AndroidNotificationDetails(
            'rest_alert',
            'Rest target alert',
            channelDescription: 'Pops up when your rest target is reached',
            importance: Importance.high,
            priority: Priority.high,
          ),
          scheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'rest',
        );
      }
    } catch (e) {
      debugPrint('Rest notification failed: $e');
    }
  }

  @override
  Future<void> cancelRest() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _restId);
      await _plugin.cancel(id: _restAlertId);
    } catch (_) {}
  }

  @override
  Future<void> cancelRestAlert() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _restAlertId);
    } catch (_) {}
  }

  @override
  Future<bool> notificationsAllowed() async {
    try {
      final ios = _ios;
      if (ios != null) return (await ios.checkPermissions())?.isEnabled ?? false;
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> exactAlarmsAllowed() async {
    // iPhones always deliver scheduled notifications on time.
    if (_ios != null) return true;
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarms() async {
    if (_ios != null) return true;
    try {
      final android = _android;
      if (android == null) return false;
      if (await android.canScheduleExactNotifications() ?? false) return true;
      return await android.requestExactAlarmsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> launchPayload() async {
    if (!_ready) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload ?? 'reminder';
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final ios = _ios;
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule(int? minuteOfDay, {bool skipToday = false}) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
      if (minuteOfDay == null) return;
      final now = DateTime.now();
      var next = DateTime(
        now.year,
        now.month,
        now.day,
        minuteOfDay ~/ 60,
        minuteOfDay % 60,
      );
      if (skipToday || !next.isAfter(now)) {
        next = DateTime(next.year, next.month, next.day + 1, next.hour, next.minute);
      }
      // Scheduled as an exact instant and repeated daily at that time.
      // The app reschedules on every launch, which keeps it right across
      // daylight-saving changes.
      await _ios?.zonedSchedule(
        id: _id,
        title: 'Good morning',
        body: 'Time for your weigh-in. Bathroom first, then the scale.',
        scheduledDate: tz.TZDateTime.from(next.toUtc(), tz.UTC),
        notificationDetails: _iosDetails,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      await _android?.zonedSchedule(
        id: _id,
        title: 'Good morning',
        body: 'Time for your weigh-in. Bathroom first, then the scale.',
        scheduledDate: tz.TZDateTime.from(next.toUtc(), tz.UTC),
        notificationDetails: const AndroidNotificationDetails(
          'morning_weigh_in',
          'Morning weigh-in',
          channelDescription: 'Daily reminder to log your weight',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        scheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Scheduling the reminder failed: $e');
    }
  }
}
