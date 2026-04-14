import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/widgets/weather_forecast_widget.dart';
import 'package:casi/design_system.dart';
import 'package:url_launcher/url_launcher.dart';

class WeatherPill extends StatefulWidget {
  final ValueChanged<bool>? onExpandedChanged;

  const WeatherPill({super.key, this.onExpandedChanged});

  @override
  State<WeatherPill> createState() => _WeatherPillState();
}

class _WeatherPillState extends State<WeatherPill> with WidgetsBindingObserver {
  int? _temperature;
  int? _weatherCode;
  String _unit = 'C'; // 'C' or 'F'

  List<DailyForecastData> _forecastData = [];
  List<HourlyForecastData> _hourlyData = [];

  String _currentDescription = "Unknown";
  IconData _currentIcon = CupertinoIcons.question;
  Color _currentIconColor = Colors.white;

  String _feelsLike = "--°";
  String _wind = "-- mph";
  String _precipitation = "--%";
  String _humidity = "--%";
  String _uvIndex = "--";
  String _sunrise = "--:-- AM";

  bool _isLoadingWeather = false;
  bool _isExpanded = false;
  bool _isCollapsing = false;

  Timer? _hourlySyncTimer;

  String get _unitLabel => '°$_unit';

  int _toDisplay(num celsius) {
    if (_unit == 'F') return (celsius * 9 / 5 + 32).round();
    return celsius.round();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWeather();
    _scheduleTopOfHourWeatherSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hourlySyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadUnitAndRefresh();
    }
  }

  Future<void> _reloadUnitAndRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final newUnit = prefs.getString('temperature_unit') ?? 'C';
    if (newUnit != _unit) {
      _unit = newUnit;
      // Re-parse cached data with new unit
      final cachedJson = prefs.getString('weather_json_cache');
      if (cachedJson != null) {
        try {
          _parseWeatherData(jsonDecode(cachedJson));
        } catch (_) {}
      }
    }
    _checkAndFetchWeather();
  }

  // --- Weather Logic ---

  Future<void> _initWeather() async {
    final prefs = await SharedPreferences.getInstance();
    _unit = prefs.getString('temperature_unit') ?? 'C';

    final String? cachedWeatherJson = prefs.getString('weather_json_cache');
    if (cachedWeatherJson != null) {
      try {
        final data = jsonDecode(cachedWeatherJson);
        _parseWeatherData(data);
      } catch (e) {
        debugPrint("Cache parse error: $e");
      }
    } else {
      if (mounted) {
        setState(() {
          _temperature = prefs.getInt('last_temperature');
          _weatherCode = prefs.getInt('last_weather_code');
          _currentDescription = _getWeatherDescription(_weatherCode);
          _currentIcon = _getWeatherIcon(_weatherCode, true);
          _currentIconColor = _getWeatherIconColor(_weatherCode, true);
        });
      }
    }

    _checkAndFetchWeather();
  }

  void _scheduleTopOfHourWeatherSync() {
    final now = DateTime.now();
    DateTime nextHour = DateTime(now.year, now.month, now.day, now.hour + 1, 0, 2);
    Duration durationUntilNextHour = nextHour.difference(now);

    _hourlySyncTimer?.cancel();
    _hourlySyncTimer = Timer(durationUntilNextHour, () {
      _fetchWeather();
      _scheduleTopOfHourWeatherSync();
    });
  }

  Future<void> _checkAndFetchWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final lastFetchMs = prefs.getInt('last_fetch_time_ms') ?? 0;
    final lastFetch = DateTime.fromMillisecondsSinceEpoch(lastFetchMs);
    final now = DateTime.now();

    bool crossedHour = now.hour != lastFetch.hour ||
        now.day != lastFetch.day ||
        now.month != lastFetch.month ||
        now.year != lastFetch.year;

    if (now.difference(lastFetch).inMinutes > 30 || _temperature == null || crossedHour) {
      _fetchWeather();
    }

    _scheduleTopOfHourWeatherSync();
  }

  void _parseWeatherData(Map<String, dynamic> data) {
    final current = data['current'];
    final tempC = (current['temperature_2m'] as num);
    final code = (current['weathercode'] as num).toInt();
    final currentIsDay = (current['is_day'] as num).toInt() == 1;

    final String currentDesc = _getWeatherDescription(code);
    final IconData curIcon = _getWeatherIcon(code, currentIsDay);
    final Color curIconColor = _getWeatherIconColor(code, currentIsDay);

    final feelsLikeC = (current['apparent_temperature'] as num);
    final humidityNum = (current['relative_humidity_2m'] as num).round();
    final windSpeedNum = (current['wind_speed_10m'] as num).round();
    final windDirDegrees = (current['wind_direction_10m'] as num).toInt();
    final String windDir = _getWindDirection(windDirDegrees);

    final double uvIndexRaw = (data['daily']['uv_index_max'][0] as num).toDouble();
    final String uvIndexStr = "${uvIndexRaw.round()} (${_getUvDescription(uvIndexRaw)})";

    final String sunriseIso = data['daily']['sunrise'][0] as String;
    final String sunriseTime = _formatTime(sunriseIso);

    List<DailyForecastData> dailyList = [];
    if (data['daily'] != null) {
      final daily = data['daily'];
      final times = daily['time'] as List;
      final codes = daily['weathercode'] as List;
      final maxs = daily['temperature_2m_max'] as List;
      final mins = daily['temperature_2m_min'] as List;

      for (int i = 0; i < times.length && i < 5; i++) {
        DateTime date = DateTime.parse(times[i]);
        int dCode = (codes[i] as num).toInt();
        int dMax = _toDisplay(maxs[i] as num);
        int dMin = _toDisplay(mins[i] as num);

        dailyList.add(DailyForecastData(
          day: _getDayName(date.weekday),
          icon: _getWeatherIcon(dCode, true),
          iconColor: _getWeatherIconColor(dCode, true),
          temp: "$dMax°/$dMin°",
          description: _getWeatherDescription(dCode),
        ));
      }
    }

    List<HourlyForecastData> hourlyList = [];
    int precipProbNum = 0;

    if (data['hourly'] != null) {
      final hourly = data['hourly'];
      final times = hourly['time'] as List;
      final codes = hourly['weathercode'] as List;
      final temps = hourly['temperature_2m'] as List;
      final isDays = hourly['is_day'] as List;
      final precipProbs = hourly['precipitation_probability'] as List;

      DateTime now = DateTime.now();
      int currentIndex = 0;
      for (int i = 0; i < times.length; i++) {
        DateTime t = DateTime.parse(times[i]);
        if (t.isAfter(now) || (t.hour == now.hour && t.day == now.day)) {
          currentIndex = i;
          break;
        }
      }

      precipProbNum = (precipProbs[currentIndex] as num).round();

      for (int i = currentIndex; i < currentIndex + 6 && i < times.length; i++) {
        DateTime t = DateTime.parse(times[i]);
        int hCode = (codes[i] as num).toInt();
        int hTemp = _toDisplay(temps[i] as num);
        bool hIsDay = (isDays[i] as num).toInt() == 1;

        hourlyList.add(HourlyForecastData(
          time: _getFormattedHour(t),
          icon: _getWeatherIcon(hCode, hIsDay),
          iconColor: _getWeatherIconColor(hCode, hIsDay),
          temp: "$hTemp$_unitLabel",
        ));
      }
    }

    if (mounted) {
      setState(() {
        _temperature = _toDisplay(tempC);
        _weatherCode = code;
        _currentDescription = currentDesc;
        _currentIcon = curIcon;
        _currentIconColor = curIconColor;

        _feelsLike = "${_toDisplay(feelsLikeC)}$_unitLabel";
        _humidity = "$humidityNum%";
        _wind = "$windSpeedNum mph $windDir";
        _precipitation = "$precipProbNum%";
        _uvIndex = uvIndexStr;
        _sunrise = sunriseTime;

        _forecastData = dailyList;
        _hourlyData = hourlyList;
      });
    }
  }

  Future<void> _fetchWeather() async {
    if (_isLoadingWeather) return;
    if (mounted) setState(() => _isLoadingWeather = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}

      position ??= await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}'
          '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weathercode,wind_speed_10m,wind_direction_10m'
          '&hourly=temperature_2m,weathercode,is_day,precipitation_probability'
          '&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,uv_index_max'
          '&wind_speed_unit=mph&timezone=auto');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('weather_json_cache', response.body);
        await prefs.setInt('last_fetch_time_ms', DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('last_temperature', (data['current']['temperature_2m'] as num).round());
        await prefs.setInt('last_weather_code', (data['current']['weathercode'] as num).toInt());

        _parseWeatherData(data);
      }
    } catch (e) {
      debugPrint("Error fetching weather: $e");
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  // --- Helpers ---

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  String _getFormattedHour(DateTime time) {
    int hour = time.hour;
    if (hour == 0) return "12 AM";
    if (hour < 12) return "$hour AM";
    if (hour == 12) return "12 PM";
    return "${hour - 12} PM";
  }

  String _formatTime(String isoTime) {
    DateTime time = DateTime.parse(isoTime);
    int hour = time.hour;
    int minute = time.minute;
    String ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minuteStr = minute.toString().padLeft(2, '0');
    return "$hour:$minuteStr $ampm";
  }

  String _getWindDirection(int degrees) {
    const directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    int index = ((degrees + 22.5) % 360 / 45).floor();
    return directions[index];
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
    if (code == 0) return isDay ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill;
    if (code >= 1 && code <= 3) return isDay ? CupertinoIcons.cloud_sun_fill : CupertinoIcons.cloud_moon_fill;
    if (code >= 45 && code <= 48) return CupertinoIcons.cloud_fog_fill;
    if (code >= 51 && code <= 67) return CupertinoIcons.cloud_rain_fill;
    if (code >= 71 && code <= 77) return CupertinoIcons.snow;
    if (code >= 80 && code <= 82) return CupertinoIcons.cloud_heavyrain_fill;
    if (code >= 95 && code <= 99) return CupertinoIcons.cloud_bolt_fill;
    return isDay ? CupertinoIcons.sun_max_fill : CupertinoIcons.moon_stars_fill;
  }

  Color _getWeatherIconColor(int? code, [bool isDay = true]) {
    if (code == 0) return isDay ? CASIColors.caution : CASIColors.accentSecondary;
    if (code != null && code >= 1 && code <= 3) return isDay ? Colors.white : CASIColors.accentSecondary;
    return Colors.white;
  }

  // --- Open Default Weather App ---

  Future<void> _openWeatherApp() async {
    // Try common weather app package names
    const weatherApps = [
      'com.google.android.apps.weather',     // Google Weather
      'com.samsung.android.weather',          // Samsung Weather
      'com.oneplus.weather',                  // OnePlus Weather
      'com.miui.weather2',                    // Xiaomi Weather
      'org.breezyweather',                    // Breezy Weather
      'com.accuweather.android',              // AccuWeather
    ];

    for (final pkg in weatherApps) {
      try {
        final launched = await launchUrl(
          Uri.parse('android-app://$pkg'),
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {}
    }

    // Fallback: open web weather search
    await launchUrl(
      Uri.parse('https://www.google.com/search?q=weather'),
      mode: LaunchMode.externalApplication,
    );
  }

  // --- Expand / Collapse ---

  void _collapse() {
    if (_isCollapsing) return;
    setState(() => _isCollapsing = true);
    // Phase 1: fade out content (150ms), then Phase 2: shrink to pill
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _isExpanded = false;
          _isCollapsing = false;
        });
        widget.onExpandedChanged?.call(false);
      }
    });
  }

  void _expand() {
    _checkAndFetchWeather();
    setState(() => _isExpanded = true);
    widget.onExpandedChanged?.call(true);
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    if (_temperature == null) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: <Widget>[
              ...previousChildren.map((Widget child) {
                return Positioned(top: 0, left: 0, right: 0, child: child);
              }),
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: _isExpanded
            ? _buildExpanded(key: const ValueKey('weather_expanded'))
            : _buildPill(key: const ValueKey('weather_pill')),
      ),
    );
  }

  Widget _buildPill({Key? key}) {
    return GestureDetector(
      key: key,
      onTap: _expand,
      onLongPress: _openWeatherApp,
      child: Center(
        child: GlassSurface.pill(
          cornerRadius: CASIGlass.cornerPill,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_currentIcon, color: _currentIconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                "${_temperature ?? '--'}$_unitLabel",
                style: const TextStyle(
                  color: CASIColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _currentDescription,
                style: const TextStyle(
                  color: CASIColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded({Key? key}) {
    return GestureDetector(
      key: key,
      onVerticalDragEnd: (_) => _collapse(),
      child: GlassSurface.modal(
        cornerRadius: CASIGlass.cornerSheet,
        width: double.infinity,
        child: AnimatedOpacity(
          opacity: _isCollapsing ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: WeatherForecastWidget(
            forecastData: _forecastData,
            hourlyData: _hourlyData,
            currentTemp: "${_temperature ?? '--'}$_unitLabel",
            currentDescription: _currentDescription,
            currentIcon: _currentIcon,
            currentIconColor: _currentIconColor,
            feelsLike: _feelsLike,
            wind: _wind,
            precipitation: _precipitation,
            humidity: _humidity,
            uvIndex: _uvIndex,
            sunrise: _sunrise,
          ),
        ),
      ),
    );
  }
}
