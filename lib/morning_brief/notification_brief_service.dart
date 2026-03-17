import 'dart:convert';
import 'package:flutter/services.dart';

/// Represents a single captured notification from Android.
class CapturedNotification {
  final String packageName;
  final String title;
  final String text;
  final String bigText;
  final String subText;
  final int timestamp;
  final String category;

  CapturedNotification({
    required this.packageName,
    required this.title,
    required this.text,
    required this.bigText,
    required this.subText,
    required this.timestamp,
    required this.category,
  });

  factory CapturedNotification.fromJson(Map<String, dynamic> json) {
    return CapturedNotification(
      packageName: json['packageName'] as String? ?? '',
      title: json['title'] as String? ?? '',
      text: json['text'] as String? ?? '',
      bigText: json['bigText'] as String? ?? '',
      subText: json['subText'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? 0,
      category: json['category'] as String? ?? '',
    );
  }

  /// The most detailed text content available.
  String get fullText => bigText.isNotEmpty ? bigText : text;
}

/// A scored, categorized notification ready for display.
class ImportantNotification {
  final String appCategory; // 'email', 'work', 'social', 'other'
  final String appLabel;
  final String packageName;
  final String title;
  final String summary;
  final int score;
  final int timestamp;

  ImportantNotification({
    required this.appCategory,
    required this.appLabel,
    required this.packageName,
    required this.title,
    required this.summary,
    required this.score,
    required this.timestamp,
  });
}

/// Data class holding the final notification digest for the Morning Brief.
class NotificationBriefData {
  final List<ImportantNotification> items;
  final bool hasNotificationAccess;

  NotificationBriefData({
    required this.items,
    required this.hasNotificationAccess,
  });
}

/// Service that reads captured Android notifications, categorizes them,
/// scores their importance using a local rule-based system, and returns
/// a digest of the most important ones.
class NotificationBriefService {
  static const _channel = MethodChannel('casi.launcher/notifications');

  // ─── App Category Detection ───────────────────────────────────────────────

  /// Maps package name patterns to categories.
  /// Uses substring matching so new apps with similar naming get picked up.
  static const _emailPatterns = [
    'gmail', 'outlook', 'samsung.email', 'email', 'mail', 'yahoo.mail',
    'protonmail', 'thunderbird', 'aquamail', 'bluemail', 'spark',
  ];

  static const _workSchoolPatterns = [
    'teams', 'canvas', 'slack', 'zoom', 'classroom', 'blackboard',
    'notion', 'asana', 'trello', 'jira', 'monday', 'clickup',
    'moodle', 'schoology', 'brightspace', 'remind', 'piazza',
    'google.android.apps.classroom', 'instructure',
  ];

  static const _socialPatterns = [
    'instagram', 'whatsapp', 'messaging', 'messenger', 'telegram',
    'signal', 'snapchat', 'twitter', 'discord', 'wechat', 'line',
    'viber', 'tiktok', 'reddit', 'facebook', 'threads',
    'com.google.android.apps.messaging', 'com.samsung.android.messaging',
  ];

  /// Apps whose notifications are almost never important for a morning brief.
  static const _ignorePatterns = [
    'launcher', 'keyboard', 'systemui', 'inputmethod', 'gboard',
    'swiftkey', 'gallery', 'camera', 'calculator', 'clock',
    'weather', 'dialer', 'contacts', 'settings', 'bluetooth',
    'nfc', 'wifi', 'cast', 'wear', 'watch', 'health',
    'fitness', 'step', 'music', 'spotify', 'soundcloud',
    'youtube.music', 'deezer', 'tidal', 'pandora',
    'game', 'play.games',
  ];

  static String categorizeApp(String packageName) {
    final lower = packageName.toLowerCase();

    for (final p in _ignorePatterns) {
      if (lower.contains(p)) return 'ignore';
    }
    for (final p in _emailPatterns) {
      if (lower.contains(p)) return 'email';
    }
    for (final p in _workSchoolPatterns) {
      if (lower.contains(p)) return 'work';
    }
    for (final p in _socialPatterns) {
      if (lower.contains(p)) return 'social';
    }
    return 'other';
  }

