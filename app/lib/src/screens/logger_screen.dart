import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../services/phone.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/set_type_picker.dart';
import 'exercise_library_screen.dart';
import 'workout_editor_screen.dart' show SupersetLink;

/// Logs one workout session. Every field is optional; ticking a set with
/// blank fields fills them from last time (or the plan).
class LoggerScreen extends StatefulWidget {
  const LoggerScreen({super.key, required this.sessionId});

  final String sessionId;

  /// True while a logger is on screen (the rest notification checks this).
  static bool isOpen = false;

  static Route<void> route(String sessionId) => MaterialPageRoute<void>(
        builder: (_) => LoggerScreen(sessionId: sessionId),
        fullscreenDialog: true,
      );

  @override
  State<LoggerScreen> createState() => _LoggerScreenState();
}

class _LoggerScreenState extends State<LoggerScreen> {
  final List<TextEditingController> _weight = [];
  final List<TextEditingController> _reps = [];

  // Cardio sets reuse _weight for time and _reps for distance, plus these.
  final List<TextEditingController> _hr = [];
  final List<TextEditingController> _kcal = [];

  /// Replaced controllers, disposed when the screen closes (disposing them
  /// right away would break fields still showing them this frame).
  final List<TextEditingController> _retired = [];
  Timer? _tick;

  /// The rest we already buzzed for reaching its target (set index + start).
  String? _buzzed;

  /// Permissions for the rest notification are checked once per visit.
  bool _permissionsChecked = false;
  String? _record;
  String? _recordExercise;
  bool _imperial = true;

  /// Locked against pocket touches: everything ignores taps until swiped open.
  bool _locked = false;

  /// Rest targets changed during this workout for exercises not in its plan.
  final Map<String, int> _restOverride = {};

  @override
  void initState() {
    super.initState();
    LoggerScreen.isOpen = true;
    // The screen stays on while a workout is open.
    Phone.keepScreenOn(true);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    LoggerScreen.isOpen = false;
    Phone.keepScreenOn(false);
    _tick?.cancel();
    for (final c in [..._weight, ..._reps, ..._hr, ..._kcal, ..._retired]) {
      c.dispose();
    }
    super.dispose();
  }

  Session? _session(AppState s) {
    for (final x in s.sessions) {
      if (x.id == widget.sessionId) return x;
    }
    return null;
  }

  // ------------------------------------------------------------ units

  String _fmtWeight(double kg) => oneDecimal(_imperial ? kgToLb(kg) : kg);

  double? _parseWeight(String text) {
    final v = parseNumber(text);
    if (v == null || v < 0) return null;
    return _imperial ? lbToKg(v) : v;
  }

  String get _unit => _imperial ? 'lb' : 'kg';

  /// Rebuilds the text fields when sets are added or removed.
  void _resetControllers() {
    _retired.addAll([..._weight, ..._reps, ..._hr, ..._kcal]);
    _weight.clear();
    _reps.clear();
    _hr.clear();
    _kcal.clear();
  }

  String _fmtDistance(double km) => (_imperial ? kmToMi(km) : km).toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');

  void _syncControllers(AppState s, Session x) {
    if (_weight.length == x.sets.length) return;
    _resetControllers();
    for (final set in x.sets) {
      if (s.isCardio(set.exerciseId)) {
        _weight.add(TextEditingController(
          text: set.durationSec == null ? '' : clockText(set.durationSec!),
        ));
        _reps.add(TextEditingController(
          text: set.distanceKm == null ? '' : _fmtDistance(set.distanceKm!),
        ));
      } else {
        _weight.add(TextEditingController(
          text: set.weightKg == null ? '' : _fmtWeight(set.weightKg!),
        ));
        _reps.add(TextEditingController(text: set.reps == null ? '' : '${set.reps}'));
      }
      _hr.add(TextEditingController(text: set.heartRate == null ? '' : '${set.heartRate}'));
      _kcal.add(TextEditingController(text: set.calories == null ? '' : '${set.calories}'));
    }
  }

  // ------------------------------------------------------------ edits

  void _replaceSet(AppState s, Session x, int i, SetEntry set) {
    final sets = [...x.sets];
    sets[i] = set;
    s.updateSession(x.copyWith(sets: sets));
  }

  WorkoutItem? _planItem(AppState s, Session x, String exerciseId) {
    for (final w in s.workouts) {
      if (w.id != x.workoutId) continue;
      for (final item in w.items) {
        if (item.exerciseId == exerciseId) return item;
      }
    }
    return null;
  }

  /// The rest target for [exerciseId]: changed during this workout, else the
  /// plan's, else 1:30.
  int _targetRest(AppState s, Session x, String exerciseId) =>
      _restOverride[exerciseId] ?? _planItem(s, x, exerciseId)?.restSec ?? 90;

  /// What to suggest for set [i] (shown in the empty boxes, and filled in
  /// when it's ticked blank). Weight sticks from set to set: the weight
  /// already used for this exercise earlier today, else the same set last
  /// time, else the plan's target. Warm-ups get a lighter suggestion.
  (double?, int?, SetEntry?) _hint(AppState s, Session x, int i) {
    final set = x.sets[i];
    if (set.warmup) return _warmupHint(s, x, i);
    var k = 0;
    for (var j = 0; j < i; j++) {
      if (x.sets[j].exerciseId == set.exerciseId && !x.sets[j].warmup) k++;
    }
    final prev = s.lastSetsFor(set.exerciseId, exceptSession: x.id);
    final p = prev.isEmpty ? null : (k < prev.length ? prev[k] : prev.last);
    final plan = _planItem(s, x, set.exerciseId);
    double? today;
    for (var j = i - 1; j >= 0; j--) {
      final o = x.sets[j];
      // Only a normal set's weight carries on (not a drop set's or a partial's).
      if (o.exerciseId == set.exerciseId && o.type == SetType.normal && o.weightKg != null) {
        today = o.weightKg;
        break;
      }
    }
    double? weight;
    if (today != null && set.type == SetType.normal) {
      weight = today;
    } else {
      weight = p?.weightKg ?? today ?? plan?.loadKg;
      // In a mesocycle, weights follow the block's progression.
      final meso = s.mesoById(x.mesoId);
      final week = x.mesoWeek;
      if (meso != null && week != null) {
        weight = s.mesoWeightHint(meso, week, set.exerciseId, k, weight);
      }
    }
    return (weight, p?.reps ?? plan?.repsLow, k < prev.length ? prev[k] : null);
  }

