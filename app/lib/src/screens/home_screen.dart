import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_tour.dart';
import '../widgets/common.dart';
import '../widgets/pie_menu.dart';

/// The app's sections, in pie and tab-bar order.
const appSections = <PieItem>[
  PieItem('Log', Icons.edit_note_rounded),
  PieItem('Progress', Icons.show_chart_rounded),
  PieItem('Plan', Icons.event_note_rounded),
  PieItem('Food', Icons.restaurant_rounded),
  PieItem('Settings', Icons.tune_rounded),
];
const chatSection = PieItem('Chat', Icons.chat_bubble_outline_rounded);

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

/// "Good morning Sam, it is Saturday, October 3rd" (no comma before the
/// name; "Good morning, it is ..." without one).
String welcomeLine(DateTime now, String? nickname) {
  final part = now.hour < 12 ? 'Good morning' : (now.hour < 18 ? 'Good afternoon' : 'Good evening');
  final name = nickname == null ? '' : ' $nickname';
  return '$part$name, it is ${_days[now.weekday - 1]}, ${_months[now.month - 1]} ${_ordinal(now.day)}';
}

/// "Today you will do Upper A and eat 2,100 calories."
String todaySummary(AppState s) {
  final now = DateTime.now();
  final t = s.targets;
  final kcal = t == null ? null : thousands(t.kcal);
  final active = s.activeSession;
  final planned = [
    for (final p in s.plannedOn(now))
      if (!s.plannedDone(p) && s.workoutById(p.workoutId) != null) s.workoutById(p.workoutId)!.name,
  ];
  final done = s.finishedOn(now);
  if (active != null) {
    return kcal == null ? '${active.name} is in progress.' : '${active.name} is in progress. Eat $kcal calories today.';
  }
  if (planned.isNotEmpty) {
    final what = planned.join(' and ');
    return kcal == null ? 'Today you will do $what.' : 'Today you will do $what and eat $kcal calories.';
  }
  if (done.isNotEmpty) {
    return kcal == null ? 'You did ${done.last.name} today.' : 'You did ${done.last.name} today. Eat $kcal calories.';
  }
  return kcal == null ? 'Today is a rest day.' : 'Today is a rest day. Eat $kcal calories.';
}

/// Home: the greeting, today in a sentence, the pie, and the two morning
/// check-ins. Fits on one screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.fold,
    required this.selected,
    required this.onPick,
    this.returning = false,
    this.tourStep,
  });

  final Animation<double> fold;
  final int? selected;
  final ValueChanged<int> onPick;

  /// Folding back from a section (see [PieMenu.returning]).
  final bool returning;

  /// The app tour step being shown, if any: lights up what it describes.
  final int? tourStep;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final step = tourStep == null ? null : tourSteps[tourStep!];
    // During the tour: light up the slice being described, or the rows
    // (with the pie faded); while the pie is described, the rows fade.
    final spotlight = step == null ? null : (step.rows ? -1 : step.spotlight);
    final rowsDim = step != null && !step.rows && step.spotlight != null;
    Widget fading(Widget child) => AnimatedBuilder(
          animation: fold,
          builder: (context, _) => IgnorePointer(
            ignoring: fold.value > 0,
            child: Opacity(opacity: (1 - fold.value / 0.3).clamp(0.0, 1.0), child: child),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fading(Column(
              children: [
                Text(
                  welcomeLine(DateTime.now(), s.settings.nickname),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w500, height: 1.3, color: c.text),
                ),
                const SizedBox(height: 8),
                Text(
                  todaySummary(s),
                  textAlign: TextAlign.center,
                  style: AppText.quiet(c).copyWith(fontSize: 15),
                ),
              ],
            )),
            const SizedBox(height: 10),
            Expanded(
              child: PieMenu(
                items: appSections,
                centre: chatSection,
                selected: selected,
                fold: fold,
                onPick: onPick,
                reduceMotion: reduceMotion,
                returning: returning,
                spotlight: spotlight,
              ),
            ),
            const SizedBox(height: 10),
            fading(AnimatedOpacity(
              opacity: rowsDim ? 0.3 : 1,
              duration: const Duration(milliseconds: 180),
              child: const _CheckRows(),
            )),
          ],
        ),
      ),
    );
  }
}

/// Weigh-in and last night's sleep, one row each.
class _CheckRows extends StatefulWidget {
  const _CheckRows();

  @override
  State<_CheckRows> createState() => _CheckRowsState();
}

class _CheckRowsState extends State<_CheckRows> {
  final _weight = TextEditingController();
  final _hours = TextEditingController();
  bool _editWeight = false;
  bool _editSleep = false;

  static const _qualityWords = ['', 'poor', 'fair', 'okay', 'good', 'great'];

  @override
  void dispose() {
    _weight.dispose();
    _hours.dispose();
    super.dispose();
  }

  DateTime get _today => dateOnly(DateTime.now());

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

  /// Hours as "7.5" or "7:20".
  int? _minutes(String text) {
    final t = text.trim();
    if (t.contains(':')) {
      final p = t.split(':');
      final h = int.tryParse(p[0]);
      final m = p.length > 1 ? int.tryParse(p[1]) : 0;
      if (h == null || m == null || m >= 60) return null;
      return h * 60 + m;
    }
    final v = parseNumber(t);
    return v == null ? null : (v * 60).round();
  }

