import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:casi/morning_brief/morning_brief_panel.dart';
import 'package:casi/morning_brief/weather_brief_service.dart';
import 'package:casi/morning_brief/calendar_brief_service.dart';

/// Wraps [MorningBriefPanel] in enough scaffolding for widget tests.
Widget buildTestPanel({
  WeatherBriefData? weatherData,
  CalendarBriefData? calendarData,
  Map<DateTime, List<dynamic>>? launcherEvents,
  String temperatureUnit = 'C',
  VoidCallback? onDismiss,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 500,
        height: 600,
        child: MorningBriefPanel(
          onDismiss: onDismiss ?? () {},
          weatherData: weatherData,
          calendarData: calendarData,
          temperatureUnit: temperatureUnit,
        ),
      ),
    ),
  );
}

void main() {
  group('MorningBriefPanel', () {
    group('greeting page', () {
      testWidgets('shows a greeting message', (tester) async {
        await tester.pumpWidget(buildTestPanel());

        // One of the three greetings should be visible
        final greetingFound = find.textContaining('Good Morning').evaluate().isNotEmpty ||
            find.textContaining('Good Afternoon').evaluate().isNotEmpty ||
            find.textContaining('Good Evening').evaluate().isNotEmpty;

        expect(greetingFound, true);
      });

      testWidgets('shows swipe hint', (tester) async {
        await tester.pumpWidget(buildTestPanel());

        expect(find.text('Swipe to see your day'), findsOneWidget);
      });
    });

    group('weather page', () {
      testWidgets('shows loading when weather data is null', (tester) async {
        await tester.pumpWidget(buildTestPanel());

        // Swipe to weather page
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.text('Weather data is loading...'), findsOneWidget);
      });

      testWidgets('shows weather condition and temperatures', (tester) async {
        final weather = WeatherBriefData(
          clothingSuggestion: 'Wear a light jacket.',
          weatherSummary: 'Clear skies all day.',
          currentTemp: 20,
          highTemp: 25,
          lowTemp: 15,
          overallCondition: 'Clear',
        );

        await tester.pumpWidget(buildTestPanel(weatherData: weather));

        // Swipe to weather page
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.text('Clear'), findsOneWidget);
        expect(find.text('Clear skies all day.'), findsOneWidget);
        expect(find.text('Wear a light jacket.'), findsOneWidget);
      });

      testWidgets('displays Fahrenheit when unit is F', (tester) async {
        final weather = WeatherBriefData(
          clothingSuggestion: 'Dress light.',
          weatherSummary: 'Hot day.',
          currentTemp: 30,
          highTemp: 35,
          lowTemp: 25,
          overallCondition: 'Clear',
        );

        await tester.pumpWidget(buildTestPanel(
          weatherData: weather,
          temperatureUnit: 'F',
        ));

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        // 35°C = 95°F
        expect(find.textContaining('\u00b0F'), findsWidgets);
      });
    });

    group('calendar page', () {
      testWidgets('shows loading when both calendar and launcher events are null/empty',
          (tester) async {
        await tester.pumpWidget(buildTestPanel());

        // Swipe to calendar page (two swipes)
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.text('Loading calendar...'), findsOneWidget);
      });

      testWidgets('shows permission prompt when permission denied', (tester) async {
        final calData = CalendarBriefData(hasPermission: false, events: []);

        await tester.pumpWidget(buildTestPanel(calendarData: calData));

        // Navigate to calendar page
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.textContaining('Allow calendar access'), findsOneWidget);
        expect(find.text('Grant Permission'), findsOneWidget);
      });

      testWidgets('shows "No events today" when permission granted but no events',
          (tester) async {
        final calData = CalendarBriefData(hasPermission: true, events: []);

        await tester.pumpWidget(buildTestPanel(calendarData: calData));

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.text('No events today'), findsOneWidget);
        expect(find.text('Your schedule is clear'), findsOneWidget);
      });

      testWidgets('displays calendar events', (tester) async {
        final start = DateTime(2024, 6, 15, 9, 0).millisecondsSinceEpoch;
        final end = DateTime(2024, 6, 15, 10, 0).millisecondsSinceEpoch;

        final calData = CalendarBriefData(
          hasPermission: true,
          events: [
            DeviceCalendarEvent(
              title: 'Team Standup',
              begin: start,
              end: end,
              allDay: false,
              location: 'Room 42',
            ),
            DeviceCalendarEvent(
              title: 'Birthday Party',
              begin: 0,
              end: 0,
              allDay: true,
            ),
          ],
        );

        await tester.pumpWidget(buildTestPanel(calendarData: calData));

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.text("Today's Schedule"), findsOneWidget);
        expect(find.text('2 events'), findsOneWidget);
        expect(find.text('Team Standup'), findsOneWidget);
        expect(find.text('Birthday Party'), findsOneWidget);
        expect(find.text('Room 42'), findsOneWidget);
        expect(find.text('All day'), findsOneWidget);
      });

      testWidgets('shows singular "event" for single event', (tester) async {
        final calData = CalendarBriefData(
          hasPermission: true,
          events: [
            DeviceCalendarEvent(title: 'Solo Event', begin: 0, end: 0, allDay: true),
          ],
        );

        await tester.pumpWidget(buildTestPanel(calendarData: calData));

        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PageView), const Offset(-400, 0));
        await tester.pumpAndSettle();

        expect(find.text('1 event'), findsOneWidget);
      });
    });

    group('page indicator', () {
      testWidgets('shows 3 page indicators', (tester) async {
        await tester.pumpWidget(buildTestPanel());

        // AnimatedContainer is used for dots — there should be 3
        final dots = find.byType(AnimatedContainer);
        expect(dots, findsNWidgets(3));
      });
    });
  });
}
