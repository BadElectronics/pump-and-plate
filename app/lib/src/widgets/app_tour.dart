import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// One step of the tour: what it says and what lights up on Home.
class TourStep {
  const TourStep(this.title, this.text, {this.spotlight, this.rows = false, this.support = false});

  final String title;
  final String text;

  /// Pie slice to light up (0 Log ... 4 Settings, 5 Chat), or null.
  final int? spotlight;

  /// Light up the weigh-in and sleep rows (the pie fades).
  final bool rows;

  /// The last word: please consider a tip, with a button to the tip jar.
  final bool support;
}

/// The whole tour: one short sentence each, under a minute in total.
const tourSteps = <TourStep>[
  TourStep('Welcome to Pump and Plate', 'A quick look around. It takes under a minute.'),
  TourStep('This is Home', 'Tap a slice to open that part of the app. The Home button on the bar brings you back.'),
  TourStep('Log', 'Weigh-ins, sleep, food, workouts and photos. It shows what\'s due today.', spotlight: 0),
  TourStep('Progress', 'Your weight, strength and sleep charts, and your photos.', spotlight: 1),
  TourStep('Plan', 'Your calendar. Add workouts and meals, then drag them onto days.', spotlight: 2),
  TourStep('Food', 'Grocery lists, recipes and your foods. Scan a barcode to add a food fast.', spotlight: 3),
  TourStep('Settings', 'Themes, reminders and backups. You can replay this tour there too.', spotlight: 4),
  TourStep('Chat', 'Paste a recipe or workout to save it, or chat with the AI on your phone.', spotlight: 5),
  TourStep('Every morning', 'Log your weight and last night\'s sleep right here.', rows: true),
  TourStep(
    'Free for everyone',
    'Pump and Plate has no ads and no paid features. If it helps you, please consider a tip. '
        'It\'s in Settings > Support any time.',
    support: true,
  ),
];

/// The tour card over Home. The first step sits in the middle over a dim
/// background; the rest sit at the top so the pie stays visible.
class AppTour extends StatelessWidget {
  const AppTour({super.key, required this.step, required this.onNext, required this.onSkip, this.onSupport});

  final int step;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  /// Ends the tour and opens the tip jar.
  final VoidCallback? onSupport;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final s = tourSteps[step];
    final first = step == 0;
    final last = step == tourSteps.length - 1;

    final card = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.title, style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(s.text, style: AppText.body(c).copyWith(fontSize: 15, height: 1.4)),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!first)
                Semantics(
                  label: 'Step $step of ${tourSteps.length - 1}',
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        for (var i = 1; i < tourSteps.length; i++)
                          Container(
                            width: i == step ? 14 : 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: i == step ? c.accent : c.line,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              if (!last)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Skip'),
                ),
              if (s.support && onSupport != null)
                TextButton(
                  key: const ValueKey('tour-tip'),
                  onPressed: onSupport,
                  style: TextButton.styleFrom(foregroundColor: c.accent),
                  child: const Text('Tip jar'),
                ),
              const SizedBox(width: 4),
              SmallButton(label: first ? 'Show me' : (last ? 'Done' : 'Next'), onTap: onNext),
            ],
          ),
        ],
      ),
    );

    return Stack(
      children: [
        if (first) Positioned.fill(child: ColoredBox(color: c.background.withAlpha(200))),
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Align(
                alignment: first ? Alignment.center : Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    // The card fading out ignores taps, so a quick double tap
                    // can't press its Next and skip a step.
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: AnimatedBuilder(
                        animation: animation,
                        // Only the current card (fading in or fully shown)
                        // takes taps; one fading out or already faded doesn't.
                        builder: (context, inner) => IgnorePointer(
                          ignoring: animation.status == AnimationStatus.reverse ||
                              animation.status == AnimationStatus.dismissed,
                          child: inner,
                        ),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(step), child: card),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
