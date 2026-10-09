import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/sleep_editor.dart';
import 'camera_screen.dart';
import 'food_add_sheet.dart';
import 'food_screen.dart';
import 'measurements_view.dart';
import 'plan_screen.dart';
import 'supplements_screen.dart';

enum _Pill { due, done, later }

/// Everything you log, one section open at a time. Each section says how
/// often it's asked for and whether it's due.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  String? _open;
  bool _touched = false;
  bool _editWeight = false;
  bool _editSleep = false;
  final _weight = TextEditingController();

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  DateTime get _today => dateOnly(DateTime.now());

  void _toggle(String key) {
    setState(() {
      _touched = true;
      _open = _open == key ? null : key;
    });
  }

  void _saveWeight(AppState s) {
    final v = parseNumber(_weight.text);
    if (v == null) return;
    final imperial = s.settings.units == Units.imperial;
    final kg = imperial ? lbToKg(v) : v;
    if (kg < 30 || kg > 350) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That number looks off. Check it and try again.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    s.logWeight(kg);
    setState(() => _editWeight = false);
  }

  Future<void> _pickWorkout(AppState s) async {
    final c = AppColors.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text('Start a workout', style: AppText.body(c).copyWith(fontWeight: FontWeight.w600))),
            for (final w in s.workouts)
              ListTile(
                leading: Icon(Icons.fitness_center_rounded, color: c.accent),
                title: Text(w.name),
                subtitle: Text('${w.items.length} exercises'),
                onTap: () => Navigator.of(sheet).pop(w.id),
              ),
            ListTile(
              leading: Icon(Icons.add_rounded, color: c.muted),
              title: const Text('Empty workout'),
              subtitle: const Text('Add exercises as you go'),
              onTap: () => Navigator.of(sheet).pop(''),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    startOrResume(context, s.workoutById(choice));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final today = _today;
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    String w(double kg) => oneDecimal(imperial ? kgToLb(kg) : kg);

    final weighIn = s.weighInOn(today);
    final night = s.sleepOn(today);
    final eaten = s.eatenOn(today);
    final t = s.targets;
    final active = s.activeSession;
    final plannedToday = [
      for (final p in s.plannedOn(today))
        if (!s.plannedDone(p) && s.workoutById(p.workoutId) != null) p,
    ];
    final doneToday = s.finishedOn(today);
    final photosDue = s.photosAreDue;
    final last = s.lastCheckin;
    final weeks = s.settings.photoIntervalWeeks;
    final nextPhotos = last == null || weeks == 0 ? null : DateTime(last.year, last.month, last.day + 7 * weeks);
    final dates = s.measurementDates;
    final lastMeasure = dates.isEmpty ? null : dates.last;
    final nextMeasure = lastMeasure == null ? null : DateTime(lastMeasure.year, lastMeasure.month, lastMeasure.day + 28);
    final measureDue = s.settings.measurementsOn && (nextMeasure == null || !nextMeasure.isAfter(today));

    final dueKeys = [
      if (weighIn == null) 'weight',
      if (night == null) 'sleep',
      if (photosDue) 'photos',
      if (measureDue) 'measure',
    ];
    final open = _touched ? _open : (dueKeys.isEmpty ? null : dueKeys.first);

    Widget pill(String text, _Pill kind) {
      final (bg, fg) = switch (kind) {
        _Pill.due => (c.protein.withAlpha(36), c.protein),
        _Pill.done => (c.accent.withAlpha(36), c.accent),
        _Pill.later => (c.chip, c.muted),
      };
      return Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
    }

    final sections = <(String, IconData, String, String, Widget, Widget)>[];

    // ---- weight
    sections.add((
      'weight',
      Icons.monitor_weight_outlined,
      'Weight',
      'Every day, when you wake up',
      weighIn == null ? pill('Due now', _Pill.due) : pill('Logged', _Pill.done),
      weighIn != null && !_editWeight
          ? Row(
              children: [
                Expanded(child: Text('${w(weighIn.weightKg)} $unit logged today', style: AppText.body(c))),
                SmallButton(
                  label: 'Edit',
                  quiet: true,
                  onTap: () {
                    _weight.text = w(weighIn.weightKg);
                    setState(() => _editWeight = true);
                  },
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: NumberBox(
                        key: const ValueKey('log-weight'),
                        controller: _weight,
                        suffix: unit,
                        semanticLabel: 'Weight in $unit',
                        onChanged: (_) {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    SmallButton(label: 'Save', onTap: () => _saveWeight(s)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('After the bathroom, before eating or drinking.', style: AppText.quiet(c).copyWith(fontSize: 12)),
              ],
            ),
    ));

    // ---- sleep
    final q = night?.quality;
    final mins = night?.durationMin;
    sections.add((
      'sleep',
      Icons.bedtime_outlined,
      'Sleep',
      'Every day, when you wake up',
      night == null ? pill('Due now', _Pill.due) : pill('Logged', _Pill.done),
      night != null && !_editSleep
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    [if (mins != null) formatSleep(mins), if (q != null) 'quality $q of 5'].join(' · '),
                    style: AppText.body(c),
                  ),
                ),
                SmallButton(label: 'Edit', quiet: true, onTap: () => setState(() => _editSleep = true)),
              ],
            )
          : SleepEditor(
              date: today,
              title: 'Last night',
              onClose: () => setState(() => _editSleep = false),
            ),
    ));

    // ---- water
    final imperialWater = s.settings.units == Units.imperial;
    final drank = s.waterOn(today);
    sections.add((
      'water',
      Icons.water_drop_outlined,
      'Water',
      'Through the day',
      pill(
        '${formatWater(drank, imperial: imperialWater)} of ${formatWater(s.waterGoalMl, imperial: imperialWater)}',
        drank >= s.waterGoalMl ? _Pill.done : _Pill.later,
      ),
      _WaterBody(day: today),
    ));

    // ---- supplements (only when turned on)
    if (s.settings.supplementsOn) {
      final list = s.activeSupplements;
      final taken = list.where((x) => s.doseOf(x, today) != null).length;
      sections.add((
        'supplements',
        Icons.medication_outlined,
        'Supplements',
        'Every day',
        pill(
          list.isEmpty ? 'Set up' : '$taken of ${list.length} taken',
          list.isNotEmpty && taken == list.length ? _Pill.done : _Pill.later,
        ),
        SupplementChecklist(day: today),
      ));
    }

    // ---- food
    final meals = Meal.values;
    sections.add((
      'food',
      Icons.restaurant_rounded,
      'Food',
      'Through the day',
      pill(t == null ? '${thousands(eaten.kcal)} kcal' : '${thousands(eaten.kcal)} of ${thousands(t.kcal)} kcal', _Pill.later),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: t.kcal <= 0 ? 0 : (eaten.kcal / t.kcal).clamp(0.0, 1.0),
                minHeight: 8,
                color: c.accent,
                backgroundColor: c.chip,
              ),
            ),
          for (final m in meals)
            Container(
              constraints: const BoxConstraints(minHeight: 46),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Row(
                children: [
                  Expanded(child: Text(m.label, style: AppText.body(c).copyWith(fontSize: 14))),
                  Text(
                    () {
                      final e = s.entriesOn(today, m);
                      if (e.isEmpty) return 'Not logged';
                      var k = 0.0;
                      for (final x in e) {
                        k += x.macros.kcal;
                      }
                      return '${e.length} ${e.length == 1 ? 'item' : 'items'} · ${k.round()} kcal';
                    }(),
                    style: AppText.quiet(c).copyWith(fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Add to ${m.label}',
                    onPressed: () => FoodAddSheet.open(context, today, m),
                    icon: Icon(Icons.add_circle_outline_rounded, color: c.accent),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(FoodLogPage.route()),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: const Text('Open the full food log'),
            ),
          ),
        ],
      ),
    ));

    // ---- workout
    final Widget workoutBody;
    final Widget workoutPill;
    if (active != null) {
      workoutPill = pill('In progress', _Pill.due);
      workoutBody = Row(
        children: [
          Expanded(child: Text('${active.name} is in progress', style: AppText.body(c))),
          SmallButton(label: 'Resume', onTap: () => startOrResume(context, null)),
        ],
      );
    } else if (plannedToday.isNotEmpty) {
      workoutPill = pill('Planned', _Pill.later);
      workoutBody = Column(
        children: [
          for (final p in plannedToday)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.workoutById(p.workoutId)!.name, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        () {
                          final m = s.mesoById(p.mesoId);
                          final wk = p.mesoWeek;
                          if (m == null || wk == null) return 'From your calendar';
                          return m.isDeloadWeek(wk) ? '${m.name} · deload week' : '${m.name} · week $wk of ${m.weeks}';
                        }(),
                        style: AppText.quiet(c).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                SmallButton(label: 'Start', onTap: () => startOrResume(context, s.workoutById(p.workoutId))),
              ],
            ),
        ],
      );
    } else if (doneToday.isNotEmpty) {
      workoutPill = pill('Done', _Pill.done);
      workoutBody = Row(
        children: [
          Expanded(child: Text('${doneToday.last.name} done today', style: AppText.body(c))),
          SmallButton(label: 'Another', quiet: true, onTap: () => _pickWorkout(s)),
        ],
      );
    } else {
      workoutPill = pill('Rest day', _Pill.later);
      workoutBody = Row(
        children: [
          Expanded(child: Text('Nothing planned today.', style: AppText.body(c))),
          SmallButton(label: 'Start one', quiet: true, onTap: () => _pickWorkout(s)),
        ],
      );
    }
    sections.add(('workout', Icons.fitness_center_rounded, 'Workout', 'From your plan', workoutPill, workoutBody));

    // ---- progress photos
    sections.add((
      'photos',
      Icons.photo_camera_outlined,
      'Progress photos',
      weeks == 0 ? 'Reminders off' : (weeks == 1 ? 'Every week' : 'Every $weeks weeks'),
      photosDue
          ? pill('Due', _Pill.due)
          : pill(nextPhotos == null ? 'Any time' : 'Next ${shortDate(nextPhotos)}', _Pill.later),
      Row(
        children: [
          Expanded(
            child: Text(
              last == null ? 'Front, side and back · about 2 min' : 'Last check-in ${shortDate(last)}',
              style: AppText.quiet(c),
            ),
          ),
          SmallButton(
            label: 'Take photos',
            quiet: !photosDue,
            onTap: () => Navigator.of(context).push(CameraScreen.route()),
          ),
        ],
      ),
    ));

    // ---- measurements (only when turned on)
    if (s.settings.measurementsOn) {
      sections.add((
        'measure',
        Icons.straighten_rounded,
        'Measurements',
        'Every 4 weeks',
        measureDue ? pill('Due', _Pill.due) : pill('Next ${shortDate(nextMeasure!)}', _Pill.later),
        Row(
          children: [
            Expanded(
              child: Text(
                lastMeasure == null ? 'No measurements yet' : 'Last: ${shortDate(lastMeasure)}',
                style: AppText.quiet(c),
              ),
            ),
            SmallButton(
              label: measureDue ? 'Measure' : 'Measure early',
              quiet: !measureDue,
              onTap: () => MeasurementsView.openSheet(context, today),
            ),
          ],
        ),
      ));
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Log', style: AppText.title(c)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Text(
              dueKeys.isEmpty
                  ? 'All caught up. Each section asks only when it needs you.'
                  : '${dueKeys.length} ${dueKeys.length == 1 ? 'thing is' : 'things are'} due now. Each section asks only when it needs you.',
              style: AppText.quiet(c),
            ),
          ),
          Container(
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(22)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < sections.length; i++)
                  _Section(
                    first: i == 0,
                    icon: sections[i].$2,
                    title: sections[i].$3,
                    cadence: sections[i].$4,
                    pill: sections[i].$5,
                    open: open == sections[i].$1,
                    onToggle: () => _toggle(sections[i].$1),
                    child: sections[i].$6,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.first,
    required this.icon,
    required this.title,
    required this.cadence,
    required this.pill,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final bool first;
  final IconData icon;
  final String title;
  final String cadence;
  final Widget pill;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: c.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '$title, $cadence',
            child: InkWell(
              onTap: onToggle,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: c.accent.withAlpha(36), borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, size: 19, color: c.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                            Text(cadence, style: AppText.quiet(c).copyWith(fontSize: 12)),
                          ],
                        ),
                      ),
                      pill,
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(Icons.expand_more_rounded, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(padding: const EdgeInsets.fromLTRB(14, 2, 14, 16), child: child)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Today's water: quick adds, the drinks so far, and the daily goal.
class _WaterBody extends StatelessWidget {
  const _WaterBody({required this.day});

  final DateTime day;

  Future<double?> _ask(BuildContext context, String title, String unit, double? start) async {
    final c = AppColors.of(context);
    final ctrl = TextEditingController(text: start == null ? '' : oneDecimal(start));
    final v = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title),
        content: NumberBox(controller: ctrl, suffix: unit, semanticLabel: title, onChanged: (_) {}),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(d).pop(parseNumber(ctrl.text)), child: const Text('OK')),
        ],
      ),
    );
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final step = waterStepMl(imperial: imperial);
    final entries = s.waterEntriesOn(day).reversed.toList();
    final unit = imperial ? 'cups' : 'ml';
    double toMl(double v) => imperial ? v * mlPerCup : v;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SmallButton(label: imperial ? '+1 cup' : '+250 ml', onTap: () => s.addWater(step, day: day))),
            const SizedBox(width: 8),
            Expanded(child: SmallButton(label: imperial ? '+2 cups' : '+500 ml', quiet: true, onTap: () => s.addWater(step * 2, day: day))),
            const SizedBox(width: 8),
            Expanded(
              child: SmallButton(
                label: 'Other',
                quiet: true,
                onTap: () async {
                  final v = await _ask(context, 'How much water?', unit, null);
                  if (v != null && v > 0) s.addWater(toMl(v), day: day);
                },
              ),
            ),
          ],
        ),
        for (final e in entries)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${TimeOfDay.fromDateTime(e.at).format(context)}  ·  ${formatWater(e.ml, imperial: imperial)}',
                  style: AppText.body(c).copyWith(fontSize: 14),
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => s.removeWater(e),
                icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
              ),
            ],
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text('Daily goal: ${formatWater(s.waterGoalMl, imperial: imperial)}', style: AppText.quiet(c).copyWith(fontSize: 13)),
            ),
            TextButton(
              key: const ValueKey('water-goal'),
              onPressed: () async {
                final current = imperial ? s.waterGoalMl / mlPerCup : s.waterGoalMl;
                final v = await _ask(context, 'Daily water goal', unit, current);
                if (v != null && v > 0) s.setSettings(s.settings.copyWith(waterGoalMl: toMl(v)));
              },
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: const Text('Change'),
            ),
          ],
        ),
      ],
    );
  }
}
