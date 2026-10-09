import '../services/ai_engine.dart';

/// Tools for training and food actions. Each prepares a card the user
/// confirms; the app finds what's meant (workouts, entries) itself.

const _day = {'type': 'string', 'description': 'today, yesterday, a weekday like monday, or YYYY-MM-DD.'};
const _meal = {'type': 'string', 'enum': ['breakfast', 'lunch', 'dinner', 'snack']};

const trainingTools = [
  AiTool(
    name: 'start_workout',
    description: 'Start one of the user\'s saved workouts now (opens it to log).',
    parameters: {'type': 'object', 'properties': {'workout': {'type': 'string'}}, 'required': ['workout']},
  ),
  AiTool(
    name: 'add_exercise_to_workout',
    description: 'Add an exercise to a saved workout.',
    parameters: {
      'type': 'object',
      'properties': {
        'workout': {'type': 'string'},
        'exercise': {'type': 'string', 'description': "e.g. 'Lateral raise 3x12 rest 1:30'"},
      },
      'required': ['workout', 'exercise'],
    },
  ),
  AiTool(
    name: 'remove_exercise_from_workout',
    description: 'Remove an exercise from a saved workout.',
    parameters: {
      'type': 'object',
      'properties': {'workout': {'type': 'string'}, 'exercise': {'type': 'string'}},
      'required': ['workout', 'exercise'],
    },
  ),
  AiTool(
    name: 'change_exercise_in_workout',
    description: 'Change sets, reps or rest for an exercise in a saved workout.',
    parameters: {
      'type': 'object',
      'properties': {
        'workout': {'type': 'string'},
        'exercise': {'type': 'string'},
        'sets': {'type': 'integer'},
        'reps_low': {'type': 'integer'},
        'reps_high': {'type': 'integer'},
        'rest_seconds': {'type': 'integer'},
      },
      'required': ['workout', 'exercise'],
    },
  ),
  AiTool(
    name: 'start_mesocycle',
    description: 'Start a training block (mesocycle) from saved workouts.',
    parameters: {
      'type': 'object',
      'properties': {
        'workouts': {'type': 'array', 'items': {'type': 'string'}},
        'weeks': {'type': 'integer', 'description': 'Working weeks, 2 to 12 (a deload week follows).'},
        'progression': {'type': 'string', 'enum': ['weight', 'sets', 'effort']},
        'days': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Weekday for each workout, in order.'},
        'name': {'type': 'string'},
      },
      'required': ['workouts'],
    },
  ),
];

const foodTools = [
  AiTool(
    name: 'move_food',
    description: 'Move logged food to another meal or day.',
    parameters: {
      'type': 'object',
      'properties': {'day': _day, 'meal': _meal, 'food': {'type': 'string'}, 'to_day': _day, 'to_meal': _meal},
      'required': ['day'],
    },
  ),
  AiTool(
    name: 'delete_food',
    description: 'Delete logged food (a whole meal if no food is named).',
    parameters: {
      'type': 'object',
      'properties': {'day': _day, 'meal': _meal, 'food': {'type': 'string'}},
      'required': ['day'],
    },
  ),
  AiTool(
    name: 'change_food_amount',
    description: 'Change how much of a logged food was eaten.',
    parameters: {
      'type': 'object',
      'properties': {
        'day': _day,
        'meal': _meal,
        'food': {'type': 'string'},
        'grams': {'type': 'number'},
        'servings': {'type': 'number', 'description': 'For recipes.'},
      },
      'required': ['day', 'food'],
    },
  ),
  AiTool(
    name: 'add_groceries',
    description: 'Add items to the grocery list.',
    parameters: {
      'type': 'object',
      'properties': {
        'items': {'type': 'array', 'items': {'type': 'string'}, 'description': "e.g. '12 eggs', '1 kg chicken breast', 'paper towels'"},
      },
      'required': ['items'],
    },
  ),
];

