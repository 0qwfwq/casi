import 'package:flutter/services.dart';

class HealthBriefData {
  final bool available;
  final int steps;
  final int sleepMinutes;
  final int activeMinutes;
  final int calories;
  final double distanceMeters;

  HealthBriefData({
    required this.available,
    required this.steps,
    required this.sleepMinutes,
    required this.activeMinutes,
    required this.calories,
    required this.distanceMeters,
  });

  String get sleepString {
    if (sleepMinutes <= 0) return '--';
    final hours = sleepMinutes ~/ 60;
    final mins = sleepMinutes % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}m';
    if (hours > 0) return '${hours}h';
    return '${mins}m';
  }

  String get activeTimeString {
    if (activeMinutes <= 0) return '--';
    final hours = activeMinutes ~/ 60;
    final mins = activeMinutes % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}m';
    if (hours > 0) return '${hours}h';
    return '${mins}m';
  }

  String get distanceString {
    if (distanceMeters <= 0) return '--';
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.round()} m';
  }

  String get stepsString => steps > 0 ? _formatNumber(steps) : '--';

  String get caloriesString => calories > 0 ? '${_formatNumber(calories)} kcal' : '--';

  static String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k'.replaceAll('.0k', 'k');
    }
    return n.toString();
  }
}

class HealthBriefService {
  static const _channel = MethodChannel('casi.launcher/health');

  static Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isHealthConnectAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermissions() async {
    try {
      await _channel.invokeMethod('requestHealthPermissions');
    } catch (_) {}
  }

  static Future<HealthBriefData> getTodayData() async {
    try {
      final result = await _channel.invokeMethod<Map>('getTodayHealthData');
      if (result == null) {
        return HealthBriefData(
          available: false,
          steps: 0,
          sleepMinutes: 0,
          activeMinutes: 0,
          calories: 0,
          distanceMeters: 0,
        );
      }

      return HealthBriefData(
        available: result['available'] as bool? ?? false,
        steps: (result['steps'] as num?)?.toInt() ?? 0,
        sleepMinutes: (result['sleepMinutes'] as num?)?.toInt() ?? 0,
        activeMinutes: (result['activeMinutes'] as num?)?.toInt() ?? 0,
        calories: (result['calories'] as num?)?.toInt() ?? 0,
        distanceMeters: (result['distanceMeters'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return HealthBriefData(
        available: false,
        steps: 0,
        sleepMinutes: 0,
        activeMinutes: 0,
        calories: 0,
        distanceMeters: 0,
      );
    }
  }
}
