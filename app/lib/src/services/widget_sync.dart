import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_actions.dart';

/// The two Android home screen widgets (Check-in and Today): keeps them up
/// to date and reports taps on them.
abstract class HomeWidgetSync {
  /// Sends what the widgets show (see AppState.widgetData) and redraws them.
  Future<void> push(Map<String, Object> data);

  /// Lets widget buttons (meal ticks, sleep quality) run in the background.
  Future<void> registerCallbacks();

  /// When a widget last changed something itself (milliseconds), or 0.
  Future<int> changedAt();

  /// The link the app was opened with from a widget, if any.
  Future<Uri?> launchUri();

  /// Taps on a widget that open the app while it's running.
  Stream<Uri?> get clicks;
}

/// The Android class names of the two widgets.
const widgetProviders = ['FitAppWidget', 'FitAppTodayWidget'];

/// The Kotlin package the widget classes are in (from build.bat's
/// `flutter create --org com.fitapp --project-name fitapp`).
const widgetPackage = 'com.fitapp.fitapp';

/// Saves [data] for the widgets and redraws both. Shared by the app and the
/// background callback.
Future<void> pushWidgetData(Map<String, Object> data) async {
  for (final e in data.entries) {
    final v = e.value;
    if (v is bool) {
      await HomeWidget.saveWidgetData<bool>(e.key, v);
    } else {
      await HomeWidget.saveWidgetData<String>(e.key, v.toString());
    }
  }
  for (final name in widgetProviders) {
    // The app ID (com.pumpandplate.app) is no longer the Kotlin package the
    // widget classes live in, so name them in full. Older projects created
    // under another package fall back to the short name.
    try {
      await HomeWidget.updateWidget(
          qualifiedAndroidName: '$widgetPackage.$name');
    } catch (_) {
      await HomeWidget.updateWidget(androidName: name);
    }
  }
}

class AndroidWidgetSync implements HomeWidgetSync {
  @override
  Future<void> push(Map<String, Object> data) async {
    try {
      await pushWidgetData(data);
    } catch (e) {
      debugPrint('Home widget update failed: $e');
    }
  }

  @override
  Future<void> registerCallbacks() async {
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    } catch (e) {
      debugPrint('Home widget callback setup failed: $e');
    }
  }

  @override
  Future<int> changedAt() async {
    try {
      final v = await HomeWidget.getWidgetData<String>(widgetChangedKey);
      return int.tryParse(v ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<Uri?> launchUri() async {
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Uri?> get clicks => HomeWidget.widgetClicked;
}

class NoHomeWidget implements HomeWidgetSync {
  @override
  Future<void> push(Map<String, Object> data) async {}

  @override
  Future<void> registerCallbacks() async {}

  @override
  Future<int> changedAt() async => 0;

  @override
  Future<Uri?> launchUri() async => null;

  @override
  Stream<Uri?> get clicks => const Stream<Uri?>.empty();
}
