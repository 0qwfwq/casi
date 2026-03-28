// Foresight — contextual app prediction engine for the CASI launcher.
//
// Records every app launch with rich metadata (time, day, session gap,
// previous app, network, battery, charging) into a local SQLite database.
// On each unlock, scores all candidate apps using a tiered variable-
// importance model and returns exactly three predictions.
//
// Storage: 30-day rolling window, duplicate launches within a session
// are collapsed, all I/O is asynchronous so launch performance is
// never affected.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class ForesightPrediction {
  final String packageName;
  final String appName;
  final Uint8List? icon;
  final double confidence;
  int? dbId;

  ForesightPrediction({
    required this.packageName,
    required this.appName,
    this.icon,
    required this.confidence,
    this.dbId,
  });
}

// ---------------------------------------------------------------------------
// ForesightService — singleton
// ---------------------------------------------------------------------------

class ForesightService {
  static final ForesightService instance = ForesightService._internal();
  factory ForesightService() => instance;
  ForesightService._internal();

  static const _deviceChannel = MethodChannel('casi.launcher/device');

  Database? _db;
  DateTime? _lastPauseTime;
  String? _lastSessionPackage; // dedup within a session
  String? _previousApp; // last app opened (persisted across sessions)
  int _currentSessionGap = 7200; // seconds since last unlock
  List<ForesightPrediction> _currentPredictions = [];
  bool _initialized = false;