const goalsTools = [
  AiTool(
    name: 'set_goal',
    description: "Change the user's goal: lose, maintain or gain weight, a target weight, a weekly pace.",
    parameters: {
      'type': 'object',
      'properties': {
        'mode': {'type': 'string', 'enum': ['lose', 'maintain', 'gain']},
        'target_weight': {'type': 'number'},
        'pace_per_week': {'type': 'number', 'description': "In the user's units (lb or kg) per week."},
      },
    },
  ),
  AiTool(
    name: 'set_protein_target',
    description: 'Change the daily protein target.',
    parameters: {
      'type': 'object',
      'properties': {
        'grams_per_day': {'type': 'number'},
        'grams_per_kg': {'type': 'number'},
        'grams_per_lb': {'type': 'number'},
      },
    },
  ),
  AiTool(
    name: 'set_units',
    description: 'Switch between pounds (imperial) and kilograms (metric).',
    parameters: {'type': 'object', 'properties': {'units': {'type': 'string', 'enum': ['imperial', 'metric']}}, 'required': ['units']},
  ),
  AiTool(
    name: 'set_theme',
    description: 'Change the colour theme and/or dark mode.',
    parameters: {
      'type': 'object',
      'properties': {
        'theme': {'type': 'string', 'enum': ['earth', 'clay', 'stone', 'night', 'emerald']},
        'dark_at_night': {'type': 'string', 'enum': ['off', 'phone', 'hours']},
      },
    },
  ),
  AiTool(
    name: 'set_reminder',
    description: 'Set or turn off the morning weigh-in reminder.',
    parameters: {
      'type': 'object',
      'properties': {'time': {'type': 'string', 'description': "e.g. '7:30 am'"}, 'off': {'type': 'boolean'}},
    },
  ),
  AiTool(
    name: 'set_water_goal',
    description: 'Change the daily water goal.',
    parameters: {
      'type': 'object',
      'properties': {'amount': {'type': 'number'}, 'unit': {'type': 'string', 'enum': ['ml', 'l', 'oz', 'cups']}},
      'required': ['amount', 'unit'],
    },
  ),
  AiTool(
    name: 'set_sleep_goal',
    description: 'Change the nightly sleep goal.',
    parameters: {'type': 'object', 'properties': {'hours': {'type': 'number'}}, 'required': ['hours']},
  ),
  AiTool(
    name: 'set_week_start',
    description: 'Make weeks start on Sunday or Monday.',
    parameters: {'type': 'object', 'properties': {'day': {'type': 'string', 'enum': ['sunday', 'monday']}}, 'required': ['day']},
  ),
];

const dataTools = [
  AiTool(
    name: 'change_weight',
    description: "Fix (or add) a day's weigh-in.",
    parameters: {
      'type': 'object',
      'properties': {'day': _day, 'value': {'type': 'number'}, 'unit': {'type': 'string', 'enum': ['kg', 'lb']}},
      'required': ['day', 'value'],
    },
  ),
  AiTool(
    name: 'delete_weight',
    description: "Delete a day's weigh-in.",
    parameters: {'type': 'object', 'properties': {'day': _day}, 'required': ['day']},
  ),
  AiTool(
    name: 'change_sleep',
    description: "Fix a night's sleep (the night before the day given).",
    parameters: {
      'type': 'object',
      'properties': {'day': _day, 'hours': {'type': 'number'}, 'quality': {'type': 'integer', 'description': '1 to 5'}},
      'required': ['day'],
    },
  ),
  AiTool(
    name: 'delete_sleep',
    description: "Delete a night's sleep.",
    parameters: {'type': 'object', 'properties': {'day': _day}, 'required': ['day']},
  ),
  AiTool(
    name: 'change_set',
    description: 'Fix the weight or reps of a logged set.',
    parameters: {
      'type': 'object',
      'properties': {
        'day': _day,
        'exercise': {'type': 'string'},
        'set_number': {'type': 'integer', 'description': 'Which working set, from 1.'},
        'weight': {'type': 'number'},
        'reps': {'type': 'integer'},
      },
      'required': ['day', 'exercise'],
    },
  ),
  AiTool(
    name: 'delete_set',
    description: 'Delete a logged set.',
    parameters: {
      'type': 'object',
      'properties': {'day': _day, 'exercise': {'type': 'string'}, 'set_number': {'type': 'integer'}},
      'required': ['day', 'exercise'],
    },
  ),
  AiTool(
    name: 'delete_workout_session',
    description: 'Delete a whole logged workout.',
    parameters: {'type': 'object', 'properties': {'day': _day, 'workout': {'type': 'string'}}, 'required': ['day']},
  ),
];
