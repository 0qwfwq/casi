// SystemClockService — bridges the device's default Clock app to CASI's
// home-screen alarm and timer pills.
//
//   * Alarms come from `AlarmManager.getNextAlarmClock()`. Any clock app
//     that schedules with `setAlarmClock(...)` (Google Clock, Samsung Clock,
//     OnePlus, AOSP DeskClock, etc.) shows up here. We surface the next
//     upcoming one only — that matches what the lockscreen alarm icon does.
//
//   * Timers come from clock-app *foreground notifications* parsed by
//     `CasiNotificationListenerService`. There is no public API to enumerate
//     a third-party clock app's timers; the persistent notification is the
//     only thing they all reliably expose. As a result we only see
//     timers that are currently running or paused with their notification
//     still posted.
//
// Both reads are best-effort — failures collapse to "no system clock data"
// so the UI just hides the pill rather than throwing.

import 'dart:convert';
import 'package:flutter/services.dart';

class SystemAlarm {
  /// When the alarm will next fire, in local time.
  final DateTime triggerTime;

  /// Package that scheduled the alarm (typically the user's default clock
  /// app). May be null on Android versions where `creatorPackage` returns
  /// null for cross-app intents.
  final String? ownerPackage;

  const SystemAlarm({required this.triggerTime, this.ownerPackage});

  /// Human-readable label such as `"Mon 8:30 AM"` or `"Today 7:00 AM"`.
  String formattedLabel() {
    final now = DateTime.now();
    final isToday = triggerTime.year == now.year &&
        triggerTime.month == now.month &&
        triggerTime.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = triggerTime.year == tomorrow.year &&
        triggerTime.month == tomorrow.month &&
        triggerTime.day == tomorrow.day;

    int h = triggerTime.hour;
    final m = triggerTime.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;

    final timeStr = '$h:$m $ampm';

    if (isToday) return 'Today $timeStr';
    if (isTomorrow) return 'Tomorrow $timeStr';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[triggerTime.weekday - 1]} $timeStr';
  }
}

class SystemTimer {
  /// Stable identifier — usually the notification key for the source row.
  final String id;

  /// Package of the clock app that owns the timer.
  final String packageName;

  /// Seconds remaining on the timer at the moment the notification was
  /// posted. Combined with [postTime] we can render an accurate count down
  /// without re-polling on every second.
  final int remainingSecondsAtPost;

  /// The clock-app's posted-time for this notification, in milliseconds
  /// since epoch (matches `StatusBarNotification.postTime`).
  final int postTime;

  /// True if the timer is actively counting down (not paused).
  final bool isRunning;

  /// Best-effort label from the notification title — "Timer", "5 min",
  /// or whatever the clock app set. Falls back to "Timer".
  final String label;

  const SystemTimer({
    required this.id,
    required this.packageName,
    required this.remainingSecondsAtPost,
    required this.postTime,
    required this.isRunning,
    required this.label,
  });

  /// Drift-corrected remaining seconds. For running timers we subtract the
  /// elapsed wall-clock time since `postTime` so the count matches the
  /// clock app even if the launcher polls slowly. Paused timers freeze at
  /// the value the notification reported.
  int currentRemainingSeconds() {
    if (!isRunning) return remainingSecondsAtPost;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - postTime;
    final elapsedS = (elapsedMs / 1000).round();
    final v = remainingSecondsAtPost - elapsedS;
    return v < 0 ? 0 : v;
  }
}

class SystemClockService {
  SystemClockService._();
  static final SystemClockService instance = SystemClockService._();

  static const _channel = MethodChannel('casi.launcher/clock');
  static const _notifChannel = MethodChannel('casi.launcher/notifications');

  /// Returns the next system alarm, or null if none is scheduled.
  Future<SystemAlarm?> getNextAlarm() async {
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('getNextAlarmClock');
      if (raw == null) return null;
      final triggerMs = raw['triggerTime'] as int?;
      if (triggerMs == null) return null;
      return SystemAlarm(
        triggerTime: DateTime.fromMillisecondsSinceEpoch(triggerMs),
        ownerPackage: raw['ownerPackage'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns currently active system timers (running or paused). Returns
  /// an empty list when notification access has not been granted, when
  /// the listener is disconnected, or when no clock app has a timer
  /// notification posted.
  Future<List<SystemTimer>> getSystemTimers() async {
    try {
      final raw = await _channel.invokeMethod<String>('getSystemTimers') ?? '[]';
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <SystemTimer>[];
      for (final item in list) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        final remaining = m['remainingSeconds'] as int?;
        if (remaining == null || remaining <= 0) continue;
        out.add(SystemTimer(
          id: (m['key'] as String?)?.isNotEmpty == true
              ? m['key'] as String
              : '${m['packageName']}#$remaining',
          packageName: (m['packageName'] as String?) ?? '',
          remainingSecondsAtPost: remaining,
          postTime: (m['postTime'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
          isRunning: (m['isRunning'] as bool?) ?? true,
          label: (m['title'] as String?)?.trim().isNotEmpty == true
              ? (m['title'] as String).trim()
              : 'Timer',
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Whether Notification Access has been granted to CASI. Required for
  /// system-timer reading; alarms work without it.
  Future<bool> hasNotificationAccess() async {
    try {
      return await _notifChannel
              .invokeMethod<bool>('isNotificationAccessGranted') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the user's default clock app — preferring the package that
  /// registered the next alarm, falling back to `ACTION_SHOW_ALARMS`.
  Future<void> openClockApp() async {
    try {
      await _channel.invokeMethod('openSystemClock');
    } catch (_) {}
  }

  /// Opens the timers screen of the user's default clock app.
  Future<void> openTimersScreen() async {
    try {
      await _channel.invokeMethod('openSystemTimers');
    } catch (_) {}
  }
}
