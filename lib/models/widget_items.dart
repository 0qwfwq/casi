// Data models for items managed by the Widgets Screen. Each entry has an
// isActive flag: inactive widgets are stored but hidden from the home
// screen and frozen (alarms do not ring, timers do not tick).

class AppAlarm {
  /// Human-readable label such as "Mon 8:30 AM" or "Daily 7:00 AM".
  final String label;
  bool isActive;

  AppAlarm({required this.label, this.isActive = false});

  Map<String, dynamic> toJson() => {
        'label': label,
        'isActive': isActive,
      };

  factory AppAlarm.fromJson(Map<String, dynamic> json) {
    return AppAlarm(
      label: json['label'] as String,
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}

class AppTimer {
  int totalSeconds;
  int remainingSeconds;
  bool isRunning;
  DateTime? endTime;
  bool isActive;

  AppTimer({required this.totalSeconds, this.isActive = false})
      : remainingSeconds = totalSeconds,
        isRunning = false;

  Map<String, dynamic> toJson() => {
        'totalSeconds': totalSeconds,
        'remainingSeconds': remainingSeconds,
        'isRunning': isRunning,
        'endTime': endTime?.millisecondsSinceEpoch,
        'isActive': isActive,
      };

  factory AppTimer.fromJson(Map<String, dynamic> json) {
    final t = AppTimer(
      totalSeconds: json['totalSeconds'] as int,
      isActive: json['isActive'] as bool? ?? false,
    );
    t.remainingSeconds = json['remainingSeconds'] as int;
    t.isRunning = json['isRunning'] as bool;
    final endMs = json['endTime'] as int?;
    if (endMs != null) {
      t.endTime = DateTime.fromMillisecondsSinceEpoch(endMs);
    }
    return t;
  }
}
