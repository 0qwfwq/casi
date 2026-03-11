import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

class AppLauncher {
  static const _channel = MethodChannel('casi.launcher/apps');

  static Future<void> launchApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod('launchApp', {'packageName': packageName});
      if (result != true) {
        InstalledApps.startApp(packageName);
      }
    } catch (e) {
      InstalledApps.startApp(packageName);
    }
  }
}