  static String appLabel(String packageName) {
    final lower = packageName.toLowerCase();
    // Return a human-readable short name from the package
    if (lower.contains('gmail')) return 'Gmail';
    if (lower.contains('outlook')) return 'Outlook';
    if (lower.contains('samsung.email')) return 'Samsung Email';
    if (lower.contains('teams')) return 'Teams';
    if (lower.contains('canvas') || lower.contains('instructure')) return 'Canvas';
    if (lower.contains('slack')) return 'Slack';
    if (lower.contains('zoom')) return 'Zoom';
    if (lower.contains('classroom')) return 'Classroom';
    if (lower.contains('blackboard')) return 'Blackboard';
    if (lower.contains('notion')) return 'Notion';
    if (lower.contains('instagram')) return 'Instagram';
    if (lower.contains('whatsapp')) return 'WhatsApp';
    if (lower.contains('telegram')) return 'Telegram';
    if (lower.contains('signal')) return 'Signal';
    if (lower.contains('discord')) return 'Discord';
    if (lower.contains('messenger')) return 'Messenger';
    if (lower.contains('snapchat')) return 'Snapchat';
    if (lower.contains('twitter') || lower.contains('x.com')) return 'X';
    if (lower.contains('reddit')) return 'Reddit';
    if (lower.contains('facebook')) return 'Facebook';
    if (lower.contains('threads')) return 'Threads';
    if (lower.contains('messaging') || lower.contains('mms')) return 'Messages';
    if (lower.contains('remind')) return 'Remind';
    if (lower.contains('trello')) return 'Trello';
    if (lower.contains('asana')) return 'Asana';
    if (lower.contains('jira')) return 'Jira';
    if (lower.contains('moodle')) return 'Moodle';

    // Fallback: extract the last meaningful segment from package name
    final parts = packageName.split('.');
    if (parts.length >= 2) {
      final last = parts.last;
      if (last.length > 2) {
        return last[0].toUpperCase() + last.substring(1);
      }
    }
    return packageName;
  }

  // ─── Importance Scoring ───────────────────────────────────────────────────

  /// High-urgency keywords. These strongly indicate the user should see this.
  static const _urgentKeywords = [
    'urgent', 'emergency', 'cancelled', 'canceled', 'deadline',
    'asap', 'immediately', 'critical', 'important', 'alert',
    'warning', 'action required', 'time sensitive', 'expiring',
    'overdue', 'past due', 'final notice', 'last chance',
  ];

  /// Action-needed keywords. Someone is asking the user to do something.
  static const _actionKeywords = [
    'please', 'can you', 'could you', 'need you', 'need to',
    'reminder', 'don\'t forget', 'remember to', 'make sure',
    'submit', 'complete', 'finish', 'respond', 'reply',
    'approve', 'review', 'confirm', 'sign', 'schedule',
    'meeting', 'call', 'interview', 'appointment',
  ];

  /// Time-sensitive references.
  static const _timeKeywords = [
    'today', 'tonight', 'this morning', 'this afternoon',
    'this evening', 'right now', 'in an hour', 'by end of day',
    'by eod', 'tomorrow', 'due date', 'starts at', 'begins at',
  ];

  /// Personal urgency — things happening in the real world.
  static const _personalKeywords = [
    'car', 'door', 'keys', 'wallet', 'phone', 'window',
    'left your', 'forgot', 'locked', 'raining', 'storm',
    'accident', 'hospital', 'doctor', 'flight', 'gate',
    'pickup', 'pick up', 'arriving', 'delivered', 'package',
    'miss you', 'love you', 'are you ok', 'are you okay',
    'where are you', 'call me', 'come home',
  ];

