// Foresight — contextual app prediction engine for the CASI launcher.
//
// Records every app launch with rich metadata (time, day, session gap,
// previous app, network, battery, charging) into a local SQLite database.
// On each prediction cycle, scores all candidate apps using a Multinomial
// Naive Bayes classifier that computes P(app | context) via Bayes'
// theorem with Laplace smoothing. Returns up to fifteen candidates ranked
// by posterior probability; the consuming UI picks which ones to display.
//
// The model is built from the full 30-day launch history on startup and
// updated incrementally in O(1) on each new launch. A feedback loop from
// the predictions table boosts apps the user actually opened and penalises
// consistently ignored apps.
//
// Efficiency:
//  * predict() is cached by a context-signature string built from the same
//    bucketed features the scorer uses. Repeated calls on an unchanged
//    signature return the cached result without touching SQLite.
//  * Feedback-boost offsets are cached in memory and refreshed at most
//    once every few minutes.
//  * Only the top-N displayed predictions are persisted to SQLite, and
//    only when the predicted set actually changes — preventing runaway
//    growth of the predictions table.
//  * `previous_app` vocabulary is capped to the top-K launched apps; the
//    long tail collapses into an `__other__` bucket so the in-memory
//    likelihood map stays bounded regardless of history size.
//  * Launches are kept 30 days; predictions are kept 7 days (plenty for
//    the feedback loop, a fraction of the storage).

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

  /// Top-K most-launched apps retained as distinct `previous_app` values.
  /// Every other app is bucketed as `__other__` so the likelihood map
  /// can't grow without bound.
  Set<String> _frequentAppsCache = {};
  static const int _previousAppVocabCap = 50;

  // --- Prediction-call cache ---------------------------------------------
  // Skips the scorer, the feedback query, and all DB writes when the
  // bucketed context hasn't changed since the last call.
  static const Duration _predictionCacheTtl = Duration(seconds: 30);
  DateTime? _lastPredictTime;
  String? _lastContextSignature;
  Set<String> _lastPersistedSet = {};

  // --- Feedback-boost cache ----------------------------------------------
  static const Duration _feedbackRefreshInterval = Duration(minutes: 5);
  Map<String, double> _feedbackOffsets = {};
  DateTime? _lastFeedbackRefresh;

  // --- Stale-prediction invalidation throttle ----------------------------
  static const Duration _invalidateInterval = Duration(seconds: 60);
  DateTime? _lastInvalidateTime;

  /// Number of top predictions persisted to the feedback table per change.
  static const int _persistTopN = 5;

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
      // _pruneOldData rebuilds the model when it actually deletes launches.
      // Only build here on the common no-prune path to avoid a double build.
      if (!_modelLoaded) await _buildModel();
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
  /// Returns up to the top 15 candidates so the Foresight Dock always
  /// has enough runners-up to guarantee it can fill the configured
  /// dock size (up to 7) even when some of its top picks collide with
  /// apps already shown in the notification pills or on the home dock.
  /// Returns an empty list when insufficient data exists.
  ///
  /// This method is cheap on a hot path: if the bucketed context hasn't
  /// changed since the previous call (and the cache hasn't aged out),
  /// it returns the cached result without running the scorer, the
  /// feedback query, or any database writes.
  Future<List<ForesightPrediction>> predict(List<AppInfo> installedApps) async {
    if (_db == null) return [];

    try {
      final now = DateTime.now();
      final context = await _getDeviceContext();

      final batteryLevel = (context['batteryLevel'] as int?) ?? 100;
      final isCharging = context['isCharging'] == true;
      final networkState = (context['networkState'] as String?) ?? 'unknown';

      // Cheap signature over the same bucketed inputs the scorer uses.
      // Matching signature + fresh timestamp => skip everything below.
      final signature = _buildContextSignature(
        now: now,
        previousApp: _previousApp,
        sessionGapSeconds: _currentSessionGap,
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        networkState: networkState,
      );

      final cacheAge = _lastPredictTime == null
          ? null
          : now.difference(_lastPredictTime!);
      if (signature == _lastContextSignature &&
          cacheAge != null &&
          cacheAge < _predictionCacheTtl &&
          _currentPredictions.isNotEmpty) {
        return _currentPredictions;
      }

      final scores = await _computeScores(
        hour: now.hour,
        dayOfWeek: now.weekday,
        previousApp: _previousApp,
        sessionGapSeconds: _currentSessionGap,
        batteryLevel: batteryLevel,
        isCharging: isCharging,
        networkState: networkState,
      );

      if (scores.isEmpty) {
        _currentPredictions = [];
        _lastContextSignature = signature;
        _lastPredictTime = now;
        return [];
      }

      // Map package names to AppInfo for fast lookup
      final appMap = <String, AppInfo>{};
      for (final app in installedApps) {
        appMap[app.packageName] = app;
      }

      // Sort descending by score, filter uninstalled apps, take the
      // top 15. The dock renders up to 7 icons; the extras are runners-up
      // so overlaps with the notification pills and home-dock apps
      // can be filtered out without leaving empty slots.
      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = sorted
          .where((e) => e.value > 0.001 && appMap.containsKey(e.key))
          .take(15)
          .toList();

      // Persist only the top-N package set, and only when it actually
      // differs from what we persisted last time. Caps prediction-table
      // growth to a handful of rows per genuine context change rather
      // than 15 rows per poll tick.
      final topNPackages =
          top.take(_persistTopN).map((e) => e.key).toSet();
      final shouldPersist = topNPackages.isNotEmpty &&
          !_setEquals(topNPackages, _lastPersistedSet);

      final predictions = <ForesightPrediction>[];
      if (shouldPersist) {
        await _db!.transaction((txn) async {
          for (var i = 0; i < top.length; i++) {
            final pkg = top[i].key;
            final app = appMap[pkg]!;
            int? id;
            if (i < _persistTopN) {
              id = await txn.insert('predictions', {
                'timestamp': now.toIso8601String(),
                'rank': i + 1,
                'predicted_package': pkg,
              });
            }
            predictions.add(ForesightPrediction(
              packageName: pkg,
              appName: app.name,
              icon: app.icon,
              confidence: top[i].value,
              dbId: id,
            ));
          }
        });
        _lastPersistedSet = topNPackages;
      } else {
        for (var i = 0; i < top.length; i++) {
          final pkg = top[i].key;
          final app = appMap[pkg]!;
          predictions.add(ForesightPrediction(
            packageName: pkg,
            appName: app.name,
            icon: app.icon,
            confidence: top[i].value,
            dbId: null,
          ));
        }
      }

      // Clean up stale predictions at most once per minute.
      unawaited(_maybeInvalidateOldPredictions());

      _currentPredictions = predictions;
      _lastContextSignature = signature;
      _lastPredictTime = now;
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
  ///
  /// Two passes: the first counts priors so we can determine which apps
  /// are frequent enough to keep as distinct `previous_app` vocabulary
  /// entries; the second pass builds likelihood counts with the long
  /// tail of rare apps bucketed as `__other__`.
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

    // Pass 1: priors + known-apps set. Needed before bucketing so we
    // can cap the previous_app vocabulary to the top-K most-launched apps.
    for (final row in rows) {
      final app = row['package_name'] as String;
      _priorCounts[app] = (_priorCounts[app] ?? 0) + 1;
      _totalLaunches++;
      _knownApps.add(app);
    }
    _refreshFrequentAppsCache();

    // Pass 2: build likelihood counts using the bounded vocabulary.
    for (final row in rows) {
      final app = row['package_name'] as String;
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

    // The model state just changed — invalidate the predict() cache so
    // the next call recomputes against the fresh counts.
    _lastContextSignature = null;

    debugPrint('[Foresight] Naive Bayes model built — '
        '$_totalLaunches launches, ${_knownApps.length} apps, '
        '${_frequentAppsCache.length} frequent prev-apps, '
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

    // Model state changed — the cached ranking is no longer necessarily
    // correct even if the bucketed context still matches. Force a
    // recompute on the next predict() call.
    _lastContextSignature = null;
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

    // Boost scores using the prediction feedback loop (cached offsets,
    // refreshed at most every few minutes — see _ensureFeedbackFresh).
    await _ensureFeedbackFresh();
    for (final entry in _feedbackOffsets.entries) {
      if (scores.containsKey(entry.key)) {
        scores[entry.key] = scores[entry.key]! + entry.value;
      }
    }

    // Convert log-probabilities to 0–1 confidence via softmax
    _softmaxNormalize(scores);

    return scores;
  }

  /// Recompute per-app feedback offsets (hit-rate minus 0.5) at most once
  /// every [_feedbackRefreshInterval]. Hit rates shift slowly, so there's
  /// no value in running the aggregation on every predict() call.
  Future<void> _ensureFeedbackFresh() async {
    if (_db == null) return;
    final now = DateTime.now();
    if (_lastFeedbackRefresh != null &&
        now.difference(_lastFeedbackRefresh!) < _feedbackRefreshInterval) {
      return;
    }

    final feedbackRows = await _db!.rawQuery(
      'SELECT predicted_package, '
      'SUM(CASE WHEN was_opened = 1 THEN 1.0 ELSE 0.0 END) as opened, '
      'COUNT(*) as total '
      'FROM predictions WHERE was_opened IS NOT NULL '
      'GROUP BY predicted_package',
    );

    final offsets = <String, double>{};
    for (final r in feedbackRows) {
      final pkg = r['predicted_package'] as String;
      final opened = (r['opened'] as num?)?.toDouble() ?? 0;
      final total = (r['total'] as num?)?.toDouble() ?? 1;
      final hitRate = total > 0 ? opened / total : 0.5;
      offsets[pkg] = hitRate - 0.5;
    }
    _feedbackOffsets = offsets;
    _lastFeedbackRefresh = now;
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
      'previous_app': _bucketPreviousApp(previousApp),
      'gap_bucket': _getGapBucket(sessionGapSeconds),
      'charging': isCharging ? 'true' : 'false',
      'battery_bucket':
          batteryLevel < 20 ? 'low' : (batteryLevel > 80 ? 'high' : 'medium'),
      'network': networkState,
    };
  }

  /// Map a raw previous-app package name onto the bounded vocabulary used
  /// by the classifier. Rare apps collapse into `__other__` so the
  /// likelihood map's size stays bounded regardless of how many unique
  /// apps the user ever launches.
  String _bucketPreviousApp(String? previousApp) {
    if (previousApp == null) return '__none__';
    // Before the first model build we have no frequency info — keep the
    // raw value; it'll be re-bucketed on the next rebuild.
    if (_frequentAppsCache.isEmpty) return previousApp;
    return _frequentAppsCache.contains(previousApp) ? previousApp : '__other__';
  }

  /// Refresh the set of `previous_app` values that count as distinct,
  /// derived from the top-K most-launched apps in the 30-day window.
  void _refreshFrequentAppsCache() {
    if (_priorCounts.length <= _previousAppVocabCap) {
      _frequentAppsCache = _priorCounts.keys.toSet();
      return;
    }
    final sorted = _priorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _frequentAppsCache =
        sorted.take(_previousAppVocabCap).map((e) => e.key).toSet();
  }

  /// Build a signature over the bucketed contextual inputs the scorer
  /// consumes. If two calls produce the same signature, the scorer would
  /// produce the same ranking — so predict() can skip recompute.
  String _buildContextSignature({
    required DateTime now,
    required String? previousApp,
    required int sessionGapSeconds,
    required int batteryLevel,
    required bool isCharging,
    required String networkState,
  }) {
    final timeBucket = _getTimeBucket(now.hour);
    final dayType =
        (now.weekday == 6 || now.weekday == 7) ? 'weekend' : 'weekday';
    final gapBucket = _getGapBucket(sessionGapSeconds);
    final batteryBucket =
        batteryLevel < 20 ? 'low' : (batteryLevel > 80 ? 'high' : 'medium');
    final prev = _bucketPreviousApp(previousApp);
    return '$timeBucket|$dayType|$gapBucket|$batteryBucket|'
        '$isCharging|$networkState|$prev';
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
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
    if (_currentPredictions.isEmpty || _db == null) return;
    final now = DateTime.now().toIso8601String();
    final preds = List<ForesightPrediction>.from(_currentPredictions);
    _currentPredictions = [];

    // Batch all updates in a single transaction to avoid lock contention.
    _db!.transaction((txn) async {
      for (final p in preds) {
        if (p.dbId != null) {
          final wasOpened = p.packageName == launchedPackage ? 1 : 0;
          await txn.update(
            'predictions',
            {'was_opened': wasOpened, 'feedback_timestamp': now},
            where: 'id = ? AND was_opened IS NULL',
            whereArgs: [p.dbId],
          );
        }
      }
    });
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

  /// Throttled wrapper: run [_invalidateOldPredictions] at most once per
  /// [_invalidateInterval]. Prevents the 3-second poll tick from issuing
  /// a UPDATE query every time the homescreen redraws.
  Future<void> _maybeInvalidateOldPredictions() async {
    final now = DateTime.now();
    if (_lastInvalidateTime != null &&
        now.difference(_lastInvalidateTime!) < _invalidateInterval) {
      return;
    }
    _lastInvalidateTime = now;
    await _invalidateOldPredictions();
  }

  /// Remove all launch history and prediction data for a specific package.
  /// Call this when an app is uninstalled so it stops being recommended.
  Future<void> purgeApp(String packageName) async {
    if (_db == null) return;
    try {
      int launchesDeleted = 0;
      int predictionsDeleted = 0;
      await _db!.transaction((txn) async {
        launchesDeleted = await txn.delete(
          'launches',
          where: 'package_name = ?',
          whereArgs: [packageName],
        );
        predictionsDeleted = await txn.delete(
          'predictions',
          where: 'predicted_package = ?',
          whereArgs: [packageName],
        );
      });
      // Clear from current predictions cache
      _currentPredictions.removeWhere((p) => p.packageName == packageName);
      if (_previousApp == packageName) _previousApp = null;

      // Remove from in-memory Naive Bayes model
      _knownApps.remove(packageName);
      _priorCounts.remove(packageName);
      _frequentAppsCache.remove(packageName);
      for (final featureMap in _likelihoodCounts.values) {
        for (final valueMap in featureMap.values) {
          valueMap.remove(packageName);
        }
      }
      _totalLaunches = _priorCounts.values.fold(0, (a, b) => a + b);

      // Invalidate predict() cache and force feedback refresh on next use
      // so the purged app can't linger in cached rankings/offsets.
      _lastContextSignature = null;
      _lastPersistedSet = {};
      _feedbackOffsets.remove(packageName);

      debugPrint('[Foresight] Purged $packageName: '
          '$launchesDeleted launches, $predictionsDeleted predictions removed.');
    } catch (e) {
      debugPrint('[Foresight] purgeApp error: $e');
    }
  }

  /// Delete data older than the retention window. Launches keep the full
  /// 30 days so the Naive Bayes model has a rich history to learn from,
  /// while the prediction log is trimmed to 7 days — enough to compute
  /// meaningful hit rates for the feedback boost without ballooning the
  /// database.
  Future<void> _pruneOldData() async {
    if (_db == null) return;
    final now = DateTime.now();
    final launchCutoff =
        now.subtract(const Duration(days: 30)).toIso8601String();
    final predictionCutoff =
        now.subtract(const Duration(days: 7)).toIso8601String();
    int launchesDeleted = 0;
    int predictionsDeleted = 0;
    await _db!.transaction((txn) async {
      launchesDeleted = await txn.delete(
        'launches',
        where: 'timestamp < ?',
        whereArgs: [launchCutoff],
      );
      predictionsDeleted = await txn.delete(
        'predictions',
        where: 'timestamp < ?',
        whereArgs: [predictionCutoff],
      );
    });
    if (launchesDeleted > 0 || predictionsDeleted > 0) {
      debugPrint('[Foresight] Pruned $launchesDeleted launches (>30d), '
          '$predictionsDeleted predictions (>7d).');
    }
    if (launchesDeleted > 0) {
      // Launch counts changed — rebuild the classifier.
      await _buildModel();
    }
    if (predictionsDeleted > 0) {
      // Hit-rate denominators shifted; force a feedback-boost refresh.
      _lastFeedbackRefresh = null;
    }
  }
}
