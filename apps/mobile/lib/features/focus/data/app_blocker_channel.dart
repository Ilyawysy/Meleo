import 'dart:io';
import 'package:flutter/services.dart';

class InstalledApp {
  final String packageName;
  final String appName;
  final Uint8List? icon;

  const InstalledApp({
    required this.packageName,
    required this.appName,
    this.icon,
  });
}

class AppBlockerChannel {
  static const _channel = MethodChannel('com.meleo.mobile/app_blocker');

  Future<List<InstalledApp>> getInstalledApps() async {
    if (!Platform.isAndroid) return [];
    final result = await _channel.invokeListMethod<Map>('getInstalledApps');
    if (result == null) return [];
    return result.map((m) {
      final map = Map<String, dynamic>.from(m);
      return InstalledApp(
        packageName: map['packageName'] as String,
        appName: map['appName'] as String,
        icon: map['icon'] as Uint8List?,
      );
    }).toList();
  }

  Future<void> startBlocking(List<String> packageNames) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('startBlocking', {'packageNames': packageNames});
  }

  Future<void> stopBlocking() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('stopBlocking');
  }

  Future<bool> isBlockingActive() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('isBlockingActive') ?? false;
  }

  Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasOverlayPermission') ?? false;
  }

  Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('requestOverlayPermission');
  }

  Future<bool> hasUsageStatsPermission() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasUsageStatsPermission') ?? false;
  }

  Future<void> requestUsageStatsPermission() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('requestUsageStatsPermission');
  }
}
