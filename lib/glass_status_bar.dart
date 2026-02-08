import 'package:flutter/material.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';
import 'clock_capsule.dart';
import 'status_icons_capsule.dart';
import 'weather_capsule.dart';

class GlassStatusBar extends StatelessWidget {
  final bool isImageBackground;
  final Color backgroundColor;
  final double opacity;

  const GlassStatusBar({
    super.key,
    this.isImageBackground = false,
    this.backgroundColor = Colors.black,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity == 0) return const SizedBox.shrink();

    return OCLiquidGlassGroup(
      settings: OCLiquidGlassSettings(
        blurRadiusPx: 3.0 * opacity,
        specStrength: 5.0 * opacity,
        distortExponent: 1.0,
        distortFalloffPx: 20.0,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            WeatherCapsule(opacity: opacity),
            ClockCapsule(opacity: opacity),
            StatusIconsCapsule(opacity: opacity),
          ],
        ),
      ),
    );
  }
}
