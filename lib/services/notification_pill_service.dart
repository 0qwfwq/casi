// NotificationPillService — surfaces the highest-priority active notifications
// as actionable app shortcuts in the Foresight Dock.
//
// Tier system:
//   T1  Critical / Intimate     (SMS, Phone, Emergency)
//   T2  Personal Messaging      (WhatsApp, Signal, Telegram, etc.)
//   T3  Professional Comms      (Gmail, Outlook, Slack DMs, Discord DMs)
//   T4  Social & Reactive       (Instagram DMs, Twitter DMs, Snapchat)
//   T5  Reminders & Tasks       (Calendar, Tasks, Alarms)
//   T6  Utility                 (Banking, delivery, 2FA)
//   --  Ignored                 (YouTube, charging, media, system)
//
// Only the top 1–2 unique apps from qualifying notifications are surfaced.

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class NotificationPillEntry {
  final String packageName;
  final int tier;
  final int timestamp;
  final Uint8List? icon;
  final String appName;

  NotificationPillEntry({
    required this.packageName,
    required this.tier,
    required this.timestamp,
    this.icon,
    required this.appName,
  });
}

// ---------------------------------------------------------------------------
// NotificationPillService
// ---------------------------------------------------------------------------

class NotificationPillService {
  static const _channel = MethodChannel('casi.launcher/notifications');
  static const _prefsKey = 'notification_tier_overrides';

  // -------------------------------------------------------------------------
  // Default tier lookup table — packageName substring → tier (1–6)
  // -------------------------------------------------------------------------

  // T1: Critical / Intimate
  static const _t1Patterns = [
    'com.google.android.apps.messaging', // Google Messages
    'com.samsung.android.messaging',     // Samsung Messages
    'com.android.mms',
    'com.android.messaging',
    'com.google.android.dialer',
    'com.samsung.android.dialer',
    'com.android.phone',
    'com.android.incallui',
    'com.sec.android.app.samsungapps', // emergency
  ];

  // T2: Personal Messaging
  static const _t2Patterns = [
    'whatsapp',
    'org.thoughtcrime.securesms', // Signal
    'org.telegram',
    'com.beeper',
    'im.vector.app',  // Element (Matrix)
    'org.matrix',
    'chat.rocket',
    'im.status',
  ];

  // T3: Professional Comms
  static const _t3Patterns = [
    'gmail',
    'outlook',
    'com.microsoft.teams',
    'slack',
    'discord',
    'com.samsung.android.email',
    'protonmail',
    'thunderbird',
    'spark',
    'zoom',
    'com.cisco.webex',
  ];

  // T4: Social & Reactive
  static const _t4Patterns = [
    'instagram',
    'twitter',
    'com.x.',
    'snapchat',
    'reddit',
    'facebook.orca',  // Messenger
    'facebook.katana', // Facebook
    'threads',
    'tiktok',
    'pinterest',
    'tumblr',
    'linkedin',
  ];

  // T5: Reminders & Tasks
  static const _t5Patterns = [
    'calendar',
    'com.google.android.apps.tasks',
    'todoist',
    'ticktick',
    'com.android.deskclock',
    'com.samsung.android.app.reminder',
    'com.google.android.apps.reminders',
    'notion',
    'asana',
    'trello',
  ];

  // T6: Utility
  static const _t6Patterns = [
    'banking',
    'bank',
    'paypal',
    'venmo',
    'cashapp',
    'zelle',
    'com.google.android.apps.authenticator',
    'authy',
    'tracking',
    'fedex',
    'ups.mobile',
    'usps',
    'doordash',
    'ubereats',
    'grubhub',
    'postmates',
    'amazon.mShop',
  ];

