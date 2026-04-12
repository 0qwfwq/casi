import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/services/foresight_service.dart';
import 'package:casi/services/notification_pill_service.dart';

/// The Foresight dock + notification stack pill.
///
/// Layout:
///   ┌────────── notification stack pill (single card) ──────┐
///   │  [icon]  Sender                                        │
///   │          message preview text…                         │
///   └───────────────────────────────────────────────────────┘
///   ┌───────────── 1–7 foresight app chips ──────────────────┐
///   │   [ A ]  [ B ]  [ C ]  [ D ]  [ E ]                    │
///   └───────────────────────────────────────────────────────┘
///
/// The foresight chip row displays up to [maxForesight] app icons
/// (configurable 1–7 via settings, default 5). The caller has
/// already deduped against any notification apps. Above it sits a
/// single "stacked" notification pill that matches the music player's
/// width and feels like a natural extension of the dock below.
///
/// The stack shows the most-important notification on top with the
/// remaining notifications visually layered behind it. Tapping the
/// front card opens its app. Swiping right cycles forward through the
/// stack (1 → 2 → 3 → … → wrap to 1); swiping left cycles backward.
class ForesightPill extends StatelessWidget {
  /// Max foresight apps rendered in the dock row.
  /// Configurable via settings (1–7); falls back to 5.
  final int maxForesight;

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
    this.maxForesight = 5,
    this.notificationApps = const [],
    this.onNotificationTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasNotifs = notificationApps.isNotEmpty;
    if (predictions.isEmpty && !hasNotifs) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Animated notification stack pill above the dock. AnimatedSize
        // collapses smoothly when there are no notifications so the
        // dock slides up/down as pills appear and disappear.
        AnimatedSize(
          duration: CASIMotion.standard,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: hasNotifs
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _NotificationStackPill(
                    entries: notificationApps,
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

    final int count = predictions.length < maxForesight
        ? predictions.length
        : maxForesight;

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

// ─── Notification Stack Pill ────────────────────────────────────────────────
//
// A single music-player-width pill that sits above the Foresight dock
// and shows the user's most-important active notification on top. The
// remaining notifications are visually layered behind it like a deck
// of cards. Swiping right cycles forward (1 → 2 → 3 → … → wrap to 1);
// swiping left cycles backward. Tapping the front card opens its app.

/// Horizontal margin around the stack pill — matches `SongPlayer`'s
/// margin so the pill aligns to the same rail as the music player.
const double _kStackHorizontalMargin = 40.0;

/// Front-card height. Sized to fit a sender line + a single body
/// preview line comfortably.
const double _kStackPillHeight = 64.0;

/// How many cards behind the front are visible as decorative
/// "depth" layers (each progressively smaller and dimmer).
const int _kStackVisibleBehind = 2;

/// Horizontal drag distance (px) past which a swipe is committed.
const double _kSwipeCommitThreshold = 48.0;

/// Horizontal velocity (px/s) past which a flick is committed even
/// without crossing the distance threshold.
const double _kSwipeVelocityThreshold = 320.0;

class _NotificationStackPill extends StatefulWidget {
  final List<NotificationPillEntry> entries;
  final void Function(String packageName) onTap;

  const _NotificationStackPill({
    required this.entries,
    required this.onTap,
  });

  @override
  State<_NotificationStackPill> createState() => _NotificationStackPillState();
}

class _NotificationStackPillState extends State<_NotificationStackPill> {
  /// Index of the notification currently shown on the front of the
  /// stack. 0 = most important.
  int _index = 0;

  /// Direction of the most recent swipe — drives the slide animation
  /// of the [AnimatedSwitcher] inside the front card. +1 = forward
  /// (next), -1 = backward (previous).
  int _direction = 1;

  /// Live horizontal drag offset for the front card. Resets to 0 on
  /// drag end.
  double _dragDx = 0.0;

  @override
  void didUpdateWidget(covariant _NotificationStackPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the visible index in range when notifications come and go.
    if (widget.entries.isEmpty) {
      _index = 0;
    } else if (_index >= widget.entries.length) {
      _index = _index % widget.entries.length;
    }
  }

  void _cycle(int delta) {
    if (widget.entries.length <= 1) return;
    setState(() {
      _direction = delta >= 0 ? 1 : -1;
      _index = (_index + delta) % widget.entries.length;
      if (_index < 0) _index += widget.entries.length;
      _dragDx = 0.0;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (widget.entries.length <= 1) return;
    setState(() {
      _dragDx += details.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (widget.entries.length <= 1) {
      setState(() => _dragDx = 0.0);
      return;
    }
    final velocity = details.primaryVelocity ?? 0.0;
    final committed = _dragDx.abs() >= _kSwipeCommitThreshold ||
        velocity.abs() >= _kSwipeVelocityThreshold;

    if (committed) {
      // Swipe right (positive dx / positive velocity) → next
      // notification. Swipe left → previous.
      final goingForward = (_dragDx > 0) || (velocity > 0);
      _cycle(goingForward ? 1 : -1);
    } else {
      setState(() => _dragDx = 0.0);
    }
  }

  void _onHorizontalDragCancel() {
    setState(() => _dragDx = 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();

    final entries = widget.entries;
    final total = entries.length;
    final safeIndex = total == 0 ? 0 : _index % total;
    final current = entries[safeIndex];

    // Build a list of "behind" entries to render as decorative depth
    // layers. We render at most [_kStackVisibleBehind] of them, and
    // skip rendering anything if the stack only has the front card.
    final int behindCount =
        (total - 1).clamp(0, _kStackVisibleBehind).toInt();
    final behindEntries = <NotificationPillEntry>[];
    for (int offset = behindCount; offset >= 1; offset--) {
      // Walk forward through the cycle so the *next* notifications
      // peek out behind the current one.
      final i = (safeIndex + offset) % total;
      behindEntries.add(entries[i]);
    }

    // Reserve enough vertical space for the front card AND the
    // visible "behind" cards so the dock doesn't visually clip them.
    final double stackHeight =
        _kStackPillHeight + behindCount * _kBehindVerticalGap;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kStackHorizontalMargin),
      child: SizedBox(
        height: stackHeight,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Decorative "behind" cards. They're non-interactive — the
            // user reaches them by swiping the front card.
            for (int i = 0; i < behindEntries.length; i++)
              _BehindCard(
                // depth: 1 = directly behind front, 2 = one further back
                depth: behindEntries.length - i,
                entry: behindEntries[i],
              ),
            // Front (interactive) card.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onTap(current.packageName),
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                onHorizontalDragCancel: _onHorizontalDragCancel,
                child: Transform.translate(
                  // Live drag tracking — gives the swipe a tactile,
                  // direct-manipulation feel before it commits.
                  offset: Offset(_dragDx, 0),
                  child: AnimatedSwitcher(
                    duration: CASIMotion.standard,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          ...previousChildren,
                          ?currentChild,
                        ],
                      );
                    },
                    transitionBuilder: (child, animation) {
                      // Slide direction matches the swipe so the
                      // outgoing card flies off the way the user
                      // pushed it.
                      final beginX = _direction.toDouble();
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(beginX, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _FrontNotificationCard(
                      key: ValueKey('notif_front_${current.packageName}_$safeIndex'),
                      entry: current,
                      indexLabel:
                          total > 1 ? '${safeIndex + 1}/$total' : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical pixels each "behind" depth layer is offset upward from
/// the front card so the user can see it peeking out.
const double _kBehindVerticalGap = 6.0;

/// A non-interactive decorative "deck" card behind the front pill.
/// [depth] = 1 means directly behind the front, 2 means one further
/// back, etc. Larger depths render smaller, dimmer, and shifted up.
class _BehindCard extends StatelessWidget {
  final int depth;
  final NotificationPillEntry entry;

  const _BehindCard({required this.depth, required this.entry});

  @override
  Widget build(BuildContext context) {
    // Each layer back: shrink horizontally, drop opacity, shift up.
    final double horizontalInset = 14.0 * depth;
    final double verticalShift = _kBehindVerticalGap * depth;
    final double opacity = (1.0 - 0.28 * depth).clamp(0.25, 1.0);

    return Positioned(
      left: horizontalInset,
      right: horizontalInset,
      bottom: verticalShift,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kStackPillHeight / 2),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: CASIGlass.blurStandard,
                sigmaY: CASIGlass.blurStandard,
              ),
              child: Container(
                height: _kStackPillHeight - 6.0 * depth,
                decoration: BoxDecoration(
                  color: Colors.white
                      .withValues(alpha: CASIElevation.card.bgAlpha * 0.85),
                  borderRadius:
                      BorderRadius.circular(_kStackPillHeight / 2),
                  border: Border.all(
                    color: Colors.white.withValues(
                        alpha: CASIElevation.card.borderAlpha * 0.85),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The interactive top-of-stack notification card. Shows the app
/// icon, the sender (notification title) and the message body, with
/// the body truncated by ellipsis if it overflows. Sized to roughly
/// match the music player's width and height aesthetic.
class _FrontNotificationCard extends StatelessWidget {
  final NotificationPillEntry entry;

  /// Optional "1/4" style index indicator shown in the top-right of
  /// the pill so users know how deep the stack is.
  final String? indexLabel;

  const _FrontNotificationCard({
    super.key,
    required this.entry,
    this.indexLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Determine which strings to use. Fall back to the app name if
    // the notification has no title (rare). Body falls back to empty.
    final String displayTitle =
        entry.title.isNotEmpty ? entry.title : entry.appName;
    final String displayBody = entry.text;

    return ClipRRect(
      borderRadius: BorderRadius.circular(_kStackPillHeight / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: CASIGlass.blurHeavy,
          sigmaY: CASIGlass.blurHeavy,
        ),
        child: Container(
          height: _kStackPillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white
                .withValues(alpha: CASIElevation.raised.bgAlpha),
            borderRadius: BorderRadius.circular(_kStackPillHeight / 2),
            border: Border.all(
              color: Colors.white.withValues(
                  alpha: CASIElevation.raised.borderAlpha),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              _NotifAppIcon(entry: entry, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayTitle,
                            style: const TextStyle(
                              color: CASIColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (indexLabel != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            indexLabel!,
                            style: const TextStyle(
                              color: CASIColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (displayBody.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        displayBody,
                        style: const TextStyle(
                          color: CASIColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.appName,
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

/// Square-rounded app icon for a notification entry, with a graceful
/// fallback to a generic notification glyph.
class _NotifAppIcon extends StatelessWidget {
  final NotificationPillEntry entry;
  final double size;

  const _NotifAppIcon({required this.entry, required this.size});

  @override
  Widget build(BuildContext context) {
    final hasIcon = entry.icon != null && entry.icon!.isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: hasIcon
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
            ),
    );
  }
}
