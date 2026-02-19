import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeatherCapsule extends StatefulWidget {
  final double opacity;

  const WeatherCapsule({
    super.key,
    this.opacity = 1.0,
  });

  @override
  State<WeatherCapsule> createState() => _WeatherCapsuleState();
}

class _WeatherCapsuleState extends State<WeatherCapsule> with WidgetsBindingObserver {
  String? _weatherPackage;
  int? _temperature;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _findWeatherApp();
    _initWeather();
  }

  Future<void> _initWeather() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _temperature = prefs.getInt('last_temperature');
      });
    }
    _fetchWeather();
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

  Future<void> _fetchWeather() async {
    if (_isLoading) return;
    if (mounted) setState(() => _isLoading = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permissions are denied');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      
      // Using Open-Meteo API (No API key required)
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current_weather=true');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          final temp = (data['current_weather']['temperature'] as num).round();
          setState(() => _temperature = temp);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('last_temperature', temp);
        }
      }
    } catch (e) {
      debugPrint("Error fetching weather: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _findWeatherApp() async {
    try {
      // Fetch apps without icons for speed
      List<AppInfo> apps = await InstalledApps.getInstalledApps(withIcon: false, excludeSystemApps: false);
      
      String? findPackage(List<String> priorityPackages, String keyword) {
        // 1. Check priority list
        for (var pkg in priorityPackages) {
          if (apps.any((app) => app.packageName == pkg)) return pkg;
        }
        // 2. Check for exact app name match (High confidence)
        try {
          return apps.firstWhere((app) => app.name.toLowerCase() == keyword.toLowerCase()).packageName;
        } catch (_) {}
        // 3. Check for keyword in package name
        try {
          return apps.firstWhere((app) => app.packageName.toLowerCase().contains(keyword)).packageName;
        } catch (_) {}
        // 4. Check for keyword in app name
        try {
          return apps.firstWhere((app) => app.name.toLowerCase().contains(keyword)).packageName;
        } catch (_) {}
        
        return null;
      }

      if (mounted) {
        setState(() {
          _weatherPackage = findPackage([
            'com.google.android.apps.dynaprop', // Google Weather
            'com.samsung.android.weather',      // Samsung Weather (Alternative)
            'com.sec.android.daemonapp',        // Samsung Weather (Service)
            'net.oneplus.weather',              // OnePlus Weather
            'com.miui.weather2',                // Xiaomi Weather
            'com.huawei.android.weather',       // Huawei Weather
            'com.sonymobile.xperiaweather',     // Sony Weather
            'com.asus.weather',                 // Asus Weather
            'com.accuweather.android',          // AccuWeather
            'com.weather.Weather',              // The Weather Channel
            'com.apple.weather',                // Just in case
          ], 'weather');
        });
      }
    } catch (e) {
      debugPrint("Error finding weather app: $e");
    }
  }

  void _launchApp(String? packageName) {
    if (packageName != null) {
      debugPrint("Attempting to launch: $packageName");
      InstalledApps.startApp(packageName);
    }
  }

  Color _getTemperatureColor(int? temp) {
    if (temp == null) return Colors.white.withValues(alpha: 0.5);
    if (temp < 15) return Colors.blueAccent; // Cold
    if (temp > 28) return Colors.redAccent;  // Hot
    return Colors.greenAccent;               // Nice
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _launchApp(_weatherPackage),
      child: _GlassCapsule(
        opacity: widget.opacity,
        color: _getTemperatureColor(_temperature),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                _temperature != null ? "$_temperature°" : "--",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassCapsule extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double opacity;
  
  const _GlassCapsule({required this.child, this.color, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(30)),
      child: Stack(
        children: [
          Positioned.fill(
            child: OCLiquidGlass(
              color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
              child: const SizedBox(),
            ),
          ),
          Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(30)),
              border: Border.all(
                color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
                width: 1.5,
              ),
            ),
            child: Opacity(
              opacity: opacity,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}