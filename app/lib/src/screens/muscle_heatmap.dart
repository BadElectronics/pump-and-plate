import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/muscles.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/muscle_map.dart';

/// Sets per muscle: over the last 7 days, or the weekly average of the last
/// 28 (so a fresh week never shows an empty map).
({Map<Muscle, double> sets, DateTime from, DateTime to}) muscleSetsFor(AppState s, {required bool fourWeeks}) {
  final to = dateOnly(DateTime.now());
  final from = DateTime(to.year, to.month, to.day - (fourWeeks ? 27 : 6));
  final raw = setsPerMuscle(s.finishedSessions, from: from, to: to, exercise: s.exercise);
  return (sets: fourWeeks ? {for (final e in raw.entries) e.key: e.value / 4} : raw, from: from, to: to);
}

/// The same per muscle head (the advanced map).
({Map<MuscleHead, double> sets, DateTime from, DateTime to}) headSetsFor(AppState s, {required bool fourWeeks}) {
  final to = dateOnly(DateTime.now());
  final from = DateTime(to.year, to.month, to.day - (fourWeeks ? 27 : 6));
  final raw = setsPerHead(s.finishedSessions, from: from, to: to, exercise: s.exercise);
  return (sets: fourWeeks ? {for (final e in raw.entries) e.key: e.value / 4} : raw, from: from, to: to);
}

Widget _label(AppColors c, String text) =>
    Text(text.toUpperCase(), style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent));

/// Progress > Training: the heatmap and sets per muscle.
class MuscleHeatmapCard extends StatefulWidget {
  const MuscleHeatmapCard({super.key});

  @override
  State<MuscleHeatmapCard> createState() => _MuscleHeatmapCardState();
}

class _MuscleHeatmapCardState extends State<MuscleHeatmapCard> {
  bool _fourWeeks = false;
  bool _back = false;
  Muscle? _selected;
  MuscleHead? _selectedHead;

  Future<void> _openHead(AppState s, MuscleHead h) async {
    HapticFeedback.selectionClick();
    setState(() => _selectedHead = h);
    await showHeadSheet(context, s, h, fourWeeks: _fourWeeks);
    if (mounted) setState(() => _selectedHead = null);
  }

