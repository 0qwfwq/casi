// Foresight — User-configured rules: schedule and scenario.
//
// Users can pin specific apps to the Foresight dock based on:
//
//  • Schedule rules — "Show Gmail from 6–8 AM on Mon, Tue, Fri"
//  • Scenario rules — "Show Spotify when Bluetooth is connected"
//
// Matched apps are injected into the Foresight predictions at the highest
// priority, ahead of any automatically-scored apps. The dock still shows
// at most 6 apps total; user-pinned apps fill slots from the front.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'foresight_context.dart';

// ─── ScenarioTrigger ─────────────────────────────────────────────────────────

enum ScenarioTrigger {
  anyBluetooth,
  carBluetooth,
  wiredHeadphones,
  charging,
  lowBattery,
  weekendDaytime,
  morningHours,
  eveningHours,
  specificWifi,
}

extension ScenarioTriggerX on ScenarioTrigger {
  String get label {
    switch (this) {
      case ScenarioTrigger.anyBluetooth:    return 'Any Bluetooth connected';
      case ScenarioTrigger.carBluetooth:    return 'Connected to a car';
      case ScenarioTrigger.wiredHeadphones: return 'Wired headphones plugged in';
      case ScenarioTrigger.charging:        return 'Phone is charging';
      case ScenarioTrigger.lowBattery:      return 'Battery below 20%';
      case ScenarioTrigger.weekendDaytime:  return 'Weekend daytime (10 am – 7 pm)';
      case ScenarioTrigger.morningHours:    return 'Morning hours (6 – 9 am)';
      case ScenarioTrigger.eveningHours:    return 'Evening hours (7 – 11 pm)';
      case ScenarioTrigger.specificWifi:    return 'Connected to specific Wi-Fi';
    }
  }

  String get _key {
    switch (this) {
      case ScenarioTrigger.anyBluetooth:    return 'anyBluetooth';
      case ScenarioTrigger.carBluetooth:    return 'carBluetooth';
      case ScenarioTrigger.wiredHeadphones: return 'wiredHeadphones';
      case ScenarioTrigger.charging:        return 'charging';
      case ScenarioTrigger.lowBattery:      return 'lowBattery';
      case ScenarioTrigger.weekendDaytime:  return 'weekendDaytime';
      case ScenarioTrigger.morningHours:    return 'morningHours';
      case ScenarioTrigger.eveningHours:    return 'eveningHours';
      case ScenarioTrigger.specificWifi:    return 'specificWifi';
    }
  }

  static ScenarioTrigger fromKey(String k) => ScenarioTrigger.values.firstWhere(
    (e) => e._key == k,
    orElse: () => ScenarioTrigger.anyBluetooth,
  );
}

// ─── Car-name hint list (mirrors the one in foresight_context.dart) ──────────

const _carHints = [
  'car', 'auto', 'drive', 'vehicle', 'truck', 'jeep', 'suv',
  'carplay', 'android auto', 'sync', 'uconnect', 'mybmw',
  'bmw', 'audi', 'mercedes', 'benz', 'toyota', 'honda', 'ford',
  'tesla', 'nissan', 'hyundai', 'kia', 'mazda', 'subaru', 'chevy',
  'chevrolet', 'gmc', 'volkswagen', 'vw', 'volvo', 'lexus',
  'porsche', 'acura', 'infiniti', 'cadillac', 'lincoln', 'dodge',
  'ram', 'rivian', 'polestar', 'lucid', 'pioneer', 'kenwood', 'alpine',
  'civic', 'corolla', 'camry', 'rav4', 'f150', 'silverado',
  'mustang', 'tacoma', 'altima', 'sentra', 'wrangler',
];

bool _isCarName(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  final lower = raw.toLowerCase();
  return _carHints.any((w) => lower.contains(w));
}

// ─── ForesightScheduleRule ────────────────────────────────────────────────────

class ForesightScheduleRule {
  final String id;
  final String packageName;
  final String appName;

  /// 0–23 (inclusive). The window is [startHour, endHour).
  final int startHour;

  /// 0–23 (exclusive upper bound). If startHour > endHour the window wraps
  /// midnight (e.g. 22–6 = 10 pm to 6 am).
  final int endHour;

  /// DateTime.weekday values: 1 = Monday … 7 = Sunday.
  /// An empty list means every day.
  final List<int> weekdays;

  const ForesightScheduleRule({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.startHour,
    required this.endHour,
    required this.weekdays,
  });

  bool matches(DateTime now) {
    if (weekdays.isNotEmpty && !weekdays.contains(now.weekday)) return false;
    final h = now.hour;
    if (startHour < endHour) return h >= startHour && h < endHour;
    if (startHour == endHour) return false; // degenerate — no window
    return h >= startHour || h < endHour; // midnight-wrapping window
  }

  String get timeRangeLabel {
    final s = fmtHour(startHour);
    final e = fmtHour(endHour);
    return '$s – $e';
  }

  String get daysLabel {
    if (weekdays.isEmpty) return 'Every day';
    const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = [...weekdays]..sort();
    return sorted.map((d) => names[d]).join(', ');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'packageName': packageName,
    'appName': appName,
    'startHour': startHour,
    'endHour': endHour,
    'weekdays': weekdays,
  };

  factory ForesightScheduleRule.fromJson(Map<String, dynamic> j) =>
      ForesightScheduleRule(
        id: j['id'] as String,
        packageName: j['packageName'] as String,
        appName: j['appName'] as String,
        startHour: j['startHour'] as int,
        endHour: j['endHour'] as int,
        weekdays: List<int>.from(j['weekdays'] as List),
      );
}

