import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../morning_brief/notification_brief_service.dart';
import '../utils/app_launcher.dart';

class NotificationHistoryScreen extends StatefulWidget {
  final String bgType;
  final Color bgColor;
  final String? bgImagePath;
  final bool immersiveMode;

  const NotificationHistoryScreen({
    super.key,
    required this.bgType,
    required this.bgColor,
    this.bgImagePath,
    required this.immersiveMode,
  });

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  List<CapturedNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.immersiveMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
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

  Color _categoryColor(String category) {
    switch (category) {
      case 'email':
        return Colors.red.shade300;
      case 'work':
        return Colors.blue.shade300;
      case 'social':
        return Colors.purple.shade300;
      case 'ignore':
        return Colors.grey.shade500;
      default:
        return Colors.teal.shade300;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'email':
        return Icons.email_outlined;
      case 'work':
        return Icons.work_outline;
      case 'social':
        return Icons.chat_bubble_outline;
      case 'ignore':
        return Icons.notifications_off_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe right-to-left to go back
        if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Background — matches main screen
            Positioned.fill(
              child: widget.bgType == 'image' && widget.bgImagePath != null
                  ? Image.file(
                      File(widget.bgImagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: Colors.black),
                    )
                  : Container(color: widget.bgColor),
            ),
            // Content
            _isLoading
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
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                            16, topPadding + 16, 16, bottomPadding + 16),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _buildNotificationCard(
                              _notifications[index]);
                        },
                      ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(CapturedNotification notif) {
    final category = NotificationBriefService.categorizeApp(notif.packageName);
    final label = NotificationBriefService.appLabel(notif.packageName);
    final catColor = _categoryColor(category);
    final catIcon = _categoryIcon(category);
    final fullText = notif.fullText;

    return GestureDetector(
      onTap: () => AppLauncher.launchApp(notif.packageName),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 0.8,
          ),
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
    );
  }
}
