import 'dart:ui';
import 'package:flutter/material.dart';

/// A frosted-glass notification pill that drops from the top center of the
/// screen (near the holepunch camera) and auto-dismisses after a few seconds.
///
/// Usage:
///   NotifyPill.show(context, 'Home Screen is full!');
///   NotifyPill.show(context, 'App added to Home Screen', icon: Icons.check);
class NotifyPill extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Duration duration;

  const NotifyPill({
    super.key,
    required this.message,
    this.icon,
    this.duration = const Duration(seconds: 3),
  });

  /// Show a notification pill overlay.
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _NotifyPillOverlay(
        message: message,
        icon: icon,
        duration: duration,
        onDismissed: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  @override
  State<NotifyPill> createState() => _NotifyPillState();
}

class _NotifyPillState extends State<NotifyPill> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

// ─── Overlay Animation Widget ────────────────────────────────────────────────

class _NotifyPillOverlay extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDismissed;

  const _NotifyPillOverlay({
    required this.message,
    this.icon,
    required this.duration,
    required this.onDismissed,
  });

  @override
  State<_NotifyPillOverlay> createState() => _NotifyPillOverlayState();
}

class _NotifyPillOverlayState extends State<_NotifyPillOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
    );

    // Slide: starts above screen (-1.0) → drops to position (0.0)
    _slideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn),
    );

    // Fade in/out
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut, reverseCurve: Curves.easeIn),
    );

    _controller.forward().then((_) {
      // Wait, then reverse to dismiss
      Future.delayed(widget.duration, () {
        if (mounted) {
          _controller.reverse().then((_) {
            if (mounted) widget.onDismissed();
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          // Slide from above the screen, land just below the status bar / holepunch
          top: topPadding + 8 + (_slideAnimation.value * (topPadding + 60)),
          left: 0,
          right: 0,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: Center(
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            // Swipe up to dismiss early
            if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
              _controller.reverse().then((_) {
                if (mounted) widget.onDismissed();
              });
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          decoration: TextDecoration.none,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
