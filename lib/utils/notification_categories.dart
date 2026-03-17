import 'package:flutter/material.dart';

/// Shared category-to-UI mappings used by Morning Brief and Notification History.
class NotificationCategories {
  const NotificationCategories._();

  static IconData iconFor(String category) {
    return switch (category) {
      'email' => Icons.email_outlined,
      'work' => Icons.work_outline,
      'social' => Icons.chat_bubble_outline,
      'ignore' => Icons.notifications_off_outlined,
      _ => Icons.notifications_outlined,
    };
  }

  static Color colorFor(String category) {
    return switch (category) {
      'email' => Colors.red.shade300,
      'work' => Colors.blue.shade300,
      'social' => Colors.purple.shade300,
      'ignore' => Colors.grey.shade500,
      _ => Colors.teal.shade300,
    };
  }
}