  Future<void> _open(AppState s, Muscle m) async {
    HapticFeedback.selectionClick();
    setState(() => _selected = m);
    await showMuscleSheet(context, s, m, fourWeeks: _fourWeeks);
    if (mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final data = muscleSetsFor(s, fourWeeks: _fourWeeks);
    final ranked = Muscle.values.toList()..sort((a, b) => data.sets[b]!.compareTo(data.sets[a]!));
    final heads = s.settings.headsMap;
    final headData = heads ? headSetsFor(s, fourWeeks: _fourWeeks) : null;
    final rankedHeads = headData == null
        ? const <MuscleHead>[]
        : (MuscleHead.values.toList()..sort((a, b) => headData.sets[b]!.compareTo(headData.sets[a]!)));
    Widget card(Widget child) => Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
          child: child,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _label(c, 'Muscles')),
                SizedBox(
                  width: 190,
                  child: Segmented<bool>(
                    label: 'Range',
                    options: const [(false, 'This week'), (true, '4 weeks')],
                    value: _fourWeeks,
                    onChanged: (v) => setState(() => _fourWeeks = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Segmented<bool>(
                    label: 'Side',
                    options: const [(false, 'Front'), (true, 'Back')],
                    value: _back,
                    onChanged: (v) => setState(() => _back = v),
                  ),
                ),
                const SizedBox(width: 10),
                Text('Heads', style: AppText.body(c).copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Toggle(
                  key: const ValueKey('heads-toggle'),
                  label: 'Advanced: show muscle heads',
                  value: heads,
                  onChanged: (v) => s.setSettings(s.settings.copyWith(headsMap: v)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: headData != null
                  ? HeadMap(
                      key: const ValueKey('head-map'),
                      sets: headData.sets,
                      back: _back,
                      selected: _selectedHead,
                      width: 180,
                      onTap: (h) => _openHead(s, h),
                    )
                  : MuscleMap(
                      key: const ValueKey('muscle-map'),
                      sets: data.sets,
                      back: _back,
                      selected: _selected,
                      width: 180,
                      onTap: (m) => _open(s, m),
                    ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final (level, text) in const [(0, '0'), (1, '1–4'), (2, '5–9'), (3, '10–19'), (4, '20+ sets')])
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: heatColor(c, level), borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(width: 4),
                    Text(text, style: AppText.quiet(c).copyWith(fontSize: 11)),
                  ]),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_fourWeeks ? 'Weekly average over the last 4 weeks.' : 'Last 7 days.'} '
              'Tap a ${heads ? 'part' : 'muscle'} for details.',
              style: AppText.quiet(c).copyWith(fontSize: 12),
            ),
          ],
        )),
        const SizedBox(height: 14),
        card(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(c, '${heads ? 'Sets per head' : 'Sets per muscle'} · ${_fourWeeks ? 'weekly average' : 'last 7 days'}'),
            const SizedBox(height: 6),
            if (headData != null)
              for (final h in rankedHeads)
                InkWell(
                  onTap: () => _openHead(s, h),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(width: 132, child: Text(h.label, style: AppText.body(c).copyWith(fontSize: 13))),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (headData.sets[h]! / 20).clamp(0.0, 1.0),
                              minHeight: 8,
                              color: c.accent,
                              backgroundColor: c.chip,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(setsText(headData.sets[h]!),
                              textAlign: TextAlign.right, style: AppText.quiet(c).copyWith(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                )
            else
            for (final m in ranked)
              InkWell(
                onTap: () => _open(s, m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      SizedBox(width: 92, child: Text(m.label, style: AppText.body(c).copyWith(fontSize: 13))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (data.sets[m]! / 20).clamp(0.0, 1.0),
                            minHeight: 8,
                            color: c.accent,
                            backgroundColor: c.chip,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(setsText(data.sets[m]!),
                            textAlign: TextAlign.right, style: AppText.quiet(c).copyWith(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
                heads
                    ? 'A set counts in full for a part an exercise works most, half for some, a quarter for a little. Warm-ups don\'t count.'
                    : 'Primary muscles count a full set, secondary ones half. Warm-ups don\'t count.',
                style: AppText.quiet(c).copyWith(fontSize: 11)),
          ],
        )),
      ],
    );
  }
}

