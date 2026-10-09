/// Which muscles each exercise works, and sets per muscle for the heatmap.
/// No Flutter imports: unit-tested.
library;

import '../ai/matcher.dart';
import 'exercise_heads.dart';
import 'models.dart';

enum Muscle {
  chest, frontDelts, sideDelts, rearDelts, biceps, triceps, forearms, abs, obliques,
  traps, upperBack, lats, lowerBack, glutes, quads, hamstrings, adductors, calves,
}

extension MuscleLabel on Muscle {
  String get label => switch (this) {
        Muscle.chest => 'Chest',
        Muscle.frontDelts => 'Front delts',
        Muscle.sideDelts => 'Side delts',
        Muscle.rearDelts => 'Rear delts',
        Muscle.biceps => 'Biceps',
        Muscle.triceps => 'Triceps',
        Muscle.forearms => 'Forearms',
        Muscle.abs => 'Abs',
        Muscle.obliques => 'Obliques',
        Muscle.traps => 'Traps',
        Muscle.upperBack => 'Upper back',
        Muscle.lats => 'Lats',
        Muscle.lowerBack => 'Lower back',
        Muscle.glutes => 'Glutes',
        Muscle.quads => 'Quads',
        Muscle.hamstrings => 'Hamstrings',
        Muscle.adductors => 'Adductors',
        Muscle.calves => 'Calves',
      };

  /// The parts of this muscle in the advanced map, in order.
  List<MuscleHead> get heads => [for (final h in MuscleHead.values) if (h.muscle == this) h];
}

/// The parts the advanced muscle map shows: a muscle's heads (triceps long,
/// lateral, medial), or regions people train separately (upper chest).
enum MuscleHead {
  chestUpper(Muscle.chest, 'Upper'),
  chestMiddle(Muscle.chest, 'Middle'),
  chestLower(Muscle.chest, 'Lower'),
  frontDelt(Muscle.frontDelts, ''),
  sideDelt(Muscle.sideDelts, ''),
  rearDelt(Muscle.rearDelts, ''),
  bicepsLong(Muscle.biceps, 'Long head'),
  bicepsShort(Muscle.biceps, 'Short head'),
  brachialis(Muscle.biceps, 'Brachialis'),
  tricepsLong(Muscle.triceps, 'Long head'),
  tricepsLateral(Muscle.triceps, 'Lateral head'),
  tricepsMedial(Muscle.triceps, 'Medial head'),
  forearmFlexors(Muscle.forearms, 'Flexors'),
  forearmExtensors(Muscle.forearms, 'Extensors'),
  brachioradialis(Muscle.forearms, 'Brachioradialis'),
  absUpper(Muscle.abs, 'Upper'),
  absLower(Muscle.abs, 'Lower'),
  obliques(Muscle.obliques, ''),
  trapsUpper(Muscle.traps, 'Upper'),
  trapsMiddle(Muscle.traps, 'Middle'),
  trapsLower(Muscle.traps, 'Lower'),
  rhomboids(Muscle.upperBack, 'Rhomboids'),
  teres(Muscle.upperBack, 'Teres major'),
  infraspinatus(Muscle.upperBack, 'Rotator cuff'),
  latsUpper(Muscle.lats, 'Upper'),
  latsLower(Muscle.lats, 'Lower'),
  erectors(Muscle.lowerBack, 'Spinal erectors'),
  gluteMax(Muscle.glutes, 'Gluteus maximus'),
  gluteMed(Muscle.glutes, 'Gluteus medius'),
  rectusFemoris(Muscle.quads, 'Rectus femoris'),
  vastusLateralis(Muscle.quads, 'Outer (vastus lateralis)'),
  vastusMedialis(Muscle.quads, 'Inner (vastus medialis)'),
  adductors(Muscle.adductors, ''),
  hamOuter(Muscle.hamstrings, 'Outer (biceps femoris)'),
  hamInner(Muscle.hamstrings, 'Inner'),
  calfInner(Muscle.calves, 'Inner'),
  calfOuter(Muscle.calves, 'Outer'),
  soleus(Muscle.calves, 'Soleus');

  const MuscleHead(this.muscle, this.part);

  final Muscle muscle;

  /// The part's own name ('' when the muscle is shown whole).
  final String part;

  /// "Triceps: Long head", or just "Side delts".
  String get label => part.isEmpty ? muscle.label : '${muscle.label}: $part';

