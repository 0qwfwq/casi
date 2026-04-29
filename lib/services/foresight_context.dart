// Foresight — Context interpreter (rule engine).
//
// Reads every signal we can observe about the user's current situation —
// time, calendar, notifications, battery, charging, network, session gap,
// previous app — and reasons about what they probably *need right now*.
//
// Produces a list of [Need] records, each with:
//  * a set of capability tags an app would have to expose to satisfy it
//  * a 0–1 priority weight
//  * a human-readable reason explaining why the need was inferred
//
// Each rule is an explicit Dart function operating on a [ContextSnapshot].
// The system is fully transparent: there is no model, no training, no
// hidden weights. Every recommendation can be traced to a single rule.
//
// Upgrade path: swap [ContextInterpreter.interpret] for an LLM that
// emits the same `List<Need>` structure. Everything downstream stays
// identical.

import 'foresight_capabilities.dart';
import '../morning_brief/calendar_brief_service.dart';
import 'notification_pill_service.dart';

// ---------------------------------------------------------------------------
// Snapshot of every signal a rule can read.
// ---------------------------------------------------------------------------

class ContextSnapshot {
  final DateTime now;

  /// Battery level 0–100 (or -1 if unknown).
  final int batteryLevel;
  final bool isCharging;

  /// 'wifi' | 'cellular' | 'other' | 'offline' | 'unknown'.
  final String networkState;

  /// Seconds since the launcher was last paused/unlocked. 7200 means
  /// "fresh — assume the user just came back to the device."
  final int sessionGapSeconds;

  /// Last app the user actually opened from the launcher (null at boot).
  final String? previousApp;

  /// Today's calendar events from the device's default calendar.
  final List<DeviceCalendarEvent> todayEvents;

  /// Currently active notifications, ranked highest priority first.
  final List<NotificationPillEntry> notifications;

  ContextSnapshot({
    required this.now,
    required this.batteryLevel,
    required this.isCharging,
    required this.networkState,
    required this.sessionGapSeconds,
    required this.previousApp,
    required this.todayEvents,
    required this.notifications,
  });

  bool get isWeekend => now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
  bool get isWeekday => !isWeekend;
  int get hour => now.hour;
}

// ---------------------------------------------------------------------------
// Need — a structured demand the user has right now.
// ---------------------------------------------------------------------------

class Need {
  /// Short label for debugging/UI ("note_taking", "navigation").
  final String name;

  /// Capability tags an app must expose at least one of to satisfy this
  /// need. See [AppCapability] for the canonical tag vocabulary.
  final List<String> tags;

  /// 0.0 – 1.0. Higher means a stronger demand for an app that satisfies
  /// this need; multiple needs scoring the same app stack additively.
  final double priority;

  /// Human-readable reason this need was emitted, e.g.
  /// "Lecture starts in 12 min". Surfaced via [ForesightPrediction.reason]
  /// for debugging and future UI.
  final String reason;

  Need({
    required this.name,
    required this.tags,
    required this.priority,
    required this.reason,
  });

  @override
  String toString() => 'Need($name, p=${priority.toStringAsFixed(2)}, '
      'tags=$tags, "$reason")';
}

// ---------------------------------------------------------------------------
// Rule engine.
// ---------------------------------------------------------------------------

class ContextInterpreter {
  ContextInterpreter._();

  /// Returns the full set of needs inferred from [s].
  static List<Need> interpret(ContextSnapshot s) {
    final needs = <Need>[];
    _calendarRules(s, needs);
    _notificationRules(s, needs);
    _commuteRules(s, needs);
    _workdayRules(s, needs);
    _eveningRules(s, needs);
    _windDownRules(s, needs);
    _morningRules(s, needs);
    _batteryRules(s, needs);
    _weekendRules(s, needs);
    _sessionGapRules(s, needs);
    _previousAppRules(s, needs);
    return needs;
  }

  // ---------------------------------------------------------------------------
  // Calendar — the strongest signal we have. An imminent event tells us
  // exactly what the user is about to do.
  // ---------------------------------------------------------------------------

