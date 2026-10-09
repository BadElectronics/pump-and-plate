import 'dart:io';

import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'camera_screen.dart';

const _tips = [
  ('Same time', 'Morning, after the bathroom, before you eat. Right after your weigh-in works well.'),
  ('Same place and light', 'Face a window or use the same lamp. Avoid harsh overhead light, which exaggerates shadows.'),
  ('Same camera position', 'Phone at chest height, 6–8 ft away, propped up. Use the timer.'),
  ('Same clothes, same pose', 'Wear the same outfit. Flex if you want to; just pose the same way every time.'),
];

/// Photos half of the Progress tab.
class PhotosView extends StatefulWidget {
  const PhotosView({super.key});

  @override
  State<PhotosView> createState() => _PhotosViewState();
}

class _PhotosViewState extends State<PhotosView> {
  PhotoPose _pose = PhotoPose.front;
  DateTime? _then;
  bool _showTips = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final dates = s.checkinDates;
    final due = s.photosAreDue;
    final weeks = s.settings.photoIntervalWeeks;

    final children = <Widget>[
      _dueCard(context, s, c, due, weeks),
      const SizedBox(height: 14),
      _tipsCard(c, expanded: dates.isEmpty || _showTips),
    ];

    if (dates.length >= 2) {
      final then = (_then != null && dates.any((d) => d == _then)) ? _then! : dates.first;
      final now = dates.last;
      children.addAll([
        const SizedBox(height: 14),
        _compareCard(s, c, dates, then, now),
      ]);
    }

    if (dates.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 14),
        _gridCard(context, s, c, dates),
      ]);
    }

    children.addAll([
      const SizedBox(height: 12),
      Text(
        'Photos stay in this app\'s private storage. Include them when you '
        'save a backup (Settings > Your data) to move them to a new phone.',
        style: AppText.quiet(c).copyWith(fontSize: 12),
      ),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _dueCard(BuildContext context, AppState s, AppColors c, bool due, int weeks) {
    final last = s.lastCheckin;
    final bg = c.text;
    final fg = c.background;
    final soft = Color.lerp(c.background, c.text, 0.35)!;
    String detail;
    if (weeks == 0) {
      detail = 'Photo reminders are off. You can still take photos any time.';
    } else if (last == null) {
      detail = 'Front, side and back. About 2 minutes.';
    } else if (due) {
      detail = 'Last check-in ${shortDate(last)}. Front, side and back, about 2 minutes.';
    } else {
      final next = DateTime(last.year, last.month, last.day + 7 * weeks);
      detail = 'Last check-in ${shortDate(last)}. Next one is due ${shortDate(next)}.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            due ? 'Progress photos due' : 'Progress photos',
            style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(detail, style: TextStyle(color: soft, fontSize: 13, height: 1.45)),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(CameraScreen.route()),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  due ? 'Start guided photos' : 'Take photos now',
                  style: TextStyle(
                    color: c.onAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipsCard(AppColors c, {required bool expanded}) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showTips = !_showTips),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(child: Text('How to take them', style: AppText.label(c))),
                  Icon(
                    expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            for (var i = 0; i < _tips.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.accent.withAlpha(36),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(color: c.accent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tips[i].$1,
                            style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
                          ),
                          Text(_tips[i].$2, style: AppText.quiet(c)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _compareCard(
    AppState s,
    AppColors c,
    List<DateTime> dates,
    DateTime then,
    DateTime now,
  ) {
    final imperial = s.settings.units == Units.imperial;
    String weight(PhotoCheckin? p) {
      final w = p?.weightKg;
      if (w == null) return '';
      return '${oneDecimal(imperial ? kgToLb(w) : w)} ${imperial ? 'lb' : 'kg'}';
    }

    final a = s.photoFor(then, _pose);
    final b = s.photoFor(now, _pose);

    return SectionCard(
      title: 'Compare',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Segmented<PhotoPose>(
            label: 'Pose',
            options: [for (final p in PhotoPose.values) (p, p.label)],
            value: _pose,
            onChanged: (v) => setState(() => _pose = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PhotoTile(
                  path: a == null ? null : s.pathFor(a),
                  caption: then == dates.first ? 'First · ${shortDate(then)}' : shortDate(then),
                  sub: weight(a),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PhotoTile(path: b == null ? null : s.pathFor(b), caption: 'Latest · ${shortDate(now)}', sub: weight(b)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Compare with', style: AppText.quiet(c).copyWith(fontSize: 12)),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final d in dates.take(dates.length - 1))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _then = d),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: d == then ? c.text : c.background,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: c.line),
                        ),
                        child: Text(
                          shortDate(d),
                          style: TextStyle(
                            fontSize: 13,
                            color: d == then ? c.background : c.text,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridCard(BuildContext context, AppState s, AppColors c, List<DateTime> dates) {
    return SectionCard(
      title: 'All check-ins',
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 8.0;
          final w = (box.maxWidth - gap * 3) / 4;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final d in dates.reversed)
                SizedBox(
                  width: w,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(CheckinScreen.route(d)),
                    child: _PhotoTile(
                      path: _firstPath(s, d),
                      caption: shortDate(d),
                      small: true,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String? _firstPath(AppState s, DateTime d) {
    for (final pose in PhotoPose.values) {
      final p = s.photoFor(d, pose);
      if (p != null) return s.pathFor(p);
    }
    return null;
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.path,
    required this.caption,
    this.sub = '',
    this.small = false,
  });

  final String? path;
  final String caption;
  final String sub;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final p = path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(small ? 10 : 14),
            child: p == null
                ? Container(
                    color: c.chip,
                    alignment: Alignment.center,
                    child: Text('No photo', style: AppText.quiet(c).copyWith(fontSize: 11)),
                  )
                : Image.file(
                    File(p),
                    fit: BoxFit.cover,
                    cacheWidth: small ? 240 : 600,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Container(color: c.chip),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                caption,
                textAlign: small ? TextAlign.center : TextAlign.left,
                style: AppText.quiet(c).copyWith(fontSize: small ? 11 : 12),
              ),
            ),
            if (sub.isNotEmpty)
              Text(sub, style: AppText.body(c).copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}

/// One check-in: all three poses, with delete.
class CheckinScreen extends StatelessWidget {
  const CheckinScreen({super.key, required this.date});

  final DateTime date;

  static Route<void> route(DateTime date) =>
      MaterialPageRoute<void>(builder: (_) => CheckinScreen(date: date));

  Future<void> _delete(BuildContext context, AppState s) async {
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Delete this check-in?'),
        content: Text('All photos from ${longDate(date)} will be deleted from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.protein),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    s.deleteCheckin(date);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    double? w;
    for (final pose in PhotoPose.values) {
      w ??= s.photoFor(date, pose)?.weightKg;
    }

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_rounded, color: c.text),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(longDate(date), style: AppText.title(c).copyWith(fontSize: 24)),
                      if (w != null)
                        Text(
                          '${oneDecimal(imperial ? kgToLb(w) : w)} ${imperial ? 'lb' : 'kg'} that day',
                          style: AppText.quiet(c),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final pose in PhotoPose.values) ...[
                    Text(pose.label, style: AppText.label(c)),
                    const SizedBox(height: 6),
                    _PhotoTile(
                      path: () {
                        final p = s.photoFor(date, pose);
                        return p == null ? null : s.pathFor(p);
                      }(),
                      caption: '',
                    ),
                    const SizedBox(height: 16),
                  ],
                  SmallButton(
                    label: 'Delete this check-in',
                    quiet: true,
                    onTap: () => _delete(context, s),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
