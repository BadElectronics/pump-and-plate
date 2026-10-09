import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'history_screen.dart';
import 'plan_screen.dart';

const _dows = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _dowsLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

enum _View { month, week, day }

/// Something being placed on a day: a workout or recipe from a tray, or a
/// planned workout being moved.
class _Drag {
  _Drag.workout(String id)
      : workoutId = id,
        recipeId = null,
        planned = null;
  _Drag.recipe(String id)
      : recipeId = id,
        workoutId = null,
        planned = null;
  _Drag.move(PlannedWorkout p)
      : planned = p,
        workoutId = p.workoutId,
        recipeId = null;

  final String? workoutId;
  final String? recipeId;
  final PlannedWorkout? planned;

  bool same(_Drag? o) =>
      o != null && o.workoutId == workoutId && o.recipeId == recipeId && o.planned?.id == planned?.id;
}

/// Plan > Calendar: workouts and meals on Month, Week and Today views.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key, this.mealsTick = 0});

  /// When this changes, the Add meals tray opens.
  final int mealsTick;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  _View _view = _View.month;
  late DateTime _month;
  late DateTime _week;
  DateTime? _day;

  /// '' closed, 'w' workouts, 'm' meals.
  String _tray = '';
  _Drag? _picked;

  DateTime get _today => dateOnly(DateTime.now());

  /// The last "Add meals in Plan" request already acted on. Static, because
  /// the calendar is rebuilt each time Plan opens and must not reopen the
  /// tray for an old request.
  static int _seenMealsTick = 0;

  void _checkMealsRequest() {
    if (widget.mealsTick > _seenMealsTick) {
      _seenMealsTick = widget.mealsTick;
      _tray = 'm';
      _picked = null;
    }
  }

  @override
  void initState() {
    super.initState();
    final t = _today;
    _month = DateTime(t.year, t.month, 1);
    _checkMealsRequest();
  }

  /// Sunday or Monday first (from settings); null until first read.
  bool? _sundayFirst;
  bool get _sunFirst => _sundayFirst ?? true;
  DateTime _startOf(DateTime d) => weekStartOf(d, sundayFirst: _sunFirst);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Settings can't be read in initState; this also keeps the week view
    // lined up if the week start is changed.
    final sun = AppScope.of(context).settings.weekStartsSunday;
    if (_sundayFirst == null) {
      _sundayFirst = sun;
      _week = _startOf(_today);
    } else if (sun != _sundayFirst) {
      _sundayFirst = sun;
      _week = _startOf(_week);
    }
  }

  @override
  void didUpdateWidget(CalendarView old) {
    super.didUpdateWidget(old);
    if (widget.mealsTick != old.mealsTick) setState(_checkMealsRequest);
  }

  void _undo(String text, VoidCallback undo) => showUndo(context, text, undo);

  String _dayName(DateTime d) => '${_dows[d.weekday - 1]} ${shortDate(d)}';

  Future<Meal?> _askMeal(String what, DateTime day) {
    final c = AppColors.of(context);
    return showModalBottomSheet<Meal>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('$what on ${_dayName(day)}', style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
              subtitle: const Text('Which meal is it?'),
            ),
            for (final m in Meal.values)
              ListTile(title: Text(m.label), onTap: () => Navigator.of(sheet).pop(m)),
          ],
        ),
      ),
    );
  }

  Future<void> _place(AppState s, _Drag d, DateTime day) async {
    HapticFeedback.mediumImpact();
    final recipeId = d.recipeId;
    if (recipeId != null) {
      final r = s.recipe(recipeId);
      if (r == null) return;
      final meal = await _askMeal(r.name, day);
      if (meal == null || !mounted) return;
      final p = s.planMeal(day, meal, 'recipe', recipeId, 1);
      _undo('Added ${r.name} to ${meal.label.toLowerCase()} on ${_dayName(day)}.', () => s.removePlannedMeal(p));
      return;
    }
    final name = s.workoutById(d.workoutId ?? '')?.name ?? 'Workout';
    final moving = d.planned;
    if (moving != null) {
      if (_sameDay(moving.date, day)) return;
      final before = moving;
      s.movePlanned(moving, day);
      _undo('Moved $name to ${_dayName(day)}.', () => s.restorePlanned(before));
    } else if (d.workoutId != null) {
      final added = s.schedule(d.workoutId!, day);
      _undo('Added $name on ${_dayName(day)}.', () => s.removePlanned(added));
    }
  }

  void _tapDay(AppState s, DateTime day) {
    final p = _picked;
    if (p != null) {
      setState(() => _picked = null);
      _place(s, p, day);
      return;
    }
    setState(() {
      _day = _sameDay(day, _today) ? null : day;
      _view = _View.day;
    });
  }

  Future<void> _plannedMenu(AppState s, PlannedWorkout p) async {
    final c = AppColors.of(context);
    final w = s.workoutById(p.workoutId);
    final isToday = _sameDay(p.date, _today);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(w?.name ?? 'Workout', style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('Planned for ${longDate(p.date)}. Hold and drag it to move.'),
            ),
            if (isToday && w != null)
              ListTile(
                leading: Icon(Icons.play_arrow_rounded, color: c.accent),
                title: const Text('Start it now'),
                onTap: () => Navigator.of(sheet).pop('start'),
              ),
            ListTile(
              leading: Icon(Icons.event_rounded, color: c.muted),
              title: const Text('Move to another day'),
              onTap: () => Navigator.of(sheet).pop('move'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: c.protein),
              title: const Text('Remove from the calendar'),
              onTap: () => Navigator.of(sheet).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'start':
        startOrResume(context, w);
      case 'move':
        final picked = await showDatePicker(
          context: context,
          initialDate: p.date,
          firstDate: DateTime(_today.year - 1),
          lastDate: DateTime(_today.year + 2),
          helpText: 'Move to',
        );
        if (picked != null && mounted) _place(s, _Drag.move(p), dateOnly(picked));
      case 'remove':
        s.removePlanned(p);
        _undo('Removed ${w?.name ?? 'the workout'}.', () => s.restorePlanned(p));
    }
  }

  Future<void> _mealMenu(AppState s, PlannedMeal p) async {
    final c = AppColors.of(context);
    final logged = s.isPlannedLogged(p);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s.plannedName(p), style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('${p.meal.label} · ${longDate(p.date)}'),
            ),
            if (!logged)
              ListTile(
                leading: Icon(Icons.check_circle_outline_rounded, color: c.accent),
                title: const Text('Log it as eaten'),
                onTap: () => Navigator.of(sheet).pop('log'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: c.protein),
              title: const Text('Remove from the plan'),
              onTap: () => Navigator.of(sheet).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'log') {
      final e = s.logPlanned(p);
      if (e != null) _undo('Logged ${s.plannedName(p)}.', () => s.deleteEntry(e));
    } else if (choice == 'remove') {
      s.removePlannedMeal(p);
      _undo('Removed ${s.plannedName(p)}.', () => s.savePlannedMeal(p));
    }
  }

  Future<void> _weighDialog(AppState s, DateTime day) async {
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    final existing = s.weighInOn(day);
    final ctrl = TextEditingController(
      text: existing == null ? '' : oneDecimal(imperial ? kgToLb(existing.weightKg) : existing.weightKg),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Weigh-in, ${_dayName(day)}'),
        content: NumberBox(controller: ctrl, suffix: unit, semanticLabel: 'Weight in $unit', onChanged: (_) {}),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.of(dialog).pop('delete'),
              style: TextButton.styleFrom(foregroundColor: c.protein),
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop('save'),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = ctrl.text;
    // The dialog's closing animation still shows the field; dispose after it.
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
    if (!mounted || result == null) return;
    if (result == 'delete') {
      s.deleteWeighIn(day);
      return;
    }
    final v = parseNumber(text);
    if (v == null) return;
    final kg = imperial ? lbToKg(v) : v;
    if (kg < 30 || kg > 350) return;
    s.logWeight(kg, day: day);
  }

  // ---------------------------------------------------------------- pieces

  Widget _addButtons(AppColors c) {
    Widget b(String key, String label) {
      final on = _tray == key;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            onTap: () => setState(() {
              _tray = on ? '' : key;
              _picked = null;
            }),
            child: ExcludeSemantics(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                height: 44,
                decoration: BoxDecoration(
                  color: on ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.accent, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: on ? c.onAccent : c.accent),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: on ? c.onAccent : c.accent)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [b('w', 'Add workouts'), const SizedBox(width: 8), b('m', 'Add meals')]);
  }

  Widget _chip(AppColors c, String label, _Drag d) {
    final on = d.same(_picked);
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? c.accent : c.background,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: on ? c.accent : c.line, width: 1.5),
      ),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? c.onAccent : c.text)),
    );
    return LongPressDraggable<_Drag>(
      data: d,
      delay: const Duration(milliseconds: 150),
      hapticFeedbackOnStart: true,
      feedback: Material(color: Colors.transparent, child: chip),
      childWhenDragging: Opacity(opacity: 0.4, child: chip),
      child: Semantics(
        button: true,
        selected: on,
        label: on ? '$label, picked. Tap a day to add it.' : label,
        child: GestureDetector(
          onTap: () => setState(() => _picked = on ? null : d),
          child: ExcludeSemantics(child: chip),
        ),
      ),
    );
  }

  Widget _trayPanel(AppState s, AppColors c) {
    final workouts = _tray == 'w';
    final chips = <Widget>[
      if (workouts)
        for (final w in s.workouts) _chip(c, w.name, _Drag.workout(w.id))
      else
        for (final r in s.recipes) _chip(c, r.name, _Drag.recipe(r.id)),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            chips.isEmpty
                ? (workouts
                    ? 'No workouts yet. Make one in Plan > Workouts.'
                    : 'No recipes yet. Make one in Food > Recipes.')
                : 'Hold and drag one onto a day, or tap it and then tap a day.',
            style: AppText.quiet(c).copyWith(fontSize: 12),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
        ],
      ),
    );
  }

  Widget _navRow(AppColors c, String title, String prevLabel, String nextLabel, VoidCallback prev, VoidCallback next,
      {VoidCallback? today}) {
    return Row(
      children: [
        IconButton(tooltip: prevLabel, onPressed: prev, icon: Icon(Icons.chevron_left_rounded, color: c.text)),
        Expanded(
          child: Text(title, textAlign: TextAlign.center, style: AppText.body(c).copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        if (today != null)
          TextButton(
            onPressed: today,
            style: TextButton.styleFrom(foregroundColor: c.accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Today'),
          ),
        IconButton(tooltip: nextLabel, onPressed: next, icon: Icon(Icons.chevron_right_rounded, color: c.text)),
      ],
    );
  }

  /// Swipe left or right to page.
  Widget _swipe({required Widget child, required VoidCallback prev, required VoidCallback next}) {
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -250) next();
        if (v > 250) prev();
      },
      child: child,
    );
  }

  Widget _dropTarget(AppState s, AppColors c, DateTime day, Widget Function(bool hover) builder) {
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _place(s, d.data, day),
      builder: (context, candidates, _) => builder(candidates.isNotEmpty),
    );
  }

  Widget _labels(AppState s, AppColors c, DateTime day) {
    final phase = s.phaseOn(day);
    final meso = s.mesoOn(day);
    final wk = meso?.weekOn(day);
    final parts = [
      if (phase != null)
        'Phase: ${switch (phase.mode) {
          GoalMode.lose => 'Cut',
          GoalMode.gain => 'Lean bulk',
          GoalMode.maintain => 'Maintain',
        }}${phase.end == null ? '' : ' until ${shortDate(phase.end!)}'}',
      if (meso != null)
        '${meso.name}${wk == null ? '' : (meso.isDeloadWeek(wk) ? ', deload week' : ', week $wk of ${meso.weeks}')}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(parts.join(' · '), style: AppText.quiet(c).copyWith(color: c.accent, fontWeight: FontWeight.w600)),
    );
  }

  // ---------------------------------------------------------------- month

  Widget _monthView(AppState s, AppColors c) {
    final first = _month;
    final lead = _sunFirst ? first.weekday % 7 : first.weekday - 1;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final rows = ((lead + days) / 7).ceil();
    final start = DateTime(first.year, first.month, 1 - lead);
    final today = _today;
    final isThisMonth = first.year == today.year && first.month == today.month;
    void prev() => setState(() => _month = DateTime(first.year, first.month - 1, 1));
    void next() => setState(() => _month = DateTime(first.year, first.month + 1, 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navRow(c, '${_monthNames[first.month - 1]} ${first.year}', 'Previous month', 'Next month', prev, next,
            today: isThisMonth ? null : () => setState(() => _month = DateTime(today.year, today.month, 1))),
        _labels(s, c, isThisMonth ? today : first),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final w in weekdayOrder(sundayFirst: _sunFirst))
              Expanded(child: Text(_dows[w - 1], textAlign: TextAlign.center, style: AppText.quiet(c).copyWith(fontSize: 11))),
          ],
        ),
        const SizedBox(height: 4),
        _swipe(
          prev: prev,
          next: next,
          child: Column(
            children: [
              for (var r = 0; r < rows; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                            child: _monthCell(s, c, DateTime(start.year, start.month, start.day + r * 7 + i), first.month),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(c, Container(width: 14, height: 8, decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(3))), 'Workout'),
            _legend(c, Container(width: 7, height: 7, decoration: BoxDecoration(color: c.ringA, shape: BoxShape.circle)), 'Meal'),
            Text('Tap a day for details', style: AppText.quiet(c).copyWith(fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        _weightLegend(c),
      ],
    );
  }

  /// A weight as shown on the calendar: plain for a weigh-in, coloured and
  /// italic for a projection (so it doesn't rely on colour alone).
  TextStyle _weightStyle(AppColors c, bool projected, double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        fontStyle: projected ? FontStyle.italic : FontStyle.normal,
        color: projected ? c.ringB : c.muted,
      );

  String? _weightLabel(AppState s, DateTime d, {bool unit = false}) {
    final w = s.calendarWeightOn(d);
    if (w == null) return null;
    final imperial = s.settings.units == Units.imperial;
    return '${oneDecimal(imperial ? kgToLb(w.kg) : w.kg)}${unit ? (imperial ? ' lb' : ' kg') : ''}';
  }

  Widget _weightLegend(AppColors c) => Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          _legend(c, Text('180', style: _weightStyle(c, false, 10)), 'Weigh-in'),
          _legend(c, Text('178', style: _weightStyle(c, true, 10)), 'Projected weight (at your calorie target)'),
        ],
      );

  Widget _legend(AppColors c, Widget mark, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [mark, const SizedBox(width: 5), Text(label, style: AppText.quiet(c).copyWith(fontSize: 11))],
      );

  Widget _monthCell(AppState s, AppColors c, DateTime d, int month) {
    final inMonth = d.month == month;
    final today = _sameDay(d, _today);
    final planned = s.plannedOn(d);
    final done = s.finishedOn(d);
    final meals = s.plannedMealsOn(d);
    final names = [
      for (final p in planned)
        if (!s.plannedDone(p)) s.workoutById(p.workoutId)?.name ?? 'Workout',
    ];
    final label = names.isNotEmpty ? names.join(' + ') : (done.isNotEmpty ? '✓ ${done.last.name}' : null);
    final weight = _weightLabel(s, d);
    final projected = s.calendarWeightOn(d)?.projected ?? false;
    return _dropTarget(s, c, d, (hover) {
      return Semantics(
        button: true,
        label: '${_dowsLong[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}'
            '${label == null ? ', nothing planned' : ', $label'}${meals.isEmpty ? '' : ', ${meals.length} meals'}'
            '${weight == null ? '' : ', ${projected ? 'projected weight' : 'weight'} $weight'}',
        child: GestureDetector(
          onTap: () => _tapDay(s, d),
          child: ExcludeSemantics(
            child: Opacity(
              opacity: inMonth ? 1 : 0.4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: 60,
                padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
                decoration: BoxDecoration(
                  color: today ? c.accent.withAlpha(36) : c.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hover || (_picked != null && inMonth) ? c.accent : (today ? c.accent : Colors.transparent),
                    width: hover ? 2 : 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Row(
                        children: [
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                              color: today ? c.accent : c.text,
                            ),
                          ),
                          if (weight != null) ...[
                            const SizedBox(width: 2),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(weight, style: _weightStyle(c, projected, 8.5)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (label != null)
                      Container(
                        height: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: names.isNotEmpty ? c.accent : c.chip,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                            color: names.isNotEmpty ? c.onAccent : c.muted,
                          ),
                        ),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        for (var i = 0; i < meals.length && i < 4; i++)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(color: c.ringA, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  // ---------------------------------------------------------------- week

  Widget _weekView(AppState s, AppColors c) {
    final mon = _week;
    final sun = DateTime(mon.year, mon.month, mon.day + 6);
    final today = _today;
    final isThisWeek = _sameDay(mon, _startOf(today));
    void prev() => setState(() => _week = DateTime(mon.year, mon.month, mon.day - 7));
    void next() => setState(() => _week = DateTime(mon.year, mon.month, mon.day + 7));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navRow(c, '${shortDate(mon)} – ${shortDate(sun)}', 'Previous week', 'Next week', prev, next,
            today: isThisWeek ? null : () => setState(() => _week = _startOf(today))),
        _labels(s, c, isThisWeek ? today : mon),
        const SizedBox(height: 8),
        _swipe(
          prev: prev,
          next: next,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                      child: _weekColumn(s, c, DateTime(mon.year, mon.month, mon.day + i)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _weightLegend(c),
        const SizedBox(height: 4),
        Row(
          children: [
            TextButton(
              onPressed: () {
                final w = s.copyPreviousWeek(mon);
                final m = s.copyPreviousMealWeek(mon);
                if (w.isEmpty && m.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nothing new to copy from last week.')),
                  );
                  return;
                }
                _undo('Copied ${w.length} workouts and ${m.length} meals from last week.', () {
                  for (final p in w) {
                    s.removePlanned(p);
                  }
                  for (final p in m) {
                    s.removePlannedMeal(p);
                  }
                });
              },
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: const Text('Copy last week'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _weekColumn(AppState s, AppColors c, DateTime d) {
    final today = _sameDay(d, _today);
    final planned = s.plannedOn(d);
    final done = s.finishedOn(d);
    final meals = s.plannedMealsOn(d)..sort((a, b) => a.meal.index.compareTo(b.meal.index));
    Widget item(String text, Color bg, Color fg) => Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, height: 1.25, fontWeight: FontWeight.w600, color: fg),
          ),
        );
    return _dropTarget(s, c, d, (hover) {
      return GestureDetector(
        onTap: () => _tapDay(s, d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 300),
          padding: const EdgeInsets.fromLTRB(3, 6, 3, 6),
          decoration: BoxDecoration(
            color: today ? c.accent.withAlpha(36) : c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hover || _picked != null ? c.accent : (today ? c.accent : Colors.transparent),
              width: hover ? 2 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: '${_dowsLong[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}',
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      Text(_dows[d.weekday - 1], style: AppText.quiet(c).copyWith(fontSize: 11)),
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                          color: today ? c.accent : c.text,
                        ),
                      ),
                      if (_weightLabel(s, d) case final String w)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(w, style: _weightStyle(c, s.calendarWeightOn(d)!.projected, 9.5)),
                        ),
                    ],
                  ),
                ),
              ),
              for (final p in planned)
                if (!s.plannedDone(p))
                  LongPressDraggable<_Drag>(
                    data: _Drag.move(p),
                    hapticFeedbackOnStart: true,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: 60,
                        child: item(s.workoutById(p.workoutId)?.name ?? 'Workout', c.accent, c.onAccent),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: item(s.workoutById(p.workoutId)?.name ?? 'Workout', c.accent, c.onAccent),
                    ),
                    child: GestureDetector(
                      onTap: () => _plannedMenu(s, p),
                      child: item(s.workoutById(p.workoutId)?.name ?? 'Workout', c.accent, c.onAccent),
                    ),
                  ),
              for (final x in done) item('✓ ${x.name}', c.chip, c.muted),
              for (final m in meals)
                GestureDetector(
                  onTap: () => _mealMenu(s, m),
                  child: item(s.plannedName(m), c.ringA.withAlpha(60), c.text),
                ),
            ],
          ),
        ),
      );
    });
  }

  // ---------------------------------------------------------------- day

  Widget _dayView(AppState s, AppColors c) {
    final today = _today;
    final d = _day ?? today;
    final isToday = _sameDay(d, today);
    final planned = s.plannedOn(d);
    final done = s.finishedOn(d);
    final meals = s.plannedMealsOn(d);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    final weigh = s.weighInOn(d);
    var kcal = 0.0;
    for (final m in meals) {
      kcal += s.plannedMacros(m).kcal;
    }
    final t = s.targets;
    void shift(int n) => setState(() {
          final next = DateTime(d.year, d.month, d.day + n);
          _day = _sameDay(next, today) ? null : next;
        });

    Widget card(IconData icon, String title, String? aside, List<Widget> children) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: c.accent),
                  const SizedBox(width: 8),
                  Text(title, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                  const Spacer(),
                  if (aside != null) Text(aside, style: AppText.quiet(c).copyWith(fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              ...children,
            ],
          ),
        );
    Widget line(Widget child) => Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: child,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _navRow(
          c,
          isToday ? 'Today, ${shortDate(d)}' : '${_dowsLong[d.weekday - 1]}, ${shortDate(d)}',
          'Previous day',
          'Next day',
          () => shift(-1),
          () => shift(1),
          today: isToday ? null : () => setState(() => _day = null),
        ),
        _labels(s, c, d),
        _dropTarget(s, c, d, (hover) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: hover ? c.accent : Colors.transparent, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_picked != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SmallButton(label: 'Add it to this day', onTap: () => _tapDay(s, d)),
                  ),
                card(Icons.fitness_center_rounded, 'Workouts', null, [
                  for (final p in planned)
                    if (!s.plannedDone(p))
                      line(Row(
                        children: [
                          Expanded(
                            child: Text(s.workoutById(p.workoutId)?.name ?? 'Workout',
                                style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                          ),
                          if (isToday && s.workoutById(p.workoutId) != null)
                            SmallButton(label: 'Start', onTap: () => startOrResume(context, s.workoutById(p.workoutId))),
                          IconButton(
                            tooltip: 'More',
                            onPressed: () => _plannedMenu(s, p),
                            icon: Icon(Icons.more_horiz_rounded, color: c.muted),
                          ),
                        ],
                      )),
                  for (final x in done)
                    line(GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).push(SessionDetailScreen.route(x.id)),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 18, color: c.accent),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${x.name}, done', style: AppText.body(c))),
                          Icon(Icons.chevron_right_rounded, color: c.muted),
                        ],
                      ),
                    )),
                  if (planned.isEmpty && done.isEmpty)
                    line(Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Rest day. Use Add workouts to plan one.', style: AppText.quiet(c)),
                    )),
                ]),
                card(Icons.restaurant_rounded, 'Meals',
                    meals.isEmpty ? null : (t == null ? '${kcal.round()} kcal planned' : '${kcal.round()} of ${thousands(t.kcal)} kcal'), [
                  for (final meal in Meal.values)
                    line(Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(width: 76, child: Text(meal.label, style: AppText.quiet(c).copyWith(fontSize: 12))),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final m in meals)
                                if (m.meal == meal)
                                  GestureDetector(
                                    onTap: () => _mealMenu(s, m),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: s.isPlannedLogged(m) ? c.accent.withAlpha(36) : c.chip,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${s.isPlannedLogged(m) ? '✓ ' : ''}${s.plannedName(m)}',
                                        style: AppText.body(c).copyWith(fontSize: 13),
                                      ),
                                    ),
                                  ),
                              if (!meals.any((m) => m.meal == meal))
                                Text('Nothing planned', style: AppText.quiet(c).copyWith(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    )),
                ]),
                card(Icons.monitor_weight_outlined, 'Weigh-in', null, [
                  line(Row(
                    children: [
                      Expanded(
                        child: weigh == null && s.projectedWeightOn(d) != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Projected ${_weightLabel(s, d, unit: true)}',
                                      style: _weightStyle(c, true, 15)),
                                  Text('If you keep to your calorie target', style: AppText.quiet(c).copyWith(fontSize: 12)),
                                ],
                              )
                            : Text(
                                weigh == null
                                    ? 'No weigh-in'
                                    : '${oneDecimal(imperial ? kgToLb(weigh.weightKg) : weigh.weightKg)} $unit',
                                style: weigh == null ? AppText.quiet(c) : AppText.body(c),
                              ),
                      ),
                      SmallButton(label: weigh == null ? 'Add' : 'Edit', quiet: true, onTap: () => _weighDialog(s, d)),
                    ],
                  )),
                ]),
              ],
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _addButtons(c),
        if (_tray.isNotEmpty) _trayPanel(s, c),
        const SizedBox(height: 12),
        IconTabs(
          label: 'Calendar view',
          compact: true,
          items: const [
            (Icons.calendar_view_month_rounded, 'Month'),
            (Icons.view_week_outlined, 'Week'),
            (Icons.today_outlined, 'Today'),
          ],
          index: _view.index,
          onChanged: (i) => setState(() {
            _view = _View.values[i];
            if (_view == _View.day) _day = null;
          }),
        ),
        const SizedBox(height: 8),
        switch (_view) {
          _View.month => _monthView(s, c),
          _View.week => _weekView(s, c),
          _View.day => _dayView(s, c),
        },
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(WorkoutHistoryScreen.route()),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Workout history'),
          ),
        ),
      ],
    );
  }
}
