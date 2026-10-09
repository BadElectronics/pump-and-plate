import 'package:flutter/material.dart';

import '../calc/calc.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/set_type_picker.dart';
import 'exercise_library_screen.dart';

/// Create or edit one workout.
class WorkoutEditorScreen extends StatefulWidget {
  const WorkoutEditorScreen({super.key, this.workout});

  final Workout? workout;

  static Route<void> route([Workout? w]) =>
      MaterialPageRoute<void>(builder: (_) => WorkoutEditorScreen(workout: w));

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late final _name = TextEditingController(text: widget.workout?.name ?? '');
  late final List<(int, WorkoutItem)> _items = [
    for (final item in widget.workout?.items ?? const <WorkoutItem>[]) (_nextUid++, item),
  ];
  static int _nextUid = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addExercise() async {
    final id = await ExerciseLibraryScreen.pick(context);
    if (id == null || !mounted) return;
    setState(() => _items.add((_nextUid++, WorkoutItem(exerciseId: id))));
  }

  Future<void> _editItem(int index) async {
    final c = AppColors.of(context);
    final result = await showModalBottomSheet<(WorkoutItem?, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ItemSheet(item: _items[index].$2),
    );
    if (result == null || !mounted) return;
    final (item, remove) = result;
    setState(() {
      if (remove) {
        _items.removeAt(index);
      } else if (item != null) {
        _items[index] = (_items[index].$1, item);
      }
    });
  }

  void _save() {
    final s = AppScope.of(context);
    final name = _name.text.trim().isEmpty ? 'Workout' : _name.text.trim();
    final items = [for (final (_, item) in _items) item];
    final existing = widget.workout;
    s.saveWorkout(existing == null
        ? Workout(id: newId('w'), name: name, items: items)
        : existing.copyWith(name: name, items: items));
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final w = widget.workout;
    if (w == null) return;
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Delete ${w.name}?'),
        content: const Text('The plan is removed. Workouts you already logged with it stay.'),
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
    if (ok != true || !mounted) return;
    AppScope.of(context).deleteWorkout(w);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final imperial = s.settings.units == Units.imperial;
    final minutes = s.minutesFor([for (final (_, i) in _items) i]);
    final spans = AppState.supersetSpans([for (final (_, i) in _items) i]);

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
                    tooltip: 'Back without saving',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: c.text),
                  ),
                  Expanded(
                    child: Text(
                      widget.workout == null ? 'New workout' : 'Edit workout',
                      style: AppText.title(c).copyWith(fontSize: 22),
                    ),
                  ),
                  SmallButton(label: 'Save', onTap: _save),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                buildDefaultDragHandles: false,
                header: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('Name'),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: c.surface,
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        cursorColor: c.accent,
                        style: AppText.body(c).copyWith(fontSize: 16),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'e.g. Upper A',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _items.isEmpty
                          ? 'No exercises yet'
                          : '${_items.length} exercises, about $minutes min. Tap an '
                              'exercise to change its sets, reps, weight and rest time; '
                              'hold the handle to reorder.',
                      style: AppText.quiet(c),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                footer: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SmallButton(label: 'Add exercise', quiet: true, onTap: _addExercise),
                      if (widget.workout != null) ...[
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: _delete,
                          style: TextButton.styleFrom(foregroundColor: c.protein),
                          child: const Text('Delete this workout'),
                        ),
                      ],
                    ],
                  ),
                ),
                onReorder: (oldIndex, newIndex) => setState(() {
                  final moved = _items.removeAt(oldIndex);
                  _items.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
                }),
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Column(
                      key: ValueKey(_items[i].$1),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          color: c.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: spans[i] == null
                                ? BorderSide.none
                                : BorderSide(color: c.accent, width: 2),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _editItem(i),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(6, 10, 14, 10),
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Icon(Icons.drag_indicator_rounded, color: c.muted),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.exerciseName(_items[i].$2.exerciseId),
                                          style: AppText.body(c).copyWith(fontWeight: FontWeight.w500),
                                        ),
                                        Text(
                                          _summary(s, _items[i].$2, imperial),
                                          style: AppText.quiet(c).copyWith(fontSize: 12),
                                        ),
                                        if (s.exercise(_items[i].$2.exerciseId)?.note != null)
                                          Text(
                                            'Note: ${s.exercise(_items[i].$2.exerciseId)!.note}',
                                            style: AppText.quiet(c).copyWith(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.edit_outlined, size: 18, color: c.muted),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (i < _items.length - 1)
                          SupersetLink(
                            linked: _items[i].$2.linkNext,
                            onToggle: () => setState(() {
                              final (uid, item) = _items[i];
                              _items[i] = (uid, item.copyWith(linkNext: !item.linkNext));
                            }),
                          )
                        else
                          const SizedBox(height: 8),
                      ],
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

