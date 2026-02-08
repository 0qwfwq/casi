import 'package:flutter/material.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class StatusIconsCapsule extends StatelessWidget {
  final double opacity;

  const StatusIconsCapsule({super.key, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return _GlassCapsule(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.battery_std, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCapsule extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double opacity;
  
  const _GlassCapsule({required this.child, this.color, this.opacity = 1.0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (opacity > 0)
          Positioned.fill(
            child: OCLiquidGlass(
              borderRadius: 30,
              color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
              child: const SizedBox(),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: (color ?? Colors.white).withValues(alpha: 0.1 * opacity),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: (color ?? Colors.white).withValues(alpha: 0.2 * opacity),
              width: 1.5,
            ),
          ),
          child: Opacity(
            opacity: opacity,
            child: child,
          ),
        ),
      ],
    );
  }
}