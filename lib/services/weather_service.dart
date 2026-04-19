// Weather service — single source of truth for the home screen's weather
// data. Replaces the data-owning role that the old WeatherPill played.
//
// Two consumer surfaces share this state:
//   • The inline temperature text rendered next to the date in
//     [ClockCapsule].
//   • The expanded [WeatherForecastWidget] rendered on the home screen
//     when the user has placed the Weather widget in the "Active" section
//     of the Widgets Screen.
//
// Fetching, caching, hourly refresh, and unit-change reparsing are owned
// here so both surfaces always read the same snapshot.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/design_system.dart';
import 'package:casi/widgets/weather_forecast_widget.dart';

class WeatherSnapshot {
  final int? temperature;
  final int? weatherCode;
  final String unit; // 'C' or 'F'
  final String description;
  final IconData icon;
  final Color iconColor;
  final List<DailyForecastData> daily;
  final List<HourlyForecastData> hourly;
  final String feelsLike;
  final String wind;
  final String precipitation;
  final String humidity;
  final String uvIndex;
  final String sunrise;

  const WeatherSnapshot({
    this.temperature,
    this.weatherCode,
    this.unit = 'C',
    this.description = 'Unknown',
    this.icon = CupertinoIcons.question,
    this.iconColor = Colors.white,
    this.daily = const [],
    this.hourly = const [],
    this.feelsLike = '--°',
    this.wind = '-- mph',
    this.precipitation = '--%',
    this.humidity = '--%',
    this.uvIndex = '--',
    this.sunrise = '--:-- AM',
  });

  String get unitLabel => '°$unit';
  String get tempLabel =>
      temperature == null ? '--$unitLabel' : '$temperature$unitLabel';
  bool get hasData => temperature != null;
}

