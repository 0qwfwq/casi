import 'package:flutter/material.dart';
import 'package:casi/design_system.dart';

/// Shared category-to-UI mappings used by Morning Brief and Notification History.
/// Uses CASI Design System semantic and accent colors.
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
      'email' => CASIColors.alert,           // Red — errors/attention
      'work' => CASIColors.accentPrimary,    // Pulse Blue — interactive
      'social' => CASIColors.accentSecondary, // Pulse Purple — secondary
      'ignore' => CASIColors.textTertiary,    // Muted — disabled state
      _ => CASIColors.accentTertiary,         // Teal — informational
    };
  }
}
