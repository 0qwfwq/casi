import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// One entry in the timer pill deck. The pill renders the list as a stack
/// of cards (front card = lowest remaining time) and lets the user flip
/// through the deck with vertical swipes.
class TimerDeckEntry {
  /// Index into the parent's `_appTimers` list. Stable identity used to
  /// keep the user's selection pinned across re-sorts.
  final int timerIndex;
  final String timeText;
  final bool isRunning;
  final bool isRinging;

  const TimerDeckEntry({
    required this.timerIndex,
    required this.timeText,
    required this.isRunning,
    required this.isRinging,
  });
}

/// Timer deck pill shown above the music player on the home screen.
///
/// Multiple active timers render as a stacked deck (sorted lowest→highest
/// remaining time) similar to the notification pill. An "N/M" counter
/// appears on the front card when more than one timer is active.
///
/// Gestures:
/// - Tap: opens the clock app via [onTap].
/// - Swipe up: advance the deck forward (next higher time).
/// - Swipe down: advance the deck backward (next lower time).
/// - Swipe right-to-left on the front card: pause/resume that timer.
/// - Swipe left-to-right on the front card: stop+reset that timer.
/// - Tap (when any timer is ringing): stops ALL currently-ringing timers.
///
/// In spatial mode pass [compact] = true so the pill shrinks to its text
/// content instead of expanding to fill the row. Long-press is left free
/// for the spatial drag wrapper.
///
/// Liquid-glass treatment:
///   The front card is a [LiquidGlassSurface]. While the user swipes
///   horizontally, the lens *tint* is shifted toward the action color
///   (red for stop, pulse-blue for pause/resume) instead of painting an
///   opaque overlay on top.
class TimerPill extends StatefulWidget {
  final List<TimerDeckEntry> entries;
  final bool anyRinging;

  /// Called (after a short press-pulse animation) when the user taps the
  /// pill in the idle state. Typically opens the device clock app.
  final VoidCallback? onTap;
  final void Function(int timerIndex) onTogglePause;
  final void Function(int timerIndex) onStopSingle;
  final VoidCallback onStopAllRinging;

  /// When true the text column does not expand — the pill sizes itself to
  /// its content so the spatial-mode layout can auto-size.
  final bool compact;

  /// Wallpaper widget the lens refracts. Pass
  /// [WallpaperService.buildBackground].
  final Widget backgroundWidget;

  const TimerPill({
    super.key,
    required this.entries,
    required this.anyRinging,
    this.onTap,
    required this.onTogglePause,
    required this.onStopSingle,
    required this.onStopAllRinging,
    required this.backgroundWidget,
    this.compact = false,
  });

  @override
  State<TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends State<TimerPill> with TickerProviderStateMixin {
  static const double _horizActionThreshold = 80;
  static const double _horizMaxDrag = 150;
  static const double _vertCommitThreshold = 36.0;
  static const double _vertVelocityThreshold = 280.0;
  static const int _visibleBehind = 2;
  static const double _frontHeight = 70.0;
  static const double _cornerRadius = 35.0;

  int? _selectedTimerIndex;
  double _dragOffset = 0;
  double _settleFrom = 0;
  double _vertDragDy = 0;

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

    _syncSelectedIndex();
    if (widget.anyRinging) _ringShake.repeat();
  }

  void _syncSelectedIndex() {
    if (widget.entries.isEmpty) {
      _selectedTimerIndex = null;
      return;
    }
    final stillExists = _selectedTimerIndex != null &&
        widget.entries.any((e) => e.timerIndex == _selectedTimerIndex);
    if (!stillExists) {
      _selectedTimerIndex = widget.entries.first.timerIndex;
    }
  }

