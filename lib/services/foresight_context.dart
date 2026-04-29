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

  /// Active audio output route. One of: 'speaker', 'wired_headphones',
  /// 'bluetooth', 'dock', 'unknown'. A non-speaker route is a strong
  /// signal the user wants audio playback.
  final String audioRoute;

  /// True if at least one Bluetooth audio sink (A2DP/SCO) is connected.
  final bool bluetoothAudioConnected;

  /// Best-effort name of the connected Bluetooth audio device — used to
  /// detect car contexts ("BMW", "Tesla", "Toyota", "MyCar", "SYNC").
  /// May be null on Android 12+ without BLUETOOTH_CONNECT.
  final String? bluetoothDeviceName;

  /// Best-effort current Wi-Fi SSID — used to detect car/work/home Wi-Fi
  /// from the network name (e.g. "Tesla Model 3", "Office", "Home Wifi").
  /// May be null without location permission or on locked networks.
  final String? wifiSsid;

  ContextSnapshot({
    required this.now,
    required this.batteryLevel,
    required this.isCharging,
    required this.networkState,
    required this.sessionGapSeconds,
    required this.previousApp,
    required this.todayEvents,
    required this.notifications,
    this.audioRoute = 'unknown',
    this.bluetoothAudioConnected = false,
    this.bluetoothDeviceName,
    this.wifiSsid,
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
    _calendarTextRules(s, needs);
    _notificationRules(s, needs);
    _audioOutputRules(s, needs);
    _carContextRules(s, needs);
    _commuteRules(s, needs);
    _workdayRules(s, needs);
    _eveningRules(s, needs);
    _windDownRules(s, needs);
    _morningRules(s, needs);
    _batteryRules(s, needs);
    _weekendRules(s, needs);
    _sessionGapRules(s, needs);
    _previousAppRules(s, needs);
    _baselineRules(s, needs);
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
    if (_hasDayOffEvent(s)) return;
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
    if (_hasDayOffEvent(s)) return;
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
  // Morning: 6–9am. Always surface weather + calendar + news. On weekdays
  // (without a day-off event) also surface email, work chat (Teams/Slack),
  // and time-clock / HR apps so the user can clock in and triage their
  // inbox while getting ready for work.
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

    // Work-prep bias: only on weekdays the user actually has to work.
    if (!s.isWeekday || _hasDayOffEvent(s)) return;

    out.add(Need(
      name: 'morning_email',
      tags: const [AppCapability.email],
      priority: 0.75,
      reason: 'Morning inbox before work',
    ));
    out.add(Need(
      name: 'morning_work_chat',
      tags: const [
        AppCapability.professional,
        AppCapability.communication,
        AppCapability.messaging,
      ],
      priority: 0.7,
      reason: 'Catch up on work chat',
    ));
    out.add(Need(
      name: 'morning_time_clock',
      tags: const [
        AppCapability.timeClock,
        AppCapability.hrPortal,
        AppCapability.professional,
      ],
      priority: 0.8,
      reason: 'Clock in / view shift',
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
  // Audio output: Bluetooth or wired headphones is a near-deterministic
  // signal that the user is about to listen to something. Rank music,
  // podcasts, and audiobooks high so the first thing they see in the
  // dock is what they actually want.
  // ---------------------------------------------------------------------------

  static void _audioOutputRules(ContextSnapshot s, List<Need> out) {
    // Any audio sink connected → user wants something that plays. We
    // emit one need per playback flavour so depth-of-match scoring still
    // ranks specialists (Spotify, Pocket Casts) above generalists, but
    // *any* app that plays media qualifies — the device name plays no
    // role in whether the rule fires.
    final isBt = s.audioRoute == 'bluetooth' || s.bluetoothAudioConnected;
    final isWired = s.audioRoute == 'wired_headphones';
    final isDock = s.audioRoute == 'dock';
    if (!isBt && !isWired && !isDock) return;

    final reason = isBt
        ? (s.bluetoothDeviceName != null && s.bluetoothDeviceName!.isNotEmpty
            ? 'Bluetooth: ${s.bluetoothDeviceName}'
            : 'Bluetooth audio connected')
        : isWired
            ? 'Headphones connected'
            : 'Docked';

    // Strength ladder: BT (most likely deliberate listening session) >
    // wired (intentional but lower commitment) > dock.
    final strength = isBt ? 1.0 : (isWired ? 0.85 : 0.65);

    out.add(Need(
      name: 'audio_music',
      tags: const [
        AppCapability.music,
        AppCapability.audio,
        AppCapability.streaming,
      ],
      priority: 0.95 * strength,
      reason: reason,
    ));
    out.add(Need(
      name: 'audio_video',
      tags: const [
        AppCapability.video,
        AppCapability.entertainment,
        AppCapability.streaming,
      ],
      priority: 0.85 * strength,
      reason: reason,
    ));
    out.add(Need(
      name: 'audio_spoken',
      tags: const [
        AppCapability.podcasts,
        AppCapability.audiobooks,
        AppCapability.audio,
      ],
      priority: 0.8 * strength,
      reason: reason,
    ));
    // Generic catch-all so any app tagged with `entertainment` or
    // `audio` gets a baseline lift even if it doesn't fall neatly into
    // the buckets above (e.g. SoundCloud, Twitch, Bandcamp).
    out.add(Need(
      name: 'audio_any',
      tags: const [
        AppCapability.audio,
        AppCapability.entertainment,
      ],
      priority: 0.6 * strength,
      reason: reason,
    ));
  }

  // ---------------------------------------------------------------------------
  // Car context: detect when the device is paired to a car via either
  // Bluetooth audio OR Wi-Fi SSID. Cars produce extremely identifiable
  // names ("BMW Bluetooth", "Tesla Model 3", "SYNC", "MyCar"). When that
  // happens we surface navigation + audio hard so the user gets Maps and
  // Spotify the moment they sit down.
  // ---------------------------------------------------------------------------

  static const List<String> _carHints = [
    // Generic
    'car', 'auto', 'drive', 'vehicle', 'truck', 'jeep', 'suv',
    'carplay', 'android auto', 'sync', 'uconnect', 'mybmw',
    // Brands
    'bmw', 'audi', 'mercedes', 'benz', 'toyota', 'honda', 'ford',
    'tesla', 'nissan', 'hyundai', 'kia', 'mazda', 'subaru', 'chevy',
    'chevrolet', 'gmc', 'volkswagen', ' vw', 'volvo', 'lexus',
    'porsche', 'acura', 'infiniti', 'cadillac', 'lincoln', 'dodge',
    'ram', 'rivian', 'polestar', 'lucid',
    // Common car-stereo brands
    'pioneer', 'kenwood', 'alpine', 'jbl link drive',
    // Common model names that uniquely imply a car
    'civic', 'corolla', 'camry', 'rav4', 'f150', 'silverado',
    'mustang', 'tacoma', 'altima', 'sentra', 'wrangler',
  ];

  static String? _matchCarName(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    for (final w in _carHints) {
      if (lower.contains(w)) return raw;
    }
    return null;
  }

  static void _carContextRules(ContextSnapshot s, List<Need> out) {
    final btMatch = _matchCarName(s.bluetoothDeviceName);
    final ssidMatch = _matchCarName(s.wifiSsid);
    if (btMatch == null && ssidMatch == null) return;

    final reason = btMatch != null
        ? 'Connected to "$btMatch"'
        : 'On "$ssidMatch" Wi-Fi';

    out.add(Need(
      name: 'car_navigation',
      tags: const [
        AppCapability.navigation,
        AppCapability.location,
        AppCapability.commute,
        AppCapability.traffic,
        AppCapability.transit,
      ],
      priority: 0.95,
      reason: reason,
    ));
    out.add(Need(
      name: 'car_music',
      tags: const [
        AppCapability.music,
        AppCapability.audio,
        AppCapability.entertainment,
      ],
      priority: 0.9,
      reason: reason,
    ));
    out.add(Need(
      name: 'car_podcasts',
      tags: const [
        AppCapability.podcasts,
        AppCapability.audiobooks,
        AppCapability.audio,
      ],
      priority: 0.75,
      reason: reason,
    ));
  }

  // ---------------------------------------------------------------------------
  // Baseline: no matter what time it is, the user might want to text,
  // call, or look something up. A small constant hum of communication +
  // browser keeps the dock from collapsing into a single category when
  // every other rule happens to fire on the same tag bucket (the classic
  // "10am workday → only Docs/Drive/Keep" failure mode).
  // ---------------------------------------------------------------------------

  static void _baselineRules(ContextSnapshot s, List<Need> out) {
    out.add(Need(
      name: 'baseline_comm',
      tags: const [
        AppCapability.communication,
        AppCapability.messaging,
        AppCapability.phone,
      ],
      priority: 0.20,
      reason: 'Stay connected',
    ));
    out.add(Need(
      name: 'baseline_web',
      tags: const [
        AppCapability.browser,
        AppCapability.search,
      ],
      priority: 0.15,
      reason: 'Quick lookups',
    ));
    out.add(Need(
      name: 'baseline_capture',
      tags: const [
        AppCapability.camera,
        AppCapability.gallery,
        AppCapability.photos,
      ],
      priority: 0.10,
      reason: 'Capture / review',
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

  // ---------------------------------------------------------------------------
  // Day-off detection. Scans today's events (and reminders, which Android
  // surfaces as calendar events) for any all-day or full-workday item whose
  // text describes the user *not* working. Used to suppress work-related
  // morning, commute, and workday biases so the launcher doesn't push the
  // inbox / Teams / time-clock at someone on PTO.
  // ---------------------------------------------------------------------------

  static const List<String> _dayOffPhrases = [
    'day off', 'days off', 'off work', 'off today',
    'pto', 'paid time off', 'time off',
    'vacation', 'holiday', 'sick day', 'sick leave',
    'out of office', 'ooo',
    'personal day', 'mental health day',
    'no work', 'not working', 'work cancel',
    'bereavement', 'jury duty',
    'maternity', 'paternity', 'parental leave',
  ];

  static bool _hasDayOffEvent(ContextSnapshot s) {
    if (s.todayEvents.isEmpty) return false;
    for (final event in s.todayEvents) {
      // A 4-hour-or-longer block during work hours counts even without
      // allDay; an "off work — flying out at 11" event still means no job.
      final lengthMs = event.end - event.begin;
      final coversWorkday = event.allDay || lengthMs >= 4 * 60 * 60 * 1000;
      if (!coversWorkday) continue;

      final haystack =
          ('${event.title} ${event.description}').toLowerCase();
      for (final phrase in _dayOffPhrases) {
        if (haystack.contains(phrase)) return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Calendar / reminder text scan. Reads every event today (allDay events
  // and reminders included — Android sync providers surface tasks the same
  // way) and infers what action the user is being told to do, then biases
  // the matching app capability. This lets a reminder titled "text mom
  // about dinner" surface the messaging app, "send draft to Michael" the
  // email app, "pay rent" the banking app, and so on.
  //
  // Matches are additive: a single event can trigger several biases (e.g.
  // "drive to airport — bring boarding pass" lifts navigation AND travel).
  // Priority is moderate — strong enough to outrank generic time-of-day
  // bias, weak enough that an imminent meeting still wins.
  // ---------------------------------------------------------------------------

  static void _calendarTextRules(ContextSnapshot s, List<Need> out) {
    if (s.todayEvents.isEmpty) return;
    final nowMs = s.now.millisecondsSinceEpoch;

    for (final event in s.todayEvents) {
      final title = event.title;
      final text = ('$title ${event.description}').toLowerCase();
      if (text.trim().isEmpty) continue;

      // Recency weight: imminent / current events outweigh later-today
      // ones, all-day items get a flat mid weight. Past-and-done events
      // are skipped entirely.
      final minsToStart = ((event.begin - nowMs) / 60000).round();
      final minsToEnd = ((event.end - nowMs) / 60000).round();
      double recency;
      if (event.allDay) {
        recency = 0.7;
      } else if (minsToEnd < -30) {
        continue; // event finished more than 30 min ago — stale
      } else if (minsToStart <= 0 && minsToEnd > 0) {
        recency = 1.0; // happening now
      } else if (minsToStart > 0 && minsToStart <= 60) {
        recency = 0.95;
      } else if (minsToStart > 0 && minsToStart <= 240) {
        recency = 0.75;
      } else {
        recency = 0.55;
      }

      final reason = title.isEmpty ? 'Reminder' : 'Reminder: "$title"';

      void emit(String name, List<String> tags, double base) {
        out.add(Need(
          name: name,
          tags: tags,
          priority: (base * recency).clamp(0.0, 1.0),
          reason: reason,
        ));
      }

      // -- Messaging --------------------------------------------------------
      // "text mom", "message dave", "tell sarah", "dm them", "send sms"
      if (_anyMatch(text, const [
        'text ', 'text mom', 'text dad', 'text her', 'text him',
        'message ', ' msg ', 'msg ',
        'tell ', 'ping ', 'dm ', ' dm ', 'send a text', 'shoot a text',
        'sms ', 'imessage', 'whatsapp', 'snap ', 'snapchat',
      ])) {
        emit('reminder_message', const [
          AppCapability.messaging,
          AppCapability.communication,
          AppCapability.sms,
        ], 0.85);
      }

      // -- Phone call -------------------------------------------------------
      if (_anyMatch(text, const [
        'call ', 'phone ', 'ring ', 'give a call', 'give them a call',
        'voicemail', 'callback', 'call back',
      ])) {
        emit('reminder_call', const [
          AppCapability.phone,
          AppCapability.communication,
        ], 0.85);
      }

      // -- Email ------------------------------------------------------------
      // "send draft to michael", "email professor", "reply to boss",
      // "follow up with X", "forward the report".
      if (_anyMatch(text, const [
        'email', 'e-mail', 'inbox',
        'send draft', 'send the draft', 'send draft to',
        'reply to', 'respond to', 'follow up', 'follow-up', 'followup',
        'forward ', 'cc ', 'bcc ',
        'send to ', 'send report', 'send the ',
      ])) {
        emit('reminder_email', const [
          AppCapability.email,
          AppCapability.communication,
          AppCapability.professional,
        ], 0.85);
      }

      // -- Video / work meeting --------------------------------------------
      if (_anyMatch(text, const [
        'zoom', 'teams call', 'webex', 'google meet', 'meet link',
        'video call', 'video chat', 'facetime', 'huddle',
      ])) {
        emit('reminder_videocall', const [
          AppCapability.videoCall,
          AppCapability.meeting,
          AppCapability.conference,
        ], 0.9);
      }

      // -- Time clock / HR --------------------------------------------------
      if (_anyMatch(text, const [
        'clock in', 'clock-in', 'clock out', 'clock-out',
        'punch in', 'punch out', 'shift start', 'start shift',
        'timesheet', 'time sheet', 'submit hours', 'log hours',
        'request pto', 'request time off', 'pay stub', 'paystub',
        'view schedule', 'check schedule',
      ])) {
        emit('reminder_timeclock', const [
          AppCapability.timeClock,
          AppCapability.hrPortal,
          AppCapability.professional,
        ], 0.9);
      }

      // -- Notes / write-up -------------------------------------------------
      if (_anyMatch(text, const [
        'write ', 'write up', 'write-up', 'jot ', 'note ', 'take notes',
        'draft ', 'outline ', 'brainstorm',
      ])) {
        emit('reminder_notes', const [
          AppCapability.noteTaking,
          AppCapability.productivity,
        ], 0.7);
      }

      // -- Tasks / todo / reminders ----------------------------------------
      if (_anyMatch(text, const [
        'todo', 'to-do', 'to do', 'task ', 'checklist', 'finish ',
        'complete ', 'submit ', 'turn in',
      ])) {
        emit('reminder_tasks', const [
          AppCapability.tasks,
          AppCapability.reminders,
          AppCapability.productivity,
        ], 0.7);
      }

      // -- Documents -------------------------------------------------------
      if (_anyMatch(text, const [
        'review doc', 'review the doc', 'sign ', 'docusign',
        'spreadsheet', 'slide deck', 'slides for', 'powerpoint',
        'word doc', 'pdf', 'contract', 'proposal',
      ])) {
        emit('reminder_docs', const [
          AppCapability.documentEditing,
          AppCapability.productivity,
          AppCapability.professional,
        ], 0.75);
      }

      // -- Navigation / location -------------------------------------------
      if (_anyMatch(text, const [
        'drive to', 'drive ', 'pick up', 'pick-up', 'drop off', 'drop-off',
        'meet at', 'meet @', 'go to ', 'head to', 'heading to',
        'visit ', 'stop by', 'commute',
      ])) {
        emit('reminder_navigation', const [
          AppCapability.navigation,
          AppCapability.location,
          AppCapability.commute,
        ], 0.8);
      }

      // -- Rideshare / transit ---------------------------------------------
      if (_anyMatch(text, const [
        'uber', 'lyft', 'taxi', 'cab ', 'rideshare',
        'subway', 'bus to', 'train to', 'transit',
      ])) {
        emit('reminder_rideshare', const [
          AppCapability.rideshare,
          AppCapability.transit,
          AppCapability.commute,
        ], 0.8);
      }

      // -- Travel / flights ------------------------------------------------
      if (_anyMatch(text, const [
        'flight', 'airport', 'check in', 'check-in', 'boarding',
        'pack ', 'packing', 'hotel', 'airbnb', 'reservation',
        'tsa', 'passport', 'gate ',
      ])) {
        emit('reminder_travel', const [
          AppCapability.travel,
          AppCapability.flights,
        ], 0.8);
      }

      // -- Camera / photos -------------------------------------------------
      if (_anyMatch(text, const [
        'photo', 'picture', 'pic of', 'snap a', 'take a pic', 'selfie',
        'screenshot', 'scan ',
      ])) {
        emit('reminder_camera', const [
          AppCapability.camera,
          AppCapability.photography,
        ], 0.7);
      }

      // -- Banking / payments ----------------------------------------------
      if (_anyMatch(text, const [
        'pay bill', 'pay bills', 'pay rent', 'pay back', 'venmo ',
        'zelle ', 'cashapp', 'transfer money', 'wire ', 'deposit ',
        'invoice', 'tax', 'payroll',
      ])) {
        emit('reminder_banking', const [
          AppCapability.banking,
          AppCapability.finance,
          AppCapability.payments,
        ], 0.8);
      }

      // -- Shopping --------------------------------------------------------
      if (_anyMatch(text, const [
        'buy ', 'order ', 'purchase', 'amazon', 'pick up groceries',
        'grocer', 'shopping list', 'walmart', 'target', 'costco',
        'returns ', 'return the',
      ])) {
        emit('reminder_shopping', const [
          AppCapability.shopping,
          AppCapability.discovery,
        ], 0.7);
      }

      // -- Food / delivery --------------------------------------------------
      if (_anyMatch(text, const [
        'lunch', 'dinner', 'breakfast', 'brunch', 'coffee',
        'order food', 'doordash', 'ubereats', 'grubhub',
        'restaurant', 'reservation at', 'reserve a table',
      ])) {
        emit('reminder_food', const [
          AppCapability.food,
          AppCapability.restaurants,
          AppCapability.delivery,
        ], 0.7);
      }

      // -- Fitness / health ------------------------------------------------
      if (_anyMatch(text, const [
        'gym', 'workout', 'work out', 'lift ', 'yoga', 'pilates',
        'cardio', 'run ', 'jog ', 'walk ', 'hike',
        'doctor', 'dentist', 'physical', 'checkup', 'check-up',
        'appointment',
      ])) {
        emit('reminder_fitness', const [
          AppCapability.fitness,
          AppCapability.health,
          AppCapability.running,
        ], 0.75);
      }

      // -- Meditation / wind down ------------------------------------------
      if (_anyMatch(text, const [
        'meditate', 'meditation', 'breathe', 'breathing',
        'mindfulness', 'relax', 'wind down', 'wind-down',
      ])) {
        emit('reminder_meditation', const [
          AppCapability.meditation,
          AppCapability.windDown,
          AppCapability.sleepTools,
        ], 0.7);
      }

      // -- Reading / books / news ------------------------------------------
      if (_anyMatch(text, const [
        'read ', 'reading', 'finish book', 'chapter ', 'article',
        'news', 'blog ', 'newsletter',
      ])) {
        emit('reminder_reading', const [
          AppCapability.reading,
          AppCapability.articles,
          AppCapability.books,
        ], 0.65);
      }

      // -- Music / audio ---------------------------------------------------
      if (_anyMatch(text, const [
        'playlist', 'spotify', 'apple music', 'listen to',
        'podcast', 'audiobook',
      ])) {
        emit('reminder_audio', const [
          AppCapability.music,
          AppCapability.audio,
          AppCapability.podcasts,
          AppCapability.audiobooks,
        ], 0.7);
      }

      // -- Calendar / scheduling -------------------------------------------
      if (_anyMatch(text, const [
        'schedule ', 'reschedule', 'book ', 'appointment',
        'set up a meeting', 'find a time',
      ])) {
        emit('reminder_calendar', const [
          AppCapability.calendar,
          AppCapability.scheduling,
        ], 0.65);
      }

      // -- Education / school -----------------------------------------------
      if (_anyMatch(text, const [
        'homework', 'assignment', 'study ', 'studying', 'exam ',
        'midterm', 'final', 'quiz', 'lecture', 'class ', 'lab ',
        'canvas', 'blackboard', 'moodle', 'professor',
      ])) {
        emit('reminder_education', const [
          AppCapability.education,
          AppCapability.campusPortal,
          AppCapability.lectureCompanion,
          AppCapability.noteTaking,
        ], 0.8);
      }
    }
  }

  static bool _anyMatch(String haystack, List<String> needles) {
    for (final n in needles) {
      if (haystack.contains(n)) return true;
    }
    return false;
  }
}
