// Foresight — contextual app prediction engine for the CASI launcher.
//
// Records every app launch with rich metadata (time, day, session gap,
// previous app, network, battery, charging) into a local SQLite database.
// On each prediction cycle, scores all candidate apps using a Multinomial
// Naive Bayes classifier that computes P(app | context) via Bayes'
// theorem with Laplace smoothing. Returns up to five predictions ranked
// by posterior probability. The consuming UI decides how many to display
// based on how many notification pills are currently active.
//
// The model is built from the full 30-day launch history on startup and
// updated incrementally in O(1) on each new launch. A feedback loop from
// the predictions table boosts apps the user actually opened and penalises
// consistently ignored apps.
//
// Storage: 30-day rolling window, duplicate launches within a session
// are collapsed, all I/O is asynchronous so launch performance is
// never affected.

import 'dart:async';
import 'dart:io';
import 'dart:math';
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

  // ---------------------------------------------------------------------------
  // Naive Bayes model state
  // ---------------------------------------------------------------------------

  /// Prior counts: package_name -> total launches in 30-day window.
  Map<String, int> _priorCounts = {};

  /// Total launches across all apps in the 30-day window.
  int _totalLaunches = 0;

  /// Likelihood counts: feature_name -> { feature_value -> { package -> count } }.
  Map<String, Map<String, Map<String, int>>> _likelihoodCounts = {};

  /// Number of distinct values observed per feature (for Laplace denominator).
  Map<String, int> _vocabSizes = {};

  /// All app package names the model has seen.
  Set<String> _knownApps = {};

  /// Whether the model has been built from the database at least once.
  bool _modelLoaded = false;

  /// Laplace smoothing parameter (additive smoothing).
  static const double _alpha = 1.0;

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
      await _pruneOldData();
      await _buildModel();
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
      final prevApp = _previousApp; // capture before overwriting

      await _db!.insert('launches', {
        'package_name': packageName,
        'app_name': appName ?? packageName,
        'timestamp': now.toIso8601String(),
        'hour': now.hour,
        'day_of_week': now.weekday,
        'session_gap_seconds': _currentSessionGap,
        'previous_app': prevApp,
        'network_state': context['networkState'] ?? 'unknown',
        'battery_level': context['batteryLevel'] ?? -1,
        'charging_state': (context['isCharging'] == true) ? 1 : 0,
      });

      // Update tracking state
      _previousApp = packageName;
      _lastSessionPackage = packageName;

      // Incrementally update the Naive Bayes model with this observation
      if (_modelLoaded) {
        _incrementalUpdate(
          packageName,
          _extractFeatures(
            hour: now.hour,
            dayOfWeek: now.weekday,
            previousApp: prevApp,
            sessionGapSeconds: _currentSessionGap,
            batteryLevel: (context['batteryLevel'] as int?) ?? 100,
            isCharging: context['isCharging'] == true,
            networkState: (context['networkState'] as String?) ?? 'unknown',
          ),
        );
      }

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

  /// Generate a ranked list of app predictions for the current context.
  /// Returns up to the top 10 candidates so the Foresight Dock always
  /// has enough runners-up to guarantee it can display 5 chips even
  /// when some of its top picks collide with apps already shown in the
  /// notification pills or pinned on the home dock.
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

      // Map package names to AppInfo for fast lookup
      final appMap = <String, AppInfo>{};
      for (final app in installedApps) {
        appMap[app.packageName] = app;
      }

      // Sort descending by score, filter uninstalled apps, take the
      // top 10. The dock renders 5 icons; the extra 5 are runners-up
      // so overlaps with the notification pills and home-dock apps
      // can be filtered out without leaving empty slots.
      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted
          .where((e) => e.value > 0.001 && appMap.containsKey(e.key))
          .take(10)
          .toList();

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
          appName: app!.name,
          icon: app.icon,
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
  // Naive Bayes classifier
  // -------------------------------------------------------------------------
  //
  // Computes P(app | context) ∝ P(app) · ∏ P(feature_i | app) for every
  // candidate app using Bayes' theorem with a conditional-independence
  // assumption. All arithmetic is done in log-space to avoid floating-point
  // underflow, and Laplace smoothing (α = 1) ensures unseen feature–app
  // combinations receive a small non-zero probability.

  /// Build (or rebuild) the in-memory Naive Bayes model from the 30-day
  /// launch history stored in SQLite. Called once on startup and again
  /// after old data is pruned.
  Future<void> _buildModel() async {
    if (_db == null) return;

    final cutoff =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    final rows = await _db!.rawQuery(
      'SELECT package_name, hour, day_of_week, previous_app, '
      'session_gap_seconds, battery_level, charging_state, network_state '
      'FROM launches WHERE timestamp >= ?',
      [cutoff],
    );

    // Reset model state
    _priorCounts = {};
    _totalLaunches = 0;
    _likelihoodCounts = {};
    _knownApps = {};
    final vocabSets = <String, Set<String>>{};

    for (final row in rows) {
      final app = row['package_name'] as String;
      _priorCounts[app] = (_priorCounts[app] ?? 0) + 1;
      _totalLaunches++;
      _knownApps.add(app);

      final features = _extractFeatures(
        hour: row['hour'] as int,
        dayOfWeek: row['day_of_week'] as int,
        previousApp: row['previous_app'] as String?,
        sessionGapSeconds: row['session_gap_seconds'] as int,
        batteryLevel: row['battery_level'] as int,
        isCharging: (row['charging_state'] as int) == 1,
        networkState: row['network_state'] as String,
      );

      for (final entry in features.entries) {
        final fname = entry.key;
        final fval = entry.value;

        _likelihoodCounts.putIfAbsent(fname, () => {});
        _likelihoodCounts[fname]!.putIfAbsent(fval, () => {});
        _likelihoodCounts[fname]![fval]![app] =
            (_likelihoodCounts[fname]![fval]![app] ?? 0) + 1;

        vocabSets.putIfAbsent(fname, () => {});
        vocabSets[fname]!.add(fval);
      }
    }

    _vocabSizes = vocabSets.map((k, v) => MapEntry(k, v.length));
    _modelLoaded = true;
    debugPrint('[Foresight] Naive Bayes model built — '
        '$_totalLaunches launches, ${_knownApps.length} apps, '
        '${_vocabSizes.entries.map((e) => '${e.key}:${e.value}').join(', ')}');
  }

  /// Incrementally update the model with a single new launch observation
  /// in O(1) time, avoiding a full rebuild.
  void _incrementalUpdate(String app, Map<String, String> features) {
    _priorCounts[app] = (_priorCounts[app] ?? 0) + 1;
    _totalLaunches++;
    _knownApps.add(app);

    for (final entry in features.entries) {
      final fname = entry.key;
      final fval = entry.value;

      _likelihoodCounts.putIfAbsent(fname, () => {});
      _likelihoodCounts[fname]!.putIfAbsent(fval, () => {});
      _likelihoodCounts[fname]![fval]![app] =
          (_likelihoodCounts[fname]![fval]![app] ?? 0) + 1;

      // Expand vocabulary size if a new value appears
      final distinctValues = _likelihoodCounts[fname]!.keys.length;
      if (distinctValues > (_vocabSizes[fname] ?? 0)) {
        _vocabSizes[fname] = distinctValues;
      }
    }
  }

  /// Score every known app using the Naive Bayes posterior probability
  /// given the current context, then normalize via softmax to produce
  /// confidence values in the 0–1 range.
  Future<Map<String, double>> _computeScores({
    required int hour,
    required int dayOfWeek,
    required String? previousApp,
    required int sessionGapSeconds,
    required int batteryLevel,
    required bool isCharging,
    required String networkState,
  }) async {
    if (!_modelLoaded) await _buildModel();
    if (_totalLaunches == 0 || _knownApps.isEmpty) return {};

    final features = _extractFeatures(
      hour: hour,
      dayOfWeek: dayOfWeek,
      previousApp: previousApp,
      sessionGapSeconds: sessionGapSeconds,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      networkState: networkState,
    );

    final numApps = _knownApps.length;
    final scores = <String, double>{};

    for (final app in _knownApps) {
      // Log-prior: log P(app)
      double logScore = _safeLog((_priorCounts[app] ?? 0) + _alpha) -
          _safeLog(_totalLaunches + _alpha * numApps);

      // Log-likelihoods: sum of log P(feature_value | app)
      for (final entry in features.entries) {
        final fname = entry.key;
        final fval = entry.value;
        final vocabSize = _vocabSizes[fname] ?? 1;

        final countGivenApp =
            _likelihoodCounts[fname]?[fval]?[app] ?? 0;
        final countApp = _priorCounts[app] ?? 0;

        logScore += _safeLog(countGivenApp + _alpha) -
            _safeLog(countApp + _alpha * vocabSize);
      }

      scores[app] = logScore;
    }

    // Boost scores using the prediction feedback loop
    await _applyFeedbackBoost(scores);

    // Convert log-probabilities to 0–1 confidence via softmax
    _softmaxNormalize(scores);

    return scores;
  }

  /// Adjust log-scores using prediction hit-rate feedback from the
  /// predictions table. Apps the user actually opened after they were
  /// predicted receive a positive boost; consistently-ignored apps
  /// receive a penalty.
  Future<void> _applyFeedbackBoost(Map<String, double> logScores) async {
    if (_db == null) return;

    final feedbackRows = await _db!.rawQuery(
      'SELECT predicted_package, '
      'SUM(CASE WHEN was_opened = 1 THEN 1.0 ELSE 0.0 END) as opened, '
      'COUNT(*) as total '
      'FROM predictions WHERE was_opened IS NOT NULL '
      'GROUP BY predicted_package',
    );

    for (final r in feedbackRows) {
      final pkg = r['predicted_package'] as String;
      final opened = (r['opened'] as num?)?.toDouble() ?? 0;
      final total = (r['total'] as num?)?.toDouble() ?? 1;
      final hitRate = total > 0 ? opened / total : 0.5;

      if (logScores.containsKey(pkg)) {
        // Shift in log-space: hitRate 1.0 → +0.5, hitRate 0.0 → −0.5
        logScores[pkg] = logScores[pkg]! + (hitRate - 0.5);
      }
    }
  }

  /// Softmax-normalize a map of log-scores into 0–1 confidence values.
  void _softmaxNormalize(Map<String, double> logScores) {
    if (logScores.isEmpty) return;

    // Subtract max for numerical stability
    final maxLog = logScores.values.reduce((a, b) => a > b ? a : b);

    double sumExp = 0.0;
    final expScores = <String, double>{};
    for (final entry in logScores.entries) {
      final e = _safeExp(entry.value - maxLog);
      expScores[entry.key] = e;
      sumExp += e;
    }

    for (final key in logScores.keys) {
      logScores[key] = sumExp > 0 ? expScores[key]! / sumExp : 0.0;
    }
  }

  /// log(x) clamped so log(0) returns −30 instead of −infinity.
  double _safeLog(num x) => x > 0 ? log(x.toDouble()) : -30.0;

  /// exp(x) clamped to avoid overflow/underflow.
  double _safeExp(double x) => exp(x.clamp(-30.0, 30.0));

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Map an hour (0–23) to a behavioural time-bucket label.
  String _getTimeBucket(int hour) {
    if (hour >= 5 && hour < 8) return 'early_morning';
    if (hour >= 8 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 21) return 'evening';
    if (hour >= 21 || hour < 1) return 'night';
    return 'late_night';
  }

  /// Map a session gap (seconds) to a behavioural bucket label.
  String _getGapBucket(int seconds) {
    if (seconds < 30) return 'instant';
    if (seconds < 300) return 'short';
    if (seconds < 1800) return 'medium';
    if (seconds < 7200) return 'long';
    return 'fresh';
  }

  /// Convert raw contextual signals into categorical feature values
  /// for the Naive Bayes classifier.
  Map<String, String> _extractFeatures({
    required int hour,
    required int dayOfWeek,
    required String? previousApp,
    required int sessionGapSeconds,
    required int batteryLevel,
    required bool isCharging,
    required String networkState,
  }) {
    return {
      'time_bucket': _getTimeBucket(hour),
      'day_type': (dayOfWeek == 6 || dayOfWeek == 7) ? 'weekend' : 'weekday',
      'previous_app': previousApp ?? '__none__',
      'gap_bucket': _getGapBucket(sessionGapSeconds),
      'charging': isCharging ? 'true' : 'false',
      'battery_bucket':
          batteryLevel < 20 ? 'low' : (batteryLevel > 80 ? 'high' : 'medium'),
      'network': networkState,
    };
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

  /// Remove all launch history and prediction data for a specific package.
  /// Call this when an app is uninstalled so it stops being recommended.
  Future<void> purgeApp(String packageName) async {
    if (_db == null) return;
    try {
      final launchesDeleted = await _db!.delete(
        'launches',
        where: 'package_name = ?',
        whereArgs: [packageName],
      );
      final predictionsDeleted = await _db!.delete(
        'predictions',
        where: 'predicted_package = ?',
        whereArgs: [packageName],
      );
      // Clear from current predictions cache
      _currentPredictions.removeWhere((p) => p.packageName == packageName);
      if (_previousApp == packageName) _previousApp = null;

      // Remove from in-memory Naive Bayes model
      _knownApps.remove(packageName);
      _priorCounts.remove(packageName);
      for (final featureMap in _likelihoodCounts.values) {
        for (final valueMap in featureMap.values) {
          valueMap.remove(packageName);
        }
      }
      _totalLaunches = _priorCounts.values.fold(0, (a, b) => a + b);

      debugPrint('[Foresight] Purged $packageName: '
          '$launchesDeleted launches, $predictionsDeleted predictions removed.');
    } catch (e) {
      debugPrint('[Foresight] purgeApp error: $e');
    }
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
      await _buildModel(); // Rebuild model without pruned data
    }
  }
}
