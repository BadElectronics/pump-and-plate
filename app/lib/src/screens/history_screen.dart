import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'logger_screen.dart';

/// Every finished workout, newest first.
class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const WorkoutHistoryScreen());

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final all = s.finishedSessions.reversed.toList();
    final names = <String>[];
    for (final x in all) {
      if (!names.contains(x.name)) names.add(x.name);
    }
    final shown = [
      for (final x in all)
        if (_filter == null || x.name == _filter) x,
    ];

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  Text('Workout history', style: AppText.title(c).copyWith(fontSize: 22)),
                ],
              ),
            ),
            if (names.length > 1)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                  children: [
                    for (final n in <String?>[null, ...names])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _filter = n),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: n == _filter ? c.text : c.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: c.line),
                            ),
                            child: Text(
                              n ?? 'All',
                              style: TextStyle(fontSize: 14, color: n == _filter ? c.background : c.text),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: shown.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Finished workouts appear here.',
                        textAlign: TextAlign.center,
                        style: AppText.quiet(c),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final x = shown[i];
                        final mins = x.endedAt == null
                            ? null
                            : x.endedAt!.difference(x.startedAt).inMinutes;
                        final working = x.sets.where((e) => !e.warmup).length;
                        return Material(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.of(context).push(SessionDetailScreen.route(x.id)),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 58,
                                    child: Text(shortDate(x.date), style: AppText.quiet(c)),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          x.name,
                                          style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
                                        ),
                                        Text(
                                          '$working sets'
                                          '${mins == null || mins <= 0 ? '' : ' · $mins min'}',
                                          style: AppText.quiet(c).copyWith(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: c.muted),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One finished workout: every set, plus edit, change date and delete.
class SessionDetailScreen extends StatelessWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  static Route<void> route(String id) =>
      MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: id));

  Future<void> _changeDate(BuildContext context, AppState s, Session x) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: x.date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Workout date',
    );
    if (picked != null) s.updateSession(x.copyWith(date: dateOnly(picked)));
  }

  Future<void> _delete(BuildContext context, AppState s, Session x) async {
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Delete this workout?'),
        content: const Text('It\'s removed from your history, records and charts.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.protein),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    s.discardSession(x);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    Session? x;
    for (final y in s.sessions) {
      if (y.id == sessionId) x = y;
    }
    if (x == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(child: Text('This workout was deleted.', style: AppText.body(c))),
      );
    }
    final session = x;
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    String w(double kg) => oneDecimal(imperial ? kgToLb(kg) : kg);

    final order = <String>[];
    for (final set in session.sets) {
      if (!order.contains(set.exerciseId)) order.add(set.exerciseId);
    }
    final mins = session.endedAt == null
        ? null
        : session.endedAt!.difference(session.startedAt).inMinutes;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_rounded, color: c.text),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.name, style: AppText.title(c).copyWith(fontSize: 24)),
                      Text(
                        '${longDate(session.date)}${mins == null || mins <= 0 ? '' : ' · $mins min'}',
                        style: AppText.quiet(c),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final id in order) ...[
                    SectionCard(
                      title: s.exerciseName(id),
                      child: Column(
                        children: [
                          if (session.exerciseNotes[id] case final String note)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.sticky_note_2_outlined, size: 16, color: c.accent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      note,
                                      style: AppText.body(c).copyWith(fontSize: 14, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final set in session.sets)
                            if (set.exerciseId == id)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      // W, D, F, P, RP, A, M: the same tags as in a workout.
                                      child: Text(
                                        set.type.short,
                                        style: TextStyle(color: set.warmup ? c.protein : c.accent, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        s.isCardio(id)
                                            ? _cardioText(set, imperial)
                                            : '${set.weightKg == null ? (s.exercise(id)?.bodyweight == true ? 'BW' : '–') : '${w(set.weightKg!)} $unit'}'
                                                ' × ${set.reps ?? '–'}',
                                        style: AppText.body(c),
                                      ),
                                    ),
                                    if (set.restSec != null)
                                      Text(
                                        'rest ${set.restSec! ~/ 60}:${(set.restSec! % 60).toString().padLeft(2, '0')}',
                                        style: AppText.quiet(c).copyWith(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (session.note != null) ...[
                    SectionCard(
                      title: 'Note',
                      child: Text(session.note!, style: AppText.body(c)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  SmallButton(
                    label: 'Edit sets',
                    onTap: () => Navigator.of(context).push(LoggerScreen.route(session.id)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SmallButton(
                          label: 'Change date',
                          quiet: true,
                          onTap: () => _changeDate(context, s, session),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SmallButton(
                          label: 'Delete',
                          quiet: true,
                          onTap: () => _delete(context, s, session),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cardioText(SetEntry set, bool imperial) {
  final parts = <String>[];
  if (set.durationSec != null) parts.add(clockText(set.durationSec!));
  final km = set.distanceKm;
  if (km != null) {
    parts.add('${(imperial ? kmToMi(km) : km).toStringAsFixed(2)} ${imperial ? 'mi' : 'km'}');
  }
  if (set.heartRate != null) parts.add('${set.heartRate} bpm');
  if (set.calories != null) parts.add('${set.calories} kcal');
  return parts.isEmpty ? 'Logged' : parts.join(' · ');
}