  static void _calendarRules(ContextSnapshot s, List<Need> out) {
    if (s.todayEvents.isEmpty) return;
    final nowMs = s.now.millisecondsSinceEpoch;

    for (final event in s.todayEvents) {
      if (event.allDay) continue;
      final minutesUntilStart = ((event.begin - nowMs) / 60000).round();
      final minutesUntilEnd = ((event.end - nowMs) / 60000).round();

      // Imminent (next 30 minutes) or in-progress (started up to 10 min ago).
      final isImminent = minutesUntilStart >= -10 && minutesUntilStart <= 30;
      // In progress: started but not yet ended.
      final isInProgress = minutesUntilStart <= 0 && minutesUntilEnd > 0;
      if (!isImminent && !isInProgress) continue;

      final title = event.title;
      final lower = title.toLowerCase();
      final loc = event.location.toLowerCase();

      String when;
      if (minutesUntilStart > 0) {
        when = 'in $minutesUntilStart min';
      } else if (minutesUntilEnd > 0) {
        when = 'now';
      } else {
        when = 'just started';
      }

      // Lecture / class / lab / seminar — academic context.
      if (lower.contains('lecture') ||
          lower.contains('class') ||
          lower.contains('lab') ||
          lower.contains('seminar') ||
          lower.contains('lesson') ||
          lower.contains('tutorial') ||
          lower.contains('recitation')) {
        out.add(Need(
          name: 'lecture_notes',
          tags: const [
            AppCapability.noteTaking,
            AppCapability.lectureCompanion,
          ],
          priority: 0.95,
          reason: '"$title" $when',
        ));
        out.add(Need(
          name: 'lecture_portal',
          tags: const [
            AppCapability.campusPortal,
            AppCapability.education,
          ],
          priority: 0.85,
          reason: 'Class materials for "$title"',
        ));
        out.add(Need(
          name: 'cancellation_check',
          tags: const [AppCapability.email],
          priority: 0.6,
          reason: 'Check for class cancellation',
        ));
        out.add(Need(
          name: 'lecture_calendar',
          tags: const [AppCapability.calendar],
          priority: 0.4,
          reason: 'Confirm "$title" details',
        ));
        continue;
      }

      // Meeting / call / 1:1 / sync — work context.
      if (lower.contains('meeting') ||
          lower.contains('call') ||
          lower.contains('1:1') ||
          lower.contains('1 on 1') ||
          lower.contains('sync') ||
          lower.contains('standup') ||
          lower.contains('stand-up') ||
          lower.contains('interview') ||
          lower.contains('zoom') ||
          lower.contains('teams') ||
          lower.contains('webex') ||
          lower.contains('meet ')) {
        out.add(Need(
          name: 'meeting_join',
          tags: const [
            AppCapability.videoCall,
            AppCapability.meeting,
            AppCapability.conference,
          ],
          priority: 0.95,
          reason: '"$title" $when',
        ));
        out.add(Need(
          name: 'meeting_notes',
          tags: const [
            AppCapability.noteTaking,
            AppCapability.productivity,
          ],
          priority: 0.7,
          reason: 'Take notes for "$title"',
        ));
        out.add(Need(
          name: 'meeting_calendar',
          tags: const [AppCapability.calendar],
          priority: 0.5,
          reason: 'Confirm meeting details',
        ));
        continue;
      }

      // Workout / gym / run — fitness context.
      if (lower.contains('workout') ||
          lower.contains('gym') ||
          lower.contains('run') ||
          lower.contains('yoga') ||
          lower.contains('exercise') ||
          lower.contains('training')) {
        out.add(Need(
          name: 'workout_tracker',
          tags: const [
            AppCapability.fitness,
            AppCapability.health,
            AppCapability.running,
          ],
          priority: 0.9,
          reason: '"$title" $when',
        ));
        out.add(Need(
          name: 'workout_audio',
          tags: const [AppCapability.music, AppCapability.audio],
          priority: 0.65,
          reason: 'Workout playlist',
        ));
        continue;
      }

      // Flight / trip — travel context.
      if (lower.contains('flight') ||
          lower.contains('trip') ||
          lower.contains('vacation') ||
          lower.contains('travel')) {
        out.add(Need(
          name: 'travel_check',
          tags: const [
            AppCapability.travel,
            AppCapability.flights,
          ],
          priority: 0.85,
          reason: '"$title" $when',
        ));
        out.add(Need(
          name: 'travel_navigation',
          tags: const [AppCapability.navigation],
          priority: 0.6,
          reason: 'Get to "$title"',
        ));
        continue;
      }

      // Has a physical location → user probably needs to navigate there.
      if (loc.isNotEmpty &&
          minutesUntilStart > 0 &&
          minutesUntilStart <= 60 &&
          !_looksLikeUrl(loc)) {
        out.add(Need(
          name: 'event_navigation',
          tags: const [
            AppCapability.navigation,
            AppCapability.location,
          ],
          priority: 0.8,
          reason: 'Navigate to "${event.location}"',
        ));
      }

      // Generic upcoming event — calendar + minor note-taking nudge.
      out.add(Need(
        name: 'event_check',
        tags: const [
          AppCapability.calendar,
          AppCapability.scheduling,
        ],
        priority: 0.55,
        reason: '"$title" $when',
      ));
      out.add(Need(
        name: 'event_notes',
        tags: const [AppCapability.noteTaking],
        priority: 0.35,
        reason: 'Notes for "$title"',
      ));
    }
  }

