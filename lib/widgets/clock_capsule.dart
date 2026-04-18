import 'dart:async';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:casi/design_system.dart';

// --- Custom notifications that bubble up to the Hub ---
class CalendarTapNotification extends Notification {}

class ClockCapsule extends StatefulWidget {
  final double opacity;

  const ClockCapsule({super.key, this.opacity = 1.0});

  @override
  State<ClockCapsule> createState() => _ClockCapsuleState();
}

class _ClockCapsuleState extends State<ClockCapsule> {
  late Timer _timer;

  DateTime _now = DateTime.now();
  String? _calendarPackage;

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

      _calendarPackage = findPackage([
        'com.google.android.calendar',
        'com.samsung.android.calendar',
        'com.android.calendar',
        'com.oneplus.calendar',
      ], 'calendar');

    } catch (e) {
      debugPrint("Error finding clock app: $e");
    }
  }

  void _launchApp(String? packageName) {
    if (packageName != null) {
      InstalledApps.startApp(packageName);
    }
  }

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
        // 1. The Date — type.body2 equivalent (Inter, 14sp would be too small here; using body1 at 20sp)
        GestureDetector(
          onTap: () => CalendarTapNotification().dispatch(context),
          onLongPress: () => _launchApp(_calendarPackage),
          child: Padding(
            padding: const EdgeInsets.only(bottom: CASISpacing.sm),
            child: Text(
              _getFormattedDate(),
              style: CASITypography.body1.copyWith(
                color: CASIColors.textSecondary,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    offset: const Offset(0, 2),
                    blurRadius: 4.0,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 2. The Clock — non-interactive. Tapping and long-press are
        // intentionally disabled; users manage alarms/timers in the
        // Widgets Screen (long-press the wallpaper) and open the system
        // clock from the app drawer.
        SizedBox(
          height: screenHeight * 0.17,
          width: double.infinity,
          child: IgnorePointer(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: CASISpacing.md),
                child: Text(
                  "$hour:$minute",
                  textAlign: TextAlign.center,
                  style: CASITypography.display.copyWith(
                    fontSize: 120, // Will be scaled by FittedBox
                    fontWeight: FontWeight.w200,
                    height: 1.0,
                    letterSpacing: -1.0,
                    shadows: [
                      Shadow(
                        offset: const Offset(0, 8),
                        blurRadius: 16.0,
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      Shadow(
                        offset: const Offset(0, 2),
                        blurRadius: 4.0,
                        color: Colors.black.withValues(alpha: 0.2),
                      ),
                    ],
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
