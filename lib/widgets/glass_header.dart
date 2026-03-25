import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'clock_capsule.dart';

class GlassStatusBar extends StatelessWidget {
  final double opacity;

  const GlassStatusBar({
    super.key,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: CASISpacing.sm),
      child: ClockCapsule(opacity: opacity),
    );
  }
}
