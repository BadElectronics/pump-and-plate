import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../screens/weigh_in_screen.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'sleep_editor.dart';

/// Today's weight and last night's sleep. Both optional; both editable.
class CheckInCard extends StatefulWidget {
  const CheckInCard({super.key});

  @override
  State<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends State<CheckInCard> {
  final _weight = TextEditingController();
  bool _editWeight = false;
  bool _editSleep = false;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  String _time(int minuteOfDay) => TimeOfDay(
        hour: minuteOfDay ~/ 60,
        minute: minuteOfDay % 60,
      ).format(context);

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  // ------------------------------------------------------------ weight

  void _saveWeight(AppState s, bool imperial) {
    final v = parseNumber(_weight.text);
    if (v == null) return;
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

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;

    return SectionCard(
      title: 'Morning check-in',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _weightPart(s, c, imperial),
          const SizedBox(height: 14),
          Container(height: 1, color: c.line),
          const SizedBox(height: 14),
          _sleepPart(s, c),
        ],
      ),
    );
  }

  Widget _weightPart(AppState s, AppColors c, bool imperial) {
    final unit = imperial ? 'lb' : 'kg';
    final today = s.weighInOn(_today);
    double disp(double kg) => imperial ? kgToLb(kg) : kg;

    if (today != null && !_editWeight) {
      final y = s.weighInOn(DateTime(_today.year, _today.month, _today.day - 1));
      String delta = 'Logged for today.';
      if (y != null) {
        final d = disp(today.weightKg) - disp(y.weightKg);
        if (d.abs() < 0.05) {
          delta = 'Same as yesterday.';
        } else {
          delta = '${d > 0 ? '+' : '−'}${oneDecimal(d.abs())} vs yesterday. '
              'Daily numbers bounce; the weekly average is what counts.';
        }
      }
      return _DoneRow(
        title: '${oneDecimal(disp(today.weightKg))} $unit logged',
        detail: delta,
        onEdit: () {
          _weight.text = oneDecimal(disp(today.weightKg));
          setState(() => _editWeight = true);
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(
          'Today\'s weight',
          trailing: GestureDetector(
            onTap: () => Navigator.of(context).push(WeighInScreen.route()),
            child: Text(
              'Keypad',
              style: AppText.label(c).copyWith(color: c.accent),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: NumberBox(
                controller: _weight,
                suffix: unit,
                semanticLabel: 'Today\'s weight',
                hint: s.currentWeightKg == null
                    ? (imperial ? 'e.g. 182.4' : 'e.g. 82.7')
                    : oneDecimal(disp(s.currentWeightKg!)),
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: 8),
            SmallButton(label: 'Save', onTap: () => _saveWeight(s, imperial)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'After the bathroom, before eating or drinking.',
          style: AppText.quiet(c).copyWith(fontSize: 12),
        ),
      ],
    );
  }

  Widget _sleepPart(AppState s, AppColors c) {
    if (_editSleep) {
      return SleepEditor(
        date: _today,
        onClose: () => setState(() => _editSleep = false),
      );
    }
    final today = s.sleepOn(_today);
    if (today == null) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Last night\'s sleep', style: AppText.body(c)),
                Text('Optional', style: AppText.quiet(c).copyWith(fontSize: 12)),
              ],
            ),
          ),
          SmallButton(
            label: 'Add',
            quiet: true,
            onTap: () => setState(() => _editSleep = true),
          ),
        ],
      );
    }
    final parts = <String>[];
    if (today.bedMinute != null && today.wakeMinute != null) {
      parts.add('${_time(today.bedMinute!)} to ${_time(today.wakeMinute!)}');
    }
    if (today.quality != null) parts.add('quality ${today.quality}/5');
    return _DoneRow(
      title: today.durationMin == null
          ? 'Sleep logged'
          : '${formatSleep(today.durationMin!)} of sleep',
      detail: parts.isEmpty ? 'Logged for last night.' : parts.join(', '),
      onEdit: () => setState(() => _editSleep = true),
    );
  }
}

class _DoneRow extends StatelessWidget {
  const _DoneRow({required this.title, required this.detail, required this.onEdit});

  final String title;
  final String detail;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 18, color: c.onAccent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.body(c).copyWith(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(detail, style: AppText.quiet(c)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SmallButton(label: 'Edit', quiet: true, onTap: onEdit),
      ],
    );
  }
}
