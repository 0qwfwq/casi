import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/services/foresight_service.dart';
import 'package:casi/services/notification_pill_service.dart';

/// Glassy pill that displays Foresight's app predictions flanked by up to 2
/// notification pill badges. The foresight chip row stays dead-center
/// regardless of how many notification pills are visible; #1 priority sits
/// to its right and #2 sits to its left.
class ForesightPill extends StatelessWidget {
  final List<ForesightPrediction> predictions;
  final void Function(String packageName) onAppTap;
  final List<NotificationPillEntry> notificationApps;
  final void Function(String packageName)? onNotificationTap;

  const ForesightPill({
    super.key,
    required this.predictions,
    required this.onAppTap,
    this.notificationApps = const [],
    this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasNotifs = notificationApps.isNotEmpty;
    if (predictions.isEmpty && !hasNotifs) return const SizedBox.shrink();

    // Split notification apps: #2 (index 1) on the left, #1 (index 0) on the right
    final NotificationPillEntry? leftNotif =
        notificationApps.length >= 2 ? notificationApps[1] : null;
    final NotificationPillEntry? rightNotif =
        notificationApps.isNotEmpty ? notificationApps[0] : null;

    // If no notifications, just center the foresight pill directly
    if (!hasNotifs) {
      return Center(child: _buildForesightChips());
    }

    // Use a Row with balanced spacers so the foresight pill stays centered.
    // Each side gets an Expanded that holds (or doesn't hold) a notification
    // pill. Because both Expanded widgets have equal flex, the center child
    // stays exactly in the middle.
    return Row(
      children: [
        // Left side — fills equally with right
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (leftNotif != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _NotificationPillBadge(
                    key: ValueKey('notif_pill_left_${leftNotif.packageName}'),
                    entry: leftNotif,
                    onTap: () => _handleNotifTap(leftNotif.packageName),
                  ),
                ),
            ],
          ),
        ),

        // Center — foresight chips (never shifts)
        _buildForesightChips(),

        // Right side — fills equally with left
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (rightNotif != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: _NotificationPillBadge(
                    key: ValueKey('notif_pill_right_${rightNotif.packageName}'),
                    entry: rightNotif,
                    onTap: () => _handleNotifTap(rightNotif.packageName),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildForesightChips() {
    if (predictions.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
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
                  child: _buildPredictionIcon(predictions[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleNotifTap(String packageName) {
    if (onNotificationTap != null) {
      onNotificationTap!(packageName);
    } else {
      onAppTap(packageName);
    }
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

/// A single circular notification pill badge with frosted glass background.
class _NotificationPillBadge extends StatefulWidget {
  final NotificationPillEntry entry;
  final VoidCallback onTap;

  const _NotificationPillBadge({
    super.key,
    required this.entry,
    required this.onTap,
  });

  @override
  State<_NotificationPillBadge> createState() => _NotificationPillBadgeState();
}

class _NotificationPillBadgeState extends State<_NotificationPillBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: CASIMotion.standard,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double pillSize = 54;
    const double iconSize = 34;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(pillSize / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: CASIGlass.blurStandard,
              sigmaY: CASIGlass.blurStandard,
            ),
            child: Container(
              width: pillSize,
              height: pillSize,
              decoration: BoxDecoration(
                color: Colors.white
                    .withValues(alpha: CASIElevation.card.bgAlpha),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white
                      .withValues(alpha: CASIElevation.card.borderAlpha),
                ),
              ),
              child: Center(
                child: _buildNotifIcon(iconSize),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotifIcon(double size) {
    final hasIcon =
        widget.entry.icon != null && widget.entry.icon!.isNotEmpty;
    return hasIcon
        ? ClipRRect(
            borderRadius: BorderRadius.circular(size / 4),
            child: Image.memory(
              widget.entry.icon!,
              width: size,
              height: size,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Icon(
                Icons.notifications_active_rounded,
                color: CASIColors.textPrimary,
                size: size,
              ),
            ),
          )
        : Icon(
            Icons.notifications_active_rounded,
            color: CASIColors.textPrimary,
            size: size,
          );
  }
}
