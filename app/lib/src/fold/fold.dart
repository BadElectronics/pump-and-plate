import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How the screen is being used.
enum FoldMode {
  /// An ordinary phone screen, or a folding phone's outside screen.
  phone,

  /// An unfolded (or tablet-sized) screen, split into two panes side by
  /// side on the fold.
  twoPane,

  /// Half-folded like a laptop: the fold runs across the screen, the top
  /// half upright and the bottom half flat.
  laptop,

  /// Half-folded like a tent, with only the outside screen showing,
  /// turned sideways.
  tent,
}

/// The layout for the current screen and fold.
@immutable
class FoldLayout {
  const FoldLayout(this.mode, {this.split = 0, this.gap = 0});

  final FoldMode mode;

  /// [FoldMode.twoPane]: the left pane's width. [FoldMode.laptop]: the top
  /// half's height.
  final double split;

  /// The fold's own width (or height), which nothing is drawn under.
  final double gap;

  /// Off in most tests, whose wide test screen would otherwise count as an
  /// unfolded phone. The foldable tests turn it on.
  static bool enabled = true;

  /// Narrowest a window can be for two panes, as Android's own guidance has it.
  static const double minWidth = 600;
  static const double minHeight = 480;

  static bool _halfOpen(double? angle) => angle != null && angle > 30 && angle < 150;

  /// The layout for this screen. [hingeAngle] comes from [Hinge.angle].
  static FoldLayout of(MediaQueryData mq, {double? hingeAngle}) {
    if (!enabled) return const FoldLayout(FoldMode.phone);
    final size = mq.size;
    Rect? down;
    Rect? across;
    for (final f in mq.displayFeatures) {
      if (f.type == DisplayFeatureType.cutout) continue;
      final b = f.bounds;
      final fullHeight = b.top <= 1 && b.bottom >= size.height - 1;
      final fullWidth = b.left <= 1 && b.right >= size.width - 1;
      if (fullHeight && b.width < size.width / 4) down = b;
      if (fullWidth && b.height < size.height / 4 && f.state == DisplayFeatureState.postureHalfOpened) {
        across = b;
      }
    }
    final a = across;
    if (a != null) return FoldLayout(FoldMode.laptop, split: a.top, gap: a.height);
    // Half-open with only the outside screen on, turned sideways: a tent.
    if (_halfOpen(hingeAngle) && size.shortestSide < minWidth && size.width > size.height) {
      return const FoldLayout(FoldMode.tent);
    }
    if (size.width >= minWidth && size.height >= minHeight) {
      final d = down;
      if (d != null) return FoldLayout(FoldMode.twoPane, split: d.left, gap: d.width);
      return FoldLayout(FoldMode.twoPane, split: (size.width / 2).floorToDouble());
    }
    return const FoldLayout(FoldMode.phone);
  }

  /// Ordinary phones stay in portrait. Big screens can turn, and so can a
  /// half-open folding phone, so it can stand as a tent.
  static bool rotates(MediaQueryData mq, double? hingeAngle) =>
      enabled && (mq.size.shortestSide >= minWidth || _halfOpen(hingeAngle));

  /// Dialogs and sheets only keep to one side of a fold that has some width,
  /// and a flat folding phone reports its fold as a line with none. In two
  /// panes this gives the divider one pixel, so pop-ups open on one side
  /// instead of across the fold. On an iPhone, which doesn't report its fold
  /// at all, it adds one down the middle.
  static MediaQueryData withPaneDivider(MediaQueryData mq, {double? hingeAngle}) {
    final f = of(mq, hingeAngle: hingeAngle);
    if (f.mode != FoldMode.twoPane) return mq;
    final hasOne = mq.displayFeatures.any((d) =>
        d.type != DisplayFeatureType.cutout && d.bounds.width > 0 && d.bounds.height >= mq.size.height - 1);
    if (hasOne) return mq;
    final others = mq.displayFeatures.where((d) =>
        !(d.type != DisplayFeatureType.cutout && d.bounds.top <= 1 && d.bounds.bottom >= mq.size.height - 1));
    final x = f.split + f.gap / 2;
    return mq.copyWith(displayFeatures: [
      ...others,
      DisplayFeature(
        bounds: Rect.fromLTWH(x - 0.5, 0, 1, mq.size.height),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is FoldLayout && other.mode == mode && other.split == split && other.gap == gap;

  @override
  int get hashCode => Object.hash(mode, split, gap);

  @override
  String toString() => 'FoldLayout($mode, split: $split, gap: $gap)';
}

/// A folding phone's hinge angle in degrees (0 closed, 180 flat), from
/// Android's hinge sensor. Null on phones without one, and on iPhone.
class Hinge {
  static const _channel = EventChannel('fitapp/hinge');
  static final ValueNotifier<double?> angle = ValueNotifier<double?>(null);
  static StreamSubscription<dynamic>? _sub;

  static void start() {
    if (_sub != null || kIsWeb || !Platform.isAndroid) return;
    _sub = _channel.receiveBroadcastStream().listen(
      (v) {
        if (v is num) angle.value = v.toDouble();
      },
      onError: (Object _) {},
    );
  }
}

/// Lets the screen turn only where [FoldLayout.rotates] says so.
class OrientationGuard extends StatefulWidget {
  const OrientationGuard({super.key, required this.child});

  final Widget child;

  @override
  State<OrientationGuard> createState() => _OrientationGuardState();
}

class _OrientationGuardState extends State<OrientationGuard> {
  bool? _rotates;

  void _apply(bool rotates) {
    if (_rotates == rotates) return;
    _rotates = rotates;
    final allowed = rotates ? DeviceOrientation.values : const [DeviceOrientation.portraitUp];
    // After this frame: changing it mid-build isn't allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setPreferredOrientations(allowed).catchError((Object _) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double?>(
      valueListenable: Hinge.angle,
      builder: (context, angle, child) {
        _apply(FoldLayout.rotates(MediaQuery.of(context), angle));
        return child!;
      },
      child: widget.child,
    );
  }
}
