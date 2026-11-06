import 'dart:async';

import 'package:fitapp/src/fold/fold.dart';

/// Runs before every test file. The test screen is 800 × 600, which would
/// count as an unfolded phone, so the foldable layouts are off except in the
/// tests written for them (fold_test.dart).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FoldLayout.enabled = false;
  await testMain();
}
