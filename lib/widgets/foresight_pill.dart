import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/services/foresight_service.dart';
import 'package:casi/widgets/press_pulse.dart';

/// The Foresight dock — a pill row of up to 6 predicted app icons that
/// sits just above the main dock.
///
/// The number shown is automatic (driven by context scoring and user rules)
/// with a hard maximum of 6. Tapping an icon opens that app. Long-pressing
/// anywhere on the pill launches the user's configured "long-press" app
/// (default: the system browser) via [PressPulse].
class ForesightPill extends StatelessWidget {
  /// Hard ceiling on icons rendered. Predictions are already filtered to ≤6
  /// before reaching this widget; this cap is a safety backstop.
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

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) return const SizedBox.shrink();

    final int count = predictions.length < maxForesight
        ? predictions.length
        : maxForesight;

    return PressPulse(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: LiquidGlassSurface.foresight(
        backgroundWidget: backgroundWidget,
        cornerRadius: CASILiquidGlass.cornerPill,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              GestureDetector(
                onTap: () => onAppTap(predictions[i].packageName),
                behavior: HitTestBehavior.opaque,
                child: _buildPredictionIcon(predictions[i]),
              ),
            ],
          ],
        ),
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