String repsText(WorkoutItem i) =>
    i.repsLow == i.repsHigh ? '${i.repsLow}' : '${i.repsLow}–${i.repsHigh}';

String _summary(AppState s, WorkoutItem i, bool imperial) {
  if (s.isCardio(i.exerciseId)) {
    return i.targetMin == null ? 'Cardio' : 'Cardio · ${i.targetMin} min';
  }
  final parts = ['${i.sets} × ${repsText(i)}'];
  final load = i.loadKg;
  if (load != null) {
    parts.add('${oneDecimal(imperial ? kgToLb(load) : load)} ${imperial ? 'lb' : 'kg'}');
  }
  parts.add('rest ${_restLabel(i.restSec)}');
  for (var n = 0; n < i.sets; n++) {
    final t = setTypeByName(i.setTypeAt(n));
    if (t != SetType.normal) parts.add('set ${n + 1} ${t.label.toLowerCase()}');
  }
  return parts.join(' · ');
}

/// The chain between two exercises: tap to link them as a superset.
class SupersetLink extends StatelessWidget {
  const SupersetLink({super.key, required this.linked, this.onToggle});

  final bool linked;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final line = Container(width: 3, height: 10, color: linked ? c.accent : Colors.transparent);
    final chip = linked
        ? Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_rounded, size: 16, color: c.onAccent),
                const SizedBox(width: 6),
                Text(
                  'Superset',
                  style: TextStyle(color: c.onAccent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          )
        : Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_link_rounded, size: 16, color: c.muted),
                const SizedBox(width: 6),
                Text('Superset with next', style: TextStyle(color: c.muted, fontSize: 12)),
              ],
            ),
          );
    return Semantics(
      button: onToggle != null,
      label: linked ? 'Superset. Tap to unlink.' : 'Link with the next exercise as a superset',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(left: 12), child: line),
              chip,
              Padding(padding: const EdgeInsets.only(left: 12), child: line),
            ],
          ),
        ),
      ),
    );
  }
}

