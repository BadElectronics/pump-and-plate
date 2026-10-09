import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/catalog.dart';
import '../ai/facts.dart';
import '../ai/log_parser.dart';
import '../ai/matcher.dart';
import '../ai/paste_parser.dart';
import '../ai/plan_intents.dart';
import '../ai/router.dart';
import '../ai/tools.dart';
import '../calc/calc.dart';
import '../config.dart';
import '../data/models.dart';
import '../data/muscles.dart';
import '../services/ai_engine.dart';
import '../services/phone.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'ai_setup_screen.dart';
import 'draft_cards.dart';
import 'logger_screen.dart';

// ------------------------------------------------------------------ items

sealed class _Item {}

class _UserItem extends _Item {
  _UserItem(this.text);
  final String text;
}

class _AiItem extends _Item {
  String text = '';
  bool done = false;
}

class _NoteItem extends _Item {
  _NoteItem(this.text);
  final String text;
}

class _RecipeItem extends _Item {
  _RecipeItem(this.draft);
  final RecipeDraft draft;
  String? savedAs;
}

class _WorkoutItem extends _Item {
  _WorkoutItem(this.draft);
  final WorkoutDraft draft;
  String? savedAs;
}

class _LogItem extends _Item {
  _LogItem(this.intent);
  final LogIntent intent;
  String? savedAs;
}

class _PlanItem extends _Item {
  _PlanItem(this.intent);
  final PlanIntent intent;
  String? savedAs;
}

/// An action the AI prepared, waiting for Confirm.
class _ActionItem extends _Item {
  _ActionItem({required this.title, required this.lines, required this.confirmLabel, required this.onConfirm, this.warning, this.onUndo});
  final String title;
  final List<String> lines;
  final String confirmLabel;
  final String Function() onConfirm;
  final String? warning;
  final VoidCallback? onUndo;
  String? savedAs;
}

/// "Starting the AI..." while a model loads.
class _StatusItem extends _Item {
  _StatusItem(this.text);
  final String text;
}

/// Facts or findings from the user's data, shown as a short list.
class _FactsItem extends _Item {
  _FactsItem(this.title, this.lines);
  final String title;
  final List<String> lines;
}

// ------------------------------------------------------------------ prompt

const _system =
    'You are the assistant inside Pump and Plate, a private fitness and nutrition app that runs on the '
    "user's phone. Be brief, friendly and specific: a few sentences. "
    'When a message includes facts from the app, use those exact numbers and never invent others; '
    "if you don't have a number, say so. "
    "To log food, call log_food with each item as 'amount unit food' (for example '2 eggs'). "
    'To log a weigh-in, call log_weight. To log sleep, call log_sleep. To log water, call log_water. '
    "When the user gives you a recipe, call make_recipe with one ingredient per line as 'amount unit food'. "
    "When the user gives you a workout, call make_workout with one exercise per line as 'Exercise sets x reps @ load'. "
    'To put a workout on a day, call plan_workout. To plan a meal for a day, call plan_meal with the '
    "foods in items (for example ['1 egg', '2 slices toast']); if the user hasn't said which foods, ask "
    'them first instead of calling it. '
    'Other functions start or edit workouts, start a training block, move, change or delete logged food, '
    'add groceries, change goals and settings, and fix or delete past weigh-ins, sleep, sets and workouts; '
    'use them when asked. '
    "You can't change anything in the app yourself: functions only prepare a card the user checks and "
    "confirms. Never say something is added, planned, logged or saved; say you've prepared it to "
    "confirm. If there's no function for what's asked, say you can't do that yet. Don't give medical advice.";

const _tools = [
  AiTool(
    name: 'plan_workout',
    description: 'Prepare a workout on a day for the user to confirm. Use when asked to plan or schedule a workout.',
    parameters: {
      'type': 'object',
      'properties': {
        'workout': {'type': 'string', 'description': 'The workout name, e.g. "Push day" or "Upper A".'},
        'day': {'type': 'string', 'description': 'today, tomorrow, a weekday like friday, or YYYY-MM-DD.'},
      },
      'required': ['workout', 'day'],
    },
  ),
  AiTool(
    name: 'plan_meal',
    description: 'Prepare a planned meal on a day for the user to confirm. Use when asked to plan or schedule food.',
    parameters: {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': "Required unless planning a recipe: each food as 'amount unit food', e.g. '1 egg' or '150 g chicken breast'.",
        },
        'recipe': {'type': 'string', 'description': "A saved recipe's name, when planning a recipe."},
        'meal': {'type': 'string', 'enum': ['breakfast', 'lunch', 'dinner', 'snack']},
        'day': {'type': 'string', 'description': 'today, tomorrow, a weekday like friday, or YYYY-MM-DD.'},
      },
      'required': ['day'],
    },
  ),
  AiTool(
    name: 'log_food',
    description: 'Prepare a food log the user checks and saves. Use when the user says what they ate.',
    parameters: {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': "One food per item, as 'amount unit food', e.g. '2 eggs' or '150 g chicken breast'.",
        },
        'meal': {'type': 'string', 'enum': ['breakfast', 'lunch', 'dinner', 'snack']},
        'day': {'type': 'string', 'enum': ['today', 'yesterday']},
      },
      'required': ['items'],
    },
  ),
  AiTool(
    name: 'log_weight',
    description: 'Prepare a weigh-in the user checks and saves.',
    parameters: {
      'type': 'object',
      'properties': {
        'value': {'type': 'number'},
        'unit': {'type': 'string', 'enum': ['kg', 'lb']},
        'day': {'type': 'string', 'enum': ['today', 'yesterday']},
      },
      'required': ['value'],
    },
  ),
  AiTool(
    name: 'log_water',
    description: 'Prepare some water the user drank, to check and save.',
    parameters: {
      'type': 'object',
      'properties': {
        'amount': {'type': 'number'},
        'unit': {'type': 'string', 'enum': ['ml', 'l', 'oz', 'cups']},
        'day': {'type': 'string', 'enum': ['today', 'yesterday']},
      },
      'required': ['amount', 'unit'],
    },
  ),
  AiTool(
    name: 'log_sleep',
    description: "Prepare a night's sleep the user checks and saves.",
    parameters: {
      'type': 'object',
      'properties': {
        'hours': {'type': 'number'},
        'quality': {'type': 'integer', 'description': 'From 1 (poor) to 5 (great).'},
        'night': {'type': 'string', 'enum': ['last night', 'the night before']},
      },
      'required': ['hours'],
    },
  ),
  AiTool(
    name: 'make_recipe',
    description: 'Turn a recipe into a draft the user reviews and saves. Use whenever the user '
        'shares or asks you to read a recipe.',
    parameters: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'description': 'The recipe name.'},
        'servings': {'type': 'number', 'description': 'How many servings it makes.'},
        'ingredients': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': "One ingredient per item, as 'amount unit food', e.g. '2 cups rolled oats'.",
        },
        'steps': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': 'The method, one step per item.',
        },
      },
      'required': ['name', 'ingredients'],
    },
  ),
  AiTool(
    name: 'make_workout',
    description: 'Turn a workout into a draft the user reviews and saves. Use whenever the user '
        'shares or asks you to read a workout.',
    parameters: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string', 'description': "A short workout name, e.g. 'Push day'. Make one up if the user didn't give one."},
        'exercises': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': "One exercise per item, as 'Exercise sets x reps @ load', e.g. 'Squat 5x5 @ 225 lb'. "
              "Use only the sets, reps and load the user gave: never invent them. Without reps, write "
              "'Push-ups 3 sets'; without a load, leave out the @ part.",
        },
      },
      'required': ['exercises'],
    },
  ),
];

/// A list of lines from a function call (or one block of text, split up).
List<String> _strings(Object? v) => [
      if (v is List)
        for (final x in v)
          if ('$x'.trim().isNotEmpty) '$x'.trim(),
      if (v is String)
        for (final x in v.split(RegExp(r'\r?\n')))
          if (x.trim().isNotEmpty) x.trim(),
    ];

/// Hides any thinking text a model emits.
String _visible(String text) => text.replaceAll(RegExp(r'<think>[\s\S]*?(</think>|$)'), '').trim();