  /// One line on what trains it most.
  String get tip => switch (this) {
        MuscleHead.chestUpper => 'Incline presses and low-to-high flyes hit it most.',
        MuscleHead.chestMiddle => 'Flat presses and flyes hit it most.',
        MuscleHead.chestLower => 'Dips, decline presses and high-to-low flyes hit it most.',
        MuscleHead.frontDelt => 'Overhead and incline presses already work it a lot.',
        MuscleHead.sideDelt => 'Lateral raises are the main way to train it.',
        MuscleHead.rearDelt => 'Rear delt flyes, face pulls and wide rows hit it most.',
        MuscleHead.bicepsLong => 'Works hardest with your arm behind your body, as in incline curls.',
        MuscleHead.bicepsShort => 'Works hardest with your arm in front of you, as in preacher curls.',
        MuscleHead.brachialis => 'Hammer, reverse and neutral-grip work hits it most.',
        MuscleHead.tricepsLong => 'It also crosses the shoulder, so it works hardest with your arms overhead.',
        MuscleHead.tricepsLateral => 'Pushdowns and close-grip presses hit it most.',
        MuscleHead.tricepsMedial => 'Works in every triceps exercise, especially reverse-grip pushdowns.',
        MuscleHead.forearmFlexors => 'Wrist curls and heavy holds (deadlifts, carries) train your grip.',
        MuscleHead.forearmExtensors => 'Reverse wrist curls and reverse curls hit it most.',
        MuscleHead.brachioradialis => 'Hammer and reverse curls hit it most.',
        MuscleHead.absUpper => 'Crunches and sit-ups hit it most.',
        MuscleHead.absLower => 'Leg and knee raises hit it most, though your abs always work as one.',
        MuscleHead.obliques => 'Twisting, or resisting a twist: side planks, woodchops, Pallof presses.',
        MuscleHead.trapsUpper => 'Shrugs, carries and upright rows hit it most.',
        MuscleHead.trapsMiddle => 'Rows that squeeze your shoulder blades together hit it most.',
        MuscleHead.trapsLower => 'Y raises and pulling down from overhead hit it most.',
        MuscleHead.rhomboids => 'Rows that squeeze your shoulder blades together hit it most.',
        MuscleHead.teres => 'Pulldowns and pull-ups work it along with your lats.',
        MuscleHead.infraspinatus => 'External rotations and face pulls hit it most.',
        MuscleHead.latsUpper => 'Wide-grip pulldowns and pull-ups hit it most.',
        MuscleHead.latsLower => 'Close-grip and single-arm pulls toward your hip hit it most.',
        MuscleHead.erectors => 'Deadlifts, back extensions and good mornings hit it most.',
        MuscleHead.gluteMax => 'Hip thrusts, deep squats and lunges hit it most.',
        MuscleHead.gluteMed => 'Hip abductions and single-leg work hit it most.',
        MuscleHead.rectusFemoris => 'It also crosses the hip, so leg extensions and sissy squats hit it most.',
        MuscleHead.vastusLateralis => 'Squats, leg presses and hack squats hit it most.',
        MuscleHead.vastusMedialis => 'Deep knee bends hit it most: full squats, split squats, leg extensions.',
        MuscleHead.adductors => 'Wide-stance squats, sumo deadlifts and the adduction machine hit it most.',
        MuscleHead.hamOuter => 'Leg curls and hip hinges (Romanian deadlifts) both work it.',
        MuscleHead.hamInner => 'Leg curls, especially seated ones, hit it most.',
        MuscleHead.calfInner => 'Straight-leg calf raises hit it most.',
        MuscleHead.calfOuter => 'Straight-leg calf raises hit it most.',
        MuscleHead.soleus => 'Bent-knee (seated) calf raises hit it most.',
      };
}

MuscleHead? headByName(String name) {
  for (final h in MuscleHead.values) {
    if (h.name == name) return h;
  }
  return null;
}

/// How much an exercise works a head: 3 main, 2 some, 1 a little.
String emphasisLabel(int level) => switch (level) { >= 3 => 'Main', 2 => 'Some', _ => 'A little' };

/// The share of a set a head gets: main 1, some 1/2, a little 1/4.
double emphasisShare(int level) => switch (level) { >= 3 => 1.0, 2 => 0.5, 1 => 0.25, _ => 0.0 };

