import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Enter or change one night of sleep, filed under [date] (the morning).
class SleepEditor extends StatefulWidget {
  const SleepEditor({
    super.key,
    required this.date,
    required this.onClose,
    this.title = 'Last night\'s sleep',
  });

  final DateTime date;
  final VoidCallback onClose;
  final String title;

  @override
  State<SleepEditor> createState() => _SleepEditorState();
}

class _SleepEditorState extends State<SleepEditor> {
  final _hours = TextEditingController();
  bool _byHours = false;
  int? _bed;
  int? _wake;
  int? _quality;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final s = AppScope.of(context);
    final existing = s.sleepOn(widget.date);
    final last = existing ?? s.latestSleep;
    _bed = last?.bedMinute ?? 23 * 60;
    _wake = last?.wakeMinute ?? 7 * 60;
    _quality = existing?.quality;
    _byHours = existing != null && existing.bedMinute == null;
    final mins = existing?.durationMin;
    _hours.text = mins == null ? '' : oneDecimal(mins / 60);
  }

  @override
  void dispose() {
    _hours.dispose();
    super.dispose();
  }

  String _time(int minuteOfDay) => TimeOfDay(
        hour: minuteOfDay ~/ 60,
        minute: minuteOfDay % 60,
      ).format(context);

  Future<void> _pickTime(bool bed) async {
    final current = (bed ? _bed : _wake) ?? (bed ? 23 * 60 : 7 * 60);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: bed ? 'Bedtime' : 'Wake time',
    );
    if (picked == null) return;
    setState(() {
      final m = picked.hour * 60 + picked.minute;
      if (bed) {
        _bed = m;
      } else {
        _wake = m;
      }
    });
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _save() {
    final s = AppScope.of(context);
    int? duration;
    int? bed;
    int? wake;
    if (_byHours) {
      final h = parseNumber(_hours.text);
      if (h == null || h <= 0 || h > 16) {
        _toast('Enter hours slept, for example 7.5');
        return;
      }
      duration = (h * 60).round();
    } else {
      bed = _bed;
      wake = _wake;
      if (bed == null || wake == null) return;
      duration = sleepMinutes(bed, wake);
      if (duration == null || duration > 16 * 60) {
        _toast('Those times don\'t look right. Check bed and wake times.');
        return;
      }
    }
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    s.logSleep(SleepEntry(
      date: widget.date,
      bedMinute: bed,
      wakeMinute: wake,
      durationMin: duration,
      quality: _quality,
    ));
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final preview = (!_byHours && _bed != null && _wake != null)
        ? sleepMinutes(_bed!, _wake!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(widget.title),
        Segmented<bool>(
          label: 'How to enter sleep',
          options: const [(false, 'Bed and wake'), (true, 'Just hours')],
          value: _byHours,
          onChanged: (v) => setState(() => _byHours = v),
        ),
        const SizedBox(height: 10),
        if (_byHours)
          NumberBox(
            controller: _hours,
            suffix: 'hours',
            semanticLabel: 'Hours slept',
            hint: 'e.g. 7.5',
            onChanged: (_) {},
          )
        else
          Row(
            children: [
              Expanded(
                child: _TimeBox(
                  label: 'Bed',
                  value: _bed == null ? '--' : _time(_bed!),
                  onTap: () => _pickTime(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TimeBox(
                  label: 'Wake',
                  value: _wake == null ? '--' : _time(_wake!),
                  onTap: () => _pickTime(false),
                ),
              ),
            ],
          ),
        if (preview != null) ...[
          const SizedBox(height: 6),
          Text(formatSleep(preview), style: AppText.quiet(c)),
        ],
        const SizedBox(height: 12),
        FieldLabel(
          'Quality (optional)',
          trailing: _quality == null
              ? null
              : GestureDetector(
                  onTap: () => setState(() => _quality = null),
                  child: Text(
                    'Clear',
                    style: AppText.label(c).copyWith(color: c.accent),
                  ),
                ),
        ),
        Row(
          children: [
            for (var q = 1; q <= 5; q++) ...[
              if (q > 1) const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _quality == q,
                  label: 'Quality $q of 5',
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _quality = q);
                    },
                    child: ExcludeSemantics(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _quality == q ? c.text : c.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.line),
                        ),
                        child: Text(
                          '$q',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _quality == q ? c.background : c.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '1 = rough night, 5 = great',
          style: AppText.quiet(c).copyWith(fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SmallButton(
                label: 'Cancel',
                quiet: true,
                onTap: () {
                  FocusScope.of(context).unfocus();
                  widget.onClose();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: SmallButton(label: 'Save sleep', onTap: _save)),
          ],
        ),
      ],
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      label: '$label time, $value',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.background,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text(label, style: AppText.quiet(c)),
                const Spacer(),
                Text(value, style: AppText.body(c).copyWith(fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
