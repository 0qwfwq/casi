import 'package:flutter/material.dart';
import 'dart:ui';

/// The parent wrapper for the dynamic pill.
/// It handles the layout structure, the glassmorphic background, 
/// and the swipe left/right gestures to dismiss it.
class DynamicPill extends StatelessWidget {
  final Widget child;
  final VoidCallback onDismissed;
  
  // --- NEW: Optional widget to float directly above the pill (like a checkmark) ---
  final Widget? topWidget; 

  const DynamicPill({
    super.key,
    required this.child,
    required this.onDismissed,
    this.topWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key ?? UniqueKey(),
      direction: DismissDirection.horizontal,
      onDismissed: (direction) => onDismissed(),
      // Wrapping in a stack INSIDE the dismissible ensures the topWidget swipes away with the pill
      child: Stack(
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
          
          // --- NEW: Inject the floating action button above the glass ---
          if (topWidget != null)
            Positioned(
              top: -55, 
              child: AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 300),
                child: topWidget!,
              ),
            ),
        ],
      ),
    );
  }
}