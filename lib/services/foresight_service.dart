// Foresight — need-driven app surfacing for the CASI launcher.
//
// The dock no longer predicts from launch history. It reasons:
//
//   "What does the user need right now?"  — inferred from real-world
//                                            signals (calendar, time,
//                                            notifications, network,
//                                            charging, battery, …).
//   "Which app satisfies that need?"      — matched against a structured
//                                            capability knowledge base.
//
// Two clean pieces sit behind this service:
//
//  * [ContextInterpreter] (foresight_context.dart) — a pure rule engine
//    that maps a [ContextSnapshot] of every signal we can read into a
//    list of semantic [Need]s, each with a priority and a reason.
//
//  * [AppCapabilityMap] (foresight_capabilities.dart) — a hand-curated
//    map from package name patterns to capability tags ("Spotify →
//    music, audio, podcasts; Google Maps → navigation, commute").
//
// [predict] scores every installed app by summing the priorities of the
// needs whose tags overlap that app's capabilities, then returns the
// top candidates. This is genuinely non-frequency: a freshly-installed
// app the user has never opened can rank #1 if context demands its
// capability and no other installed app supplies it.
//
// Upgrade path: replace [ContextInterpreter.interpret] with an LLM
// (e.g. Gemma 4) that emits the same `List<Need>`. The capability map
// and matching logic don't change.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';

import '../morning_brief/calendar_brief_service.dart';
import 'foresight_capabilities.dart';
import 'foresight_context.dart';
import 'notification_pill_service.dart';

// ---------------------------------------------------------------------------
// Data model — kept compatible with the consuming UI (foresight_pill.dart,
// home_info_bar.dart). Only [reason] is new; old persistence-related
// fields (dbId) are gone since there is no database any more.
// ---------------------------------------------------------------------------

class ForesightPrediction {
  final String packageName;
  final String appName;
  final Uint8List? icon;

  /// 0.0 – 1.0. Currently the highest-scoring app gets 1.0 and everything
  /// else is its score divided by the max.
  final double confidence;

  /// Human-readable explanation surfaced from the highest-priority need
  /// that matched this app, e.g. "Lecture starts in 12 min" or
  /// "Morning commute". Useful for debugging and future UI labels.
  final String? reason;

  ForesightPrediction({
    required this.packageName,
    required this.appName,
    this.icon,
    required this.confidence,
    this.reason,
  });
}

// ---------------------------------------------------------------------------
// ForesightService — singleton.
// ---------------------------------------------------------------------------

class ForesightService {
  static final ForesightService instance = ForesightService._internal();
  factory ForesightService() => instance;
  ForesightService._internal();

  static const _deviceChannel = MethodChannel('casi.launcher/device');

  // --- Session state (in-memory only — no persistence) ----------------------
  DateTime? _lastPauseTime;
  String? _lastSessionPackage; // dedup within a session
  String? _previousApp;        // last app launched
  int _currentSessionGap = 7200;
  List<ForesightPrediction> _currentPredictions = [];
  bool _initialized = false;

  // --- Calendar caching -----------------------------------------------------
  // Calendar reads cross a method channel and hit the system calendar
  // provider; refreshing on every 3-second poll would be wasteful.
  static const Duration _calendarTtl = Duration(minutes: 2);
  List<DeviceCalendarEvent> _cachedEvents = const [];
  DateTime? _lastCalendarFetch;

  // --- Prediction caching ---------------------------------------------------
  // The rule engine itself is cheap, but several inputs (calendar, time
  // bucket, notification set) change slowly. A short-lived cache keyed
  // off a coarse signature avoids redundant scoring on rapid polls.
  static const Duration _predictionTtl = Duration(seconds: 10);
  String? _lastSignature;
  DateTime? _lastPredictAt;

  List<ForesightPrediction> get currentPredictions => _currentPredictions;
  bool get isInitialized => _initialized;

