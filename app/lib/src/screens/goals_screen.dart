import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

const _menPcts = [5, 8, 10, 12, 15, 20, 30, 40, 50];
const _womenPcts = [10, 12, 15, 20, 30, 40, 50];

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, this.embedded = false});

  /// Inside the Plan tab: no own title or safe-area padding.
  final bool embedded;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  final _cm = TextEditingController();
  final _weight = TextEditingController();
  final _target = TextEditingController();

  Units? _filledFor;
  bool _pickingGoal = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    if (_filledFor != s.settings.units) {
      _filledFor = s.settings.units;
      _fill(s);
    }
  }

  @override
  void dispose() {
    for (final c in [_feet, _inches, _cm, _weight, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _imperial => _filledFor == Units.imperial;

  double _toDisplayWeight(double kg) => _imperial ? kgToLb(kg) : kg;
  double _fromDisplayWeight(double v) => _imperial ? lbToKg(v) : v;
  String get _wUnit => _imperial ? 'lb' : 'kg';

  void _fill(AppState s) {
    final h = s.profile.heightCm;
    if (h != null) {
      final totalIn = cmToInch(h);
      var ft = (totalIn / 12).floor();
      var inch = (totalIn - ft * 12).round();
      if (inch == 12) {
        ft += 1;
        inch = 0;
      }
      _feet.text = '$ft';
      _inches.text = '$inch';
      _cm.text = h.round().toString();
    } else {
      _feet.clear();
      _inches.clear();
      _cm.clear();
    }
    final w = s.currentWeightKg;
    _weight.text = w == null ? '' : oneDecimal(_toDisplayWeight(w));
    final t = s.goal.targetWeightKg;
    _target.text = t == null ? '' : oneDecimal(_toDisplayWeight(t));
  }

  // ------------------------------------------------------------ edits

  void _onHeightImperial(AppState s) {
    final ft = parseNumber(_feet.text);
    final inch = parseNumber(_inches.text) ?? 0;
    if (ft == null || ft < 3 || ft > 8 || inch < 0 || inch >= 12) return;
    s.setProfile(s.profile.copyWith(heightCm: inchToCm(ft * 12 + inch)));
  }

  void _onHeightMetric(AppState s) {
    final cm = parseNumber(_cm.text);
    if (cm == null || cm < 100 || cm > 250) return;
    s.setProfile(s.profile.copyWith(heightCm: cm));
  }

  void _onWeight(AppState s) {
    final v = parseNumber(_weight.text);
    if (v == null) return;
    final kg = _fromDisplayWeight(v);
    if (kg < 30 || kg > 350) return;
    s.logWeight(kg, source: 'goals');
  }

  void _onTarget(AppState s) {
    if (_target.text.trim().isEmpty) {
      s.setGoal(s.goal.copyWith(targetWeightKg: null));
      return;
    }
    final v = parseNumber(_target.text);
    if (v == null) return;
    final kg = _fromDisplayWeight(v);
    if (kg < 30 || kg > 350) return;
    s.setGoal(s.goal.copyWith(targetWeightKg: kg));
  }

  Future<void> _pickBirthday(AppState s) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: s.profile.birthday ?? DateTime(now.year - 30, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Your birthday',
    );
    if (picked != null) s.setProfile(s.profile.copyWith(birthday: picked));
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);

    final list = ListView(
      padding: EdgeInsets.fromLTRB(20, widget.embedded ? 16 : 28, 20, 40),
      children: [
        if (!widget.embedded) ...[
          Text('Goals', style: AppText.title(c)),
          const SizedBox(height: 20),
        ],
          _aboutYou(s, c),
          const SizedBox(height: 14),
          _bodyFat(s, c),
          const SizedBox(height: 14),
          _goal(s, c),
          const SizedBox(height: 14),
          _targets(s, c),
          const SizedBox(height: 14),
          _phases(s, c),
          const SizedBox(height: 14),
          _learned(s, c),
          const SizedBox(height: 14),
          _metrics(s, c),
      ],
    );
    return widget.embedded ? list : SafeArea(bottom: false, child: list);
  }

  Widget _aboutYou(AppState s, AppColors c) {
    final p = s.profile;
    return SectionCard(
      title: 'About you',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Birthday'),
          _TapBox(
            text: p.birthday == null ? 'Set your birthday' : longDate(p.birthday!),
            placeholder: p.birthday == null,
            onTap: () => _pickBirthday(s),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Height'),
          if (_imperial)
            Row(
              children: [
                Expanded(
                  child: NumberBox(
                    controller: _feet,
                    suffix: 'ft',
                    decimal: false,
                    semanticLabel: 'Height, feet',
                    onChanged: (_) => _onHeightImperial(s),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NumberBox(
                    controller: _inches,
                    suffix: 'in',
                    decimal: false,
                    semanticLabel: 'Height, inches',
                    onChanged: (_) => _onHeightImperial(s),
                  ),
                ),
              ],
            )
          else
            NumberBox(
              controller: _cm,
              suffix: 'cm',
              decimal: false,
              semanticLabel: 'Height in centimeters',
              onChanged: (_) => _onHeightMetric(s),
            ),
          const SizedBox(height: 14),
          const FieldLabel('Current weight'),
          NumberBox(
            controller: _weight,
            suffix: _wUnit,
            semanticLabel: 'Current weight',
            hint: _imperial ? 'e.g. 182.4' : 'e.g. 82.7',
            onChanged: (_) => _onWeight(s),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Sex (used by the calorie formula)'),
          Segmented<Sex>(
            label: 'Sex',
            options: const [(Sex.male, 'Male'), (Sex.female, 'Female')],
            value: p.sex,
            onChanged: (v) => s.setProfile(p.copyWith(sex: v)),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Activity outside workouts'),
          for (final a in Activity.values)
            _ChoiceRow(
              title: a.label,
              detail: a.detail,
              selected: p.activity == a,
              onTap: () => s.setProfile(p.copyWith(activity: a)),
            ),
        ],
      ),
    );
  }

  Widget _bodyFat(AppState s, AppColors c) {
    final g = s.goal;
    final female = s.profile.sex == Sex.female;
    final pcts = female ? _womenPcts : _menPcts;
    final prefix = female ? 'women' : 'men';
    final now = g.bodyFatNowPct;
    final goal = g.bodyFatGoalPct;

    return SectionCard(
      title: 'Body fat estimate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Segmented<bool>(
            label: 'Tap a photo to set',
            options: const [(false, 'Set current'), (true, 'Set goal')],
            value: _pickingGoal,
            onChanged: (v) => setState(() => _pickingGoal = v),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              const gap = 8.0;
              final w = (box.maxWidth - gap * 2) / 3;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final pct in pcts)
                    SizedBox(
                      width: w,
                      child: _BodyFatTile(
                        asset:
                            'assets/bodyfat/${prefix}_${pct.toString().padLeft(2, '0')}.jpg',
                        pct: pct,
                        isNow: now != null && now.round() == pct,
                        isGoal: goal != null && goal.round() == pct,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          s.setGoal(_pickingGoal
                              ? g.copyWith(bodyFatGoalPct: pct.toDouble())
                              : g.copyWith(bodyFatNowPct: pct.toDouble()));
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Tap the photo closest to what you see in the mirror, then fine-tune '
            'with the sliders. Reference photos: JN Muscle Lab, measured with '
            'DXA and BIA.',
            style: AppText.quiet(c).copyWith(fontSize: 12),
          ),
          const SizedBox(height: 14),
          _PctSlider(
            label: 'Current',
            value: now,
            min: 5,
            max: 50,
            color: c.protein,
            onChanged: (v) => s.setGoal(g.copyWith(bodyFatNowPct: v)),
          ),
          const SizedBox(height: 6),
          _PctSlider(
            label: 'Goal',
            value: goal,
            min: 5,
            max: 35,
            color: c.accent,
            onChanged: (v) => s.setGoal(g.copyWith(bodyFatGoalPct: v)),
          ),
        ],
      ),
    );
  }

  Widget _goal(AppState s, AppColors c) {
    final g = s.goal;
    final double? weight = s.currentWeightKg;
    final now = g.bodyFatNowPct;
    final goalBf = g.bodyFatGoalPct;
    final double? suggestKg = (weight != null && now != null && goalBf != null)
        ? weightAtBodyFat(leanMassKg(weight, now), goalBf)
        : null;

    // Pace slider runs in the display unit.
    final paceMin = _imperial ? 0.25 : 0.1;
    final paceMax = _imperial ? 2.0 : 0.9;
    final paceDivisions = _imperial ? 7 : 8;

    // Protein slider: g per lb of body weight (0.8-1.2), or the same range
    // per kg (1.8-2.6) in metric.
    final protMin = _imperial ? 0.8 : 1.8;
    final protMax = _imperial ? 1.2 : 2.6;
    final protDisplay = (_imperial
            ? g.proteinGPerKg * kgPerLb
            : g.proteinGPerKg)
        .clamp(protMin, protMax)
        .toDouble();
    final protUnit = _imperial ? 'g per lb' : 'g per kg';
    final useTarget = g.proteinBasis == ProteinBasis.target;
    final basisKg = s.proteinBasisKg;
    final protGrams = basisKg == null ? null : basisKg * g.proteinGPerKg;
    final paceDisplay =
        (_imperial ? kgToLb(g.paceKgPerWeek) : g.paceKgPerWeek)
            .clamp(paceMin, paceMax)
            .toDouble();

    return SectionCard(
      title: 'Goal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.activePhase case final phase?) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.accent.withAlpha(28),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Your current phase (${_phaseLabel(s, phase)}) sets the goal and pace '
                'right now${phase.end == null ? '' : ', until ${shortDate(phase.end!)}'}. '
                'What you choose here applies when no phase is running.',
                style: AppText.body(c).copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Segmented<GoalMode>(
            label: 'Goal type',
            options: const [
              (GoalMode.lose, 'Lose'),
              (GoalMode.maintain, 'Maintain'),
              (GoalMode.gain, 'Gain'),
            ],
            value: g.mode,
            onChanged: (v) => s.setGoal(g.copyWith(mode: v)),
          ),
          const SizedBox(height: 14),
          const FieldLabel('Target weight'),
          NumberBox(
            controller: _target,
            suffix: _wUnit,
            semanticLabel: 'Target weight',
            onChanged: (_) => _onTarget(s),
          ),
          if (suggestKg != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                final v = oneDecimal(_toDisplayWeight(suggestKg!));
                _target.text = v;
                _onTarget(s);
              },
              child: Text(
                'At ${goalBf!.round()}% body fat with today\'s lean mass: '
                '${oneDecimal(_toDisplayWeight(suggestKg!))} $_wUnit. Tap to use it.',
                style: AppText.quiet(c).copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (g.mode != GoalMode.maintain) ...[
            const SizedBox(height: 14),
            FieldLabel(
              'Pace',
              trailing: Text(
                '${paceDisplay.toStringAsFixed(_imperial ? 2 : 1)} $_wUnit / week',
                style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: c.accent,
                inactiveTrackColor: c.line,
                thumbColor: c.accent,
                overlayColor: c.accent.withAlpha(30),
                trackHeight: 4,
              ),
              child: Slider(
                value: paceDisplay,
                min: paceMin,
                max: paceMax,
                divisions: paceDivisions,
                label: paceDisplay.toStringAsFixed(_imperial ? 2 : 1),
                onChanged: (v) => s.setGoal(g.copyWith(
                  paceKgPerWeek: _imperial ? lbToKg(v) : v,
                )),
              ),
            ),
          ],
          const SizedBox(height: 14),
          FieldLabel(
            'Protein',
            trailing: Text(
              '${protDisplay.toStringAsFixed(_imperial ? 2 : 1)} $protUnit',
              style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: c.protein,
              inactiveTrackColor: c.line,
              thumbColor: c.protein,
              overlayColor: c.protein.withAlpha(30),
              trackHeight: 4,
            ),
            child: Slider(
              value: protDisplay,
              min: protMin,
              max: protMax,
              divisions: 8,
              label: protDisplay.toStringAsFixed(_imperial ? 2 : 1),
              onChanged: (v) => s.setGoal(g.copyWith(
                proteinGPerKg: _imperial ? v / kgPerLb : v,
              )),
            ),
          ),
          const SizedBox(height: 4),
          Segmented<ProteinBasis>(
            label: 'Protein is based on',
            options: const [
              (ProteinBasis.current, 'Current weight'),
              (ProteinBasis.target, 'Target weight'),
            ],
            value: g.proteinBasis,
            onChanged: (v) => s.setGoal(g.copyWith(proteinBasis: v)),
          ),
          const SizedBox(height: 8),
          Text(
            protGrams == null
                ? 'Add your weight to see grams per day.'
                : '${protGrams.round()} g a day, based on your '
                    '${useTarget && g.targetWeightKg != null ? 'target' : 'current'} weight of '
                    '${oneDecimal(_toDisplayWeight(basisKg!))} $_wUnit.',
            style: AppText.quiet(c),
          ),
          if (useTarget && g.targetWeightKg == null)
            Text(
              'Set a target weight above to use it; current weight is used until then.',
              style: AppText.quiet(c).copyWith(color: c.protein),
            ),
        ],
      ),
    );
  }

  Widget _targets(AppState s, AppColors c) {
    final t = s.targets;
    // Inverted card: dark on light themes, light on Night.
    final bg = c.text;
    final fg = c.background;
    final soft = Color.lerp(c.background, c.text, 0.35)!;

    if (t == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'Add your birthday, height and current weight to see your daily '
          'calorie and protein targets.',
          style: AppText.body(c).copyWith(color: fg),
        ),
      );
    }

    final weight = s.currentWeightKg!;
    String eta;
    final target = s.goal.targetWeightKg;
    if (s.goal.mode == GoalMode.maintain) {
      eta = 'Holding steady around ${oneDecimal(_toDisplayWeight(weight))} $_wUnit.';
    } else if (t.goalDate != null && target != null) {
      eta = 'At this pace you reach ${oneDecimal(_toDisplayWeight(target))} '
          '$_wUnit around ${shortDate(t.goalDate!)}.';
    } else {
      eta = 'Set a target weight to see when you get there.';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your daily targets',
              style: AppText.quiet(c).copyWith(color: soft)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _BigStat(thousands(t.kcal), 'kcal', fg, soft)),
              Expanded(
                child: _BigStat('${t.proteinG.round()} g', 'protein', fg, soft),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: soft.withAlpha(90)),
          const SizedBox(height: 14),
          Text(eta, style: AppText.body(c).copyWith(color: fg)),
          if (t.floored) ...[
            const SizedBox(height: 6),
            Text(
              'Raised to a safe minimum: a faster pace would put you below '
              'your resting burn.',
              style: AppText.quiet(c).copyWith(color: soft),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            t.learned
                ? 'Maintenance is ${thousands(t.maintenanceKcal)} kcal, learned from '
                    'your food and weight logs.'
                : 'Maintenance is estimated at ${thousands(t.maintenanceKcal)} kcal. '
                    'After about 3 weeks of logging food and weight, it can be '
                    'learned from your real numbers (see below).',
            style: AppText.quiet(c).copyWith(color: soft, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 0.25 -> "0.25", 0.5 -> "0.5", 1.0 -> "1" (two decimals at most).
  static String _paceText(double v) => v
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');

  String _phaseLabel(AppState s, Phase p) {
    final imperial = s.settings.units == Units.imperial;
    final pace = _paceText(imperial ? kgToLb(p.paceKgPerWeek) : p.paceKgPerWeek);
    final unit = imperial ? 'lb' : 'kg';
    return switch (p.mode) {
      GoalMode.lose => 'Cut, $pace $unit a week',
      GoalMode.gain => 'Lean bulk, $pace $unit a week',
      GoalMode.maintain => 'Maintain',
    };
  }

  Widget _phases(AppState s, AppColors c) {
    final active = s.activePhase;
    final today = dateOnly(DateTime.now());
    final shown = [
      for (final p in s.phases)
        if (p.end == null || !p.end!.isBefore(DateTime(today.year, today.month, today.day - 60))) p,
    ];
    return SectionCard(
      title: 'Phases',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            active == null
                ? 'Plan a cut, maintenance or lean bulk on a timeline. While a phase '
                    'is running it sets your goal and pace, and targets switch on '
                    'their own when the next one starts.'
                : 'Your current phase sets the goal and pace above; when it ends, '
                    'the next phase (or your goal above) takes over.',
            style: AppText.quiet(c),
          ),
          const SizedBox(height: 8),
          for (final p in shown)
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _phaseLabel(s, p),
                          style: AppText.body(c).copyWith(
                            fontWeight: identical(p, active) ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        Text(
                          '${shortDate(p.start)} – ${p.end == null ? 'no end date' : shortDate(p.end!)}'
                          '${identical(p, active) ? ' · now' : (p.start.isAfter(today) ? ' · upcoming' : (p.end != null && p.end!.isBefore(today) ? ' · done' : ''))}',
                          style: AppText.quiet(c).copyWith(
                            fontSize: 12,
                            color: identical(p, active) ? c.accent : c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove phase',
                    onPressed: () {
                      s.deletePhase(p);
                      showUndo(context, 'Removed the phase.', () => s.savePhase(p));
                    },
                    icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SmallButton(
            label: 'Add a phase',
            quiet: true,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: c.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              builder: (_) => const _PhaseSheet(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _learned(AppState s, AppColors c) {
    final m = s.learnedMaintenance;
    final (foodDays, weighIns) = s.learnedProgress;
    return SectionCard(
      title: 'Learned maintenance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m == null) ...[
            Text(
              'After about 3 weeks of logging food and weighing in, the app works '
              'out the calories you really maintain at, from what you ate and how '
              'your weight trend moved. Formulas can be off by a few hundred '
              'calories for a given person; this fixes that.',
              style: AppText.body(c),
            ),
            const SizedBox(height: 8),
            Text(
              'In the last $adaptiveWindowDays days: $foodDays of '
              '$adaptiveMinFoodDays days of food logged, $weighIns of '
              '$adaptiveMinWeighIns weigh-ins. The weigh-ins also need to span '
              'at least $adaptiveMinSpanDays days.',
              style: AppText.quiet(c),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  thousands(m.kcal),
                  style: AppText.title(c).copyWith(fontSize: 30, fontWeight: FontWeight.w300),
                ),
                Text(' kcal a day', style: AppText.quiet(c)),
              ],
            ),
            Text(
              'From ${m.foodDays} days of food and ${m.weighIns} weigh-ins in the '
              'last $adaptiveWindowDays days. Days you didn\'t log everything make it '
              'read low, so log fully for the best number.',
              style: AppText.quiet(c),
            ),
            SettingRow(
              divider: false,
              label: 'Use it for my targets',
              note: s.settings.useLearnedMaintenance
                  ? 'Targets use the learned number'
                  : 'Targets use the formula estimate',
              trailing: Toggle(
                label: 'Use learned maintenance',
                value: s.settings.useLearnedMaintenance,
                onChanged: (v) => s.setSettings(s.settings.copyWith(useLearnedMaintenance: v)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metrics(AppState s, AppColors c) {
    final w = s.currentWeightKg;
    final h = s.profile.heightCm;
    final bf = s.goal.bodyFatNowPct;
    final goalBf = s.goal.bodyFatGoalPct;

    if (w == null || h == null || bf == null) {
      return SectionCard(
        title: 'Body metrics',
        child: Text(
          'Add your height, current weight and a body fat estimate to see '
          'BMI, FFMI, lean mass and more.',
          style: AppText.quiet(c),
        ),
      );
    }

    final lean = leanMassKg(w, bf);
    final fat = w - lean;
    final bmiNow = bmi(w, h);
    final ffmi = ffmiNormalized(lean, h);
    final tiles = <(String, String, String)>[];

    String wt(double kg) => '${oneDecimal(_toDisplayWeight(kg))} $_wUnit';

    if (goalBf != null) {
      final goalW = weightAtBodyFat(lean, goalBf);
      tiles.add(('BMI', bmiNow.toStringAsFixed(1),
          '${bmiCategory(bmiNow)}, ${bmi(goalW, h).toStringAsFixed(1)} at goal'));
    } else {
      tiles.add(('BMI', bmiNow.toStringAsFixed(1), bmiCategory(bmiNow)));
    }
    tiles.add(('FFMI (normalized)', ffmi.toStringAsFixed(1),
        '${ffmiCategory(ffmi)}; holds if you keep muscle'));
    tiles.add(('Lean mass', wt(lean), 'Everything that isn\'t fat'));
    if (goalBf != null) {
      final goalFat = weightAtBodyFat(lean, goalBf) - lean;
      tiles.add(('Fat mass', wt(fat), '${wt(goalFat)} at goal'));
      tiles.add((
        'Fat to lose',
        wt(fat - goalFat < 0 ? 0 : fat - goalFat),
        'To reach ${goalBf.round()}% body fat',
      ));
    } else {
      tiles.add(('Fat mass', wt(fat), 'Set a goal body fat to compare'));
    }
    final waist = s.settings.measurementsOn
        ? s.latestMeasurement(MeasureSite.waist)?.valueCm
        : null;
    if (waist != null) {
      tiles.add(('Waist-to-height', waistToHeight(waist, h).toStringAsFixed(2),
          'Under 0.50 is the usual target'));
    }
    tiles.add(('BMR', '${thousands(bmrKatch(lean))} kcal',
        'Katch-McArdle, uses lean mass'));
    final t = s.targets;
    if (t != null) {
      final perLean = _imperial ? t.proteinG / kgToLb(lean) : t.proteinG / lean;
      tiles.add((
        'Protein per $_wUnit lean',
        '${perLean.toStringAsFixed(2)} g',
        '${t.proteinG.round()} g target ÷ lean mass',
      ));
    }

    return SectionCard(
      title: 'Body metrics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              const gap = 8.0;
              final w2 = (box.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (label, value, note) in tiles)
                    SizedBox(
                      width: w2,
                      child: _MetricTile(label: label, value: value, note: note),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'BMI ignores muscle, so it reads high for lifters. FFMI uses lean '
            'mass to show how much muscle you carry for your height. All body '
            'fat numbers are estimates.',
            style: AppText.quiet(c).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ pieces

class _TapBox extends StatelessWidget {
  const _TapBox({
    required this.text,
    required this.placeholder,
    required this.onTap,
  });

  final String text;
  final bool placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: c.background,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: placeholder
                ? AppText.quiet(c).copyWith(fontSize: 16)
                : AppText.body(c).copyWith(fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? c.accent : c.line,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: selected ? 10 : 0,
                  height: selected ? 10 : 0,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.body(c)),
                    Text(detail, style: AppText.quiet(c).copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BodyFatTile extends StatelessWidget {
  const _BodyFatTile({
    required this.asset,
    required this.pct,
    required this.isNow,
    required this.isGoal,
    required this.onTap,
  });

  final String asset;
  final int pct;
  final bool isNow;
  final bool isGoal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ring = isNow ? c.protein : (isGoal ? c.accent : c.accent.withAlpha(0));
    String? badge;
    if (isNow && isGoal) {
      badge = 'Now · Goal';
    } else if (isNow) {
      badge = 'Now';
    } else if (isGoal) {
      badge = 'Goal';
    }

    return Semantics(
      button: true,
      selected: isNow || isGoal,
      label: '$pct percent body fat example${badge == null ? '' : ', $badge'}',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ring, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          asset,
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          gaplessPlayback: true,
                        ),
                        if (badge != null)
                          Positioned(
                            left: 5,
                            top: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isNow ? c.protein : c.accent,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                badge,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isNow || isGoal ? FontWeight.w600 : FontWeight.w400,
                  color: c.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PctSlider extends StatelessWidget {
  const _PctSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double? value;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final v = (value ?? 20).clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(
          label,
          trailing: Text(
            value == null ? 'Not set' : '${value!.round()}%',
            style: AppText.body(c).copyWith(
              fontWeight: FontWeight.w500,
              color: value == null ? c.muted : c.text,
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: c.line,
            thumbColor: color,
            overlayColor: color.withAlpha(30),
            trackHeight: 4,
          ),
          child: Slider(
            value: v,
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: '${v.round()}%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat(this.value, this.label, this.fg, this.soft);

  final String value;
  final String label;
  final Color fg;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.8,
            color: fg,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 13, color: soft)),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.note,
  });

  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.quiet(c).copyWith(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppText.body(c).copyWith(
              fontSize: 19,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(note, style: AppText.quiet(c).copyWith(fontSize: 12)),
        ],
      ),
    );
  }

}

class _PhaseSheet extends StatefulWidget {
  const _PhaseSheet();

  @override
  State<_PhaseSheet> createState() => _PhaseSheetState();
}

class _PhaseSheetState extends State<_PhaseSheet> {
  GoalMode _mode = GoalMode.lose;
  double? _pace;
  DateTime? _start;
  DateTime? _end;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_start != null) return;
    // Starts the day after the last phase ends, or today.
    final s = AppScope.of(context);
    final today = dateOnly(DateTime.now());
    DateTime next = today;
    for (final p in s.phases) {
      final e = p.end;
      if (e != null) {
        final after = DateTime(e.year, e.month, e.day + 1);
        if (after.isAfter(next)) next = after;
      }
    }
    _start = next;
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? _start ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: start ? 'Phase starts' : 'Phase ends (last day)',
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = dateOnly(picked);
      } else {
        _end = dateOnly(picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    final paces = imperial ? const [0.25, 0.5, 1.0, 1.5, 2.0] : const [0.1, 0.25, 0.5, 0.75, 1.0];
    final pace = _pace ?? (imperial ? 1.0 : 0.5);
    final start = _start!;
    final end = _end;
    final badEnd = end != null && end.isBefore(start);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a phase', style: AppText.title(c).copyWith(fontSize: 22)),
            const SizedBox(height: 14),
            Segmented<GoalMode>(
              label: 'Phase type',
              options: const [
                (GoalMode.lose, 'Cut'),
                (GoalMode.maintain, 'Maintain'),
                (GoalMode.gain, 'Lean bulk'),
              ],
              value: _mode,
              onChanged: (v) => setState(() => _mode = v),
            ),
            if (_mode != GoalMode.maintain) ...[
              const SizedBox(height: 14),
              Text('Pace, $unit a week', style: AppText.body(c)),
              const SizedBox(height: 6),
              Segmented<double>(
                label: 'Pace',
                options: [for (final p in paces) (p, _GoalsScreenState._paceText(p))],
                value: paces.contains(pace) ? pace : paces[2],
                onChanged: (v) => setState(() => _pace = v),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SmallButton(
                    label: 'Starts ${shortDate(start)}',
                    quiet: true,
                    onTap: () => _pick(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SmallButton(
                    label: end == null ? 'No end date' : 'Ends ${shortDate(end)}',
                    quiet: true,
                    onTap: () => _pick(false),
                  ),
                ),
              ],
            ),
            if (end != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _end = null),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Remove end date'),
                ),
              ),
            if (badEnd)
              Text('The end date is before the start.', style: AppText.quiet(c).copyWith(color: c.protein)),
            const SizedBox(height: 14),
            SmallButton(
              label: 'Add phase',
              onTap: () {
                if (badEnd) return;
                final kg = _mode == GoalMode.maintain ? 0.0 : (imperial ? lbToKg(pace) : pace);
                s.savePhase(Phase(
                  id: newId('ph'),
                  mode: _mode,
                  paceKgPerWeek: kg,
                  start: start,
                  end: end,
                ));
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
