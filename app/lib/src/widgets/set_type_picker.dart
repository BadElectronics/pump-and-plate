import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/tokens.dart';

/// Bottom sheet listing every set type; returns the one tapped, or null.
/// Used while logging a set and when planning a saved workout.
Future<SetType?> pickSetType(BuildContext context, SetType current, {String? title}) {
  final c = AppColors.of(context);
  return showModalBottomSheet<SetType>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
              ),
            for (final t in SetType.values)
              ListTile(
                leading: SizedBox(
                  width: 30,
                  child: Text(
                    t == SetType.normal ? '1' : t.short,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: t == SetType.warmup ? c.protein : c.accent,
                    ),
                  ),
                ),
                title: Text(t.label),
                subtitle: Text(t.hint),
                trailing: t == current ? Icon(Icons.check_rounded, color: c.accent) : null,
                onTap: () => Navigator.of(sheet).pop(t),
              ),
          ],
        ),
      ),
    ),
  );
}
