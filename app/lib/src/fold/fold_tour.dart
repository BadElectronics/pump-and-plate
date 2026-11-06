import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// One page of the folding-phone tour.
class FoldTip {
  const FoldTip(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

/// The tips, in order. The half-folded ones only on phones that can tell
/// when they're half-folded.
List<FoldTip> foldTips({required bool halfFold}) => [
      const FoldTip(
        Icons.view_week_outlined,
        'Made for your folding phone',
        'Unfolded, your section is on the left and the wheel on the right. Tap a slice to open it on the left. '
            'Fold it shut and you carry on where you left off.',
      ),
      const FoldTip(
        Icons.vertical_split_outlined,
        'Two at once',
        'Hold a slice and choose "Open on the right" to see two sections side by side. '
            'The buttons at the top of each side swap them, or bring the wheel back.',
      ),
      if (halfFold) ...const [
        FoldTip(
          Icons.laptop_outlined,
          'Half-folded like a laptop',
          'In a workout, the rest timer sits on the upright half and your sets on the flat half, '
              'so you can log with the phone on the bench.',
        ),
        FoldTip(
          Icons.change_history_outlined,
          'Standing as a tent',
          'Stand it on its edges with the outside screen facing you: you get a big rest timer '
              'and one button to log your next set.',
        ),
      ],
    ];

/// Shown once, the first time the app opens on an unfolded screen.
class FoldTour extends StatefulWidget {
  const FoldTour({super.key, required this.tips});

  final List<FoldTip> tips;

  static Future<void> show(BuildContext context, {required bool halfFold}) => showDialog<void>(
        context: context,
        builder: (_) => FoldTour(tips: foldTips(halfFold: halfFold)),
      );

  @override
  State<FoldTour> createState() => _FoldTourState();
}

class _FoldTourState extends State<FoldTour> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final tip = widget.tips[_page];
    final last = _page == widget.tips.length - 1;
    return AlertDialog(
      key: const ValueKey('fold-tour'),
      backgroundColor: c.surface,
      icon: Icon(tip.icon, color: c.accent, size: 32),
      title: Text(tip.title, textAlign: TextAlign.center, style: AppText.body(c).copyWith(fontSize: 19, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tip.body, textAlign: TextAlign.center, style: AppText.body(c).copyWith(fontSize: 15, height: 1.4)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.tips.length; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? c.accent : c.line),
                ),
            ],
          ),
        ],
      ),
      actions: [
        if (!last)
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
        FilledButton(
          key: const ValueKey('fold-tour-next'),
          onPressed: () => last ? Navigator.of(context).pop() : setState(() => _page++),
          style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent),
          child: Text(last ? 'Got it' : 'Next'),
        ),
      ],
    );
  }
}