// ------------------------------------------------------------------ screen

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  /// Forgets the conversation (it's otherwise kept while the app runs).
  static void clearHistory() {
    _ChatScreenState._log.clear();
    _ChatScreenState._skipped = false;
    final chat = _ChatScreenState._chat;
    _ChatScreenState._chat = null;
    _ChatScreenState._chatTier = null;
    chat?.close();
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Kept while the app runs, so switching tabs doesn't lose the conversation.
  static final _log = <_Item>[];
  static bool _skipped = false;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  /// The AI conversation, kept with the history above so it survives leaving
  /// Chat (the AI still remembers the conversation when you come back). It's
  /// closed by Clear chat, Put AI away, a model switch, or the app freeing
  /// the model's memory.
  static AiChat? _chat;
  static AiTier? _chatTier;

  /// Which area's tools the conversation was opened with.
  static AiArea _chatArea = AiArea.general;

  /// The conversation was just restarted for another area: the next message
  /// carries a short recap so the AI keeps the thread.
  static bool _recapNext = false;

  AiTool _tool(String name) => _tools.firstWhere((t) => t.name == name);

  /// Only the tools for the area a message is about: a small model chooses
  /// better from a handful, and each tool takes up its limited memory.
  List<AiTool> _toolsFor(AiArea area) => switch (area) {
        AiArea.general => _tools,
        AiArea.training => [_tool('make_workout'), _tool('plan_workout'), ...trainingTools],
        AiArea.food => [_tool('log_food'), _tool('plan_meal'), _tool('make_recipe'), _tool('log_water'), ...foodTools],
        AiArea.goals => goalsTools,
        AiArea.data => [_tool('log_weight'), _tool('log_sleep'), ...dataTools],
      };

  /// The last few exchanges, for a conversation restarted with other tools.
  String _recap() {
    final lines = <String>[];
    // Skip the message being sent now (the last user item).
    final earlier = _log.sublist(0, (_log.lastIndexWhere((i) => i is _UserItem)).clamp(0, _log.length));
    for (final i in earlier.reversed) {
      if (lines.length >= 6) break;
      final text = switch (i) {
        _UserItem(:final text) => 'User: $text',
        _AiItem(:final text) when text.trim().isNotEmpty => 'Assistant: ${text.trim()}',
        _ => null,
      };
      if (text != null) lines.add(text.length > 220 ? '${text.substring(0, 220)}...' : text);
    }
    return lines.isEmpty ? '' : '(Earlier in this chat, for context:\n${lines.reversed.join('\n')})\n\n';
  }
  AiEngine? _engine;
  bool _busy = false;
  bool _stopping = false;

  bool _warming = false;

  /// "Put AI away" is running.
  bool _putting = false;

  /// "Free memory when Chat isn't used" (read here: settings can't be looked
  /// up in dispose).
  bool _idleUnload = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final first = _engine == null;
    _engine = ServicesScope.of(context).ai;
    _idleUnload = AppScope.of(context).settings.aiIdleUnload;
    if (first) {
      _engine!.cancelIdleUnload(); // back in Chat: keep the model
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _warmUp();
        _aiNotice();
      });
    }
  }

  /// Each time Chat opens with an AI model set up, until "Don't remind me
  /// again" is ticked: the AI is experimental and not for serious decisions.
  Future<void> _aiNotice() async {
    if (!mounted || _tier == null || !(_engine?.available ?? false)) return;
    final s = AppScope.of(context);
    if (s.settings.aiNoticeOff) return;
    final c = AppColors.of(context);
    var dontRemind = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          backgroundColor: c.surface,
          title: const Text('The AI is experimental'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'It runs on your phone and can be wrong or make things up. Don\'t rely on it '
                'for medical, injury, nutrition or other serious decisions: check with a '
                'qualified professional. It never changes anything without asking you first.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('ai-notice-off'),
                value: dontRemind,
                onChanged: (v) => setDialog(() => dontRemind = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: c.accent,
                title: const Text('Don\'t remind me again'),
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const ValueKey('ai-notice-ok'),
              onPressed: () => Navigator.of(dialog).pop(true),
              style: TextButton.styleFrom(foregroundColor: c.accent),
              child: const Text('I understand'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && dontRemind) s.setSettings(s.settings.copyWith(aiNoticeOff: true));
  }

  /// Starts loading the model as soon as Chat opens (off the UI thread), so
  /// the first message doesn't wait as long.
  Future<void> _warmUp() async {
    final tier = mounted ? _tier : null;
    final engine = _engine;
    if (tier == null || engine == null || engine.loadedTier == tier) return;
    setState(() => _warming = true);
    try {
      await engine.warmUp(modelFor(tier));
    } catch (_) {
      // A failed load is explained when a message is sent.
    } finally {
      if (mounted) setState(() => _warming = false);
    }
  }

  @override
  void dispose() {
    // The model and the conversation stay (freeing a model blocks the screen;
    // the app does that in the background instead). Only an answer still
    // being written is stopped, since nothing is left to show it.
    if (_busy) _chat?.stop();
    if (_idleUnload) _engine?.scheduleIdleUnload(const Duration(minutes: 5));
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _add(_Item item) {
    // An answer can finish after you've left Chat: keep it in the history
    // (you'll see it when you come back) without touching a closed screen.
    if (!mounted) {
      _log.add(item);
      return;
    }
    setState(() => _log.add(item));
    _toBottom();
  }

  AiTier? get _tier {
    final s = AppScope.of(context);
    final t = tierByName(s.settings.aiTier);
    return (t != null && ServicesScope.of(context).ai.available) ? t : null;
  }

  Future<AiChat?> _ensureChat({AiArea area = AiArea.general}) async {
    final tier = _tier;
    if (tier == null) return null;
    final engine = ServicesScope.of(context).ai;
    // The model may have been unloaded while the app was in the background.
    if (_chat != null && _chatTier == tier && engine.loadedTier == tier && _chatArea == area) return _chat;
    if (_chat != null && _chatTier == tier && engine.loadedTier == tier) _recapNext = true; // only the area changed
    final old = _chat;
    _chat = null;
    await old?.close();
    if (!mounted) return null;
    final ai = engine;
    final s = AppScope.of(context);
    // After restoring a backup on another phone, the setting can name a model
    // whose file isn't here: go back to setup.
    final installed = await ai.isInstalled(modelFor(tier));
    if (!mounted) return null;
    if (!installed) {
      s.setSettings(s.settings.copyWith(aiTier: null));
      _add(_NoteItem('The ${tier.label} model isn\'t on this phone anymore. Set it up again in Chat settings.'));
      return null;
    }
    // Loading takes a few seconds the first time: say so instead of pausing.
    _StatusItem? status;
    if (ai.loadedTier != tier) {
      status = _StatusItem('Starting ${tier.label} (${modelFor(tier).name}). The first message takes a few '
          'seconds while it loads; it stays loaded after that.');
      _add(status);
    }
    try {
      _chat = await ai.openChat(modelFor(tier), system: _system, tools: _toolsFor(area));
      _chatTier = tier;
      _chatArea = area;
      if (status != null && mounted) setState(() => _log.remove(status));
      return _chat;
    } catch (e) {
      if (status != null && mounted) setState(() => _log.remove(status));
      if (mounted) {
        // The engine's own message already names the model and what to do.
        _add(_NoteItem(e is AiFailure ? e.message : 'The AI model couldn\'t start: $e'));
      }
      return null;
    }
  }

  /// Text the parser reads well becomes a draft right away; messier text goes
  /// to the AI to tidy; anything else is a chat message.
  Future<void> _send([String? given]) async {
    final text = (given ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    _add(_UserItem(text));
    // "plan push day for tomorrow", "add oatmeal for breakfast on friday".
    final plan = _planFromCommand(text);
    if (plan != null) {
      _addPlan(plan);
      return;
    }
    // "weighed 182.4", "slept 7h", "breakfast: 2 eggs": ready to check and save.
    final log = parseLogIntent(text);
    if (log != null) {
      _add(_LogItem(log));
      return;
    }
    final kind = classifyPaste(text);
    // What the parser could read, kept in case the AI doesn't make a draft.
    _Item? fallback;
    if (kind == PasteKind.recipe) {
      final d = parseRecipe(text);
      if (d.ingredients.isNotEmpty) fallback = _RecipeItem(d);
      if (d.ingredients.isNotEmpty && (unreadShare(d.ingredients.length, d.skipped.length) <= 0.4 || _tier == null)) {
        _add(_RecipeItem(d));
        return;
      }
    } else if (kind == PasteKind.workout) {
      final d = parseWorkout(text);
      if (d.items.isNotEmpty) fallback = _WorkoutItem(d);
      if (d.items.isNotEmpty && (unreadShare(d.items.length, d.skipped.length) <= 0.4 || _tier == null)) {
        _add(_WorkoutItem(d));
        return;
      }
    }
    final facts = kind == PasteKind.none ? factsFor(AppScope.of(context), text) : '';
    if (_tier == null && facts.isNotEmpty) {
      _add(_FactsItem('From your data', facts.split('\n')));
      return;
    }
    if (_tier == null) {
      final available = ServicesScope.of(context).ai.available;
      _add(_NoteItem(kind != PasteKind.none
          ? 'Couldn\'t read that. Put each ingredient or exercise on its own line, like '
              '"2 cups rolled oats" or "Bench press 3x8 @ 185".'
          : available
              ? 'Set up the on-device AI (Chat settings, at the top) to chat. Without it, you can still '
                  'paste a recipe or workout, one ingredient or exercise per line, and save it.'
              : 'On-device AI isn\'t available on this phone, so Chat can\'t answer messages. You can '
                  'still paste a recipe or workout, one ingredient or exercise per line, and save it.'));
      return;
    }
    final drafts = _draftCount;
    await _askAi(text, prompt: facts.isEmpty ? null : '$text\n\n(Facts from the app. Use these exact numbers:\n$facts)');
    if (mounted && fallback != null && _draftCount == drafts) {
      _add(_NoteItem('Here\'s what could be read from it:'));
      _add(fallback);
    }
  }

  int get _draftCount =>
      _log.where((i) => i is _RecipeItem || i is _WorkoutItem || i is _LogItem || i is _PlanItem || i is _ActionItem).length;

  // ------------------------------------------------------------ actions

  Workout? _findWorkout(Object? name) {
    final q = '${name ?? ''}'.trim();
    if (q.isEmpty) return null;
    return bestMatch(q, AppScope.of(context).workouts, (w) => w.name, threshold: 0.5);
  }

  String _workoutList() {
    final names = [for (final w in AppScope.of(context).workouts) w.name];
    return names.isEmpty ? 'You have no saved workouts yet.' : 'Your workouts: ${names.join(', ')}.';
  }

  static String _clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  WorkoutItem? _findItem(Workout w, Object? exercise) {
    final q = '${exercise ?? ''}'.trim();
    if (q.isEmpty) return null;
    final s = AppScope.of(context);
    return bestMatch(exerciseKey(q), w.items, (i) => exerciseKey(s.exerciseName(i.exerciseId)), threshold: 0.5);
  }

  DateTime _dayAt(int offset) {
    final t = dateOnly(DateTime.now());
    return DateTime(t.year, t.month, t.day + offset);
  }

  Meal? _mealNamed(Object? v) {
    final t = '${v ?? ''}'.toLowerCase().trim();
    if (t == 'supper') return Meal.dinner;
    for (final m in Meal.values) {
      if (m.name == t) return m;
    }
    return null;
  }

  /// Logged food matching a day, meal and food name (all optional but day).
  List<FoodEntry> _findEntries(Map<String, dynamic> a) {
    final s = AppScope.of(context);
    final day = _dayAt(pastDayOffset(a['day']?.toString(), DateTime.now()) ?? 0);
    var list = s.entriesOn(day, _mealNamed(a['meal']));
    final food = '${a['food'] ?? ''}'.trim();
    if (food.isNotEmpty) {
      final key = normalizeName(food);
      list = [for (final e in list) if (normalizeName(e.name).contains(key) || nameScore(food, e.name) >= 0.5) e];
    }
    return list;
  }

  String _entryText(FoodEntry e) {
    final a = e.amount; // empty for calories-only entries
    final amount = a == null
        ? ''
        : e.kind == 'recipe'
            ? '${oneDecimal(a)} ${a == 1 ? 'serving' : 'servings'}'
            : (e.kind == 'food' ? '${a.round()} g' : '');
    return '${e.name}${amount.isEmpty ? '' : ', $amount'} (${e.meal.label}, ${shortDate(e.date)})';
  }

  void _action(String title, List<String> lines, String confirm, String Function() run, {String? warning, VoidCallback? undo}) =>
      _add(_ActionItem(title: title, lines: lines, confirmLabel: confirm, onConfirm: run, warning: warning, onUndo: undo));

  /// Training and food actions; true if [name] was one of them.
  bool _handleAction(String name, Map<String, dynamic> a, num? Function(Object?) n) {
    final s = AppScope.of(context);
    switch (name) {
      case 'start_workout':
        {
        final w = _findWorkout(a['workout']);
        if (w == null) {
          _add(_NoteItem('There\'s no workout called "${a['workout'] ?? ''}". ${_workoutList()}'));
          return true;
        }
        _action(
          'Start a workout',
          [w.name, for (final i in w.items) '· ${s.exerciseName(i.exerciseId)}, ${i.sets} × ${i.repsLow}–${i.repsHigh}'],
          'Start',
          () {
            final x = s.startSession(w);
            Navigator.of(context).push(LoggerScreen.route(x.id));
            return 'Started ${w.name}.';
          },
          warning: s.activeSession == null ? null : 'A workout is already in progress; this starts another one.',
        );
        return true;
        }
      case 'add_exercise_to_workout':
        {
        final w = _findWorkout(a['workout']);
        final text = '${a['exercise'] ?? ''}'.trim();
        if (w == null || text.isEmpty) {
          _add(_NoteItem(w == null ? 'There\'s no workout called "${a['workout'] ?? ''}". ${_workoutList()}' : 'Which exercise?'));
          return true;
        }
        final line = parseExerciseLine(text) ?? ExerciseLine(raw: text, name: text);
        final known = bestMatch(exerciseKey(line.name), [for (final e in s.exercises) if (!e.archived) e], (e) => exerciseKey(e.name));
        final sets = line.sets ?? 3;
        final lo = line.repsLow ?? 8, hi = line.repsHigh ?? line.repsLow ?? 12;
        final rest = line.restSec ?? 90;
        _action(
          'Add an exercise',
          [
            'Add ${known?.name ?? '${line.name} (new exercise)'} to ${w.name}',
            '$sets sets × $lo${hi != lo ? '–$hi' : ''} · rest ${_clock(rest)}',
          ],
          'Add',
          () {
            var id = known?.id;
            if (id == null) {
              final guess = guessMuscles(line.name);
              final e = Exercise(
                id: newId('x'),
                name: line.name[0].toUpperCase() + line.name.substring(1),
                muscle: guess == null ? 'Chest' : groupFor(guess),
                custom: true,
                primaryMuscles: [for (final m in guess?.primary ?? const <Muscle>[]) m.name],
                secondaryMuscles: [for (final m in guess?.secondary ?? const <Muscle>[]) m.name],
              );
              s.saveExercise(e);
              id = e.id;
            }
            final fresh = s.workoutById(w.id) ?? w;
            s.saveWorkout(fresh.copyWith(items: [
              ...fresh.items,
              WorkoutItem(exerciseId: id, sets: sets, repsLow: lo, repsHigh: hi, restSec: rest),
            ]));
            return 'Added ${s.exerciseName(id)} to ${w.name}.';
          },
        );
        return true;
        }
      case 'remove_exercise_from_workout':
      case 'change_exercise_in_workout':
        {
        final w = _findWorkout(a['workout']);
        final item = w == null ? null : _findItem(w, a['exercise']);
        if (w == null || item == null) {
          _add(_NoteItem(w == null
              ? 'There\'s no workout called "${a['workout'] ?? ''}". ${_workoutList()}'
              : '${w.name} has no exercise like "${a['exercise'] ?? ''}".'));
          return true;
        }
        final exName = s.exerciseName(item.exerciseId);
        if (name == 'remove_exercise_from_workout') {
          _action('Remove an exercise', ['Remove $exName from ${w.name}'], 'Remove', () {
            // Found by exercise in the current version of the workout.
            final fresh = s.workoutById(w.id) ?? w;
            final items = [...fresh.items];
            final k = items.indexWhere((i) => i.exerciseId == item.exerciseId);
            if (k >= 0) items.removeAt(k);
            s.saveWorkout(fresh.copyWith(items: items));
            return 'Removed $exName from ${w.name}.';
          });
          return true;
        }
        final sets = n(a['sets'])?.round();
        final lo = n(a['reps_low'])?.round();
        final hi = n(a['reps_high'])?.round() ?? lo;
        final rest = n(a['rest_seconds'])?.round();
        final changes = <String>[
          if (sets != null && sets > 0 && sets != item.sets) 'Sets: ${item.sets} → $sets',
          if (lo != null && lo > 0 && (lo != item.repsLow || hi != item.repsHigh))
            'Reps: ${item.repsLow}–${item.repsHigh} → $lo${hi != null && hi != lo ? '–$hi' : ''}',
          if (rest != null && rest > 0 && rest != item.restSec) 'Rest: ${_clock(item.restSec)} → ${_clock(rest)}',
        ];
        if (changes.isEmpty) {
          _add(_NoteItem('Nothing to change for $exName in ${w.name}.'));
          return true;
        }
        _action('Change $exName in ${w.name}', changes, 'Change', () {
          final fresh = s.workoutById(w.id) ?? w;
          final k = fresh.items.indexWhere((i) => i.exerciseId == item.exerciseId);
          s.saveWorkout(fresh.copyWith(items: [
            for (var j = 0; j < fresh.items.length; j++)
              j == k
                  ? fresh.items[j].copyWith(
                      sets: sets != null && sets > 0 ? sets : null,
                      repsLow: lo != null && lo > 0 ? lo : null,
                      repsHigh: lo != null && lo > 0 ? (hi ?? lo) : null,
                      restSec: rest != null && rest > 0 ? rest : null,
                    )
                  : fresh.items[j],
          ]));
          return 'Updated $exName in ${w.name}.';
        });
        return true;
        }
      case 'start_mesocycle':
        {
        final picked = <Workout>[
          for (final name in _strings(a['workouts']))
            if (_findWorkout(name) case final Workout w) w,
        ];
        if (picked.isEmpty) {
          _add(_NoteItem('Which workouts should the block use? ${_workoutList()}'));
          return true;
        }
        final weeks = (n(a['weeks'])?.round() ?? 4).clamp(2, 12);
        final progression = switch ('${a['progression'] ?? ''}'.toLowerCase()) {
          'sets' => MesoProgression.sets,
          'effort' => MesoProgression.effort,
          _ => MesoProgression.weight,
        };
        const spread = {1: [1], 2: [1, 4], 3: [1, 3, 5], 4: [1, 2, 4, 5], 5: [1, 2, 3, 4, 5], 6: [1, 2, 3, 4, 5, 6]};
        final days = [for (final d in _strings(a['days'])) _weekdayNumber(d)];
        final schedule = <int, String>{};
        final defaults = spread[picked.length.clamp(1, 6)]!;
        for (var i = 0; i < picked.length && i < 7; i++) {
          final day = i < days.length && days[i] != null ? days[i]! : (i < defaults.length ? defaults[i] : i + 1);
          schedule[day] = picked[i].id;
        }
        const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final clash = s.activeMeso ?? s.upcomingMeso;
        final label = '${a['name'] ?? ''}'.trim().isEmpty ? 'Block' : '${a['name']}'.trim();
        _action(
          'Start a training block',
          [
            '$label: $weeks weeks, then a deload week',
            'Progress by ${progression.label.toLowerCase()}',
            for (final e in (schedule.entries.toList()..sort((x, y) => x.key.compareTo(y.key))))
              '${dayNames[e.key - 1]}: ${s.workoutById(e.value)?.name ?? '?'}',
          ],
          'Start block',
          () {
            s.startMeso(Mesocycle(
              id: newId('m'),
              name: label,
              start: dateOnly(DateTime.now()),
              weeks: weeks,
              progression: progression,
              schedule: schedule,
            ));
            return 'Started $label: $weeks weeks. It\'s on your calendar.';
          },
          warning: clash == null ? null : '"${clash.name}" is already planned; only one block runs at a time.',
        );
        return true;
        }
      case 'move_food':
      case 'delete_food':
      case 'change_food_amount':
        {
        final found = _findEntries(a);
        if (found.isEmpty) {
          _add(_NoteItem('Nothing logged matches that (${[a['food'], a['meal'], a['day']].where((x) => x != null).join(', ')}).'));
          return true;
        }
        if (name == 'delete_food') {
          _action('Delete food', [for (final e in found) _entryText(e)], found.length == 1 ? 'Delete' : 'Delete ${found.length}', () {
            for (final e in found) {
              s.deleteEntry(e);
            }
            return 'Deleted ${found.length} ${found.length == 1 ? 'item' : 'items'}.';
          }, undo: () {
            for (final e in found) {
              s.restoreEntry(e);
            }
          });
          return true;
        }
        if (name == 'move_food') {
          final toOffset = pastDayOffset(a['to_day']?.toString(), DateTime.now()) ??
              daysAheadFrom(a['to_day']?.toString(), DateTime.now());
          final toMeal = _mealNamed(a['to_meal']);
          if (toOffset == null && toMeal == null) {
            _add(_NoteItem('Move it where? Say a meal or a day.'));
            return true;
          }
          _action(
            'Move food',
            [
              for (final e in found) _entryText(e),
              '→ ${(toMeal ?? found.first.meal).label}${toOffset == null ? '' : ', ${shortDate(_dayAt(toOffset))}'}',
            ],
            'Move',
            () {
              for (final e in found) {
                s.moveEntry(e, toOffset == null ? e.date : _dayAt(toOffset), toMeal ?? e.meal);
              }
              return 'Moved ${found.length} ${found.length == 1 ? 'item' : 'items'}.';
            },
          );
          return true;
        }
        final entry = found.first;
        final grams = n(a['grams']);
        final servings = n(a['servings']);
        final amount = entry.kind == 'recipe' ? (servings ?? grams) : (grams ?? servings);
        if (amount == null || amount <= 0 || entry.kind == 'quick') {
          _add(_NoteItem(entry.kind == 'quick'
              ? '${entry.name} was logged as calories only; edit it in the Food tab.'
              : 'How much ${entry.name}? Say it in ${entry.kind == 'recipe' ? 'servings' : 'grams'}.'));
          return true;
        }
        final unit = entry.kind == 'recipe' ? 'servings' : 'g';
        _action(
          'Change amount',
          ['${entry.name} (${entry.meal.label}, ${shortDate(entry.date)})', '${oneDecimal(entry.amount ?? 0)} $unit → ${oneDecimal(amount.toDouble())} $unit'],
          'Change',
          () {
            s.updateEntryAmount(entry, amount.toDouble());
            return 'Changed ${entry.name} to ${oneDecimal(amount.toDouble())} $unit.';
          },
        );
        return true;
        }
      case 'add_groceries':
        {
        final items = _strings(a['items']);
        if (items.isEmpty) {
          _add(_NoteItem('Which groceries?'));
          return true;
        }
        final foods = [for (final f in s.foods) if (!f.archived) f];
        final plan = <(String, Food?, double?)>[];
        for (final raw in items) {
          final line = parseIngredientLine(raw);
          final what = line?.name ?? raw;
          final f = bestMatch<Food>(what, foods, (f) => foodMainName(f.name));
          double? g;
          if (f != null) {
            final each = (f.gramsPerItem ?? 0) > 0 ? f.gramsPerItem : f.servingGrams;
            g = line == null ? each : gramsFor(line, foodName: f.name, gramsPerItem: each);
          }
          plan.add((raw, f, g));
        }
        _action(
          'Add to groceries',
          [
            for (final (raw, f, g) in plan)
              f == null ? '$raw (as a note)' : '${f.name}${g == null ? '' : ', ${g.round()} g'}',
          ],
          'Add',
          () {
            for (final (raw, f, g) in plan) {
              if (f != null) {
                s.addGroceryFood(f, g ?? f.servingGrams ?? 100);
              } else {
                s.saveGroceryItem(GroceryItem(id: newId('g'), label: raw));
              }
            }
            return 'Added ${plan.length} to your grocery list.';
          },
        );
        return true;
        }
    }
    return false;
  }

  // ------------------------------------------------------------ goals, settings, data

  bool get _imperial => AppScope.of(context).settings.units == Units.imperial;
  String _wt(double kg) => _imperial ? '${oneDecimal(kgToLb(kg))} lb' : '${oneDecimal(kg)} kg';

  /// "7:30 am", "7 pm", "19:00" -> minutes after midnight.
  static int? _clockMinutes(String text) {
    final m = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?', caseSensitive: false).firstMatch(text);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    final ap = (m.group(3) ?? '').toLowerCase();
    if (ap.startsWith('p') && h < 12) h += 12;
    if (ap.startsWith('a') && h == 12) h = 0;
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  /// A day for a logged thing; for sleep, "last night" is this morning's entry.
  DateTime _loggedDay(Object? day, {bool sleep = false}) {
    final t = '${day ?? ''}';
    if (sleep && RegExp(r'last night|this morning', caseSensitive: false).hasMatch(t)) return _dayAt(0);
    return _dayAt(pastDayOffset(t, DateTime.now()) ?? 0);
  }

  /// The logged sets of [exercise] on a day: (session, set index, set) in order.
  List<(Session, int, SetEntry)> _setsOn(DateTime day, String exercise) {
    final s = AppScope.of(context);
    final out = <(Session, int, SetEntry)>[];
    final key = exerciseKey(exercise);
    for (final x in s.sessions) {
      if (dateOnly(x.date) != day) continue;
      for (var i = 0; i < x.sets.length; i++) {
        final set = x.sets[i];
        if (set.warmup) continue;
        if (nameScore(key, exerciseKey(s.exerciseName(set.exerciseId))) >= 0.6) out.add((x, i, set));
      }
    }
    return out;
  }

  String _setText(SetEntry e) =>
      '${e.weightKg == null ? 'bodyweight' : _wt(e.weightKg!)} × ${e.reps ?? '?'}${e.type == SetType.normal ? '' : ' (${e.type.label.toLowerCase()})'}';

  /// Goals, settings and fixing past data; true if [name] was one of them.
  bool _handleMore(String name, Map<String, dynamic> a, num? Function(Object?) n) {
    final s = AppScope.of(context);
    final cfg = s.settings;
    final g = s.goal;
    switch (name) {
      case 'set_goal':
        {
          final mode = switch ('${a['mode'] ?? ''}'.toLowerCase()) {
            'lose' => GoalMode.lose,
            'gain' => GoalMode.gain,
            'maintain' => GoalMode.maintain,
            _ => null,
          };
          final target = n(a['target_weight'])?.toDouble();
          final pace = n(a['pace_per_week'])?.toDouble();
          final targetKg = target == null || target <= 0 ? null : (_imperial ? lbToKg(target) : target);
          final paceKg = pace == null || pace <= 0 ? null : (_imperial ? lbToKg(pace) : pace).clamp(0.05, 1.5).toDouble();
          String modeName(GoalMode m) => switch (m) { GoalMode.lose => 'lose', GoalMode.gain => 'gain', GoalMode.maintain => 'maintain' };
          final lines = <String>[
            if (mode != null && mode != g.mode) 'Goal: ${modeName(g.mode)} → ${modeName(mode)} weight',
            if (targetKg != null) 'Target: ${g.targetWeightKg == null ? 'none' : _wt(g.targetWeightKg!)} → ${_wt(targetKg)}',
            if (paceKg != null) 'Pace: ${_wt(g.paceKgPerWeek)} → ${_wt(paceKg)} a week',
          ];
          if (lines.isEmpty) {
            _add(_NoteItem('Nothing to change in your goal.'));
            return true;
          }
          _action('Change your goal', lines, 'Change', () {
            s.setGoal(s.goal.copyWith(mode: mode, targetWeightKg: targetKg ?? s.goal.targetWeightKg, paceKgPerWeek: paceKg));
            return 'Goal updated. Your calorie and protein targets follow it.';
          }, undo: () => s.setGoal(g));
          return true;
        }
      case 'set_protein_target':
        {
          final weight = s.currentWeightKg;
          final perKg = n(a['grams_per_kg'])?.toDouble() ??
              (n(a['grams_per_lb']) == null ? null : n(a['grams_per_lb'])!.toDouble() * 2.20462) ??
              (n(a['grams_per_day']) == null || weight == null ? null : n(a['grams_per_day'])!.toDouble() / weight);
          if (perKg == null || perKg <= 0 || perKg > 4) {
            _add(_NoteItem(weight == null && a['grams_per_day'] != null
                ? 'Log a weigh-in first, so a daily amount can be turned into your target.'
                : 'How much protein? Say grams a day, or per kg or lb of body weight.'));
            return true;
          }
          final daily = weight == null ? '' : ' (about ${(perKg * weight).round()} g a day)';
          _action('Change your protein target', [
            'Protein: ${g.proteinGPerKg.toStringAsFixed(1)} → ${perKg.toStringAsFixed(1)} g per kg$daily',
          ], 'Change', () {
            s.setGoal(s.goal.copyWith(proteinGPerKg: perKg));
            return 'Protein target updated.';
          }, undo: () => s.setGoal(g));
          return true;
        }
      case 'set_units':
        {
          final to = '${a['units']}'.toLowerCase() == 'metric' ? Units.metric : Units.imperial;
          if (to == cfg.units) {
            _add(_NoteItem('You\'re already using ${to == Units.metric ? 'kilograms' : 'pounds'}.'));
            return true;
          }
          _action('Change units', [to == Units.metric ? 'Pounds → kilograms (metric)' : 'Kilograms → pounds (imperial)'], 'Change', () {
            s.setSettings(s.settings.copyWith(units: to));
            return 'Units changed. Your data is the same, just shown in ${to == Units.metric ? 'kilograms' : 'pounds'}.';
          }, undo: () => s.setSettings(s.settings.copyWith(units: cfg.units)));
          return true;
        }
      case 'set_theme':
        {
          final themeName = '${a['theme'] ?? ''}'.toLowerCase();
          AppPalette? found;
          for (final p in AppPalette.all) {
            if (p.id == themeName) found = p;
          }
          final theme = found; // final, so it stays non-null inside the Confirm action
          final dark = '${a['dark_at_night'] ?? ''}'.toLowerCase();
          final lines = <String>[
            if (theme != null && theme.id != cfg.themeId) 'Theme: ${AppPalette.byId(cfg.themeId).name} → ${theme.name}',
            if (dark == 'off') 'Dark at night: off',
            if (dark == 'phone') 'Dark at night: follow the phone',
            if (dark == 'hours') 'Dark at night: set hours (${TimeOfDay(hour: cfg.darkFrom ~/ 60, minute: cfg.darkFrom % 60).format(context)} to ${TimeOfDay(hour: cfg.darkTo ~/ 60, minute: cfg.darkTo % 60).format(context)})',
          ];
          if (lines.isEmpty) {
            _add(_NoteItem('Which theme? Earth, Clay, Stone, Night or Emerald.'));
            return true;
          }
          _action('Change the look', lines, 'Change', () {
            var next = s.settings;
            if (theme != null) next = next.copyWith(themeId: theme.id);
            if (dark == 'off') next = next.copyWith(followSystem: false, darkSchedule: false);
            if (dark == 'phone') next = next.copyWith(followSystem: true, darkSchedule: false);
            if (dark == 'hours') next = next.copyWith(followSystem: false, darkSchedule: true);
            s.setSettings(next);
            return 'Done.';
          }, undo: () => s.setSettings(s.settings.copyWith(
                themeId: cfg.themeId,
                followSystem: cfg.followSystem,
                darkSchedule: cfg.darkSchedule,
              )));
          return true;
        }
      case 'set_reminder':
        {
          final off = a['off'] == true || '${a['off']}' == 'true';
          final minute = off ? null : _clockMinutes('${a['time'] ?? ''}');
          if (!off && minute == null) {
            _add(_NoteItem('What time should the weigh-in reminder be?'));
            return true;
          }
          String show(int? m) => m == null ? 'off' : TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);
          _action('Weigh-in reminder', ['Reminder: ${show(cfg.reminderMinute)} → ${show(minute)}'], 'Change', () {
            s.setSettings(s.settings.copyWith(reminderMinute: minute));
            return minute == null ? 'Reminder off.' : 'Reminder set for ${show(minute)}.';
          }, undo: () => s.setSettings(s.settings.copyWith(reminderMinute: cfg.reminderMinute)));
          return true;
        }
      case 'set_water_goal':
        {
          final v = n(a['amount'])?.toDouble();
          final per = switch ('${a['unit'] ?? ''}') { 'l' => 1000.0, 'oz' => 29.5735, 'cups' => mlPerCup, _ => 1.0 };
          if (v == null || v <= 0 || v * per > 8000) {
            _add(_NoteItem('How much water a day?'));
            return true;
          }
          _action('Water goal', [
            'Water: ${formatWater(s.waterGoalMl, imperial: _imperial)} → ${formatWater(v * per, imperial: _imperial)} a day',
          ], 'Change', () {
            s.setSettings(s.settings.copyWith(waterGoalMl: v * per));
            return 'Water goal updated.';
          }, undo: () => s.setSettings(s.settings.copyWith(waterGoalMl: cfg.waterGoalMl)));
          return true;
        }
      case 'set_sleep_goal':
        {
          final h = n(a['hours'])?.toDouble();
          if (h == null || h < 4 || h > 12) {
            _add(_NoteItem('How many hours of sleep (4 to 12)?'));
            return true;
          }
          _action('Sleep goal', ['Sleep: ${oneDecimal(cfg.sleepGoalHours)} → ${oneDecimal(h)} hours a night'], 'Change', () {
            s.setSettings(s.settings.copyWith(sleepGoalHours: h));
            return 'Sleep goal updated.';
          }, undo: () => s.setSettings(s.settings.copyWith(sleepGoalHours: cfg.sleepGoalHours)));
          return true;
        }
      case 'set_week_start':
        {
          final sunday = '${a['day']}'.toLowerCase().startsWith('sun');
          if (sunday == cfg.weekStartsSunday) {
            _add(_NoteItem('Weeks already start on ${sunday ? 'Sunday' : 'Monday'}.'));
            return true;
          }
          _action('Week start', ['Weeks start on ${sunday ? 'Monday → Sunday' : 'Sunday → Monday'}'], 'Change', () {
            s.setSettings(s.settings.copyWith(weekStartsSunday: sunday));
            return 'Weeks now start on ${sunday ? 'Sunday' : 'Monday'}.';
          }, undo: () => s.setSettings(s.settings.copyWith(weekStartsSunday: cfg.weekStartsSunday)));
          return true;
        }
      case 'change_weight':
      case 'delete_weight':
        {
          final day = _loggedDay(a['day']);
          final was = s.weighInOn(day);
          if (name == 'delete_weight') {
            if (was == null) {
              _add(_NoteItem('There\'s no weigh-in on ${shortDate(day)}.'));
              return true;
            }
            _action('Delete a weigh-in', ['${shortDate(day)}: ${_wt(was.weightKg)}'], 'Delete', () {
              s.deleteWeighIn(day);
              return 'Deleted the weigh-in for ${shortDate(day)}.';
            }, undo: () => s.logWeight(was.weightKg, day: day));
            return true;
          }
          final v = n(a['value'])?.toDouble();
          final unit = '${a['unit'] ?? ''}';
          if (v == null || v <= 0) {
            _add(_NoteItem('What weight?'));
            return true;
          }
          final kg = unit == 'kg' ? v : (unit == 'lb' ? lbToKg(v) : (_imperial ? lbToKg(v) : v));
          _action(was == null ? 'Add a weigh-in' : 'Fix a weigh-in', [
            '${shortDate(day)}: ${was == null ? 'none' : _wt(was.weightKg)} → ${_wt(kg)}',
          ], was == null ? 'Add' : 'Fix', () {
            s.logWeight(kg, day: day);
            return 'Weigh-in for ${shortDate(day)} is ${_wt(kg)}.';
          }, undo: () => was == null ? s.deleteWeighIn(day) : s.logWeight(was.weightKg, day: day));
          return true;
        }
      case 'change_sleep':
      case 'delete_sleep':
        {
          final day = _loggedDay(a['day'], sleep: true);
          final was = s.sleepOn(day);
          String show(SleepEntry? e) => e?.durationMin == null
              ? 'none'
              : '${oneDecimal(e!.durationMin! / 60)} h${e.quality == null ? '' : ', quality ${e.quality}'}';
          if (name == 'delete_sleep') {
            if (was == null) {
              _add(_NoteItem('There\'s no sleep logged for ${shortDate(day)}.'));
              return true;
            }
            _action('Delete sleep', ['Night before ${shortDate(day)}: ${show(was)}'], 'Delete', () {
              s.deleteSleep(day);
              return 'Deleted the sleep for ${shortDate(day)}.';
            }, undo: () => s.logSleep(was));
            return true;
          }
          final h = n(a['hours'])?.toDouble();
          final q = n(a['quality'])?.round();
          if ((h == null || h <= 0 || h > 16) && (q == null || q < 1 || q > 5)) {
            _add(_NoteItem('How long did you sleep, or how well (1 to 5)?'));
            return true;
          }
          final next = SleepEntry(
            date: day,
            durationMin: h != null && h > 0 && h <= 16 ? (h * 60).round() : was?.durationMin,
            // New hours replace the old bed and wake times; quality alone keeps them.
            bedMinute: h == null ? was?.bedMinute : null,
            wakeMinute: h == null ? was?.wakeMinute : null,
            quality: q != null && q >= 1 && q <= 5 ? q : was?.quality,
          );
          _action('Fix sleep', ['Night before ${shortDate(day)}: ${show(was)} → ${show(next)}'], 'Fix', () {
            s.logSleep(next);
            return 'Sleep for ${shortDate(day)} updated.';
          }, undo: () => was == null ? s.deleteSleep(day) : s.logSleep(was));
          return true;
        }
      case 'change_set':
      case 'delete_set':
        {
          final day = _loggedDay(a['day']);
          final exercise = '${a['exercise'] ?? ''}'.trim();
          final found = exercise.isEmpty ? <(Session, int, SetEntry)>[] : _setsOn(day, exercise);
          if (found.isEmpty) {
            _add(_NoteItem('No logged sets of "$exercise" on ${shortDate(day)}.'));
            return true;
          }
          final k = n(a['set_number'])?.round();
          if (k == null && found.length > 1) {
            _add(_NoteItem('Which set? ${s.exerciseName(found.first.$3.exerciseId)} on ${shortDate(day)} has ${found.length}: '
                '${[for (var i = 0; i < found.length; i++) '${i + 1}) ${_setText(found[i].$3)}'].join(', ')}.'));
            return true;
          }
          final pick = k == null ? 1 : k;
          if (pick < 1 || pick > found.length) {
            _add(_NoteItem('There are ${found.length} sets; say a number from 1 to ${found.length}.'));
            return true;
          }
          final (x, index, set) = found[pick - 1];
          final exName = s.exerciseName(set.exerciseId);
          if (name == 'delete_set') {
            _action('Delete a set', ['$exName, set $pick (${shortDate(day)}): ${_setText(set)}'], 'Delete', () {
              final now = s.sessions.firstWhere((y) => y.id == x.id, orElse: () => x);
              s.updateSession(now.copyWith(sets: [...now.sets]..removeAt(index)));
              return 'Deleted set $pick of $exName.';
            }, undo: () => s.updateSession(x));
            return true;
          }
          final w = n(a['weight'])?.toDouble();
          final reps = n(a['reps'])?.round();
          if ((w == null || w < 0) && (reps == null || reps <= 0)) {
            _add(_NoteItem('What should set $pick of $exName be (weight and reps)?'));
            return true;
          }
          final next = set.copyWith(
            weightKg: w == null || w < 0 ? set.weightKg : (_imperial ? lbToKg(w) : w),
            reps: reps == null || reps <= 0 ? set.reps : reps,
          );
          _action('Fix a set', ['$exName, set $pick (${shortDate(day)}): ${_setText(set)} → ${_setText(next)}'], 'Fix', () {
            final now = s.sessions.firstWhere((y) => y.id == x.id, orElse: () => x);
            final sets = [...now.sets];
            if (index < sets.length) sets[index] = next;
            s.updateSession(now.copyWith(sets: sets));
            return 'Fixed set $pick of $exName.';
          }, undo: () => s.updateSession(x));
          return true;
        }
      case 'delete_workout_session':
        {
          final day = _loggedDay(a['day']);
          var onDay = [for (final x in s.sessions) if (dateOnly(x.date) == day) x];
          final named = '${a['workout'] ?? ''}'.trim();
          if (named.isNotEmpty && onDay.length > 1) {
            final best = bestMatch(named, onDay, (x) => x.name, threshold: 0.5);
            if (best != null) onDay = [best];
          }
          if (onDay.isEmpty) {
            _add(_NoteItem('No workout logged on ${shortDate(day)}.'));
            return true;
          }
          if (onDay.length > 1) {
            _add(_NoteItem('${shortDate(day)} has ${onDay.length} workouts (${onDay.map((x) => x.name).join(', ')}). Which one?'));
            return true;
          }
          final session = onDay.single;
          final done = session.sets.where((e) => e.done).length;
          _action('Delete a workout', ['${session.name}, ${shortDate(day)}: $done ${done == 1 ? 'set' : 'sets'} logged'], 'Delete', () {
            s.discardSession(session);
            return 'Deleted ${session.name} from ${shortDate(day)}.';
          }, warning: 'Its sets leave your history and charts too.', undo: () => s.restoreSession(session));
          return true;
        }
    }
    return false;
  }

  /// 1 (Monday) ... 7 (Sunday) for a weekday name, or null.
  static int? _weekdayNumber(String d) {
    const names = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final t = d.toLowerCase().trim();
    for (var i = 0; i < 7; i++) {
      if (t.startsWith(names[i])) return i + 1;
    }
    return null;
  }

  /// The day of the last plan card in this chat.
  int? _lastPlanDays;

  void _addPlan(PlanIntent intent) {
    _lastPlanDays = intent.daysAhead;
    _add(_PlanItem(intent));
  }

  String? get _lastUserText {
    for (final i in _log.reversed) {
      if (i is _UserItem) return i.text;
    }
    return null;
  }

  /// Foods from a plan_meal call, in whatever shape the model sent them:
  /// "items" or "foods" or "food"..., as text, a list of text, or a list of
  /// {name, amount, unit} objects.
  List<String> _foodStrings(Map<String, dynamic> a) {
    for (final key in ['items', 'foods', 'food', 'item', 'ingredients', 'meal_items']) {
      final v = a[key];
      if (v == null) continue;
      final out = <String>[];
      if (v is String) out.addAll(_strings(v).expand((x) => x.split(RegExp(r',|\band\b'))));
      if (v is List) {
        for (final x in v) {
          if (x is Map) {
            final name = x['name'] ?? x['food'] ?? x['item'] ?? x['description'] ?? '';
            final amount = x['amount'] ?? x['quantity'] ?? x['qty'] ?? '';
            final unit = x['unit'] ?? '';
            out.add('$amount $unit $name'.trim());
          } else if ('$x'.trim().isNotEmpty) {
            out.add('$x'.trim());
          }
        }
      }
      final cleaned = [for (final x in out) if (x.trim().isNotEmpty) x.trim()];
      if (cleaned.isNotEmpty) return cleaned;
    }
    return const [];
  }

  /// Foods named in the user's latest message: "add an egg", "and 2 slices
  /// of toast". Generic words ("a meal", "food") don't count.
  List<IngredientLine> _foodsInUserText() {
    final t = _lastUserText;
    if (t == null) return const [];
    final body = t
        .replaceAll(RegExp(r'[?.!]'), ' ')
        .replaceFirst(RegExp(r'^\s*(?:can|could|would) you\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^\s*(?:please\s+)?(?:also\s+)?(?:add|plan|schedule|put|include|log)\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b(?:to|for|on|in|into)\s+(?:my\s+|the\s+|that\s+|this\s+)?(?:meal|plan|calendar|day|it)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b(?:for|at|as)\s+(?:breakfast|lunch|dinner|supper|snacks?|a snack)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b(?:today|tonight|tomorrow|(?:next\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b(?:too|as well|please)\b', caseSensitive: false), ' ');
    final items = foodIntentFrom(body.split(RegExp(r',|\band\b|\+|&', caseSensitive: false)))?.items ?? const [];
    const generic = {'meal', 'a meal', 'food', 'foods', 'something', 'it', 'that', 'breakfast', 'lunch', 'dinner', 'snack'};
    return [for (final i in items) if (!generic.contains(i.name.toLowerCase().trim())) i];
  }

  /// A typed plan command as a card: a workout if it names one of yours, a
  /// recipe if it names one, else foods (when it reads like food).
  PlanIntent? _planFromCommand(String text) {
    final cmd = parsePlanCommand(text, DateTime.now());
    if (cmd == null) return null;
    final s = AppScope.of(context);
    final w = bestMatch(cmd.subject, s.workouts, (x) => x.name, threshold: 0.5);
    if (w != null && cmd.meal == null) return PlanWorkoutIntent(w.name, cmd.daysAhead);
    final r = bestMatch(cmd.subject, s.recipes, (x) => x.name, threshold: 0.5);
    if (r != null) return PlanMealIntent(recipe: r.name, meal: cmd.meal, daysAhead: cmd.daysAhead);
    if (RegExp(r'workout|\bday\b|session|training|\bleg|\bpush\b|\bpull\b|upper|lower|cardio', caseSensitive: false)
        .hasMatch(cmd.subject)) {
      return PlanWorkoutIntent(cmd.subject, cmd.daysAhead);
    }
    // "plan a meal for tomorrow" opens an empty meal card; "add an egg
    // tomorrow" plans the egg.
    const generic = {'meal', 'a meal', 'food', 'something', 'breakfast', 'lunch', 'dinner', 'snack'};
    final parts = cmd.subject.split(RegExp(r',|\band\b|\+|&'));
    final foods = foodIntentFrom(parts, meal: cmd.meal);
    final items = [for (final i in foods?.items ?? const <IngredientLine>[]) if (!generic.contains(i.name.toLowerCase().trim())) i];
    final known = [for (final f in s.foods) if (!f.archived) f];
    final anyMatch = items.any((i) => bestMatch(i.name, known, (f) => foodMainName(f.name)) != null);
    // Foods you have (or a named meal) plan a meal; "a meal"/"food" alone opens
    // an empty meal card; anything else ("a reminder") is left to the AI.
    if (anyMatch || (cmd.meal != null && items.isNotEmpty)) {
      return PlanMealIntent(items: items, meal: cmd.meal, daysAhead: cmd.daysAhead);
    }
    if (items.isEmpty && RegExp(r'\b(?:meal|food)\b', caseSensitive: false).hasMatch(cmd.subject)) {
      return PlanMealIntent(meal: cmd.meal, daysAhead: cmd.daysAhead);
    }
    return null;
  }

  Future<void> _askAi(String text, {String? prompt, AiArea? area}) async {
    setState(() {
      _busy = true;
      _stopping = false;
    });
    try {
      final chat = await _ensureChat(area: area ?? routeMessage(text));
      if (chat == null || !mounted) return;
      final recap = _recapNext ? _recap() : '';
      _recapNext = false;
      await _run(chat, chat.send('$recap${prompt ?? text}'), 0);
    } catch (e) {
      // Often the conversation has outgrown the model's memory: start fresh.
      final old = _chat;
      _chat = null;
      _chatTier = null;
      await old?.close();
      if (mounted) _add(_NoteItem('That didn\'t work ($e). The AI starts a fresh conversation with your next message.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Streams one answer; a function call shows a draft, then the model is
  /// told it's on screen and may add a short reply.
  Future<void> _run(AiChat chat, Stream<AiEvent> stream, int depth) async {
    final item = _AiItem();
    _add(item);
    AiCall? call;
    await for (final e in stream) {
      if (!mounted || _stopping) break;
      switch (e) {
        case AiText(:final text):
          setState(() => item.text += text);
          _toBottom();
        case AiCall():
          call ??= e;
          _handleCall(e);
      }
    }
    item.done = true;
    if (mounted && _visible(item.text).isEmpty) setState(() => _log.remove(item));
    final made = call;
    if (made != null && depth < 1 && mounted && !_stopping) {
      await _run(chat, chat.sendToolResult(made.name, {'status': 'shown to the user to check and save'}), depth + 1);
    }
  }

  /// Starts an email to us about an AI answer that was wrong, harmful or
  /// offensive. The person sees and can edit everything before sending.
  Future<void> _reportReply(String reply) async {
    final tier = tierByName(AppScope.of(context).settings.aiTier);
    final model = tier == null ? 'unknown model' : modelFor(tier).name;
    final quoted = reply.length > 1500 ? '${reply.substring(0, 1500)}...' : reply;
    final ok = await Phone.email(
      to: supportEmail,
      subject: '$appName: AI reply report',
      body: 'What was wrong with this reply:\n\n\n'
          '---\nThe reply:\n$quoted\n---\n$appName $buildLabel, $model',
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No email app opened. Write to $supportEmail and paste the reply.'),
      ));
    }
  }

  /// Handles an AI function call by showing a card, and nothing else: the
  /// AI never changes data by itself. Checked on every call (in development
  /// builds and tests, any data written here stops with an error).
  void _handleCall(AiCall call) {
    final s = AppScope.of(context);
    final before = s.writeCount;
    _prepareCard(call);
    assert(
      s.writeCount == before,
      'AI call "${call.name}" changed data without a confirmation card. '
      'Tool handlers may only add cards; changes happen on the card\'s button.',
    );
  }

  void _prepareCard(AiCall call) {
    final a = call.args;
    num? n(Object? v) => v is num ? v : num.tryParse('$v');
    if (_handleAction(call.name, a, n)) return;
    if (_handleMore(call.name, a, n)) return;
    if (call.name == 'plan_workout' || call.name == 'plan_meal') {
      // No day given: the day of the last plan in this chat ("add an egg"
      // after "a meal tomorrow"), else today. The card can change it.
      final days = daysAheadFrom(a['day']?.toString(), DateTime.now()) ?? _lastPlanDays ?? 0;
      if (call.name == 'plan_workout') {
        final name = (a['workout'] ?? a['name'] ?? '').toString().trim();
        _addPlan(PlanWorkoutIntent(name.isEmpty ? (_lastUserText ?? '') : name, days));
        return;
      }
      final recipe = a['recipe']?.toString().trim();
      var items = foodIntentFrom(_foodStrings(a))?.items ?? const <IngredientLine>[];
      // The model may leave the foods out; take them from what was just typed.
      if (items.isEmpty && (recipe == null || recipe.isEmpty)) items = _foodsInUserText();
      // Always a card: with no foods it opens empty, with "Add a food".
      _addPlan(PlanMealIntent(
        items: items,
        recipe: recipe == null || recipe.isEmpty ? null : recipe,
        meal: a['meal']?.toString(),
        daysAhead: days,
      ));
      return;
    }
    if (call.name == 'log_food') {
      final i = foodIntentFrom(_strings(a['items']), meal: a['meal']?.toString(), daysAgo: a['day'] == 'yesterday' ? 1 : 0);
      _add(i == null ? _NoteItem('The AI couldn\'t tell which foods to log.') : _LogItem(i));
      return;
    }
    if (call.name == 'log_weight') {
      final v = n(a['value']);
      final u = a['unit']?.toString();
      _add(v == null || v <= 0
          ? _NoteItem('The AI couldn\'t tell the weight.')
          : _LogItem(WeightIntent(v.toDouble(), unit: u == 'kg' || u == 'lb' ? u : null, daysAgo: a['day'] == 'yesterday' ? 1 : 0)));
      return;
    }
    if (call.name == 'log_water') {
      final v = n(a['amount']);
      final per = switch (a['unit']?.toString()) { 'l' => 1000.0, 'oz' => 29.5735, 'cups' => 236.588, _ => 1.0 };
      _add(v == null || v <= 0 || v * per > 6000
          ? _NoteItem('The AI couldn\'t tell how much water.')
          : _LogItem(WaterIntent(v * per, daysAgo: a['day'] == 'yesterday' ? 1 : 0)));
      return;
    }
    if (call.name == 'log_sleep') {
      final h = n(a['hours']);
      final q = n(a['quality'])?.round();
      _add(h == null || h <= 0 || h > 16
          ? _NoteItem('The AI couldn\'t tell how long you slept.')
          : _LogItem(SleepIntent((h * 60).round(),
              quality: q != null && q >= 1 && q <= 5 ? q : null, daysAgo: a['night'] == 'the night before' ? 1 : 0)));
      return;
    }
    if (call.name == 'make_recipe') {
      final lines = [
        '${call.args['name'] ?? 'Recipe'}',
        if (call.args['servings'] != null) 'Serves ${call.args['servings']}',
        'Ingredients',
        ..._strings(call.args['ingredients']),
        'Directions',
        ..._strings(call.args['steps']),
      ];
      final d = parseRecipe(lines.join('\n'));
      _add(d.ingredients.isEmpty ? _NoteItem('The AI couldn\'t find ingredients with amounts in that.') : _RecipeItem(d));
    } else if (call.name == 'make_workout') {
      final given = '${call.args['name'] ?? ''}'.trim();
      final lines = [
        // The first line is read as the name; the AI's drafts aren't "pasted".
        given.isEmpty ? 'New workout' : given,
        ..._strings(call.args['exercises']),
      ];
      final d = parseWorkout(lines.join('\n'));
      _add(d.items.isEmpty ? _NoteItem('The AI couldn\'t find exercises with sets in that.') : _WorkoutItem(d));
    }
  }

  /// Coaching: the app finds what's worth acting on; the AI (if set up)
  /// turns it into a few friendly suggestions.
  Future<void> _coach() async {
    if (_busy) return;
    final s = AppScope.of(context);
    const ask = 'How am I doing?';
    _add(_UserItem(ask));
    final findings = coachingFindings(s);
    if (_tier == null) {
      _add(_FactsItem(
        'How you\'re doing',
        findings.isEmpty ? ['Nothing needs attention right now. Keep logging and it\'ll spot trends as they appear.'] : findings,
      ));
      return;
    }
    final facts = factsFor(s, ask);
    final prompt = findings.isEmpty
        ? 'Nothing in my data needs attention. Give me one or two sentences of encouragement, using these facts '
            'from the app (exact numbers):\n$facts'
        : 'Give me 2 to 4 short, specific suggestions, one per finding, based on these findings from the app '
            '(use the exact numbers):\n- ${findings.join('\n- ')}\n\nMore facts:\n$facts';
    await _askAi(ask, prompt: prompt, area: AiArea.general);
  }

  /// "Put AI away": stops any answer, clears anything stuck on screen and
  /// frees the model. If the engine doesn't respond within 5 seconds, offers
  /// to restart the app, the one sure way to clear a frozen engine.
  Future<void> _putAway() async {
    final engine = ServicesScope.of(context).ai;
    final s = AppScope.of(context);
    setState(() {
      _putting = true;
      _stopping = true;
      _busy = false;
      _warming = false;
      _log.removeWhere((i) => i is _StatusItem);
    });
    _chat = null;
    _chatTier = null;
    final finished = Completer<bool>();
    final timer = Timer(const Duration(seconds: 5), () {
      if (!finished.isCompleted) finished.complete(false);
    });
    engine.forceUnload().whenComplete(() {
      if (!finished.isCompleted) finished.complete(true);
    });
    final ok = await finished.future;
    timer.cancel();
    if (!mounted) return;
    setState(() {
      _putting = false;
      _stopping = false;
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI put away. Memory freed. Your next message loads it again.')),
      );
      return;
    }
    final c = AppColors.of(context);
    final restart = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('The AI isn\'t responding'),
        content: const Text(
          'It didn\'t stop within a few seconds. Restarting Pump and Plate fully clears it. Everything you\'ve '
          'logged is already saved.\n\nThe app will close; open it again from your home screen.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('ai-wait'),
            onPressed: () => Navigator.of(d).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Wait'),
          ),
          TextButton(
            key: const ValueKey('ai-restart'),
            onPressed: () => Navigator.of(d).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.accent),
            child: const Text('Restart the app'),
          ),
        ],
      ),
    );
    if (restart != true) return;
    // Make sure every change is written before the app closes.
    await s.settle();
    exit(0);
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    await _chat?.stop();
  }

  void _prefill(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _pasteAndSend(String what) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Copy a $what first (select it and tap Copy), then tap here.')));
      return;
    }
    await _send(text);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(AiSetupScreen.route());
    if (!mounted) return;
    if (_chatTier != _tier) {
      final old = _chat;
      _chat = null;
      _chatTier = null;
      await old?.close();
    }
    if (mounted) setState(() {});
  }

  Widget _bubble(AppColors c, _Item item) {
    switch (item) {
      case _UserItem(:final text):
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(18)),
              child: Text(text, style: TextStyle(color: c.onAccent, fontSize: 15, height: 1.35)),
            ),
          ),
        );
      case _AiItem():
        final shown = _visible(item.text);
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
                  child: shown.isEmpty && !item.done
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                        )
                      : SelectableText(shown, style: AppText.body(c).copyWith(fontSize: 15, height: 1.4)),
                ),
                // Lets anyone flag a bad or offensive answer (Google Play's AI
                // rules). It only opens an email; nothing is sent until they
                // tap Send there.
                if (item.done && shown.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('ai-report'),
                    onPressed: () => _reportReply(shown),
                    icon: Icon(Icons.flag_outlined, size: 15, color: c.muted),
                    label: Text('Report', style: AppText.quiet(c).copyWith(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: c.muted,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        );
      case _NoteItem(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(text, textAlign: TextAlign.center, style: AppText.quiet(c).copyWith(fontSize: 13)),
        );
      case _RecipeItem():
        return RecipeDraftCard(
          key: ObjectKey(item),
          draft: item.draft,
          savedAs: item.savedAs,
          onSaved: (n) => item.savedAs = n,
        );
      case _ActionItem():
        return ActionCard(
          key: ObjectKey(item),
          title: item.title,
          lines: item.lines,
          confirmLabel: item.confirmLabel,
          onConfirm: item.onConfirm,
          warning: item.warning,
          onUndo: item.onUndo,
          savedAs: item.savedAs,
          onSaved: (t) => item.savedAs = t,
        );
      case _PlanItem():
        return PlanDraftCard(
          key: ObjectKey(item),
          intent: item.intent,
          savedAs: item.savedAs,
          onSaved: (n) => item.savedAs = n,
        );
      case _StatusItem(:final text):
        return Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppText.quiet(c).copyWith(fontSize: 13))),
          ],
        );
      case _LogItem():
        return LogDraftCard(
          key: ObjectKey(item),
          intent: item.intent,
          savedAs: item.savedAs,
          onSaved: (n) => item.savedAs = n,
        );
      case _FactsItem(:final title, :final lines):
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(), style: AppText.label(c).copyWith(fontSize: 11, letterSpacing: 0.8, color: c.accent)),
              const SizedBox(height: 6),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l, style: AppText.body(c).copyWith(fontSize: 14, height: 1.35)),
                ),
            ],
          ),
        );
      case _WorkoutItem():
        return WorkoutDraftCard(
          key: ObjectKey(item),
          draft: item.draft,
          savedAs: item.savedAs,
          onSaved: (n) => item.savedAs = n,
        );
    }
  }

  Widget _empty(AppColors c, bool aiOn) {
    Widget chip(String label, IconData icon, String what) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: () => _pasteAndSend(what),
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.text,
              side: BorderSide(color: c.line),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Icon(Icons.chat_bubble_outline_rounded, size: 34, color: c.accent),
        const SizedBox(height: 10),
        Text(
          aiOn
              ? 'Paste a recipe or a workout and it becomes a draft you can check and save. '
                  'Or ask anything about training and food.'
              : 'Paste a recipe or a workout, one ingredient or exercise per line, and it becomes a '
                  'draft you can check and save.',
          textAlign: TextAlign.center,
          style: AppText.body(c).copyWith(fontSize: 15, height: 1.4),
        ),
        if (aiOn) ...[
          const SizedBox(height: 14),
          const AiPrivacyNote(),
        ],
        const SizedBox(height: 18),
        chip('Paste a recipe', Icons.restaurant_menu_rounded, 'recipe'),
        chip('Paste a workout', Icons.fitness_center_rounded, 'workout'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final ai = ServicesScope.of(context).ai;
    final tier = tierByName(s.settings.aiTier);
    if (tier == null && !_skipped && ai.available) {
      return SafeArea(
        bottom: false,
        child: AiSetupView(
          onSkip: () => setState(() => _skipped = true),
          onReady: () => setState(() {}),
        ),
      );
    }
    final aiOn = _tier != null;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chat', style: AppText.title(c)),
                      Text(
                        _warming && tier != null
                            ? 'Getting ${tier.label} ready…'
                            : aiOn && tier != null
                                ? '${modelFor(tier).name} · on your phone'
                                : 'No AI model · pasting still works',
                        style: AppText.quiet(c).copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (_log.isNotEmpty && !_busy)
                  IconButton(
                    tooltip: 'Clear chat',
                    onPressed: () async {
                      final old = _chat;
                      _chat = null;
                      _chatTier = null;
                      setState(() => _log.clear());
                      await old?.close();
                    },
                    icon: Icon(Icons.delete_sweep_outlined, color: c.muted),
                  ),
                if (ai.available && tier != null)
                  _putting
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          key: const ValueKey('ai-put-away'),
                          tooltip: 'Put AI away',
                          onPressed: _putAway,
                          icon: Icon(Icons.power_settings_new_rounded, color: c.muted),
                        ),
                if (ai.available)
                  IconButton(
                    tooltip: 'Chat settings',
                    onPressed: _busy ? null : _openSettings,
                    icon: Icon(Icons.tune_rounded, color: c.muted),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _log.isEmpty
                ? _empty(c, aiOn)
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _log.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _bubble(c, _log[i]),
                  ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (label, action) in <(String, VoidCallback)>[
                  ('How am I doing?', _coach),
                  ('Log breakfast', () => _prefill('breakfast: ')),
                  ('Weight trend', () => _send('How is my weight trending?')),
                  ('Sleep this week', () => _send('How did I sleep this week?')),
                  ('Food today', () => _send('How much protein and calories do I have left today?')),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                    child: ActionChip(
                      label: Text(label, style: AppText.body(c).copyWith(fontSize: 13)),
                      onPressed: _busy ? null : action,
                      backgroundColor: c.surface,
                      side: BorderSide(color: c.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            // The shell already ends this page just above the tab bar.
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(left: 14),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('chat-input'),
                            controller: _input,
                            minLines: 1,
                            maxLines: 5,
                            cursorColor: c.accent,
                            textCapitalization: TextCapitalization.sentences,
                            style: AppText.body(c).copyWith(fontSize: 15),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: aiOn ? 'Message, or paste a recipe or workout' : 'Paste a recipe or workout',
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Paste',
                          onPressed: () async {
                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                            final t = data?.text ?? '';
                            if (t.isNotEmpty) {
                              _input.text = t;
                              _input.selection = TextSelection.collapsed(offset: t.length);
                            }
                          },
                          icon: Icon(Icons.content_paste_rounded, color: c.muted, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.filled(
                    key: const ValueKey('chat-send'),
                    tooltip: _busy ? 'Stop' : 'Send',
                    onPressed: _busy ? _stop : () => _send(),
                    style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent),
                    icon: Icon(_busy ? Icons.stop_rounded : Icons.arrow_upward_rounded),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
