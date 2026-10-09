import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/sleep_editor.dart';

/// Last night's sleep on its own page (from the Check-in widget).
class SleepPage extends StatelessWidget {
  const SleepPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const SleepPage());

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 32),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.arrow_back_rounded, color: c.text),
                ),
                Text('Sleep', style: AppText.title(c).copyWith(fontSize: 22)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 8),
              child: SleepEditor(
                date: dateOnly(DateTime.now()),
                title: 'Last night',
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
