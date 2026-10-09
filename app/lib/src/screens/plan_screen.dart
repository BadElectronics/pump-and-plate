import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'calendar_view.dart';
import 'exercise_library_screen.dart';
import 'goals_screen.dart';
import 'history_screen.dart';
import 'logger_screen.dart';
import 'meso_screens.dart';
import 'workout_editor_screen.dart';

/// Plan tab: Calendar, Workouts and Goals.
class PlanScreen extends StatelessWidget {
  const PlanScreen({
    super.key,
    required this.section,
    required this.onSection,
    this.mealsTick = 0,
  });

  final int section;
  final ValueChanged<int> onSection;

  /// When this changes, the calendar opens its Add meals tray.
  final int mealsTick;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Plan', style: AppText.title(c)),
                ),
                const SizedBox(height: 12),
                IconTabs(
                  label: 'Plan section',
                  items: const [
                    (Icons.calendar_month_rounded, 'Calendar'),
                    (Icons.fitness_center_rounded, 'Workouts'),
                    (Icons.track_changes_rounded, 'Goals'),
                  ],
                  index: section,
                  onChanged: onSection,
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (section) {
              0 => CalendarView(mealsTick: mealsTick),
              1 => const WorkoutsView(),
              _ => const GoalsScreen(embedded: true),
            },
          ),
        ],
      ),
    );
  }
}

/// Opens the logger for [w], or resumes the workout already in progress.
void startOrResume(BuildContext context, Workout? w) {
  final s = AppScope.of(context);
  final active = s.activeSession;
  if (active != null) {
    Navigator.of(context).push(LoggerScreen.route(active.id));
    return;
  }
  final x = s.startSession(w);
  Navigator.of(context).push(LoggerScreen.route(x.id));
}

class WorkoutsView extends StatefulWidget {
  const WorkoutsView({super.key});

  @override
  State<WorkoutsView> createState() => _WorkoutsViewState();
}

class _WorkoutsViewState extends State<WorkoutsView> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final active = s.activeSession;

    final header = <Widget>[
      const MesoCard(),
      if (active != null) ...[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.text, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${active.name} is in progress',
                  style: TextStyle(color: c.background, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              SmallButton(label: 'Resume', onTap: () => startOrResume(context, null)),
            ],
          ),
        ),
        const SizedBox(height: 14),
      ],
      Row(
        children: [
          Expanded(
            child: SmallButton(
              label: 'New workout',
              onTap: () => Navigator.of(context).push(WorkoutEditorScreen.route()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SmallButton(
              label: 'Exercises',
              quiet: true,
              onTap: () => Navigator.of(context).push(ExerciseLibraryScreen.route()),
            ),
          ),
        ],
      ),
      if (s.finishedSessions.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push(WorkoutHistoryScreen.route()),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: Text('Workout history (${s.finishedSessions.length})'),
          ),
        ),
      const SizedBox(height: 10),
    ];

    if (s.workouts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          ...header,
          SectionCard(
            title: 'No workouts yet',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Build your own, or start from a 4-day upper/lower split '
                  '(Upper A, Lower A, Upper B, Lower B) and change anything.',
                  style: AppText.body(c),
                ),
                const SizedBox(height: 14),
                SmallButton(label: 'Add the upper/lower plan', quiet: true, onTap: s.addStarterPlan),
                const SizedBox(height: 8),
                SmallButton(
                  label: 'Start an empty workout',
                  quiet: true,
                  onTap: () => startOrResume(context, null),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ReorderableListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      buildDefaultDragHandles: false,
      header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: header),
      footer: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: TextButton(
          onPressed: () => startOrResume(context, null),
          style: TextButton.styleFrom(foregroundColor: c.accent),
          child: const Text('Start an empty workout'),
        ),
      ),
      onReorder: s.reorderWorkouts,
      children: [
        for (var i = 0; i < s.workouts.length; i++)
          Padding(
            key: ValueKey(s.workouts[i].id),
            padding: const EdgeInsets.only(bottom: 10),
            child: _WorkoutCard(
              index: i,
              workout: s.workouts[i],
              open: _open == s.workouts[i].id,
              imperial: imperial,
              onToggle: () => setState(
                () => _open = _open == s.workouts[i].id ? null : s.workouts[i].id,
              ),
            ),
          ),
      ],
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.index,
    required this.workout,
    required this.open,
    required this.imperial,
    required this.onToggle,
  });

  final int index;
  final Workout workout;
  final bool open;
  final bool imperial;
  final VoidCallback onToggle;

  Widget _row(AppState s, AppColors c, WorkoutItem item, {bool first = false, bool grouped = false}) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: grouped ? 0 : 18),
      padding: EdgeInsets.symmetric(vertical: 10, horizontal: grouped ? 12 : 0),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(s.exerciseName(item.exerciseId), style: AppText.body(c))),
          Text(
            s.isCardio(item.exerciseId)
                ? (item.targetMin == null ? 'Cardio' : '${item.targetMin} min')
                : '${item.sets} × ${repsText(item)}'
                    '${item.loadKg == null ? '' : '  ${oneDecimal(imperial ? kgToLb(item.loadKg!) : item.loadKg!)} ${imperial ? 'lb' : 'kg'}'}',
            style: AppText.quiet(c),
          ),
        ],
      ),
    );
  }

  /// Exercise rows, with each superset drawn as one outlined group.
  List<Widget> _itemRows(AppState s, AppColors c, Workout w) {
    final spans = AppState.supersetSpans(w.items);
    final out = <Widget>[];
    var i = 0;
    while (i < w.items.length) {
      final span = spans[i];
      if (span == null) {
        out.add(_row(s, c, w.items[i]));
        i++;
        continue;
      }
      final (start, end) = span;
      out.add(Container(
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.accent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 16, color: c.onAccent),
                  const SizedBox(width: 6),
                  Text(
                    end - start + 1 > 2 ? 'Superset of ${end - start + 1}' : 'Superset',
                    style: TextStyle(color: c.onAccent, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            for (var k = start; k <= end; k++)
              _row(s, c, w.items[k], first: k == start, grouped: true),
          ],
        ),
      ));
      i = end + 1;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final w = workout;
    final minutes = s.minutesFor(w.items);

    return Container(
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(Icons.drag_indicator_rounded, color: c.muted),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          w.name,
                          style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          '${w.items.length} exercises · about $minutes min',
                          style: AppText.quiet(c).copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            ..._itemRows(s, c, w),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SmallButton(
                      label: 'Edit',
                      quiet: true,
                      onTap: () => Navigator.of(context).push(WorkoutEditorScreen.route(w)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SmallButton(label: 'Start', onTap: () => startOrResume(context, w)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