  // Ignored — never surface
  static const _ignoredPatterns = [
    'youtube',
    'spotify',
    'music',
    'deezer',
    'tidal',
    'pandora',
    'soundcloud',
    'launcher',
    'keyboard',
    'inputmethod',
    'gboard',
    'swiftkey',
    'systemui',
    'nfc',
    'bluetooth',
    'wifi',
    'cast',
    'wear',
    'watch',
    'gallery',
    'camera',
    'calculator',
    'settings',
    'download',
    'com.android.providers',
    'com.android.vending', // Play Store
    'com.google.android.gms', // Google Play Services
    'com.google.android.googlequicksearchbox',
    'game',
    'play.games',
    'netflix',
    'hulu',
    'disneyplus',
    'hbomax',
    'twitch',
    'com.android.shell',
    'com.android.systemui',
  ];

  // Cache of user tier overrides: packageName → tier (1–6, or 0 for ignored)
  static Map<String, int>? _userOverrides;

  /// Classify a package into a notification tier.
  /// Returns 1–6 for qualifying tiers, or null for ignored.
  static int? classifyTier(String packageName) {
    // Check user overrides first
    if (_userOverrides != null && _userOverrides!.containsKey(packageName)) {
      final override = _userOverrides![packageName]!;
      return override == 0 ? null : override;
    }

    final lower = packageName.toLowerCase();

    // Check ignored first
    for (final p in _ignoredPatterns) {
      if (lower.contains(p)) return null;
    }

    for (final p in _t1Patterns) {
      if (lower.contains(p.toLowerCase())) return 1;
    }
    for (final p in _t2Patterns) {
      if (lower.contains(p.toLowerCase())) return 2;
    }
    for (final p in _t3Patterns) {
      if (lower.contains(p.toLowerCase())) return 3;
    }
    for (final p in _t4Patterns) {
      if (lower.contains(p.toLowerCase())) return 4;
    }
    for (final p in _t5Patterns) {
      if (lower.contains(p.toLowerCase())) return 5;
    }
    for (final p in _t6Patterns) {
      if (lower.contains(p.toLowerCase())) return 6;
    }

    // Fallback: unrecognized apps default to T6 (utility) rather than ignored,
    // so unknown messaging apps still surface. The Android category hint from
    // the notification can help here but we keep it simple.
    return 6;
  }