/// "chestUpper:3 chestMiddle:2" -> {chestUpper: 3, chestMiddle: 2}, in order.
Map<MuscleHead, int> parseHeads(String text) {
  final out = <MuscleHead, int>{};
  for (final part in text.split(RegExp(r'\s+'))) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    final h = headByName(part.substring(0, i));
    final v = int.tryParse(part.substring(i + 1));
    if (h != null && v != null && v > 0) out[h] = v.clamp(1, 3);
  }
  return out;
}

/// Primary muscles: ones with a main head; secondary: the rest worked.
/// Muscles are listed in the order their heads first appear.
MuscleWork workFromHeads(Map<MuscleHead, int> heads) {
  final primary = <Muscle>[];
  final secondary = <Muscle>[];
  final best = <Muscle, int>{};
  for (final e in heads.entries) {
    final m = e.key.muscle;
    if (e.value > (best[m] ?? 0)) best[m] = e.value;
  }
  for (final h in heads.keys) {
    final m = h.muscle;
    if (primary.contains(m) || secondary.contains(m)) continue;
    (best[m]! >= 3 ? primary : secondary).add(m);
  }
  return MuscleWork(primary, secondary);
}

Muscle? muscleByName(String name) {
  for (final m in Muscle.values) {
    if (m.name == name) return m;
  }
  return null;
}

/// The muscles an exercise works: primary count a full set, secondary half.
class MuscleWork {
  const MuscleWork(this.primary, [this.secondary = const []]);
  final List<Muscle> primary;
  final List<Muscle> secondary;
  static const none = MuscleWork([]);
}

const _builtIn = <String, MuscleWork>{
  'bench_press': MuscleWork([Muscle.chest], [Muscle.frontDelts, Muscle.triceps]),
  'incline_bench': MuscleWork([Muscle.chest], [Muscle.frontDelts, Muscle.triceps]),
  'db_bench': MuscleWork([Muscle.chest], [Muscle.frontDelts, Muscle.triceps]),
  'incline_db_press': MuscleWork([Muscle.chest], [Muscle.frontDelts, Muscle.triceps]),
  'cable_fly': MuscleWork([Muscle.chest], [Muscle.frontDelts]),
  'push_up': MuscleWork([Muscle.chest], [Muscle.frontDelts, Muscle.triceps, Muscle.abs]),
  'dip': MuscleWork([Muscle.chest, Muscle.triceps], [Muscle.frontDelts]),
  'deadlift': MuscleWork([Muscle.hamstrings, Muscle.glutes, Muscle.lowerBack],
      [Muscle.traps, Muscle.quads, Muscle.forearms, Muscle.lats]),
  'barbell_row': MuscleWork([Muscle.upperBack, Muscle.lats], [Muscle.rearDelts, Muscle.biceps, Muscle.lowerBack]),
  'db_row': MuscleWork([Muscle.lats, Muscle.upperBack], [Muscle.rearDelts, Muscle.biceps]),
  'pull_up': MuscleWork([Muscle.lats], [Muscle.biceps, Muscle.upperBack, Muscle.forearms]),
  'chin_up': MuscleWork([Muscle.lats, Muscle.biceps], [Muscle.upperBack, Muscle.forearms]),
  'lat_pulldown': MuscleWork([Muscle.lats], [Muscle.biceps, Muscle.upperBack]),
  'cable_row': MuscleWork([Muscle.upperBack, Muscle.lats], [Muscle.rearDelts, Muscle.biceps]),
  'ohp': MuscleWork([Muscle.frontDelts], [Muscle.sideDelts, Muscle.triceps, Muscle.traps]),
  'db_shoulder_press': MuscleWork([Muscle.frontDelts], [Muscle.sideDelts, Muscle.triceps]),
  'arnold_press': MuscleWork([Muscle.frontDelts, Muscle.sideDelts], [Muscle.triceps]),
  'lateral_raise': MuscleWork([Muscle.sideDelts], [Muscle.traps]),
  'face_pull': MuscleWork([Muscle.rearDelts], [Muscle.upperBack, Muscle.traps]),
  'rear_delt_fly': MuscleWork([Muscle.rearDelts], [Muscle.upperBack]),
  'barbell_curl': MuscleWork([Muscle.biceps], [Muscle.forearms]),
  'db_curl': MuscleWork([Muscle.biceps], [Muscle.forearms]),
  'hammer_curl': MuscleWork([Muscle.biceps, Muscle.forearms]),
  'triceps_pushdown': MuscleWork([Muscle.triceps]),
  'skull_crusher': MuscleWork([Muscle.triceps]),
  'overhead_triceps': MuscleWork([Muscle.triceps]),
  'back_squat': MuscleWork([Muscle.quads, Muscle.glutes], [Muscle.hamstrings, Muscle.lowerBack]),
  'front_squat': MuscleWork([Muscle.quads], [Muscle.glutes, Muscle.abs]),
  'rdl': MuscleWork([Muscle.hamstrings, Muscle.glutes], [Muscle.lowerBack, Muscle.forearms]),
  'leg_press': MuscleWork([Muscle.quads, Muscle.glutes], [Muscle.hamstrings]),
  'walking_lunge': MuscleWork([Muscle.quads, Muscle.glutes], [Muscle.hamstrings]),
  'bulgarian_split_squat': MuscleWork([Muscle.quads, Muscle.glutes], [Muscle.hamstrings]),
  'leg_curl': MuscleWork([Muscle.hamstrings]),
  'leg_extension': MuscleWork([Muscle.quads]),
  'hip_thrust': MuscleWork([Muscle.glutes], [Muscle.hamstrings]),
  'calf_raise': MuscleWork([Muscle.calves]),
  'hanging_leg_raise': MuscleWork([Muscle.abs], [Muscle.obliques]),
  'cable_crunch': MuscleWork([Muscle.abs], [Muscle.obliques]),
};