// ─── ForesightScenarioRule ────────────────────────────────────────────────────

class ForesightScenarioRule {
  final String id;
  final String packageName;
  final String appName;
  final ScenarioTrigger trigger;

  /// Only used when trigger == specificWifi. The app surfaces whenever
  /// the current Wi-Fi SSID contains this string (case-insensitive).
  final String? ssidFilter;

  const ForesightScenarioRule({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.trigger,
    this.ssidFilter,
  });

  bool matches(ContextSnapshot s) {
    switch (trigger) {
      case ScenarioTrigger.anyBluetooth:
        return s.bluetoothAudioConnected || s.audioRoute == 'bluetooth';
      case ScenarioTrigger.carBluetooth:
        return _isCarName(s.bluetoothDeviceName) || _isCarName(s.wifiSsid);
      case ScenarioTrigger.wiredHeadphones:
        return s.audioRoute == 'wired_headphones';
      case ScenarioTrigger.charging:
        return s.isCharging;
      case ScenarioTrigger.lowBattery:
        return s.batteryLevel >= 0 && s.batteryLevel < 20 && !s.isCharging;
      case ScenarioTrigger.weekendDaytime:
        return s.isWeekend && s.hour >= 10 && s.hour < 19;
      case ScenarioTrigger.morningHours:
        return s.hour >= 6 && s.hour < 9;
      case ScenarioTrigger.eveningHours:
        return s.hour >= 19 && s.hour < 23;
      case ScenarioTrigger.specificWifi:
        final ssid = s.wifiSsid;
        final filter = ssidFilter;
        if (ssid == null || ssid.isEmpty || filter == null || filter.isEmpty) {
          return false;
        }
        return ssid.toLowerCase().contains(filter.toLowerCase());
    }
  }

  String get triggerLabel => trigger.label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'packageName': packageName,
    'appName': appName,
    'trigger': trigger._key,
    if (ssidFilter != null) 'ssidFilter': ssidFilter,
  };

  factory ForesightScenarioRule.fromJson(Map<String, dynamic> j) =>
      ForesightScenarioRule(
        id: j['id'] as String,
        packageName: j['packageName'] as String,
        appName: j['appName'] as String,
        trigger: ScenarioTriggerX.fromKey(j['trigger'] as String),
        ssidFilter: j['ssidFilter'] as String?,
      );
}

// ─── ForesightUserRulesService ────────────────────────────────────────────────

class ForesightUserRulesService {
  static final ForesightUserRulesService instance =
      ForesightUserRulesService._();
  ForesightUserRulesService._();

  static const _scheduleKey = 'foresight_schedule_rules_v1';
  static const _scenarioKey = 'foresight_scenario_rules_v1';

  List<ForesightScheduleRule> _scheduleRules = [];
  List<ForesightScenarioRule> _scenarioRules = [];

  List<ForesightScheduleRule> get scheduleRules =>
      List.unmodifiable(_scheduleRules);
  List<ForesightScenarioRule> get scenarioRules =>
      List.unmodifiable(_scenarioRules);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final sched = prefs.getString(_scheduleKey);
      if (sched != null) {
        final list = jsonDecode(sched) as List;
        _scheduleRules = list
            .map((e) => ForesightScheduleRule.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      final scenario = prefs.getString(_scenarioKey);
      if (scenario != null) {
        final list = jsonDecode(scenario) as List;
        _scenarioRules = list
            .map((e) => ForesightScenarioRule.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[ForesightRules] load error: $e');
    }
  }

  Future<void> _saveSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scheduleKey,
      jsonEncode(_scheduleRules.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> _saveScenario() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _scenarioKey,
      jsonEncode(_scenarioRules.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> addScheduleRule(ForesightScheduleRule rule) async {
    _scheduleRules.add(rule);
    await _saveSchedule();
  }

  Future<void> removeScheduleRule(String id) async {
    _scheduleRules.removeWhere((r) => r.id == id);
    await _saveSchedule();
  }

  Future<void> addScenarioRule(ForesightScenarioRule rule) async {
    _scenarioRules.add(rule);
    await _saveScenario();
  }

  Future<void> removeScenarioRule(String id) async {
    _scenarioRules.removeWhere((r) => r.id == id);
    await _saveScenario();
  }

  /// Returns every (packageName, appName, reason) that has a matching rule
  /// right now. Deduplicates by package so an app pinned by two rules still
  /// only appears once (first-match wins).
  List<({String packageName, String appName, String reason})> matchNow(
    DateTime now,
    ContextSnapshot? snapshot,
  ) {
    final seen = <String>{};
    final out = <({String packageName, String appName, String reason})>[];

    for (final r in _scheduleRules) {
      if (r.matches(now) && seen.add(r.packageName)) {
        out.add((
          packageName: r.packageName,
          appName: r.appName,
          reason: 'Scheduled: ${r.timeRangeLabel} · ${r.daysLabel}',
        ));
      }
    }

    if (snapshot != null) {
      for (final r in _scenarioRules) {
        if (r.matches(snapshot) && seen.add(r.packageName)) {
          out.add((
            packageName: r.packageName,
            appName: r.appName,
            reason: 'Scenario: ${r.triggerLabel}',
          ));
        }
      }
    }

    return out;
  }
}

// ─── Formatting helpers (also used by the Settings UI) ───────────────────────

String fmtHour(int h) {
  if (h == 0) return '12 AM';
  if (h < 12) return '$h AM';
  if (h == 12) return '12 PM';
  return '${h - 12} PM';
}

String dayAbbr(int weekday) {
  const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[weekday];
}
