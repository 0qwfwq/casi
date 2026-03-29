import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class HourlyWeather {
  final int hour;
  final double temp;
  final int weatherCode;
  final int precipProbability;
  final bool isDay;

  HourlyWeather({
    required this.hour,
    required this.temp,
    required this.weatherCode,
    required this.precipProbability,
    required this.isDay,
  });

  bool get isRainy => (weatherCode >= 51 && weatherCode <= 67) || (weatherCode >= 80 && weatherCode <= 82);
  bool get isSnowy => weatherCode >= 71 && weatherCode <= 77;
  bool get isStormy => weatherCode >= 95 && weatherCode <= 99;
  bool get isCloudy => weatherCode >= 1 && weatherCode <= 3;
  bool get isFoggy => weatherCode >= 45 && weatherCode <= 48;
  bool get isClear => weatherCode == 0;
}

class WeatherPeriod {
  final String label;
  final int startHour;
  final int endHour;
  final String condition;
  final double avgTemp;
  final int maxPrecipProb;

  WeatherPeriod({
    required this.label,
    required this.startHour,
    required this.endHour,
    required this.condition,
    required this.avgTemp,
    required this.maxPrecipProb,
  });
}

class WeatherBriefData {
  final String clothingSuggestion;
  final String weatherSummary;
  final double currentTemp;
  final double highTemp;
  final double lowTemp;
  final String overallCondition;
  final List<WeatherPeriod> periods;
  final int maxPrecipProbability;
  final bool hasPrecipitation;

  WeatherBriefData({
    required this.clothingSuggestion,
    required this.weatherSummary,
    required this.currentTemp,
    required this.highTemp,
    required this.lowTemp,
    required this.overallCondition,
    this.periods = const [],
    this.maxPrecipProbability = 0,
    this.hasPrecipitation = false,
  });
}

class WeatherBriefService {
  static Future<WeatherBriefData?> generateBrief() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString('weather_json_cache');
    if (cachedJson == null) return null;