/// A sensible guess from an exercise's broad group (Chest, Back, Legs...).
MuscleWork musclesForGroup(String group) => switch (group) {
      'Chest' => const MuscleWork([Muscle.chest], [Muscle.frontDelts, Muscle.triceps]),
      'Back' => const MuscleWork([Muscle.lats, Muscle.upperBack], [Muscle.biceps]),
      'Legs' => const MuscleWork([Muscle.quads, Muscle.glutes], [Muscle.hamstrings]),
      'Arms' => const MuscleWork([Muscle.biceps, Muscle.triceps], [Muscle.forearms]),
      'Shoulders' => const MuscleWork([Muscle.frontDelts, Muscle.sideDelts], [Muscle.triceps]),
      'Core' => const MuscleWork([Muscle.abs], [Muscle.obliques]),
      _ => MuscleWork.none,
    };

/// What [e] works: its own choice if set, else the built-in table, else a
/// guess from its group. Cardio works none (for the heatmap).
MuscleWork musclesOf(Exercise e) {
  if (e.cardio) return MuscleWork.none;
  if (e.primaryMuscles.isNotEmpty) {
    return MuscleWork(
      [for (final n in e.primaryMuscles) if (muscleByName(n) case final Muscle m) m],
      [for (final n in e.secondaryMuscles) if (muscleByName(n) case final Muscle m) m],
    );
  }
  final heads = e.heads.isNotEmpty ? _headsFromMap(e.heads) : null;
  if (heads != null && heads.isNotEmpty) return workFromHeads(heads);
  final known = _builtIn[e.id];
  if (known != null) return known;
  final table = exerciseHeadTable[e.id];
  if (table != null) return workFromHeads(parseHeads(table));
  return musclesForGroup(e.muscle);
}

Map<MuscleHead, int> _headsFromMap(Map<String, int> m) => {
      for (final e in m.entries)
        if (headByName(e.key) case final MuscleHead h) h: e.value.clamp(1, 3),
    };

/// Which heads [e] works and how much: its own choice if changed, else the
/// built-in table, else every head of its primary muscles (main) and
/// secondary ones (some). Cardio works none.
Map<MuscleHead, int> headsOf(Exercise e) {
  if (e.cardio) return const {};
  if (e.heads.isNotEmpty) {
    final own = _headsFromMap(e.heads);
    if (own.isNotEmpty) return own;
  }
  if (e.primaryMuscles.isEmpty) {
    final table = exerciseHeadTable[e.id];
    if (table != null) return parseHeads(table);
  }
  final w = musclesOf(e);
  return {
    for (final m in w.primary)
      for (final h in m.heads) h: 3,
    for (final m in w.secondary)
      for (final h in m.heads) h: 2,
  };
}