  void _saveHours(AppState s) {
    final m = _minutes(_hours.text);
    if (m == null || m < 60 || m > 16 * 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the hours you slept, like 7.5 or 7:30.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final old = s.sleepOn(_today);
    s.logSleep(SleepEntry(date: _today, durationMin: m, quality: old?.quality));
    // With no quality yet, the row asks for it next.
    setState(() => _editSleep = false);
  }

  void _saveQuality(AppState s, int q) {
    final e = s.sleepOn(_today);
    if (e == null) return;
    HapticFeedback.mediumImpact();
    s.logSleep(SleepEntry(
      date: e.date,
      bedMinute: e.bedMinute,
      wakeMinute: e.wakeMinute,
      durationMin: e.durationMin,
      quality: q,
      source: e.source,
    ));
    setState(() => _editSleep = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    String w(double kg) => oneDecimal(imperial ? kgToLb(kg) : kg);
    final weighIn = s.weighInOn(_today);
    final night = s.sleepOn(_today);
    final avg = s.weeklyAverageKg;

    Widget label(IconData icon, String text) => Container(
          width: 104,
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Flexible(child: Text(text, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600, fontSize: 14))),
            ],
          ),
        );
    Widget row(Widget child) => Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
          child: child,
        );
    // A narrow box, right-aligned next to Save: the numbers are short.
    Widget input(TextEditingController ctrl, String suffix, String semantic, Key key) => SizedBox(
          width: 104,
          child: NumberBox(key: key, controller: ctrl, suffix: suffix, semanticLabel: semantic, onChanged: (_) {}),
        );
    Widget done(String main, String sub, VoidCallback onEdit) => Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(main, style: AppText.body(c).copyWith(fontSize: 17)),
                    Text(sub, style: AppText.quiet(c).copyWith(fontSize: 12, color: c.accent, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              SmallButton(label: 'Edit', quiet: true, onTap: onEdit),
            ],
          ),
        );

    // ---- weight
    final weightRow = row(Row(
      children: [
        label(Icons.monitor_weight_outlined, 'Weigh-in'),
        if (weighIn != null && !_editWeight)
          done('${w(weighIn.weightKg)} $unit', avg == null ? 'Logged' : 'Logged · 7-day avg ${w(avg)}', () {
            _weight.text = w(weighIn.weightKg);
            setState(() => _editWeight = true);
          })
        else ...[
          const Spacer(),
          input(_weight, unit, 'Weight in $unit', const ValueKey('home-weight')),
          const SizedBox(width: 8),
          SmallButton(label: 'Save', onTap: () => _saveWeight(s)),
        ],
      ],
    ));

    // ---- sleep: hours first, then quality, then what's logged
    final n = night;
    Widget sleepBody;
    if (n != null && n.quality == null && !_editSleep) {
      sleepBody = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${oneDecimal((n.durationMin ?? 0) / 60)} h. How did you sleep? 1 poor, 5 great.',
              style: AppText.quiet(c).copyWith(fontSize: 12),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var q = 1; q <= 5; q++) ...[
                  if (q > 1) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Sleep quality $q of 5',
                      child: GestureDetector(
                        onTap: () => _saveQuality(s, q),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.chip,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: c.line),
                          ),
                          child: Text('$q', style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    } else if (n != null && !_editSleep) {
      final mins = n.durationMin;
      final q = n.quality;
      sleepBody = done(
        [if (mins != null) '${oneDecimal(mins / 60)} h', if (q != null) 'quality $q of 5 (${_qualityWords[q]})'].join(' · '),
        'Logged',
        () {
          _hours.text = mins == null ? '' : oneDecimal(mins / 60);
          setState(() => _editSleep = true);
        },
      );
    } else {
      sleepBody = Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            input(_hours, 'h', 'Hours slept', const ValueKey('home-sleep')),
            const SizedBox(width: 8),
            SmallButton(label: 'Save', onTap: () => _saveHours(s)),
          ],
        ),
      );
    }
    final sleepRow = row(Row(children: [label(Icons.bedtime_outlined, 'Last night'), sleepBody]));

    final imperialWater = s.settings.units == Units.imperial;
    final drank = s.waterOn(DateTime.now());
    final waterGoal = s.waterGoalMl;
    final waterRow = row(Row(
      children: [
        label(Icons.water_drop_outlined, 'Water'),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatWater(drank, imperial: imperialWater)} of ${formatWater(waterGoal, imperial: imperialWater)}',
                style: AppText.body(c).copyWith(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: waterGoal <= 0 ? 0 : (drank / waterGoal).clamp(0.0, 1.0),
                  minHeight: 5,
                  color: c.accent,
                  backgroundColor: c.chip,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SmallButton(
          key: const ValueKey('home-water'),
          label: imperialWater ? '+1 cup' : '+250 ml',
          onTap: () {
            HapticFeedback.lightImpact();
            s.addWater(waterStepMl(imperial: imperialWater));
          },
        ),
      ],
    ));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [weightRow, const SizedBox(height: 8), sleepRow, const SizedBox(height: 8), waterRow],
    );
  }
}
