import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:casi/design_system.dart';
import 'settings_page.dart';
import '../widgets/glass_header.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_dock.dart';
import '../widgets/song_player.dart';
import '../widgets/weather_forecast_widget.dart';
import '../services/weather_service.dart';
import '../utils/app_launcher.dart';
import '../widgets/notify_pill.dart';
import '../morning_brief/morning_brief_panel.dart';
import '../morning_brief/weather_brief_service.dart';
import '../morning_brief/calendar_brief_service.dart';
import '../services/wallpaper_service.dart';
import '../services/system_clock_service.dart';
import 'package:casi/services/foresight_service.dart';
import '../widgets/foresight_pill.dart';
import '../widgets/timer_pill.dart';
import '../widgets/alarm_pill.dart';
import '../models/widget_items.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver, TickerProviderStateMixin {
  static List<AppInfo>? _cachedFullApps;

  List<AppInfo> _apps = [];
  final Map<int, AppInfo> _homeApps = {};
  
  bool _isLoading = true;
  bool _isDragging = false;
  AppInfo? _draggingApp;
  bool _isPlayerVisible = false;

  // --- Alarm list (each alarm carries its own isActive flag) ---
  List<AppAlarm> _alarms = [];
  bool _isAlarmRinging = false;
  Timer? _alarmTimer;
  Timer? _foresightPollTimer;
  String? _lastRungAlarmTime;

  // Tracks which schedule-row pill(s) are currently ringing so we can
  // render the red bell-shake state in place. A set of timer indices
  // (multiple timers can ring simultaneously); alarms ring one at a time.
  String? _ringingAlarmLabel;
  Set<int> _ringingTimerIndices = {};

  // --- Audio States ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _soundTimer;
  Timer? _vibrationTimer;
  double? _previousVolume;

  // --- Timer list ---
  List<AppTimer> _appTimers = [];
  Timer? _countdownTimer;

  // --- Morning Brief State ---
  bool _showMorningBrief = true;
  int _morningBriefDismissDay = -1;
  int _morningBriefKey = 0; // incremented to force panel reset to page 0
  WeatherBriefData? _weatherBriefData;
  CalendarBriefData? _calendarBriefData;
  String _temperatureUnit = 'C';

  // Whether the user has enabled the weather widget in Settings.
  // Persisted to SharedPreferences.
  bool _weatherWidgetActive = false;

  // --- Foresight State ---
  List<ForesightPrediction> _foresightPredictions = [];
  bool _showForesight = true;

  // --- Foresight long-press launch target ---
  // Empty string means "use the system's default browser".
  String _foresightLongPressPackage = '';

  // --- System clock state (read from user's default clock app) ---
  // Next system alarm scheduled via AlarmManager.setAlarmClock — populated
  // for any clock app the user has installed (Google Clock, Samsung Clock,
  // OnePlus, AOSP DeskClock, etc.).
  SystemAlarm? _systemAlarm;
  // Currently active system timers parsed from the clock app's foreground
  // notifications. Empty list means no clock-app timer is running, OR the
  // user hasn't granted Notification Access.
  List<SystemTimer> _systemTimers = const [];
  Timer? _systemClockTimer;

  // --- Settings ---
  final WallpaperService _wallpaperService = WallpaperService();
  bool _immersiveMode = false;

  // --- Spatial layout mode ---
  bool _spatialMode = false;
  final Map<String, Offset> _spatialPositions = {};
  String? _activeDragKey;
  Offset _dragStartElementPos = Offset.zero;

  // Clock + date visibility (Settings → Clock). Date slot height is
  // always reserved by [ClockCapsule] — only the glyph rendering toggles
  // — so widgets below the capsule never drift up into the date band.
  bool _showClock = true;
  bool _showDate = true;

  int _lastCheckedDay = DateTime.now().day;

  // --- Layout Constants ---
  static const int _maxHomeApps = 7;

  // --- Drawer Control ---
  final ValueNotifier<double> _drawerProgress = ValueNotifier(0.0);
  final DraggableScrollableController _drawerController = DraggableScrollableController();
  double _dragStartY = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (_cachedFullApps != null) {
      _apps = _cachedFullApps!;
      _isLoading = false;
      _loadSavedLayout(_apps).then((_) {
        if (mounted) setState(() {});
        _checkAppChangesOnResume();
      });
    } else {
      _initApps();
    }
    
    _loadSettings();
    _loadAlarms();
    _loadTimers();
    _loadMorningBriefState();
    _loadForesightState();
    _loadWeatherWidgetState();
    WeatherService.instance.initialize();
    _refreshWeatherBrief();
    _refreshCalendarBrief();


    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkAlarms();
    });

    // System clock polling — alarms refresh slowly (they only change when the
    // user opens the clock app), but timers tick down second-by-second so we
    // refresh both every second to keep the timer pill accurate.
    _refreshSystemClock();
    _systemClockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _refreshSystemClock());

    _initForesight();
  }

  Future<void> _refreshSystemClock() async {
    final results = await Future.wait([
      SystemClockService.instance.getNextAlarm(),
      SystemClockService.instance.getSystemTimers(),
    ]);
    if (!mounted) return;
    final nextAlarm = results[0] as SystemAlarm?;
    final timers = results[1] as List<SystemTimer>;
    setState(() {
      _systemAlarm = nextAlarm;
      _systemTimers = timers;
    });
  }

  Future<void> _initForesight() async {
    await ForesightService.instance.initialize();
    _refreshForesightPredictions();
    // Re-evaluate Foresight periodically so context-driven predictions
    // refresh without waiting for the user to leave and come back.
    _foresightPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshForesightPredictions();
    });
  }

  Future<void> _refreshForesightPredictions() async {
    if (!ForesightService.instance.isInitialized || _apps.isEmpty) return;
    final predictions = await ForesightService.instance.predict(_apps);
    if (mounted) {
      setState(() => _foresightPredictions = predictions);
    }
  }

  void _onForesightAppTap(String packageName) {
    ForesightService.instance.recordLaunch(packageName);
    AppLauncher.launchApp(packageName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmTimer?.cancel();
    _foresightPollTimer?.cancel();
    _systemClockTimer?.cancel();
    _countdownTimer?.cancel();
    _stopAlarmSound();
    _audioPlayer.dispose();
    _wallpaperService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersiveMode();
      _wallpaperService.reload();
      _checkAppChangesOnResume();
      // Reload temperature unit in case it was changed in settings
      SharedPreferences.getInstance().then((prefs) {
        final newUnit = prefs.getString('temperature_unit') ?? 'C';
        if (newUnit != _temperatureUnit && mounted) {
          setState(() => _temperatureUnit = newUnit);
        }
      });
      _syncTimersOnResume();
      _refreshWeatherBrief();
      _refreshCalendarBrief();
      WeatherService.instance.reloadUnitAndRefresh();

      // Foresight: generate predictions on unlock
      ForesightService.instance.onResume();
      _refreshForesightPredictions();
      // Instantly close the drawer when returning to the launcher
      if (_drawerController.isAttached && _drawerController.size > 0.0) {
        _drawerController.jumpTo(0.0);
      }
    } else if (state == AppLifecycleState.paused) {
      ForesightService.instance.onPause();
      // Instantly close the drawer when leaving the launcher (e.g. opening an app)
      if (_drawerController.isAttached && _drawerController.size > 0.0) {
        _drawerController.jumpTo(0.0);
      }
    }
  }

  // --- Alarm Audio Logic ---
  Future<void> _playSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/alarm_sound.wav'));
    } catch (e) {
      debugPrint("Error playing alarm sound: $e");
    }
  }

  void _startAlarmSound() {
    // Save current volume and set to 70%
    VolumeController().getVolume().then((vol) {
      _previousVolume = vol;
      VolumeController().setVolume(0.7, showSystemUI: false);
    });

    _playSound();
    _soundTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAlarmRinging) {
        _playSound();
      } else {
        _stopAlarmSound();
      }
    });

    // Calming vibration pattern: gentle pulses with pauses
    _startCalmVibration();
  }

  void _startCalmVibration() {
    _vibrationTimer?.cancel();
    // Gentle repeating pattern: light buzz, pause, light buzz, longer pause
    int tick = 0;
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!_isAlarmRinging) {
        _vibrationTimer?.cancel();
        _vibrationTimer = null;
        return;
      }
      // Alternate between light impact and soft vibration
      if (tick % 3 == 0) {
        HapticFeedback.lightImpact();
      } else if (tick % 3 == 1) {
        HapticFeedback.mediumImpact();
      }
      // tick % 3 == 2 → silence (the pause in the pattern)
      tick++;
    });
  }

  void _stopAlarmSound() {
    _soundTimer?.cancel();
    _soundTimer = null;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    _audioPlayer.stop();

    // Restore previous volume
    if (_previousVolume != null) {
      VolumeController().setVolume(_previousVolume!, showSystemUI: false);
      _previousVolume = null;
    }
  }

  // --- Alarm Background Logic ---
  void _checkAlarms() {
    // Reset event pill dismiss and morning brief when the day changes
    final today = DateTime.now().day;
    if (today != _lastCheckedDay) {
      _lastCheckedDay = today;
      if (_morningBriefDismissDay != today) {
        _showMorningBrief = true;
        _refreshWeatherBrief();
        _refreshCalendarBrief();
      }
    }

    if (_isAlarmRinging) return;

    final now = DateTime.now();
    int hour = now.hour;
    int minute = now.minute;
    String ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minuteStr = minute.toString().padLeft(2, '0');
    
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String currentDay = days[now.weekday - 1];
    
    String currentTimeStr = "$currentDay $hour:$minuteStr $ampm";
    String dailyTimeStr = "Daily $hour:$minuteStr $ampm";

    final activeLabels =
        _alarms.where((a) => a.isActive).map((a) => a.label).toSet();

    final matchesCurrent = activeLabels.contains(currentTimeStr) &&
        _lastRungAlarmTime != currentTimeStr;
    final matchesDaily = activeLabels.contains(dailyTimeStr) &&
        _lastRungAlarmTime != dailyTimeStr;

    if (matchesCurrent || matchesDaily) {
      final matchedAlarm = matchesCurrent ? currentTimeStr : dailyTimeStr;
      setState(() {
        _isAlarmRinging = true;
        _ringingAlarmLabel = matchedAlarm;
        _lastRungAlarmTime = matchedAlarm;
      });
      _startAlarmSound();
    }
  }

  void _snoozeAlarm() {
    _stopAlarmSound(); 

    final now = DateTime.now().add(const Duration(minutes: 5));
    int hour = now.hour;
    int minute = now.minute;
    String ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minuteStr = minute.toString().padLeft(2, '0');
    
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String currentDay = days[now.weekday - 1];

    String snoozeTime = "$currentDay $hour:$minuteStr $ampm";

    setState(() {
      _isAlarmRinging = false;
      _ringingAlarmLabel = null;
      final existing =
          _alarms.indexWhere((a) => a.label == snoozeTime);
      if (existing == -1) {
        _alarms.add(AppAlarm(label: snoozeTime, isActive: true));
      } else {
        _alarms[existing].isActive = true;
      }
    });
    _saveAlarms();

    NotifyPill.show(context, 'Snoozed for 5 minutes ($snoozeTime)', icon: Icons.snooze);
  }

  void _stopAlarm() {
    setState(() {
      _ringingAlarmLabel = null;
      // Another ringing source (e.g. a timer) may still be active.
      _isAlarmRinging = _ringingTimerIndices.isNotEmpty;
    });
    if (!_isAlarmRinging) _stopAlarmSound();
  }

  /// Stop every timer currently going off. Resets each to its starting
  /// value and clears the ringing set. If no alarm is also ringing, this
  /// also stops the alarm sound. Called by a single tap on the timer pill
  /// while any timer is ringing — one tap kills the whole chorus.
  void _stopAllRingingTimers() {
    if (_ringingTimerIndices.isEmpty) return;
    setState(() {
      for (final idx in _ringingTimerIndices) {
        if (idx < 0 || idx >= _appTimers.length) continue;
        final t = _appTimers[idx];
        t.isRunning = false;
        t.endTime = null;
        t.remainingSeconds = t.totalSeconds;
      }
      _ringingTimerIndices = {};
      _isAlarmRinging = _ringingAlarmLabel != null;
    });
    if (!_isAlarmRinging) _stopAlarmSound();
    _saveTimers();
  }

  /// Stop-and-reset from a left-to-right swipe on a non-ringing timer pill.
  /// Resets the timer to its full value and stops it. The timer stays on
  /// the home screen (since it is still active) but in a paused state.
  void _stopAndResetTimer(int index) {
    if (index < 0 || index >= _appTimers.length) return;
    setState(() {
      final t = _appTimers[index];
      t.isRunning = false;
      t.endTime = null;
      t.remainingSeconds = t.totalSeconds;
    });
    _saveTimers();
  }

  // --- Advanced Background Timer Logic ---
  String _formatTimerTime(int totalSeconds) {
    int h = totalSeconds ~/ 3600;
    int m = (totalSeconds % 3600) ~/ 60;
    int s = totalSeconds % 60;
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    } else {
      return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
  }

  void _tickTimers() {
    bool anyRunning = false;
    final newlyRinging = <int>{};
    final now = DateTime.now();

    for (int i = 0; i < _appTimers.length; i++) {
      final t = _appTimers[i];
      // Inactive timers are frozen — skip entirely.
      if (!t.isActive) continue;
      if (t.isRunning && t.endTime != null) {
        anyRunning = true;
        t.remainingSeconds = t.endTime!.difference(now).inSeconds;

        if (t.remainingSeconds <= 0) {
          // Keep at zero (not reset) so the ringing pill shows 00:00 until
          // the user taps to stop. The reset happens in
          // _stopAllRingingTimers.
          t.remainingSeconds = 0;
          t.isRunning = false;
          t.endTime = null;
          newlyRinging.add(i);
        }
      }
    }

    if (newlyRinging.isNotEmpty) {
      final wasRinging = _isAlarmRinging;
      setState(() {
        _ringingTimerIndices = _ringingTimerIndices.union(newlyRinging);
        _isAlarmRinging = true;
      });
      // Only (re)start the alarm chorus if nothing was already ringing —
      // otherwise the currently-playing sound keeps going and additional
      // timers join the same ringing session.
      if (!wasRinging) _startAlarmSound();
      _saveTimers();
    }

    if (mounted) setState(() {});

    if (!anyRunning) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _saveTimers();
    }
  }

  void _syncTimersOnResume() {
    _tickTimers();
    if (_appTimers.any((t) => t.isActive && t.isRunning) &&
        (_countdownTimer == null || !_countdownTimer!.isActive)) {
      _countdownTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
    }
  }

  void _toggleTimer(int index) {
    if (index < 0 || index >= _appTimers.length) return;

    var t = _appTimers[index];
    setState(() {
      if (t.isRunning) {
        t.isRunning = false;
        t.endTime = null;
      } else {
        if (t.remainingSeconds <= 0) t.remainingSeconds = t.totalSeconds;
        t.isRunning = true;
        t.endTime = DateTime.now().add(Duration(seconds: t.remainingSeconds));

        if (_countdownTimer == null || !_countdownTimer!.isActive) {
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
        }
      }
    });
    _saveTimers();
  }

  Future<void> _initApps() async {
    final fastApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: false);
    fastApps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _loadSavedLayout(fastApps);
    if (mounted) {
      setState(() {
        _apps = fastApps;
        _isLoading = false;
      });
    }

    final fullApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);
    fullApps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _loadSavedLayout(fullApps);

    _cachedFullApps = fullApps;

    if (mounted) {
      setState(() {
        _apps = fullApps;
      });
    }
  }

  Future<void> _checkAppChangesOnResume() async {
    if (_isLoading) return; 

    try {
      final currentFastApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: false);
      
      final currentPackages = currentFastApps.map((e) => e.packageName).toSet();
      final loadedPackages = _apps.map((e) => e.packageName).toSet();

      if (currentPackages.length == loadedPackages.length && currentPackages.containsAll(loadedPackages)) {
        return;
      }

      // Purge foresight data for apps that were removed
      final removedPackages = loadedPackages.difference(currentPackages);
      for (final pkg in removedPackages) {
        ForesightService.instance.purgeApp(pkg);
      }

      final fullApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);
      fullApps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      
      _cachedFullApps = fullApps;
      await _loadSavedLayout(fullApps);

      if (mounted) {
        setState(() {
          _apps = fullApps;
        });
      }
    } catch (e) {
      debugPrint("Error checking app changes: $e");
    }
  }

  Future<void> _loadSavedLayout(List<AppInfo> availableApps) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedLayout = prefs.getStringList('home_layout') ?? [];
    final Map<int, AppInfo> tempLayout = {};

    for (String item in savedLayout) {
      final parts = item.split(':');
      if (parts.length != 2) continue;

      final int index = int.tryParse(parts[0]) ?? -1;
      final String packageName = parts[1];

      if (index >= 0 && index < _maxHomeApps) {
        try {
          final app = availableApps.firstWhere((a) => a.packageName == packageName);
          tempLayout[index] = app;
        } catch (_) {}
      }
    }

    _homeApps.clear();
    _homeApps.addAll(tempLayout);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _immersiveMode = prefs.getBool('immersive_mode') ?? false;
      _temperatureUnit = prefs.getString('temperature_unit') ?? 'C';
      _showClock = prefs.getBool('show_clock') ?? true;
      _showDate = prefs.getBool('show_date') ?? true;
      _spatialMode = prefs.getBool('spatial_mode') ?? false;
    });
    _applyImmersiveMode();
    if (_spatialMode) await _loadSpatialPositions();
    await _wallpaperService.initialize();
    // Foresight state (including the long-press app) and the Morning
    // Brief dismiss flag may have been changed from the settings page —
    // reload so the home screen reflects it immediately on return.
    await _loadForesightState();
    await _loadMorningBriefState();
    await _loadWeatherWidgetState();
    if (mounted) setState(() {});
  }

  void _applyImmersiveMode() {
    if (_immersiveMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> layout = _homeApps.entries
        .map((e) => '${e.key}:${e.value.packageName}')
        .toList();
    await prefs.setStringList('home_layout', layout);
  }

  Future<void> _loadMorningBriefState() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissDay = prefs.getInt('morning_brief_dismiss_day') ?? -1;
    final today = DateTime.now().day;
    final dismissed = dismissDay == today;
    final wasShowing = _showMorningBrief;
    setState(() {
      _morningBriefDismissDay = dismissDay;
      _showMorningBrief = !dismissed;
      // If the brief is being re-shown (e.g. after the user hit
      // "Show Brief Again" in settings), force the panel to recreate
      // at page 0 so it doesn't resume mid-flow.
      if (!wasShowing && _showMorningBrief) {
        _morningBriefKey++;
      }
    });
    if (!wasShowing && _showMorningBrief) {
      _refreshWeatherBrief();
      _refreshCalendarBrief();
    }
  }

  Future<void> _dismissMorningBrief() async {
    final today = DateTime.now().day;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('morning_brief_dismiss_day', today);
    setState(() {
      _morningBriefDismissDay = today;
      _showMorningBrief = false;
    });
  }


  Future<void> _loadForesightState() async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getBool('foresight_hidden') ?? false;
    final longPressPkg = prefs.getString('foresight_longpress_package') ?? '';
    if (mounted) {
      setState(() {
        _showForesight = !hidden;
        _foresightLongPressPackage = longPressPkg;
      });
    }
  }

  Future<void> _loadWeatherWidgetState() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool('weather_widget_active') ?? false;
    if (mounted) setState(() => _weatherWidgetActive = active);
  }


  /// Launches the user's chosen "foresight long-press" app. An empty
  /// package string means "open the system's default browser" via an
  /// http: intent that Android resolves to whatever browser the user
  /// has set as default.
  Future<void> _onForesightLongPress() async {
    HapticFeedback.mediumImpact();
    if (_foresightLongPressPackage.isEmpty) {
      try {
        // about:blank is the most neutral URL that still routes through
        // the user's configured default browser.
        final uri = Uri.parse('https://www.google.com/');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Failed to open default browser: $e');
      }
    } else {
      AppLauncher.launchApp(_foresightLongPressPackage);
    }
  }

  Future<void> _refreshWeatherBrief() async {
    final data = await WeatherBriefService.generateBrief();
    if (mounted && data != null) {
      setState(() {
        _weatherBriefData = data;
      });
    }
  }

  Future<void> _refreshCalendarBrief() async {
    final data = await CalendarBriefService.instance.getTodayEvents();
    if (mounted) {
      setState(() {
        _calendarBriefData = data;
      });
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList =
        _alarms.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList('active_alarms', jsonList);
  }

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('active_alarms');
    if (saved == null) return;
    final loaded = <AppAlarm>[];
    for (final entry in saved) {
      try {
        // New-format entries are JSON objects; legacy rows are plain
        // label strings. Legacy rows migrate in as Active so existing
        // alarms keep ringing through the upgrade.
        if (entry.startsWith('{')) {
          loaded.add(AppAlarm.fromJson(jsonDecode(entry)));
        } else {
          loaded.add(AppAlarm(label: entry, isActive: true));
        }
      } catch (e) {
        debugPrint('Error loading alarm "$entry": $e');
      }
    }
    setState(() => _alarms = loaded);
  }

  Future<void> _saveTimers() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _appTimers.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList('app_timers', jsonList);
  }

  Future<void> _loadTimers() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('app_timers');
    if (saved != null) {
      final now = DateTime.now();
      final loaded = <AppTimer>[];
      for (final jsonStr in saved) {
        try {
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          // Legacy rows have no `isActive` field; migrate as Active so
          // any in-flight timers keep ticking after the upgrade.
          final hadIsActive = map.containsKey('isActive');
          final t = AppTimer.fromJson(map);
          if (!hadIsActive) t.isActive = true;

          if (t.isRunning && t.endTime != null) {
            final remaining = t.endTime!.difference(now).inSeconds;
            if (remaining <= 0) {
              t.remainingSeconds = t.totalSeconds;
              t.isRunning = false;
              t.endTime = null;
            } else {
              t.remainingSeconds = remaining;
            }
          }
          loaded.add(t);
        } catch (e) {
          debugPrint("Error loading timer: $e");
        }
      }
      setState(() {
        _appTimers = loaded;
      });
      if (_appTimers.any((t) => t.isActive && t.isRunning)) {
        _countdownTimer ??= Timer.periodic(
            const Duration(seconds: 1), (_) => _tickTimers());
      }
    }
  }

  void _addToHomeScreen(AppInfo app) {
    if (_homeApps.values.any((element) => element.packageName == app.packageName)) {
      return;
    }

    for (int i = 0; i < _maxHomeApps; i++) {
      if (!_homeApps.containsKey(i)) {
        setState(() {
          _homeApps[i] = app;
        });
        _saveLayout();
        NotifyPill.show(context, '${app.name} added to Home Screen', icon: Icons.add_to_home_screen);
        return;
      }
    }
    
    NotifyPill.show(context, 'Home Screen is full!', icon: Icons.block);
  }

  // ── Spatial Layout ───────────────────────────────────────────────────────────

  Future<void> _loadSpatialPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, Offset> loaded = {};
    for (final key in ['clock', 'weather', 'schedule', 'foresight']) {
      final x = prefs.getDouble('spatial_${key}_x');
      final y = prefs.getDouble('spatial_${key}_y');
      if (x != null && y != null) loaded[key] = Offset(x, y);
    }
    if (mounted) {
      setState(() {
        _spatialPositions.clear();
        _spatialPositions.addAll(loaded);
      });
    }
  }

  Future<void> _saveSpatialPositions() async {
    final prefs = await SharedPreferences.getInstance();
    for (final e in _spatialPositions.entries) {
      await prefs.setDouble('spatial_${e.key}_x', e.value.dx);
      await prefs.setDouble('spatial_${e.key}_y', e.value.dy);
    }
  }

  Offset _defaultSpatialPos(String key, Size screen) {
    // Clock height = dateSlot(36) + clockFraction(0.17) * screenH + topPad(8)
    final double clockH = 36.0 + screen.height * 0.17 + 8.0;
    switch (key) {
      case 'clock':    return const Offset(0, 0);
      case 'weather':  return Offset(40, clockH + 4);
      case 'schedule': return Offset(40, clockH + 260);
      case 'foresight': return Offset(40, screen.height - 190);
      default: return Offset.zero;
    }
  }

  Widget _buildSpatialElement(String key, Size screen, Widget child) {
    final Offset pos = _spatialPositions[key] ?? _defaultSpatialPos(key, screen);
    final bool isDraggingThis = _activeDragKey == key;
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          setState(() {
            _activeDragKey = key;
            _dragStartElementPos =
                _spatialPositions[key] ?? _defaultSpatialPos(key, screen);
          });
        },
        onLongPressMoveUpdate: (details) {
          if (_activeDragKey == key) {
            setState(() => _spatialPositions[key] =
                _dragStartElementPos + details.offsetFromOrigin);
          }
        },
        onLongPressEnd: (_) {
          if (_activeDragKey == key) {
            setState(() => _activeDragKey = null);
            _saveSpatialPositions();
          }
        },
        child: AnimatedScale(
          scale: isDraggingThis ? 1.04 : 1.0,
          duration: CASIMotion.fast,
          child: child,
        ),
      ),
    );
  }

  Widget _buildSpatialHomeStack() {
    final Size screen = MediaQuery.of(context).size;
    return Stack(
      children: [
        const SizedBox.expand(),

        // Morning Brief + Music Player — non-draggable, pinned to top
        Positioned(
          top: 0, left: 0, right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                reverseDuration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                      sizeFactor: animation, axisAlignment: -1.0, child: child),
                ),
                child: (_showMorningBrief && !_isAlarmRinging)
                    ? Padding(
                        key: ValueKey('morning_brief_$_morningBriefKey'),
                        padding: const EdgeInsets.only(top: 12),
                        child: MorningBriefPanel(
                          weatherData: _weatherBriefData,
                          calendarData: _calendarBriefData,
                          onDismiss: _dismissMorningBrief,
                          temperatureUnit: _temperatureUnit,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no_brief')),
              ),
              Offstage(
                offstage: !_isPlayerVisible || _isAlarmRinging,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SongPlayer(
                    backgroundWidget: _wallpaperService.buildBackground(),
                    onVisibilityChanged: (visible) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _isPlayerVisible != visible) {
                          setState(() => _isPlayerVisible = visible);
                        }
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Clock / Date — draggable
        _buildSpatialElement('clock', screen,
          SizedBox(
            width: screen.width,
            child: GlassStatusBar(
              opacity: 1.0,
              showClock: _showClock,
              showDate: _showDate,
              backgroundWidget: _wallpaperService.buildBackground(),
            ),
          ),
        ),

        // Weather widget — draggable, only when active
        if (_weatherWidgetActive)
          _buildSpatialElement('weather', screen,
            ValueListenableBuilder<WeatherSnapshot>(
              valueListenable: WeatherService.instance.snapshot,
              builder: (ctx, snap, _) => LiquidGlassSurface.modal(
                backgroundWidget: _wallpaperService.buildBackground(),
                cornerRadius: CASILiquidGlass.cornerSheet,
                width: screen.width - 80,
                child: WeatherForecastWidget(
                  forecastData: snap.daily,
                  hourlyData: snap.hourly,
                  currentTemp: snap.tempLabel,
                  currentDescription: snap.description,
                  currentIcon: snap.icon,
                  currentIconColor: snap.iconColor,
                  feelsLike: snap.feelsLike,
                  wind: snap.wind,
                  precipitation: snap.precipitation,
                  humidity: snap.humidity,
                  uvIndex: snap.uvIndex,
                  sunrise: snap.sunrise,
                  visibility: snap.visibility,
                  location: snap.location,
                  lastUpdated: snap.lastUpdated,
                  isRefreshing: snap.isRefreshing,
                  onRefresh: () => WeatherService.instance.forceRefresh(),
                ),
              ),
            ),
          ),

        // Timer + Alarm pills — draggable
        _buildSpatialElement('schedule', screen,
          _buildScheduleStatusRow(spatial: true),
        ),

        // Foresight dock — draggable
        if (_foresightPredictions.isNotEmpty &&
            _showForesight &&
            _homeApps.isNotEmpty &&
            !_isAlarmRinging &&
            !_isDragging)
          _buildSpatialElement('foresight', screen,
            ForesightPill(
              predictions: _foresightPredictions,
              onAppTap: _onForesightAppTap,
              maxForesight: 6,
              onLongPress: null, // long-press starts drag in spatial mode
              backgroundWidget: _wallpaperService.buildBackground(),
            ),
          ),

        // Dock — fixed, never draggable per spec
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: TapRegion(
              groupId: 'dock_region',
              onTapOutside: null,
              child: ScreenDock(
                isDragging: _isDragging,
                showApps: !_isAlarmRinging,
                onRemove: (app) {
                  setState(() {
                    _homeApps.removeWhere(
                        (k, v) => v.packageName == app.packageName);
                    _isDragging = false;
                    _draggingApp = null;
                  });
                  _saveLayout();
                },
                onUninstall: (app) {
                  setState(() {
                    _isDragging = false;
                    _draggingApp = null;
                  });
                  ForesightService.instance.purgeApp(app.packageName);
                  try {
                    InstalledApps.uninstallApp(app.packageName);
                  } catch (e) {
                    debugPrint('Uninstall error: $e');
                  }
                },
                onCancel: () => setState(
                    () { _isDragging = false; _draggingApp = null; }),
                homeApps: _homeApps,
                maxHomeApps: _maxHomeApps,
                onAppDropped: (index, app) => _onAppDropped(index, app),
                onAppTap: (app) {
                  ForesightService.instance
                      .recordLaunch(app.packageName, appName: app.name);
                  AppLauncher.launchApp(app.packageName);
                },
                onDragStarted: (app) => setState(() {
                  _isDragging = true;
                  _draggingApp = app;
                }),
                draggingApp: _draggingApp,
                emptyDockWidget: null,
                activePill: null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_drawerController.isAttached && _drawerController.size > 0.1) {
          _drawerController.animateTo(0.0, duration: const Duration(milliseconds: 120), curve: Curves.easeOutCubic);
        }
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildBackground(),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              if (_drawerProgress.value > 0.05 || _isAlarmRinging) {
                return;
              }
              const MethodChannel('casi.launcher/apps').invokeMethod('lockScreen');
            },
            onLongPress: null,
            onVerticalDragStart: (details) {
              _dragStartY = details.globalPosition.dy;
            },
            onVerticalDragEnd: (details) {
              final double screenHeight = MediaQuery.of(context).size.height;
              final double velocity = details.primaryVelocity ?? 0;
              final bool drawerOpen = _drawerController.isAttached &&
                  _drawerController.size > 0.05;

              if (drawerOpen) {
                // Once the drawer is showing, a swipe anywhere on screen
                // expands it to full or closes it entirely.
                if (velocity < -500) {
                  _drawerController.animateTo(
                    1.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                  );
                } else if (velocity > 500) {
                  _drawerController.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                  );
                }
              } else {
                // Drawer closed: a swipe up from anywhere but the very
                // bottom edge opens it to the full app drawer.
                if (_dragStartY < screenHeight - 60 && velocity < -500) {
                  _drawerController.animateTo(
                    1.0,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                  );
                }
              }
            },
            child: SafeArea(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          children: [
                            ValueListenableBuilder<double>(
                              valueListenable: _drawerProgress,
                              builder: (context, progress, child) {
                                // Crossfade: homescreen widgets soften to
                                // invisible as the drawer rises, exposing the
                                // wallpaper at 100% opacity behind the apps
                                // (OneUI-style — no glass tint on the drawer).
                                final double homeOpacity =
                                    (1.0 - progress / 0.5).clamp(0.0, 1.0);
                                return IgnorePointer(
                                  ignoring: progress > 0.05,
                                  child: Opacity(
                                    opacity: homeOpacity,
                                    child: _spatialMode
                                        ? _buildSpatialHomeStack()
                                        : Stack(
                                  children: [
                                    const SizedBox.expand(),
                                    // TOP: Clock + Weather Pill + Brief + Music
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GlassStatusBar(
                                            opacity: 1.0,
                                            showClock: _showClock,
                                            showDate: _showDate,
                                            backgroundWidget: _wallpaperService.buildBackground(),
                                          ),
                                          const SizedBox(height: 4),
                                          // Pill row: Alarm > Weather > Timer (clipped to prevent transient overflow)
                                          ClipRect(child: _buildPillRow()),
                                          // Morning Brief panel — animated show/hide
                                          AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 400),
                                            reverseDuration: const Duration(milliseconds: 350),
                                            switchInCurve: Curves.easeOutCubic,
                                            switchOutCurve: Curves.easeInCubic,
                                            transitionBuilder: (child, animation) {
                                              return FadeTransition(
                                                opacity: animation,
                                                child: SizeTransition(
                                                  sizeFactor: animation,
                                                  axisAlignment: -1.0,
                                                  child: child,
                                                ),
                                              );
                                            },
                                            child: (_showMorningBrief && !_isAlarmRinging)
                                                ? Padding(
                                                    key: ValueKey('morning_brief_$_morningBriefKey'),
                                                    padding: const EdgeInsets.only(top: 12),
                                                    child: MorningBriefPanel(
                                                      weatherData: _weatherBriefData,
                                                      calendarData: _calendarBriefData,
                                                      onDismiss: _dismissMorningBrief,
                                                      temperatureUnit: _temperatureUnit,
                                                    ),
                                                  )
                                                : const SizedBox.shrink(key: ValueKey('no_brief')),
                                          ),
                                          // Schedule status row — Timer (left) & Alarm (right)
                                          // pills above the music player. Stays visible with
                                          // weather expanded or clock/timer panels open.
                                          _buildScheduleStatusRow(),
                                          // Music Player
                                          Offstage(
                                            offstage: !_isPlayerVisible || _isAlarmRinging,
                                            child: Padding(
                                              padding: const EdgeInsets.only(top: 12),
                                              child: SongPlayer(
                                                backgroundWidget: _wallpaperService.buildBackground(),
                                                onVisibilityChanged: (visible) {
                                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                                    if (mounted && _isPlayerVisible != visible) {
                                                      setState(() => _isPlayerVisible = visible);
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // BOTTOM: Status Pills + Dock
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          bottom: MediaQuery.of(context).viewInsets.bottom,
                                        ),
                                        child: TapRegion(
                                        groupId: 'dock_region',
                                        onTapOutside: null,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Foresight prediction pill — above dock
                                            AnimatedSwitcher(
                                              duration: CASIMotion.standard,
                                              switchInCurve: Curves.easeOutCubic,
                                              switchOutCurve: Curves.easeInCubic,
                                              transitionBuilder: (child, animation) => FadeTransition(
                                                opacity: animation,
                                                child: SlideTransition(
                                                  position: Tween<Offset>(
                                                    begin: const Offset(0, 0.5),
                                                    end: Offset.zero,
                                                  ).animate(animation),
                                                  child: child,
                                                ),
                                              ),
                                              child: (_foresightPredictions.isNotEmpty &&
                                                      _showForesight &&
                                                      _homeApps.isNotEmpty &&
                                                      !_isAlarmRinging &&
                                                      !_isDragging)
                                                  ? Padding(
                                                      key: const ValueKey('foresight_pill'),
                                                      padding: const EdgeInsets.only(bottom: 12),
                                                      child: ForesightPill(
                                                        predictions: _foresightPredictions,
                                                        onAppTap: _onForesightAppTap,
                                                        maxForesight: 6,
                                                        onLongPress: _onForesightLongPress,
                                                        backgroundWidget: _wallpaperService.buildBackground(),
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(
                                                      key: ValueKey('no_foresight')),
                                            ),
                                            ScreenDock(
                                              isDragging: _isDragging,
                                              showApps: !_isAlarmRinging,
                                              onRemove: (app) {
                                                setState(() {
                                                  _homeApps.removeWhere((key, value) => value.packageName == app.packageName);
                                                  _isDragging = false;
                                                  _draggingApp = null;
                                                });
                                                _saveLayout();
                                              },
                                              onUninstall: (app) {
                                                setState(() {
                                                  _isDragging = false;
                                                  _draggingApp = null;
                                                });
                                                ForesightService.instance.purgeApp(app.packageName);
                                                try {
                                                  InstalledApps.uninstallApp(app.packageName);
                                                } catch (e) {
                                                  debugPrint("Uninstall error: $e");
                                                }
                                              },
                                              onCancel: () => setState(() {
                                                _isDragging = false;
                                                _draggingApp = null;
                                              }),
                                              homeApps: _homeApps,
                                              maxHomeApps: _maxHomeApps,
                                              onAppDropped: (index, app) => _onAppDropped(index, app),
                                              onAppTap: (app) {
                                                ForesightService.instance.recordLaunch(app.packageName, appName: app.name);
                                                AppLauncher.launchApp(app.packageName);
                                              },
                                              onDragStarted: (app) => setState(() {
                                                _isDragging = true;
                                                _draggingApp = app;
                                              }),
                                              draggingApp: _draggingApp,
                                              emptyDockWidget: (_foresightPredictions.isNotEmpty &&
                                                      _showForesight &&
                                                      !_isAlarmRinging)
                                                  ? ForesightPill(
                                                      predictions: _foresightPredictions,
                                                      onAppTap: _onForesightAppTap,
                                                      maxForesight: 6,
                                                      onLongPress: _onForesightLongPress,
                                                      backgroundWidget: _wallpaperService.buildBackground(),
                                                    )
                                                  : null,
                                              activePill: null,
                                            ),
                                          ],
                                        ),
                                      ),
                                      ),
                                    ),
                                  ],
                                ),
                                  ),
                                );
                              },
                            ),
                            AppDrawer(
                              apps: _apps,
                              progressNotifier: _drawerProgress,
                              controller: _drawerController,
                              backgroundWidget: _wallpaperService.buildBackground(),
                              onAppTap: (app) {
                                ForesightService.instance.recordLaunch(app.packageName, appName: app.name);
                                setState(() => _foresightPredictions = []);
                                AppLauncher.launchApp(app.packageName);
                              },
                              onAddToHome: (app) => _addToHomeScreen(app),
                              onUninstall: (app) {
                                ForesightService.instance.purgeApp(app.packageName);
                                try {
                                  InstalledApps.uninstallApp(app.packageName);
                                } catch (e) {
                                  debugPrint("Uninstall error: $e");
                                }
                              },
                              onOpenSettings: () {
                                Navigator.push(context, PageRouteBuilder(
                                      pageBuilder: (context, animation, secondaryAnimation) => const SettingsPage(),
                                      transitionDuration: const Duration(milliseconds: 80),
                                      reverseTransitionDuration: const Duration(milliseconds: 60),
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                        return FadeTransition(
                                          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                                          child: child,
                                        );
                                      },
                                    )).then((_) => _loadSettings());
                              },
                            ),
                          ],
                      ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  // --- Nearest active alarm (returns time string like "Mon 8:30 AM", or null) ---
  String? _nearestAlarmLabel() {
    final activeLabels =
        _alarms.where((a) => a.isActive).map((a) => a.label).toList();
    if (activeLabels.isEmpty) return null;
    final now = DateTime.now();
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    Duration? bestDiff;
    String? bestLabel;

    for (final alarm in activeLabels) {
      final parts = alarm.split(' ');
      String dayPart;
      String timePart;
      String amPmPart;
      if (parts.length == 3) {
        dayPart = parts[0];
        timePart = parts[1];
        amPmPart = parts[2];
      } else if (parts.length == 2) {
        dayPart = 'Daily';
        timePart = parts[0];
        amPmPart = parts[1];
      } else {
        continue;
      }

      final tp = timePart.split(':');
      int hour = int.tryParse(tp[0]) ?? 0;
      int minute = int.tryParse(tp[1]) ?? 0;
      if (amPmPart == 'PM' && hour != 12) hour += 12;
      if (amPmPart == 'AM' && hour == 12) hour = 0;

      int targetWeekday;
      if (dayPart == 'Daily') {
        targetWeekday = now.weekday;
      } else {
        targetWeekday = dayNames.indexOf(dayPart) + 1;
        if (targetWeekday <= 0) continue;
      }

      var target = DateTime(now.year, now.month, now.day, hour, minute);
      int dayDiff = targetWeekday - now.weekday;
      if (dayDiff < 0) dayDiff += 7;
      if (dayDiff == 0 && target.isBefore(now)) {
        dayDiff = dayPart == 'Daily' ? 1 : 7;
      }
      target = target.add(Duration(days: dayDiff));

      final diff = target.difference(now);
      if (bestDiff == null || diff < bestDiff) {
        bestDiff = diff;
        bestLabel = alarm;
      }
    }
    return bestLabel;
  }

  // --- Active timer indices, sorted lowest→highest remaining seconds ---
  // A timer shows on the home screen when the user has marked it Active in
  // the Widgets Screen. Multiple active timers render as a deck pill; this
  // returns their indices in display order (front = lowest remaining).
  List<int> _activeTimerIndicesSorted() {
    final entries = <({int index, int remaining})>[];
    for (int i = 0; i < _appTimers.length; i++) {
      final t = _appTimers[i];
      if (!t.isActive) continue;
      entries.add((index: i, remaining: t.remainingSeconds));
    }
    entries.sort((a, b) => a.remaining.compareTo(b.remaining));
    return entries.map((e) => e.index).toList();
  }

  // The home-screen weather slot. Renders the expanded forecast widget
  // only when the user has enabled weather in Settings — otherwise the
  // slot collapses to zero. The inline temperature beside the
  // date in [ClockCapsule] is what's shown in the inactive case.
  Widget _buildPillRow() {
    return AnimatedSize(
      duration: CASIMotion.standard,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _weatherWidgetActive
          ? Padding(
              padding: const EdgeInsets.fromLTRB(40, 8, 40, 0),
              child: ValueListenableBuilder<WeatherSnapshot>(
                valueListenable: WeatherService.instance.snapshot,
                builder: (context, snap, _) {
                  return LiquidGlassSurface.modal(
                    backgroundWidget: _wallpaperService.buildBackground(),
                    cornerRadius: CASILiquidGlass.cornerSheet,
                    width: double.infinity,
                    child: WeatherForecastWidget(
                      forecastData: snap.daily,
                      hourlyData: snap.hourly,
                      currentTemp: snap.tempLabel,
                      currentDescription: snap.description,
                      currentIcon: snap.icon,
                      currentIconColor: snap.iconColor,
                      feelsLike: snap.feelsLike,
                      wind: snap.wind,
                      precipitation: snap.precipitation,
                      humidity: snap.humidity,
                      uvIndex: snap.uvIndex,
                      sunrise: snap.sunrise,
                      visibility: snap.visibility,
                      location: snap.location,
                      lastUpdated: snap.lastUpdated,
                      isRefreshing: snap.isRefreshing,
                      onRefresh: () => WeatherService.instance.forceRefresh(),
                    ),
                  );
                },
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }

  // Schedule status row: alarm & timer pills above the music player.
  //
  // Pills are populated from:
  //   * The user's default clock app — system alarms come from
  //     `AlarmManager.getNextAlarmClock()`, system timers from the clock
  //     app's foreground notifications. System timers ride alongside CASI
  //     timers in the same swipe-able deck, sorted lowest→highest
  //     remaining time as the user requested.
  //
  // System timers carry a negative `timerIndex` sentinel so the pill's
  // tap/swipe callbacks can route them to the clock app instead of
  // mutating CASI state.
  Widget _buildScheduleStatusRow({bool spatial = false}) {
    final String? casiNearestAlarm =
        _ringingAlarmLabel ?? _nearestAlarmLabel();
    final String? systemAlarmLabel = _systemAlarm?.formattedLabel();
    // Prefer the system alarm when one is set — that's the "user's default
    // clock app" alarm they expect to see; CASI internal alarms still
    // appear when the system has none scheduled.
    final String? nearestAlarm = systemAlarmLabel ?? casiNearestAlarm;

    final List<int> activeTimerIndices = _activeTimerIndicesSorted();
    final bool hasAlarm = nearestAlarm != null;
    final bool hasTimer =
        activeTimerIndices.isNotEmpty || _systemTimers.isNotEmpty;
    final bool show = hasAlarm || hasTimer;

    Widget? timerPillWidget;
    if (hasTimer) {
      // Build a unified deck. CASI entries keep their real index; system
      // entries get -1, -2, ... so the callbacks can detect them and route
      // accordingly. Sort by remaining seconds so 1-min timers always sit
      // in front of 5-min ones, regardless of which source they came from.
      final deckEntries = <_DeckBuildEntry>[];
      for (final idx in activeTimerIndices) {
        final t = _appTimers[idx];
        deckEntries.add(_DeckBuildEntry(
          remaining: t.remainingSeconds,
          entry: TimerDeckEntry(
            timerIndex: idx,
            timeText: _formatTimerTime(t.remainingSeconds),
            isRunning: t.isRunning,
            isRinging: _ringingTimerIndices.contains(idx),
          ),
        ));
      }
      for (int i = 0; i < _systemTimers.length; i++) {
        final st = _systemTimers[i];
        final remaining = st.currentRemainingSeconds();
        deckEntries.add(_DeckBuildEntry(
          remaining: remaining,
          entry: TimerDeckEntry(
            // Sentinel negative index identifies a system timer.
            timerIndex: -(i + 1),
            timeText: _formatTimerTime(remaining),
            isRunning: st.isRunning,
            isRinging: false,
          ),
        ));
      }
      deckEntries.sort((a, b) => a.remaining.compareTo(b.remaining));

      timerPillWidget = TimerPill(
        entries: deckEntries.map((e) => e.entry).toList(),
        anyRinging: _ringingTimerIndices.isNotEmpty,
        onTap: () => SystemClockService.instance.openClockApp(),
        onTogglePause: _onTimerDeckTogglePause,
        onStopSingle: _onTimerDeckStop,
        onStopAllRinging: _stopAllRingingTimers,
        backgroundWidget: _wallpaperService.buildBackground(),
        compact: spatial,
      );
    }

    Widget? alarmPillWidget;
    if (hasAlarm) {
      // Only CASI internal alarms can ring inside CASI; the system clock
      // handles its own ringing UI for system alarms.
      final bool isCasiAlarmShown = systemAlarmLabel == null;
      final bool isThisRinging =
          isCasiAlarmShown && _ringingAlarmLabel == nearestAlarm;
      alarmPillWidget = AlarmPill(
        title: nearestAlarm,
        isRinging: isThisRinging,
        onTap: () => SystemClockService.instance.openClockApp(),
        onStop: _stopAlarm,
        backgroundWidget: _wallpaperService.buildBackground(),
        compact: spatial,
      );
    }

    Widget content;
    if (timerPillWidget != null && alarmPillWidget != null) {
      content = spatial
          // Compact pills: Row sizes to content, no Expanded needed.
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                timerPillWidget,
                const SizedBox(width: 12),
                alarmPillWidget,
              ],
            )
          : Row(
              children: [
                Expanded(child: timerPillWidget),
                const SizedBox(width: 12),
                Expanded(child: alarmPillWidget),
              ],
            );
    } else {
      content = timerPillWidget ?? alarmPillWidget ?? const SizedBox.shrink();
    }

    if (spatial) {
      if (!show) return const SizedBox.shrink();
      return content;
    }

    return AnimatedSize(
      duration: CASIMotion.standard,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: show
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: content,
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }

  // Routes a deck pause/resume gesture to the right backend. Negative
  // indices are system timers — we can't pause those from CASI, so we
  // open the user's clock app instead (which is the only way for them to
  // act on it).
  void _onTimerDeckTogglePause(int timerIndex) {
    if (timerIndex < 0) {
      SystemClockService.instance.openTimersScreen();
    } else {
      _toggleTimer(timerIndex);
    }
  }

  void _onTimerDeckStop(int timerIndex) {
    if (timerIndex < 0) {
      SystemClockService.instance.openTimersScreen();
    } else {
      _stopAndResetTimer(timerIndex);
    }
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: _wallpaperService.buildBackground(),
    );
  }

  void _onAppDropped(int newIndex, AppInfo data) {
    setState(() {
      final int? oldIndex = _homeApps.keys.cast<int?>().firstWhere(
            (k) => _homeApps[k]?.packageName == data.packageName,
            orElse: () => null,
          );

      // Swap: move the app at the target position to the old position
      final AppInfo? existingApp = _homeApps[newIndex];

      if (oldIndex != null) {
        if (existingApp != null) {
          _homeApps[oldIndex] = existingApp;
        } else {
          _homeApps.remove(oldIndex);
        }
      }
      _homeApps[newIndex] = data;
      _isDragging = false;
      _draggingApp = null;
    });
    _saveLayout();
  }

}

/// Lightweight tuple used while sorting CASI + system timers into a single
/// deck. The pill itself only sees the embedded [TimerDeckEntry]; the
/// `remaining` field exists purely so the merged list can be sorted by
/// remaining time before stripping back down.
class _DeckBuildEntry {
  final int remaining;
  final TimerDeckEntry entry;
  const _DeckBuildEntry({required this.remaining, required this.entry});
}