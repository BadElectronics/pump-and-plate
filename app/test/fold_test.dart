import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/app.dart';
import 'package:fitapp/src/calc/calc.dart';
import 'package:fitapp/src/data/models.dart';
import 'package:fitapp/src/data/store.dart';
import 'package:fitapp/src/fold/fold.dart';
import 'package:fitapp/src/screens/food_screen.dart';
import 'package:fitapp/src/screens/logger_screen.dart';
import 'package:fitapp/src/screens/progress_screen.dart';
import 'package:fitapp/src/services/reminders.dart';
import 'package:fitapp/src/widgets/pie_menu.dart';

// Screen sizes from each phone's published resolution and density.
const _fold8Open = Size(933, 704); // Galaxy Z Fold 8, unfolded (opens wide)
const _fold8Cover = Size(475, 751);
const _ultraOpen = Size(860, 954); // Galaxy Z Fold 8 Ultra, unfolded
const _duoOpen = Size(890, 626); // iPhone Duo, unfolded (no fold reported)
const _ultraTent = Size(955, 409); // Ultra's outside screen, turned sideways

MediaQueryData _mq(Size size, [List<DisplayFeature> features = const []]) =>
    MediaQueryData(size: size, displayFeatures: features);

DisplayFeature _foldDown(Size size, {double width = 0, DisplayFeatureState state = DisplayFeatureState.postureFlat}) =>
    DisplayFeature(
      bounds: Rect.fromLTWH(size.width / 2 - width / 2, 0, width, size.height),
      type: DisplayFeatureType.fold,
      state: state,
    );

DisplayFeature _foldAcross(Size size) => DisplayFeature(
      bounds: Rect.fromLTWH(0, size.height / 2, size.width, 0),
      type: DisplayFeatureType.fold,
      state: DisplayFeatureState.postureHalfOpened,
    );

const _settings = AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true, foldTourSeen: true);