/// Sets per head in finished [sessions] dated [from]..[to]: each set counts
/// in full for a main head, half for some and a quarter for a little,
/// scaled by the set type like [setsPerMuscle].
Map<MuscleHead, double> setsPerHead(
  Iterable<Session> sessions, {
  required DateTime from,
  required DateTime to,
  required Exercise? Function(String id) exercise,
}) {
  final out = {for (final h in MuscleHead.values) h: 0.0};
  final cache = <String, Map<MuscleHead, int>>{};
  for (final x in sessions) {
    if (!_inRange(x.date, from, to)) continue;
    for (final set in x.sets) {
      if (!set.done) continue;
      final share = set.type.volumeShare;
      if (share == 0) continue;
      final heads = cache[set.exerciseId] ??= (() {
        final e = exercise(set.exerciseId);
        return e == null ? const <MuscleHead, int>{} : headsOf(e);
      })();
      for (final h in heads.entries) {
        out[h.key] = out[h.key]! + share * emphasisShare(h.value);
      }
    }
  }
  return out;
}

/// What counted toward [head]: (exercise id, sets, level), most first.
List<(String, double, int)> setsForHead(
  MuscleHead head,
  Iterable<Session> sessions, {
  required DateTime from,
  required DateTime to,
  required Exercise? Function(String id) exercise,
}) {
  final total = <String, double>{};
  final level = <String, int>{};
  for (final x in sessions) {
    if (!_inRange(x.date, from, to)) continue;
    for (final set in x.sets) {
      if (!set.done || set.type.volumeShare == 0) continue;
      final e = exercise(set.exerciseId);
      if (e == null) continue;
      final v = headsOf(e)[head];
      if (v == null) continue;
      total[e.id] = (total[e.id] ?? 0) + set.type.volumeShare * emphasisShare(v);
      level[e.id] = v;
    }
  }
  final list = [for (final e in total.entries) (e.key, e.value, level[e.key]!)];
  list.sort((a, b) => b.$2.compareTo(a.$2));
  return list;
}

