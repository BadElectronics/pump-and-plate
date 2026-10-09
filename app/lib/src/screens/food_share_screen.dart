import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/food_share.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Picks a food-share file and adds its recipes and foods after a preview.
Future<void> importFoodShareFile(BuildContext context) async {
  final s = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final FoodShare share;
  try {
    final file = await FilePicker.pickFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    share = decodeFoodShare(utf8.decode(bytes, allowMalformed: true));
  } on FoodShareError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  } catch (e) {
    messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t open that file.')));
    return;
  }
  if (!context.mounted) return;
  if (share.foods.isEmpty && share.recipes.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('That share file is empty.')));
    return;
  }
  final c = AppColors.of(context);
  final names = share.recipes.map((r) => r.name).take(6).join(', ');
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(share.from == null ? 'Add shared food?' : 'Food from ${share.from}'),
      content: Text(
        '${share.recipes.length} ${share.recipes.length == 1 ? 'recipe' : 'recipes'} and '
        '${share.foods.length} ${share.foods.length == 1 ? 'food' : 'foods'}'
        '${names.isEmpty ? '' : ': $names${share.recipes.length > 6 ? '…' : ''}'}.\n\n'
        'Foods you already have (same name) are reused, and recipes with a name you '
        'already use are skipped, so nothing of yours changes.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(false),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialog).pop(true),
          style: TextButton.styleFrom(foregroundColor: c.accent),
          child: const Text('Add them'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final r = s.importFoodShare(share);
  final parts = [
    '${r.recipes} ${r.recipes == 1 ? 'recipe' : 'recipes'}',
    '${r.foods} new ${r.foods == 1 ? 'food' : 'foods'}',
  ];
  messenger.showSnackBar(SnackBar(
    content: Text(
      'Added ${parts.join(' and ')}'
      '${r.skippedRecipes == 0 ? '.' : '. Skipped ${r.skippedRecipes} you already have.'}',
    ),
  ));
}

/// Choose recipes and your own foods to send to someone.
class ShareFoodScreen extends StatefulWidget {
  const ShareFoodScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const ShareFoodScreen());

  @override
  State<ShareFoodScreen> createState() => _ShareFoodScreenState();
}

class _ShareFoodScreenState extends State<ShareFoodScreen> {
  final Set<String> _recipes = {};
  final Set<String> _foods = {};

  Future<void> _save(AppState s) async {
    final recipes = [
      for (final r in s.recipes)
        if (_recipes.contains(r.id)) r,
    ];
    final foods = [
      for (final f in s.foods)
        if (_foods.contains(f.id)) f,
    ];
    if (recipes.isEmpty && foods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tick at least one recipe or food.')),
      );
      return;
    }
    final text = s.shareFoods(recipes: recipes, extraFoods: foods);
    final who = (s.settings.nickname ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final name = 'fitapp-food${who.isEmpty ? '' : '-$who'}-${dayKey(DateTime.now())}.json';
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save food to share',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(text)),
      );
      if (saved == null || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Saved $name. Send it to your friend; they open it with Food > Recipes > Import.',
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t save the file.')),
        );
      }
    }
  }

  Widget _row(AppColors c, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
        child: Row(
          children: [
            Checkbox(
              value: value,
              activeColor: c.accent,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppText.body(c)),
                  if (subtitle.isNotEmpty) Text(subtitle, style: AppText.quiet(c).copyWith(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final myFoods = [
      for (final f in s.foods)
        if (f.custom && !f.archived) f,
    ];
    final count = _recipes.length + _foods.length;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: c.text),
                  ),
                  Expanded(child: Text('Share food', style: AppText.title(c).copyWith(fontSize: 22))),
                  SmallButton(
                    label: count == 0 ? 'Save' : 'Save ($count)',
                    onTap: () => _save(s),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  Text(
                    'Tick what to share. Recipes bring their ingredients along. Store '
                    'prices stay with you. You\'ll get one small file to send any way '
                    'you like.',
                    style: AppText.quiet(c),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Recipes',
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (s.recipes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('No recipes yet.', style: AppText.quiet(c)),
                          )
                        else ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() {
                                if (_recipes.length == s.recipes.length) {
                                  _recipes.clear();
                                } else {
                                  _recipes.addAll(s.recipes.map((r) => r.id));
                                }
                              }),
                              style: TextButton.styleFrom(foregroundColor: c.accent),
                              child: Text(_recipes.length == s.recipes.length ? 'Select none' : 'Select all'),
                            ),
                          ),
                          for (final r in s.recipes)
                            _row(
                              c,
                              r.name,
                              '${r.items.length} ingredients · ${oneDecimal(r.servings)} servings',
                              _recipes.contains(r.id),
                              (v) => setState(() => v ? _recipes.add(r.id) : _recipes.remove(r.id)),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'Foods you added',
                    padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (myFoods.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              'Foods you add yourself show up here. The starter foods '
                              'come with every copy of the app.',
                              style: AppText.quiet(c),
                            ),
                          ),
                        for (final f in myFoods)
                          _row(
                            c,
                            f.name,
                            '${f.per100.kcal.round()} kcal per 100 g',
                            _foods.contains(f.id),
                            (v) => setState(() => v ? _foods.add(f.id) : _foods.remove(f.id)),
                          ),
                      ],
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
