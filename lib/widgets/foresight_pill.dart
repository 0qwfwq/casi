import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/services/foresight_service.dart';
import 'package:casi/widgets/press_pulse.dart';

/// The Foresight dock — a pill row of app icons configured by the user
/// via schedule and scenario rules in settings.
///
/// Up to [maxForesight] icons are shown at once. When more apps are active
/// the pill stays the same physical width and becomes horizontally scrollable.
class ForesightPill extends StatelessWidget {
  /// Number of icons visible at once. When predictions exceed this the pill
  /// scrolls rather than growing.
  final int maxForesight;

  final List<ForesightPrediction> predictions;
  final void Function(String packageName) onAppTap;

  /// Long-press anywhere on the foresight dock fires this callback.
  final VoidCallback? onLongPress;

  /// Wallpaper widget the lens refracts. Pass
  /// [WallpaperService.buildBackground]; the dock can't render its
  /// liquid-glass material without it.
  final Widget backgroundWidget;

  const ForesightPill({
    super.key,
    required this.predictions,
    required this.onAppTap,
    required this.backgroundWidget,
    this.maxForesight = 6,
    this.onLongPress,
  });

  static const double _iconSize = 34.0;
  static const double _iconGap = 16.0;

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) return const SizedBox.shrink();

    final bool needsScroll = predictions.length > maxForesight;

    final iconChildren = <Widget>[
      for (int i = 0; i < predictions.length; i++) ...[
        if (i > 0) const SizedBox(width: _iconGap),
        GestureDetector(
          onTap: () => onAppTap(predictions[i].packageName),
          behavior: HitTestBehavior.opaque,
          child: _buildPredictionIcon(predictions[i]),
        ),
      ],
    ];

    Widget content;
    if (needsScroll) {
      // Fixed width = exactly maxForesight icons so the pill never grows.
      final double fixedWidth =
          maxForesight * _iconSize + (maxForesight - 1) * _iconGap;
      content = SizedBox(
        width: fixedWidth,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: iconChildren,
          ),
        ),
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: iconChildren,
      );
    }

    return PressPulse(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: LiquidGlassSurface.foresight(
        backgroundWidget: backgroundWidget,
        cornerRadius: CASILiquidGlass.cornerPill,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: content,
      ),
    );
  }

  Widget _buildPredictionIcon(ForesightPrediction prediction) {
    const double size = 34;
    final hasIcon = prediction.icon != null && prediction.icon!.isNotEmpty;
    return hasIcon
        ? Image.memory(
            prediction.icon!,
            width: size,
            height: size,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Icon(
              Icons.android,
              color: CASIColors.textPrimary,
              size: size,
            ),
          )
        : const Icon(
            Icons.android,
            color: CASIColors.textPrimary,
            size: size,
          );
  }
}
