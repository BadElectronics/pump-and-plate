import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Shown once, the first time the app opens. Every step can be skipped.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _feet = TextEditingController();
  final _inches = TextEditingController();
  final _cm = TextEditingController();
  final _weight = TextEditingController();
  final _target = TextEditingController();
  final _nickname = TextEditingController();
  bool _remind = true;
  int _remindAt = 6 * 60 + 30;

  @override
  void dispose() {
    for (final c in [_feet, _inches, _cm, _weight, _target, _nickname]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _imperial(AppState s) => s.settings.units == Units.imperial;

  void _saveAboutYou(AppState s) {
    final imperial = _imperial(s);
    double? heightCm;
    if (imperial) {
      final ft = parseNumber(_feet.text);
      final inch = parseNumber(_inches.text) ?? 0;
      if (ft != null && ft >= 3 && ft <= 8 && inch >= 0 && inch < 12) {
        heightCm = inchToCm(ft * 12 + inch);
      }
    } else {
      final cm = parseNumber(_cm.text);
      if (cm != null && cm >= 100 && cm <= 250) heightCm = cm;
    }
    if (heightCm != null) s.setProfile(s.profile.copyWith(heightCm: heightCm));
    final w = parseNumber(_weight.text);
    if (w != null) {
      final kg = imperial ? lbToKg(w) : w;
      if (kg >= 30 && kg <= 350) s.logWeight(kg, source: 'setup');
    }
  }

  Future<void> _finish(AppState s) async {
    final t = parseNumber(_target.text);
    if (t != null) {
      final kg = _imperial(s) ? lbToKg(t) : t;
      if (kg >= 30 && kg <= 350) s.setGoal(s.goal.copyWith(targetWeightKg: kg));
    }
    int? reminder;
    if (_remind) {
      final allowed = await s.reminders.requestPermission();
      if (allowed) reminder = _remindAt;
    }
    s.setSettings(s.settings.copyWith(onboarded: true, reminderMinute: reminder));
  }

  void _saveNickname(AppState s) {
    final n = _nickname.text.trim();
    s.setSettings(s.settings.copyWith(
      nicknameAsked: true,
      nickname: n.isEmpty ? s.settings.nickname : n,
    ));
  }

  void _skip(AppState s) {
    _saveNickname(s);
    s.setSettings(s.settings.copyWith(onboarded: true));
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

  Future<void> _pickReminder() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _remindAt ~/ 60, minute: _remindAt % 60),
      helpText: 'Reminder time',
    );
    if (picked != null) setState(() => _remindAt = picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final pages = [_welcome, _aboutYou, _goal];

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _step ? 22 : 8,
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _step ? c.accent : c.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _skip(s),
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    child: const Text('Skip setup'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: pages[_step](s, c),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame({
    required AppColors c,
    required String title,
    required String intro,
    required List<Widget> children,
    required String button,
    required VoidCallback onNext,
    VoidCallback? onBack,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text(title, style: AppText.title(c).copyWith(fontSize: 32)),
        const SizedBox(height: 10),
        Text(intro, style: AppText.body(c).copyWith(color: c.muted, fontSize: 16)),
        const SizedBox(height: 24),
        ...children,
        const SizedBox(height: 28),
        Row(
          children: [
            if (onBack != null) ...[
              Expanded(child: SmallButton(label: 'Back', quiet: true, onTap: onBack)),
              const SizedBox(width: 8),
            ],
            Expanded(flex: 2, child: SmallButton(label: button, onTap: onNext)),
          ],
        ),
      ],
    );
  }

  Widget _welcome(AppState s, AppColors c) {
    return _frame(
      c: c,
      title: 'Welcome to $appName.',
      intro: 'Track your weight, sleep and goals in one quiet place. Everything '
          'stays on this phone; there\'s no account.',
      children: [
        const FieldLabel('Nickname (optional)'),
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
            controller: _nickname,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            cursorColor: c.accent,
            style: AppText.body(c).copyWith(fontSize: 16),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterText: '',
              hintText: 'What should we call you?',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Units'),
        Segmented<Units>(
          label: 'Units',
          options: const [(Units.imperial, 'lb, ft, in'), (Units.metric, 'kg, cm')],
          value: s.settings.units,
          onChanged: (v) => s.setSettings(s.settings.copyWith(units: v)),
        ),
      ],
      button: 'Continue',
      onNext: () {
        _saveNickname(s);
        setState(() => _step = 1);
      },
    );
  }

  Widget _aboutYou(AppState s, AppColors c) {
    final imperial = _imperial(s);
    final p = s.profile;
    return _frame(
      c: c,
      title: 'About you',
      intro: 'Used for your calorie and protein targets. You can change any of '
          'this later in Plan.',
      children: [
        const FieldLabel('Birthday'),
        GestureDetector(
          onTap: () => _pickBirthday(s),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              p.birthday == null ? 'Set your birthday' : longDate(p.birthday!),
              style: (p.birthday == null ? AppText.quiet(c) : AppText.body(c))
                  .copyWith(fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Height'),
        if (imperial)
          Row(
            children: [
              Expanded(
                child: NumberBox(
                  controller: _feet,
                  suffix: 'ft',
                  decimal: false,
                  semanticLabel: 'Height, feet',
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NumberBox(
                  controller: _inches,
                  suffix: 'in',
                  decimal: false,
                  semanticLabel: 'Height, inches',
                  onChanged: (_) {},
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
            onChanged: (_) {},
          ),
        const SizedBox(height: 14),
        const FieldLabel('Current weight'),
        NumberBox(
          controller: _weight,
          suffix: imperial ? 'lb' : 'kg',
          semanticLabel: 'Current weight',
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        const FieldLabel('Sex (used by the calorie formula)'),
        Segmented<Sex>(
          label: 'Sex',
          options: const [(Sex.male, 'Male'), (Sex.female, 'Female')],
          value: p.sex,
          onChanged: (v) => s.setProfile(p.copyWith(sex: v)),
        ),
      ],
      button: 'Continue',
      onBack: () => setState(() => _step = 0),
      onNext: () {
        FocusScope.of(context).unfocus();
        _saveAboutYou(s);
        setState(() => _step = 2);
      },
    );
  }

  Widget _goal(AppState s, AppColors c) {
    final imperial = _imperial(s);
    return _frame(
      c: c,
      title: 'Your goal',
      intro: 'Pick a direction and a target. Pace, protein and body fat can be '
          'fine-tuned in Plan.',
      children: [
        Segmented<GoalMode>(
          label: 'Goal type',
          options: const [
            (GoalMode.lose, 'Lose'),
            (GoalMode.maintain, 'Maintain'),
            (GoalMode.gain, 'Gain'),
          ],
          value: s.goal.mode,
          onChanged: (v) => s.setGoal(s.goal.copyWith(mode: v)),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Target weight (optional)'),
        NumberBox(
          controller: _target,
          suffix: imperial ? 'lb' : 'kg',
          semanticLabel: 'Target weight',
          onChanged: (_) {},
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              SettingRow(
                divider: false,
                label: 'Remind me each morning',
                note: 'A gentle nudge to weigh in. Skipped once you have.',
                trailing: Toggle(
                  label: 'Remind me each morning',
                  value: _remind,
                  onChanged: (v) => setState(() => _remind = v),
                ),
              ),
              if (_remind)
                SettingRow(
                  label: 'Time',
                  trailing: TextButton(
                    onPressed: _pickReminder,
                    style: TextButton.styleFrom(foregroundColor: c.accent),
                    child: Text(
                      TimeOfDay(hour: _remindAt ~/ 60, minute: _remindAt % 60)
                          .format(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      button: 'Finish',
      onBack: () => setState(() => _step = 1),
      onNext: () {
        FocusScope.of(context).unfocus();
        _finish(s);
      },
    );
  }
}
