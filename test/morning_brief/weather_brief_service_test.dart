import 'package:flutter_test/flutter_test.dart';
import 'package:casi/morning_brief/weather_brief_service.dart';

void main() {
  group('HourlyWeather', () {
    test('isClear is true only for code 0', () {
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 0, precipProbability: 0, isDay: true).isClear, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 1, precipProbability: 0, isDay: true).isClear, false);
    });

    test('isCloudy for codes 1-3', () {
      for (final code in [1, 2, 3]) {
        expect(
          HourlyWeather(hour: 0, temp: 20, weatherCode: code, precipProbability: 0, isDay: true).isCloudy,
          true,
          reason: 'code $code should be cloudy',
        );
      }
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 0, precipProbability: 0, isDay: true).isCloudy, false);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 4, precipProbability: 0, isDay: true).isCloudy, false);
    });

    test('isFoggy for codes 45-48', () {
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 45, precipProbability: 0, isDay: true).isFoggy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 48, precipProbability: 0, isDay: true).isFoggy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 44, precipProbability: 0, isDay: true).isFoggy, false);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 49, precipProbability: 0, isDay: true).isFoggy, false);
    });

    test('isRainy for codes 51-67 and 80-82', () {
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 51, precipProbability: 0, isDay: true).isRainy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 67, precipProbability: 0, isDay: true).isRainy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 80, precipProbability: 0, isDay: true).isRainy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 82, precipProbability: 0, isDay: true).isRainy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 50, precipProbability: 0, isDay: true).isRainy, false);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 70, precipProbability: 0, isDay: true).isRainy, false);
    });

    test('isSnowy for codes 71-77', () {
      expect(HourlyWeather(hour: 0, temp: 0, weatherCode: 71, precipProbability: 0, isDay: true).isSnowy, true);
      expect(HourlyWeather(hour: 0, temp: 0, weatherCode: 77, precipProbability: 0, isDay: true).isSnowy, true);
      expect(HourlyWeather(hour: 0, temp: 0, weatherCode: 70, precipProbability: 0, isDay: true).isSnowy, false);
    });

    test('isStormy for codes 95-99', () {
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 95, precipProbability: 0, isDay: true).isStormy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 99, precipProbability: 0, isDay: true).isStormy, true);
      expect(HourlyWeather(hour: 0, temp: 20, weatherCode: 94, precipProbability: 0, isDay: true).isStormy, false);
    });
  });

  group('WeatherBriefService.codeToCondition', () {
    test('maps weather codes to condition strings', () {
      expect(WeatherBriefService.codeToCondition(0), 'Clear');
      expect(WeatherBriefService.codeToCondition(1), 'Cloudy');
      expect(WeatherBriefService.codeToCondition(3), 'Cloudy');
      expect(WeatherBriefService.codeToCondition(45), 'Foggy');
      expect(WeatherBriefService.codeToCondition(48), 'Foggy');
      expect(WeatherBriefService.codeToCondition(51), 'Rainy');
      expect(WeatherBriefService.codeToCondition(67), 'Rainy');
      expect(WeatherBriefService.codeToCondition(71), 'Snowy');
      expect(WeatherBriefService.codeToCondition(77), 'Snowy');
      expect(WeatherBriefService.codeToCondition(80), 'Rainy');
      expect(WeatherBriefService.codeToCondition(82), 'Rainy');
      expect(WeatherBriefService.codeToCondition(95), 'Stormy');
      expect(WeatherBriefService.codeToCondition(99), 'Stormy');
    });

    test('defaults to Clear for unknown codes', () {
      expect(WeatherBriefService.codeToCondition(4), 'Clear');
      expect(WeatherBriefService.codeToCondition(100), 'Clear');
      expect(WeatherBriefService.codeToCondition(-1), 'Clear');
    });
  });

  group('WeatherBriefService.tempStr', () {
    test('formats Celsius correctly', () {
      expect(WeatherBriefService.tempStr(22.3, 'C'), '22\u00b0C');
      expect(WeatherBriefService.tempStr(0.0, 'C'), '0\u00b0C');
      expect(WeatherBriefService.tempStr(-5.7, 'C'), '-6\u00b0C');
    });

    test('converts to Fahrenheit correctly', () {
      // 0°C = 32°F
      expect(WeatherBriefService.tempStr(0.0, 'F'), '32\u00b0F');
      // 100°C = 212°F
      expect(WeatherBriefService.tempStr(100.0, 'F'), '212\u00b0F');
      // 20°C = 68°F
      expect(WeatherBriefService.tempStr(20.0, 'F'), '68\u00b0F');
    });
  });

  group('WeatherBriefService.tempFeeling', () {
    test('returns correct feeling for temperature ranges', () {
      expect(WeatherBriefService.tempFeeling(-5), 'freezing');
      expect(WeatherBriefService.tempFeeling(0), 'freezing');
      expect(WeatherBriefService.tempFeeling(3), 'very cold');
      expect(WeatherBriefService.tempFeeling(5), 'very cold');
      expect(WeatherBriefService.tempFeeling(8), 'cold');
      expect(WeatherBriefService.tempFeeling(10), 'cold');
      expect(WeatherBriefService.tempFeeling(13), 'cool');
      expect(WeatherBriefService.tempFeeling(18), 'mild');
      expect(WeatherBriefService.tempFeeling(22), 'warm');
      expect(WeatherBriefService.tempFeeling(28), 'hot');
      expect(WeatherBriefService.tempFeeling(35), 'very hot');
    });
  });

  group('WeatherBriefService.hourLabel', () {
    test('formats midnight as 12 AM', () {
      expect(WeatherBriefService.hourLabel(0), '12 AM');
    });

    test('formats morning hours', () {
      expect(WeatherBriefService.hourLabel(1), '1 AM');
      expect(WeatherBriefService.hourLabel(11), '11 AM');
    });

    test('formats noon as 12 PM', () {
      expect(WeatherBriefService.hourLabel(12), '12 PM');
    });

    test('formats afternoon/evening hours', () {
      expect(WeatherBriefService.hourLabel(13), '1 PM');
      expect(WeatherBriefService.hourLabel(23), '11 PM');
    });
  });

  group('WeatherBriefService.determineOverallCondition', () {
    HourlyWeather hw(int code) => HourlyWeather(
          hour: 10,
          temp: 20,
          weatherCode: code,
          precipProbability: 0,
          isDay: true,
        );

    test('prioritizes Stormy over everything', () {
      final hours = [hw(0), hw(0), hw(0), hw(95)];
      expect(WeatherBriefService.determineOverallCondition(hours), 'Stormy');
    });

    test('prioritizes Snowy over rain and clear', () {
      final hours = [hw(0), hw(0), hw(71)];
      expect(WeatherBriefService.determineOverallCondition(hours), 'Snowy');
    });

    test('returns Rainy when rain > 30% of hours', () {
      // 4 out of 10 hours are rainy = 40%
      final hours = List.generate(6, (_) => hw(0)) + List.generate(4, (_) => hw(61));
      expect(WeatherBriefService.determineOverallCondition(hours), 'Rainy');
    });

    test('returns most common condition when no severe weather', () {
      final hours = [hw(0), hw(0), hw(1)];
      expect(WeatherBriefService.determineOverallCondition(hours), 'Clear');
    });

    test('returns Cloudy when it dominates', () {
      final hours = [hw(1), hw(2), hw(3), hw(0)];
      expect(WeatherBriefService.determineOverallCondition(hours), 'Cloudy');
    });
  });

  group('WeatherBriefService.getClothingSuggestion', () {
    test('suggests heavy winter clothing for freezing temps', () {
      final result = WeatherBriefService.getClothingSuggestion(-5, -10, 'Clear', false, 0);
      expect(result, contains('heavy winter coat'));
      expect(result, contains('gloves'));
    });

    test('suggests light clothing for warm temps', () {
      final result = WeatherBriefService.getClothingSuggestion(28, 22, 'Clear', false, 0);
      expect(result, contains('Light and comfortable'));
    });

    test('suggests hot weather clothing for very high temps', () {
      final result = WeatherBriefService.getClothingSuggestion(35, 30, 'Clear', false, 0);
      expect(result, contains('stay cool'));
    });

    test('adds layering advice for large temp spreads', () {
      final result = WeatherBriefService.getClothingSuggestion(25, 10, 'Clear', false, 0);
      expect(result, contains('Layer up'));
    });

    test('suggests umbrella for rain with high probability', () {
      final result = WeatherBriefService.getClothingSuggestion(15, 10, 'Rainy', true, 70);
      expect(result, contains('umbrella'));
    });

    test('suggests umbrella consideration for moderate rain probability', () {
      final result = WeatherBriefService.getClothingSuggestion(15, 10, 'Rainy', true, 35);
      expect(result, contains('Consider carrying an umbrella'));
    });

    test('suggests waterproof boots for snow', () {
      final result = WeatherBriefService.getClothingSuggestion(0, -5, 'Snowy', true, 80);
      expect(result, contains('waterproof boots'));
    });

    test('suggests sun protection for clear hot days', () {
      final result = WeatherBriefService.getClothingSuggestion(30, 20, 'Clear', false, 0);
      expect(result, contains('sunglasses'));
      expect(result, contains('sunscreen'));
    });

    test('no sun protection for cloudy days', () {
      final result = WeatherBriefService.getClothingSuggestion(30, 20, 'Cloudy', false, 0);
      expect(result, isNot(contains('sunglasses')));
    });
  });

  group('WeatherBriefService.groupIntoPeriods', () {
    test('returns empty list for empty input', () {
      expect(WeatherBriefService.groupIntoPeriods([]), isEmpty);
    });

    test('returns single period for uniform weather', () {
      final hours = List.generate(5, (i) => HourlyWeather(
            hour: 8 + i,
            temp: 20,
            weatherCode: 0,
            precipProbability: 0,
            isDay: true,
          ));

      final periods = WeatherBriefService.groupIntoPeriods(hours);

      expect(periods.length, 1);
      expect(periods.first.condition, 'Clear');
      expect(periods.first.startHour, 8);
      expect(periods.first.endHour, 12);
    });

    test('splits into multiple periods on condition change', () {
      final hours = [
        HourlyWeather(hour: 8, temp: 20, weatherCode: 0, precipProbability: 0, isDay: true),
        HourlyWeather(hour: 9, temp: 20, weatherCode: 0, precipProbability: 0, isDay: true),
        HourlyWeather(hour: 10, temp: 18, weatherCode: 61, precipProbability: 60, isDay: true),
        HourlyWeather(hour: 11, temp: 17, weatherCode: 61, precipProbability: 70, isDay: true),
        HourlyWeather(hour: 12, temp: 20, weatherCode: 0, precipProbability: 5, isDay: true),
      ];

      final periods = WeatherBriefService.groupIntoPeriods(hours);

      expect(periods.length, 3);
      expect(periods[0].condition, 'Clear');
      expect(periods[0].startHour, 8);
      expect(periods[0].endHour, 9);
      expect(periods[1].condition, 'Rainy');
      expect(periods[1].startHour, 10);
      expect(periods[1].maxPrecipProb, 70);
      expect(periods[2].condition, 'Clear');
      expect(periods[2].startHour, 12);
    });

    test('computes average temperature per period', () {
      final hours = [
        HourlyWeather(hour: 8, temp: 10, weatherCode: 0, precipProbability: 0, isDay: true),
        HourlyWeather(hour: 9, temp: 20, weatherCode: 0, precipProbability: 0, isDay: true),
      ];

      final periods = WeatherBriefService.groupIntoPeriods(hours);

      expect(periods.first.avgTemp, 15.0);
    });
  });

  group('WeatherBriefService.buildWeatherSummary', () {
    test('single clear period produces clear summary', () {
      final hours = [
        HourlyWeather(hour: 10, temp: 22, weatherCode: 0, precipProbability: 0, isDay: true),
      ];
      final periods = WeatherBriefService.groupIntoPeriods(hours);
      final summary = WeatherBriefService.buildWeatherSummary(periods, hours, 22, 22, 'C');

      expect(summary, contains('clear'));
      expect(summary, contains('warm'));
    });

    test('single rainy period mentions rain', () {
      final hours = [
        HourlyWeather(hour: 10, temp: 15, weatherCode: 61, precipProbability: 70, isDay: true),
      ];
      final periods = WeatherBriefService.groupIntoPeriods(hours);
      final summary = WeatherBriefService.buildWeatherSummary(periods, hours, 15, 15, 'C');

      expect(summary, contains('Rain'));
    });

    test('multi-period summary includes transitions', () {
      final hours = [
        HourlyWeather(hour: 8, temp: 18, weatherCode: 0, precipProbability: 0, isDay: true),
        HourlyWeather(hour: 12, temp: 15, weatherCode: 61, precipProbability: 60, isDay: true),
      ];
      final periods = WeatherBriefService.groupIntoPeriods(hours);
      final summary = WeatherBriefService.buildWeatherSummary(periods, hours, 18, 15, 'C');

      expect(summary, contains('Currently'));
      expect(summary, contains('rain'));
    });
  });

  group('WeatherBriefService.analyzeWeather', () {
    Map<String, dynamic> buildWeatherJson({
      required DateTime date,
      List<int>? hours,
      List<double>? temps,
      List<int>? codes,
      List<int>? precipProbs,
      List<int>? isDays,
    }) {
      final h = hours ?? [8, 9, 10, 11, 12, 13, 14, 15];
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      return {
        'hourly': {
          'time': h.map((hr) => '$dateStr T${hr.toString().padLeft(2, '0')}:00'.replaceAll(' ', '')).toList(),
          'temperature_2m': temps ?? List.filled(h.length, 20.0),
          'weathercode': codes ?? List.filled(h.length, 0),
          'precipitation_probability': precipProbs ?? List.filled(h.length, 0),
          'is_day': isDays ?? List.filled(h.length, 1),
        },
        'daily': {
          'temperature_2m_max': [25.0],
          'temperature_2m_min': [15.0],
          'weathercode': [0],
        },
      };
    }

    test('uses daily fallback when no hourly data matches today', () {
      final yesterday = DateTime(2024, 1, 1);
      final today = DateTime(2024, 1, 2, 10);
      final data = buildWeatherJson(date: yesterday);

      final result = WeatherBriefService.analyzeWeather(data, 'C', now: today);

      expect(result.highTemp, 25.0);
      expect(result.lowTemp, 15.0);
      expect(result.overallCondition, 'Clear');
    });

    test('computes high and low from hourly data', () {
      final now = DateTime(2024, 6, 15, 8);
      final data = buildWeatherJson(
        date: now,
        temps: [15, 18, 22, 25, 28, 26, 23, 20],
      );

      final result = WeatherBriefService.analyzeWeather(data, 'C', now: now);

      expect(result.highTemp, 28);
      expect(result.lowTemp, 15);
      expect(result.currentTemp, 15);
    });

    test('detects precipitation', () {
      final now = DateTime(2024, 6, 15, 8);
      final data = buildWeatherJson(
        date: now,
        codes: [0, 0, 61, 61, 61, 0, 0, 0],
        precipProbs: [0, 0, 70, 80, 60, 10, 0, 0],
      );

      final result = WeatherBriefService.analyzeWeather(data, 'C', now: now);

      expect(result.hasPrecipitation, true);
      expect(result.maxPrecipProbability, 80);
    });

    test('generates clothing suggestion', () {
      final now = DateTime(2024, 6, 15, 8);
      final data = buildWeatherJson(
        date: now,
        temps: [22, 24, 26, 28, 27, 25, 23, 21],
      );

      final result = WeatherBriefService.analyzeWeather(data, 'C', now: now);

      expect(result.clothingSuggestion, isNotEmpty);
    });

    test('generates weather summary', () {
      final now = DateTime(2024, 6, 15, 8);
      final data = buildWeatherJson(date: now);

      final result = WeatherBriefService.analyzeWeather(data, 'C', now: now);

      expect(result.weatherSummary, isNotEmpty);
    });

    test('Fahrenheit unit produces F in summary', () {
      final now = DateTime(2024, 6, 15, 8);
      final data = buildWeatherJson(date: now);

      final result = WeatherBriefService.analyzeWeather(data, 'F', now: now);

      expect(result.weatherSummary, contains('\u00b0F'));
    });

    test('filters out past hours', () {
      final now = DateTime(2024, 6, 15, 12);
      final data = buildWeatherJson(
        date: now,
        hours: [8, 9, 10, 11, 12, 13, 14, 15],
        temps: [10, 11, 12, 13, 20, 21, 22, 23],
      );

      final result = WeatherBriefService.analyzeWeather(data, 'C', now: now);

      // Only hours 12-15 should be included
      expect(result.currentTemp, 20);
      expect(result.lowTemp, 20);
      expect(result.highTemp, 23);
    });
  });
}
