import 'dart:ui';
import 'package:flutter/material.dart';
import '../morning_brief/notification_brief_service.dart';
import '../utils/app_launcher.dart';
import '../utils/notification_categories.dart';

/// Notification history content panel — designed to be embedded in the home
/// page Stack so it shares the same wallpaper background. Call [onDismiss]
/// when the user swipes to go back.
class NotificationHistoryPanel extends StatefulWidget {
  final VoidCallback onDismiss;

  const NotificationHistoryPanel({
    super.key,
    required this.onDismiss,
  });

  @override
  State<NotificationHistoryPanel> createState() =>
      _NotificationHistoryPanelState();
}

class _NotificationHistoryPanelState extends State<NotificationHistoryPanel> {
  List<CapturedNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final notifs = await NotificationBriefService.getAllNotifications();
    if (mounted) {
      setState(() {
        _notifications = notifs;
        _isLoading = false;
      });
    }
  }

  String _timeAgo(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    final minutes = diff ~/ (60 * 1000);
    if (minutes < 1) return 'Just now';
    if (minutes < 60) return '${minutes}m ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        // Swipe right-to-left to go back
        if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
          widget.onDismiss();
        }
      },
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white24,
                strokeWidth: 2,
              ),
            )
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        color: Colors.white.withValues(alpha: 0.3),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No notifications in the last 24 hours',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                        16, topPadding + 16, 16, bottomPadding + 16),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _buildNotificationCard(_notifications[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildNotificationCard(CapturedNotification notif) {
    final category = NotificationBriefService.categorizeApp(notif.packageName);
    final label = NotificationBriefService.appLabel(notif.packageName);
    final catColor = NotificationCategories.colorFor(category);
    final catIcon = NotificationCategories.iconFor(category);
    final fullText = notif.fullText;

    return GestureDetector(
      onTap: () => AppLauncher.launchApp(notif.packageName),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App label row with icon and time
                Row(
                  children: [
                    Icon(catIcon, color: catColor, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: catColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _timeAgo(notif.timestamp),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Title
                if (notif.title.isNotEmpty)
                  Text(
                    notif.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                // Full text content (no maxLines — show everything)
                if (fullText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    fullText,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      height: 1.45,
                    ),
                  ),
                ],
                // SubText if available
                if (notif.subText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notif.subText,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
