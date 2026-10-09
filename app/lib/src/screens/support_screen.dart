import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/phone.dart';
import '../services/services_scope.dart';
import '../services/tips.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Starts a bug report email with the build and phone filled in. Nothing is
/// sent until the person taps Send in their email app. Without an email app,
/// shows the address to copy instead.
Future<void> reportBug(BuildContext context) async {
  final model = await Phone.model();
  final body = 'What happened:\n\n\nWhat you expected:\n\n\n'
      '---\n$appName $buildLabel${model.isEmpty ? '' : '\n$model'}';
  final ok = await Phone.email(to: supportEmail, subject: '$appName: bug report or idea', body: body);
  if (ok || !context.mounted) return;
  final c = AppColors.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: c.surface,
      title: const Text('Report a bug'),
      content: Text('No email app opened. You can write to $supportEmail and mention $buildLabel.'),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: supportEmail));
            Navigator.of(dialog).pop();
          },
          style: TextButton.styleFrom(foregroundColor: c.accent),
          child: const Text('Copy address'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Future<void> openYouTube(BuildContext context) async {
  final ok = await Phone.openUrl(youtubeUrl);
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t open YouTube on this phone.')));
}

Future<void> openPrivacyPolicy(BuildContext context) async {
  final ok = await Phone.openUrl(privacyPolicyUrl);
  if (ok || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Couldn\'t open a browser. The policy is at $privacyPolicyUrl')),
  );
}

/// Tips, the YouTube channel, and bug reports.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const SupportScreen());

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  TipJar? _jar;
  List<Tip>? _tips;
  StreamSubscription<TipOutcome>? _sub;
  bool _waiting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_jar != null) return;
    final jar = ServicesScope.of(context).tips;
    _jar = jar;
    _sub = jar.outcomes.listen(_onOutcome);
    jar.tips().then((t) {
      if (mounted) setState(() => _tips = t);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onOutcome(TipOutcome o) {
    if (!mounted) return;
    setState(() => _waiting = false);
    final text = switch (o) {
      TipOutcome.thanks => 'Thank you! That really helps keep $appName going.',
      TipOutcome.pending => 'Your tip is waiting on the store. Thank you!',
      TipOutcome.failed => 'The tip didn\'t go through. You weren\'t charged.',
      TipOutcome.cancelled => null,
    };
    if (text == null) return;
    if (o == TipOutcome.thanks) HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _give(Tip t) async {
    setState(() => _waiting = true);
    final opened = await _jar!.give(t.id);
    if (!mounted) return;
    if (!opened) {
      setState(() => _waiting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The store couldn\'t open. Try again in a moment.')));
    }
  }

  Future<void> _other(List<Tip> tips) async {
    final c = AppColors.of(context);
    final picked = await showModalBottomSheet<Tip>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text('Choose an amount', style: AppText.body(c).copyWith(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              for (final t in tips)
                ListTile(
                  key: ValueKey('tip-${t.id}'),
                  title: Text(t.price, style: AppText.body(c).copyWith(fontSize: 17)),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
                  onTap: () => Navigator.of(sheet).pop(t),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) await _give(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final tips = _tips;
    final quick = tips == null ? const <Tip>[] : [for (final t in tips) if (quickTipIds.contains(t.id)) t];

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, elevation: 0, foregroundColor: c.text),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            Text('Support $appName', style: AppText.title(c)),
            const SizedBox(height: 8),
            Text(
              '$appName is free, with no ads and no accounts. If it helps you, '
              'a tip keeps it going and growing.',
              style: AppText.body(c).copyWith(height: 1.4),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Leave a tip',
              child: tips == null
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
                    )
                  : tips.isEmpty
                      ? Text(
                          'Tips aren\'t available yet. They\'ll show up here once '
                          '$appName is on ${Theme.of(context).platform == TargetPlatform.iOS ? 'the App Store' : 'the Play Store'}.',
                          style: AppText.quiet(c),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                for (var i = 0; i < (quick.isEmpty ? tips.take(3).length : quick.length); i++) ...[
                                  if (i > 0) const SizedBox(width: 8),
                                  Expanded(
                                    child: SmallButton(
                                      key: ValueKey('quick-tip-$i'),
                                      label: (quick.isEmpty ? tips[i] : quick[i]).price,
                                      onTap: _waiting ? () {} : () => _give(quick.isEmpty ? tips[i] : quick[i]),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            SmallButton(
                              key: const ValueKey('other-tip'),
                              label: 'Other amount',
                              quiet: true,
                              onTap: _waiting ? () {} : () => _other(tips),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'One-time, through ${Theme.of(context).platform == TargetPlatform.iOS ? 'the App Store' : 'Google Play'}. '
                              'Tips don\'t unlock anything: every feature is free for everyone.',
                              style: AppText.quiet(c).copyWith(fontSize: 13),
                            ),
                          ],
                        ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'More',
              padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
              child: Column(
                children: [
                  if (youtubeUrl.isNotEmpty)
                    SettingRow(
                      divider: false,
                      label: 'Watch on YouTube',
                      note: 'Training videos and what\'s new in the app',
                      trailing: TextButton(
                        onPressed: () => openYouTube(context),
                        style: TextButton.styleFrom(foregroundColor: c.accent),
                        child: const Text('Open'),
                      ),
                    ),
                  SettingRow(
                    divider: youtubeUrl.isNotEmpty,
                    label: 'Report a bug or suggest a feature',
                    note: 'Opens an email; nothing is sent until you tap Send',
                    trailing: TextButton(
                      onPressed: () => reportBug(context),
                      style: TextButton.styleFrom(foregroundColor: c.accent),
                      child: const Text('Email'),
                    ),
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
