import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// A frosted-glass notification pill that drops from the top center of the
/// screen and auto-dismisses after a few seconds.
///
/// Uses CASI glass.raised (18% white, 12% border) with heavy blur.
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
      duration: CASIMotion.fast,       // 150ms enter (section 7.2)
      reverseDuration: CASIMotion.micro, // 100ms exit
    );

    // Slide: starts above screen (-1.0) → drops to position (0.0)
    _slideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: CASIMotion.easeEnter,   // Decelerate in
        reverseCurve: CASIMotion.easeExit, // Accelerate out
      ),
    );

    // Fade in/out
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
        reverseCurve: CASIMotion.easeExit,
      ),
    );

    _controller.forward().then((_) {
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
          top: topPadding + CASISpacing.sm + (_slideAnimation.value * (topPadding + 60)),
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
            if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
              _controller.reverse().then((_) {
                if (mounted) widget.onDismissed();
              });
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CASISearchBarSpec.cornerRadius),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: CASIGlass.blurHeavy,
                sigmaY: CASIGlass.blurHeavy,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CASISearchBarSpec.horizontalPadding,
                  vertical: 12,
                ),
                constraints: const BoxConstraints(maxWidth: 300),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: CASIElevation.raised.bgAlpha),
                  borderRadius: BorderRadius.circular(CASISearchBarSpec.cornerRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: CASIElevation.raised.borderAlpha),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        color: CASIColors.textPrimary,
                        size: CASIIcons.small,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        widget.message,
                        style: CASITypography.body2.copyWith(
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