  /// Spam/marketing signals — reduce score for these.
  static const _spamKeywords = [
    'sale', '% off', 'promo', 'coupon', 'deal', 'discount',
    'subscribe', 'newsletter', 'unsubscribe', 'advertisement',
    'shop now', 'buy now', 'limited time', 'free shipping',
    'click here', 'learn more', 'sponsored', 'ad:',
    'earn rewards', 'cashback', 'offer expires',
    'we miss you', 'come back', 'haven\'t visited',
  ];

  /// Question detection patterns.
  static const _questionKeywords = [
    '?', 'can you', 'could you', 'would you', 'will you',
    'do you', 'did you', 'have you', 'are you', 'what time',
    'where is', 'when is', 'how do', 'how is',
  ];

  /// Casual/low-substance patterns — reduce score for social chitchat.
  /// Using a Set for O(1) lookups instead of O(n) list iteration.
  static const _casualPatterns = {
    'hi', 'hey', 'yo', 'sup',
    'ok', 'okay', 'k', 'kk',
    'bet', 'aight',
    'lol', 'lmao', 'lmfao', 'haha',
    'ya', 'yea', 'yeah', 'yep', 'yup', 'nah', 'nope',
    'bruh', 'bro', 'dude', 'ight',
    'gn', 'gm', 'ttyl', 'gtg', 'omg', 'omw',
    'wya', 'wyd', 'nm', 'nmu',
    'gg', 'fs', 'fr', 'smh', 'ngl',
    'idk', 'idc', 'idm', 'imo',
    'ty', 'thx', 'tysm', 'np', 'yw',
    'hbu', 'wbu', 'ikr',
    'nice', 'cool', 'fire', 'lit', 'slay',
    'true', 'facts', 'same', 'mood', 'real',
  };

  /// Collapses repeated characters: "betttt" → "bet", "hiiii" → "hi"
  static String _collapseRepeats(String s) {
    return s.replaceAll(RegExp(r'(.)\1+'), r'$1');
  }

  static int _scoreNotification(CapturedNotification notif, String category) {
    if (category == 'ignore') return -100;

    // Base score by category
    int score = switch (category) {
      'email' => 3,
      'work' => 4,
      'social' => 2,
      _ => 1,
    };

    final combined = '${notif.title} ${notif.fullText}'.toLowerCase();

    // Urgency keywords (+5 each, cap at +15)
    int urgencyHits = 0;
    for (final kw in _urgentKeywords) {
      if (combined.contains(kw)) urgencyHits++;
    }
    score += (urgencyHits.clamp(0, 3)) * 5;

    // Action keywords (+3 each, cap at +9)
    int actionHits = 0;
    for (final kw in _actionKeywords) {
      if (combined.contains(kw)) actionHits++;
    }
    score += (actionHits.clamp(0, 3)) * 3;

    // Time-sensitive (+3 each, cap at +6)
    int timeHits = 0;
    for (final kw in _timeKeywords) {
      if (combined.contains(kw)) timeHits++;
    }
    score += (timeHits.clamp(0, 2)) * 3;

    // Personal keywords (+4 each, cap at +8)
    int personalHits = 0;
    for (final kw in _personalKeywords) {
      if (combined.contains(kw)) personalHits++;
    }
    score += (personalHits.clamp(0, 2)) * 4;

    // Question detection (+3)
    int questionHits = 0;
    for (final kw in _questionKeywords) {
      if (combined.contains(kw)) questionHits++;
    }
    if (questionHits > 0) score += 3;

    // Spam/marketing detection (-6 each, cap at -12)
    int spamHits = 0;
    for (final kw in _spamKeywords) {
      if (combined.contains(kw)) spamHits++;
    }
    score -= (spamHits.clamp(0, 2)) * 6;

    // Direct message bonus: social messages with short text are likely DMs
    if (category == 'social' && notif.text.length < 200 && notif.text.isNotEmpty) {
      score += 2;
    }

    // Android notification category hints
    if (notif.category == 'msg' || notif.category == 'email') {
      score += 2;
    }

    // Recency bonus: notifications from the last 6 hours get a boost
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - notif.timestamp;
    if (age < 6 * 60 * 60 * 1000) {
      score += 2;
    } else if (age < 12 * 60 * 60 * 1000) {
      score += 1;
    }

    // Casual/low-substance penalty for social messages
    if (category == 'social') {
      final textLower = notif.fullText.toLowerCase().trim();
      final collapsed = _collapseRepeats(textLower);
      final stripped = collapsed.replaceAll(RegExp(r'[^\w\s]'), '').trim();

      if (_casualPatterns.contains(stripped)) {
        score -= 4;
      } else if (textLower.length < 12 && urgencyHits == 0 && actionHits == 0 && personalHits == 0 && questionHits == 0) {
        score -= 3;
      }
    }

    return score;
  }

