import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';
import 'package:casi/services/notification_pill_service.dart';

/// A single notification "deck" pill sized to match the music player.
/// The top card shows the most-important active notification; the
/// remaining notifications render behind it like a stack of cards.
///
/// Swipe right → cycle forward (1 → 2 → … → wrap to 1).
/// Swipe left  → cycle backward.
/// Tap        → fires [onTap] with the front-card package name.
class NotificationStackPill extends StatefulWidget {
  final List<NotificationPillEntry> entries;
  final void Function(String packageName) onTap;

  const NotificationStackPill({
    super.key,
    required this.entries,
    required this.onTap,
  });

  @override
  State<NotificationStackPill> createState() => _NotificationStackPillState();
}

/// Horizontal margin around the stack pill — matches `SongPlayer`'s
/// margin so the pill aligns to the same rail as the music player.
const double _kStackHorizontalMargin = 40.0;

/// Front-card height — matches `SongPlayer`'s height so the two pills
/// read as the same size.
const double _kStackPillHeight = 70.0;

/// Corner radius — matches `SongPlayer`'s 35px radius.
const double _kStackCornerRadius = 35.0;

/// How many cards behind the front are visible as decorative
/// "depth" layers.
const int _kStackVisibleBehind = 2;

const double _kSwipeCommitThreshold = 48.0;
const double _kSwipeVelocityThreshold = 320.0;
const double _kBehindVerticalGap = 6.0;

class _NotificationStackPillState extends State<NotificationStackPill> {
  int _index = 0;
  int _direction = 1;
  double _dragDx = 0.0;

  @override
  void didUpdateWidget(covariant NotificationStackPill oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    setState(() => _dragDx += details.delta.dx);
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

    final int behindCount =
        (total - 1).clamp(0, _kStackVisibleBehind).toInt();
    final behindEntries = <NotificationPillEntry>[];
    for (int offset = behindCount; offset >= 1; offset--) {
      final i = (safeIndex + offset) % total;
      behindEntries.add(entries[i]);
    }

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
            for (int i = 0; i < behindEntries.length; i++)
              _BehindCard(
                depth: behindEntries.length - i,
                entry: behindEntries[i],
              ),
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
                      key: ValueKey(
                          'notif_front_${current.packageName}_$safeIndex'),
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

class _BehindCard extends StatelessWidget {
  final int depth;
  final NotificationPillEntry entry;

  const _BehindCard({required this.depth, required this.entry});

  @override
  Widget build(BuildContext context) {
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
          child: GlassSurface.foresight(
            cornerRadius: _kStackCornerRadius,
            height: _kStackPillHeight - 6.0 * depth,
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _FrontNotificationCard extends StatelessWidget {
  final NotificationPillEntry entry;
  final String? indexLabel;

  const _FrontNotificationCard({
    super.key,
    required this.entry,
    this.indexLabel,
  });

  @override
  Widget build(BuildContext context) {
    final String displayTitle =
        entry.title.isNotEmpty ? entry.title : entry.appName;
    final String displayBody = entry.text;

    return GlassSurface.foresight(
      cornerRadius: _kStackCornerRadius,
      height: _kStackPillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _NotifAppIcon(entry: entry, size: 42),
          const SizedBox(width: 14),
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
                const SizedBox(height: 2),
                Text(
                  displayBody.isNotEmpty ? displayBody : entry.appName,
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
      ),
    );
  }
}

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
