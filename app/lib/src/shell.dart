import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/chat_screen.dart';
import 'screens/food_screen.dart';
import 'screens/home_screen.dart';
import 'screens/log_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/support_screen.dart';
import 'state/app_state.dart';
import 'theme/tokens.dart';
import 'widgets/app_tour.dart';
import 'widgets/common.dart';

/// Home is the pie. Picking a slice folds the pie into a tab bar and opens
/// that section; the bar's Home button folds everything back.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.palette});

  final AppPalette palette;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with SingleTickerProviderStateMixin {
  late final AnimationController _fold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 320),
  );

  /// The open section (0 Log, 1 Progress, 2 Plan, 3 Food, 4 Settings,
  /// 5 Chat), or null on Home.
  int? _section;
  int _planSection = 0;
  int _foodSection = 0;

  /// Bumped to ask the calendar to open its Add meals tray.
  int _mealsTick = 0;

  /// True while folding back to Home.
  bool _returning = false;

  /// The app tour step on screen, or null.
  int? _tourStep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeAskNickname();
      _maybeStartTour();
    });
  }

  @override
  void dispose() {
    _fold.dispose();
    super.dispose();
  }

  /// Asks once for an (optional) nickname on installs from before it existed.
  Future<void> _maybeAskNickname() async {
    if (!mounted) return;
    final s = AppScope.of(context);
    if (!s.settings.onboarded || s.settings.nicknameAsked) return;
    final name = await askNickname(context, firstTime: true);
    final latest = s.settings;
    s.setSettings(latest.copyWith(
      nicknameAsked: true,
      nickname: (name == null || name.isEmpty) ? latest.nickname : name,
    ));
  }

  /// Shows the tour once, the first time Home appears.
  void _maybeStartTour() {
    if (!mounted) return;
    final s = AppScope.of(context);
    if (!s.settings.onboarded || s.settings.tourSeen || _section != null) return;
    setState(() => _tourStep = 0);
  }

  void _tourNext() {
    final step = _tourStep;
    if (step == null) return;
    if (step >= tourSteps.length - 1) {
      _endTour();
    } else {
      HapticFeedback.selectionClick();
      setState(() => _tourStep = step + 1);
    }
  }

  void _endTour() {
    final s = AppScope.of(context);
    if (!s.settings.tourSeen) s.setSettings(s.settings.copyWith(tourSeen: true));
    setState(() => _tourStep = null);
  }

  /// From Settings: back to Home, then the tour from the start.
  Future<void> _replayTour() async {
    await _home();
    if (mounted) setState(() => _tourStep = 0);
  }

  Future<void> _open(int i) async {
    if (_fold.isAnimating) return;
    HapticFeedback.selectionClick();
    // Home stays built in the background, so let go of any field there.
    FocusScope.of(context).unfocus();
    final quick = MediaQuery.of(context).disableAnimations;
    _fold.duration = Duration(milliseconds: quick ? 150 : 420);
    _fold.reverseDuration = Duration(milliseconds: quick ? 120 : 320);
    setState(() {
      _section = i;
      _returning = false;
    });
    await _fold.forward(from: 0);
  }

  Future<void> _home() async {
    if (_fold.isAnimating || _section == null) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _returning = true);
    await _fold.reverse();
    if (mounted) {
      setState(() {
        _section = null;
        _returning = false;
      });
    }
  }

  void _switch(int i) {
    if (i == _section) return;
    HapticFeedback.selectionClick();
    setState(() => _section = i);
  }

  void _addMealsInPlan() {
    setState(() {
      _planSection = 0;
      _mealsTick++;
      _section = 2;
    });
  }

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const LogScreen();
      case 1:
        return const ProgressScreen();
      case 2:
        return PlanScreen(
          section: _planSection,
          onSection: (v) => setState(() => _planSection = v),
          mealsTick: _mealsTick,
        );
      case 3:
        return FoodScreen(
          section: _foodSection,
          onSection: (v) => setState(() => _foodSection = v),
          onAddMeals: _addMealsInPlan,
        );
      case 4:
        return SettingsScreen(onReplayTour: _replayTour);
      default:
        return const ChatScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom > 0;
    const barHeight = 72.0;
    final barBottom = 14 + mq.padding.bottom;
    final barSpace = keyboard ? 0.0 : barHeight + barBottom + 4;
    final overlay = widget.palette.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    final tour = _tourStep;

    // Built once per change (not on every animation frame): the fold only
    // moves and fades these, so Flutter can skip rebuilding what's inside.
    final openSection = _section;
    final pageView = openSection == null
        ? null
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(key: ValueKey<int>(openSection), child: _page(openSection)),
          );
    final homeView = IgnorePointer(
      ignoring: tour != null,
      child: HomeScreen(
        fold: _fold,
        selected: _returning ? null : openSection,
        onPick: _open,
        returning: _returning,
        tourStep: tour,
      ),
    );
    final barView = _TabBar(index: openSection ?? 0, onSelect: _switch, onHome: _home);

    return PopScope(
      canPop: _section == null && tour == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back skips the tour, or folds a section back to Home.
        if (_tourStep != null) {
          _endTour();
        } else {
          _home();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: c.background,
        ),
        child: Scaffold(
          backgroundColor: c.background,
          body: AnimatedBuilder(
            animation: _fold,
            builder: (context, _) {
              final t = _fold.value;
              final page = Curves.easeOut.transform(((t - 0.5) / 0.5).clamp(0.0, 1.0));
              final bar = Curves.easeOutCubic.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));
              return Stack(
                children: [
                  if (pageView != null && t > 0)
                    Positioned.fill(
                      bottom: barSpace,
                      child: IgnorePointer(
                        ignoring: t < 1,
                        child: Opacity(
                          opacity: page,
                          child: Transform.translate(
                            offset: Offset(0, 16 * (1 - page)),
                            child: pageView,
                          ),
                        ),
                      ),
                    ),
                  // Home stays built (hidden, animations paused) while a
                  // section is open, so coming back doesn't have to rebuild
                  // it on the first frame, which caused a visible hitch.
                  Positioned.fill(
                    child: Offstage(
                      offstage: t >= 1,
                      child: TickerMode(enabled: t < 1, child: homeView),
                    ),
                  ),
                  if (tour != null && t == 0)
                    Positioned.fill(child: AppTour(
                      step: tour,
                      onNext: _tourNext,
                      onSkip: _endTour,
                      onSupport: () {
                        _endTour();
                        Navigator.of(context).push(SupportScreen.route());
                      },
                    )),
                  if (t > 0 && !keyboard)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: barBottom,
                      height: barHeight,
                      child: IgnorePointer(
                        ignoring: t < 1,
                        child: Opacity(
                          opacity: bar,
                          child: Transform(
                            alignment: Alignment.bottomCenter,
                            transform: Matrix4.identity()
                              ..translate(0.0, 40 * (1 - bar))
                              ..scale(0.6 + 0.4 * bar, 1.0),
                            child: barView,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Home button plus the six sections. The open one is highlighted and a
/// touch larger.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect, required this.onHome});

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final items = [...appSections, chatSection];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Home',
            child: GestureDetector(
              onTap: onHome,
              child: Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(color: c.text, shape: BoxShape.circle),
                child: Icon(Icons.home_rounded, size: 20, color: c.background),
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                label: items[i].label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: ExcludeSemantics(
                    child: AnimatedScale(
                      scale: i == index ? 1.05 : 1,
                      duration: const Duration(milliseconds: 160),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: i == index ? c.accent.withAlpha(38) : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(items[i].icon, size: i == index ? 21 : 19, color: i == index ? c.accent : c.muted),
                            const SizedBox(height: 3),
                            Padding(
                              // Keeps longer labels ("Progress") off the edges.
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  items[i].label,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: i == index ? 10 : 9.5,
                                    letterSpacing: -0.1,
                                    fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                                    color: i == index ? c.text : c.muted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
