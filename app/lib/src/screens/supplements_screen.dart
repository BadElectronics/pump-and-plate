import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Today's supplements as a checklist: tap one to mark it taken (tap again
/// to undo). Used on Log and on the Supplements page.
class SupplementChecklist extends StatelessWidget {
  const SupplementChecklist({super.key, required this.day, this.showManage = true});

  final DateTime day;
  final bool showManage;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final list = s.activeSupplements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Add the supplements you take, then tick them off each day.', style: AppText.quiet(c)),
          ),
        for (final x in list)
          _SupplementRow(supplement: x, dose: s.doseOf(x, day), onTap: () {
            HapticFeedback.selectionClick();
            final taken = s.doseOf(x, day);
            if (taken == null) {
              s.takeSupplement(x, day: day);
            } else {
              s.removeDose(taken);
            }
          }),
        if (showManage) ...[
          const SizedBox(height: 8),
          SmallButton(
            key: const ValueKey('manage-supplements'),
            label: list.isEmpty ? 'Add supplements' : 'Edit list and history',
            quiet: list.isNotEmpty,
            onTap: () => Navigator.of(context).push(SupplementsScreen.route()),
          ),
        ],
      ],
    );
  }
}

class _SupplementRow extends StatelessWidget {
  const _SupplementRow({required this.supplement, required this.dose, required this.onTap});

  final Supplement supplement;
  final SupplementDose? dose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final taken = dose != null;
    final amount = supplement.dose;
    return Semantics(
      button: true,
      checked: taken,
      label: '${supplement.name}${amount.isEmpty ? '' : ', $amount'}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('supplement-${supplement.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: taken ? c.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: taken ? c.accent : c.line, width: 2),
                ),
                child: taken ? Icon(Icons.check_rounded, size: 17, color: c.onAccent) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplement.name, style: AppText.body(c).copyWith(fontWeight: FontWeight.w500)),
                    if (amount.isNotEmpty || taken)
                      Text(
                        [
                          if (amount.isNotEmpty) amount,
                          if (taken) 'taken ${TimeOfDay.fromDateTime(dose!.at).format(context)}',
                        ].join('  ·  '),
                        style: AppText.quiet(c).copyWith(fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The supplement list (add, change, remove) and the last two weeks.
class SupplementsScreen extends StatelessWidget {
  const SupplementsScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const SupplementsScreen());

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final today = dateOnly(DateTime.now());
    final days = [for (var i = 13; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
    final list = s.activeSupplements;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, elevation: 0, foregroundColor: c.text),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            Text('Supplements', style: AppText.title(c)),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Today',
              child: SupplementChecklist(day: today, showManage: false),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Your list',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final x in list)
                    // Its own Material: the card's background would hide the
                    // tap ripple otherwise.
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        key: ValueKey('edit-supplement-${x.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(x.name, style: AppText.body(c)),
                        subtitle: x.dose.isEmpty ? null : Text(x.dose, style: AppText.quiet(c)),
                        trailing: Icon(Icons.edit_outlined, size: 18, color: c.muted),
                        onTap: () => editSupplement(context, x),
                      ),
                    ),
                  const SizedBox(height: 6),
                  SmallButton(
                    key: const ValueKey('add-supplement'),
                    label: 'Add a supplement',
                    onTap: () => editSupplement(context, null),
                  ),
                ],
              ),
            ),
            if (list.isNotEmpty) ...[
              const SizedBox(height: 14),
              SectionCard(
                title: 'Last 2 weeks',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final x in list) ...[
                      Text(x.name, style: AppText.body(c).copyWith(fontSize: 14)),
                      const SizedBox(height: 4),
                      Semantics(
                        label: '${x.name}: taken on ${days.where((d) => s.doseOf(x, d) != null).length} of the last 14 days',
                        excludeSemantics: true,
                        child: Row(
                          children: [
                            for (final d in days)
                              Expanded(
                                child: Container(
                                  height: 14,
                                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                  decoration: BoxDecoration(
                                    color: s.doseOf(x, d) != null ? c.accent : c.chip,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Oldest on the left, today on the right.', style: AppText.quiet(c).copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add ([x] null) or change a supplement.
Future<void> editSupplement(BuildContext context, Supplement? x) async {
  final s = AppScope.of(context);
  final c = AppColors.of(context);
  final name = TextEditingController(text: x?.name ?? '');
  final amount = TextEditingController(
    text: x?.amount == null ? '' : (x!.amount! == x.amount!.roundToDouble() ? '${x.amount!.round()}' : '${x.amount}'),
  );
  var unit = x?.unit ?? 'mg';
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(x == null ? 'Add a supplement' : 'Change supplement', style: AppText.title(c).copyWith(fontSize: 22)),
              const SizedBox(height: 14),
              const FieldLabel('Name'),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  key: const ValueKey('supplement-name'),
                  controller: name,
                  autofocus: x == null,
                  textCapitalization: TextCapitalization.words,
                  cursorColor: c.accent,
                  style: AppText.body(c).copyWith(fontSize: 16),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'e.g. Vitamin D, Creatine'),
                ),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Amount per day (optional)'),
              NumberBox(
                key: const ValueKey('supplement-amount'),
                controller: amount,
                suffix: unit,
                semanticLabel: 'Amount',
                onChanged: (_) {},
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final u in supplementUnits)
                    ChoiceChip(
                      label: Text(u),
                      selected: u == unit,
                      selectedColor: c.accent,
                      labelStyle: TextStyle(color: u == unit ? c.onAccent : c.text),
                      backgroundColor: c.background,
                      side: BorderSide(color: c.line),
                      showCheckmark: false,
                      onSelected: (_) => setSheet(() => unit = u),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (x != null) ...[
                    Expanded(
                      child: SmallButton(label: 'Remove', quiet: true, onTap: () => Navigator.of(sheet).pop('remove')),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    flex: 2,
                    child: SmallButton(
                      key: const ValueKey('save-supplement'),
                      label: 'Save',
                      onTap: () => Navigator.of(sheet).pop('save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (result == 'remove' && x != null) {
    s.removeSupplement(x);
  } else if (result == 'save') {
    final n = name.text.trim();
    if (n.isNotEmpty) {
      final v = parseNumber(amount.text);
      final a = v == null || v <= 0 ? null : v;
      s.saveSupplement(x == null
          ? Supplement(id: newId('su'), name: n, amount: a, unit: unit)
          : x.copyWith(name: n, amount: a, unit: unit));
    }
  }
  // The controllers aren't disposed here: the sheet is still animating
  // closed and uses them for a few more frames.
}
