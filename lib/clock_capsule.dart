import 'dart:async';
import 'package:flutter/material.dart';
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
  String? _calendarPackage;

  @override
  void initState() {
    super.initState();
    _findSystemApps();
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

      _calendarPackage = findPackage([
        'com.google.android.calendar',
        'com.android.calendar',
        'com.samsung.android.calendar',
        'com.oneplus.calendar',
      ], 'calendar');

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

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour == 0 || _now.hour == 12 ? 12 : _now.hour % 12;
    final amPm = _now.hour >= 12 ? 'PM' : 'AM';
    final minute = _now.minute.toString().padLeft(2, '0');
    final date = "${_now.month}/${_now.day}";

    return _GlassCapsule(
      opacity: widget.opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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