import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calc/calc.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Full-screen number pad. The morning reminder (build 1.3) opens this.
class WeighInScreen extends StatefulWidget {
  const WeighInScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const WeighInScreen(),
        fullscreenDialog: true,
      );

  @override
  State<WeighInScreen> createState() => _WeighInScreenState();
}

class _WeighInScreenState extends State<WeighInScreen> {
  String _entry = '';
  bool _started = false;

  void _press(String key, String fallback) {
    HapticFeedback.selectionClick();
    setState(() {
      var cur = _started ? _entry : '';
      if (key == 'del') {
        cur = (_started ? _entry : fallback);
        _entry = cur.isEmpty ? '' : cur.substring(0, cur.length - 1);
        _started = true;
        return;
      }
      if (key == '.') {
        if (!cur.contains('.')) cur = (cur.isEmpty ? '0' : cur) + '.';
      } else {
        final parts = cur.split('.');
        if (parts.length == 2 && parts[1].isNotEmpty) return;
        if (parts.length == 1 && parts[0].length >= 3) return;
        cur += key;
      }
      _entry = cur;
      _started = true;
    });
  }

  void _save(AppState s, bool imperial) {
    final v = parseNumber(_started ? _entry : _fallback(s, imperial));
    if (v == null) return;
    final kg = imperial ? lbToKg(v) : v;
    if (kg < 30 || kg > 350) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That number looks off. Check it and try again.')),
      );
      return;
    }
    s.logWeight(kg, source: 'keypad');
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  String _fallback(AppState s, bool imperial) {
    final w = s.currentWeightKg;
    if (w == null) return '';
    return oneDecimal(imperial ? kgToLb(w) : w);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final unit = imperial ? 'lb' : 'kg';
    final shown = _started ? _entry : _fallback(s, imperial);
    final now = DateTime.now();
    final yesterday = s.weighInOn(DateTime(now.year, now.month, now.day - 1));
    final avg = s.weeklyAverageKg;
    final context1 = [
      if (yesterday != null)
        'Yesterday ${oneDecimal(imperial ? kgToLb(yesterday.weightKg) : yesterday.weightKg)}',
      if (avg != null) '7-day avg ${oneDecimal(imperial ? kgToLb(avg) : avg)}',
    ].join('   ');

    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'];

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: c.text),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                now.hour < 12 ? 'Good morning.' : 'Weigh-in',
                style: AppText.title(c).copyWith(fontSize: 32),
              ),
              const SizedBox(height: 8),
              Text(
                'Weigh in after the bathroom, before you eat or drink.',
                style: AppText.body(c).copyWith(color: c.muted),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    shown.isEmpty ? '0' : shown,
                    style: TextStyle(
                      fontSize: 84,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -3,
                      color: _started || shown.isEmpty ? c.text : c.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(unit, style: AppText.body(c).copyWith(color: c.muted, fontSize: 20)),
                ],
              ),
              if (context1.isNotEmpty)
                Text(
                  context1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 13,
                    color: c.muted,
                  ),
                ),
              const Spacer(),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.9,
                children: [
                  for (final k in keys)
                    Semantics(
                      button: true,
                      label: k == 'del' ? 'Delete digit' : (k == '.' ? 'Decimal point' : k),
                      child: GestureDetector(
                        onTap: () => _press(k, _fallback(s, imperial)),
                        child: ExcludeSemantics(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: k == 'del'
                                ? Icon(Icons.backspace_outlined, color: c.text, size: 22)
                                : Text(k, style: AppText.body(c).copyWith(fontSize: 24)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _save(s, imperial),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Save weight',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: c.onAccent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