String _restLabel(int sec) =>
    sec % 60 == 0 ? '${sec ~/ 60} min' : '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item});

  final WorkoutItem item;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late int _sets = widget.item.sets;
  late int _lo = widget.item.repsLow;
  late int _hi = widget.item.repsHigh;
  late int _rest = widget.item.restSec;
  late int _minutes = widget.item.targetMin ?? 30;
  late final List<String> _types = [...widget.item.setTypes];
  final _load = TextEditingController();
  final _note = TextEditingController();
  bool _filled = false;
  bool _imperial = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final s = AppScope.of(context);
    _imperial = s.settings.units == Units.imperial;
    final l = widget.item.loadKg;
    _load.text = l == null ? '' : oneDecimal(_imperial ? kgToLb(l) : l);
    _note.text = s.exercise(widget.item.exerciseId)?.note ?? '';
  }

  @override
  void dispose() {
    _load.dispose();
    _note.dispose();
    super.dispose();
  }

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> set, {int step = 1}) {
    final c = AppColors.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: AppText.body(c))),
        _Round(
          icon: Icons.remove_rounded,
          label: 'Fewer $label',
          onTap: value <= min ? null : () => setState(() => set(value - step < min ? min : value - step)),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppText.body(c).copyWith(fontSize: 17, fontWeight: FontWeight.w500),
          ),
        ),
        _Round(
          icon: Icons.add_rounded,
          label: 'More $label',
          onTap: value >= max ? null : () => setState(() => set(value + step > max ? max : value + step)),
        ),
      ],
    );
  }

  SetType _typeAt(int i) => setTypeByName(i < _types.length ? _types[i] : '');

  Future<void> _chooseType(int i) async {
    final picked = await pickSetType(context, _typeAt(i), title: 'Set ${i + 1}');
    if (picked == null || !mounted) return;
    setState(() {
      while (_types.length <= i) {
        _types.add('');
      }
      _types[i] = picked == SetType.normal ? '' : picked.name;
    });
  }

  /// The set types to save: one per set, trailing normal sets dropped.
  List<String> _savedTypes() {
    final out = [for (var i = 0; i < _sets; i++) i < _types.length ? _types[i] : ''];
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out;
  }

  Widget _setTypeChips() {
    final c = AppColors.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < _sets; i++)
          Semantics(
            button: true,
            label: 'Set ${i + 1}, ${_typeAt(i).label}. Tap to change the set type.',
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('set-type-$i'),
              onTap: () => _chooseType(i),
              child: Container(
                height: 38,
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _typeAt(i) == SetType.normal ? c.background : c.accent,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: _typeAt(i) == SetType.normal ? c.line : c.accent),
                ),
                child: Text(
                  _typeAt(i) == SetType.normal ? '${i + 1}' : '${i + 1} ${_typeAt(i).short}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _typeAt(i) == SetType.normal ? c.text : c.onAccent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final ex = s.exercise(widget.item.exerciseId);
    final special = [
      for (var i = 0; i < _sets; i++)
        if (_typeAt(i) != SetType.normal) 'Set ${i + 1}: ${_typeAt(i).label}',
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ex?.name ?? 'Exercise', style: AppText.title(c).copyWith(fontSize: 22)),
            const SizedBox(height: 16),
            if (ex != null && ex.cardio) ...[
              _stepper('Target minutes', _minutes, 5, 240, (v) => _minutes = v, step: 5),
              const SizedBox(height: 16),
            ] else ...[
            _stepper('Sets', _sets, 1, 12, (v) => _sets = v),
            const SizedBox(height: 12),
            const FieldLabel('Set types'),
            _setTypeChips(),
            const SizedBox(height: 6),
            Text(
              special.isEmpty
                  ? 'All normal sets. Tap a set to make it a warm-up, drop set, '
                      'failure set and so on; it is set up that way each time you start this workout.'
                  : '${special.join(' · ')}. Tap a set to change it.',
              style: AppText.quiet(c).copyWith(fontSize: 12),
            ),
            const SizedBox(height: 14),
            _stepper('Reps, low', _lo, 1, 50, (v) {
              _lo = v;
              if (_hi < v) _hi = v;
            }),
            const SizedBox(height: 10),
            _stepper('Reps, high', _hi, 1, 50, (v) {
              _hi = v;
              if (_lo > v) _lo = v;
            }),
            const SizedBox(height: 16),
            FieldLabel(ex != null && ex.bodyweight ? 'Added weight (optional)' : 'Target weight (optional)'),
            NumberBox(
              controller: _load,
              suffix: _imperial ? 'lb' : 'kg',
              semanticLabel: 'Target weight',
              onChanged: (_) {},
            ),
            const SizedBox(height: 16),
            const FieldLabel('Rest between sets'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final sec in [45, 60, 90, 120, 150, 180, 240])
                  GestureDetector(
                    onTap: () => setState(() => _rest = sec),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sec == _rest ? c.text : c.background,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        _restLabel(sec),
                        style: TextStyle(fontSize: 14, color: sec == _rest ? c.background : c.text),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ],
            const FieldLabel('Note (shows every time you do this exercise)'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.background,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _note,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: c.accent,
                style: AppText.body(c),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'e.g. Seat height 4, grip just outside rings',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SmallButton(
                    label: 'Remove',
                    quiet: true,
                    onTap: () => Navigator.of(context).pop((null, true)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SmallButton(
                    label: 'Done',
                    onTap: () {
                      s.setExerciseNote(widget.item.exerciseId, _note.text);
                      final v = parseNumber(_load.text);
                      final kg = v == null || v <= 0 ? null : (_imperial ? lbToKg(v) : v);
                      Navigator.of(context).pop((
                        widget.item.copyWith(
                          sets: _sets,
                          repsLow: _lo,
                          repsHigh: _hi,
                          loadKg: kg,
                          restSec: _rest,
                          targetMin: ex != null && ex.cardio ? _minutes : null,
                          setTypes: ex != null && ex.cardio ? const <String>[] : _savedTypes(),
                        ),
                        false,
                      ));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: onTap == null ? c.muted : c.text),
        ),
      ),
    );
  }
}
