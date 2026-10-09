import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Salted, stretched hash of a PIN. Only this is stored, never the PIN.
String hashPin(String pin, String salt) {
  var bytes = utf8.encode('$salt:$pin');
  for (var i = 0; i < 20000; i++) {
    bytes = Uint8List.fromList(sha256.convert(bytes).bytes);
  }
  return base64Encode(bytes);
}

String newSalt() {
  final r = Random.secure();
  return base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
}

/// Fingerprint / face unlock.
abstract class Unlocker {
  /// True when the phone has biometrics set up.
  Future<bool> available();

  /// Shows the system prompt. True if the person was recognised.
  Future<bool> authenticate();
}

class LocalUnlocker implements Unlocker {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (e) {
      debugPrint('Biometrics unavailable: $e');
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Pump and Plate',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('Biometric unlock failed: $e');
      return false;
    }
  }
}

class NoUnlocker implements Unlocker {
  @override
  Future<bool> available() async => false;

  @override
  Future<bool> authenticate() async => false;
}
