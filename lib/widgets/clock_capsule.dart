import 'dart:async';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:casi/design_system.dart';

// --- Custom notifications that bubble up to the Hub ---
class CalendarTapNotification extends Notification {}

class ClockCapsule extends StatefulWidget {
  final double opacity;

  /// Whether to render the time digits. When false, the clock collapses
  /// to zero height so pills and widgets below the capsule shift up into
  /// the freed space.
  final bool showClock;

  /// Whether to render the date label. When false the date glyphs are
  /// hidden but the date slot keeps its full reserved height — nothing
  /// below the capsule is ever allowed to drift up into where the date
  /// sits on screen.
  final bool showDate;

  const ClockCapsule({
    super.key,
    this.opacity = 1.0,
    this.showClock = true,
    this.showDate = true,
  });

  /// Always-reserved vertical band for the date row. Comfortable enough
  /// for the 18sp date text plus its drop-shadow halo. Kept as a const
  /// so the home screen layout can reason about it without measuring.
  static const double dateSlotHeight = 36.0;

  /// Fraction of the available screen height reclaimed by the clock
  /// digits when [showClock] is true.
  static const double clockHeightFraction = 0.17;

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

    final dateStyle = CASITypography.body1.copyWith(
      color: Colors.white.withValues(alpha: 0.92),
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      shadows: [
        Shadow(
          offset: const Offset(0, 1),
          blurRadius: 6.0,
          color: Colors.black.withValues(alpha: 0.35),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. Date slot — height is reserved unconditionally so pills
        // and widgets below the capsule can never creep up into where
        // the date glyphs sit, regardless of [showDate].
        SizedBox(
          height: ClockCapsule.dateSlotHeight,
          child: GestureDetector(
            onTap: widget.showDate
                ? () => CalendarTapNotification().dispatch(context)
                : null,
            onLongPress: widget.showDate
                ? () => _launchApp(_calendarPackage)
                : null,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: AnimatedOpacity(
                duration: CASIMotion.standard,
                opacity: widget.showDate ? 1.0 : 0.0,
                child: Text(_getFormattedDate(), style: dateStyle),
              ),
            ),
          ),
        ),

        // 2. Clock — collapses entirely when hidden so the pills/widgets
        // that follow shift up into the freed space.
        AnimatedSize(
          duration: CASIMotion.standard,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: widget.showClock
              ? SizedBox(
                  height: screenHeight * ClockCapsule.clockHeightFraction,
                  width: double.infinity,
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: CASISpacing.md),
                      child: Center(
                        child: _LiquidGlassClockText(text: "$hour:$minute"),
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// The time-of-day glyphs rendered as liquid glass.
///
/// The digits use a thin, condensed display weight and are filled with
/// a vertical white-to-translucent-to-white gradient via a [ShaderMask],
/// which gives the iOS-26 "wet glass" sheen across the body of each
/// numeral. A soft dark drop-shadow Text sits behind the gradient layer
/// to keep the digits legible against busy wallpapers.
///
/// Wrapped in a [FittedBox] so the digits scale down to the available
/// width without manually re-tuning [TextStyle.fontSize] per device.
class _LiquidGlassClockText extends StatelessWidget {
  final String text;

  const _LiquidGlassClockText({required this.text});

  @override
  Widget build(BuildContext context) {
    const TextStyle baseStyle = TextStyle(
      fontFamily: CASITypography.fontFamily,
      fontSize: 220,
      fontWeight: FontWeight.w200,
      height: 1.0,
      letterSpacing: -8.0,
      color: Colors.white,
    );

    return FittedBox(
      fit: BoxFit.contain,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft drop-shadow halo. Drawn separately from the gradient
          // layer so the shadow keeps its full alpha — a [ShaderMask]
          // would otherwise clip the shadow to the glyph body.
          Text(
            text,
            textAlign: TextAlign.center,
            style: baseStyle.copyWith(
              color: Colors.transparent,
              shadows: [
                Shadow(
                  offset: const Offset(0, 8),
                  blurRadius: 28.0,
                  color: Colors.black.withValues(alpha: 0.30),
                ),
                Shadow(
                  offset: const Offset(0, 2),
                  blurRadius: 8.0,
                  color: Colors.black.withValues(alpha: 0.18),
                ),
              ],
            ),
          ),
          // Gradient-masked translucent body — the "liquid glass" look.
          // Vertical alpha ramp: bright at the top edge, see-through
          // through the middle, bright again toward the bottom — the
          // wallpaper reads through the dim band.
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (Rect bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.95),
                Colors.white.withValues(alpha: 0.50),
                Colors.white.withValues(alpha: 0.88),
              ],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(bounds),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: baseStyle,
            ),
          ),
        ],
      ),
    );
  }
}
