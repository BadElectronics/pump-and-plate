import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Weekdays to spread [n] workouts over (1 = Monday).
List<int> defaultDays(int n) => switch (n) {
      0 => const [],
      1 => const [1],
      2 => const [1, 4],
      3 => const [1, 3, 5],
      4 => const [1, 2, 4, 5],
      5 => const [1, 2, 3, 5, 6],
      6 => const [1, 2, 3, 4, 5, 6],
      _ => const [1, 2, 3, 4, 5, 6, 7],
    };

/// 2.5 -> "2.5", 5.0 -> "5".
String _num(double v) =>
    v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

Future<bool> _confirm(BuildContext context, String title, String body, String action) async {
  final c = AppColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          style: TextButton.styleFrom(foregroundColor: c.protein),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The block at the top of Plan > Workouts.
class MesoCard extends StatelessWidget {
  const MesoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final today = dateOnly(DateTime.now());
    final active = s.activeMeso;
    final upcoming = s.upcomingMeso;
    final past = s.pastMesos;

    if (active == null && upcoming == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SmallButton(
            label: past.isEmpty ? 'Start a mesocycle' : 'Start the next block',
            quiet: true,
            onTap: () => Navigator.of(context).push(
              MesoEditorScreen.route(past.isEmpty ? null : past.first),
            ),
          ),
          if (past.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MesoSummaryScreen.route(past.first.id)),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: Text('${past.first.name} summary'),
              ),
            ),
          const SizedBox(height: 10),
        ],
      );
    }

    final m = (active ?? upcoming)!;
    final week = m.weekOn(today);
    final total = m.totalWeeks * 7;
    final done = daysBetween(m.start, today).clamp(0, total);
    final title = week == null
        ? 'Starts ${shortDate(m.start)}'
        : (m.isDeloadWeek(week) ? 'Deload week' : 'Week $week of ${m.weeks}');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, color: c.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.name,
                  style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Text(title, style: AppText.body(c).copyWith(color: c.accent, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              color: c.accent,
              backgroundColor: c.chip,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            week == null
                ? '${m.progression.label} progression · ${m.weeks} weeks'
                    '${m.deload ? ' + deload' : ''} · ends ${shortDate(m.lastDay)}'
                : s.mesoInstruction(m, week),
            style: AppText.quiet(c),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).push(MesoSummaryScreen.route(m.id)),
                style: TextButton.styleFrom(foregroundColor: c.accent),
                child: Text(week == null ? 'Details' : 'Progress so far'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  final ok = await _confirm(
                    context,
                    week == null ? 'Cancel ${m.name}?' : 'End ${m.name} now?',
                    week == null
                        ? 'Its workouts are removed from your calendar.'
                        : 'Workouts already logged stay. Its remaining calendar slots are removed.',
                    week == null ? 'Cancel block' : 'End block',
                  );
                  if (ok) s.endMeso(m);
                },
                style: TextButton.styleFrom(foregroundColor: c.protein),
                child: Text(week == null ? 'Cancel' : 'End early'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Set up a block. With [prefill], starts from a previous block's setup.
class MesoEditorScreen extends StatefulWidget {
  const MesoEditorScreen({super.key, this.prefill});

  final Mesocycle? prefill;

  static Route<void> route([Mesocycle? prefill]) =>
      MaterialPageRoute<void>(builder: (_) => MesoEditorScreen(prefill: prefill));

  @override
  State<MesoEditorScreen> createState() => _MesoEditorScreenState();
}

class _MesoEditorScreenState extends State<MesoEditorScreen> {
  final _name = TextEditingController();
  late DateTime _start;
  int _weeks = 4;
  bool _deload = true;
  MesoProgression _progression = MesoProgression.weight;
  double? _stepShown;
  final Map<int, String> _schedule = {};
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final s = AppScope.of(context);
    final today = dateOnly(DateTime.now());
    final p = widget.prefill;
    // Next Monday (today if it's Monday), or the Monday after the last block.
    var start = DateTime(today.year, today.month, today.day + (8 - today.weekday) % 7);
    if (p != null) {
      final after = DateTime(p.endDay.year, p.endDay.month, p.endDay.day + 1);
      final monday = DateTime(after.year, after.month, after.day + (8 - after.weekday) % 7);
      if (monday.isAfter(start)) start = monday;
    }
    _start = start;
    _name.text = 'Block ${s.mesocycles.length + 1}';
    if (p != null) {
      _weeks = p.weeks;
      _deload = p.deload;
      _progression = p.progression;
      final imperial = s.settings.units == Units.imperial;
      _stepShown = double.parse((imperial ? kgToLb(p.weightStepKg) : p.weightStepKg).toStringAsFixed(2));
      for (final e in p.schedule.entries) {
        if (s.workoutById(e.value) != null) _schedule[e.key] = e.value;
      }
    } else {
      final days = defaultDays(s.workouts.length);
      for (var i = 0; i < days.length && i < s.workouts.length; i++) {
        _schedule[days[i]] = s.workouts[i].id;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDay(AppState s, int weekday) async {
    final c = AppColors.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(_days[weekday - 1], style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: Icon(Icons.hotel_rounded, color: c.muted),
              title: const Text('Rest day'),
              onTap: () => Navigator.of(sheet).pop(''),
            ),
            for (final w in s.workouts)
              ListTile(
                leading: Icon(Icons.fitness_center_rounded, color: c.accent),
                title: Text(w.name),
                subtitle: Text('${w.items.length} exercises'),
                onTap: () => Navigator.of(sheet).pop(w.id),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() {
      if (choice.isEmpty) {
        _schedule.remove(weekday);
      } else {
        _schedule[weekday] = choice;
      }
    });
  }

  Future<void> _begin(AppState s) async {
    if (_schedule.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one workout day.')),
      );
      return;
    }
    final imperial = s.settings.units == Units.imperial;
    final step = _stepShown ?? (imperial ? 5.0 : 2.5);
    final m = Mesocycle(
      id: newId('m'),
      name: _name.text.trim().isEmpty ? 'Block' : _name.text.trim(),
      start: _start,
      weeks: _weeks,
      deload: _deload,
      progression: _progression,
      weightStepKg: imperial ? lbToKg(step) : step,
      schedule: Map.of(_schedule),
    );
    // Only one block at a time.
    final clash = s.activeMeso ?? s.upcomingMeso;
    if (clash != null && !m.start.isAfter(clash.endDay)) {
      final ok = await _confirm(
        context,
        'End ${clash.name} first?',
        'Only one block runs at a time. Ending ${clash.name} removes its remaining '
            'calendar slots; workouts already logged stay.',
        'End it and start',
      );
      if (!ok || !mounted) return;
      s.endMeso(clash);
    }
    final count = s.startMeso(m);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${m.name} starts ${shortDate(m.start)}: $count workouts are on your calendar.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    final steps = imperial ? const [2.5, 5.0, 10.0] : const [1.0, 2.5, 5.0];
    final step = _stepShown ?? steps[1];
    final perWeek = _schedule.length;
    final totalWeeks = _weeks + (_deload ? 1 : 0);
    final end = DateTime(_start.year, _start.month, _start.day + totalWeeks * 7 - 1);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 40),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.text),
                ),
                Expanded(child: Text('New mesocycle', style: AppText.title(c).copyWith(fontSize: 22))),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.workouts.isEmpty)
                    SectionCard(
                      title: 'Make workouts first',
                      child: Text(
                        'A mesocycle runs your workouts on a weekly schedule. Add some in '
                        'Plan > Workouts (or the upper/lower starter plan), then come back.',
                        style: AppText.body(c),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 8),
                    const FieldLabel('Name'),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        cursorColor: c.accent,
                        style: AppText.body(c).copyWith(fontSize: 16),
                        decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionCard(
                      title: 'Length',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SmallButton(
                            label: 'Starts ${shortDate(_start)}',
                            quiet: true,
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _start,
                                firstDate: DateTime(now.year, now.month, now.day - 7),
                                lastDate: DateTime(now.year + 1, now.month, now.day),
                                helpText: 'Week 1 starts',
                              );
                              if (picked != null) setState(() => _start = dateOnly(picked));
                            },
                          ),
                          const SizedBox(height: 12),
                          Text('Working weeks', style: AppText.body(c)),
                          const SizedBox(height: 6),
                          Segmented<int>(
                            label: 'Working weeks',
                            options: const [(3, '3'), (4, '4'), (5, '5'), (6, '6'), (7, '7'), (8, '8')],
                            value: _weeks,
                            onChanged: (v) => setState(() => _weeks = v),
                          ),
                          SettingRow(
                            label: 'Deload week at the end',
                            note: 'Half the sets, about 10% lighter, to recover',
                            trailing: Toggle(
                              label: 'Deload week at the end',
                              value: _deload,
                              onChanged: (v) => setState(() => _deload = v),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      title: 'Progression',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Segmented<MesoProgression>(
                            label: 'Progression',
                            options: [for (final p in MesoProgression.values) (p, p.label)],
                            value: _progression,
                            onChanged: (v) => setState(() => _progression = v),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            switch (_progression) {
                              MesoProgression.weight =>
                                'Same sets every week; weights go up by a set amount each week. '
                                    'Week 1 sets your starting weights.',
                              MesoProgression.sets =>
                                'Same weights; one more set per exercise each week (up to +4).',
                              MesoProgression.effort =>
                                'Same sets; push closer to failure each week, from about 3 reps '
                                    'in reserve in week 1 to 0 in the last week.',
                            },
                            style: AppText.quiet(c),
                          ),
                          if (_progression == MesoProgression.weight) ...[
                            const SizedBox(height: 12),
                            Text('Add each week', style: AppText.body(c)),
                            const SizedBox(height: 6),
                            Segmented<double>(
                              label: 'Weight added each week',
                              options: [for (final v in steps) (v, '${_num(v)} $unit')],
                              value: steps.contains(step) ? step : steps[1],
                              onChanged: (v) => setState(() => _stepShown = v),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SectionCard(
                      title: 'Weekly schedule',
                      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
                      child: Column(
                        children: [
                          for (final d in weekdayOrder(sundayFirst: s.settings.weekStartsSunday))
                            InkWell(
                              onTap: () => _pickDay(s, d),
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 48),
                                decoration: BoxDecoration(
                                  border: d == 1 ? null : Border(top: BorderSide(color: c.line)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(width: 104, child: Text(_days[d - 1], style: AppText.body(c))),
                                    Expanded(
                                      child: Text(
                                        _schedule[d] == null
                                            ? 'Rest'
                                            : (s.workoutById(_schedule[d]!)?.name ?? 'Workout'),
                                        style: _schedule[d] == null
                                            ? AppText.quiet(c)
                                            : AppText.body(c).copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded, color: c.muted),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$perWeek ${perWeek == 1 ? 'workout' : 'workouts'} a week for $_weeks weeks'
                      '${_deload ? ' plus a deload week' : ''}: ${perWeek * totalWeeks} sessions, '
                      '${shortDate(_start)} to ${shortDate(end)}.',
                      style: AppText.quiet(c),
                    ),
                    const SizedBox(height: 14),
                    SmallButton(label: 'Start mesocycle', onTap: () => _begin(s)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a block went: sessions and each lift's strength change.
class MesoSummaryScreen extends StatelessWidget {
  const MesoSummaryScreen({super.key, required this.mesoId});

  final String mesoId;

  static Route<void> route(String id) =>
      MaterialPageRoute<void>(builder: (_) => MesoSummaryScreen(mesoId: id));

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final m = s.mesoById(mesoId);
    if (m == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: Center(child: Text('This block no longer exists.', style: AppText.body(c))),
      );
    }
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    String w(double kg) => '${oneDecimal(imperial ? kgToLb(kg) : kg)} $unit';
    final report = s.mesoReport(m);
    final today = dateOnly(DateTime.now());
    final finished = m.endDay.isBefore(today);
    final week = m.weekOn(today);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 40),
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
                      Text(m.name, style: AppText.title(c).copyWith(fontSize: 24)),
                      Text(
                        '${shortDate(m.start)} – ${shortDate(m.endDay)}'
                        '${m.endedEarly != null ? ' (ended early)' : ''}',
                        style: AppText.quiet(c),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Overview',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (label, value) in [
                          ('Progression', m.progression.label),
                          ('Length', '${m.weeks} weeks${m.deload ? ' + deload' : ''}'),
                          ('Workouts done', '${report.done} of ${report.scheduled} scheduled'),
                          if (week != null)
                            ('Now', m.isDeloadWeek(week) ? 'Deload week' : 'Week $week of ${m.weeks}'),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(label, style: AppText.quiet(c))),
                                Text(value, style: AppText.body(c).copyWith(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Strength change (estimated 1RM)',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (report.lifts.isEmpty)
                          Text('Log workouts in this block to see each lift here.', style: AppText.quiet(c)),
                        for (final (id, first, last) in report.lifts)
                          Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                            child: Row(
                              children: [
                                Expanded(child: Text(s.exerciseName(id), style: AppText.body(c))),
                                Text(
                                  first == null || last == null
                                      ? '—'
                                      : '${w(first)} → ${w(last)}',
                                  style: AppText.body(c).copyWith(fontSize: 14),
                                ),
                                if (first != null && last != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    '${last >= first ? '+' : '−'}${oneDecimal(imperial ? kgToLb((last - first).abs()) : (last - first).abs())}',
                                    style: AppText.body(c).copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: last >= first ? c.accent : c.protein,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          'Best set in the first week each lift was done vs the last working '
                          'week (deload left out).',
                          style: AppText.quiet(c).copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (finished) ...[
                    const SizedBox(height: 16),
                    SmallButton(
                      label: 'Start the next block',
                      onTap: () => Navigator.of(context).pushReplacement(MesoEditorScreen.route(m)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Same setup, starting the Monday after this block. Your weights '
                      'carry over through "last time" in the logger.',
                      style: AppText.quiet(c).copyWith(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
