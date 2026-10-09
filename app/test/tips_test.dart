import 'package:fitapp/src/services/tips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the store is not started until the tip jar asks for tips', () async {
    final jar = StoreTipJar();
    // Listening for outcomes (as the app does at startup) must not start it.
    final sub = jar.outcomes.listen((_) {});
    expect(jar.started, isFalse);
    await sub.cancel();
  });
}
