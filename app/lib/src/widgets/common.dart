import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String longDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// 1234.6 -> "1,235"
String thousands(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// 182.0 -> "182", 182.44 -> "182.4"
String oneDecimal(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
  });

  final String? title;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!, style: AppText.label(c)),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppText.quiet(c))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Pill-style choice control used for sex, goal mode, units and so on.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: label,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final (v, text) in options)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: v == value,
                  label: text,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (v == value) return;
                      HapticFeedback.selectionClick();
                      onChanged(v);
                    },
                    child: ExcludeSemantics(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: v == value ? c.text : c.text.withAlpha(0),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            text,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  v == value ? FontWeight.w500 : FontWeight.w400,
                              color: v == value ? c.background : c.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// On/off switch matching the mockups.
class Toggle extends StatelessWidget {
  const Toggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? c.accent : c.line,
            borderRadius: BorderRadius.circular(15),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? c.onAccent : c.surface,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row with a label, optional note, and a control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.note,
    required this.trailing,
    this.divider = true,
  });

  final String label;
  final String? note;
  final Widget trailing;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: c.line)) : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.body(c)),
                if (note != null) Text(note!, style: AppText.quiet(c)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// Number input box with a unit suffix, e.g. [ 182.4  lb ].
class NumberBox extends StatelessWidget {
  const NumberBox({
    super.key,
    required this.controller,
    required this.suffix,
    required this.onChanged,
    required this.semanticLabel,
    this.hint,
    this.decimal = true,
  });

  final TextEditingController controller;
  final String suffix;
  final ValueChanged<String> onChanged;
  final String semanticLabel;
  final String? hint;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.background,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: semanticLabel,
              child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: TextInputType.numberWithOptions(decimal: decimal),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
                ),
              ],
              cursorColor: c.accent,
              style: AppText.body(c).copyWith(fontSize: 16),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: AppText.quiet(c).copyWith(fontSize: 16),
              ),
            ),
            ),
          ),
          Text(suffix, style: AppText.quiet(c)),
        ],
      ),
    );
  }
}

/// Parses user input, accepting a comma as the decimal mark.
double? parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// Compact button: filled accent, or outlined when [quiet].
class SmallButton extends StatelessWidget {
  const SmallButton({
    super.key,
    required this.label,
    required this.onTap,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: quiet ? c.background : c.accent,
            border: quiet ? Border.all(color: c.line) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: quiet ? c.text : c.onAccent,
            ),
          ),
        ),
      ),
    );
  }
}


ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _undoBar;

/// A message with Undo and a close (×) button. Messages with a button can
/// stay up until tapped on some phones, so this one always closes itself
/// after [seconds].
void showUndo(BuildContext context, String text, VoidCallback onUndo, {int seconds = 5}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final bar = messenger.showSnackBar(SnackBar(
    content: Text(text),
    duration: Duration(seconds: seconds),
    showCloseIcon: true,
    action: SnackBarAction(label: 'Undo', onPressed: onUndo),
  ));
  _undoBar = bar;
  var closed = false;
  bar.closed.then((_) => closed = true);
  Timer(Duration(seconds: seconds), () {
    if (!closed && identical(_undoBar, bar)) bar.close();
  });
}


/// Asks for a nickname. Returns the trimmed name, '' to clear it, or null
/// if the dialog was dismissed.
Future<String?> askNickname(BuildContext context, {String? current, bool firstTime = false}) {
  final c = AppColors.of(context);
  final ctrl = TextEditingController(text: current ?? '');
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(firstTime ? 'What should we call you?' : 'Nickname'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Optional. It\'s used to greet you, and on food you share.',
            style: AppText.quiet(c),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            cursorColor: c.accent,
            decoration: const InputDecoration(hintText: 'Nickname (optional)', counterText: ''),
            onSubmitted: (v) => Navigator.of(dialog).pop(v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(firstTime ? '' : null),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: Text(firstTime ? 'Skip' : 'Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(ctrl.text.trim()),
          style: TextButton.styleFrom(foregroundColor: c.accent),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  // ctrl isn't disposed: nothing listens to it once the dialog closes, so it's
  // freed with the dialog. (Waiting to dispose it delayed the answer.)
}


/// Tabs with an icon above (or beside, when [compact]) each label.
class IconTabs extends StatelessWidget {
  const IconTabs({
    super.key,
    required this.label,
    required this.items,
    required this.index,
    required this.onChanged,
    this.compact = false,
    this.small = false,
  });

  final String label;
  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool compact;

  /// A smaller row (icon above label), for when there are many tabs.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      label: label,
      container: true,
      child: Container(
        padding: EdgeInsets.all(compact ? 4 : 5),
        decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(compact ? 14 : 18)),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: items[i].$2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: ExcludeSemantics(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: compact ? 38 : (small ? 46 : 52),
                        margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        decoration: BoxDecoration(
                          color: i == index ? (compact ? c.surface : c.accent) : Colors.transparent,
                          borderRadius: BorderRadius.circular(compact ? 10 : 14),
                        ),
                        child: compact
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(items[i].$1, size: 16, color: i == index ? c.accent : c.muted),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      items[i].$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.fade,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: i == index ? c.text : c.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(items[i].$1, size: small ? 18 : 20, color: i == index ? c.onAccent : c.muted),
                                  SizedBox(height: small ? 2 : 3),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        items[i].$2,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: small ? 10.5 : 12,
                                          fontWeight: FontWeight.w600,
                                          color: i == index ? c.onAccent : c.muted,
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
          ],
        ),
      ),
    );
  }
}
