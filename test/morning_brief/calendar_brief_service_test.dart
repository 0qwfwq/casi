import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:casi/morning_brief/calendar_brief_service.dart';

void main() {
  group('DeviceCalendarEvent', () {
    group('fromJson', () {
      test('parses a fully populated JSON map', () {
        final json = {
          'title': 'Team Standup',
          'begin': 1700000000000,
          'end': 1700003600000,
          'allDay': false,
          'location': 'Zoom',
          'description': 'Daily sync',
          'calendarName': 'Work',
        };

        final event = DeviceCalendarEvent.fromJson(json);

        expect(event.title, 'Team Standup');
        expect(event.begin, 1700000000000);
        expect(event.end, 1700003600000);
        expect(event.allDay, false);
        expect(event.location, 'Zoom');
        expect(event.description, 'Daily sync');
        expect(event.calendarName, 'Work');
      });

      test('uses defaults for missing fields', () {
        final event = DeviceCalendarEvent.fromJson({});

        expect(event.title, 'Untitled');
        expect(event.begin, 0);
        expect(event.end, 0);
        expect(event.allDay, false);
        expect(event.location, '');
        expect(event.description, '');
        expect(event.calendarName, '');
      });

      test('handles null values in JSON', () {
        final json = {
          'title': null,
          'begin': null,
          'end': null,
          'allDay': null,
          'location': null,
          'description': null,
          'calendarName': null,
        };

        final event = DeviceCalendarEvent.fromJson(json);

        expect(event.title, 'Untitled');
        expect(event.begin, 0);
        expect(event.allDay, false);
      });
    });

    group('timeString', () {
      test('returns "All day" for all-day events', () {
        final event = DeviceCalendarEvent(
          title: 'Holiday',
          begin: 0,
          end: 0,
          allDay: true,
        );

        expect(event.timeString, 'All day');
      });

      test('formats AM times correctly', () {
        // 9:30 AM to 10:00 AM on Jan 1 2024
        final start = DateTime(2024, 1, 1, 9, 30).millisecondsSinceEpoch;
        final end = DateTime(2024, 1, 1, 10, 0).millisecondsSinceEpoch;

        final event = DeviceCalendarEvent(
          title: 'Meeting',
          begin: start,
          end: end,
          allDay: false,
        );

        expect(event.timeString, '9:30 AM – 10:00 AM');
      });

      test('formats PM times correctly', () {
        final start = DateTime(2024, 1, 1, 14, 15).millisecondsSinceEpoch;
        final end = DateTime(2024, 1, 1, 15, 45).millisecondsSinceEpoch;

        final event = DeviceCalendarEvent(
          title: 'Review',
          begin: start,
          end: end,
          allDay: false,
        );

        expect(event.timeString, '2:15 PM – 3:45 PM');
      });

      test('formats 12 PM (noon) correctly', () {
        final start = DateTime(2024, 1, 1, 12, 0).millisecondsSinceEpoch;
        final end = DateTime(2024, 1, 1, 13, 0).millisecondsSinceEpoch;

        final event = DeviceCalendarEvent(
          title: 'Lunch',
          begin: start,
          end: end,
          allDay: false,
        );

        expect(event.timeString, '12:00 PM – 1:00 PM');
      });

      test('formats 12 AM (midnight) correctly', () {
        final start = DateTime(2024, 1, 1, 0, 0).millisecondsSinceEpoch;
        final end = DateTime(2024, 1, 1, 1, 0).millisecondsSinceEpoch;

        final event = DeviceCalendarEvent(
          title: 'Late Night',
          begin: start,
          end: end,
          allDay: false,
        );

        expect(event.timeString, '12:00 AM – 1:00 AM');
      });
    });

    group('formatTime', () {
      test('pads single-digit minutes with zero', () {
        final dt = DateTime(2024, 1, 1, 9, 5);
        expect(DeviceCalendarEvent.formatTime(dt), '9:05 AM');
      });

      test('handles hour boundaries', () {
        expect(
            DeviceCalendarEvent.formatTime(DateTime(2024, 1, 1, 0, 0)),
            '12:00 AM');
        expect(
            DeviceCalendarEvent.formatTime(DateTime(2024, 1, 1, 11, 59)),
            '11:59 AM');
        expect(
            DeviceCalendarEvent.formatTime(DateTime(2024, 1, 1, 12, 0)),
            '12:00 PM');
        expect(
            DeviceCalendarEvent.formatTime(DateTime(2024, 1, 1, 23, 59)),
            '11:59 PM');
      });
    });
  });

  group('CalendarBriefData', () {
    test('stores permission and events', () {
      final events = [
        DeviceCalendarEvent(
            title: 'Test', begin: 0, end: 0, allDay: true),
      ];
      final data =
          CalendarBriefData(hasPermission: true, events: events);

      expect(data.hasPermission, true);
      expect(data.events.length, 1);
      expect(data.events.first.title, 'Test');
    });
  });

  group('CalendarBriefService', () {
    late CalendarBriefService service;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      service = CalendarBriefService(
        channel: const MethodChannel('casi.launcher/calendar.test'),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('casi.launcher/calendar.test'),
        null,
      );
    });

    void mockChannel(
        Future<Object?>? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('casi.launcher/calendar.test'),
        handler,
      );
    }

    group('hasPermission', () {
      test('returns true when platform says true', () async {
        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return true;
          return null;
        });

        expect(await service.hasPermission(), true);
      });

      test('returns false when platform says false', () async {
        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return false;
          return null;
        });

        expect(await service.hasPermission(), false);
      });

      test('returns false when platform returns null', () async {
        mockChannel((call) async => null);

        expect(await service.hasPermission(), false);
      });

      test('returns false on platform exception', () async {
        mockChannel((call) async {
          throw PlatformException(code: 'ERROR');
        });

        expect(await service.hasPermission(), false);
      });
    });

    group('getTodayEvents', () {
      test('returns no permission when permission denied', () async {
        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return false;
          return null;
        });

        final result = await service.getTodayEvents();

        expect(result.hasPermission, false);
        expect(result.events, isEmpty);
      });

      test('returns empty events when result is null', () async {
        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return true;
          if (call.method == 'getTodayEvents') return null;
          return null;
        });

        final result = await service.getTodayEvents();

        expect(result.hasPermission, true);
        expect(result.events, isEmpty);
      });

      test('returns empty events for empty JSON array', () async {
        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return true;
          if (call.method == 'getTodayEvents') return '[]';
          return null;
        });

        final result = await service.getTodayEvents();

        expect(result.hasPermission, true);
        expect(result.events, isEmpty);
      });

      test('parses valid event JSON', () async {
        final events = [
          {
            'title': 'Standup',
            'begin': 1700000000000,
            'end': 1700003600000,
            'allDay': false,
            'location': 'Zoom',
            'description': '',
            'calendarName': 'Work',
          },
          {
            'title': 'Birthday',
            'begin': 0,
            'end': 0,
            'allDay': true,
          },
        ];

        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return true;
          if (call.method == 'getTodayEvents') return jsonEncode(events);
          return null;
        });

        final result = await service.getTodayEvents();

        expect(result.hasPermission, true);
        expect(result.events.length, 2);
        expect(result.events[0].title, 'Standup');
        expect(result.events[0].location, 'Zoom');
        expect(result.events[1].title, 'Birthday');
        expect(result.events[1].allDay, true);
      });

      test('returns empty events on malformed JSON', () async {
        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return true;
          if (call.method == 'getTodayEvents') return '{bad json';
          return null;
        });

        final result = await service.getTodayEvents();

        expect(result.hasPermission, true);
        expect(result.events, isEmpty);
      });

      test('returns empty events on platform exception', () async {
        mockChannel((call) async {
          if (call.method == 'hasCalendarPermission') return true;
          if (call.method == 'getTodayEvents') {
            throw PlatformException(code: 'ERROR');
          }
          return null;
        });

        final result = await service.getTodayEvents();

        expect(result.hasPermission, true);
        expect(result.events, isEmpty);
      });
    });
  });
}