  /// Total number of needs the rule engine produced on the most recent
  /// [predict] call. Exposed for diagnostics; the UI doesn't use it.
  int get lastNeedCount => _lastNeedCount;
  int _lastNeedCount = 0;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// No-op besides flipping the initialized flag — the rule engine is
  /// stateless and the capability map is compile-time. Kept async to
  /// preserve the previous public signature so callers don't change.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    debugPrint('[Foresight] Initialized (rule-engine, no model).');
  }

  /// Called when the launcher is paused (user leaves the home screen).
  void onPause() {
    _lastPauseTime = DateTime.now();
  }

  /// Called when the launcher resumes (user returns).
  void onResume() {
    _lastSessionPackage = null;
    _currentSessionGap = _lastPauseTime != null
        ? DateTime.now().difference(_lastPauseTime!).inSeconds
        : 7200;
    // Force the next predict() call to recompute since session-gap is a
    // rule input.
    _lastSignature = null;
  }

  // -------------------------------------------------------------------------
  // Recording — only the in-memory continuity hint matters now. There is
  // no database, no learning, no feedback loop. This method exists purely
  // so existing call-sites don't have to change.
  // -------------------------------------------------------------------------

  Future<void> recordLaunch(String packageName, {String? appName}) async {
    if (_lastSessionPackage == packageName) return;
    _previousApp = packageName;
    _lastSessionPackage = packageName;
    _lastSignature = null; // continuity rule depends on previous app
  }

  /// Clear any stored state for a package (e.g. on uninstall). With no
  /// persistent store this just nulls out the in-memory continuity hint
  /// if it pointed at the now-gone app.
  Future<void> purgeApp(String packageName) async {
    if (_previousApp == packageName) _previousApp = null;
    _currentPredictions.removeWhere((p) => p.packageName == packageName);
    _lastSignature = null;
  }

  // -------------------------------------------------------------------------
  // Prediction
  // -------------------------------------------------------------------------

  /// Build a list of app suggestions for the current moment.
  ///
  /// Returns up to 15 predictions so the dock has runners-up after
  /// filtering out apps already shown in the home dock or notification
  /// pills. The dock UI picks the top N to display.
  Future<List<ForesightPrediction>> predict(List<AppInfo> installedApps) async {
    if (installedApps.isEmpty) return const [];

    try {
      final snapshot = await _gatherSnapshot();
      final signature = _buildSignature(snapshot);

      // Quick path: identical signature within TTL → reuse last result.
      final age = _lastPredictAt == null
          ? null
          : snapshot.now.difference(_lastPredictAt!);
      if (signature == _lastSignature &&
          age != null &&
          age < _predictionTtl &&
          _currentPredictions.isNotEmpty) {
        return _currentPredictions;
      }

      final needs = ContextInterpreter.interpret(snapshot);
      _lastNeedCount = needs.length;

      if (needs.isEmpty) {
        _currentPredictions = const [];
        _lastSignature = signature;
        _lastPredictAt = snapshot.now;
        return const [];
      }

      final predictions = _scoreApps(installedApps, needs);

      _currentPredictions = predictions;
      _lastSignature = signature;
      _lastPredictAt = snapshot.now;

      if (kDebugMode) {
        final summary = predictions
            .take(5)
            .map((p) =>
                '${p.appName}(${p.confidence.toStringAsFixed(2)})')
            .join(', ');
        final needsSummary =
            needs.map((n) => '${n.name}@${n.priority.toStringAsFixed(2)}')
                .join(', ');
        debugPrint('[Foresight] needs=[$needsSummary]');
        debugPrint('[Foresight] picks=[$summary]');
      }
      return predictions;
    } catch (e, st) {
      debugPrint('[Foresight] predict error: $e\n$st');
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // Scoring
  // -------------------------------------------------------------------------

  /// Score every installed app by summing the priorities of the needs
  /// whose capability tags overlap the app's capability tags. Returns
  /// the top candidates sorted by descending score.
  List<ForesightPrediction> _scoreApps(
    List<AppInfo> installedApps,
    List<Need> needs,
  ) {
    final scores = <String, double>{};
    final topReason = <String, String>{};
    final topReasonPriority = <String, double>{};

    for (final app in installedApps) {
      final tags = AppCapabilityMap.tagsFor(app.packageName);
      if (tags.isEmpty) continue;
      final tagSet = tags.toSet();

      double total = 0.0;
      double bestPriority = 0.0;
      String bestReason = '';

      for (final need in needs) {
        // Need is satisfied if any of its tags is among the app's tags.
        bool matched = false;
        for (final t in need.tags) {
          if (tagSet.contains(t)) {
            matched = true;
            break;
          }
        }
        if (!matched) continue;

        total += need.priority;
        if (need.priority > bestPriority) {
          bestPriority = need.priority;
          bestReason = need.reason;
        }
      }

      if (total > 0.0) {
        scores[app.packageName] = total;
        topReason[app.packageName] = bestReason;
        topReasonPriority[app.packageName] = bestPriority;
      }
    }

    if (scores.isEmpty) return const [];

    // Resolve AppInfo for each scored package once.
    final appMap = <String, AppInfo>{};
    for (final a in installedApps) {
      appMap[a.packageName] = a;
    }

    final maxScore =
        scores.values.fold<double>(0.0, (a, b) => b > a ? b : a);

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top = sorted.take(15).toList();

    return [
      for (final entry in top)
        ForesightPrediction(
          packageName: entry.key,
          appName: appMap[entry.key]!.name,
          icon: appMap[entry.key]!.icon,
          confidence: maxScore > 0 ? entry.value / maxScore : 0.0,
          reason: topReason[entry.key],
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // Snapshot assembly
  // -------------------------------------------------------------------------

  Future<ContextSnapshot> _gatherSnapshot() async {
    final now = DateTime.now();

    // Fan out the I/O-bound fetches in parallel; they're independent.
    final results = await Future.wait([
      _fetchDeviceContext(),
      _fetchTodayEvents(now),
      _fetchActiveNotifications(),
    ]);

    final device = results[0] as Map<String, dynamic>;
    final events = results[1] as List<DeviceCalendarEvent>;
    final notifs = results[2] as List<NotificationPillEntry>;

    return ContextSnapshot(
      now: now,
      batteryLevel: (device['batteryLevel'] as int?) ?? -1,
      isCharging: device['isCharging'] == true,
      networkState: (device['networkState'] as String?) ?? 'unknown',
      sessionGapSeconds: _currentSessionGap,
      previousApp: _previousApp,
      todayEvents: events,
      notifications: notifs,
    );
  }

  Future<Map<String, dynamic>> _fetchDeviceContext() async {
    try {
      final result = await _deviceChannel
          .invokeMapMethod<String, dynamic>('getDeviceContext');
      return result ??
          {
            'batteryLevel': -1,
            'isCharging': false,
            'networkState': 'unknown',
          };
    } catch (e) {
      debugPrint('[Foresight] device fetch error: $e');
      return {
        'batteryLevel': -1,
        'isCharging': false,
        'networkState': 'unknown',
      };
    }
  }

  Future<List<DeviceCalendarEvent>> _fetchTodayEvents(DateTime now) async {
    if (_lastCalendarFetch != null &&
        now.difference(_lastCalendarFetch!) < _calendarTtl) {
      return _cachedEvents;
    }
    try {
      final brief = await CalendarBriefService.instance.getTodayEvents();
      _cachedEvents = brief.events;
      _lastCalendarFetch = now;
      return _cachedEvents;
    } catch (e) {
      debugPrint('[Foresight] calendar fetch error: $e');
      return _cachedEvents;
    }
  }

  Future<List<NotificationPillEntry>> _fetchActiveNotifications() async {
    try {
      return await NotificationPillService.getNotificationPillApps();
    } catch (e) {
      debugPrint('[Foresight] notification fetch error: $e');
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // Cache signature
  // -------------------------------------------------------------------------

  /// A coarse fingerprint of the snapshot's rule-relevant inputs. Two
  /// snapshots that hash identically will produce the same set of needs
  /// and the same ranking.
  String _buildSignature(ContextSnapshot s) {
    final hour = s.hour;
    final timeBucket = hour < 6
        ? 'night'
        : hour < 9
            ? 'morning'
            : hour < 12
                ? 'late_morning'
                : hour < 17
                    ? 'afternoon'
                    : hour < 19
                        ? 'commute_pm'
                        : hour < 23
                            ? 'evening'
                            : 'late';
    final batteryBucket = s.batteryLevel < 0
        ? 'na'
        : s.batteryLevel < 20
            ? 'low'
            : s.batteryLevel > 80
                ? 'high'
                : 'mid';
    final notifKey = s.notifications.isEmpty
        ? 'none'
        : '${s.notifications.first.packageName}#${s.notifications.first.tier}';
    final eventKey = s.todayEvents.isEmpty
        ? 'none'
        : s.todayEvents
            .where((e) =>
                ((e.begin - s.now.millisecondsSinceEpoch) / 60000).round() <=
                    60 &&
                e.end > s.now.millisecondsSinceEpoch)
            .map((e) => '${e.title}@${e.begin}')
            .join('|');
    return '$timeBucket|${s.now.weekday}|${s.networkState}|'
        '${s.isCharging}|$batteryBucket|${s.previousApp ?? "_"}|'
        '${s.sessionGapSeconds > 1800 ? "fresh" : "warm"}|'
        '$notifKey|$eventKey';
  }
}
