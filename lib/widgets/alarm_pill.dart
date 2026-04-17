import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// Alarm schedule pill shown above the music player on the home screen.
///
/// Gestures:
/// - Long-press (idle): plays a grow/shrink press-pulse, then opens the
///   alarm panel.
/// - Tap (idle): nothing.
/// - Tap (ringing): stops the alarm.
///
/// Ringing state turns the whole pill red and plays a repeating bell-shake
/// rotation until the user taps to stop.
class AlarmPill extends StatefulWidget {
  final String title;
  final bool isRinging;
  final VoidCallback onLongPressOpen;
  final VoidCallback onStop;

  const AlarmPill({
    super.key,
    required this.title,
    required this.isRinging,
    required this.onLongPressOpen,
    required this.onStop,
  });

  @override
  State<AlarmPill> createState() => _AlarmPillState();
}

class _AlarmPillState extends State<AlarmPill>
    with TickerProviderStateMixin {
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

  void _onLongPress() {
    _pressController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 162), () {
      if (mounted) widget.onLongPressOpen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.isRinging ? _buildRinging() : _buildIdle();
  }

  Widget _buildIdle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _onLongPress,
      child: ScaleTransition(
        scale: _pressScale,
        child: GlassSurface.foresight(
          cornerRadius: 35.0,
          height: 70.0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child:
                      Icon(Icons.alarm, color: CASIColors.textPrimary, size: 26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: CASIColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Alarm',
                      style: TextStyle(
                        color: CASIColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: CASIColors.alert,
            borderRadius: BorderRadius.circular(35),
            boxShadow: [
              BoxShadow(
                color: CASIColors.alert.withValues(alpha: 0.5),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.25), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: Icon(Icons.stop_rounded,
                      color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to stop',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