  static bool _looksLikeUrl(String s) =>
      s.startsWith('http') || s.contains('://') || s.contains('zoom.us') ||
      s.contains('meet.google') || s.contains('teams.microsoft');

  // ---------------------------------------------------------------------------
  // Active notifications — the user has unread something. The notification
  // pill already surfaces the apps directly; this rule additionally biases
  // related capability classes (e.g. an email from the boss biases
  // "professional" / "calendar" alongside the email app itself).
  // ---------------------------------------------------------------------------

  static void _notificationRules(ContextSnapshot s, List<Need> out) {
    if (s.notifications.isEmpty) return;

    // Top notification dominates. Tier 1–2 = critical/personal, tier 3 = work,
    // tier 4 = social, tier 5 = reminders, tier 6 = utility.
    final top = s.notifications.first;
    final tier = top.tier;
    final senderHint = top.title.isNotEmpty ? ' from ${top.title}' : '';

    if (tier <= 2) {
      out.add(Need(
        name: 'reply_personal',
        tags: const [
          AppCapability.communication,
          AppCapability.messaging,
        ],
        priority: 0.95,
        reason: 'Unread message$senderHint',
      ));
    } else if (tier == 3) {
      out.add(Need(
        name: 'reply_work',
        tags: const [
          AppCapability.communication,
          AppCapability.email,
          AppCapability.professional,
        ],
        priority: 0.85,
        reason: 'Work notification$senderHint',
      ));
      out.add(Need(
        name: 'work_calendar',
        tags: const [AppCapability.calendar],
        priority: 0.4,
        reason: 'Sender may reference a meeting',
      ));
    } else if (tier == 4) {
      out.add(Need(
        name: 'reply_social',
        tags: const [AppCapability.social],
        priority: 0.65,
        reason: 'Social update$senderHint',
      ));
    } else if (tier == 5) {
      out.add(Need(
        name: 'reminder_action',
        tags: const [
          AppCapability.reminders,
          AppCapability.tasks,
          AppCapability.calendar,
        ],
        priority: 0.7,
        reason: 'Reminder${top.title.isNotEmpty ? ': ${top.title}' : ''}',
      ));
    } else {
      out.add(Need(
        name: 'utility_check',
        tags: const [AppCapability.utility],
        priority: 0.3,
        reason: 'Pending notification',
      ));
    }

    // A second notification of equal-or-higher priority piles on a slightly
    // smaller communication signal so a flurry of messages still ranks
    // chat apps highly even when the top tier is something else.
    if (s.notifications.length > 1) {
      final second = s.notifications[1];
      if (second.tier <= 4) {
        out.add(Need(
          name: 'reply_secondary',
          tags: const [
            AppCapability.communication,
            AppCapability.messaging,
          ],
          priority: 0.4,
          reason: '${s.notifications.length} unread items',
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Commute window: weekday morning/evening. Cellular-only is a strong
  // hint the user is out of the house. Wi-Fi at commute time is more likely
  // "still at home" or "just got to work" — handle both gently.
  // ---------------------------------------------------------------------------

  static void _commuteRules(ContextSnapshot s, List<Need> out) {
    if (!s.isWeekday) return;
    final h = s.hour;
    final isMorningCommute = h >= 7 && h < 10;
    final isEveningCommute = h >= 16 && h < 19;
    if (!isMorningCommute && !isEveningCommute) return;

    // Cellular without wi-fi → almost certainly mobile.
    final onTheGo = s.networkState == 'cellular';
    final reason = isMorningCommute ? 'Morning commute' : 'Evening commute';

    if (onTheGo) {
      out.add(Need(
        name: 'commute_navigation',
        tags: const [
          AppCapability.navigation,
          AppCapability.commute,
          AppCapability.transit,
          AppCapability.traffic,
        ],
        priority: 0.85,
        reason: reason,
      ));
      out.add(Need(
        name: 'commute_audio',
        tags: const [
          AppCapability.podcasts,
          AppCapability.audio,
          AppCapability.audiobooks,
        ],
        priority: 0.7,
        reason: '$reason — listen on the go',
      ));
      out.add(Need(
        name: 'commute_music',
        tags: const [AppCapability.music, AppCapability.audio],
        priority: 0.6,
        reason: '$reason soundtrack',
      ));
    } else {
      // Probably still at home / arrived. Lighter nudge.
      out.add(Need(
        name: 'commute_audio_soft',
        tags: const [
          AppCapability.podcasts,
          AppCapability.music,
          AppCapability.audio,
        ],
        priority: 0.4,
        reason: '$reason hours',
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Workday hours: weekday 9–5. Bias toward professional/productivity
  // capabilities even without a specific calendar event.
  // ---------------------------------------------------------------------------

  static void _workdayRules(ContextSnapshot s, List<Need> out) {
    if (!s.isWeekday) return;
    if (s.hour < 9 || s.hour >= 17) return;
    out.add(Need(
      name: 'workday',
      tags: const [
        AppCapability.professional,
        AppCapability.productivity,
        AppCapability.email,
        AppCapability.tasks,
      ],
      priority: 0.55,
      reason: 'Workday hours',
    ));
  }

  // ---------------------------------------------------------------------------
  // Evening: charging at home (wi-fi) suggests downtime. Lean entertainment
  // & social.
  // ---------------------------------------------------------------------------

  static void _eveningRules(ContextSnapshot s, List<Need> out) {
    final h = s.hour;
    if (h < 19 || h >= 23) return;

    final atHome = s.networkState == 'wifi';
    final priority = atHome ? 0.55 : 0.4;
    final reason = atHome ? 'Evening at home' : 'Evening hours';

    out.add(Need(
      name: 'evening_video',
      tags: const [
        AppCapability.video,
        AppCapability.streaming,
        AppCapability.entertainment,
      ],
      priority: priority,
      reason: reason,
    ));
    out.add(Need(
      name: 'evening_social',
      tags: const [AppCapability.social, AppCapability.entertainment],
      priority: priority - 0.15,
      reason: reason,
    ));
    out.add(Need(
      name: 'evening_reading',
      tags: const [
        AppCapability.reading,
        AppCapability.articles,
      ],
      priority: priority - 0.25,
      reason: reason,
    ));
  }

  // ---------------------------------------------------------------------------
  // Late night / wind-down: 11pm–4am. Lean reading, audio, meditation.
  // ---------------------------------------------------------------------------

  static void _windDownRules(ContextSnapshot s, List<Need> out) {
    final h = s.hour;
    if (h < 23 && h >= 4) return;
    out.add(Need(
      name: 'wind_down',
      tags: const [
        AppCapability.windDown,
        AppCapability.sleepTools,
        AppCapability.meditation,
        AppCapability.reading,
        AppCapability.audiobooks,
      ],
      priority: 0.5,
      reason: 'Late night — wind down',
    ));
    out.add(Need(
      name: 'late_alarm',
      tags: const [AppCapability.alarm, AppCapability.clock],
      priority: 0.4,
      reason: 'Set tomorrow\'s alarm',
    ));
  }

  // ---------------------------------------------------------------------------
  // Morning: weekday 6–9am. Bias toward news, email, calendar, weather.
  // ---------------------------------------------------------------------------

  static void _morningRules(ContextSnapshot s, List<Need> out) {
    final h = s.hour;
    if (h < 6 || h >= 9) return;

    out.add(Need(
      name: 'morning_news',
      tags: const [AppCapability.news, AppCapability.reading],
      priority: 0.6,
      reason: 'Morning catch-up',
    ));
    out.add(Need(
      name: 'morning_email',
      tags: const [AppCapability.email],
      priority: 0.7,
      reason: 'Morning inbox',
    ));
    out.add(Need(
      name: 'morning_calendar',
      tags: const [AppCapability.calendar, AppCapability.scheduling],
      priority: 0.55,
      reason: 'See today\'s schedule',
    ));
    out.add(Need(
      name: 'morning_weather',
      tags: const [AppCapability.weather],
      priority: 0.45,
      reason: 'Weather for today',
    ));
  }

  // ---------------------------------------------------------------------------
  // Battery: low + not charging → bias toward system/settings/utility so
  // power-saver shortcuts surface; high + charging → no specific need.
  // ---------------------------------------------------------------------------

  static void _batteryRules(ContextSnapshot s, List<Need> out) {
    if (s.batteryLevel >= 0 && s.batteryLevel < 20 && !s.isCharging) {
      out.add(Need(
        name: 'battery_low',
        tags: const [
          AppCapability.system,
          AppCapability.settings,
          AppCapability.utility,
        ],
        priority: 0.4,
        reason: 'Battery at ${s.batteryLevel}%',
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Weekend daytime: leisure-leaning bias.
  // ---------------------------------------------------------------------------

  static void _weekendRules(ContextSnapshot s, List<Need> out) {
    if (!s.isWeekend) return;
    final h = s.hour;
    if (h < 10 || h >= 19) return;

    out.add(Need(
      name: 'weekend_leisure',
      tags: const [
        AppCapability.entertainment,
        AppCapability.social,
        AppCapability.discovery,
        AppCapability.shopping,
        AppCapability.food,
      ],
      priority: 0.45,
      reason: 'Weekend afternoon',
    ));
    out.add(Need(
      name: 'weekend_outdoor',
      tags: const [
        AppCapability.navigation,
        AppCapability.location,
        AppCapability.discovery,
      ],
      priority: 0.35,
      reason: 'Plans / errands',
    ));
  }

  // ---------------------------------------------------------------------------
  // Session gap: long absence (came back from outside / break) →
  // catch-up bias; very fresh session is just a passing tap, no signal.
  // ---------------------------------------------------------------------------

  static void _sessionGapRules(ContextSnapshot s, List<Need> out) {
    if (s.sessionGapSeconds < 1800) return; // less than 30 min — no signal
    out.add(Need(
      name: 'catchup',
      tags: const [
        AppCapability.email,
        AppCapability.communication,
        AppCapability.social,
      ],
      priority: 0.35,
      reason: 'Just back to the device',
    ));
  }

  // ---------------------------------------------------------------------------
  // Previous app: very weak nudge — if the user just left a related app,
  // we keep the same capability class warm. Without history this would
  // lose nothing; with history it gives the rule engine a tiny continuity
  // signal so back-and-forth flows feel coherent.
  // ---------------------------------------------------------------------------

  static void _previousAppRules(ContextSnapshot s, List<Need> out) {
    final prev = s.previousApp;
    if (prev == null) return;
    final tags = AppCapabilityMap.tagsFor(prev);
    if (tags.isEmpty) return;
    out.add(Need(
      name: 'continuity',
      tags: tags,
      priority: 0.2,
      reason: 'Continue from previous app',
    ));
  }
}
