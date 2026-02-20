import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:casi/weather_forecast_widget.dart';

class ScreenDock extends StatefulWidget {
  const ScreenDock({super.key});

  @override
  State<ScreenDock> createState() => _ScreenDockState();
}

class _ScreenDockState extends State<ScreenDock> with WidgetsBindingObserver {
  // Weather State
  int? _temperature;
  int? _weatherCode;
  
  // Data lists for the widget
  List<DailyForecastData> _forecastData = [];
  List<HourlyForecastData> _hourlyData = [];
  
  // Current Weather Info passed to Widget
  String _currentDescription = "Unknown";
  IconData _currentIcon = CupertinoIcons.question;
  Color _currentIconColor = Colors.white;

  // Detailed Data passed to Widget
  String _feelsLike = "--°C";
  String _wind = "-- mph";
  String _precipitation = "--%";
  String _humidity = "--%";
  String _uvIndex = "--";
  String _sunrise = "--:-- AM";

  bool _isLoadingWeather = false;
  bool _showForecast = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWeather();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchWeather();
    }
  }

  // --- Weather Logic ---
  Future<void> _initWeather() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _temperature = prefs.getInt('last_temperature');
        _weatherCode = prefs.getInt('last_weather_code');
        _currentDescription = _getWeatherDescription(_weatherCode);
        _currentIcon = _getWeatherIcon(_weatherCode, true);
        _currentIconColor = _getWeatherIconColor(_weatherCode, true);
      });
    }
    _fetchWeather();
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

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low);

      // Fetch expanded data including current detailed parameters, hourly precip_probability, and daily sunrise/UV.
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}'
          '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weathercode,wind_speed_10m,wind_direction_10m'
          '&hourly=temperature_2m,weathercode,is_day,precipitation_probability'
          '&daily=weathercode,temperature_2m_max,temperature_2m_min,sunrise,uv_index_max'
          '&wind_speed_unit=mph&timezone=auto');
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          // Parse Current Weather
          final current = data['current'];
          final temp = (current['temperature_2m'] as num).round();
          final code = (current['weathercode'] as num).toInt();
          final currentIsDay = (current['is_day'] as num).toInt() == 1;
          
          final String currentDesc = _getWeatherDescription(code);
          final IconData curIcon = _getWeatherIcon(code, currentIsDay);
          final Color curIconColor = _getWeatherIconColor(code, currentIsDay);

          // Parse Detailed Current Fields
          final feelsLikeNum = (current['apparent_temperature'] as num).round();
          final humidityNum = (current['relative_humidity_2m'] as num).round();
          final windSpeedNum = (current['wind_speed_10m'] as num).round();
          final windDirDegrees = (current['wind_direction_10m'] as num).toInt();
          final String windDir = _getWindDirection(windDirDegrees);
          
          final double uvIndexRaw = (data['daily']['uv_index_max'][0] as num).toDouble();
          final String uvIndexStr = "${uvIndexRaw.round()} (${_getUvDescription(uvIndexRaw)})";
          
          final String sunriseIso = data['daily']['sunrise'][0] as String;
          final String sunriseTime = _formatTime(sunriseIso);

          // Parse Daily Data
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
              int dMax = (maxs[i] as num).round();
              int dMin = (mins[i] as num).round();

              dailyList.add(DailyForecastData(
                day: _getDayName(date.weekday),
                icon: _getWeatherIcon(dCode, true), 
                iconColor: _getWeatherIconColor(dCode, true),
                temp: "$dMax°/$dMin°",
                description: _getWeatherDescription(dCode),
              ));
            }
          }

          // Parse Hourly Data
          List<HourlyForecastData> hourlyList = [];
          int precipProbNum = 0; // fallback

          if (data['hourly'] != null) {
            final hourly = data['hourly'];
            final times = hourly['time'] as List;
            final codes = hourly['weathercode'] as List;
            final temps = hourly['temperature_2m'] as List;
            final isDays = hourly['is_day'] as List;
            final precipProbs = hourly['precipitation_probability'] as List;

            // Find the index for the current hour
            DateTime now = DateTime.now();
            int currentIndex = 0;
            for (int i = 0; i < times.length; i++) {
              DateTime t = DateTime.parse(times[i]);
              if (t.isAfter(now) || (t.hour == now.hour && t.day == now.day)) {
                currentIndex = i;
                break;
              }
            }

            // Grab current precipitation probability
            precipProbNum = (precipProbs[currentIndex] as num).round();

            // Grab the next 6 hours of forecasts
            for (int i = currentIndex; i < currentIndex + 6 && i < times.length; i++) {
              DateTime t = DateTime.parse(times[i]);
              int hCode = (codes[i] as num).toInt();
              int hTemp = (temps[i] as num).round();
              bool hIsDay = (isDays[i] as num).toInt() == 1;

              hourlyList.add(HourlyForecastData(
                time: _getFormattedHour(t),
                icon: _getWeatherIcon(hCode, hIsDay),
                iconColor: _getWeatherIconColor(hCode, hIsDay),
                temp: "$hTemp°C",
              ));
            }
          }

          setState(() {
            _temperature = temp;
            _weatherCode = code;
            _currentDescription = currentDesc;
            _currentIcon = curIcon;
            _currentIconColor = curIconColor;
            
            _feelsLike = "$feelsLikeNum°C";
            _humidity = "$humidityNum%";
            _wind = "$windSpeedNum mph $windDir";
            _precipitation = "$precipProbNum%";
            _uvIndex = uvIndexStr;
            _sunrise = sunriseTime;

            _forecastData = dailyList;
            _hourlyData = hourlyList;
          });

          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_temperature', temp);
          await prefs.setInt('last_weather_code', code);
        }
      }
    } catch (e) {
      debugPrint("Error fetching weather: $e");
    } finally {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

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
    if (code == 0) return isDay ? Colors.orange : Colors.indigo.shade300;
    if (code != null && code >= 1 && code <= 3) return isDay ? Colors.white : Colors.indigo.shade200;
    return Colors.white; // Default for snow, rain, etc.
  }

  void _launchBrowser() {
    launchUrl(Uri.parse('https://google.com'),
        mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40.0, 0, 40.0, 40.0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // Enforce bottom alignment during the layout transition so elements do not jump!
        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: 1.0,
              child: child,
            ),
          );
        },
        child: _showForecast
            ? TapRegion(
                key: const ValueKey('forecast'),
                onTapOutside: (event) {
                  setState(() {
                    _showForecast = false;
                  });
                },
                child: WeatherForecastWidget(
                  forecastData: _forecastData,
                  hourlyData: _hourlyData,
                  currentTemp: "${_temperature ?? '--'}°C",
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
              )
            : Container(
                key: const ValueKey('dock_pill'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                    child: Container(
                      // Matched exactly to the bottom padding of WeatherForecastWidget!
                      padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 16.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(36.0),
                      ),
                      child: Row(
                        children: [
                          // Weather Pill
                          Expanded(
                            child: _GlassPill(
                              onTap: () {
                                _fetchWeather();
                                setState(() {
                                  _showForecast = true;
                                });
                              },
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center, // Lock vertical alignment
                                children: [
                                  Icon(
                                    _currentIcon,
                                    color: _currentIconColor,
                                    size: 24, // Reduced from 28 to balance exactly with 13pt font
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        "$_currentDescription, ${_temperature ?? '--'}°C",
                                        style: const TextStyle(
                                          fontSize: 13.0,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Chrome Pill
                          Expanded(
                            child: _GlassPill(
                              onTap: _launchBrowser,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.public,
                                    color: Colors.blue, 
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        "Open Web",
                                        style: const TextStyle(
                                          fontSize: 13.0,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _GlassPill({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54.0,
        padding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(27.0),
          border: Border.all(
            color: Colors.white.withOpacity(0.5),
            width: 1.2,
          ),
        ),
        child: child,
      ),
    );
  }
}