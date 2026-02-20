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
  List<DailyForecastData> _forecastData = [];
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

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current_weather=true&daily=weathercode,temperature_2m_max,temperature_2m_min&timezone=auto');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          final current = data['current_weather'];
          final temp = (current['temperature'] as num).round();
          final code = (current['weathercode'] as num).toInt();

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
                icon: _getWeatherIcon(dCode),
                iconColor: _getWeatherIconColor(dCode),
                temp: "$dMax°/$dMin°",
                description: _getWeatherDescription(dCode),
              ));
            }
          }

          setState(() {
            _temperature = temp;
            _weatherCode = code;
            _forecastData = dailyList;
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

  IconData _getWeatherIcon(int? code) {
    if (code == null) return CupertinoIcons.question;
    if (code == 0) return CupertinoIcons.sun_max_fill;
    if (code >= 1 && code <= 3) return CupertinoIcons.cloud_fill;
    if (code >= 45 && code <= 48) return CupertinoIcons.cloud_fog_fill;
    if (code >= 51 && code <= 67) return CupertinoIcons.cloud_rain_fill;
    if (code >= 71 && code <= 77) return CupertinoIcons.snow;
    if (code >= 80 && code <= 82) return CupertinoIcons.cloud_heavyrain_fill;
    if (code >= 95 && code <= 99) return CupertinoIcons.cloud_bolt_fill;
    return CupertinoIcons.sun_max_fill;
  }

  Color _getWeatherIconColor(int? code) {
    if (code == 0) return Colors.orange;
    if (code != null && code >= 1 && code <= 3) return Colors.white;
    return Colors.white;
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
                child: WeatherForecastWidget(forecastData: _forecastData),
              )
            : Container(
                key: const ValueKey('dock_pill'),
                child: ClipRRect(
                borderRadius: BorderRadius.circular(36.0),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: Container(
                    padding: const EdgeInsets.all(6.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(36.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
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
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    _getWeatherIcon(_weatherCode),
                                    color: _getWeatherIconColor(_weatherCode),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    "${_getWeatherDescription(_weatherCode)}, ${_temperature ?? '--'}°C",
                                    style: const TextStyle(
                                      fontSize: 13.0,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                      fontFamily: 'Roboto',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: const Icon(Icons.public,
                                      color: Colors.blue, size: 28),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    "Open Web",
                                    style: const TextStyle(
                                      fontSize: 13.0,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                      fontFamily: 'Roboto',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
