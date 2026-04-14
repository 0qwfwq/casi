import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// The parent wrapper for the dynamic pill. Uses the unified visionOS
/// glass material at the pill role opacity.
class DynamicPill extends StatelessWidget {
  final Widget child;

  const DynamicPill({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        GlassSurface.pill(
          cornerRadius: CASIGlass.cornerStandard,
          padding: const EdgeInsets.symmetric(
            horizontal: CASISpacing.sm,
            vertical: CASISpacing.sm,
          ),
          child: child,
        ),
      ],
    );
  }
}
