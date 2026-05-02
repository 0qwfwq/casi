import 'dart:async';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

class ClockCapsule extends StatefulWidget {
  final double opacity;

  /// Whether to render the time digits. When false, the clock collapses
  /// to zero height so pills and widgets below the capsule shift up into
  /// the freed space.
  final bool showClock;

  /// Whether to render the date label. When false the date glyphs are
  /// hidden but the date slot keeps its full reserved height — nothing
  /// below the capsule is ever allowed to drift up into where the date
  /// sits on screen.
  final bool showDate;

  /// Wallpaper the liquid-glass clock and date pill refract.
  final Widget backgroundWidget;

  const ClockCapsule({
    super.key,
    this.opacity = 1.0,
    this.showClock = true,
    this.showDate = true,
    required this.backgroundWidget,
  });

  /// Always-reserved vertical band for the date row.
  static const double dateSlotHeight = 36.0;

  /// Fraction of the available screen height reclaimed by the clock
  /// digits when [showClock] is true.
  static const double clockHeightFraction = 0.17;

  @override
  State<ClockCapsule> createState() => _ClockCapsuleState();
}

class _ClockCapsuleState extends State<ClockCapsule> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _getFormattedDate() {
    const List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const List<String> months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[_now.weekday - 1]} ${months[_now.month - 1]} ${_now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final int hour =
        _now.hour == 0 || _now.hour == 12 ? 12 : _now.hour % 12;
    final String hourText = hour.toString().padLeft(2, '0');
    final String minuteText = _now.minute.toString().padLeft(2, '0');
    final double screenHeight = MediaQuery.of(context).size.height;

    final dateStyle = CASITypography.body1.copyWith(
      color: Colors.white.withValues(alpha: 0.95),
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. Date slot — liquid glass pill (display only, not interactive).
        SizedBox(
          height: ClockCapsule.dateSlotHeight,
          child: Center(
            child: AnimatedOpacity(
              duration: CASIMotion.standard,
              opacity: widget.showDate ? 1.0 : 0.0,
              child: LiquidGlassSurface.pill(
                backgroundWidget: widget.backgroundWidget,
                cornerRadius: 14,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 5),
                child: Text(_getFormattedDate(), style: dateStyle),
              ),
            ),
          ),
        ),

        // 2. Clock bubble pills — collapse entirely when hidden.
        AnimatedSize(
          duration: CASIMotion.standard,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: widget.showClock
              ? SizedBox(
                  height: screenHeight * ClockCapsule.clockHeightFraction,
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: CASISpacing.lg, vertical: 4),
                    child: Center(
                      child: _ClockPills(
                        hourText: hourText,
                        minuteText: minuteText,
                        backgroundWidget: widget.backgroundWidget,
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// Two liquid-glass bubble pills (hour | minute) with a two-dot colon
/// between them. Each pill refracts the wallpaper behind it and renders
/// the digit text with a vertical alpha-gradient sheen.
class _ClockPills extends StatelessWidget {
  final String hourText;
  final String minuteText;
  final Widget backgroundWidget;

  const _ClockPills({
    required this.hourText,
    required this.minuteText,
    required this.backgroundWidget,
  });

  Widget _digitText(String text, double fontSize) {
    const TextStyle base = TextStyle(
      fontFamily: CASITypography.fontFamily,
      fontWeight: FontWeight.w200,
      height: 1.0,
      letterSpacing: -3.0,
      color: Colors.white,
    );
    // Drop-shadow layer behind the gradient body for legibility on any
    // wallpaper, same approach as the old single-text implementation.
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: base.copyWith(
            fontSize: fontSize,
            color: Colors.transparent,
            shadows: [
              Shadow(
                offset: const Offset(0, 6),
                blurRadius: 20,
                color: Colors.black.withValues(alpha: 0.28),
              ),
            ],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.96),
              Colors.white.withValues(alpha: 0.58),
              Colors.white.withValues(alpha: 0.90),
            ],
            stops: const [0.0, 0.52, 1.0],
          ).createShader(bounds),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: base.copyWith(fontSize: fontSize),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 120.0;
        final double cornerRadius = h * 0.23; // bubbly rounded rect
        final double pillWidth = h * 0.82;
        final double fontSize = h * 0.58;
        final double dotSize = h * 0.068;
        final double dotGap = h * 0.13;
        final double sideGap = h * 0.065;

        Widget dot() => Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            );

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Hour pill
            LiquidGlassSurface.foresight(
              backgroundWidget: backgroundWidget,
              cornerRadius: cornerRadius,
              width: pillWidth,
              height: h,
              child: Center(child: _digitText(hourText, fontSize)),
            ),
            SizedBox(width: sideGap),
            // Two-dot colon
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                dot(),
                SizedBox(height: dotGap),
                dot(),
              ],
            ),
            SizedBox(width: sideGap),
            // Minute pill
            LiquidGlassSurface.foresight(
              backgroundWidget: backgroundWidget,
              cornerRadius: cornerRadius,
              width: pillWidth,
              height: h,
              child: Center(child: _digitText(minuteText, fontSize)),
            ),
          ],
        );
      },
    );
  }
}
