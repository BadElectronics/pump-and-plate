import 'package:flutter/material.dart';

import '../ai/matcher.dart';
import '../data/models.dart';
import '../data/muscles.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Browse and edit exercises, or pick one (returns its id).
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key, this.pickMode = false});

  final bool pickMode;

  static Future<String?> pick(BuildContext context) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen(pickMode: true)),
      );

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const ExerciseLibraryScreen());

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _search = TextEditingController();

  /// Groups opened by hand (all start closed, except Recent when picking).
  final Set<String> _open = {};

  /// Only this equipment, or all when null.
  String? _equipment;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(Exercise? existing) async {
    final c = AppColors.of(context);
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ExerciseSheet(existing: existing),
    );
    if (result == null || !mounted) return;
    // "Other versions": open that one instead.
    if (result is _OpenOther) {
      final other = AppScope.of(context).exercise(result.id);
      if (other != null) await _edit(other);
      return;
    }
    if (result is! Exercise) return;
    final saved = result;
    AppScope.of(context).saveExercise(saved);
    if (widget.pickMode && existing == null && !saved.archived) {
      Navigator.of(context).pop(saved.id);
    }
  }

  /// Exercises from your recent workouts, newest first.
  List<Exercise> _recent(AppState s) {
    final seen = <String>{};
    final out = <Exercise>[];
    for (final x in s.sessions.reversed) {
      for (final set in x.sets) {
        if (!seen.add(set.exerciseId)) continue;
        final e = s.exercise(set.exerciseId);
        if (e != null && !e.archived) out.add(e);
        if (out.length >= 8) return out;
      }
    }
    return out;
  }

  Widget _row(AppColors c, Exercise e, bool first) {
    final kit = equipmentOf(e);
    return InkWell(
      key: ValueKey('exercise-${e.id}'),
      onTap: () => widget.pickMode ? Navigator.of(context).pop(e.id) : _edit(e),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.name, style: AppText.body(c)),
                  if (kit != null) Text(kit, style: AppText.quiet(c).copyWith(fontSize: 12)),
                ],
              ),
            ),
            if (e.note != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.sticky_note_2_outlined, size: 16, color: c.muted),
              ),
            if (!widget.pickMode) ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ],
        ),
      ),
    );
  }

  /// A group: a header you tap to open or close, then its exercises.
  List<Widget> _group(AppColors c, String name, List<Exercise> list, {required bool open}) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Material(
          color: c.surface,
          borderRadius: open
              ? const BorderRadius.vertical(top: Radius.circular(16))
              : BorderRadius.circular(16),
          child: InkWell(
            key: ValueKey('group-$name'),
            borderRadius: open
                ? const BorderRadius.vertical(top: Radius.circular(16))
                : BorderRadius.circular(16),
            onTap: () => setState(() => _open.contains(name) ? _open.remove(name) : _open.add(name)),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name, style: AppText.body(c).copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Text('${list.length}', style: AppText.quiet(c)),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.expand_more_rounded, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (open)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++) _row(c, list[i], i == 0),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final q = _search.text.trim().toLowerCase();
    final kit = _equipment;
    bool shown(Exercise e) =>
        !e.archived &&
        (q.isEmpty || e.name.toLowerCase().contains(q)) &&
        (kit == null || equipmentOf(e) == kit);
    final visible = [for (final e in s.exercises) if (shown(e)) e];
    // Searching or filtering opens every group, so nothing is hidden.
    final openAll = q.isNotEmpty || kit != null;

    final children = <Widget>[];
    if (widget.pickMode && !openAll) {
      final recent = _recent(s);
      if (recent.isNotEmpty) {
        children.addAll(_group(c, 'Recent', recent, open: !_open.contains('Recent')));
      }
    }
    for (final group in muscleGroups) {
      final list = [
        for (final e in visible)
          if (e.muscle == group) e,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (list.isEmpty) continue;
      children.addAll(_group(c, group, list, open: openAll || _open.contains(group)));
    }

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
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  Expanded(
                    child: Text(
                      widget.pickMode ? 'Pick an exercise' : 'Exercise library',
                      style: AppText.title(c).copyWith(fontSize: 22),
                    ),
                  ),
                  SmallButton(label: 'New', quiet: true, onTap: () => _edit(null)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: c.muted, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        cursorColor: c.accent,
                        style: AppText.body(c),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search exercises',
                          hintStyle: AppText.quiet(c).copyWith(fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                children: [
                  for (final k in equipmentKinds)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        key: ValueKey('kit-$k'),
                        label: Text(k),
                        selected: k == kit,
                        selectedColor: c.accent,
                        labelStyle: TextStyle(color: k == kit ? c.onAccent : c.text, fontSize: 13),
                        backgroundColor: c.surface,
                        side: BorderSide(color: c.line),
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _equipment = k == kit ? null : k),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        q.isEmpty
                            ? 'Nothing here with that equipment.'
                            : 'No exercise called "${_search.text.trim()}". Tap New to add it.',
                        textAlign: TextAlign.center,
                        style: AppText.quiet(c),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      children: children,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseSheet extends StatefulWidget {
  const _ExerciseSheet({this.existing});

  final Exercise? existing;

  @override
  State<_ExerciseSheet> createState() => _ExerciseSheetState();
}

class _ExerciseSheetState extends State<_ExerciseSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _muscle = widget.existing?.muscle ?? 'Chest';
  late bool _bodyweight = widget.existing?.bodyweight ?? false;

  /// Muscles worked: 1 = primary, 2 = secondary (missing = not worked).
  late final Map<Muscle, int> _works = () {
    final w = widget.existing == null ? musclesForGroup(_muscle) : musclesOf(widget.existing!);
    return {for (final m in w.primary) m: 1, for (final m in w.secondary) m: 2};
  }();

  /// Until muscles are picked by hand, changing the group re-fills them.
  bool _picked = false;

  /// Heads worked, 1-3; changed by hand only when [_headsChanged].
  late final Map<MuscleHead, int> _heads = widget.existing == null ? _headsFor(_works) : {...headsOf(widget.existing!)};
  bool _headsChanged = false;

  /// Every head of a primary muscle as main, of a secondary one as some.
  static Map<MuscleHead, int> _headsFor(Map<Muscle, int> works) => {
        for (final e in works.entries)
          for (final h in e.key.heads) h: e.value == 1 ? 3 : 2,
      };

  void _setGroup(String m) {
    setState(() {
      _muscle = m;
      if (!_picked) {
        final w = musclesForGroup(m);
        _works
          ..clear()
          ..addAll({for (final x in w.primary) x: 1, for (final x in w.secondary) x: 2});
        _heads
          ..clear()
          ..addAll(_headsFor(_works));
      }
    });
  }

  /// A muscle chip changed: its heads follow (main, some or none).
  void _syncHeads(Muscle m) {
    for (final h in m.heads) {
      _heads.remove(h);
    }
    final kind = _works[m];
    if (kind != null) {
      for (final h in m.heads) {
        _heads[h] = kind == 1 ? 3 : 2;
      }
    }
  }

  List<String> _named(int kind) => [for (final e in _works.entries) if (e.value == kind) e.key.name];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Exercise? _build({bool archived = false}) {
    final name = _name.text.trim();
    if (name.isEmpty) return null;
    final e = widget.existing;
    final cardio = _muscle == 'Cardio';
    if (e == null) {
      final fromHeads = _headsChanged && !cardio ? workFromHeads(_heads) : null;
      return Exercise(
        id: newId('x'),
        name: name,
        muscle: _muscle,
        bodyweight: !cardio && _bodyweight,
        custom: true,
        cardio: cardio,
        primaryMuscles: cardio ? const [] : (fromHeads == null ? _named(1) : [for (final m in fromHeads.primary) m.name]),
        secondaryMuscles: cardio ? const [] : (fromHeads == null ? _named(2) : [for (final m in fromHeads.secondary) m.name]),
        heads: fromHeads == null ? const {} : {for (final h in _heads.entries) h.key.name: h.value},
      );
    }
    // Muscles and heads are only saved when changed here, so a built-in
    // exercise keeps following the built-in table otherwise.
    final heads = _headsChanged && !cardio ? {for (final h in _heads.entries) h.key.name: h.value} : null;
    final fromHeads = heads == null ? null : workFromHeads(_heads);
    // A new group refills the muscles, so they're saved then too.
    final picked = _picked || _muscle != e.muscle;
    return e.copyWith(
      name: name,
      muscle: _muscle,
      bodyweight: !cardio && _bodyweight,
      archived: archived,
      cardio: cardio,
      primaryMuscles: cardio
          ? const []
          : fromHeads != null
              ? [for (final m in fromHeads.primary) m.name]
              : (picked ? _named(1) : null),
      secondaryMuscles: cardio
          ? const []
          : fromHeads != null
              ? [for (final m in fromHeads.secondary) m.name]
              : (picked ? _named(2) : null),
      heads: cardio ? const {} : (heads ?? (picked ? const {} : null)),
    );
  }

  /// Exercises for the same main muscle and movement ("Incline barbell press"
  /// for "Incline dumbbell press").
  List<Widget> _otherVersions(AppColors c) {
    final s = AppScope.of(context);
    final me = widget.existing!;
    final mine = musclesOf(me).primary;
    if (mine.isEmpty) return const [];
    String move(String name) => normalizeName(name).split(' ').last;
    final list = [
      for (final e in s.exercises)
        if (e.id != me.id && !e.archived && !e.cardio && move(e.name) == move(me.name) &&
            musclesOf(e).primary.isNotEmpty && musclesOf(e).primary.first == mine.first)
          e,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (list.isEmpty) return const [];
    return [
      Text('Other versions', style: AppText.body(c)),
      const SizedBox(height: 4),
      for (final e in list.take(6))
        InkWell(
          key: ValueKey('version-${e.id}'),
          onTap: () => Navigator.of(context).pop(_OpenOther(e.id)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Expanded(child: Text(e.name, style: AppText.body(c).copyWith(fontSize: 14))),
                Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
              ],
            ),
          ),
        ),
      const SizedBox(height: 10),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? 'New exercise' : 'Edit exercise',
              style: AppText.title(c).copyWith(fontSize: 22),
            ),
            const SizedBox(height: 16),
            const FieldLabel('Name'),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: c.background,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _name,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: c.accent,
                style: AppText.body(c).copyWith(fontSize: 16),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'e.g. Cable lateral raise',
                ),
              ),
            ),
            const SizedBox(height: 14),
            const FieldLabel('Muscle group'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in muscleGroups)
                  GestureDetector(
                    onTap: () => _setGroup(m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: m == _muscle ? c.text : c.background,
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: c.line),
                      ),
                      child: Text(
                        m,
                        style: TextStyle(
                          fontSize: 14,
                          color: m == _muscle ? c.background : c.text,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_muscle != 'Cardio') ...[
              Text('Muscles worked', style: AppText.body(c)),
              const SizedBox(height: 2),
              Text('Tap: primary (counts a full set), again: secondary (half), again: off.',
                  style: AppText.quiet(c).copyWith(fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in Muscle.values)
                    GestureDetector(
                      key: ValueKey('muscle-${m.name}'),
                      onTap: () => setState(() {
                        _picked = true;
                        final next = ((_works[m] ?? 0) + 1) % 3;
                        if (next == 0) {
                          _works.remove(m);
                        } else {
                          _works[m] = next;
                        }
                        _syncHeads(m);
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _works[m] == 1 ? c.accent : (_works[m] == 2 ? c.accent.withAlpha(40) : c.background),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _works[m] == null ? c.line : c.accent),
                        ),
                        child: Text(
                          '${m.label}${_works[m] == 2 ? ' ½' : ''}',
                          style: AppText.body(c).copyWith(fontSize: 12.5, color: _works[m] == 1 ? Colors.white : c.text),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Muscle heads', style: AppText.body(c)),
              const SizedBox(height: 2),
              Text('Which parts it works most. Tap to change: main, some, a little, off.',
                  style: AppText.quiet(c).copyWith(fontSize: 12)),
              const SizedBox(height: 6),
              for (final m in Muscle.values)
                if (m.heads.any(_heads.containsKey) || _works.containsKey(m)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: Text(m.label, style: AppText.body(c).copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  for (final h in m.heads)
                    _HeadRow(
                      head: h,
                      level: _heads[h] ?? 0,
                      onTap: () => setState(() {
                        _headsChanged = true;
                        final next = ((_heads[h] ?? 0) + 3) % 4; // 3 -> 2 -> 1 -> 0 -> 3
                        if (next == 0) {
                          _heads.remove(h);
                        } else {
                          _heads[h] = next;
                        }
                      }),
                    ),
                ],
              const SizedBox(height: 10),
              if (widget.existing != null) ..._otherVersions(c),
            ],
            if (_muscle == 'Cardio')
              Text(
                'Cardio is logged as time and distance, with optional heart rate '
                'and calories.',
                style: AppText.quiet(c),
              )
            else
            SettingRow(
              label: 'Bodyweight exercise',
              note: 'Load counts your body weight plus any added weight',
              trailing: Toggle(
                label: 'Bodyweight exercise',
                value: _bodyweight,
                onChanged: (v) => setState(() => _bodyweight = v),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.existing != null) ...[
                  Expanded(
                    child: SmallButton(
                      label: 'Hide',
                      quiet: true,
                      onTap: () {
                        final e = _build(archived: true);
                        if (e != null) Navigator.of(context).pop(e);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: SmallButton(
                    label: 'Save',
                    onTap: () {
                      final e = _build();
                      if (e != null) Navigator.of(context).pop(e);
                    },
                  ),
                ),
              ],
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              Text(
                'Hiding removes it from the library and pickers. Its history stays.',
                style: AppText.quiet(c).copyWith(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Other versions" picked: the library opens that exercise next.
class _OpenOther {
  const _OpenOther(this.id);
  final String id;
}

/// One head in the exercise sheet: three dots and Main / Some / A little.
class _HeadRow extends StatelessWidget {
  const _HeadRow({required this.head, required this.level, required this.onTap});

  final MuscleHead head;
  final int level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Semantics(
      button: true,
      label: '${head.label}: ${level == 0 ? 'off' : emphasisLabel(level)}. Tap to change.',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('head-${head.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(head.part.isEmpty ? head.muscle.label : head.part, style: AppText.body(c).copyWith(fontSize: 14)),
              ),
              for (var i = 1; i <= 3; i++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: i <= level ? c.accent : c.line,
                    shape: BoxShape.circle,
                  ),
                ),
              SizedBox(
                width: 64,
                child: Text(
                  level == 0 ? 'Off' : emphasisLabel(level),
                  textAlign: TextAlign.right,
                  style: AppText.quiet(c).copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
