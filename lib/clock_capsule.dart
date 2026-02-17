import 'dart:async';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'weather_capsule.dart';
import 'status_icons_capsule.dart';

class ClockCapsule extends StatefulWidget {
  final double opacity;

  const ClockCapsule({super.key, this.opacity = 1.0});

  @override
  State<ClockCapsule> createState() => _ClockCapsuleState();
}

class _ClockCapsuleState extends State<ClockCapsule> {
  late Timer _timer;
  
  // --- Time State ---
  DateTime _now = DateTime.now();
  String? _clockPackage;

  @override
  void initState() {
    super.initState();
    _findClockApp();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  Future<void> _findClockApp() async {
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps(withIcon: false, excludeSystemApps: false);
      
      String? findPackage(List<String> priorityPackages, String keyword) {
        // 1. Check priority list
        for (var pkg in priorityPackages) {
          if (apps.any((app) => app.packageName == pkg)) return pkg;
        }
        // 2. Search by name or package name
        final lowerKeyword = keyword.toLowerCase();
        final app = apps.where(
          (app) => app.name.toLowerCase() == lowerKeyword ||
                   app.packageName.toLowerCase().contains(lowerKeyword) ||
                   app.name.toLowerCase().contains(lowerKeyword),
        ).firstOrNull;
        return app?.packageName;
      }

      _clockPackage = findPackage([
        'com.google.android.deskclock',
        'com.android.deskclock',
        'com.sec.android.app.clockpackage',
        'com.oneplus.deskclock',
      ], 'clock');

    } catch (e) {
      debugPrint("Error finding clock app: $e");
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

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour == 0 || _now.hour == 12 ? 12 : _now.hour % 12;
    final minute = _now.minute.toString().padLeft(2, '0');
    final double screenHeight = MediaQuery.of(context).size.height;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Clock Section (1/4 of screen)
        SizedBox(
          height: screenHeight * 0.22,
          width: double.infinity,
          child: GestureDetector(
            onTap: () => _launchApp(_clockPackage),
            child: FittedBox(
              fit: BoxFit.contain,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(1.1, 1.5, 1.0),
                  child: Text(
                    "$hour:$minute",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Weather and Status Section (Underneath)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              WeatherCapsule(opacity: widget.opacity),
              StatusIconsCapsule(opacity: widget.opacity),
            ],
          ),
        ),
      ],
    );
  }
}