/// One muscle: its sets and what counted toward them.
Future<void> showMuscleSheet(BuildContext context, AppState s, Muscle m, {required bool fourWeeks}) {
  final c = AppColors.of(context);
  final data = muscleSetsFor(s, fourWeeks: fourWeeks);
  final n = data.sets[m]!;
  final parts = setsForMuscle(m, s.finishedSessions, from: data.from, to: data.to, exercise: s.exercise);
  final hint = n == 0
      ? 'Not trained in this range.'
      : n < 10
          ? 'Below the usual 10–20 sets a week.'
          : n <= 20
              ? 'Within the usual 10–20 sets a week.'
              : 'Above 20 sets a week.';
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(m.label, style: AppText.title(c).copyWith(fontSize: 22))),
                Text(
                  '${setsText(n)} ${n == 1 ? 'set' : 'sets'} ${fourWeeks ? 'a week, on average' : 'in the last 7 days'}',
                  style: AppText.quiet(c),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(hint, style: AppText.quiet(c).copyWith(fontSize: 13)),
            const SizedBox(height: 8),
            if (parts.isEmpty)
              Text('No exercises in this range.', style: AppText.quiet(c))
            else
              for (final (id, sets, secondary) in parts)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text('${s.exerciseName(id)}${secondary ? ' (½)' : ''}', style: AppText.body(c).copyWith(fontSize: 14))),
                      Text('${setsText(fourWeeks ? sets / 4 : sets)} sets', style: AppText.quiet(c)),
                    ],
                  ),
                ),
            const SizedBox(height: 8),
            Text('Secondary muscles count as half a set.', style: AppText.quiet(c).copyWith(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

/// Progress > Overview: "Muscles this week", opening the full heatmap.
class MusclesOverviewCard extends StatelessWidget {
  const MusclesOverviewCard({super.key, this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final sets = muscleSetsFor(s, fourWeeks: false).sets;
    final top = (Muscle.values.where((m) => sets[m]! > 0).toList()..sort((a, b) => sets[b]!.compareTo(sets[a]!))).take(3).toList();
    final missed = Muscle.values.where((m) => sets[m]! == 0).take(3).map((m) => m.label.toLowerCase()).toList();
    return InkWell(
      key: const ValueKey('muscles-overview'),
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: _label(c, 'Muscles this week')),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ]),
            const SizedBox(height: 6),
            Row(
              children: [
                if (s.settings.headsMap) ...[
                  HeadMap(sets: headSetsFor(s, fourWeeks: false).sets, width: 58),
                  const SizedBox(width: 4),
                  HeadMap(sets: headSetsFor(s, fourWeeks: false).sets, back: true, width: 58),
                ] else ...[
                  MuscleMap(sets: sets, width: 58),
                  const SizedBox(width: 4),
                  MuscleMap(sets: sets, back: true, width: 58),
                ],
                const SizedBox(width: 14),
                Expanded(
                  child: top.isEmpty
                      ? Text('Finish a workout to see which muscles you train.', style: AppText.quiet(c))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final m in top)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text.rich(TextSpan(children: [
                                  TextSpan(text: m.label, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
                                  TextSpan(text: '  ${setsText(sets[m]!)} sets', style: AppText.quiet(c).copyWith(fontSize: 13)),
                                ])),
                              ),
                            if (missed.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Not trained: ${missed.join(', ')}', style: AppText.quiet(c).copyWith(fontSize: 12)),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One muscle head: its sets, a tip, what counted, and what hits it most.
Future<void> showHeadSheet(BuildContext context, AppState s, MuscleHead h, {required bool fourWeeks}) {
  final c = AppColors.of(context);
  final data = headSetsFor(s, fourWeeks: fourWeeks);
  final n = data.sets[h]!;
  final parts = setsForHead(h, s.finishedSessions, from: data.from, to: data.to, exercise: s.exercise);
  final best = exercisesForHead(h, s.exercises).take(6).toList();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (h.part.isNotEmpty) Text(h.muscle.label, style: AppText.quiet(c)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: Text(h.part.isEmpty ? h.muscle.label : h.part, style: AppText.title(c).copyWith(fontSize: 22))),
                Text(
                  '${setsText(n)} ${n == 1 ? 'set' : 'sets'}${fourWeeks ? ' a week' : ''}',
                  style: AppText.quiet(c),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(h.tip, style: AppText.body(c).copyWith(fontSize: 14, height: 1.4)),
            const SizedBox(height: 12),
            Text('WHAT COUNTED', style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
            const SizedBox(height: 4),
            if (parts.isEmpty)
              Text(fourWeeks ? 'Nothing in the last 4 weeks.' : 'Nothing in the last 7 days.', style: AppText.quiet(c))
            else
              for (final (id, sets, level) in parts)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.exerciseName(id), style: AppText.body(c).copyWith(fontSize: 14))),
                      Text('${emphasisLabel(level).toLowerCase()} → ${setsText(fourWeeks ? sets / 4 : sets)}', style: AppText.quiet(c)),
                    ],
                  ),
                ),
            if (best.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('HITS IT MOST', style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in best)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(16)),
                      child: Text(e.name, style: AppText.body(c).copyWith(fontSize: 13)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
