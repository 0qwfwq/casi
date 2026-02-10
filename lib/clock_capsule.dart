import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class ClockCapsule extends StatefulWidget {
  final double opacity;

  const ClockCapsule({super.key, this.opacity = 1.0});

  @override
  State<ClockCapsule> createState() => _ClockCapsuleState();
}

class _ClockCapsuleState extends State<ClockCapsule> {
  late Timer _timer;
  DateTime _now = DateTime.now();
  String? _clockPackage;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _findSystemApps();
    _initLocation();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  Future<void> _initLocation() async {
    try {
      // Check permissions (assuming WeatherCapsule handles the request, we just check)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        if (mounted) {
          setState(() {
            _latitude = position.latitude;
            _longitude = position.longitude;
          });
        }
      }
    } catch (e) {
      debugPrint("Error getting location for clock color: $e");
    }
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
    _timer.cancel();
    super.dispose();
  }

  // Calculates solar elevation angle in degrees
  double _calculateSolarElevation(DateTime date, double latitude, double longitude) {
    DateTime utc = date.toUtc();
    // Julian Day
    double julianDay = 367 * utc.year -
        (7 * (utc.year + (utc.month + 9) ~/ 12)) ~/ 4 +
        (275 * utc.month) ~/ 9 +
        utc.day +
        1721013.5 +
        (utc.hour + utc.minute / 60.0 + utc.second / 3600.0) / 24.0;

    double n = julianDay - 2451545.0;
    double L = (280.460 + 0.9856474 * n) % 360;
    double g = (357.528 + 0.9856003 * n) % 360;
    double gRad = g * math.pi / 180;
    double lambda = L + 1.915 * math.sin(gRad) + 0.020 * math.sin(2 * gRad);
    double lambdaRad = lambda * math.pi / 180;
    double epsilon = 23.439 - 0.0000004 * n;
    double epsilonRad = epsilon * math.pi / 180;
    double alpha = math.atan2(math.cos(epsilonRad) * math.sin(lambdaRad), math.cos(lambdaRad));
    double delta = math.asin(math.sin(epsilonRad) * math.sin(lambdaRad));
    double gmst = 6.697375 + 0.0657098242 * n + utc.hour + (utc.minute + utc.second / 60.0) / 60.0;
    gmst = (gmst % 24) * 15;
    double lst = gmst + longitude;
    double lstRad = lst * math.pi / 180;
    double H = lstRad - alpha;
    double latRad = latitude * math.pi / 180;
    double sinElevation = math.sin(latRad) * math.sin(delta) + math.cos(latRad) * math.cos(delta) * math.cos(H);
    
    return math.asin(sinElevation) * 180 / math.pi;
  }

  Color _getSolarColor() {
    // Fallback if location is not available
    if (_latitude == null || _longitude == null) {
      return _getSimpleTimeColor();
    }

    double elevation = _calculateSolarElevation(_now, _latitude!, _longitude!);

    // Day: > 6 degrees
    if (elevation > 6) return Colors.white;
    
    // Transition to Golden Hour: 6 to 0 degrees
    if (elevation > 0) {
      double t = (6 - elevation) / 6;
      return Color.lerp(Colors.white, const Color(0xFFFF8C00), t)!; // White -> Deep Orange
    }
    
    // Golden Hour: 0 to -4 degrees
    if (elevation > -4) {
      double t = (0 - elevation) / 4;
      return Color.lerp(const Color(0xFFFF8C00), const Color(0xFFC2185B), t)!; // Deep Orange -> Magenta
    }
    
    // Blue Hour: -4 to -6 degrees
    if (elevation > -6) {
      double t = (-4 - elevation) / 2;
      return Color.lerp(const Color(0xFFC2185B), const Color(0xFF304FFE), t)!; // Magenta -> Deep Cobalt/Violet
    }
    
    // Night: < -6 degrees (Fade to Dark)
    return const Color(0xFF120024); // Dark Purple/Black
  }

  Color _getSimpleTimeColor() {
    final double hour = _now.hour + _now.minute / 60.0;
    final double t = 1.0 - ((hour - 12.0).abs() / 12.0);
    return Color.lerp(const Color(0xFF120024), Colors.white, t)!;
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour == 0 || _now.hour == 12 ? 12 : _now.hour % 12;
    final minute = _now.minute.toString().padLeft(2, '0');

    return _GlassCapsule(
      opacity: widget.opacity,
      color: _getSolarColor(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
        child: GestureDetector(
          onTap: () => _launchApp(_clockPackage),
          child: SizedBox(
            width: double.infinity,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scale(1.0, 1.3),
              child: Text(
                "$hour:$minute",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 70,
                  height: 1.0,
                ),
              ),
            ),
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
    return Stack(
      children: [
        if (opacity > 0)
          Positioned.fill(
            child: OCLiquidGlass(
              borderRadius: 30,
              color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
              child: const SizedBox(),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: (color ?? Colors.white).withValues(alpha: 0.1 * opacity),
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
    );
  }
}