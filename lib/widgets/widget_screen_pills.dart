import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/models/widget_items.dart';

// Pills rendered inside the Widgets Screen. They mirror the home-screen
// alarm/timer pill sizing (70px tall) but sit at half the width of the
// music-player rail to fit two per row.

const double kWidgetPillHeight = 70.0;
const double kWidgetPillCorner = 35.0;

/// Plain liquid-glass pill used by every widget tile (alarm, timer,
/// weather). Per-type accent tints were removed so the grid reads as one
/// unified liquid-glass material — content alone differentiates the tiles.
Widget _glassPill({
  required Widget child,
  required Widget backgroundWidget,
}) {
  return LiquidGlassSurface.foresight(
    backgroundWidget: backgroundWidget,
    cornerRadius: kWidgetPillCorner,
    height: kWidgetPillHeight,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    child: child,
  );
}

class WidgetScreenAlarmPill extends StatelessWidget {
  final AppAlarm alarm;
  final Widget backgroundWidget;

  const WidgetScreenAlarmPill({
    super.key,
    required this.alarm,
    required this.backgroundWidget,
  });

  @override
  Widget build(BuildContext context) {
    final parts = alarm.label.split(' ');
    String dayLabel;
    String timeLabel;
    if (parts.length == 3) {
      dayLabel = _expandDay(parts[0]);
      timeLabel = "${parts[1]} ${parts[2]}";
    } else if (parts.length == 2) {
      dayLabel = "Daily";
      timeLabel = "${parts[0]} ${parts[1]}";
    } else {
      dayLabel = alarm.label;
      timeLabel = "";
    }

    return _glassPill(
      backgroundWidget: backgroundWidget,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            dayLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            timeLabel,
            style: const TextStyle(
              color: CASIColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  static String _expandDay(String abbr) {
    switch (abbr) {
      case 'Mon':
        return 'Monday';
      case 'Tue':
        return 'Tuesday';
      case 'Wed':
        return 'Wednesday';
      case 'Thu':
        return 'Thursday';
      case 'Fri':
        return 'Friday';
      case 'Sat':
        return 'Saturday';
      case 'Sun':
        return 'Sunday';
      default:
        return abbr;
    }
  }
}

class WidgetScreenTimerPill extends StatelessWidget {
  final AppTimer timer;
  final Widget backgroundWidget;

  const WidgetScreenTimerPill({
    super.key,
    required this.timer,
    required this.backgroundWidget,
  });

  @override
  Widget build(BuildContext context) {
    final total = timer.totalSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final text =
        "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";

    return _glassPill(
      backgroundWidget: backgroundWidget,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w400,
            fontFeatures: [FontFeature.tabularFigures()],
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// The Weather widget pill. Always present in either Active or Inactive,
/// never deletable, never created from the + menu.
class WidgetScreenWeatherPill extends StatelessWidget {
  final Widget backgroundWidget;

  const WidgetScreenWeatherPill({
    super.key,
    required this.backgroundWidget,
  });

  @override
  Widget build(BuildContext context) {
    return _glassPill(
      backgroundWidget: backgroundWidget,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Text(
            "Weather",
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 2),
          Text(
            "Widget",
            style: TextStyle(
              color: CASIColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// Ghost/outline pill shown in a drop target while dragging. Green = will
// be moved to Active, Red = will be moved to Inactive. Kept as a flat
// outlined shape (not liquid glass) — it's a transient drop affordance,
// not a content surface, and the strong solid color is the entire point.
class GhostPill extends StatelessWidget {
  final Color color;

  const GhostPill({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kWidgetPillHeight,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(kWidgetPillCorner),
        border: Border.all(
          color: color.withValues(alpha: 0.75),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Icon(
          color == CASIColors.confirm
              ? Icons.check_rounded
              : Icons.remove_rounded,
          color: color,
          size: 24,
        ),
      ),
    );
  }
}
