import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'data/models.dart';
import 'data/store.dart';
import 'screens/lock_screen.dart';
import 'screens/logger_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sleep_page.dart';
import 'screens/weigh_in_screen.dart';
import 'services/ai_engine.dart';
import 'services/auto_backup.dart';
import 'services/backup_folder.dart';
import 'services/device_probe.dart';
import 'services/reminders.dart';
import 'services/services_scope.dart';
import 'services/tips.dart';
import 'services/unlocker.dart';
import 'services/widget_sync.dart';
import 'shell.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class FitApp extends StatefulWidget {
  const FitApp({
    super.key,
    required this.store,
    required this.reminders,
    this.photosDir,
    Unlocker? unlocker,
    HomeWidgetSync? homeWidget,
    AiEngine? ai,
    DeviceProbe? device,
    BackupFolder? backups,
    TipJar? tips,
  })  : unlocker = unlocker ?? const _NoUnlock(),
        homeWidget = homeWidget ?? const _NoWidget(),
        ai = ai ?? const NoAiEngine(),
        device = device ?? const FixedDeviceProbe(),
        backups = backups ?? const NoBackupFolder(),
        tips = tips ?? const NoTipJar();

  /// Tips through the app store; none in tests.
  final TipJar tips;

  /// Where automatic backups go; nowhere in tests.
  final BackupFolder backups;

  /// On-device AI; none in tests.
  final AiEngine ai;

  /// Memory, chip, storage and connection; fixed values in tests.
  final DeviceProbe device;

  final Store store;
  final Reminders reminders;

  /// Fingerprint unlock; a do-nothing stand-in in tests.
  final Unlocker unlocker;

  /// Android home screen widget; a do-nothing stand-in in tests.
  final HomeWidgetSync homeWidget;

  /// Finds the private photos folder. Null in tests, where there's no
  /// phone storage; photo features then stay idle.
  final Future<String> Function()? photosDir;

  @override
  State<FitApp> createState() => _FitAppState();
}

class _FitAppState extends State<FitApp> with WidgetsBindingObserver {
  late final AppState _state = AppState(widget.store, widget.reminders);
  final _navigator = GlobalKey<NavigatorState>();

  // App lock
  bool _locked = false;
  bool _unlockedOnce = false;
  DateTime? _leftAt;

  // Home screen widgets
  StreamSubscription<Uri?>? _widgetClicks;
  String? _lastWidgetText;
  Timer? _widgetDebounce;

