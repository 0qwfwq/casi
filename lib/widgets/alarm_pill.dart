import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// Alarm schedule pill shown above the music player on the home screen.
///
/// Gestures:
/// - Tap (idle): plays a grow/shrink press-pulse, then opens the clock app
///   via [onTap].
/// - Tap (ringing): stops the alarm via [onStop].
///
/// In spatial mode pass [compact] = true so the pill shrinks to its text
/// content instead of expanding to fill the row. This lets the drag wrapper
/// in [_buildSpatialElement] handle long-press for repositioning without
/// conflicting with an inner long-press handler.
///
/// Ringing state heavily tints the liquid-glass surface red, adds a glow
/// halo, and plays a repeating bell-shake until the user taps to stop.
class AlarmPill extends StatefulWidget {
  final String title;
  final bool isRinging;

  /// Called (after a short press-pulse animation) when the user taps the
  /// pill in the idle state. Typically opens the device clock app.
  final VoidCallback? onTap;
  final VoidCallback onStop;

  /// When true the text column does not expand — the pill sizes itself to
  /// its content so the spatial-mode layout can auto-size.
  final bool compact;

  /// Wallpaper widget the lens refracts. Pass
  /// [WallpaperService.buildBackground].
  final Widget backgroundWidget;

  const AlarmPill({
    super.key,
    required this.title,
    required this.isRinging,
    this.onTap,
    required this.onStop,
    required this.backgroundWidget,
    this.compact = false,
  });

  @override
  State<AlarmPill> createState() => _AlarmPillState();
}

class _AlarmPillState extends State<AlarmPill>
    with TickerProviderStateMixin {
  static const double _height = 70.0;
  static const double _cornerRadius = 35.0;

  late final AnimationController _ringShake;
  late final AnimationController _pressController;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();

    _ringShake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _pressScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.14, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 55,
      ),
    ]).animate(_pressController);

    if (widget.isRinging) _ringShake.repeat();
  }

  @override
  void didUpdateWidget(covariant AlarmPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRinging && !_ringShake.isAnimating) {
      _ringShake.repeat();
    } else if (!widget.isRinging && _ringShake.isAnimating) {
      _ringShake.stop();
      _ringShake.value = 0;
    }
  }

  @override
  void dispose() {
    _ringShake.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _onTap() {
    _pressController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 162), () {
      if (mounted) widget.onTap?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.isRinging ? _buildRinging() : _buildIdle();
  }

  Widget _buildIdle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: ScaleTransition(
        scale: _pressScale,
        child: LiquidGlassSurface.foresight(
          backgroundWidget: widget.backgroundWidget,
          cornerRadius: _cornerRadius,
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Center(
            child: _buildContent(
              icon: Icons.alarm,
              iconColor: CASIColors.textPrimary,
              iconSize: 26,
              title: widget.title,
              titleColor: CASIColors.textPrimary,
              subtitle: 'Alarm',
              subtitleColor: CASIColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRinging() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStop,
      child: AnimatedBuilder(
        animation: _ringShake,
        builder: (context, child) {
          final angle = math.sin(_ringShake.value * math.pi * 6) * 0.09;
          return Transform.rotate(angle: angle, child: child);
        },
        // Glow halo sits behind the lens so the going-off color spills
        // beyond the pill edges. The lens itself is a red-tinted
        // LiquidGlass, not a flat fill, so refraction continues through
        // the alarm color.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_cornerRadius),
            boxShadow: [
              BoxShadow(
                color: CASIColors.alert.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
          child: LiquidGlassSurface.foresight(
            backgroundWidget: widget.backgroundWidget,
            cornerRadius: _cornerRadius,
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            tintOverride: CASIColors.alert.withValues(alpha: 0.72),
            borderOverride: Colors.white.withValues(alpha: 0.30),
            child: Center(
              child: _buildContent(
                icon: Icons.stop_rounded,
                iconColor: Colors.white,
                iconSize: 32,
                title: widget.title,
                titleColor: Colors.white,
                titleWeight: FontWeight.w700,
                subtitle: 'Tap to stop',
                subtitleColor: Colors.white.withValues(alpha: 0.9),
                subtitleWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent({
    required IconData icon,
    required Color iconColor,
    required double iconSize,
    required String title,
    required Color titleColor,
    FontWeight titleWeight = FontWeight.w600,
    required String subtitle,
    required Color subtitleColor,
    FontWeight subtitleWeight = FontWeight.w400,
  }) {
    final textColumn = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontSize: 14,
            fontWeight: titleWeight,
            height: 1.15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            color: subtitleColor,
            fontSize: 12,
            fontWeight: subtitleWeight,
            height: 1.2,
          ),
        ),
      ],
    );

    return Row(
      mainAxisSize: widget.compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
        ),
        const SizedBox(width: 12),
        widget.compact ? textColumn : Expanded(child: textColumn),
      ],
    );
  }
}
