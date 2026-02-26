import 'package:flutter/material.dart';
import 'dart:ui';

/// The parent wrapper for the dynamic pill.
/// It handles the layout structure, the glassmorphic background, 
/// and the swipe left/right gestures to dismiss it.
class DynamicPill extends StatelessWidget {
  final Widget child;
  final VoidCallback onDismissed;

  const DynamicPill({
    super.key,
    required this.child,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    // Upgraded to Dismissible for a smooth, premium visual swipe-away effect
    return Dismissible(
      key: key ?? UniqueKey(),
      direction: DismissDirection.horizontal,
      onDismissed: (direction) => onDismissed(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(40.0),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            // The child will be whatever specific pill is currently active (e.g. DClockPill)
            child: child, 
          ),
        ),
      ),
    );
  }
}