  // ─── Internal Helpers ─────────────────────────────────────────────────────

  static Future<bool> _checkAccess() async {
    try {
      return await _channel.invokeMethod('isNotificationAccessGranted') as bool? ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<List<CapturedNotification>?> _fetchNotifications(String method) async {
    String rawJson;
    try {
      rawJson = await _channel.invokeMethod(method) as String? ?? '[]';
    } on PlatformException {
      return null;
    }

    try {
      final parsed = jsonDecode(rawJson) as List<dynamic>;
      return parsed
          .map((e) => CapturedNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static const _dayInMs = 24 * 60 * 60 * 1000;

  // ─── Public API ───────────────────────────────────────────────────────────

  /// Fetches only currently active (non-dismissed) notifications from the
  /// system notification shade, scores and filters them, and returns a
  /// digest of the most important ones.
  static Future<NotificationBriefData> generateBrief() async {
    final hasAccess = await _checkAccess();
    if (!hasAccess) {
      return NotificationBriefData(items: [], hasNotificationAccess: false);
    }

    final notifications = await _fetchNotifications('getActiveNotifications');
    if (notifications == null) {
      return NotificationBriefData(items: [], hasNotificationAccess: true);
    }

    final cutoff = DateTime.now().millisecondsSinceEpoch - _dayInMs;
    final recent = notifications.where((n) => n.timestamp > cutoff).toList();

    // Score and categorize
    final scored = <ImportantNotification>[];
    for (final notif in recent) {
      final category = categorizeApp(notif.packageName);
      final score = _scoreNotification(notif, category);

      // Threshold: only include notifications scoring 5 or above
      if (score >= 5) {
        scored.add(ImportantNotification(
          appCategory: category,
          appLabel: appLabel(notif.packageName),
          packageName: notif.packageName,
          title: notif.title,
          summary: _truncate(notif.fullText, 120),
          score: score,
          timestamp: notif.timestamp,
        ));
      }
    }

    // Sort by score descending, then by timestamp descending
    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return b.timestamp.compareTo(a.timestamp);
    });

    // Deduplicate: keep only the highest-scored notification per app+title
    final seen = <String>{};
    final deduped = <ImportantNotification>[];
    for (final item in scored) {
      final key = '${item.appLabel}|${item.title}';
      if (!seen.contains(key)) {
        seen.add(key);
        deduped.add(item);
      }
    }

    // Return top 6 items max
    final topItems = deduped.take(6).toList();

    return NotificationBriefData(items: topItems, hasNotificationAccess: true);
  }

  /// Fetches all stored notifications from the history (SharedPreferences).
  /// Returns all notifications from the last 24 hours, sorted by timestamp
  /// descending (newest first). Used by the notification history screen.
  static Future<List<CapturedNotification>> getAllNotifications() async {
    final hasAccess = await _checkAccess();
    if (!hasAccess) return [];

    final notifications = await _fetchNotifications('getNotifications');
    if (notifications == null) return [];

    final cutoff = DateTime.now().millisecondsSinceEpoch - _dayInMs;
    final recent = notifications.where((n) => n.timestamp > cutoff).toList();

    recent.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return recent;
  }

  static String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen - 1)}…';
  }
}
