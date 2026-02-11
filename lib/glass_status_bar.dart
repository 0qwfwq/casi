import 'package:flutter/material.dart';
import 'clock_capsule.dart';

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: ClockCapsule(opacity: opacity),
    );
  }
}