  /// Load user tier overrides from SharedPreferences.
  static Future<void> loadUserOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _userOverrides = decoded.map((k, v) => MapEntry(k, v as int));
      } catch (_) {
        _userOverrides = {};
      }
    } else {
      _userOverrides = {};
    }
  }

  /// Save a user tier override.
  static Future<void> setTierOverride(String packageName, int tier) async {
    _userOverrides ??= {};
    _userOverrides![packageName] = tier;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_userOverrides));
  }

  /// Remove a user tier override (revert to default).
  static Future<void> removeTierOverride(String packageName) async {
    _userOverrides?.remove(packageName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_userOverrides ?? {}));
  }

  /// Get the current user overrides map.
  static Map<String, int> get userOverrides => Map.unmodifiable(_userOverrides ?? {});

  // -------------------------------------------------------------------------
  // Notification fetching & ranking
  // -------------------------------------------------------------------------

  /// Fetch active notifications, filter and rank them, return top 0–2 unique
  /// app entries suitable for the notification pill.
  ///
  /// [foregroundPackage] — if the user currently has an app open, exclude it.
  static Future<List<NotificationPillEntry>> getNotificationPillApps({
    String? foregroundPackage,
  }) async {
    // Check notification access
    bool hasAccess;
    try {
      hasAccess = await _channel.invokeMethod('isNotificationAccessGranted') as bool? ?? false;
    } catch (_) {
      return [];
    }
    if (!hasAccess) return [];

    // Fetch active notifications
    String rawJson;
    try {
      rawJson = await _channel.invokeMethod('getActiveNotifications') as String? ?? '[]';
    } catch (_) {
      return [];
    }

    List<dynamic> parsed;
    try {
      parsed = jsonDecode(rawJson) as List<dynamic>;
    } catch (_) {
      return [];
    }

    // Filter and classify
    final candidates = <_RankedNotification>[];

    for (final item in parsed) {
      final map = item as Map<String, dynamic>;
      final packageName = map['packageName'] as String? ?? '';
      if (packageName.isEmpty) continue;

      // Skip if this app is currently in foreground
      if (foregroundPackage != null && packageName == foregroundPackage) continue;

      // Skip ongoing / foreground service notifications
      final isOngoing = map['isOngoing'] as bool? ?? false;
      final isForeground = map['isForeground'] as bool? ?? false;
      final isGroupSummary = map['isGroupSummary'] as bool? ?? false;
      if (isOngoing || isForeground) continue;
      if (isGroupSummary) continue;

      // Skip low-importance (IMPORTANCE_LOW = 2, IMPORTANCE_MIN = 1, IMPORTANCE_NONE = 0)
      final importance = map['importance'] as int? ?? 3;
      if (importance < 3) continue;

      // Classify tier
      final tier = classifyTier(packageName);
      if (tier == null) continue; // Ignored

      final timestamp = map['timestamp'] as int? ?? 0;

      candidates.add(_RankedNotification(
        packageName: packageName,
        tier: tier,
        timestamp: timestamp,
      ));
    }

    // Sort: tier ascending (lower = higher priority), then recency descending
    candidates.sort((a, b) {
      final tierCmp = a.tier.compareTo(b.tier);
      if (tierCmp != 0) return tierCmp;
      return b.timestamp.compareTo(a.timestamp);
    });

    // Deduplicate by package name, keep first (highest priority) occurrence
    final seen = <String>{};
    final unique = <_RankedNotification>[];
    for (final c in candidates) {
      if (!seen.contains(c.packageName)) {
        seen.add(c.packageName);
        unique.add(c);
      }
    }

    // Take top 2
    final top = unique.take(2).toList();

    return top
        .map((c) => NotificationPillEntry(
              packageName: c.packageName,
              tier: c.tier,
              timestamp: c.timestamp,
              appName: _appLabel(c.packageName),
            ))
        .toList();
  }

  /// Human-readable short name from package name.
  static String _appLabel(String packageName) {
    final lower = packageName.toLowerCase();
    if (lower.contains('com.google.android.apps.messaging')) return 'Messages';
    if (lower.contains('com.samsung.android.messaging')) return 'Messages';
    if (lower.contains('com.android.mms')) return 'Messages';
    if (lower.contains('dialer') || lower.contains('phone')) return 'Phone';
    if (lower.contains('whatsapp')) return 'WhatsApp';
    if (lower.contains('org.thoughtcrime.securesms')) return 'Signal';
    if (lower.contains('org.telegram')) return 'Telegram';
    if (lower.contains('beeper')) return 'Beeper';
    if (lower.contains('gmail')) return 'Gmail';
    if (lower.contains('outlook')) return 'Outlook';
    if (lower.contains('teams')) return 'Teams';
    if (lower.contains('slack')) return 'Slack';
    if (lower.contains('discord')) return 'Discord';
    if (lower.contains('instagram')) return 'Instagram';
    if (lower.contains('twitter') || lower.contains('com.x.')) return 'X';
    if (lower.contains('snapchat')) return 'Snapchat';
    if (lower.contains('reddit')) return 'Reddit';
    if (lower.contains('facebook.orca')) return 'Messenger';
    if (lower.contains('facebook')) return 'Facebook';
    if (lower.contains('threads')) return 'Threads';
    if (lower.contains('tiktok')) return 'TikTok';
    if (lower.contains('calendar')) return 'Calendar';
    if (lower.contains('zoom')) return 'Zoom';
    if (lower.contains('protonmail')) return 'Proton Mail';
    if (lower.contains('linkedin')) return 'LinkedIn';
    // Fallback: last meaningful segment
    final parts = packageName.split('.');
    if (parts.length >= 2) {
      final last = parts.last;
      if (last.length > 2) return last[0].toUpperCase() + last.substring(1);
    }
    return packageName;
  }
}

class _RankedNotification {
  final String packageName;
  final int tier;
  final int timestamp;

  _RankedNotification({
    required this.packageName,
    required this.tier,
    required this.timestamp,
  });
}