    try {
      final data = jsonDecode(cachedJson);
      return _analyzeWeather(data);
    } catch (e) {
      return null;
    }
  }

  static WeatherBriefData _analyzeWeather(Map<String, dynamic> data) {
    final hourly = data['hourly'];
    final times = hourly['time'] as List;
    final temps = hourly['temperature_2m'] as List;
    final codes = hourly['weathercode'] as List;
    final precipProbs = hourly['precipitation_probability'] as List;
    final isDays = hourly['is_day'] as List;

    final now = DateTime.now();
    final todayHours = <HourlyWeather>[];

    for (int i = 0; i < times.length; i++) {
      final t = DateTime.parse(times[i]);
      if (t.day == now.day && t.month == now.month && t.year == now.year && t.hour >= now.hour) {
        todayHours.add(HourlyWeather(
          hour: t.hour,
          temp: (temps[i] as num).toDouble(),
          weatherCode: (codes[i] as num).toInt(),
          precipProbability: (precipProbs[i] as num).toInt(),
          isDay: (isDays[i] as num).toInt() == 1,
        ));
      }
    }

    if (todayHours.isEmpty) {
      // Fallback: use daily data
      final daily = data['daily'];
      final maxTemp = (daily['temperature_2m_max'][0] as num).toDouble();
      final minTemp = (daily['temperature_2m_min'][0] as num).toDouble();
      final code = (daily['weathercode'][0] as num).toInt();
      final condition = _codeToCondition(code);
      return WeatherBriefData(
        clothingSuggestion: _getClothingSuggestion(maxTemp, minTemp, condition, false, 0),
        weatherSummary: "Today's high is ${maxTemp.round()}°C with a low of ${minTemp.round()}°C. Expect ${condition.toLowerCase()} skies.",
        currentTemp: maxTemp,
        highTemp: maxTemp,
        lowTemp: minTemp,
        overallCondition: condition,
      );
    }

    final highTemp = todayHours.map((h) => h.temp).reduce((a, b) => a > b ? a : b);
    final lowTemp = todayHours.map((h) => h.temp).reduce((a, b) => a < b ? a : b);
    final currentTemp = todayHours.first.temp;

    // Group into periods based on weather changes
    final periods = _groupIntoPeriods(todayHours);
    final hasRain = todayHours.any((h) => h.isRainy);
    final hasSnow = todayHours.any((h) => h.isSnowy);
    final hasStorm = todayHours.any((h) => h.isStormy);
    final maxPrecipProb = todayHours.map((h) => h.precipProbability).reduce((a, b) => a > b ? a : b);

    final overallCondition = _determineOverallCondition(todayHours);
    final weatherSummary = _buildWeatherSummary(periods, todayHours, highTemp, lowTemp);
    final clothingSuggestion = _getClothingSuggestion(
      highTemp, lowTemp, overallCondition,
      hasRain || hasSnow || hasStorm, maxPrecipProb,
    );

    return WeatherBriefData(
      clothingSuggestion: clothingSuggestion,
      weatherSummary: weatherSummary,
      currentTemp: currentTemp,
      highTemp: highTemp,
      lowTemp: lowTemp,
      overallCondition: overallCondition,
      periods: periods,
      maxPrecipProbability: maxPrecipProb,
      hasPrecipitation: hasRain || hasSnow || hasStorm,
    );
  }

  static List<WeatherPeriod> _groupIntoPeriods(List<HourlyWeather> hours) {
    if (hours.isEmpty) return [];

    final periods = <WeatherPeriod>[];
    String currentCondition = _codeToCondition(hours.first.weatherCode);
    int startHour = hours.first.hour;
    List<double> tempAccum = [hours.first.temp];
    int maxPrecip = hours.first.precipProbability;

    for (int i = 1; i < hours.length; i++) {
      final condition = _codeToCondition(hours[i].weatherCode);
      if (condition != currentCondition) {
        periods.add(WeatherPeriod(
          label: _hourLabel(startHour),
          startHour: startHour,
          endHour: hours[i - 1].hour,
          condition: currentCondition,
          avgTemp: tempAccum.reduce((a, b) => a + b) / tempAccum.length,
          maxPrecipProb: maxPrecip,
        ));
        currentCondition = condition;
        startHour = hours[i].hour;
        tempAccum = [hours[i].temp];
        maxPrecip = hours[i].precipProbability;
      } else {
        tempAccum.add(hours[i].temp);
        if (hours[i].precipProbability > maxPrecip) {
          maxPrecip = hours[i].precipProbability;
        }
      }
    }

    periods.add(WeatherPeriod(
      label: _hourLabel(startHour),
      startHour: startHour,
      endHour: hours.last.hour,
      condition: currentCondition,
      avgTemp: tempAccum.reduce((a, b) => a + b) / tempAccum.length,
      maxPrecipProb: maxPrecip,
    ));

    return periods;
  }

  static String _buildWeatherSummary(
    List<WeatherPeriod> periods,
    List<HourlyWeather> hours,
    double highTemp,
    double lowTemp,
  ) {
    if (periods.length == 1) {
      final p = periods.first;
      final tempRange = (highTemp - lowTemp).abs() < 3
          ? "around ${highTemp.round()}°C"
          : "between ${lowTemp.round()}°C and ${highTemp.round()}°C";

      if (p.condition == 'Clear') {
        return "It's going to be clear and ${_tempFeeling(highTemp)} all day, with temperatures $tempRange.";
      } else if (p.condition == 'Cloudy') {
        return "Expect cloudy skies throughout the day with temperatures $tempRange.";
      } else if (p.condition == 'Rainy') {
        return "Rain is expected throughout the day. Temperatures will be $tempRange.";
      } else if (p.condition == 'Snowy') {
        return "Snow is expected throughout the day. Stay warm with temperatures $tempRange.";
      } else if (p.condition == 'Foggy') {
        return "Foggy conditions expected today with temperatures $tempRange.";
      } else {
        return "Expect ${p.condition.toLowerCase()} conditions all day with temperatures $tempRange.";
      }
    }

    // Multiple weather periods - build a narrative
    final parts = <String>[];
    for (int i = 0; i < periods.length && i < 3; i++) {
      final p = periods[i];
      final timeStr = i == 0
          ? "Currently"
          : "Around ${_hourLabel(p.startHour)}";

      if (p.condition == 'Clear') {
        parts.add("$timeStr, it will be ${_tempFeeling(p.avgTemp)} and clear at ${p.avgTemp.round()}°C.");
      } else if (p.condition == 'Rainy') {
        parts.add("$timeStr, rain is expected with a ${p.maxPrecipProb}% chance and temperatures near ${p.avgTemp.round()}°C.");
      } else if (p.condition == 'Cloudy') {
        parts.add("$timeStr, skies will be cloudy at ${p.avgTemp.round()}°C.");
      } else if (p.condition == 'Snowy') {
        parts.add("$timeStr, expect snow with temperatures around ${p.avgTemp.round()}°C.");
      } else if (p.condition == 'Stormy') {
        parts.add("$timeStr, thunderstorms are expected around ${p.avgTemp.round()}°C.");
      } else {
        parts.add("$timeStr, expect ${p.condition.toLowerCase()} conditions at ${p.avgTemp.round()}°C.");
      }
    }

    return parts.join(' ');
  }

  static String _getClothingSuggestion(
    double highTemp, double lowTemp, String condition,
    bool hasPrecipitation, int maxPrecipProb,
  ) {
    final avgTemp = (highTemp + lowTemp) / 2;
    final tempSpread = highTemp - lowTemp;
    final parts = <String>[];

    // Temperature-based clothing
    if (avgTemp <= 0) {
      parts.add("Bundle up warmly with a heavy winter coat, scarf, and gloves.");
    } else if (avgTemp <= 5) {
      parts.add("Wear a heavy coat with warm layers underneath.");
    } else if (avgTemp <= 10) {
      parts.add("A warm jacket or coat is recommended today.");
    } else if (avgTemp <= 15) {
      parts.add("Wear a light jacket or sweater.");
    } else if (avgTemp <= 20) {
      parts.add("A light layer should be enough for today.");
    } else if (avgTemp <= 25) {
      parts.add("Light and comfortable clothing is perfect today.");
    } else {
      parts.add("Dress light and stay cool today.");
    }

    // Large temp spread
    if (tempSpread > 8) {
      parts.add("Layer up, as temperatures will vary significantly.");
    }

    // Precipitation
    if (hasPrecipitation && maxPrecipProb >= 50) {
      if (condition == 'Snowy') {
        parts.add("Wear waterproof boots and bring warm accessories.");
      } else if (condition == 'Stormy') {
        parts.add("Carry an umbrella and avoid open areas if possible.");
      } else {
        parts.add("Don't forget your umbrella.");
      }
    } else if (hasPrecipitation && maxPrecipProb >= 30) {
      parts.add("Consider carrying an umbrella just in case.");
    }

    // Sun protection
    if (condition == 'Clear' && highTemp > 22) {
      parts.add("Don't forget sunglasses and sunscreen.");
    }

    return parts.join(' ');
  }

  static String _determineOverallCondition(List<HourlyWeather> hours) {
    final conditionCounts = <String, int>{};
    for (final h in hours) {
      final c = _codeToCondition(h.weatherCode);
      conditionCounts[c] = (conditionCounts[c] ?? 0) + 1;
    }

    // Prioritize severe conditions
    if (conditionCounts.containsKey('Stormy')) return 'Stormy';
    if (conditionCounts.containsKey('Snowy')) return 'Snowy';
    if ((conditionCounts['Rainy'] ?? 0) > hours.length * 0.3) return 'Rainy';

    // Most common condition
    String? best;
    int bestCount = 0;
    conditionCounts.forEach((k, v) {
      if (v > bestCount) {
        bestCount = v;
        best = k;
      }
    });
    return best ?? 'Clear';
  }

  static String _codeToCondition(int code) {
    if (code == 0) return 'Clear';
    if (code >= 1 && code <= 3) return 'Cloudy';
    if (code >= 45 && code <= 48) return 'Foggy';
    if (code >= 51 && code <= 67) return 'Rainy';
    if (code >= 71 && code <= 77) return 'Snowy';
    if (code >= 80 && code <= 82) return 'Rainy';
    if (code >= 95 && code <= 99) return 'Stormy';
    return 'Clear';
  }

  static String _tempFeeling(double temp) {
    if (temp <= 0) return 'freezing';
    if (temp <= 5) return 'very cold';
    if (temp <= 10) return 'cold';
    if (temp <= 15) return 'cool';
    if (temp <= 20) return 'mild';
    if (temp <= 25) return 'warm';
    if (temp <= 30) return 'hot';
    return 'very hot';
  }

  static String _hourLabel(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }
}