class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  final ValueNotifier<WeatherSnapshot> snapshot =
      ValueNotifier(const WeatherSnapshot());

  bool _initialized = false;
  bool _isLoading = false;
  Timer? _hourlyTimer;
  String _unit = 'C';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _unit = prefs.getString('temperature_unit') ?? 'C';

    final cachedJson = prefs.getString('weather_json_cache');
    if (cachedJson != null) {
      try {
        _parseWeatherData(jsonDecode(cachedJson));
      } catch (e) {
        debugPrint("Weather cache parse error: $e");
      }
    } else {
      // Hydrate the bare minimum (just temp + code) from legacy keys so
      // the inline text isn't blank on first frame after install.
      final legacyTemp = prefs.getInt('last_temperature');
      final legacyCode = prefs.getInt('last_weather_code');
      if (legacyTemp != null) {
        snapshot.value = WeatherSnapshot(
          temperature: legacyTemp,
          weatherCode: legacyCode,
          unit: _unit,
          description: _getWeatherDescription(legacyCode),
          icon: _getWeatherIcon(legacyCode, true),
          iconColor: _getWeatherIconColor(legacyCode, true),
        );
      }
    }

    _scheduleTopOfHour();
    _checkAndFetch();
  }

  /// Re-read the temperature unit from prefs and re-parse cached data
  /// when the unit has changed (settings page can flip C↔F).
  Future<void> reloadUnitAndRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final newUnit = prefs.getString('temperature_unit') ?? 'C';
    if (newUnit != _unit) {
      _unit = newUnit;
      final cached = prefs.getString('weather_json_cache');
      if (cached != null) {
        try {
          _parseWeatherData(jsonDecode(cached));
        } catch (_) {}
      }
    }
    _checkAndFetch();
  }

  void dispose() {
    _hourlyTimer?.cancel();
    _hourlyTimer = null;
  }

  // ── Internal: fetch / refresh ────────────────────────────────────────

  void _scheduleTopOfHour() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour + 1, 0, 2);
    final delay = next.difference(now);
    _hourlyTimer?.cancel();
    _hourlyTimer = Timer(delay, () {
      _fetch();
      _scheduleTopOfHour();
    });
  }

  Future<void> _checkAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchMs = prefs.getInt('last_fetch_time_ms') ?? 0;
    final lastFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchMs);
    final now = DateTime.now();
    final crossedHour = now.hour != lastFetch.hour ||
        now.day != lastFetch.day ||
        now.month != lastFetch.month ||
        now.year != lastFetch.year;
    if (now.difference(lastFetch).inMinutes > 30 ||
        snapshot.value.temperature == null ||
        crossedHour) {
      await _fetch();
    }
  }

  Future<void> _fetch() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      pos ??= await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low));

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${pos.latitude}&longitude=${pos.longitude}'
          '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weathercode,wind_speed_10m,wind_direction_10m'
          '&hourly=temperature_2m,weathercode,is_day,precipitation_probability'
          '&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,uv_index_max'
          '&wind_speed_unit=mph&timezone=auto');

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('weather_json_cache', response.body);
        await prefs.setInt(
            'last_fetch_time_ms', DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('last_temperature',
            (data['current']['temperature_2m'] as num).round());
        await prefs.setInt('last_weather_code',
            (data['current']['weathercode'] as num).toInt());
        _parseWeatherData(data);
      }
    } catch (e) {
      debugPrint("Weather fetch error: $e");
    } finally {
      _isLoading = false;
    }
  }

  void _parseWeatherData(Map<String, dynamic> data) {
    final current = data['current'];
    final tempC = current['temperature_2m'] as num;
    final code = (current['weathercode'] as num).toInt();
    final isDay = (current['is_day'] as num).toInt() == 1;

    final feelsLikeC = current['apparent_temperature'] as num;
    final humidity = (current['relative_humidity_2m'] as num).round();
    final windSpeed = (current['wind_speed_10m'] as num).round();
    final windDirDeg = (current['wind_direction_10m'] as num).toInt();
    final windDir = _getWindDirection(windDirDeg);

    final uvRaw = (data['daily']['uv_index_max'][0] as num).toDouble();
    final uvLabel = "${uvRaw.round()} (${_getUvDescription(uvRaw)})";

    final sunriseIso = data['daily']['sunrise'][0] as String;
    final sunriseLabel = _formatTime(sunriseIso);

    final dailyList = <DailyForecastData>[];
    final daily = data['daily'];
    if (daily != null) {
      final times = daily['time'] as List;
      final codes = daily['weathercode'] as List;
      final maxs = daily['temperature_2m_max'] as List;
      final mins = daily['temperature_2m_min'] as List;
      for (var i = 0; i < times.length && i < 5; i++) {
        final date = DateTime.parse(times[i]);
        final dCode = (codes[i] as num).toInt();
        final dMax = _toDisplay(maxs[i] as num);
        final dMin = _toDisplay(mins[i] as num);
        dailyList.add(DailyForecastData(
          day: _getDayName(date.weekday),
          icon: _getWeatherIcon(dCode, true),
          iconColor: _getWeatherIconColor(dCode, true),
          temp: "$dMax°/$dMin°",
          description: _getWeatherDescription(dCode),
        ));
      }
    }

    final hourlyList = <HourlyForecastData>[];
    var precipProb = 0;
    final hourly = data['hourly'];
    if (hourly != null) {
      final times = hourly['time'] as List;
      final codes = hourly['weathercode'] as List;
      final temps = hourly['temperature_2m'] as List;
      final isDays = hourly['is_day'] as List;
      final precips = hourly['precipitation_probability'] as List;
      final now = DateTime.now();
      var startIdx = 0;
      for (var i = 0; i < times.length; i++) {
        final t = DateTime.parse(times[i]);
        if (t.isAfter(now) || (t.hour == now.hour && t.day == now.day)) {
          startIdx = i;
          break;
        }
      }
      precipProb = (precips[startIdx] as num).round();
      for (var i = startIdx; i < startIdx + 6 && i < times.length; i++) {
        final t = DateTime.parse(times[i]);
        final hCode = (codes[i] as num).toInt();
        final hTemp = _toDisplay(temps[i] as num);
        final hIsDay = (isDays[i] as num).toInt() == 1;
        hourlyList.add(HourlyForecastData(
          time: _getFormattedHour(t),
          icon: _getWeatherIcon(hCode, hIsDay),
          iconColor: _getWeatherIconColor(hCode, hIsDay),
          temp: "$hTemp°$_unit",
        ));
      }
    }

    snapshot.value = WeatherSnapshot(
      temperature: _toDisplay(tempC),
      weatherCode: code,
      unit: _unit,
      description: _getWeatherDescription(code),
      icon: _getWeatherIcon(code, isDay),
      iconColor: _getWeatherIconColor(code, isDay),
      daily: dailyList,
      hourly: hourlyList,
      feelsLike: "${_toDisplay(feelsLikeC)}°$_unit",
      wind: "$windSpeed mph $windDir",
      precipitation: "$precipProb%",
      humidity: "$humidity%",
      uvIndex: uvLabel,
      sunrise: sunriseLabel,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  int _toDisplay(num celsius) =>
      _unit == 'F' ? (celsius * 9 / 5 + 32).round() : celsius.round();

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String _getFormattedHour(DateTime t) {
    final h = t.hour;
    if (h == 0) return "12 AM";
    if (h < 12) return "$h AM";
    if (h == 12) return "12 PM";
    return "${h - 12} PM";
  }

  String _formatTime(String isoTime) {
    final time = DateTime.parse(isoTime);
    var hour = time.hour;
    final minute = time.minute;
    final ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return "$hour:${minute.toString().padLeft(2, '0')} $ampm";
  }

  String _getWindDirection(int degrees) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((degrees + 22.5) % 360 / 45).floor()];
  }

  String _getUvDescription(double uv) {
    if (uv < 3) return "Low";
    if (uv < 6) return "Moderate";
    if (uv < 8) return "High";
    if (uv < 11) return "Very High";
    return "Extreme";
  }

  String _getWeatherDescription(int? code) {
    if (code == null) return "Unknown";
    if (code == 0) return "Clear";
    if (code >= 1 && code <= 3) return "Cloudy";
    if (code >= 45 && code <= 48) return "Fog";
    if (code >= 51 && code <= 67) return "Rain";
    if (code >= 71 && code <= 77) return "Snow";
    if (code >= 80 && code <= 82) return "Showers";
    if (code >= 95 && code <= 99) return "Storm";
    return "Clear";
  }

  IconData _getWeatherIcon(int? code, [bool isDay = true]) {
    if (code == null) return CupertinoIcons.question;
    if (code == 0) {
      return isDay
          ? CupertinoIcons.sun_max_fill
          : CupertinoIcons.moon_stars_fill;
    }
    if (code >= 1 && code <= 3) {
      return isDay
          ? CupertinoIcons.cloud_sun_fill
          : CupertinoIcons.cloud_moon_fill;
    }
    if (code >= 45 && code <= 48) return CupertinoIcons.cloud_fog_fill;
    if (code >= 51 && code <= 67) return CupertinoIcons.cloud_rain_fill;
    if (code >= 71 && code <= 77) return CupertinoIcons.snow;
    if (code >= 80 && code <= 82) return CupertinoIcons.cloud_heavyrain_fill;
    if (code >= 95 && code <= 99) return CupertinoIcons.cloud_bolt_fill;
    return isDay
        ? CupertinoIcons.sun_max_fill
        : CupertinoIcons.moon_stars_fill;
  }

  Color _getWeatherIconColor(int? code, [bool isDay = true]) {
    if (code == 0) {
      return isDay ? CASIColors.caution : CASIColors.accentSecondary;
    }
    if (code != null && code >= 1 && code <= 3) {
      return isDay ? Colors.white : CASIColors.accentSecondary;
    }
    return Colors.white;
  }
}