  /// A warm-up's suggestion: a step of the ramp up to the first working set's
  /// weight (40%, 60%, 80%), by its place among this exercise's warm-ups.
  (double?, int?, SetEntry?) _warmupHint(AppState s, Session x, int i) {
    final id = x.sets[i].exerciseId;
    var nth = 0;
    int? firstWorking;
    for (var j = 0; j < x.sets.length; j++) {
      final o = x.sets[j];
      if (o.exerciseId != id) continue;
      if (o.warmup && j < i) nth++;
      if (!o.warmup && firstWorking == null) firstWorking = j;
    }
    if (firstWorking == null) return (null, null, null);
    final working = x.sets[firstWorking].weightKg ?? _hint(s, x, firstWorking).$1;
    if (working == null) return (null, null, null);
    final ramp = warmupSets(working, imperial: _imperial);
    if (ramp.isEmpty) return (null, null, null);
    // One warm-up: the middle step. More: from the lightest up.
    final step = ramp.length == 1 ? 0 : (_warmupCount(x, id) == 1 ? 1 : nth).clamp(0, ramp.length - 1);
    final (kg, reps) = ramp[step];
    return (kg, reps, null);
  }

  int _warmupCount(Session x, String exerciseId) =>
      x.sets.where((o) => o.exerciseId == exerciseId && o.warmup).length;

  /// The set whose rest is running, if any.
  int? _restingIndex(Session x) {
    for (var j = 0; j < x.sets.length; j++) {
      if (x.sets[j].resting) return j;
    }
    return null;
  }

  /// Records the running rest as the time from "Rest started" until now.
  List<SetEntry> _endRest(List<SetEntry> sets, DateTime now) {
    return [
      for (final set in sets)
        if (set.resting)
          set.copyWith(
            restSec: now.difference(set.restStartedAt!).inSeconds,
            restStartedAt: null,
          )
        else
          set,
    ];
  }

  void _endRestTapped(AppState s, Session x) {
    HapticFeedback.selectionClick();
    final nx = x.copyWith(sets: _endRest(x.sets, DateTime.now()));
    s.updateSession(nx);
    _syncRestNotification(s, nx);
  }

  /// Shows the running rest outside the app, or clears it. When a rest has
  /// just [started], makes sure notifications are allowed (asked once).
  Future<void> _syncRestNotification(AppState s, Session x, {bool started = false}) async {
    final i = x.finished ? null : _restingIndex(x);
    if (i == null || !s.settings.restNotification) {
      await s.reminders.cancelRest();
      return;
    }
    if (started && !_permissionsChecked) {
      _permissionsChecked = true;
      if (!await s.reminders.notificationsAllowed()) {
        await s.reminders.requestPermission();
      }
      if (s.settings.restAlert &&
          !s.settings.restAlertAsked &&
          !await s.reminders.exactAlarmsAllowed()) {
        s.setSettings(s.settings.copyWith(restAlertAsked: true));
        if (mounted) await _explainExactAlarms(s);
      }
    }
    // The rest may have ended while we were asking.
    final fresh = _session(s);
    final j = fresh == null ? null : _restingIndex(fresh);
    if (fresh == null || j == null) return;
    final set = fresh.sets[j];
    await s.reminders.showRest(
      startedAt: set.restStartedAt!,
      targetSec: _targetRest(s, fresh, set.exerciseId),
      label: s.exerciseName(set.exerciseId),
      alert: s.settings.restAlert,
      // With your own sound the app plays it on time; the pop-up waits a
      // moment so it only shows if you've left the app.
      alertDelaySec: s.settings.restSoundPath == null ? 0 : 3,
    );
  }

