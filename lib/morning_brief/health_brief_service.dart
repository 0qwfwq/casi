import 'package:flutter/services.dart';

class HealthBriefData {
  final bool available;
  final int steps;
  final int sleepMinutes;
  final int activeMinutes;
  final int calories;
  final double distanceMeters;

  const HealthBriefData({
    required this.available,
    this.steps = 0,
    this.sleepMinutes = 0,
    this.activeMinutes = 0,
    this.calories = 0,
    this.distanceMeters = 0,
  });

  static String _formatDuration(int totalMinutes) {
    if (totalMinutes <= 0) return '--';
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}m';
    if (hours > 0) return '${hours}h';
    return '${mins}m';
  }

  String get sleepString => _formatDuration(sleepMinutes);
  String get activeTimeString => _formatDuration(activeMinutes);

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

  static const _unavailable = HealthBriefData(available: false);

  static Future<HealthBriefData> getTodayData() async {
    try {
      final result = await _channel.invokeMethod<Map>('getTodayHealthData');
      if (result == null) return _unavailable;

      return HealthBriefData(
        available: result['available'] as bool? ?? false,
        steps: (result['steps'] as num?)?.toInt() ?? 0,
        sleepMinutes: (result['sleepMinutes'] as num?)?.toInt() ?? 0,
        activeMinutes: (result['activeMinutes'] as num?)?.toInt() ?? 0,
        calories: (result['calories'] as num?)?.toInt() ?? 0,
        distanceMeters: (result['distanceMeters'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return _unavailable;
    }
  }
}
