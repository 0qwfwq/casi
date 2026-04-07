import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/services/foresight_service.dart';
import 'package:casi/services/notification_pill_service.dart';

/// The Foresight dock + notification pills.
///
/// Layout:
///   ┌──────────── 2 "half-big" notification pills ───────────┐
///   │  [ #2 notif ]              [ #1 notif ]               │
///   └───────────────────────────────────────────────────────┘
///   ┌───────────── 5 foresight app chips ───────────────────┐
///   │   [ A ]  [ B ]  [ C ]  [ D ]  [ E ]                    │
///   └───────────────────────────────────────────────────────┘
///
/// The foresight chip row ALWAYS displays 5 app icons (the caller has
/// already deduped against any notification apps). Above it sits a
/// row of up to two "half-big" pills — each roughly half the width of
/// the music player so a pair of them feel like an extension of the
/// dock below. Pills animate in/out cooperatively with the dock.
class ForesightPill extends StatelessWidget {
  /// Max foresight apps rendered in the dock row.
  static const int _maxForesight = 5;

  final List<ForesightPrediction> predictions;
  final void Function(String packageName) onAppTap;
  final List<NotificationPillEntry> notificationApps;
  final void Function(String packageName)? onNotificationTap;

  /// Long-press anywhere on the foresight dock (chips or whitespace
  /// between them) fires this callback. Used by the home screen to
  /// launch the user's chosen "long-press" app (default: browser).
  final VoidCallback? onLongPress;

  const ForesightPill({
    super.key,
    required this.predictions,
    required this.onAppTap,
    this.notificationApps = const [],
    this.onNotificationTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasNotifs = notificationApps.isNotEmpty;
    if (predictions.isEmpty && !hasNotifs) return const SizedBox.shrink();

    // #1 priority on the right, #2 on the left (matches the order the
    // rest of the UI uses — most important pill closest to the thumb).
    final NotificationPillEntry? leftNotif =
        notificationApps.length >= 2 ? notificationApps[1] : null;
    final NotificationPillEntry? rightNotif =
        notificationApps.isNotEmpty ? notificationApps[0] : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated notification pill row above the dock. AnimatedSize
        // collapses smoothly when there are no notifications so the
        // dock slides up/down as pills appear and disappear.
        AnimatedSize(
          duration: CASIMotion.standard,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: hasNotifs
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _NotificationPillRow(
                    left: leftNotif,
                    right: rightNotif,
                    onTap: _handleNotifTap,
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
        // Foresight dock chip row.
        _buildForesightChips(),
      ],
    );
  }

  Widget _buildForesightChips() {
    if (predictions.isEmpty) return const SizedBox.shrink();

    final int count = predictions.length < _maxForesight
        ? predictions.length
        : _maxForesight;

    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
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
                for (int i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => onAppTap(predictions[i].packageName),
                    onLongPress: onLongPress,
                    behavior: HitTestBehavior.opaque,
                    child: _buildPredictionIcon(predictions[i]),
                  ),
                ],
              ],
            ),
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

// ─── Notification Pill Row ──────────────────────────────────────────────────
//
// A centered row of up to two "half-big" notification pills that sits
// above the Foresight dock. Each pill is roughly half the width of the
// music player so two of them visually match one music-player-sized
// pill. When only one notification is present it's centered beneath
// where the pair would have sat so the animation feels balanced.

class _NotificationPillRow extends StatelessWidget {
  final NotificationPillEntry? left;
  final NotificationPillEntry? right;
  final void Function(String packageName) onTap;

  const _NotificationPillRow({
    required this.left,
    required this.right,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Match the music player's horizontal inset so the pill row feels
    // anchored to the same rail.
    const double horizontalMargin = 40.0;
    const double gap = 10.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double full = constraints.maxWidth;
          final double halfWidth = (full - gap) / 2;

          return SizedBox(
            width: full,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Left slot — uses AnimatedSwitcher so a new pill
                // fades/slides in smoothly when a notification arrives.
                SizedBox(
                  width: halfWidth,
                  child: _AnimatedSlot(
                    entry: left,
                    alignment: Alignment.centerRight,
                    onTap: onTap,
                  ),
                ),
                const SizedBox(width: gap),
                SizedBox(
                  width: halfWidth,
                  child: _AnimatedSlot(
                    entry: right,
                    alignment: Alignment.centerLeft,
                    onTap: onTap,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A single pill slot that animates its entry/exit. The slot itself
/// always takes the same amount of horizontal space, so when one of
/// the two pills is missing the other stays put instead of
/// re-centering — that makes the row feel stable as notifications
/// come and go.
class _AnimatedSlot extends StatelessWidget {
  final NotificationPillEntry? entry;
  final AlignmentGeometry alignment;
  final void Function(String packageName) onTap;

  const _AnimatedSlot({
    required this.entry,
    required this.alignment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: CASIMotion.standard,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
              child: child,
            ),
          ),
        );
      },
      child: entry == null
          ? const SizedBox.shrink(key: ValueKey('empty_slot'))
          : Align(
              key: ValueKey('notif_slot_${entry!.packageName}'),
              alignment: alignment,
              child: _NotificationHalfPill(
                entry: entry!,
                onTap: () => onTap(entry!.packageName),
              ),
            ),
    );
  }
}

/// "Half-big" frosted pill containing a notification app icon and
/// its short label. Designed to roughly match the music player's
/// pill aesthetic at half the width.
class _NotificationHalfPill extends StatelessWidget {
  final NotificationPillEntry entry;
  final VoidCallback onTap;

  const _NotificationHalfPill({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const double pillHeight = 54;
    const double iconSize = 34;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(pillHeight / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: CASIGlass.blurStandard,
            sigmaY: CASIGlass.blurStandard,
          ),
          child: Container(
            height: pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:
                  Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
              borderRadius: BorderRadius.circular(pillHeight / 2),
              border: Border.all(
                color: Colors.white
                    .withValues(alpha: CASIElevation.card.borderAlpha),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildNotifIcon(iconSize),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    entry.appName,
                    style: const TextStyle(
                      color: CASIColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotifIcon(double size) {
    final hasIcon = entry.icon != null && entry.icon!.isNotEmpty;
    return hasIcon
        ? ClipRRect(
            borderRadius: BorderRadius.circular(size / 4),
            child: Image.memory(
              entry.icon!,
              width: size,
              height: size,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Icon(
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