  List<ForesightPrediction> get currentPredictions => _currentPredictions;
  bool get isInitialized => _initialized;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final foresightDir = Directory(p.join(dir.path, 'foresight'));
      if (!foresightDir.existsSync()) {
        foresightDir.createSync(recursive: true);
      }
      final dbPath = p.join(foresightDir.path, 'foresight.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS launches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              package_name TEXT NOT NULL,
              app_name TEXT,
              timestamp TEXT NOT NULL,
              hour INTEGER NOT NULL,
              day_of_week INTEGER NOT NULL,
              session_gap_seconds INTEGER NOT NULL DEFAULT 0,
              previous_app TEXT,
              network_state TEXT NOT NULL DEFAULT 'unknown',
              battery_level INTEGER NOT NULL DEFAULT -1,
              charging_state INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS predictions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT NOT NULL,
              rank INTEGER NOT NULL,
              predicted_package TEXT NOT NULL,
              was_opened INTEGER DEFAULT NULL,
              feedback_timestamp TEXT
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_launches_hour ON launches(hour)');
          await db.execute(
              'CREATE INDEX idx_launches_dow ON launches(day_of_week)');
          await db.execute(
              'CREATE INDEX idx_launches_prev ON launches(previous_app)');
          await db.execute(
              'CREATE INDEX idx_launches_ts ON launches(timestamp)');
          await db.execute(
              'CREATE INDEX idx_pred_pkg ON predictions(predicted_package)');
        },
      );

      _initialized = true;
      await _loadLastApp();
      unawaited(_pruneOldData());
      debugPrint('[Foresight] Initialized.');
    } catch (e) {
      debugPrint('[Foresight] Init error: $e');
    }
  }

  /// Called when the launcher is paused (user leaves).
  void onPause() {
    _lastPauseTime = DateTime.now();
  }

  /// Called when the launcher is resumed (user unlocks / returns).
  void onResume() {
    _lastSessionPackage = null;
    _currentSessionGap = _lastPauseTime != null
        ? DateTime.now().difference(_lastPauseTime!).inSeconds
        : 7200;
  }

  // -------------------------------------------------------------------------
  // Recording
  // -------------------------------------------------------------------------

  /// Record an app launch with full contextual metadata.
  /// Duplicate launches within the same session are collapsed.
  Future<void> recordLaunch(String packageName, {String? appName}) async {
    if (_db == null) return;

    // Collapse duplicate launches within the same session
    if (_lastSessionPackage == packageName) return;

    try {
      final now = DateTime.now();
      final context = await _getDeviceContext();

      await _db!.insert('launches', {
        'package_name': packageName,
        'app_name': appName ?? packageName,
        'timestamp': now.toIso8601String(),
        'hour': now.hour,
        'day_of_week': now.weekday,
        'session_gap_seconds': _currentSessionGap,
        'previous_app': _previousApp,
        'network_state': context['networkState'] ?? 'unknown',
        'battery_level': context['batteryLevel'] ?? -1,
        'charging_state': (context['isCharging'] == true) ? 1 : 0,
      });

      // Update tracking state
      _previousApp = packageName;
      _lastSessionPackage = packageName;

      // Record feedback for any outstanding predictions
      _recordFeedbackForLaunch(packageName);

      debugPrint('[Foresight] Recorded: $packageName');
    } catch (e) {
      debugPrint('[Foresight] recordLaunch error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Prediction
  // -------------------------------------------------------------------------

  /// Generate exactly three app predictions for the current context.
  /// Returns an empty list when insufficient data exists.
  Future<List<ForesightPrediction>> predict(List<AppInfo> installedApps) async {
    if (_db == null) return [];

    try {
      final now = DateTime.now();
      final context = await _getDeviceContext();

      final scores = await _computeScores(
        hour: now.hour,
        dayOfWeek: now.weekday,
        previousApp: _previousApp,
        sessionGapSeconds: _currentSessionGap,
        batteryLevel: (context['batteryLevel'] as int?) ?? 100,
        isCharging: context['isCharging'] == true,
        networkState: (context['networkState'] as String?) ?? 'unknown',
      );

      if (scores.isEmpty) {
        _currentPredictions = [];
        return [];
      }

      // Sort descending by score, take top 3 with a minimum threshold
      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted.take(3).where((e) => e.value > 0.001).toList();

      // Map package names to AppInfo for icons/names
      final appMap = <String, AppInfo>{};
      for (final app in installedApps) {
        appMap[app.packageName] = app;
      }

      // Persist predictions and build result list
      final predictions = <ForesightPrediction>[];
      for (var i = 0; i < top.length; i++) {
        final pkg = top[i].key;
        final app = appMap[pkg];

        final id = await _db!.insert('predictions', {
          'timestamp': now.toIso8601String(),
          'rank': i + 1,
          'predicted_package': pkg,
        });

        predictions.add(ForesightPrediction(
          packageName: pkg,
          appName: app?.name ?? pkg,
          icon: app?.icon,
          confidence: top[i].value,
          dbId: id,
        ));
      }

      // Clean up stale predictions that never got feedback
      unawaited(_invalidateOldPredictions());

      _currentPredictions = predictions;
      debugPrint('[Foresight] Predictions: '
          '${predictions.map((p) => '${p.appName}(${p.confidence.toStringAsFixed(3)})').join(', ')}');
      return predictions;
    } catch (e) {
      debugPrint('[Foresight] predict error: $e');
      return [];
    }
  }

  // -------------------------------------------------------------------------
  // Scoring — tiered variable importance model
  // -------------------------------------------------------------------------
  //
  //  Tier 1 (~60%)  time_of_day 28%  |  previous_app 22%  |  day_of_week 10%
  //  Tier 2 (~25%)  session_gap  9%  |  feedback      8%  |  charging     8%
  //  Tier 3 (~10%)  battery      4%  |  network        4%  |  (notif 2% — Phase 2)
  //  Tier 4  (~5%)  hist_freq    2%  |  recent_freq    2%  |  category     1%
  //
  //  Every prediction must trace to at least one Tier 1 or Tier 2 signal.

  Future<Map<String, double>> _computeScores({
    required int hour,
    required int dayOfWeek,
    required String? previousApp,
    required int sessionGapSeconds,
    required int batteryLevel,
    required bool isCharging,
    required String networkState,
  }) async {
    final db = _db!;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final cutoff24h =
        DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

    // --- Time window ---
    final window = _getTimeWindowRange(hour);
    final bool wraps = window[1] > 24;
    final int hStart = window[0];
    final int hEnd = wraps ? window[1] - 24 : window[1];

    final timeQuery = wraps
        ? 'SELECT package_name, COUNT(*) as cnt FROM launches '
            'WHERE timestamp >= ? AND (hour >= ? OR hour < ?) '
            'GROUP BY package_name'
        : 'SELECT package_name, COUNT(*) as cnt FROM launches '
            'WHERE timestamp >= ? AND hour >= ? AND hour < ? '
            'GROUP BY package_name';

    // --- Gap bucket ---
    final gap = _getGapBucketRange(sessionGapSeconds);

    // --- Day type ---
    final isWeekend = dayOfWeek == 6 || dayOfWeek == 7;
    final dayList = isWeekend ? [6, 7] : [1, 2, 3, 4, 5];
    final dayPlaceholders = dayList.map((_) => '?').join(',');

    // --- Run all queries ---
    final timeCounts =
        await db.rawQuery(timeQuery, [cutoff, hStart, hEnd]);

    final prevCounts = previousApp != null
        ? await db.rawQuery(
            'SELECT package_name, COUNT(*) as cnt FROM launches '
            'WHERE timestamp >= ? AND previous_app = ? '
            'GROUP BY package_name',
            [cutoff, previousApp])
        : <Map<String, Object?>>[];

    final dayCounts = await db.rawQuery(
        'SELECT package_name, COUNT(*) as cnt FROM launches '
        'WHERE timestamp >= ? AND day_of_week IN ($dayPlaceholders) '
        'GROUP BY package_name',
        [cutoff, ...dayList]);

    final gapCounts = await db.rawQuery(
        'SELECT package_name, COUNT(*) as cnt FROM launches '
        'WHERE timestamp >= ? AND session_gap_seconds >= ? AND session_gap_seconds < ? '
        'GROUP BY package_name',
        [cutoff, gap[0], gap[1]]);

    final chargeCounts = await db.rawQuery(
        'SELECT package_name, COUNT(*) as cnt FROM launches '
        'WHERE timestamp >= ? AND charging_state = ? '
        'GROUP BY package_name',
        [cutoff, isCharging ? 1 : 0]);

    final netCounts = await db.rawQuery(
        'SELECT package_name, COUNT(*) as cnt FROM launches '
        'WHERE timestamp >= ? AND network_state = ? '
        'GROUP BY package_name',
        [cutoff, networkState]);

    final overallCounts = await db.rawQuery(
        'SELECT package_name, COUNT(*) as cnt FROM launches '
        'WHERE timestamp >= ? '
        'GROUP BY package_name',
        [cutoff]);

    final recentCounts = await db.rawQuery(
        'SELECT package_name, COUNT(*) as cnt FROM launches '
        'WHERE timestamp >= ? '
        'GROUP BY package_name',
        [cutoff24h]);

    final feedbackRows = await db.rawQuery(
        'SELECT predicted_package, '
        'SUM(CASE WHEN was_opened = 1 THEN 1.0 ELSE 0.0 END) as opened, '
        'COUNT(*) as total '
        'FROM predictions WHERE was_opened IS NOT NULL '
        'GROUP BY predicted_package');

    final lowBattCounts = batteryLevel < 20
        ? await db.rawQuery(
            'SELECT package_name, COUNT(*) as cnt FROM launches '
            'WHERE timestamp >= ? AND battery_level >= 0 AND battery_level < 20 '
            'GROUP BY package_name',
            [cutoff])
        : <Map<String, Object?>>[];

    // --- Convert to maps ---
    Map<String, int> toMap(List<Map<String, Object?>> rows) {
      final m = <String, int>{};
      for (final r in rows) {
        m[r['package_name'] as String] = (r['cnt'] as int?) ?? 0;
      }
      return m;
    }

    int sumCounts(Map<String, int> m) => m.values.fold(0, (a, b) => a + b);

    final timeMap = toMap(timeCounts);
    final prevMap = toMap(prevCounts);
    final dayMap = toMap(dayCounts);
    final gapMap = toMap(gapCounts);
    final chargeMap = toMap(chargeCounts);
    final netMap = toMap(netCounts);
    final overallMap = toMap(overallCounts);
    final recentMap = toMap(recentCounts);
    final lowBattMap = toMap(lowBattCounts);

    final totalTime = sumCounts(timeMap);
    final totalPrev = sumCounts(prevMap);
    final totalDay = sumCounts(dayMap);
    final totalGap = sumCounts(gapMap);
    final totalCharge = sumCounts(chargeMap);
    final totalNet = sumCounts(netMap);
    final totalOverall = sumCounts(overallMap);
    final totalRecent = sumCounts(recentMap);
    final totalLowBatt = sumCounts(lowBattMap);

    // Feedback: package -> hit rate (0.0–1.0)
    final feedbackMap = <String, double>{};
    for (final r in feedbackRows) {
      final pkg = r['predicted_package'] as String;
      final opened = (r['opened'] as num?)?.toDouble() ?? 0;
      final total = (r['total'] as num?)?.toDouble() ?? 1;
      feedbackMap[pkg] = total > 0 ? opened / total : 0.5;
    }

    // --- Score every candidate ---
    final scores = <String, double>{};

    for (final app in overallMap.keys) {
      double tier12 = 0.0;

      // Tier 1: Time of day (28%)
      final tTime =
          totalTime > 0 ? (timeMap[app] ?? 0) / totalTime : 0.0;
      tier12 += tTime * 0.28;

      // Tier 1: Previous app transition (22%)
      final tPrev =
          totalPrev > 0 ? (prevMap[app] ?? 0) / totalPrev : 0.0;
      tier12 += tPrev * 0.22;

      // Tier 1: Day of week (10%)
      final tDay = totalDay > 0 ? (dayMap[app] ?? 0) / totalDay : 0.0;
      tier12 += tDay * 0.10;

      // Tier 2: Session gap (9%)
      final tGap = totalGap > 0 ? (gapMap[app] ?? 0) / totalGap : 0.0;
      tier12 += tGap * 0.09;

      // Tier 2: Prediction feedback (8%)
      final tFb = feedbackMap[app] ?? 0.5;
      tier12 += tFb * 0.08;

      // Tier 2: Charging state (8%)
      final tCharge =
          totalCharge > 0 ? (chargeMap[app] ?? 0) / totalCharge : 0.0;
      tier12 += tCharge * 0.08;

      // Guard: must have Tier 1/2 backing
      if (tier12 < 0.001) continue;

      double score = tier12;

      // Tier 3: Battery level (4%)
      if (batteryLevel < 20 && totalLowBatt > 0) {
        score += ((lowBattMap[app] ?? 0) / totalLowBatt) * 0.04;
      } else {
        score +=
            (totalOverall > 0 ? (overallMap[app] ?? 0) / totalOverall : 0.0) *
                0.04;
      }

      // Tier 3: Network state (4%)
      score +=
          (totalNet > 0 ? (netMap[app] ?? 0) / totalNet : 0.0) * 0.04;

      // Tier 4: Historical frequency (2%)
      score +=
          (totalOverall > 0 ? (overallMap[app] ?? 0) / totalOverall : 0.0) *
              0.02;

      // Tier 4: Recent frequency — last 24 h (2%)
      score +=
          (totalRecent > 0 ? (recentMap[app] ?? 0) / totalRecent : 0.0) *
              0.02;

      // Tier 4: App category of previous app (1%) — Phase 2
      // score += 0.0;

      scores[app] = score;
    }

    return scores;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Map an hour (0–23) to a behavioural time window.
  ///   early_morning 5–7  |  morning 8–11  |  afternoon 12–16
  ///   evening 17–20      |  night 21–0    |  late_night 1–4
  /// Returns [startHour, endHour]. endHour > 24 means the window wraps
  /// past midnight.
  List<int> _getTimeWindowRange(int hour) {
    if (hour >= 5 && hour < 8) return [5, 8];
    if (hour >= 8 && hour < 12) return [8, 12];
    if (hour >= 12 && hour < 17) return [12, 17];
    if (hour >= 17 && hour < 21) return [17, 21];
    if (hour >= 21 || hour < 1) return [21, 25]; // wraps midnight
    return [1, 5]; // late night
  }

  /// Map a session gap (seconds) to a behavioural bucket.
  ///   instant <30s  |  short 30s–5m  |  medium 5m–30m
  ///   long 30m–2h   |  fresh >2h
  List<int> _getGapBucketRange(int seconds) {
    if (seconds < 30) return [0, 30];
    if (seconds < 300) return [30, 300];
    if (seconds < 1800) return [300, 1800];
    if (seconds < 7200) return [1800, 7200];
    return [7200, 999999];
  }

  Future<Map<String, dynamic>> _getDeviceContext() async {
    try {
      final result =
          await _deviceChannel.invokeMapMethod<String, dynamic>('getDeviceContext');
      return result ??
          {'batteryLevel': 100, 'isCharging': false, 'networkState': 'unknown'};
    } catch (e) {
      debugPrint('[Foresight] getDeviceContext error: $e');
      return {'batteryLevel': 100, 'isCharging': false, 'networkState': 'unknown'};
    }
  }

  /// Load the most-recently launched app from the database so
  /// `_previousApp` survives process restarts.
  Future<void> _loadLastApp() async {
    if (_db == null) return;
    try {
      final result = await _db!
          .rawQuery('SELECT package_name FROM launches ORDER BY id DESC LIMIT 1');
      if (result.isNotEmpty) {
        _previousApp = result.first['package_name'] as String?;
      }
    } catch (e) {
      debugPrint('[Foresight] _loadLastApp error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Feedback loop
  // -------------------------------------------------------------------------

  /// When an app is launched, mark matching predictions as opened and
  /// non-matching predictions as ignored.
  void _recordFeedbackForLaunch(String launchedPackage) {
    if (_currentPredictions.isEmpty) return;
    final now = DateTime.now().toIso8601String();

    for (final p in _currentPredictions) {
      if (p.dbId != null) {
        final wasOpened = p.packageName == launchedPackage ? 1 : 0;
        _db?.update(
          'predictions',
          {'was_opened': wasOpened, 'feedback_timestamp': now},
          where: 'id = ? AND was_opened IS NULL',
          whereArgs: [p.dbId],
        );
      }
    }
    _currentPredictions = [];
  }

  /// Mark predictions older than 5 minutes without feedback as ignored.
  Future<void> _invalidateOldPredictions() async {
    if (_db == null) return;
    final cutoff =
        DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
    await _db!.update(
      'predictions',
      {
        'was_opened': 0,
        'feedback_timestamp': DateTime.now().toIso8601String(),
      },
      where: 'was_opened IS NULL AND timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  /// Delete data older than 30 days (rolling window + quota management).
  Future<void> _pruneOldData() async {
    if (_db == null) return;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final deleted =
        await _db!.delete('launches', where: 'timestamp < ?', whereArgs: [cutoff]);
    await _db!.delete('predictions', where: 'timestamp < ?', whereArgs: [cutoff]);
    if (deleted > 0) {
      debugPrint('[Foresight] Pruned $deleted entries older than 30 days.');
    }
  }
}
