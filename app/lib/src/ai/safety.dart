/// Catches messages about suicide, self-harm or eating-disorder behaviour
/// before they reach the on-device model. The chat then shows a fixed,
/// written-by-people message with crisis resources instead of an AI answer:
/// a small model can't be trusted to respond well to these.
///
/// The patterns aim at clear statements and leave gym talk alone ("leg day
/// killed me", "cutting phase", "suicide sprints", "I hurt my shoulder").
library;

enum SafetyConcern { none, selfHarm, eatingDisorder }

final _selfHarm = <RegExp>[
  RegExp(r"\b(kill|killing|harm|harming)\s+my\s*self\b"),
  RegExp(r"\bself[\s-]?harm"),
  RegExp(r"\bsuicidal"),
  // "suicide", but not the running drill ("suicide sprints", "did suicides").
  RegExp(r"\bsuicide\b(?!\s+(sprints?|runs?|drills?|lines?|shuttles?))"),
  RegExp(r"\b(end|ending|take|taking)\s+my\s+(own\s+)?life\b"),
  RegExp(r"\b(want|wanted|wanting)\s+to\s+die\b"),
  RegExp(r"\bwanna\s+die\b"),
  RegExp(r"\bwish\s+i\s+(was|were)\s+dead\b"),
  RegExp(r"\bbetter\s+off\s+dead\b"),
  RegExp(r"\b(don'?t|do\s+not)\s+want\s+to\s+(live|be\s+alive|exist)\b"),
  RegExp(r"\bno\s+(reason|point)\s+(to|in)\s+(live|living)\b"),
  RegExp(r"\bnot\s+worth\s+living\b"),
  RegExp(r"\bunalive\b"),
  RegExp(r"\boverdos(e|ing)\s+on\b"),
];

final _eating = <RegExp>[
  RegExp(r"\bmake\s+my\s*self\s+(throw\s*up|vomit|puke|sick)\b"),
  RegExp(r"\b(throw|throwing)\s+up\s+(after|what)\s+(i\s+)?(eat|ate|meals?)\b"),
  RegExp(r"\bpurg(e|ed|es|ing)\b"),
  RegExp(r"\bstarv(e|ed|ing)\s+my\s*self\b"),
  RegExp(r"\b(stop|quit)\s+eating\s+(completely|entirely|altogether)\b"),
  RegExp(r"\bnot\s+eat(ing)?\s+(anything\s+)?for\s+(\d+|a\s+few|several|two|three|four|five)\s+days\b"),
  RegExp(r"\blaxatives?\b"),
  RegExp(r"\banorexi"),
  RegExp(r"\bbulimi"),
  RegExp(r"\bpro[\s-]?ana\b"),
  RegExp(r"\bthinspo"),
  // A daily target under 800 calories ("500 calories a day").
  RegExp(r"(?<![\d,.])\b([1-7]\d{2}|[1-9]\d)\s*(k?cals?|calories)\s+(a|per|each|every)\s+day\b"),
];

/// What, if anything, [text] raises. Self-harm wins over eating concerns.
SafetyConcern checkMessage(String text) {
  final t = text.toLowerCase().replaceAll('’', "'");
  if (_selfHarm.any((r) => r.hasMatch(t))) return SafetyConcern.selfHarm;
  if (_eating.any((r) => r.hasMatch(t))) return SafetyConcern.eatingDisorder;
  return SafetyConcern.none;
}

/// One place someone can reach right now.
class CrisisContact {
  const CrisisContact(this.label, this.detail, {this.url});

  /// The button text ("Call 988").
  final String label;

  /// Who it is and when ("988 Suicide & Crisis Lifeline, US and Canada, 24/7").
  final String detail;

  /// tel:, sms: or https: link the button opens. Null for detail only.
  final String? url;
}

class CrisisMessage {
  const CrisisMessage(this.title, this.body, this.contacts);
  final String title;
  final String body;
  final List<CrisisContact> contacts;
}

const _findHelp = CrisisContact('Find help in your country', 'Free, confidential helplines worldwide: findahelpline.com',
    url: 'https://findahelpline.com');

/// The fixed message for [concern]. Written by people, not generated.
CrisisMessage crisisMessage(SafetyConcern concern) => switch (concern) {
      SafetyConcern.eatingDisorder => const CrisisMessage(
          'Support for food and body worries',
          'This app\'s AI can\'t help safely with that, and you deserve real support from people '
              'who can. These are free and confidential:',
          [
            CrisisContact('Call (866) 662-1235',
                'National Alliance for Eating Disorders helpline, weekdays 9 am to 7 pm Eastern',
                url: 'tel:+18666621235'),
            CrisisContact('Text ALLIANCE to 741741', 'The same team by text, any time (US)', url: 'sms:741741'),
            CrisisContact('Call or text 988', 'If you\'re having thoughts of harming yourself (US and Canada, 24/7)',
                url: 'tel:988'),
            _findHelp,
          ],
        ),
      _ => const CrisisMessage(
          'You don\'t have to go through this alone',
          'It sounds like you might be going through something really hard. This app\'s AI can\'t '
              'help with that, but people can, right now and for free:',
          [
            CrisisContact('Call 988', '988 Suicide & Crisis Lifeline (US) and 988 Suicide Crisis Helpline (Canada), 24/7',
                url: 'tel:988'),
            CrisisContact('Text 988', 'Same line, by text', url: 'sms:988'),
            CrisisContact('Text HOME to 741741', 'Crisis Text Line (US), 24/7', url: 'sms:741741'),
            _findHelp,
            CrisisContact('In immediate danger?', 'Call 911 or your local emergency number.'),
          ],
        ),
    };

/// Added to every model's instructions, as a backstop for wording the
/// check above doesn't catch.
const safetyInstruction =
    ' If the user mentions suicide, self-harm, wanting to die, purging, starving themselves, '
    'or eating under 800 calories a day, do not give advice, numbers or plans. Say kindly that you '
    "can't help with that and that they deserve real support, and tell them they can call or text 988 "
    '(US and Canada) or visit findahelpline.com.';