Future<MemoryStore> _app(WidgetTester tester, Size size,
    {List<DisplayFeature> features = const [], AppSettings settings = _settings, StoredData? data}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.displayFeatures = features;
  addTearDown(tester.view.reset);
  final store = MemoryStore(data ?? StoredData(settings: settings));
  await tester.pumpWidget(FitApp(store: store, reminders: NoopReminders()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return store;
}

Finder _slice(String label) => find.descendant(of: find.byType(PieMenu), matching: find.text(label));

void main() {
  setUp(() => FoldLayout.enabled = true);
  tearDown(() {
    FoldLayout.enabled = false;
    Hinge.angle.value = null;
  });

  group('which layout', () {
    test('Fold 8 unfolded: two panes, split on the fold', () {
      final f = FoldLayout.of(_mq(_fold8Open, [_foldDown(_fold8Open)]));
      expect(f.mode, FoldMode.twoPane);
      expect(f.split, _fold8Open.width / 2);
    });
    test('Fold 8 folded: the ordinary phone layout, kept in portrait', () {
      expect(FoldLayout.of(_mq(_fold8Cover)).mode, FoldMode.phone);
      expect(FoldLayout.rotates(_mq(_fold8Cover), null), isFalse);
      expect(FoldLayout.rotates(_mq(_ultraOpen), null), isTrue);
    });
    test('Ultra half-folded with the fold across: laptop, top half upright', () {
      final f = FoldLayout.of(_mq(const Size(954, 860), [_foldAcross(const Size(954, 860))]));
      expect(f.mode, FoldMode.laptop);
      expect(f.split, 430);
    });
    test('iPhone Duo reports no fold: two panes split down the middle', () {
      final f = FoldLayout.of(_mq(_duoOpen));
      expect(f.mode, FoldMode.twoPane);
      expect(f.split, 445);
    });
    test('outside screen turned sideways while half-open: tent', () {
      expect(FoldLayout.of(_mq(_ultraTent), hingeAngle: 90).mode, FoldMode.tent);
      expect(FoldLayout.rotates(_mq(const Size(409, 955)), 90), isTrue);
      // Not half-open (no hinge sensor, or flat): just a short screen.
      expect(FoldLayout.of(_mq(_ultraTent)).mode, FoldMode.phone);
      expect(FoldLayout.of(_mq(_ultraTent), hingeAngle: 180).mode, FoldMode.phone);
    });
    test('pop-ups keep to one side: the flat fold gets a width', () {
      final mq = FoldLayout.withPaneDivider(_mq(_fold8Open, [_foldDown(_fold8Open)]));
      final divider = mq.displayFeatures.single;
      expect(divider.bounds.width, greaterThan(0));
      expect(divider.bounds.center.dx, closeTo(_fold8Open.width / 2, 0.01));
      // The iPhone Duo gets one down the middle.
      expect(FoldLayout.withPaneDivider(_mq(_duoOpen)).displayFeatures.single.bounds.center.dx, closeTo(445, 0.01));
      // A phone is left alone.
      expect(FoldLayout.withPaneDivider(_mq(_fold8Cover)).displayFeatures, isEmpty);
    });
    test('off in ordinary tests', () {
      FoldLayout.enabled = false;
      expect(FoldLayout.of(_mq(_fold8Open)).mode, FoldMode.phone);
    });
  });

  group('the app unfolded', () {
    testWidgets('opens on Progress, with the wheel on the right', (tester) async {
      await _app(tester, _fold8Open, features: [_foldDown(_fold8Open)]);
      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(find.byType(PieMenu), findsOneWidget);
      expect(tester.getTopLeft(find.byType(PieMenu)).dx, greaterThan(_fold8Open.width / 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tab open on the folded phone stays open when it unfolds', (tester) async {
      await _app(tester, _fold8Cover);
      await tester.tap(_slice('Food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(FoodScreen), findsOneWidget);
      // Unfold.
      tester.view.physicalSize = _fold8Open;
      tester.view.displayFeatures = [_foldDown(_fold8Open)];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FoodScreen), findsOneWidget);
      expect(find.byType(ProgressScreen), findsNothing);
      expect(find.byType(PieMenu), findsOneWidget);
      // Fold it again: still Food.
      tester.view.physicalSize = _fold8Cover;
      tester.view.displayFeatures = const [];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FoodScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap a slice: it opens on the left, the wheel stays', (tester) async {
      await _app(tester, _duoOpen);
      await tester.tap(_slice('Food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FoodScreen), findsOneWidget);
      expect(find.byType(PieMenu), findsOneWidget);
      expect(tester.getTopLeft(find.byType(FoodScreen)).dx, lessThan(10));
    });

    testWidgets('hold a slice to open it on the right, then swap and bring the wheel back', (tester) async {
      await _app(tester, _ultraOpen, features: [_foldDown(_ultraOpen)]);
      await tester.longPress(_slice('Food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Open Food on the right'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(find.byType(FoodScreen), findsOneWidget);
      expect(find.byType(PieMenu), findsNothing);
      expect(tester.getTopLeft(find.byType(FoodScreen)).dx, greaterThan(_ultraOpen.width / 2 - 1));

      await tester.tap(find.byKey(const ValueKey('swap-left')));
      await tester.pump();
      expect(tester.getTopLeft(find.byType(FoodScreen)).dx, lessThan(10));

      await tester.tap(find.byKey(const ValueKey('wheel-right')));
      await tester.pump();
      expect(find.byType(PieMenu), findsOneWidget);
      expect(find.byType(FoodScreen), findsOneWidget);
      expect(find.byType(ProgressScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the first time it opens unfolded, a short tour; only once', (tester) async {
      final store = await _app(tester, _fold8Open,
          features: [_foldDown(_fold8Open)], settings: const AppSettings(onboarded: true, nicknameAsked: true, tourSeen: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('fold-tour')), findsOneWidget);
      expect(find.text('Made for your folding phone'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fold-tour-next')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Two at once'), findsOneWidget);
      // No hinge sensor here, so two tips and done.
      await tester.tap(find.byKey(const ValueKey('fold-tour-next')));
      // The fade-out starts on the next frame, runs, then the dialog goes.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      // Only one tour was ever opened.
      expect(find.text('Made for your folding phone'), findsNothing);
      expect(find.text('Two at once'), findsNothing);
      expect(find.byKey(const ValueKey('fold-tour')), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect((await store.load()).settings.foldTourSeen, isTrue);
    });

    testWidgets('a pop-up opens on one side of the fold, not across it', (tester) async {
      await _app(tester, _fold8Open, features: [_foldDown(_fold8Open)]);
      showDialog<void>(
        context: tester.element(find.byType(PieMenu)),
        builder: (_) => const AlertDialog(key: ValueKey('probe'), content: Text('Hello')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final box = tester.getRect(find.byKey(const ValueKey('probe')));
      expect(box.right, lessThanOrEqualTo(_fold8Open.width / 2));
    });
  });

  group('workouts', () {
    const plan = Workout(
      id: 'w1',
      name: 'Push',
      items: [WorkoutItem(exerciseId: 'bench_press', sets: 3, repsLow: 6, repsHigh: 10, loadKg: 100, restSec: 120)],
    );
    Session live() => Session(
          id: 's1',
          date: dateOnly(DateTime.now()),
          name: 'Push',
          workoutId: 'w1',
          startedAt: DateTime.now(),
          sets: [
            SetEntry(exerciseId: 'bench_press', weightKg: 100, reps: 8, done: true, restStartedAt: DateTime.now()),
            const SetEntry(exerciseId: 'bench_press'),
            const SetEntry(exerciseId: 'bench_press'),
          ],
        );

    Future<MemoryStore> open(WidgetTester tester, Size size, {List<DisplayFeature> features = const []}) async {
      final store = await _app(tester, size,
          features: features, data: StoredData(settings: _settings, workouts: const [plan], sessions: [live()]));
      tester.state<NavigatorState>(find.byType(Navigator).first).push(LoggerScreen.route('s1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return store;
    }

    testWidgets('unfolded: sets on the left, the rest timer and the next set on the right', (tester) async {
      await open(tester, _fold8Open, features: [_foldDown(_fold8Open)]);
      expect(find.byKey(const ValueKey('fold-side')), findsOneWidget);
      expect(find.byKey(const ValueKey('fold-rest')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('fold-side'))).dx, greaterThan(_fold8Open.width / 2));
      expect(find.text('Next'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('half-folded like a laptop: the rest timer on the upright half', (tester) async {
      const size = Size(954, 860);
      await open(tester, size, features: [_foldAcross(size)]);
      final rest = tester.getRect(find.byKey(const ValueKey('fold-rest')));
      expect(rest.bottom, lessThanOrEqualTo(size.height / 2));
      expect(find.byKey(const ValueKey('fold-side')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('standing as a tent: a big timer and one button logs the next set', (tester) async {
      Hinge.angle.value = 90;
      final store = await open(tester, _ultraTent);
      expect(find.byKey(const ValueKey('tent-timer')), findsOneWidget);
      expect(find.byKey(const ValueKey('tent-reps')), findsOneWidget);
      await tester.tap(find.byTooltip('One rep more'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tent-log')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final x = (await store.load()).sessions.single;
      expect(x.sets[1].done, isTrue);
      expect(x.sets[1].reps, 7); // the plan's 6, plus one
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a phone keeps the ordinary layout', (tester) async {
      await open(tester, _fold8Cover);
      expect(find.byKey(const ValueKey('fold-side')), findsNothing);
      expect(find.byKey(const ValueKey('tent-timer')), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
