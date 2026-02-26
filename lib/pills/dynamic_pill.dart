import 'package:flutter/material.dart';
import 'dart:ui';

/// The parent wrapper for the dynamic pill.
/// It handles the layout structure and the glassmorphic background.
/// Swipe-to-dismiss has been removed; dismissal relies on tapping outside.
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
              child: child, 
            ),
          ),
        ),
      ],
    );
  }
}