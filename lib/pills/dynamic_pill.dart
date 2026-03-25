import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:casi/design_system.dart';

/// The parent wrapper for the dynamic pill.
/// It handles the layout structure and the glassmorphic background.
/// Uses CASI glass.standard: 20dp blur, 12% white, 1dp border at 6% white.
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
        ClipRRect(
          borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: CASIGlass.blurStandard,
              sigmaY: CASIGlass.blurStandard,
            ),
            child: AnimatedContainer(
              duration: CASIMotion.micro,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(
                horizontal: CASISpacing.sm,
                vertical: CASISpacing.sm,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
                border: Border.all(
                  color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha),
                  width: 1.0,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
