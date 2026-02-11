import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClockCapsule extends StatefulWidget {
  final double opacity;

  const ClockCapsule({super.key, this.opacity = 1.0});

  @override
  State<ClockCapsule> createState() => _ClockCapsuleState();
}

class _ClockCapsuleState extends State<ClockCapsule> with WidgetsBindingObserver {
  late Timer _timer;
  DateTime _now = DateTime.now();
  String? _clockPackage;
  double? _latitude;
  double? _longitude;

  // Weather State
  String? _weatherPackage;
  int? _temperature;
  bool _isWeatherLoading = false;

  // Status State
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.full;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isWifiConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _findSystemApps();
    _initLocation();
    _initWeather();
    _initBattery();
    _initConnectivity();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
        // Poll battery every minute
        if (timer.tick % 60 == 0) {
          _getBatteryLevel();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchWeather();
      _getBatteryLevel();
    }
  }

  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        if (mounted) {
          setState(() {
            _latitude = position.latitude;
            _longitude = position.longitude;
          });
          _fetchWeather();
        }
      }
    } catch (e) {
      debugPrint("Error getting location for clock color: $e");
    }
  }

  Future<void> _initWeather() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _temperature = prefs.getInt('last_temperature');
      });
    }
  }

  Future<void> _fetchWeather() async {
    if (_isWeatherLoading || _latitude == null || _longitude == null) return;
    if (mounted) setState(() => _isWeatherLoading = true);

    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$_latitude&longitude=$_longitude&current_weather=true');
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
      if (mounted) setState(() => _isWeatherLoading = false);
    }
  }

  void _initBattery() {
    _getBatteryLevel();
    _battery.batteryState.then((state) {
      if (mounted) {
        setState(() => _batteryState = state);
      }
    });
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      if (mounted) {
        setState(() => _batteryState = state);
        _getBatteryLevel();
      }
    });
  }

  Future<void> _getBatteryLevel() async {
    try {
      final int level = await _battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryLevel = level);
      }
    } catch (e) {
      debugPrint("Error getting battery level: $e");
    }
  }

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    final results = await connectivity.checkConnectivity();
    if (mounted) {
      setState(() => _isWifiConnected = results.contains(ConnectivityResult.wifi));
    }
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((results) {
      if (mounted) {
        setState(() => _isWifiConnected = results.contains(ConnectivityResult.wifi));
      }
    });
  }

  Future<void> _findSystemApps() async {
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(withIcon: false, excludeSystemApps: false);
      
      String? findPackage(List<String> priorityPackages, String keyword) {
        for (var pkg in priorityPackages) {
          if (apps.any((app) => app.packageName == pkg)) return pkg;
        }
        try {
          return apps.firstWhere((app) => app.name.toLowerCase() == keyword.toLowerCase()).packageName;
        } catch (_) {}
        try {
          return apps.firstWhere((app) => app.packageName.toLowerCase().contains(keyword)).packageName;
        } catch (_) {}
        try {
          return apps.firstWhere((app) => app.name.toLowerCase().contains(keyword)).packageName;
        } catch (_) {}
        return null;
      }

      _clockPackage = findPackage([
        'com.google.android.deskclock',
        'com.android.deskclock',
        'com.sec.android.app.clockpackage',
        'com.oneplus.deskclock',
      ], 'clock');

      _weatherPackage = findPackage([
        'com.google.android.apps.dynaprop',
        'com.samsung.android.weather',
        'com.sec.android.daemonapp',
        'net.oneplus.weather',
        'com.miui.weather2',
        'com.huawei.android.weather',
        'com.sonymobile.xperiaweather',
        'com.asus.weather',
        'com.accuweather.android',
        'com.weather.Weather',
        'com.apple.weather',
      ], 'weather');

    } catch (e) {
      debugPrint("Error finding system apps: $e");
    }
  }

  void _launchApp(String? packageName) {
    if (packageName != null) {
      InstalledApps.startApp(packageName);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    _batteryStateSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour == 0 || _now.hour == 12 ? 12 : _now.hour % 12;
    final minute = _now.minute.toString().padLeft(2, '0');

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Weather Section (Left)
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _GlassCapsule(
                  opacity: widget.opacity,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    child: GestureDetector(
                      onTap: () => _launchApp(_weatherPackage),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _temperature != null ? "$_temperature°" : "--",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Clock Section (Center)
            GestureDetector(
              onTap: () => _launchApp(_clockPackage),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(1.1, 1.5, 1.0),
                child: Text(
                  "$hour:$minute",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 48,
                    height: 1.0,
                  ),
                ),
              ),
            ),

            // Status Section (Right)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _GlassCapsule(
                  opacity: widget.opacity,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "$_batteryLevel%",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Icon(_isWifiConnected ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        children: [
          Positioned.fill(
            child: OCLiquidGlass(
              color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
              child: const SizedBox(),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
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