  Future<void> _explainExactAlarms(AppState s) async {
    final c = AppColors.of(context);
    final allow = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Pop-up when rest is up'),
        content: const Text(
          'To pop up right when your rest target is reached, Android needs the '
          '"Alarms and reminders" permission. Without it the pop-up can arrive '
          'a little late. You can change this any time in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow == true) await s.reminders.requestExactAlarms();
  }

  /// Whether ticking a set of [exerciseId] starts a rest: not for cardio,
  /// and in a superset only after the last exercise of the group.
  bool _startsRest(AppState s, Session x, String exerciseId) {
    if (s.isCardio(exerciseId)) return false;
    return !(_planItem(s, x, exerciseId)?.linkNext ?? false);
  }

  /// True when [a] is linked to [b] as a superset in this workout's plan.
  bool _linked(AppState s, Session x, String a, String b) {
    final w = s.workoutById(x.workoutId);
    if (w == null) return false;
    for (var k = 0; k < w.items.length - 1; k++) {
      if (w.items[k].exerciseId == a && w.items[k].linkNext) {
        return w.items[k + 1].exerciseId == b;
      }
    }
    return false;
  }

  bool _inSuperset(AppState s, Session x, String id, List<String> order) {
    final k = order.indexOf(id);
    return (k > 0 && _linked(s, x, order[k - 1], id)) ||
        (k >= 0 && k < order.length - 1 && _linked(s, x, id, order[k + 1]));
  }

  void _toggleDone(AppState s, Session x, int i) {
    final set = x.sets[i];
    if (set.done) {
      // Unticking also cancels its rest.
      final sets = [...x.sets];
      sets[i] = set.copyWith(done: false, restStartedAt: null, restSec: null);
      final nx = x.copyWith(sets: sets);
      s.updateSession(nx);
      _syncRestNotification(s, nx);
      return;
    }
    final cardio = s.isCardio(set.exerciseId);
    final (hw, hr, _) = cardio ? (null, null, null) : _hint(s, x, i);
    final w = cardio ? set.weightKg : (set.weightKg ?? hw);
    final r = cardio ? set.reps : (set.reps ?? hr);
    final now = DateTime.now();
    final updated = set.copyWith(
      weightKg: w,
      reps: r,
      done: true,
      // Editing a finished workout doesn't start a rest.
      restStartedAt: x.finished
          ? set.restStartedAt
          : (_startsRest(s, x, set.exerciseId) ? now : null),
      restSec: x.finished ? set.restSec : null,
    );
    if (!s.isCardio(set.exerciseId)) {
      _weight[i].text = w == null ? '' : _fmtWeight(w);
      _reps[i].text = r == null ? '' : '$r';
    }

    // New estimated 1RM record?
    if (!updated.warmup) {
      final v = s.setE1rm(updated, x.date);
      final before = s.bestE1rm(set.exerciseId, exceptSession: x.id);
      if (v != null && before != null) {
        var best = before;
        for (var j = 0; j < x.sets.length; j++) {
          if (j == i || x.sets[j].exerciseId != set.exerciseId) continue;
          final o = s.setE1rm(x.sets[j], x.date);
          if (o != null) best = math.max(best, o);
        }
        if (v > best + 0.05) {
          _record = 'New e1RM record: ${_fmtWeight(v)} $_unit, up from ${_fmtWeight(before)}';
          _recordExercise = set.exerciseId;
        }
      }
    }

    // A rest still running from an earlier set ends now (the user forgot
    // to tap End rest), then this set's rest starts.
    var sets = x.finished ? [...x.sets] : _endRest(x.sets, now);
    sets = [...sets];
    sets[i] = updated;
    final nx = x.copyWith(sets: sets);
    s.updateSession(nx);
    _syncRestNotification(s, nx, started: !x.finished);
    HapticFeedback.mediumImpact();
    FocusScope.of(context).unfocus();
  }

  /// Adds one warm-up set before this exercise's working sets (after any
  /// warm-ups already there). Its boxes suggest a lighter weight; type your own.
  void _addWarmup(AppState s, Session x, String exerciseId) {
    final sets = [...x.sets];
    var at = -1;
    for (var j = 0; j < sets.length; j++) {
      if (sets[j].exerciseId != exerciseId) continue;
      if (sets[j].warmup) {
        at = j + 1;
      } else {
        if (at < 0) at = j;
        break;
      }
    }
    sets.insert(at < 0 ? sets.length : at, SetEntry(exerciseId: exerciseId, type: SetType.warmup));
    _resetControllers();
    s.updateSession(x.copyWith(sets: sets));
    HapticFeedback.selectionClick();
  }

  void _addSet(AppState s, Session x, String exerciseId) {
    final sets = [...x.sets];
    var at = sets.length;
    for (var j = sets.length - 1; j >= 0; j--) {
      if (sets[j].exerciseId == exerciseId) {
        at = j + 1;
        break;
      }
    }
    sets.insert(at, SetEntry(exerciseId: exerciseId));
    _resetControllers();
    s.updateSession(x.copyWith(sets: sets));
  }

  Future<void> _addExercise(AppState s, Session x) async {
    final id = await ExerciseLibraryScreen.pick(context);
    if (id == null || !mounted) return;
    final fresh = _session(s) ?? x;
    _resetControllers();
    s.updateSession(fresh.copyWith(sets: [
      ...fresh.sets,
      for (var k = 0; k < 3; k++) SetEntry(exerciseId: id),
    ]));
  }

  Future<void> _setMenu(AppState s, Session x, int i) async {
    final c = AppColors.of(context);
    final set = x.sets[i];
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Set type: ${set.type.label}'),
              subtitle: const Text('Warm-up, drop set, to failure, partial and more'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(sheet).pop('type'),
            ),
            ListTile(
              title: Text('Remove this set', style: TextStyle(color: c.protein)),
              onTap: () => Navigator.of(sheet).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final fresh = _session(s) ?? x;
    if (choice == 'type') {
      final picked = await pickSetType(context, fresh.sets[i].type);
      if (picked == null || !mounted) return;
      final now = _session(s) ?? fresh;
      _replaceSet(s, now, i, now.sets[i].copyWith(type: picked));
    } else {
      final sets = [...fresh.sets]..removeAt(i);
      _resetControllers();
      s.updateSession(fresh.copyWith(sets: sets));
    }
  }

  /// Edit the recorded rest after a set (during or after the workout).
  Future<void> _editRest(AppState s, Session x, int i) async {
    final c = AppColors.of(context);
    final current = x.sets[i].restSec;
    final mins = TextEditingController(text: current == null ? '' : '${current ~/ 60}');
    final secs = TextEditingController(
      text: current == null ? '' : (current % 60).toString().padLeft(2, '0'),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Rest after this set'),
        content: Row(
          children: [
            Expanded(
              child: NumberBox(controller: mins, suffix: 'min', decimal: false, semanticLabel: 'Minutes', onChanged: (_) {}),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumberBox(controller: secs, suffix: 'sec', decimal: false, semanticLabel: 'Seconds', onChanged: (_) {}),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(-1),
            style: TextButton.styleFrom(foregroundColor: c.protein),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final m = int.tryParse(mins.text.trim()) ?? 0;
              final sec = int.tryParse(secs.text.trim()) ?? 0;
              Navigator.of(dialog).pop(m * 60 + sec);
            },
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    mins.dispose();
    secs.dispose();
    if (result == null || !mounted) return;
    final fresh = _session(s) ?? x;
    _replaceSet(s, fresh, i, fresh.sets[i].copyWith(restSec: result < 0 ? null : result));
  }

  /// Change the rest target for an exercise. In a planned workout it's saved
  /// to the plan, so next time starts with it too.
  Future<void> _editTarget(AppState s, Session x, String exerciseId) async {
    final c = AppColors.of(context);
    final current = _targetRest(s, x, exerciseId);
    String clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Rest target: ${s.exerciseName(exerciseId)}', style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sec in const [30, 45, 60, 90, 120, 150, 180, 240, 300])
                    ChoiceChip(
                      key: ValueKey('rest-target-$sec'),
                      label: Text(clock(sec)),
                      selected: sec == current,
                      selectedColor: c.accent,
                      labelStyle: TextStyle(color: sec == current ? c.onAccent : c.text),
                      backgroundColor: c.background,
                      side: BorderSide(color: c.line),
                      showCheckmark: false,
                      onSelected: (_) => Navigator.of(sheet).pop(sec),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final w = s.workoutById(x.workoutId);
    if (w != null && w.items.any((it) => it.exerciseId == exerciseId)) {
      s.saveWorkout(w.copyWith(items: [
        for (final it in w.items) it.exerciseId == exerciseId ? it.copyWith(restSec: picked) : it,
      ]));
      _restOverride.remove(exerciseId);
    } else {
      setState(() => _restOverride[exerciseId] = picked);
    }
    final fresh = _session(s) ?? x;
    _syncRestNotification(s, fresh);
  }

  Future<void> _finish(AppState s, Session x) async {
    final done = x.sets.where((e) => e.done).length;
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Finish workout?'),
        content: Text(done == 0
            ? 'No sets are ticked yet, so nothing would be saved.'
            : '$done ${done == 1 ? 'set' : 'sets'} logged. Sets you didn\'t tick are left out.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    s.reminders.cancelRest();
    s.finishSession(x);
    Navigator.of(context).pop();
    if (done > 0) {
      messenger.showSnackBar(SnackBar(content: Text('${x.name} saved: $done sets.')));
    }
  }

  void _saveEdit(AppState s, Session x) {
    final messenger = ScaffoldMessenger.of(context);
    final kept = s.saveEditedSession(x);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(kept ? 'Changes saved.' : 'No sets left, so the workout was deleted.'),
    ));
  }

  Future<void> _discard(AppState s, Session x) async {
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(x.finished ? 'Delete this workout?' : 'Discard this workout?'),
        content: Text(x.finished
            ? 'It\'s removed from your history, records and charts.'
            : 'Nothing from this session will be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.protein),
            child: Text(x.finished ? 'Delete' : 'Discard'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!x.finished) s.reminders.cancelRest();
    s.discardSession(x);
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    _imperial = s.settings.units == Units.imperial;
    final x = _session(s);
    if (x == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(child: Text('This workout was closed.', style: AppText.body(c))),
      );
    }
    _syncControllers(s, x);
    final minutes = DateTime.now().difference(x.startedAt).inMinutes;

    // Exercises in order of first appearance.
    final order = <String>[];
    for (final set in x.sets) {
      if (!order.contains(set.exerciseId)) order.add(set.exerciseId);
    }

    return PopScope(
      // Locked: the back gesture does nothing either.
      canPop: !_locked,
      child: Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: x.finished
                        ? 'Close; ticked changes are already kept'
                        : 'Close; the workout stays in progress',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      x.finished ? Icons.close_rounded : Icons.expand_more_rounded,
                      color: c.text,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          x.finished ? 'Edit ${x.name}' : x.name,
                          style: AppText.body(c).copyWith(fontSize: 19, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          x.finished ? longDate(x.date) : '$minutes min',
                          style: AppText.quiet(c),
                        ),
                      ],
                    ),
                  ),
                  if (!x.finished)
                    IconButton(
                      key: const ValueKey('lock-workout'),
                      tooltip: 'Lock the screen against pocket touches',
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        FocusScope.of(context).unfocus();
                        setState(() => _locked = true);
                      },
                      icon: Icon(Icons.lock_outline_rounded, color: c.text),
                    ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: c.text),
                    color: c.surface,
                    onSelected: (v) {
                      if (v == 'discard') _discard(s, x);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'discard',
                        child: Text(x.finished ? 'Delete workout' : 'Discard workout'),
                      ),
                    ],
                  ),
                  x.finished
                      ? SmallButton(label: 'Save', onTap: () => _saveEdit(s, x))
                      : SmallButton(label: 'Finish', onTap: () => _finish(s, x)),
                ],
              ),
            ),
            if (s.mesoById(x.mesoId) case final meso? when x.mesoWeek != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: meso.isDeloadWeek(x.mesoWeek!) ? c.chip : c.accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${meso.name} · ${meso.isDeloadWeek(x.mesoWeek!) ? 'Deload week' : 'Week ${x.mesoWeek} of ${meso.weeks}'}',
                      style: AppText.body(c).copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      s.mesoInstruction(meso, x.mesoWeek!),
                      style: AppText.quiet(c).copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            if (!x.finished && _restingIndex(x) != null)
              _restBar(s, c, x, _restingIndex(x)!),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  // The workout's own rules ("Add weight when you hit the top...").
                  if ((s.workoutById(x.workoutId)?.note ?? '').isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.assignment_outlined, size: 18, color: c.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.workoutById(x.workoutId)!.note!, style: AppText.body(c).copyWith(fontSize: 13, height: 1.35)),
                          ),
                        ],
                      ),
                    ),
                  for (var k = 0; k < order.length; k++) ...[
                    _exerciseCard(s, c, x, order[k], _inSuperset(s, x, order[k], order)),
                    if (k < order.length - 1 && _linked(s, x, order[k], order[k + 1]))
                      const SupersetLink(linked: true)
                    else
                      const SizedBox(height: 12),
                  ],
                  SmallButton(label: 'Add exercise', quiet: true, onTap: () => _addExercise(s, x)),
                  const SizedBox(height: 14),
                  _SessionNote(
                    key: ValueKey('note-${x.id}'),
                    initial: x.note ?? '',
                    onChanged: (t) {
                      final fresh = _session(s) ?? x;
                      s.updateSession(fresh.copyWith(note: t.trim().isEmpty ? null : t));
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    x.finished
                        ? 'Edits apply as you type. Unticked sets are removed '
                            'when you tap Save. Long-press a set number to mark a '
                            'warm-up or remove the set.'
                        : 'Every field is optional. Tick a set to log it; blank '
                            'fields fill in from last time. Your rest starts when you '
                            'tick and is saved when you tap End rest. Long-press a set '
                            'number to mark a warm-up or remove the set.',
                    style: AppText.quiet(c).copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
          ),
          if (_locked)
            Positioned.fill(
              child: _LockLayer(
                onUnlock: () {
                  HapticFeedback.mediumImpact();
                  setState(() => _locked = false);
                },
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _restBar(AppState s, AppColors c, Session x, int i) {
    final set = x.sets[i];
    final elapsed = DateTime.now().difference(set.restStartedAt!).inSeconds;
    final target = _targetRest(s, x, set.exerciseId);
    final reached = elapsed >= target;
    final key = '$i ${set.restStartedAt!.toIso8601String()}';
    if (reached && _buzzed != key) {
      _buzzed = key;
      HapticFeedback.heavyImpact();
      // Your own sound, if you picked one (only while the app is on screen;
      // otherwise the pop-up's sound plays).
      final sound = s.settings.restSoundPath;
      if (sound != null && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        Phone.playSound(sound).then((ok) {
          if (ok) s.reminders.cancelRestAlert();
        });
      }
    }
    String clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
    var number = 0;
    for (var j = 0; j <= i; j++) {
      if (x.sets[j].exerciseId == set.exerciseId && !x.sets[j].warmup) number++;
    }
    final after = set.warmup
        ? '${s.exerciseName(set.exerciseId)} warm-up'
        : '${s.exerciseName(set.exerciseId)} set $number';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rest started after $after',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.background.withAlpha(180), fontSize: 13),
                    ),
                    Text(
                      clock(elapsed),
                      style: TextStyle(
                        color: c.background,
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    GestureDetector(
                      key: const ValueKey('rest-target'),
                      onTap: () => _editTarget(s, x, set.exerciseId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          reached ? 'Target ${clock(target)} reached · change' : 'Target ${clock(target)} · change',
                          style: TextStyle(
                            color: reached ? c.accent : c.background.withAlpha(180),
                            fontSize: 13,
                            fontWeight: reached ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                child: GestureDetector(
                  onTap: () => _endRestTapped(s, x),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'End rest',
                      style: TextStyle(color: c.onAccent, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (elapsed / target).clamp(0.0, 1.0),
              minHeight: 5,
              color: c.accent,
              backgroundColor: c.background.withAlpha(50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardioCard(AppState s, AppColors c, Session x, String exerciseId, bool superset) {
    final ex = s.exercise(exerciseId);
    final dUnit = _imperial ? 'mi' : 'km';
    final prev = s.lastSetsFor(exerciseId, exceptSession: x.id);
    String summary(SetEntry e) {
      final parts = <String>[
        if (e.durationSec != null) clockText(e.durationSec!),
        if (e.distanceKm != null) '${_fmtDistance(e.distanceKm!)} $dUnit',
      ];
      return parts.isEmpty ? 'logged' : parts.join(' · ');
    }

    final rows = <int>[
      for (var i = 0; i < x.sets.length; i++)
        if (x.sets[i].exerciseId == exerciseId) i,
    ];
    final plan = _planItem(s, x, exerciseId);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: superset ? Border.all(color: c.accent, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ex?.name ?? 'Cardio',
            style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w500),
          ),
          Text(
            [
              if (plan?.targetMin != null) 'Target ${plan!.targetMin} min',
              prev.isEmpty ? 'First time logging this' : 'Last time: ${prev.map(summary).join(', ')}',
            ].join(' · '),
            style: AppText.quiet(c).copyWith(fontSize: 12),
          ),
          _noteLine(s, c, exerciseId, x),
          const SizedBox(height: 8),
          for (var n = 0; n < rows.length; n++)
            Builder(builder: (context) {
              final i = rows[n];
              final set = x.sets[i];
              SetEntry current() => (_session(s) ?? x).sets[i];
              final dist = set.distanceKm == null
                  ? null
                  : (_imperial ? kmToMi(set.distanceKm!) : set.distanceKm!);
              final pace = paceSecPer(dist, set.durationSec);
              return _CardioRow(
                label: rows.length == 1 ? '' : '${n + 1}',
                time: _weight[i],
                distance: _reps[i],
                heartRate: _hr[i],
                calories: _kcal[i],
                distanceUnit: dUnit,
                pace: pace == null ? null : '${clockText(pace.round())} /$dUnit',
                done: set.done,
                onTime: (t) => _replaceSet(s, _session(s) ?? x, i, current().copyWith(durationSec: parseClock(t))),
                onDistance: (t) {
                  final v = parseNumber(t);
                  _replaceSet(
                    s,
                    _session(s) ?? x,
                    i,
                    current().copyWith(
                      distanceKm: v == null || v < 0 ? null : (_imperial ? miToKm(v) : v),
                    ),
                  );
                },
                onHeartRate: (t) => _replaceSet(s, _session(s) ?? x, i, current().copyWith(heartRate: int.tryParse(t.trim()))),
                onCalories: (t) => _replaceSet(s, _session(s) ?? x, i, current().copyWith(calories: int.tryParse(t.trim()))),
                onDone: () => _toggleDone(s, _session(s) ?? x, i),
                onMenu: () => _setMenu(s, x, i),
              );
            }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addSet(s, x, exerciseId),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add interval'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNote(AppState s, Session x, String exerciseId) async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController(text: s.sessionNoteFor(x, exerciseId) ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Note for ${s.exerciseName(exerciseId)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: c.accent,
          decoration: InputDecoration(
            hintText: 'e.g. Seat height 4',
            helperText: x.finished ? 'Changes this workout only' : 'Also used next time you do it',
            helperMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(ctrl.text),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) s.setSessionNote(_session(s) ?? x, exerciseId, result);
  }

  Widget _noteLine(AppState s, AppColors c, String exerciseId, Session x) {
    final note = s.sessionNoteFor(x, exerciseId);
    final fromWorkout = s.workoutNoteFor(x, exerciseId);
    final line = GestureDetector(
      onTap: () => _editNote(s, x, exerciseId),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(
              note == null ? Icons.add_rounded : Icons.sticky_note_2_outlined,
              size: 15,
              color: note == null ? c.muted : c.accent,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                note ?? 'Add note',
                style: AppText.quiet(c).copyWith(
                  fontSize: 12,
                  color: note == null ? c.muted : c.text,
                  fontStyle: note == null ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (fromWorkout == null) return line;
    // This workout's note for the exercise ("Full depth."), above your own note.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.assignment_outlined, size: 15, color: c.accent),
              const SizedBox(width: 6),
              Expanded(child: Text(fromWorkout, style: AppText.quiet(c).copyWith(fontSize: 12, color: c.text))),
            ],
          ),
        ),
        line,
      ],
    );
  }

  Widget _exerciseCard(AppState s, AppColors c, Session x, String exerciseId, bool superset) {
    if (s.isCardio(exerciseId)) return _cardioCard(s, c, x, exerciseId, superset);
    final ex = s.exercise(exerciseId);
    final bodyweight = ex?.bodyweight ?? false;
    final prev = s.lastSetsFor(exerciseId, exceptSession: x.id);
    final best = s.bestE1rm(exerciseId, exceptSession: x.id);
    String setText(SetEntry e) {
      final w = e.weightKg;
      final r = e.reps;
      final ws = bodyweight
          ? (w == null || w == 0 ? 'BW' : '+${_fmtWeight(w)}')
          : (w == null ? '–' : _fmtWeight(w));
      return '$ws × ${r ?? '–'}';
    }

    // Rows for this exercise: (index in session, label). Warm-ups show "W".
    final rows = <(int, String)>[];
    var working = 0;
    for (var i = 0; i < x.sets.length; i++) {
      if (x.sets[i].exerciseId != exerciseId) continue;
      if (x.sets[i].warmup) {
        rows.add((i, 'W'));
      } else {
        working++;
        rows.add((i, '$working${x.sets[i].type.short}')); // "2D", "3F"
      }
    }

    bool typedNotLogged(SetEntry e) => !e.done && (e.weightKg != null || e.reps != null);
    final pending = rows.any((r) => typedNotLogged(x.sets[r.$1]));
    String clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

    // The target, always on show: the plan's weight (else your top set last
    // time) and rep range, and the rest target (tap to change).
    final plan = _planItem(s, x, exerciseId);
    double? lastTop;
    for (final e in prev) {
      final w = e.weightKg;
      if (w != null && w > 0 && (lastTop == null || w > lastTop)) lastTop = w;
    }
    final targetKg = plan?.loadKg ?? lastTop;
    final targetParts = <String>[
      if (targetKg != null) bodyweight ? '+${_fmtWeight(targetKg)} $_unit' : '${_fmtWeight(targetKg)} $_unit',
      if (plan != null) '${plan.repsLow == plan.repsHigh ? plan.repsLow : '${plan.repsLow}–${plan.repsHigh}'} reps',
    ];
    final rest = _targetRest(s, x, exerciseId);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: superset ? Border.all(color: c.accent, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ex?.name ?? 'Exercise',
                      style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      prev.isEmpty
                          ? 'First time logging this'
                          : 'Last time: ${prev.map(setText).join(', ')}',
                      style: AppText.quiet(c).copyWith(fontSize: 12),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (targetParts.isNotEmpty)
                            Text(
                              'Target ${targetParts.join(' × ')}${plan?.loadKg == null && targetKg != null ? ' (last time)' : ''}',
                              key: ValueKey('target-$exerciseId'),
                              style: AppText.body(c).copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          GestureDetector(
                            key: ValueKey('rest-chip-$exerciseId'),
                            onTap: () => _editTarget(s, x, exerciseId),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(10)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.timer_outlined, size: 13, color: c.muted),
                                  const SizedBox(width: 4),
                                  Text('Rest ${clock(rest)}', style: AppText.quiet(c).copyWith(fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _noteLine(s, c, exerciseId, x),
                  ],
                ),
              ),
              if (best != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.accent.withAlpha(36),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'e1RM ${_fmtWeight(best)}',
                    style: TextStyle(color: c.accent, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          if (_record != null && _recordExercise == exerciseId) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, color: c.onAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _record!,
                      style: TextStyle(color: c.onAccent, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(width: 34, child: Text('Set', style: AppText.quiet(c).copyWith(fontSize: 12))),
              Expanded(child: Text('Previous', style: AppText.quiet(c).copyWith(fontSize: 12))),
              SizedBox(
                width: 76,
                child: Text(
                  bodyweight ? '+$_unit' : _unit,
                  textAlign: TextAlign.center,
                  style: AppText.quiet(c).copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 56,
                child: Text('Reps', textAlign: TextAlign.center, style: AppText.quiet(c).copyWith(fontSize: 12)),
              ),
              const SizedBox(width: 48),
            ],
          ),
          for (final (i, label) in rows)
            Builder(builder: (context) {
              final set = x.sets[i];
              final (hw, hr, p) = _hint(s, x, i);
              SetEntry current() => (_session(s) ?? x).sets[i];
              return _SetRow(
                label: label,
                warmup: set.warmup,
                special: set.type != SetType.normal && !set.warmup,
                previous: p == null ? '–' : setText(p),
                weight: _weight[i],
                reps: _reps[i],
                weightHint: hw == null ? (bodyweight ? '0' : '') : _fmtWeight(hw),
                repsHint: hr == null ? '' : '$hr',
                done: set.done,
                onWeight: (t) => _replaceSet(
                  s,
                  _session(s) ?? x,
                  i,
                  current().copyWith(weightKg: _parseWeight(t)),
                ),
                onReps: (t) => _replaceSet(
                  s,
                  _session(s) ?? x,
                  i,
                  current().copyWith(reps: int.tryParse(t.trim())),
                ),
                onDone: () => _toggleDone(s, _session(s) ?? x, i),
                // The keyboard's check on reps logs the set like the row's
                // tick, except when re-editing a set that's already logged.
                onSubmitReps: () {
                  if (!current().done) {
                    _toggleDone(s, _session(s) ?? x, i);
                  } else {
                    FocusScope.of(context).unfocus();
                  }
                },
                onMenu: () => _setMenu(s, x, i),
                pending: typedNotLogged(set),
                // The rest taken after a set: small, and tap to fix it.
                restText: !set.done || set.resting
                    ? null
                    : set.restSec != null
                        ? 'Rest ${clock(set.restSec!)}'
                        : (x.finished ? 'Add rest time' : null),
                onRest: () => _editRest(s, _session(s) ?? x, i),
              );
            }),
          if (pending && !x.finished)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Tap ✓ beside the set, or ✓ on the keyboard after reps, to log '
                'it and start your rest.',
                style: AppText.quiet(c).copyWith(color: c.accent, fontSize: 12),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _addSet(s, x, exerciseId),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add set'),
              ),
              if (!s.isCardio(exerciseId))
                TextButton.icon(
                  key: ValueKey('warmup-$exerciseId'),
                  onPressed: () => _addWarmup(s, x, exerciseId),
                  style: TextButton.styleFrom(foregroundColor: c.accent),
                  icon: const Icon(Icons.trending_up_rounded, size: 18),
                  label: const Text('Add warm-up'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.label,
    required this.warmup,
    this.special = false,
    required this.previous,
    required this.weight,
    required this.reps,
    required this.weightHint,
    required this.repsHint,
    required this.done,
    required this.onWeight,
    required this.onReps,
    required this.onDone,
    required this.onMenu,
    this.pending = false,
    this.restText,
    this.onRest,
    this.onSubmitReps,
  });

  /// Keyboard check on the reps field.
  final VoidCallback? onSubmitReps;

  /// Has typed values but isn't logged yet.
  final bool pending;

  /// The rest taken after this set ("Rest 2:05"), tap to change.
  final String? restText;
  final VoidCallback? onRest;

  final String label;
  final bool warmup;

  /// A drop set, failure, partial and so on: shown in the accent colour.
  final bool special;
  final String previous;
  final TextEditingController weight;
  final TextEditingController reps;
  final String weightHint;
  final String repsHint;
  final bool done;
  final ValueChanged<String> onWeight;
  final ValueChanged<String> onReps;
  final VoidCallback onDone;
  final VoidCallback onMenu;

  Widget _field(AppColors c, TextEditingController ctrl, String hint, bool decimal,
      ValueChanged<String> onChanged, String semantic, TextInputAction action,
      [VoidCallback? onSubmit]) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: done ? c.accent.withAlpha(30) : c.background,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Semantics(
        label: semantic,
        child: TextField(
          controller: ctrl,
          onChanged: onChanged,
          textInputAction: action,
          onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
          textAlign: TextAlign.center,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
          ],
          cursorColor: c.accent,
          style: AppText.body(c).copyWith(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: hint,
            hintStyle: AppText.quiet(c).copyWith(fontSize: 15),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final row = _row(context, c);
    final rt = restText;
    if (rt == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: Semantics(
            button: true,
            label: '$rt. Tap to change.',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onRest,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 13, color: c.muted),
                    const SizedBox(width: 4),
                    Text(rt, style: AppText.quiet(c).copyWith(fontSize: 12)),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined, size: 12, color: c.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: GestureDetector(
              onLongPress: onMenu,
              // Shrinks to fit ("12RP") rather than wrapping onto two lines.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: warmup ? c.protein : (special ? c.accent : c.text),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(previous, style: AppText.quiet(c).copyWith(fontSize: 13)),
          ),
          SizedBox(
            width: 76,
            child: _field(c, weight, weightHint, true, onWeight, 'Set $label weight', TextInputAction.next),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: _field(c, reps, repsHint, false, onReps, 'Set $label reps', TextInputAction.done, onSubmitReps),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: done ? 'Set $label done' : 'Mark set $label done',
            child: GestureDetector(
              onTap: onDone,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: done ? c.accent : (pending ? c.accent.withAlpha(36) : Colors.transparent),
                  border: done ? null : Border.all(color: pending ? c.accent : c.line, width: pending ? 2 : 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: done ? c.onAccent : (pending ? c.accent : c.muted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardioRow extends StatelessWidget {
  const _CardioRow({
    required this.label,
    required this.time,
    required this.distance,
    required this.heartRate,
    required this.calories,
    required this.distanceUnit,
    required this.pace,
    required this.done,
    required this.onTime,
    required this.onDistance,
    required this.onHeartRate,
    required this.onCalories,
    required this.onDone,
    required this.onMenu,
  });

  final String label;
  final TextEditingController time;
  final TextEditingController distance;
  final TextEditingController heartRate;
  final TextEditingController calories;
  final String distanceUnit;
  final String? pace;
  final bool done;
  final ValueChanged<String> onTime;
  final ValueChanged<String> onDistance;
  final ValueChanged<String> onHeartRate;
  final ValueChanged<String> onCalories;
  final VoidCallback onDone;
  final VoidCallback onMenu;

  Widget _box(AppColors c, String caption, TextEditingController ctrl, String hint,
      ValueChanged<String> onChanged, TextInputType type, TextInputAction action,
      [VoidCallback? onSubmit]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: AppText.quiet(c).copyWith(fontSize: 11)),
        const SizedBox(height: 2),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: done ? c.accent.withAlpha(30) : c.background,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: ctrl,
            onChanged: onChanged,
            keyboardType: type,
            textInputAction: action,
            onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
            cursorColor: c.accent,
            style: AppText.body(c).copyWith(fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: hint,
              hintStyle: AppText.quiet(c).copyWith(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const decimal = TextInputType.numberWithOptions(decimal: true);
    const whole = TextInputType.number;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (label.isNotEmpty)
                SizedBox(
                  width: 26,
                  child: GestureDetector(
                    onLongPress: onMenu,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              Expanded(
                child: _box(c, 'Time', time, 'mm:ss', onTime, decimal, TextInputAction.next),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _box(c, 'Distance ($distanceUnit)', distance, '0.0', onDistance, decimal,
                    TextInputAction.done, done ? null : onDone),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: done ? 'Logged' : 'Log this',
                child: GestureDetector(
                  onTap: onDone,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: done ? c.accent : Colors.transparent,
                      border: done ? null : Border.all(color: c.line, width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.check_rounded, size: 20, color: done ? c.onAccent : c.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (label.isNotEmpty) const SizedBox(width: 26),
              Expanded(
                child: _box(c, 'Avg heart rate (optional)', heartRate, 'bpm', onHeartRate, whole,
                    TextInputAction.next),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _box(c, 'Calories (optional)', calories, 'kcal', onCalories, whole,
                    TextInputAction.done),
              ),
              const SizedBox(width: 48),
            ],
          ),
          if (pace != null)
            Padding(
              padding: EdgeInsets.only(left: label.isNotEmpty ? 26 : 0, top: 4),
              child: Text('Pace $pace', style: AppText.quiet(c).copyWith(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _SessionNote extends StatefulWidget {
  const _SessionNote({super.key, required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SessionNote> createState() => _SessionNoteState();
}

class _SessionNoteState extends State<_SessionNote> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: _ctrl,
        onChanged: widget.onChanged,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: c.accent,
        style: AppText.body(c),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: 'Workout note (optional): how it felt, anything to remember',
          hintStyle: AppText.quiet(c),
        ),
      ),
    );
  }
}

/// Over the workout while it's locked: taps do nothing, the rest clock still
/// shows through, and a slide along the bottom unlocks.
class _LockLayer extends StatelessWidget {
  const _LockLayer({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: 'Workout locked. Slide to unlock.',
      child: GestureDetector(
        // Swallows every tap and scroll on the workout below.
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onVerticalDragUpdate: (_) {},
        child: ColoredBox(
          color: c.background.withAlpha(150),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
                Icon(Icons.lock_rounded, size: 34, color: c.text),
                const SizedBox(height: 6),
                Text('Locked', style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
                Text('The screen stays on. Slide to unlock.', style: AppText.quiet(c)),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: SlideToUnlock(onUnlock: onUnlock),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A track with a handle: drag it most of the way across to unlock.
class SlideToUnlock extends StatefulWidget {
  const SlideToUnlock({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  State<SlideToUnlock> createState() => _SlideToUnlockState();
}

class _SlideToUnlockState extends State<SlideToUnlock> {
  double _x = 0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const size = 56.0;
    return LayoutBuilder(builder: (context, box) {
      final room = box.maxWidth - size - 8;
      return Container(
        key: const ValueKey('slide-to-unlock'),
        height: size + 8,
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(32), border: Border.all(color: c.line)),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Center(
              child: Text('Slide to unlock', style: AppText.quiet(c).copyWith(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            Positioned(
              left: 4 + _x,
              child: GestureDetector(
                key: const ValueKey('unlock-handle'),
                onHorizontalDragUpdate: (d) => setState(() => _x = (_x + d.delta.dx).clamp(0.0, room)),
                onHorizontalDragEnd: (_) {
                  if (_x >= room * 0.85) {
                    widget.onUnlock();
                  } else {
                    setState(() => _x = 0);
                  }
                },
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_forward_rounded, color: c.onAccent),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
