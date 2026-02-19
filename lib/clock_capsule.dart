import 'dart:async';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

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
        for (var pkg in priorityPackages) {
          if (apps.any((app) => app.packageName == pkg)) return pkg;
        }
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

  // Helper to format date like "Wed Jun 11" without needing 'intl' package
  String _getFormattedDate() {
    const List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    String dayName = days[_now.weekday - 1];
    String monthName = months[_now.month - 1];
    String dayNum = _now.day.toString();
    
    return "$dayName $monthName $dayNum";
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. The Date (Small, standard sans-serif, centered)
        Padding(
          padding: const EdgeInsets.only(bottom: 4.0), // Slight gap between date and time
          child: Text(
            _getFormattedDate(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              fontFamily: 'Roboto', // Or system default
            ),
          ),
        ),

        // 2. The Clock (Massive, Extra-Condensed)
        SizedBox(
          // Increased height allocation to allow for the tall font stretching
          height: screenHeight * 0.20, 
          width: double.infinity,
          child: GestureDetector(
            onTap: () => _launchApp(_clockPackage),
            child: FittedBox(
              fit: BoxFit.contain,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Transform(
                  alignment: Alignment.center,
                  // X=0.85 (Squeeze width), Y=2.0 (Stretch height) -> Creates "Extra Condensed" look
                  transform: Matrix4.diagonal3Values(0.85, 1.0, 1.0),
                  child: Text(
                    "$hour:$minute",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      // Using a bold weight helps the font retain visibility when squeezed
                      fontWeight: FontWeight.bold, 
                      height: 1.0,
                      letterSpacing: -2.0, // Tighten the gap between numbers
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}