import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceCalendarEvent {
  final String title;
  final int begin;
  final int end;
  final bool allDay;
  final String location;
  final String description;
  final String calendarName;

  DeviceCalendarEvent({
    required this.title,
    required this.begin,
    required this.end,
    required this.allDay,
    this.location = '',
    this.description = '',
    this.calendarName = '',
  });

  factory DeviceCalendarEvent.fromJson(Map<String, dynamic> json) {
    return DeviceCalendarEvent(
      title: json['title'] as String? ?? 'Untitled',
      begin: json['begin'] as int? ?? 0,
      end: json['end'] as int? ?? 0,
      allDay: json['allDay'] as bool? ?? false,
      location: json['location'] as String? ?? '',
      description: json['description'] as String? ?? '',
      calendarName: json['calendarName'] as String? ?? '',
    );
  }

  String get timeString {
    if (allDay) return 'All day';
    final start = DateTime.fromMillisecondsSinceEpoch(begin);
    final finish = DateTime.fromMillisecondsSinceEpoch(end);
    return '${formatTime(start)} – ${formatTime(finish)}';
  }

  @visibleForTesting
  static String formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}

class CalendarBriefData {
  final bool hasPermission;
  final List<DeviceCalendarEvent> events;

  CalendarBriefData({required this.hasPermission, required this.events});
}

class CalendarBriefService {
  static const _defaultChannel = MethodChannel('casi.launcher/calendar');

  final MethodChannel _channel;

  CalendarBriefService({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasCalendarPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestCalendarPermission');
    } catch (_) {}
  }

  Future<CalendarBriefData> getTodayEvents() async {
    final hasPerm = await hasPermission();
    if (!hasPerm) {
      return CalendarBriefData(hasPermission: false, events: []);
    }

    try {
      final result = await _channel.invokeMethod<String>('getTodayEvents');
      if (result == null || result == '[]') {
        return CalendarBriefData(hasPermission: true, events: []);
      }

      final List<dynamic> jsonList = jsonDecode(result);
      final events = jsonList
          .map((e) => DeviceCalendarEvent.fromJson(e as Map<String, dynamic>))
          .toList();

      return CalendarBriefData(hasPermission: true, events: events);
    } catch (_) {
      return CalendarBriefData(hasPermission: true, events: []);
    }
  }

  /// Convenience static accessor for use without injection.
  static final instance = CalendarBriefService();
}
