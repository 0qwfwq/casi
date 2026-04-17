import 'package:flutter/material.dart';

/// Wraps [child] with a tactile scale "pulse" animation that plays
/// before firing the primary action. The child grows briefly, then
/// snaps back to resting scale as the action commits — so a tap (or
/// long-press) feels like a physical press rather than an instant
/// jump.
///
/// Routing rules:
/// - If [onLongPress] is provided, the pulse plays on long-press and
///   [onTap] (if any) passes through without animation.
/// - Otherwise the pulse plays on tap.
class PressPulse extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior behavior;

  /// Peak scale reached during the pulse.
  final double peakScale;

  /// Total duration of the grow → shrink pulse.
  final Duration duration;

  /// Portion of [duration] spent growing (the rest is the shrink).
  /// 0.45 keeps the peak slightly before the midpoint so the action
  /// fires while the dock is visibly "lifted".
  final double growFraction;

  const PressPulse({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior = HitTestBehavior.opaque,
    this.peakScale = 1.14,
    this.duration = const Duration(milliseconds: 360),
    this.growFraction = 0.45,
  });

  @override
  State<PressPulse> createState() => _PressPulseState();
}

class _PressPulseState extends State<PressPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scale = _buildScale();
  }

  @override
  void didUpdateWidget(covariant PressPulse old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) _controller.duration = widget.duration;
    if (old.peakScale != widget.peakScale ||
        old.growFraction != widget.growFraction) {
      _scale = _buildScale();
    }
  }

  Animation<double> _buildScale() {
    final growWeight = (widget.growFraction * 100).clamp(1.0, 99.0);
    final shrinkWeight = 100.0 - growWeight;
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: widget.peakScale)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: growWeight,
      ),
      TweenSequenceItem(
        tween: Tween(begin: widget.peakScale, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: shrinkWeight,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pulseThenFire(VoidCallback? cb) {
    _controller.forward(from: 0.0);
    // Fire at the peak so the shrink half overlaps with the action
    // (app launch, panel open) — keeps the UI responsive.
    final peakDelay = Duration(
      milliseconds: (widget.duration.inMilliseconds * widget.growFraction).round(),
    );
    Future.delayed(peakDelay, () {
      if (mounted) cb?.call();
    });
  }

  void _handleTap() {
    if (widget.onLongPress != null) {
      // Long-press owns the pulse; a plain tap stays quiet.
      widget.onTap?.call();
    } else {
      _pulseThenFire(widget.onTap);
    }
  }

  void _handleLongPress() {
    _pulseThenFire(widget.onLongPress);
  }

  @override
  Widget build(BuildContext context) {
    final hasTap = widget.onTap != null;
    final hasLongPress = widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: hasTap ? _handleTap : null,
      onLongPress: hasLongPress ? _handleLongPress : null,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
