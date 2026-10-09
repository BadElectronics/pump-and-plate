import 'package:flutter/services.dart';

import '../ai/catalog.dart';

enum NetworkKind { unmetered, metered, none }

/// What the phone can tell us: memory, chip, storage, connection.
abstract class DeviceProbe {
  Future<DeviceSpecs?> specs();
  Future<NetworkKind> network();
}

/// Android, through a small channel in MainActivity (added by the setup script).
class AndroidDeviceProbe implements DeviceProbe {
  static const _channel = MethodChannel('fitapp/device');

  @override
  Future<DeviceSpecs?> specs() async {
    try {
      final m = await _channel.invokeMethod<Map<Object?, Object?>>('specs');
      return m == null ? null : DeviceSpecs.fromMap(m);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<NetworkKind> network() async {
    try {
      final n = await _channel.invokeMethod<String>('network');
      return switch (n) {
        'unmetered' => NetworkKind.unmetered,
        'metered' => NetworkKind.metered,
        _ => NetworkKind.none,
      };
    } catch (_) {
      // Unknown: treat as mobile data so the user is asked first.
      return NetworkKind.metered;
    }
  }
}

/// For tests and platforms without the channel.
class FixedDeviceProbe implements DeviceProbe {
  const FixedDeviceProbe({this.device, this.net = NetworkKind.unmetered});

  final DeviceSpecs? device;
  final NetworkKind net;

  @override
  Future<DeviceSpecs?> specs() async => device;

  @override
  Future<NetworkKind> network() async => net;
}
