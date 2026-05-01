// Foresight — user-rule-driven app surfacing for the CASI launcher.
//
// The dock surfaces exactly the apps the user has configured via schedule
// and scenario rules in settings. No capability scoring, no categorization,
// no automatic context inference — only what the user explicitly set up.
//
// If the user has no rules active right now, no apps are shown.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';

import '../morning_brief/calendar_brief_service.dart';
import 'foresight_context.dart';
import 'foresight_user_rules.dart';

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

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await ForesightUserRulesService.instance.load();
    debugPrint('[Foresight] Initialized.');
  }

  /// Force the next [predict] call to re-score even if the snapshot
  /// signature hasn't changed — used after user rules are edited.
  void invalidateCache() => _lastSignature = null;

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
  // Recording — no persistence, kept so call-sites don't need changing.
  // -------------------------------------------------------------------------

  Future<void> recordLaunch(String packageName, {String? appName}) async {
    if (_lastSessionPackage == packageName) return;
    _previousApp = packageName;
    _lastSessionPackage = packageName;
    _lastSignature = null;
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

  /// Returns apps whose user-configured schedule or scenario rules match now.
  /// If no rules are active, returns an empty list and the dock hides itself.
  Future<List<ForesightPrediction>> predict(List<AppInfo> installedApps) async {
    if (installedApps.isEmpty) return const [];

    try {
      final snapshot = await _gatherSnapshot();
      final signature = _buildSignature(snapshot);

      final age = _lastPredictAt == null
          ? null
          : snapshot.now.difference(_lastPredictAt!);
      if (signature == _lastSignature &&
          age != null &&
          age < _predictionTtl) {
        return _currentPredictions;
      }

      final predictions = _applyUserRules(installedApps, snapshot);

      _currentPredictions = predictions;
      _lastSignature = signature;
      _lastPredictAt = snapshot.now;

      if (kDebugMode) {
        final summary = predictions
            .map((p) => p.appName)
            .join(', ');
        debugPrint('[Foresight] user-rule picks=[$summary]');
      }
      return predictions;
    } catch (e, st) {
      debugPrint('[Foresight] predict error: $e\n$st');
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // User-rule matching
  // -------------------------------------------------------------------------

  /// Returns predictions for every schedule/scenario rule that matches now.
  /// If no rules are active, returns an empty list.
  List<ForesightPrediction> _applyUserRules(
    List<AppInfo> installedApps,
    ContextSnapshot snapshot,
  ) {
    final matched = ForesightUserRulesService.instance
        .matchNow(snapshot.now, snapshot);
    if (matched.isEmpty) return const [];

    final appMap = <String, AppInfo>{
      for (final a in installedApps) a.packageName: a,
    };

    final result = <ForesightPrediction>[];
    for (final m in matched) {
      final app = appMap[m.packageName];
      if (app == null) continue;
      result.add(ForesightPrediction(
        packageName: m.packageName,
        appName: app.name,
        icon: app.icon,
        confidence: 1.0,
        reason: m.reason,
      ));
    }
    return result;
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
    ]);

    final device = results[0] as Map<String, dynamic>;
    final events = results[1] as List<DeviceCalendarEvent>;

    return ContextSnapshot(
      now: now,
      batteryLevel: (device['batteryLevel'] as int?) ?? -1,
      isCharging: device['isCharging'] == true,
      networkState: (device['networkState'] as String?) ?? 'unknown',
      sessionGapSeconds: _currentSessionGap,
      previousApp: _previousApp,
      todayEvents: events,
      audioRoute: (device['audioRoute'] as String?) ?? 'unknown',
      bluetoothAudioConnected: device['bluetoothAudioConnected'] == true,
      bluetoothDeviceName: device['bluetoothDeviceName'] as String?,
      wifiSsid: device['wifiSsid'] as String?,
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
    final eventKey = s.todayEvents.isEmpty
        ? 'none'
        : s.todayEvents
            .where((e) =>
                ((e.begin - s.now.millisecondsSinceEpoch) / 60000).round() <=
                    60 &&
                e.end > s.now.millisecondsSinceEpoch)
            .map((e) => '${e.title}@${e.begin}')
            .join('|');
    // New context fields are part of the cache key so that plugging in
    // headphones, connecting Bluetooth, or joining a different Wi-Fi
    // immediately invalidates the cached prediction and re-runs the
    // rule engine on the next poll.
    return '$timeBucket|${s.now.weekday}|${s.networkState}|'
        '${s.isCharging}|$batteryBucket|${s.previousApp ?? "_"}|'
        '${s.sessionGapSeconds > 1800 ? "fresh" : "warm"}|'
        '$eventKey|'
        '${s.audioRoute}|${s.bluetoothDeviceName ?? "_"}|'
        '${s.wifiSsid ?? "_"}';
  }
}
