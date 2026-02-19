import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScreenDock extends StatefulWidget {
  const ScreenDock({super.key});

  @override
  State<ScreenDock> createState() => _ScreenDockState();
}

class _ScreenDockState extends State<ScreenDock> with WidgetsBindingObserver {
  // Weather State
  int? _temperature;
  int? _weatherCode;
  bool _isLoadingWeather = false;

  // Browser State
  AppInfo? _browserApp;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWeather();
    _findBrowserApp();
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
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current_weather=true');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          final current = data['current_weather'];
          final temp = (current['temperature'] as num).round();
          final code = (current['weathercode'] as num).toInt();

          setState(() {
            _temperature = temp;
            _weatherCode = code;
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

  // --- Browser Logic ---
  Future<void> _findBrowserApp() async {
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(
          withIcon: true, excludeSystemApps: false);

      // Priority list for browsers
      const priorityPackages = [
        'com.android.chrome',
        'com.google.android.apps.chrome',
        'com.sec.android.app.sbrowser',
        'org.mozilla.firefox',
        'com.microsoft.emmx',
      ];

      AppInfo? foundApp;
      for (var pkg in priorityPackages) {
        try {
          foundApp = apps.firstWhere((app) => app.packageName == pkg);
          break;
        } catch (_) {}
      }

      // Fallback to searching "browser" or "chrome"
      if (foundApp == null) {
        try {
          foundApp = apps.firstWhere((app) =>
              app.packageName.toLowerCase().contains('chrome') ||
              app.packageName.toLowerCase().contains('browser'));
        } catch (_) {}
      }

      if (mounted && foundApp != null) {
        setState(() {
          _browserApp = foundApp;
        });
      }
    } catch (e) {
      debugPrint("Error finding browser: $e");
    }
  }

  void _launchBrowser() {
    if (_browserApp != null) {
      InstalledApps.startApp(_browserApp!.packageName);
    } else {
      // Fallback if no specific browser found
      InstalledApps.startApp('com.android.chrome');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 40.0),
      child: Row(
        children: [
          // Weather Pill
          Expanded(
            child: _GlassPill(
              onTap: _fetchWeather,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Current Forecast",
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w500,
                            color: Colors.black.withOpacity(0.7),
                            fontFamily: 'Roboto',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                    child: _browserApp?.icon != null
                        ? Image.memory(_browserApp!.icon!)
                        : const Icon(Icons.public,
                            color: Colors.blue, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Search The Web",
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w500,
                            color: Colors.black.withOpacity(0.7),
                            fontFamily: 'Roboto',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "Open Chrome",
                          style: const TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            fontFamily: 'Roboto',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            height: 75.0,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(30.0),
              border: Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
