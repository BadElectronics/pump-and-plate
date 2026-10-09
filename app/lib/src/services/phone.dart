import 'package:flutter/services.dart';

import 'rest_sound.dart';

/// Small things only the phone can do, through the channel in MainActivity
/// (added by the setup script) or the iPhone code in packages/pump_native. Each one quietly does nothing where the
/// channel isn't there (tests, other platforms).
class Phone {
  Phone._();

  static const _channel = MethodChannel('fitapp/device');

  /// Opens [url] in the browser or the app that handles it. False if
  /// nothing could open it.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Starts an email in the phone's email app; nothing is sent until the
  /// person taps Send there. False if there's no email app.
  static Future<bool> email({required String to, required String subject, required String body}) async {
    try {
      return await _channel.invokeMethod<bool>('email', {'to': to, 'subject': subject, 'body': body}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// "Pixel 8 · Android 16", for bug reports. Empty if unknown.
  static Future<String> model() async {
    try {
      return await _channel.invokeMethod<String>('model') ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Keeps the screen from turning off (during a workout).
  static Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  /// Plays a sound file once (the rest-is-up sound). False if it can't.
  static Future<bool> playSound(String path) async {
    try {
      final file = await resolveRestSound(path);
      if (file == null) return false;
      return await _channel.invokeMethod<bool>('playSound', {'path': file}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stopSound() async {
    try {
      await _channel.invokeMethod<void>('stopSound');
    } catch (_) {}
  }
}