  /// The last widget-made change already loaded (see HomeWidgetSync.changedAt).
  int _widgetChangeSeen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.addListener(_watchSaves);
    _state.addListener(_syncThemeTimer);
    _start();
  }

  // ------------------------------------------------------------ save warning

  bool _saveDialogOpen = false;

  /// The problem already warned about (so one failure shows one warning).
  SaveProblem? _warnedFor;

  void _watchSaves() {
    final p = _state.saveProblem;
    if (p == null) {
      _warnedFor = null;
      return;
    }
    if (_saveDialogOpen || _warnedFor == p) return;
    _warnedFor = p;
    WidgetsBinding.instance.addPostFrameCallback((_) => _showSaveWarning());
  }

  /// Warns again even if this problem was already shown (after a retry fails).
  void _warnAgain() {
    _warnedFor = null;
    _watchSaves();
  }

  Future<void> _showSaveWarning() async {
    final ctx = _navigator.currentContext;
    final p = _state.saveProblem;
    if (ctx == null || p == null || _saveDialogOpen) return;
    _saveDialogOpen = true;
    final c = AppColors.of(ctx);
    final full = p == SaveProblem.full;
    final retry = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        backgroundColor: c.surface,
        icon: Icon(full ? Icons.sd_card_alert_outlined : Icons.error_outline_rounded, color: c.protein, size: 32),
        title: Text(full ? 'Your phone is full' : 'Couldn\'t save'),
        content: Text(
          full
              ? 'Pump and Plate couldn\'t save your latest changes because your phone\'s storage is full.\n\n'
                  'Delete things you don\'t need from your phone, like old photos, videos, downloads '
                  'or apps, then tap Try again.\n\n'
                  'Your changes are kept while Pump and Plate stays open, so don\'t close it until they\'re saved.'
              : 'Pump and Plate couldn\'t save your latest changes. Tap Try again.\n\n'
                  'Your changes are kept while Pump and Plate stays open, so don\'t close it until they\'re saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Later'),
          ),
          TextButton(
            key: const ValueKey('save-retry'),
            onPressed: () => Navigator.of(d).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
    _saveDialogOpen = false;
    if (retry != true || !mounted) return;
    final ok = await _state.retrySaves();
    if (!mounted) return;
    final messenger = _navigator.currentContext == null ? null : ScaffoldMessenger.maybeOf(_navigator.currentContext!);
    if (ok) {
      messenger?.showSnackBar(const SnackBar(content: Text('Saved. Everything is up to date.')));
    } else {
      _warnAgain();
    }
  }

  /// Coming back to the app: retry failed saves first (space may have been
  /// freed meanwhile), and only reload from storage if nothing is unsaved;
  /// otherwise the reload would replace unsaved changes with older data.
  Future<void> _onResumeData() async {
    if (_state.saveProblem != null) {
      final ok = await _state.retrySaves();
      if (!mounted) return;
      if (!ok) {
        _warnAgain();
        _pushWidget();
        return;
      }
    }
    await _reloadIfWidgetChanged();
    _pushWidget();
    await _autoBackup();
  }

  /// Saves an automatic backup if one is due. Says so once if it fails for a
  /// new reason; details are in Settings.
  Future<void> _autoBackup() async {
    if (!_state.loaded || _state.saveProblem != null) return;
    final before = _state.settings.backupError;
    final error = await runAutoBackup(_state, widget.backups);
    if (error == null || error == before || !mounted) return;
    final ctx = _navigator.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
      content: Text('Automatic backup didn\'t work. $error'),
      duration: const Duration(seconds: 6),
    ));
  }

  Future<void> _start() async {
    await widget.reminders.init(onOpen: _onNotification);
    await _state.load();
    // With the lock off at startup, turning it on later doesn't lock you
    // out right away.
    _unlockedOnce = !_state.settings.lockEnabled;
    // Once photos can be found, a due automatic backup (with them) runs.
    _findPhotosFolder().whenComplete(() {
      if (mounted) _autoBackup();
    });
    _startHomeWidget();
    final launch = await widget.reminders.launchPayload();
    if (launch != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onNotification(launch == 'reminder' ? null : launch),
      );
    }
  }

  /// Runs in the background so a slow storage lookup can never hold up
  /// startup.
  Future<void> _findPhotosFolder() async {
    final find = widget.photosDir;
    if (find == null) return;
    try {
      _state.setPhotosDir(await find());
    } catch (e) {
      debugPrint('Photos folder unavailable: $e');
    }
  }

  Future<void> _startHomeWidget() async {
    await widget.homeWidget.registerCallbacks();
    _widgetChangeSeen = await widget.homeWidget.changedAt();
    _pushWidget();
    _state.addListener(_scheduleWidgetPush);
    _widgetClicks = widget.homeWidget.clicks.listen(_onWidgetUri, onError: (_) {});
    final uri = await widget.homeWidget.launchUri();
    if (uri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onWidgetUri(uri));
    }
  }

  void _scheduleWidgetPush() {
    _widgetDebounce?.cancel();
    _widgetDebounce = Timer(const Duration(milliseconds: 800), _pushWidget);
  }

  /// Sends what the widgets show. Only while the app is on screen (or
  /// [force], when leaving): in the background, a widget button may have
  /// changed data the app hasn't reloaded yet, and an update from the app's
  /// copy would undo it on the widget.
  void _pushWidget({bool force = false}) {
    final life = WidgetsBinding.instance.lifecycleState;
    if (!force && life != null && life != AppLifecycleState.resumed) return;
    final data = _state.widgetData;
    final text = data.entries.map((e) => '${e.key}=${e.value}').join('|');
    if (text == _lastWidgetText) return;
    _lastWidgetText = text;
    widget.homeWidget.push(data);
  }

  /// Taps on a widget that open the app.
  void _onWidgetUri(Uri? uri) {
    switch (uri?.host) {
      case 'weighin':
        _openWeighIn();
      case 'sleep':
        final nav = _navigator.currentState;
        if (nav != null && _state.settings.onboarded) nav.push(SleepPage.route());
      case 'start':
        _startFromWidget(uri?.queryParameters['w']);
    }
  }

  /// The Today widget's Start: resumes the workout in progress, or starts
  /// the planned one and opens the logger.
  void _startFromWidget(String? workoutId) {
    final nav = _navigator.currentState;
    if (nav == null || !_state.settings.onboarded) return;
    final active = _state.activeSession;
    if (active != null) {
      if (!LoggerScreen.isOpen) nav.push(LoggerScreen.route(active.id));
      return;
    }
    final w = workoutId == null || workoutId.isEmpty ? null : _state.workoutById(workoutId);
    if (w == null) return;
    final x = _state.startSession(w);
    nav.push(LoggerScreen.route(x.id));
  }

  /// A widget button may have changed data in the background (ticked a meal,
  /// set sleep quality). If so, reload so the app shows it.
  Future<void> _reloadIfWidgetChanged() async {
    final at = await widget.homeWidget.changedAt();
    if (at <= _widgetChangeSeen) return;
    _widgetChangeSeen = at;
    await _state.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lockOn = _state.settings.lockEnabled;
    if (state == AppLifecycleState.paused) {
      // Free the AI model's memory while away. Closing it briefly blocks the
      // UI thread, which nobody sees in the background (unlike leaving Chat).
      // An answer still being written finishes first.
      widget.ai.unloadWhenIdle();
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // Something changed just before leaving: update the widgets now.
      if (_widgetDebounce?.isActive ?? false) {
        _widgetDebounce!.cancel();
        _pushWidget(force: true);
      }
      // Time away only counts while unlocked: the fingerprint prompt can
      // briefly background the app on some phones, and that mustn't re-lock
      // it right after a successful unlock.
      if (lockOn && !_showLock) _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (lockOn &&
          left != null &&
          DateTime.now().difference(left).inSeconds >= _state.settings.lockAfterSec) {
        setState(() => _locked = true);
      }
      // A widget may have changed something, and the day may have changed.
      _onResumeData();
      // Dark hours may have started or ended while away.
      if (_state.settings.darkSchedule) {
        setState(() {});
        _syncThemeTimer(force: true);
      }
    }
  }

  void _unlock() => setState(() {
        _locked = false;
        _unlockedOnce = true;
      });

  bool get _showLock =>
      _state.loaded && _state.settings.lockEnabled && (_locked || !_unlockedOnce);

  void _onNotification(String? payload) {
    if (payload == 'rest') {
      _openActiveWorkout();
    } else {
      _openWeighIn();
    }
  }

  void _openWeighIn() {
    final nav = _navigator.currentState;
    if (nav == null || !_state.settings.onboarded) return;
    nav.push(WeighInScreen.route());
  }

  /// Back to the workout from the rest notification. If the logger is
  /// already open, there's nothing to do.
  void _openActiveWorkout() {
    final nav = _navigator.currentState;
    final active = _state.activeSession;
    if (nav == null || active == null || LoggerScreen.isOpen) return;
    nav.push(LoggerScreen.route(active.id));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClicks?.cancel();
    _widgetDebounce?.cancel();
    _state.removeListener(_scheduleWidgetPush);
    _state.removeListener(_watchSaves);
    _state.removeListener(_syncThemeTimer);
    _themeTimer?.cancel();
    _themeCheck?.cancel();
    _state.dispose();
    super.dispose();
  }

  /// Android is short of memory: free the AI model (it reloads when needed).
  @override
  void didHaveMemoryPressure() {
    widget.ai.unloadWhenIdle();
  }

  @override
  void didChangePlatformBrightness() {
    // Repaint when the phone switches between light and dark mode.
    if (_state.settings.followSystem) setState(() {});
  }

  AppPalette _palette() {
    final settings = _state.settings;
    final chosenDark = AppPalette.byId(settings.darkThemeId);
    final dark = chosenDark.isDark ? chosenDark : AppPalette.night;
    if (settings.darkSchedule && isNightTime(DateTime.now(), settings.darkFrom, settings.darkTo)) return dark;
    if (settings.followSystem &&
        WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark) {
      return dark;
    }
    final day = AppPalette.byId(settings.themeId);
    // With a night theme on, the day theme must be a light one, or the
    // switch at the end of dark hours would change nothing.
    if ((settings.darkSchedule || settings.followSystem) && day.isDark) return AppPalette.earth;
    return day;
  }

  // ------------------------------------------------------------ dark at night

  Timer? _themeTimer;
  Timer? _themeCheck;
  String _themeKey = '';
  bool? _shownNight;

  /// With dark hours on, redraws at the next switch (and then the one after).
  /// A one-shot timer can be held up while Android pauses the app, so a
  /// check every 30 seconds also catches a missed switch.
  void _syncThemeTimer({bool force = false}) {
    final st = _state.settings;
    final key = '${st.darkSchedule}|${st.darkFrom}|${st.darkTo}';
    if (!force && key == _themeKey && (_themeTimer != null || !st.darkSchedule)) return;
    _themeKey = key;
    _themeTimer?.cancel();
    _themeTimer = null;
    _themeCheck?.cancel();
    _themeCheck = null;
    if (!st.darkSchedule || st.darkFrom == st.darkTo) return;
    final now = DateTime.now();
    _shownNight = isNightTime(now, st.darkFrom, st.darkTo);
    final wait = nextThemeFlip(now, st.darkFrom, st.darkTo).difference(now) + const Duration(seconds: 1);
    _themeTimer = Timer(wait, () {
      _themeTimer = null;
      if (!mounted) return;
      setState(() {});
      _syncThemeTimer(force: true);
    });
    _themeCheck = Timer.periodic(const Duration(seconds: 30), (_) {
      final cfg = _state.settings;
      if (!mounted || !cfg.darkSchedule) return;
      final night = isNightTime(DateTime.now(), cfg.darkFrom, cfg.darkTo);
      if (night == _shownNight) return;
      setState(() {});
      _syncThemeTimer(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ServicesScope(
        ai: widget.ai,
        device: widget.device,
        backups: widget.backups,
        tips: widget.tips,
        child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          final palette = _palette();
          final reduceMotion = _state.settings.reduceMotion;
          return MaterialApp(
            title: appName,
            navigatorKey: _navigator,
            debugShowCheckedModeBanner: false,
            theme: buildTheme(palette),
            themeAnimationDuration:
                Duration(milliseconds: reduceMotion ? 0 : 250),
            themeAnimationCurve: Curves.easeOutCubic,
            builder: (context, child) {
              Widget app = child!;
              if (reduceMotion) {
                app = MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: true),
                  child: app,
                );
              }
              if (!_showLock) return app;
              return Stack(
                children: [
                  // Keep the app underneath, but out of reach and unread.
                  ExcludeSemantics(child: IgnorePointer(child: app)),
                  Positioned.fill(
                    child: LockScreen(unlocker: widget.unlocker, onUnlocked: _unlock),
                  ),
                ],
              );
            },
            home: !_state.loaded
                ? ColoredBox(color: palette.background)
                : _state.settings.onboarded
                    ? AppShell(palette: palette)
                    : const OnboardingScreen(),
          );
        },
        ),
      ),
    );
  }
}

class _NoUnlock implements Unlocker {
  const _NoUnlock();

  @override
  Future<bool> available() async => false;

  @override
  Future<bool> authenticate() async => false;
}

class _NoWidget implements HomeWidgetSync {
  const _NoWidget();

  @override
  Future<void> push(Map<String, Object> data) async {}

  @override
  Future<void> registerCallbacks() async {}

  @override
  Future<int> changedAt() async => 0;

  @override
  Future<Uri?> launchUri() async => null;

  @override
  Stream<Uri?> get clicks => const Stream<Uri?>.empty();
}
