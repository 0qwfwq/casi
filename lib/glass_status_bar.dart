import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class GlassStatusBar extends StatefulWidget {
  final bool isImageBackground;
  final Color backgroundColor;

  const GlassStatusBar({
    super.key,
    this.isImageBackground = false,
    this.backgroundColor = Colors.black,
  });

  @override
  State<GlassStatusBar> createState() => _GlassStatusBarState();
}

class _GlassStatusBarState extends State<GlassStatusBar> {
  late Timer _timer;
  DateTime _now = DateTime.now();
  String? _clockPackage;
  String? _calendarPackage;
  String? _weatherPackage;
  final int _temperature = 24; // Placeholder temperature

  @override
  void initState() {
    super.initState();
    _findSystemApps();
    // Update time every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  Future<void> _findSystemApps() async {
    try {
      // Fetch apps without icons for speed
      List<AppInfo> apps = await InstalledApps.getInstalledApps(withIcon: false, excludeSystemApps: false);
      
      String? findPackage(List<String> priorityPackages, String keyword) {
        // 1. Check priority list
        for (var pkg in priorityPackages) {
          if (apps.any((app) => app.packageName == pkg)) return pkg;
        }
        // 2. Check for keyword in package name
        try {
          return apps.firstWhere((app) => app.packageName.toLowerCase().contains(keyword)).packageName;
        } catch (_) {}
        // 3. Check for keyword in app name
        try {
          return apps.firstWhere((app) => app.name.toLowerCase() == keyword).packageName;
        } catch (_) {}
        
        return null;
      }

      _clockPackage = findPackage([
        'com.google.android.deskclock', // Google / Pixel
        'com.android.deskclock',        // AOSP
        'com.sec.android.app.clockpackage', // Samsung
        'com.oneplus.deskclock',        // OnePlus
      ], 'clock');

      _calendarPackage = findPackage([
        'com.google.android.calendar',  // Google / Pixel
        'com.android.calendar',         // AOSP
        'com.samsung.android.calendar', // Samsung
        'com.oneplus.calendar',         // OnePlus
      ], 'calendar');

      _weatherPackage = findPackage([
        'com.google.android.apps.dynaprop', // Google Weather
        'com.sec.android.daemonapp',        // Samsung Weather
        'net.oneplus.weather',              // OnePlus Weather
        'com.miui.weather2',                // Xiaomi Weather
        'com.apple.weather',                // Just in case
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

  Color _getTemperatureColor(int temp) {
    if (temp < 15) return Colors.blueAccent; // Cold
    if (temp > 28) return Colors.redAccent;  // Hot
    return Colors.greenAccent;               // Nice
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Format: 12:00 PM | 1/7
    final hour = _now.hour == 0 || _now.hour == 12 ? 12 : _now.hour % 12;
    final amPm = _now.hour >= 12 ? 'PM' : 'AM';
    final minute = _now.minute.toString().padLeft(2, '0');
    final date = "${_now.month}/${_now.day}";
    
    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        blurRadiusPx: 3.0,
        distortExponent: 1.0,
        distortFalloffPx: 20.0,
      ),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // Left Capsule (Weather)
          GestureDetector(
            onTap: () => _launchApp(_weatherPackage),
            child: _GlassCapsule(
              color: _getTemperatureColor(_temperature),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                child: Row(
                  children: [
                    const Icon(Icons.cloud, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "$_temperature°",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Right Capsule (Status Bar)
          Expanded(
            child: _GlassCapsule(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Time & Date
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _launchApp(_clockPackage),
                          child: Text(
                            "$hour:$minute $amPm",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Text(
                          " | ",
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        GestureDetector(
                          onTap: () => _launchApp(_calendarPackage),
                          child: Text(
                            date,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    Row(
                      children: [
                        // Battery Icon (Static for now)
                        const Icon(Icons.battery_std, color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        // Profile Avatar
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          child: const Icon(Icons.person, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ],
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
  
  const _GlassCapsule({required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Glass Layer (Background)
        Positioned.fill(
          child: OCLiquidGlass(
            borderRadius: 30,
            color: (color ?? Colors.white).withValues(alpha: 0.2),
            child: const SizedBox(), // Empty child, just the glass effect
          ),
        ),
        // Content Layer (Foreground - unaffected by distortion)
        Container(
          decoration: BoxDecoration(
            color: (color ?? Colors.white).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: (color ?? Colors.white).withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}
