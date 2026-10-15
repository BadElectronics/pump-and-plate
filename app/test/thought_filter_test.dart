import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/ai/thought_filter.dart';

Future<String> _run(List<String> tokens) async =>
    (await hideThoughtChannel(Stream.fromIterable(tokens)).toList()).join();

void main() {
  test('the thought channel is dropped, one wrapper per token (as on iPhone)', () async {
    // What the AI package hands over for Qwen3 reasoning on the newer runtime:
    // each reasoning token wrapped on its own, then the answer as plain text.
    final out = await _run([
      '<|channel>thought\nOkay<channel|>',
      '<|channel>thought\n, the<channel|>',
      '<|channel>thought\n user said hello<channel|>',
      'Hi',
      '! How',
      ' can I help?',
    ]);
    expect(out, 'Hi! How can I help?');
  });

  test('a wrapper split across tokens is still dropped', () async {
    final out = await _run(['Sure. <|ch', 'annel>thought\nhmm', ' hmm<chan', 'nel|> Done.']);
    expect(out, 'Sure.  Done.');
  });

  test('text without any channel passes through untouched', () async {
    final out = await _run(['Log ', '2 eggs', ' for breakfast?']);
    expect(out, 'Log 2 eggs for breakfast?');
  });

  test('a lone < in normal text is not held back forever', () async {
    final out = await _run(['a < b', ' and more']);
    expect(out, 'a < b and more');
  });

  test('reasoning that never closes shows nothing after it', () async {
    final out = await _run(['Yes.', '<|channel>thought\nstill thinking', ' and thinking']);
    expect(out, 'Yes.');
  });
}
