import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../data/models.dart';
import '../data/sqlite_store.dart';
import '../state/app_state.dart';
import 'reminders.dart';
import 'widget_sync.dart';

/// Where the background callback records that it changed something, so the
/// app (if it's open in the background) knows to reload when you return.
const widgetChangedKey = 'changed_at';

/// Runs when a widget button that saves in the background is tapped:
///   fitapp://meal?slot=0..3   tick or untick a meal on today's plan
///   fitapp://quality?q=1..5   set last night's sleep quality
///   fitapp://refresh          recompute (a new day has started)
/// It loads the data, makes the change, waits for it to be written, then
/// redraws both widgets.
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  final s = AppState(SqliteStore(), NoopReminders());
  await s.load();
  final today = dateOnly(DateTime.now());
  var changed = false;
  switch (uri.host) {
    case 'meal':
      final slot = int.tryParse(uri.queryParameters['slot'] ?? '');
      if (slot != null && slot >= 0 && slot < Meal.values.length) {
        s.toggleMealSlot(today, Meal.values[slot]);
        changed = true;
      }
    case 'quality':
      final q = int.tryParse(uri.queryParameters['q'] ?? '');
      if (q != null && q >= 1 && q <= 5) {
        s.setSleepQuality(today, q);
        changed = true;
      }
    case 'refresh':
      break;
    default:
      return;
  }
  await s.settle();
  if (changed) {
    await HomeWidget.saveWidgetData<String>(widgetChangedKey, '${DateTime.now().millisecondsSinceEpoch}');
  }
  await pushWidgetData(s.widgetData);
}
