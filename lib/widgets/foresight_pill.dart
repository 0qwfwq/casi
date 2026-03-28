import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/services/foresight_service.dart';

/// Glassy pill that displays Foresight's three app predictions.
/// Centered above the dock, unobtrusive, immediately actionable.
class ForesightPill extends StatelessWidget {
  final List<ForesightPrediction> predictions;
  final void Function(String packageName) onAppTap;

  const ForesightPill({
    super.key,
    required this.predictions,
    required this.onAppTap,
  });

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) return const SizedBox.shrink();

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CASIGlass.cornerPill),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: CASIGlass.blurStandard,
            sigmaY: CASIGlass.blurStandard,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
              borderRadius: BorderRadius.circular(CASIGlass.cornerPill),
              border: Border.all(
                color: Colors.white
                    .withValues(alpha: CASIElevation.card.borderAlpha),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < predictions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => onAppTap(predictions[i].packageName),
                    behavior: HitTestBehavior.opaque,
                    child: _buildIcon(predictions[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ForesightPrediction prediction) {
    const double size = 34;
    final hasIcon = prediction.icon != null && prediction.icon!.isNotEmpty;
    return hasIcon
        ? Image.memory(
            prediction.icon!,
            width: size,
            height: size,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Icon(
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
