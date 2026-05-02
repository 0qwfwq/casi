import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'clock_capsule.dart';

class GlassStatusBar extends StatelessWidget {
  final double opacity;

  /// User-toggleable: render the time digits.
  final bool showClock;

  /// User-toggleable: render the date label. The date *slot* (its
  /// reserved vertical space) stays in the layout regardless of this
  /// flag — see [ClockCapsule.dateSlotHeight].
  final bool showDate;

  /// Wallpaper the liquid-glass clock pills refract. Pass
  /// [WallpaperService.buildBackground()].
  final Widget backgroundWidget;

  const GlassStatusBar({
    super.key,
    this.opacity = 1.0,
    this.showClock = true,
    this.showDate = true,
    required this.backgroundWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: CASISpacing.sm),
      child: ClockCapsule(
        opacity: opacity,
        showClock: showClock,
        showDate: showDate,
        backgroundWidget: backgroundWidget,
      ),
    );
  }
}
