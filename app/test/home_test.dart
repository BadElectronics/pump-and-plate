import 'package:flutter_test/flutter_test.dart';

import 'package:fitapp/src/screens/home_screen.dart';

void main() {
  test('greeting: no comma before the name, ordinal dates, time of day', () {
    final morning = DateTime(2026, 10, 3, 8);
    expect(welcomeLine(morning, 'Sam'), 'Good morning Sam, it is Saturday, October 3rd');
    expect(welcomeLine(morning, null), 'Good morning, it is Saturday, October 3rd');
    expect(welcomeLine(DateTime(2026, 10, 1, 13), null), 'Good afternoon, it is Thursday, October 1st');
    expect(welcomeLine(DateTime(2026, 10, 22, 20), 'Sam'), 'Good evening Sam, it is Thursday, October 22nd');
    expect(welcomeLine(DateTime(2026, 10, 11, 9), null), 'Good morning, it is Sunday, October 11th');
    expect(welcomeLine(DateTime(2026, 10, 13, 9), null), 'Good morning, it is Tuesday, October 13th');
  });
}
