import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// Timer schedule pill shown above the music player on the home screen.
///
/// Gestures:
/// - Long-press: plays a grow/shrink press-pulse, then opens the timer panel.
/// - Swipe right-to-left: pause (or resume, if paused). Pill reveals a blue
///   overlay + pause/play icon under the finger without changing size.
/// - Swipe left-to-right: stop + reset + remove. Red overlay + stop icon.
/// - Tap: nothing while idle; when the timer is ringing, tap stops + resets.
///
/// Ringing state turns the whole pill red and plays a repeating bell-shake
/// rotation until the user taps to stop.
class TimerPill extends StatefulWidget {
  final String timeText;
  final bool isRunning;
  final bool isRinging;
  final VoidCallback onLongPressOpen;
  final VoidCallback onTogglePause;
  final VoidCallback onStop;

  const TimerPill({
    super.key,
    required this.timeText,
    required this.isRunning,
    required this.isRinging,
    required this.onLongPressOpen,
    required this.onTogglePause,
    required this.onStop,
  });

  @override
  State<TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<TimerPill> with TickerProviderStateMixin {
  static const double _actionThreshold = 80;
  static const double _maxDrag = 150;

  double _dragOffset = 0; // +right (stop), -left (pause/resume)
  double _settleFrom = 0;

  late final AnimationController _settleController;
  late final AnimationController _ringShake;
  late final AnimationController _pressController;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();

    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        setState(() {
          final t = Curves.easeOutCubic.transform(_settleController.value);
          _dragOffset = _settleFrom * (1 - t);
        });
      });

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
  void didUpdateWidget(covariant TimerPill oldWidget) {
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
    _settleController.dispose();
    _ringShake.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _settleController.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset = (_dragOffset + d.delta.dx).clamp(-_maxDrag, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (_dragOffset.abs() >= _actionThreshold) {
      if (_dragOffset > 0) {
        widget.onStop();
      } else {
        widget.onTogglePause();
      }
    }
    _settleFrom = _dragOffset;
    _settleController.forward(from: 0);
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
    final double rawProgress = _dragOffset / _actionThreshold;
    final double progress = rawProgress.clamp(-1.2, 1.2);
    final double absProgress = progress.abs().clamp(0.0, 1.0);
    final bool swipingRight = progress > 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onLongPress: _onLongPress,
      child: ScaleTransition(
        scale: _pressScale,
        child: SizedBox(
          height: 70,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(35),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GlassSurface.foresight(
                    cornerRadius: 35.0,
                    height: 70.0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: _buildIdleContent(),
                  ),
                ),
                if (absProgress > 0.02)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _buildSwipeOverlay(swipingRight, absProgress),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdleContent() {
    return Row(
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Icon(
              widget.isRunning ? Icons.timer : Icons.timer_outlined,
              color: CASIColors.textPrimary,
              size: 26,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.timeText,
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
              Text(
                widget.isRunning ? 'Timer' : 'Paused',
                style: const TextStyle(
                  color: CASIColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwipeOverlay(bool swipingRight, double progress) {
    final Color actionColor =
        swipingRight ? CASIColors.alert : CASIColors.pulseBlue;
    final IconData icon = swipingRight
        ? Icons.stop_rounded
        : (widget.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded);
    final String label = swipingRight
        ? 'Stop'
        : (widget.isRunning ? 'Pause' : 'Resume');

    final double fillOpacity = (0.9 * progress).clamp(0.0, 0.95);

    return Container(
      color: actionColor.withValues(alpha: fillOpacity),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Align(
        alignment: swipingRight ? Alignment.centerLeft : Alignment.centerRight,
        child: Opacity(
          opacity: progress,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: swipingRight
                ? [
                    Icon(icon, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ]
                : [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                    const SizedBox(width: 10),
                    Icon(icon, color: Colors.white, size: 28),
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
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: Icon(Icons.stop_rounded, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.timeText,
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