/// Exercises in [library] that work [head] as a main part, by name.
List<Exercise> exercisesForHead(MuscleHead head, Iterable<Exercise> library) {
  final list = [
    for (final e in library)
      if (!e.archived && !e.cardio && (headsOf(e)[head] ?? 0) >= 3) e,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Barbell, Dumbbell, Cable, Machine, Kettlebell or Bodyweight (for the
/// library's filter); null when it can't tell.
String? equipmentOf(Exercise e) {
  if (e.cardio) return null;
  final known = exerciseEquipment[e.id];
  if (known != null) return known;
  final n = ' ${normalizeName(e.name)} ';
  if (n.contains(' smith ') || n.contains(' machine ') || n.contains(' pec deck ') || n.contains(' leg press ')) return 'Machine';
  if (n.contains(' cable ') || n.contains(' pulldown ') || n.contains(' pushdown ') || n.contains(' rope ')) return 'Cable';
  if (n.contains(' dumbbell ')) return 'Dumbbell';
  if (n.contains(' kettlebell ')) return 'Kettlebell';
  if (n.contains(' barbell ') || n.contains(' ez bar ') || n.contains(' trap bar ')) return 'Barbell';
  if (e.bodyweight) return 'Bodyweight';
  return null;
}

/// The filter chips in the exercise library.
const equipmentKinds = ['Barbell', 'Dumbbell', 'Cable', 'Machine', 'Bodyweight', 'Kettlebell'];

bool _inRange(DateTime d, DateTime from, DateTime to) => !d.isBefore(from) && !d.isAfter(to);

/// Sets per muscle in finished [sessions] dated [from]..[to] (whole days):
/// 1 for each primary muscle and 1/2 for each secondary one, scaled by the
/// set type (warm-ups 0, partial reps 1/2).
Map<Muscle, double> setsPerMuscle(
  Iterable<Session> sessions, {
  required DateTime from,
  required DateTime to,
  required Exercise? Function(String id) exercise,
}) {
  final out = {for (final m in Muscle.values) m: 0.0};
  for (final x in sessions) {
    if (!_inRange(x.date, from, to)) continue;
    for (final set in x.sets) {
      if (!set.done) continue;
      final share = set.type.volumeShare;
      if (share == 0) continue;
      final e = exercise(set.exerciseId);
      if (e == null) continue;
      final w = musclesOf(e);
      for (final m in w.primary) {
        out[m] = out[m]! + share;
      }
      for (final m in w.secondary) {
        out[m] = out[m]! + share / 2;
      }
    }
  }
  return out;
}

/// What counted toward [muscle]: (exercise id, sets, secondary?), most first.
List<(String, double, bool)> setsForMuscle(
  Muscle muscle,
  Iterable<Session> sessions, {
  required DateTime from,
  required DateTime to,
  required Exercise? Function(String id) exercise,
}) {
  final total = <String, double>{};
  final secondary = <String, bool>{};
  for (final x in sessions) {
    if (!_inRange(x.date, from, to)) continue;
    for (final set in x.sets) {
      if (!set.done || set.type.volumeShare == 0) continue;
      final e = exercise(set.exerciseId);
      if (e == null) continue;
      final w = musclesOf(e);
      final isPrimary = w.primary.contains(muscle);
      if (!isPrimary && !w.secondary.contains(muscle)) continue;
      total[e.id] = (total[e.id] ?? 0) + set.type.volumeShare * (isPrimary ? 1 : 0.5);
      secondary[e.id] = !isPrimary;
    }
  }
  final list = [for (final e in total.entries) (e.key, e.value, secondary[e.key]!)];
  list.sort((a, b) => b.$2.compareTo(a.$2));
  return list;
}

/// Heat level 0-4 for a number of sets (0, 1-4, 5-9, 10-19, 20+).
int heatLevel(double sets) => sets <= 0 ? 0 : sets < 5 ? 1 : sets < 10 ? 2 : sets < 20 ? 3 : 4;

/// "6" or "4.5".
String setsText(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

/// Name keywords -> the built-in exercise whose muscles a new one likely
/// shares. Most specific first ("leg curl" before "curl").
const _keywords = [
  ('leg press', 'leg_press'), ('leg curl', 'leg_curl'), ('leg extension', 'leg_extension'),
  ('hip thrust', 'hip_thrust'), ('romanian', 'rdl'), ('rdl', 'rdl'), ('stiff leg', 'rdl'),
  ('deadlift', 'deadlift'), ('split squat', 'bulgarian_split_squat'), ('lunge', 'walking_lunge'),
  ('step up', 'walking_lunge'), ('squat', 'back_squat'), ('calf', 'calf_raise'),
  ('leg raise', 'hanging_leg_raise'), ('crunch', 'cable_crunch'), ('sit up', 'cable_crunch'),
  ('incline', 'incline_bench'), ('bench', 'bench_press'), ('chest press', 'bench_press'),
  ('fly', 'cable_fly'), ('flye', 'cable_fly'), ('pec deck', 'cable_fly'), ('push up', 'push_up'),
  ('dip', 'dip'), ('pulldown', 'lat_pulldown'), ('pull down', 'lat_pulldown'), ('pull up', 'pull_up'),
  ('chin up', 'chin_up'), ('face pull', 'face_pull'), ('rear delt', 'rear_delt_fly'),
  ('reverse fly', 'rear_delt_fly'), ('row', 'barbell_row'), ('lateral raise', 'lateral_raise'),
  ('side raise', 'lateral_raise'), ('arnold', 'arnold_press'), ('shoulder press', 'ohp'),
  ('overhead press', 'ohp'), ('hammer curl', 'hammer_curl'), ('curl', 'barbell_curl'),
  ('pushdown', 'triceps_pushdown'), ('push down', 'triceps_pushdown'), ('skull', 'skull_crusher'),
  ('triceps', 'overhead_triceps'), ('shrug', 'deadlift'), ('press', 'ohp'),
];

/// The broad group for a set of muscles (Chest, Back, Legs...).
String groupFor(MuscleWork w) {
  if (w.primary.isEmpty) return 'Chest';
  return switch (w.primary.first) {
    Muscle.chest => 'Chest',
    Muscle.frontDelts || Muscle.sideDelts || Muscle.rearDelts => 'Shoulders',
    Muscle.biceps || Muscle.triceps || Muscle.forearms => 'Arms',
    Muscle.abs || Muscle.obliques => 'Core',
    Muscle.traps || Muscle.upperBack || Muscle.lats || Muscle.lowerBack => 'Back',
    _ => 'Legs',
  };
}

/// A best guess at what a new exercise works, from its name ("Hack squat"
/// works like a back squat). Null if the name gives no clue.
MuscleWork? guessMuscles(String name) {
  final n = ' ${normalizeName(name)} ';
  for (final (word, id) in _keywords) {
    if (n.contains(' $word ') || n.contains(' ${word}s ')) return _builtIn[id];
  }
  return null;
}