  @override
  void didUpdateWidget(covariant TimerPill oldWidget) {
    super.didUpdateWidget(oldWidget);

    _syncSelectedIndex();

    // When ringing just started, force the front to a ringing entry so
    // the user sees (and can stop) a timer that's going off rather than
    // whichever one they happened to be browsing.
    if (widget.anyRinging &&
        !oldWidget.anyRinging &&
        widget.entries.isNotEmpty) {
      final firstRinging = widget.entries.firstWhere(
        (e) => e.isRinging,
        orElse: () => widget.entries.first,
      );
      _selectedTimerIndex = firstRinging.timerIndex;
    }

    if (widget.anyRinging && !_ringShake.isAnimating) {
      _ringShake.repeat();
    } else if (!widget.anyRinging && _ringShake.isAnimating) {
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

  int _frontEntryIndex() {
    if (widget.entries.isEmpty || _selectedTimerIndex == null) return 0;
    final i = widget.entries
        .indexWhere((e) => e.timerIndex == _selectedTimerIndex);
    return i == -1 ? 0 : i;
  }

  void _cycleDeck(int delta) {
    if (widget.entries.length <= 1) return;
    setState(() {
      int next = _frontEntryIndex() + delta;
      next = next % widget.entries.length;
      if (next < 0) next += widget.entries.length;
      _selectedTimerIndex = widget.entries[next].timerIndex;
      _vertDragDy = 0;
    });
  }

  // --- Horizontal drag: pause/stop the front timer ---
  void _onHorizDragStart(DragStartDetails _) {
    _settleController.stop();
  }

  void _onHorizDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset =
          (_dragOffset + d.delta.dx).clamp(-_horizMaxDrag, _horizMaxDrag);
    });
  }

  void _onHorizDragEnd(DragEndDetails _) {
    if (widget.entries.isNotEmpty &&
        _dragOffset.abs() >= _horizActionThreshold) {
      final frontTimerIndex = widget.entries[_frontEntryIndex()].timerIndex;
      if (_dragOffset > 0) {
        widget.onStopSingle(frontTimerIndex);
      } else {
        widget.onTogglePause(frontTimerIndex);
      }
    }
    _settleFrom = _dragOffset;
    _settleController.forward(from: 0);
  }

  // --- Vertical drag: cycle the deck. Up = next, Down = previous. ---
  void _onVertDragUpdate(DragUpdateDetails d) {
    if (widget.entries.length <= 1) return;
    setState(() => _vertDragDy += d.delta.dy);
  }

  void _onVertDragEnd(DragEndDetails details) {
    if (widget.entries.length <= 1) {
      setState(() => _vertDragDy = 0);
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final committed = _vertDragDy.abs() >= _vertCommitThreshold ||
        velocity.abs() >= _vertVelocityThreshold;
    if (committed) {
      final swipingUp = (_vertDragDy < 0) || (velocity < 0);
      _cycleDeck(swipingUp ? 1 : -1);
    } else {
      setState(() => _vertDragDy = 0);
    }
  }

  void _onVertDragCancel() {
    setState(() => _vertDragDy = 0);
  }

  void _onTap() {
    _pressController.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 162), () {
      if (mounted) widget.onTap?.call();
    });
  }

  /// Computes the lens tint while the user is mid-horizontal-swipe. Returns
  /// null when the drag is small enough to leave the default glass tint
  /// in place; otherwise smoothly ramps the action color in from zero
  /// alpha so the lens transitions continuously rather than snapping into
  /// a colored overlay. Cap is intentionally low (~0.45) so the wallpaper
  /// still refracts visibly through the tint at full swipe — the pill
  /// reads as "the glass changed color", not "a colored sheet was placed
  /// on top of the glass".
  Color? _swipeTint(double absProgress, bool swipingRight) {
    if (absProgress < 0.02) return null;
    final Color action =
        swipingRight ? CASIColors.alert : CASIColors.confirm;
    final double alpha = (0.45 * absProgress).clamp(0.0, 0.45);
    return action.withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();

    final frontIndex = _frontEntryIndex();
    final frontEntry = widget.entries[frontIndex];
    final total = widget.entries.length;

    final int behindCount = (total - 1).clamp(0, _visibleBehind);
    // Keep the SizedBox fixed at _frontHeight so the front card's position
    // stays stable regardless of how many behind cards sit in the deck.
    // The Stack uses Clip.none so the smaller behind cards (narrower and
    // shorter, anchored by `bottom`) still render correctly.
    final double stackHeight = _frontHeight;

    // When any timer is ringing we show the red ringing treatment on the
    // front card. didUpdateWidget forces the front to a ringing entry on
    // ringing-start so the user sees a 00:00 timer here by default.
    final bool showRinging = widget.anyRinging;

    return SizedBox(
      height: stackHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < behindCount; i++)
            _BehindCard(depth: behindCount - i),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: showRinging
                ? _buildRinging(frontEntry)
                : _buildIdle(frontEntry, frontIndex, total),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(TimerDeckEntry entry, int frontIndex, int total) {
    final double rawProgress = _dragOffset / _horizActionThreshold;
    final double progress = rawProgress.clamp(-1.2, 1.2);
    final double absProgress = progress.abs().clamp(0.0, 1.0);
    final bool swipingRight = progress > 0;

    final liquidSurface = LiquidGlassSurface.foresight(
      backgroundWidget: widget.backgroundWidget,
      cornerRadius: _cornerRadius,
      height: _frontHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      tintOverride: _swipeTint(absProgress, swipingRight),
      child: Opacity(
        opacity: (1.0 - absProgress).clamp(0.0, 1.0),
        child: _buildIdleContent(entry, frontIndex, total),
      ),
    );

    final swipeOverlay = absProgress > 0.02
        ? Positioned.fill(
            child: IgnorePointer(
              child: _buildSwipeOverlay(entry, swipingRight, absProgress),
            ),
          )
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onHorizDragStart,
      onHorizontalDragUpdate: _onHorizDragUpdate,
      onHorizontalDragEnd: _onHorizDragEnd,
      onVerticalDragUpdate: _onVertDragUpdate,
      onVerticalDragEnd: _onVertDragEnd,
      onVerticalDragCancel: _onVertDragCancel,
      onTap: _onTap,
      child: ScaleTransition(
        scale: _pressScale,
        child: SizedBox(
          height: _frontHeight,
          child: widget.compact
              // Compact: LiquidGlassSurface is a non-positioned Stack child
              // so its content drives the Stack's width.
              ? Stack(
                  children: [
                    liquidSurface,
                    ?swipeOverlay,
                  ],
                )
              // Normal: fill the parent-constrained width via Positioned.fill.
              : Stack(
                  children: [
                    Positioned.fill(child: liquidSurface),
                    ?swipeOverlay,
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildIdleContent(
      TimerDeckEntry entry, int frontIndex, int total) {
    final String? indexLabel =
        total > 1 ? '${frontIndex + 1}/$total' : null;

    final textColumn = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.timeText,
              style: const TextStyle(
                color: CASIColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (indexLabel != null) ...[
              const SizedBox(width: 8),
              Text(
                indexLabel,
                style: const TextStyle(
                  color: CASIColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          entry.isRunning ? 'Timer' : 'Paused',
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
    );

    return Row(
      mainAxisSize: widget.compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Icon(
              entry.isRunning ? Icons.timer : Icons.timer_outlined,
              color: CASIColors.textPrimary,
              size: 26,
            ),
          ),
        ),
        const SizedBox(width: 12),
        widget.compact ? textColumn : Expanded(child: textColumn),
      ],
    );
  }

  Widget _buildSwipeOverlay(
      TimerDeckEntry entry, bool swipingRight, double progress) {
    final IconData icon = swipingRight
        ? Icons.stop_rounded
        : (entry.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded);
    final String label = swipingRight
        ? 'Stop'
        : (entry.isRunning ? 'Pause' : 'Resume');

    return Padding(
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

  Widget _buildRinging(TimerDeckEntry entry) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStopAllRinging,
      child: AnimatedBuilder(
        animation: _ringShake,
        builder: (context, child) {
          final angle = math.sin(_ringShake.value * math.pi * 6) * 0.09;
          return Transform.rotate(angle: angle, child: child);
        },
        // Glow halo behind the lens — same treatment as [AlarmPill] so
        // the going-off cue is consistent.
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
            height: _frontHeight,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            tintOverride: CASIColors.alert.withValues(alpha: 0.72),
            borderOverride: Colors.white.withValues(alpha: 0.30),
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
                        entry.timeText,
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
      ),
    );
  }
}

/// Decorative stack-hint card behind the front card. Intentionally uses
/// the lighter [GlassSurface] (flat blur) instead of [LiquidGlassSurface]:
/// each liquid lens captures the wallpaper into its own texture and runs
/// a shader, and a 3-deep deck of those would multiply that cost for a
/// surface the user can't even read. The front card — which the user
/// actually interacts with — gets the full liquid material.
class _BehindCard extends StatelessWidget {
  final int depth;
  const _BehindCard({required this.depth});

  @override
  Widget build(BuildContext context) {
    final double horizontalInset = 14.0 * depth;
    final double verticalShift = 6.0 * depth;
    final double opacity = (1.0 - 0.28 * depth).clamp(0.25, 1.0);

    return Positioned(
      left: horizontalInset,
      right: horizontalInset,
      bottom: verticalShift,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: GlassSurface.foresight(
            cornerRadius: 35.0,
            height: 70.0 - 6.0 * depth,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
