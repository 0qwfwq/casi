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
import '../widgets/clock_capsule.dart';
import '../widgets/weather_pill.dart';
import '../pills/dynamic_pill.dart';
import '../pills/d_clock_pill.dart';
import '../pills/d_calendar_pill.dart';
import '../utils/app_launcher.dart';
import '../widgets/notify_pill.dart';
import '../morning_brief/morning_brief_panel.dart';
import '../morning_brief/weather_brief_service.dart';
import '../morning_brief/calendar_brief_service.dart';
import '../services/wallpaper_service.dart';
import 'package:casi/services/foresight_service.dart';
import 'package:casi/services/notification_pill_service.dart';
import '../widgets/foresight_pill.dart';

class AppTimer {
  int totalSeconds;
  int remainingSeconds;
  bool isRunning;
  DateTime? endTime;

  AppTimer({required this.totalSeconds})
    : remainingSeconds = totalSeconds,
      isRunning = false;

  Map<String, dynamic> toJson() => {
    'totalSeconds': totalSeconds,
    'remainingSeconds': remainingSeconds,
    'isRunning': isRunning,
    'endTime': endTime?.millisecondsSinceEpoch,
  };

  factory AppTimer.fromJson(Map<String, dynamic> json) {
    final t = AppTimer(totalSeconds: json['totalSeconds'] as int);
    t.remainingSeconds = json['remainingSeconds'] as int;
    t.isRunning = json['isRunning'] as bool;
    final endMs = json['endTime'] as int?;
    if (endMs != null) {
      t.endTime = DateTime.fromMillisecondsSinceEpoch(endMs);
    }
    return t;
  }
}

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

  // --- Pill & Alarm State ---
  bool _showPill = false;
  bool _isAlarmMode = false;

  // --- Advanced Alarm States ---
  List<String> _activeAlarms = [];
  bool _isAlarmRinging = false;
  int? _selectedAlarmIndex;
  Timer? _alarmTimer;
  Timer? _notificationPollTimer;
  String? _lastRungAlarmTime;

  // --- Audio States ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _soundTimer;
  Timer? _vibrationTimer;
  double? _previousVolume;

  // --- Time Scroller States ---
  int _scrolledHour = 1;
  int _scrolledMinute = 0;
  String _scrolledAmPm = 'AM';
  List<String> _selectedDays = []; 

  // --- Stopwatch States ---
  bool _isStopwatchMode = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _stopwatchTimer;
  String _stopwatchTime = "00:00.00";
  final List<String> _stopwatchLaps = [];

  // --- Advanced Timer States ---
  bool _isTimerMode = false;
  bool _isCreatingTimer = false;
  bool _isEditingTimer = false; 
  
  List<AppTimer> _appTimers = []; 
  int? _selectedTimerIndex;
  Timer? _countdownTimer;

  int _scrolledTimerHour = 0;
  int _scrolledTimerMinute = 5;
  int _scrolledTimerSecond = 0;

  // --- Calendar States ---
  bool _isCalendarMode = false;
  bool _isViewingEvents = false;
  int? _selectedEventIndex;
  DateTime _calendarFocusedDay = DateTime.now();
  Map<DateTime, List<CalendarEvent>> _calendarEvents = {};

  // --- Morning Brief State ---
  bool _showMorningBrief = true;
  int _morningBriefDismissDay = -1;
  int _morningBriefKey = 0; // incremented to force panel reset to page 0
  WeatherBriefData? _weatherBriefData;
  CalendarBriefData? _calendarBriefData;
  bool _isForecastVisible = false;
  final GlobalKey _weatherPillKey = GlobalKey();

  String _temperatureUnit = 'C';

  // --- Foresight State ---
  List<ForesightPrediction> _foresightPredictions = [];
  bool _showForesight = true;
  int _foresightDockCount = 5;

  // --- Notification Pill State ---
  List<NotificationPillEntry> _notificationPillApps = [];

  // --- Foresight long-press launch target ---
  // Empty string means "use the system's default browser".
  String _foresightLongPressPackage = '';

  // --- Settings ---
  final WallpaperService _wallpaperService = WallpaperService();
  bool _immersiveMode = false;

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
    _loadCalendarEvents();
    _loadAlarms();
    _loadTimers();
    _loadMorningBriefState();
    _loadForesightState();
    _refreshWeatherBrief();
    _refreshCalendarBrief();


    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkAlarms();
    });

    _initForesight();
  }

  Future<void> _initForesight() async {
    await ForesightService.instance.initialize();
    await NotificationPillService.loadUserOverrides();
    await _refreshNotificationPill();
    _refreshForesightPredictions();
    // Poll notifications every 3 seconds for real-time updates
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshNotificationPill().then((_) => _refreshForesightPredictions());
    });
  }

  Future<void> _refreshForesightPredictions() async {
    if (!ForesightService.instance.isInitialized || _apps.isEmpty) return;
    final predictions = await ForesightService.instance.predict(_apps);
    final dockPackages = _homeApps.values.map((a) => a.packageName).toSet();
    // Exclude apps already on the home dock, and skip any that are
    // currently shown in a notification pill — the runner-up (#6) will
    // slide into the dock in that case so we always end up with 5.
    final notifPackages =
        _notificationPillApps.map((n) => n.packageName).toSet();
    final filtered = predictions
        .where((p) =>
            !dockPackages.contains(p.packageName) &&
            !notifPackages.contains(p.packageName))
        .take(_foresightDockCount)
        .toList();
    if (mounted) {
      setState(() => _foresightPredictions = filtered);
    }
  }

  Future<void> _refreshNotificationPill() async {
    final apps = await NotificationPillService.getNotificationPillApps();
    // Resolve icons from installed apps list
    final appMap = <String, AppInfo>{};
    for (final app in _apps) {
      appMap[app.packageName] = app;
    }
    final withIcons = apps.map((entry) {
      final installed = appMap[entry.packageName];
      return NotificationPillEntry(
        packageName: entry.packageName,
        tier: entry.tier,
        timestamp: entry.timestamp,
        icon: installed?.icon,
        appName: installed?.name ?? entry.appName,
        title: entry.title,
        text: entry.text,
      );
    }).toList();
    if (mounted) {
      setState(() => _notificationPillApps = withIcons);
    }
  }

  void _onForesightAppTap(String packageName) {
    ForesightService.instance.recordLaunch(packageName);
    AppLauncher.launchApp(packageName);
  }

  void _onNotificationPillTap(String packageName) {
    ForesightService.instance.recordLaunch(packageName);
    AppLauncher.launchApp(packageName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmTimer?.cancel();
    _notificationPollTimer?.cancel();
    _stopwatchTimer?.cancel();
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

      // Notification pill: re-evaluate queue on return
      _refreshNotificationPill().then((_) {
        // Foresight: generate predictions on unlock (after pill so dedup works)
        ForesightService.instance.onResume();
        _refreshForesightPredictions();
      });
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

    if ((_activeAlarms.contains(currentTimeStr) && _lastRungAlarmTime != currentTimeStr) ||
        (_activeAlarms.contains(dailyTimeStr) && _lastRungAlarmTime != dailyTimeStr)) {
      
      String matchedAlarm = _activeAlarms.contains(currentTimeStr) ? currentTimeStr : dailyTimeStr;

      setState(() {
        _isAlarmRinging = true;
        _showPill = true;
        _isAlarmMode = false;
        _isStopwatchMode = false;
        _isTimerMode = false;
        _isCalendarMode = false;
        _isViewingEvents = false;
        _selectedAlarmIndex = null;
        _selectedEventIndex = null;
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
      _showPill = false;
      if (!_activeAlarms.contains(snoozeTime)) {
        _activeAlarms.add(snoozeTime);
      }
    });
    _saveAlarms();

    NotifyPill.show(context, 'Snoozed for 5 minutes ($snoozeTime)', icon: Icons.snooze);
  }

  void _stopAlarm() {
    _stopAlarmSound(); 
    setState(() {
      _isAlarmRinging = false;
      _showPill = false;
    });
  }

  // --- Stopwatch Logic ---
  void _startStopwatchTimer() {
    _stopwatchTimer?.cancel();
    _stopwatchTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (_stopwatch.isRunning && mounted) {
        setState(() {
          _stopwatchTime = _formatStopwatchTime(_stopwatch.elapsed);
        });
      }
    });
  }

  String _formatStopwatchTime(Duration d) {
    String mins = d.inMinutes.toString().padLeft(2, '0');
    String secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    String ms = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return "$mins:$secs.$ms";
  }

  void _toggleStopwatch() {
    setState(() {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
      } else {
        _stopwatch.start();
        _startStopwatchTimer(); 
      }
    });
  }

  void _lapStopwatch() {
    if (_stopwatch.isRunning) {
      setState(() {
        _stopwatchLaps.insert(0, _stopwatchTime); 
      });
    }
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
    bool triggerRing = false;
    final now = DateTime.now();
    
    for (var t in _appTimers) {
      if (t.isRunning && t.endTime != null) {
        anyRunning = true;
        t.remainingSeconds = t.endTime!.difference(now).inSeconds;
        
        if (t.remainingSeconds <= 0) {
          t.remainingSeconds = t.totalSeconds; // Reset to total so it can be restarted easily
          t.isRunning = false;
          t.endTime = null;
          triggerRing = true;
        }
      }
    }

    if (triggerRing) {
      setState(() {
        _isAlarmRinging = true;
        _showPill = true;
        _isTimerMode = false;
      });
      _startAlarmSound();
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
    if (_appTimers.any((t) => t.isRunning) && (_countdownTimer == null || !_countdownTimer!.isActive)) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
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

  void _stopTimer() {
    if (_selectedTimerIndex == null || _appTimers.isEmpty) return;

    setState(() {
      var t = _appTimers[_selectedTimerIndex!];
      t.isRunning = false;
      t.endTime = null;
      t.remainingSeconds = t.totalSeconds;
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
    });
    _applyImmersiveMode();
    await _wallpaperService.initialize();
    // Foresight state (including the long-press app) and the Morning
    // Brief dismiss flag may have been changed from the settings page —
    // reload so the home screen reflects it immediately on return.
    await _loadForesightState();
    await _loadMorningBriefState();
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
    final dockCount = (prefs.getInt('foresight_dock_count') ?? 5).clamp(1, 7);
    if (mounted) {
      setState(() {
        _showForesight = !hidden;
        _foresightLongPressPackage = longPressPkg;
        _foresightDockCount = dockCount;
      });
    }
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
      // Auto-sync device calendar events into launcher events for today
      if (data.hasPermission && data.events.isNotEmpty) {
        _syncDeviceEventsToLauncher(data.events);
      }
    }
  }

  /// Copies device calendar events into the launcher's local calendar storage
  /// so they appear in the calendar pill alongside user-created events.
  void _syncDeviceEventsToLauncher(List<DeviceCalendarEvent> deviceEvents) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final existing = _calendarEvents[today] ?? [];
    final existingTitles = existing.map((e) => e.title).toSet();

    bool changed = false;
    for (final de in deviceEvents) {
      // Skip if an event with the same title already exists (avoid duplicates)
      if (existingTitles.contains(de.title)) continue;
      final launcherEvent = CalendarEvent(
        title: de.title,
        description: de.allDay
            ? 'All day'
            : '${de.timeString}${de.location.isNotEmpty ? ' · ${de.location}' : ''}',
      );
      existing.add(launcherEvent);
      existingTitles.add(de.title);
      changed = true;
    }

    if (changed) {
      setState(() {
        _calendarEvents[today] = existing;
      });
      _saveCalendarEvents();
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('active_alarms', _activeAlarms);
  }

  Future<void> _loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('active_alarms');
    if (saved != null) {
      setState(() {
        _activeAlarms = saved;
      });
    }
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
          final t = AppTimer.fromJson(jsonDecode(jsonStr));
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
      if (_appTimers.any((t) => t.isRunning)) {
        _countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
      }
    }
  }

  Future<void> _saveCalendarEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> serialized = {};
    _calendarEvents.forEach((date, events) {
      serialized[date.toIso8601String()] = events.map((e) => e.toJson()).toList();
    });
    await prefs.setString('calendar_events', jsonEncode(serialized));
  }

  Future<void> _loadCalendarEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString('calendar_events');
    if (jsonStr == null) return;
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      final Map<DateTime, List<CalendarEvent>> loaded = {};
      decoded.forEach((key, value) {
        final date = DateTime.parse(key);
        final normalized = DateTime(date.year, date.month, date.day);
        final events = (value as List)
            .map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList();
        loaded[normalized] = events;
      });
      setState(() {
        _calendarEvents = loaded;
      });
    } catch (e) {
      debugPrint("Error loading calendar events: $e");
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

  // --- Calendar Logic ---
  void _toggleCalendar() {
    setState(() {
      _showPill = true;
      _isCalendarMode = true;
      _isViewingEvents = false; 
      _selectedEventIndex = null;
      _isAlarmMode = false;
      _isStopwatchMode = false;
      _isTimerMode = false;
    });
  }

  void _dismissPill() {
    setState(() {
      _showPill = false;
      _isAlarmMode = false;
      _selectedAlarmIndex = null;
      _selectedDays = [];

      // CALENDAR CLEANUP
      _isCalendarMode = false;
      _isViewingEvents = false;
      _selectedEventIndex = null;

      // STOPWATCH CLEANUP
      _isStopwatchMode = false;
      _stopwatch.stop();
      _stopwatch.reset();
      _stopwatchTimer?.cancel();
      _stopwatchTime = "00:00.00";
      _stopwatchLaps.clear();

      // TIMER UI CLEANUP (But keeps running in background!)
      _isTimerMode = false;
      _isCreatingTimer = false;
      _isEditingTimer = false;
    });
  }

  // --- Glassmorphism Dialog to Add Events ---
  void _addCalendarEvent(String title) {
    setState(() {
      final date = DateTime(_calendarFocusedDay.year, _calendarFocusedDay.month, _calendarFocusedDay.day);
      final eventsList = _calendarEvents[date] ?? [];
      eventsList.add(CalendarEvent(title: title));
      _calendarEvents[date] = eventsList;
    });
    _saveCalendarEvents();
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
              if (_drawerProgress.value > 0.05 || _showPill || _isAlarmRinging ||
                  _isForecastVisible) {
                return;
              }
              const MethodChannel('casi.launcher/apps').invokeMethod('lockScreen');
            },
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
            child: NotificationListener<CalendarTapNotification>(
              onNotification: (notification) {
                if (_showPill && _isCalendarMode) {
                  _dismissPill();
                } else {
                  _toggleCalendar();
                }
                return true; 
              },
              child: NotificationListener<ClockTapNotification>(
                onNotification: (notification) {
                  if (_showPill && !_isStopwatchMode && !_isTimerMode && !_isCalendarMode) {
                    _dismissPill();
                  } else {
                    setState(() {
                      _showPill = true;
                      _isAlarmMode = false;
                      _isCalendarMode = false;
                      _isViewingEvents = false;
                      _selectedEventIndex = null;
                      _isStopwatchMode = false;
                      _isTimerMode = false;
                      _selectedAlarmIndex = null;
                      _selectedDays = [];
                      _scrolledHour = 1;
                      _scrolledMinute = 0;
                      _scrolledAmPm = 'AM';
                    });
                  }
                  return true; 
                },
                child: SafeArea(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Stack(
                          children: [
                            ValueListenableBuilder<double>(
                              valueListenable: _drawerProgress,
                              builder: (context, progress, child) {
                                return Stack(
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
                                          GlassStatusBar(opacity: 1.0),
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
                                            child: (_showMorningBrief && !_showPill && !_isAlarmRinging)
                                                ? Padding(
                                                    key: ValueKey('morning_brief_$_morningBriefKey'),
                                                    padding: const EdgeInsets.only(top: 12),
                                                    child: MorningBriefPanel(
                                                      weatherData: _weatherBriefData,
                                                      calendarData: _calendarBriefData,
                                                      launcherEvents: _calendarEvents,
                                                      onDismiss: _dismissMorningBrief,
                                                      temperatureUnit: _temperatureUnit,
                                                    ),
                                                  )
                                                : const SizedBox.shrink(key: ValueKey('no_brief')),
                                          ),
                                          // Music Player
                                          Offstage(
                                            offstage: !_isPlayerVisible || _isAlarmRinging,
                                            child: Padding(
                                              padding: const EdgeInsets.only(top: 12),
                                              child: SongPlayer(
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
                                        onTapOutside: (event) {
                                          if (_isAlarmRinging) {
                                            return;
                                          } else if (_showPill && _isCalendarMode && _isViewingEvents) {
                                            setState(() {
                                              _isViewingEvents = false;
                                              _selectedEventIndex = null;
                                            });
                                          } else if (_showPill) {
                                            _dismissPill();
                                          }
                                        },
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
                                              child: ((_foresightPredictions.isNotEmpty || _notificationPillApps.isNotEmpty) &&
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
                                                        maxForesight: _foresightDockCount,
                                                        notificationApps: _notificationPillApps,
                                                        onNotificationTap: _onNotificationPillTap,
                                                        onLongPress: _onForesightLongPress,
                                                      ),
                                                    )
                                                  : const SizedBox.shrink(
                                                      key: ValueKey('no_foresight')),
                                            ),
                                            ScreenDock(
                                              isDragging: _isDragging,
                                              showApps: !_showPill && !_isAlarmRinging,
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
                                              emptyDockWidget: ((_foresightPredictions.isNotEmpty || _notificationPillApps.isNotEmpty) &&
                                                      _showForesight &&
                                                      !_isAlarmRinging)
                                                  ? ForesightPill(
                                                      predictions: _foresightPredictions,
                                                      onAppTap: _onForesightAppTap,
                                                      maxForesight: _foresightDockCount,
                                                      notificationApps: _notificationPillApps,
                                                      onNotificationTap: _onNotificationPillTap,
                                                      onLongPress: _onForesightLongPress,
                                                    )
                                                  : null,
                                              activePill: _showPill
                                                  ? DynamicPill(
                                                      key: const ValueKey('main_dynamic_pill'),
                                                      child: _isCalendarMode 
                                                        ? DCalendarPill(
                                                            focusedDay: _calendarFocusedDay,
                                                            isViewingEvents: _isViewingEvents,
                                                            events: _calendarEvents,
                                                            selectedEventIndex: _selectedEventIndex,
                                                            onEventSelected: (index) {
                                                              setState(() {
                                                                _selectedEventIndex = (_selectedEventIndex == index) ? null : index;
                                                              });
                                                            },
                                                            onDateSelected: (date) {
                                                              setState(() {
                                                                _calendarFocusedDay = date;
                                                                _selectedEventIndex = null;
                                                              });
                                                            },
                                                            onViewEvents: () => setState(() => _isViewingEvents = true),
                                                            onSaveEvent: _addCalendarEvent,
                                                            onDeleteEvent: () {
                                                              if (_selectedEventIndex != null) {
                                                                setState(() {
                                                                  final date = DateTime(_calendarFocusedDay.year, _calendarFocusedDay.month, _calendarFocusedDay.day);
                                                                  if (_calendarEvents[date] != null && _selectedEventIndex! < _calendarEvents[date]!.length) {
                                                                    _calendarEvents[date]!.removeAt(_selectedEventIndex!);
                                                                    _selectedEventIndex = null;
                                                                  }
                                                                });
                                                                _saveCalendarEvents();
                                                              } else {
                                                                NotifyPill.show(context, 'Select an event to delete', icon: Icons.touch_app);
                                                              }
                                                            },
                                                            onCloseEvents: () => setState(() {
                                                              _isViewingEvents = false;
                                                              _selectedEventIndex = null;
                                                            }),
                                                          )
                                                        : DClockPill(
                                                            isAlarmMode: _isAlarmMode,
                                                            isAlarmRinging: _isAlarmRinging,
                                                            activeAlarms: _activeAlarms,
                                                            selectedIndex: _selectedAlarmIndex,
                                                            selectedDays: _selectedDays,
                                                            isStopwatchMode: _isStopwatchMode,
                                                            isStopwatchRunning: _stopwatch.isRunning,
                                                            stopwatchTime: _stopwatchTime,
                                                            stopwatchLaps: _stopwatchLaps,
                                                            isTimerMode: _isTimerMode,
                                                            isCreatingTimer: _isCreatingTimer,
                                                            isEditingTimer: _isEditingTimer,
                                                            savedTimersTimes: _appTimers.map((t) => _formatTimerTime(t.remainingSeconds)).toList(),
                                                            savedTimersRunning: _appTimers.map((t) => t.isRunning).toList(),
                                                            savedTimersAtStart: _appTimers.map((t) => t.remainingSeconds == t.totalSeconds).toList(),
                                                            selectedTimerIndex: _selectedTimerIndex,
                                                            initialHour: _scrolledHour,
                                                            initialMinute: _scrolledMinute,
                                                            initialAmPm: _scrolledAmPm,
                                                            initialTimerHour: _scrolledTimerHour,
                                                            initialTimerMinute: _scrolledTimerMinute,
                                                            initialTimerSecond: _scrolledTimerSecond,

                                                            // --- Alarm Callbacks ---
                                                            onAlarmTapped: () => setState(() {
                                                              _isAlarmMode = false;
                                                              _isStopwatchMode = false;
                                                              _isTimerMode = false;
                                                              _selectedAlarmIndex = null;
                                                              _selectedDays = [];
                                                              _scrolledHour = 1;
                                                              _scrolledMinute = 0;
                                                              _scrolledAmPm = 'AM';
                                                            }),
                                                            onAlarmRowTapped: (index) {
                                                              setState(() {
                                                                _selectedAlarmIndex = _selectedAlarmIndex == index ? null : index;
                                                              });
                                                            },
                                                            onAddNewAlarmTapped: () => setState(() {
                                                              _selectedAlarmIndex = null;
                                                              _selectedDays = [
                                                                const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][DateTime.now().weekday - 1]
                                                              ];
                                                              _scrolledHour = 8;
                                                              _scrolledMinute = 0;
                                                              _scrolledAmPm = 'AM';
                                                              _isAlarmMode = true;
                                                            }),
                                                            onEditSelectedAlarm: () {
                                                              if (_selectedAlarmIndex == null) return;
                                                              final alarm = _activeAlarms[_selectedAlarmIndex!];
                                                              final parts = alarm.split(' ');
                                                              setState(() {
                                                                if (parts.length == 3) {
                                                                  _selectedDays = [parts[0]];
                                                                  final timeParts = parts[1].split(':');
                                                                  _scrolledHour = int.parse(timeParts[0]);
                                                                  _scrolledMinute = int.parse(timeParts[1]);
                                                                  _scrolledAmPm = parts[2];
                                                                } else if (parts.length == 2) {
                                                                  _selectedDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                                                  final timeParts = parts[0].split(':');
                                                                  _scrolledHour = int.parse(timeParts[0]);
                                                                  _scrolledMinute = int.parse(timeParts[1]);
                                                                  _scrolledAmPm = parts[1];
                                                                }
                                                                _isAlarmMode = true;
                                                              });
                                                            },
                                                            onCancelAlarmTapped: () => setState(() {
                                                              _isAlarmMode = false;
                                                              _selectedDays = [];
                                                            }),
                                                            onSaveAlarmTapped: () {
                                                              setState(() {
                                                                String minStr = _scrolledMinute.toString().padLeft(2, '0');
                                                                String timeStr = "$_scrolledHour:$minStr $_scrolledAmPm";

                                                                if (_selectedAlarmIndex != null) {
                                                                  // Editing: replace the single selected alarm
                                                                  if (_selectedDays.length == 7) {
                                                                    _activeAlarms[_selectedAlarmIndex!] = timeStr;
                                                                  } else if (_selectedDays.isNotEmpty) {
                                                                    _activeAlarms[_selectedAlarmIndex!] = "${_selectedDays.first} $timeStr";
                                                                    // Add extra alarms for additional selected days
                                                                    for (int i = 1; i < _selectedDays.length; i++) {
                                                                      String extra = "${_selectedDays[i]} $timeStr";
                                                                      if (!_activeAlarms.contains(extra)) {
                                                                        _activeAlarms.add(extra);
                                                                      }
                                                                    }
                                                                  }
                                                                } else {
                                                                  // Creating new alarms
                                                                  if (_selectedDays.length == 7) {
                                                                    if (!_activeAlarms.contains(timeStr)) {
                                                                      _activeAlarms.add(timeStr);
                                                                    }
                                                                  } else {
                                                                    for (final day in _selectedDays) {
                                                                      String newAlarm = "$day $timeStr";
                                                                      if (!_activeAlarms.contains(newAlarm)) {
                                                                        _activeAlarms.add(newAlarm);
                                                                      }
                                                                    }
                                                                  }
                                                                }

                                                                _isAlarmMode = false;
                                                                _selectedAlarmIndex = null;
                                                                _selectedDays = [];
                                                              });
                                                              _saveAlarms();
                                                            },
                                                            onDeleteAlarm: (index) {
                                                              setState(() {
                                                                _activeAlarms.removeAt(index);
                                                                if (_selectedAlarmIndex == index) {
                                                                  _selectedAlarmIndex = null;
                                                                } else if (_selectedAlarmIndex != null && _selectedAlarmIndex! > index) {
                                                                  _selectedAlarmIndex = _selectedAlarmIndex! - 1;
                                                                }
                                                              });
                                                              _saveAlarms();
                                                            },
                                                            onDaysChanged: (days) => setState(() => _selectedDays = days),
                                                            onAmPmChanged: (val) => _scrolledAmPm = val,
                                                            onHourChanged: (val) => _scrolledHour = val,
                                                            onMinuteChanged: (val) => _scrolledMinute = val,

                                                            // --- Stopwatch Callbacks (unchanged) ---
                                                            onStopwatchTapped: () => setState(() {
                                                              _isStopwatchMode = true;
                                                              _isAlarmMode = false;
                                                              _isTimerMode = false;
                                                              _selectedAlarmIndex = null;
                                                            }),
                                                            onStopwatchToggle: _toggleStopwatch,
                                                            onStopwatchLap: _lapStopwatch,
                                                            onStopwatchReset: () {
                                                              setState(() {
                                                                _stopwatch.stop();
                                                                _stopwatch.reset();
                                                                _stopwatchTimer?.cancel();
                                                                _stopwatchTime = "00:00.00";
                                                                _stopwatchLaps.clear();
                                                              });
                                                            },

                                                            // --- Timer Callbacks ---
                                                            onTimerTapped: () => setState(() {
                                                              _isTimerMode = true;
                                                              _isStopwatchMode = false;
                                                              _isAlarmMode = false;
                                                              _isCreatingTimer = false;
                                                              _isEditingTimer = false;
                                                              _selectedAlarmIndex = null;
                                                              if (_appTimers.isNotEmpty && _selectedTimerIndex == null) {
                                                                _selectedTimerIndex = 0;
                                                              }
                                                            }),
                                                            onTimerRowTapped: (index) {
                                                              setState(() {
                                                                _selectedTimerIndex = _selectedTimerIndex == index ? null : index;
                                                              });
                                                            },
                                                            onToggleTimer: (index) => _toggleTimer(index),
                                                            onTimerReset: _stopTimer,
                                                            onAddNewTimerTapped: () => setState(() {
                                                              _isCreatingTimer = true;
                                                              _isEditingTimer = false;
                                                              _scrolledTimerHour = 0;
                                                              _scrolledTimerMinute = 5;
                                                              _scrolledTimerSecond = 0;
                                                            }),
                                                            onCancelTimerTapped: () => setState(() {
                                                              _isCreatingTimer = false;
                                                              _isEditingTimer = false;
                                                              if (_appTimers.isEmpty) {
                                                                _isTimerMode = false;
                                                                _showPill = false;
                                                              }
                                                            }),
                                                            onSaveTimerTapped: () {
                                                              setState(() {
                                                                int totalSecs = _scrolledTimerHour * 3600 + _scrolledTimerMinute * 60 + _scrolledTimerSecond;
                                                                if (totalSecs > 0) {
                                                                  if (_isEditingTimer && _selectedTimerIndex != null) {
                                                                    var t = _appTimers[_selectedTimerIndex!];
                                                                    t.totalSeconds = totalSecs;
                                                                    t.remainingSeconds = totalSecs;
                                                                    t.isRunning = true;
                                                                    t.endTime = DateTime.now().add(Duration(seconds: totalSecs));
                                                                  } else {
                                                                    var newT = AppTimer(totalSeconds: totalSecs);
                                                                    newT.isRunning = true;
                                                                    newT.endTime = DateTime.now().add(Duration(seconds: totalSecs));
                                                                    _appTimers.add(newT);
                                                                    _selectedTimerIndex = _appTimers.length - 1;
                                                                  }
                                                                  _isCreatingTimer = false;
                                                                  _isEditingTimer = false;
                                                                  if (_countdownTimer == null || !_countdownTimer!.isActive) {
                                                                    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
                                                                  }
                                                                } else {
                                                                  _isCreatingTimer = false;
                                                                  _isEditingTimer = false;
                                                                }
                                                              });
                                                              _saveTimers();
                                                            },
                                                            onDeleteTimer: (index) {
                                                              setState(() {
                                                                _appTimers.removeAt(index);
                                                                if (_selectedTimerIndex == index) {
                                                                  _selectedTimerIndex = _appTimers.isNotEmpty ? 0 : null;
                                                                  if (_appTimers.isEmpty) {
                                                                    _isCreatingTimer = false;
                                                                  }
                                                                } else if (_selectedTimerIndex != null && _selectedTimerIndex! > index) {
                                                                  _selectedTimerIndex = _selectedTimerIndex! - 1;
                                                                }
                                                              });
                                                              _saveTimers();
                                                            },
                                                            onLongPressTimer: (index) {
                                                              setState(() {
                                                                _selectedTimerIndex = index;
                                                                var t = _appTimers[index];
                                                                _scrolledTimerHour = t.totalSeconds ~/ 3600;
                                                                _scrolledTimerMinute = (t.totalSeconds % 3600) ~/ 60;
                                                                _scrolledTimerSecond = t.totalSeconds % 60;
                                                                _isCreatingTimer = true;
                                                                _isEditingTimer = true;
                                                              });
                                                            },
                                                            onTimerHourChanged: (val) => _scrolledTimerHour = val,
                                                            onTimerMinuteChanged: (val) => _scrolledTimerMinute = val,
                                                            onTimerSecondChanged: (val) => _scrolledTimerSecond = val,

                                                            // --- Ringing Callbacks (unchanged) ---
                                                            onSnoozeRinging: _snoozeAlarm,
                                                            onCancelRinging: _stopAlarm,
                                                          ),
                                                    )
                                                  : null,
                                            ),
                                          ],
                                        ),
                                      ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            AppDrawer(
                              apps: _apps,
                              progressNotifier: _drawerProgress,
                              controller: _drawerController,
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
            ),
          ),
        ],
      ),
      ),
    );
  }

  // --- Nearest active alarm (returns time string like "Mon 8:30 AM", or null) ---
  String? _nearestAlarmLabel() {
    if (_activeAlarms.isEmpty) return null;
    final now = DateTime.now();
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    Duration? bestDiff;
    String? bestLabel;

    for (final alarm in _activeAlarms) {
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

  // --- Nearest active timer (returns index, or null) ---
  int? _nearestTimerIndex() {
    if (_appTimers.isEmpty) return null;
    int? bestIdx;
    int bestRemaining = 999999999;
    for (int i = 0; i < _appTimers.length; i++) {
      final t = _appTimers[i];
      if (t.isRunning && t.remainingSeconds < bestRemaining) {
        bestRemaining = t.remainingSeconds;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  // Fixed width for alarm & timer status pills so they always match
  static const double _statusPillWidth = 105.0;

  Widget _buildPillRow() {
    // Build small status pills: Alarm (left) | Weather (center) | Timer (right)
    final nearestAlarm = _nearestAlarmLabel();
    final nearestTimer = _nearestTimerIndex();
    final bool hasAlarm = nearestAlarm != null;
    final bool hasTimer = nearestTimer != null;

    // Hide status pills during alarm ringing or expanded weather (but keep them
    // visible when panels like timer/alarm/calendar are open)
    final bool showStatusPills = !_isAlarmRinging && !_isForecastVisible;

    // GlobalKey preserves WeatherPill state (including _isExpanded) across layout changes
    final weatherPill = WeatherPill(
      key: _weatherPillKey,
      onExpandedChanged: (expanded) {
        setState(() => _isForecastVisible = expanded);
      },
    );

    final bool showAlarm = showStatusPills && hasAlarm;
    final bool showTimer = showStatusPills && hasTimer;

    // Centered row: visible pills group together and center as a unit.
    // AnimatedSize collapses hidden pills to zero width; AnimatedOpacity fades them.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _isForecastVisible ? 40 : 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Alarm pill — collapses to zero width when hidden
          AnimatedSize(
            duration: CASIMotion.standard,
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerRight,
            child: showAlarm
                ? AnimatedOpacity(
                    opacity: 1.0,
                    duration: CASIMotion.standard,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: _statusPillWidth,
                          child: _buildStatusPill(
                            icon: Icons.alarm,
                            label: nearestAlarm,
                            onTap: () {
                              setState(() {
                                _showPill = true;
                                _isAlarmMode = true;
                                _isStopwatchMode = false;
                                _isTimerMode = false;
                                _isCalendarMode = false;
                                _isViewingEvents = false;
                                _selectedAlarmIndex = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Weather pill — Expanded only when forecast is open (needs bounded width
          // for its double.infinity Container); unwrapped when collapsed so pills
          // group tightly and center as a unit.
          if (_isForecastVisible) Expanded(child: weatherPill)
          else weatherPill,
          // Timer pill — collapses to zero width when hidden
          AnimatedSize(
            duration: CASIMotion.standard,
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: showTimer
                ? AnimatedOpacity(
                    opacity: 1.0,
                    duration: CASIMotion.standard,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 4),
                        SizedBox(
                          width: _statusPillWidth,
                          child: _buildStatusPill(
                            icon: Icons.timer,
                            label: _formatTimerTime(_appTimers[nearestTimer].remainingSeconds),
                            textAlignment: Alignment.centerRight,
                            onTap: () {
                              setState(() {
                                _showPill = true;
                                _isTimerMode = true;
                                _isStopwatchMode = false;
                                _isAlarmMode = false;
                                _isCalendarMode = false;
                                _isViewingEvents = false;
                                _isCreatingTimer = false;
                                _isEditingTimer = false;
                                _selectedTimerIndex = nearestTimer;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Alignment textAlignment = Alignment.centerLeft,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassSurface.pill(
        cornerRadius: CASIGlass.cornerPill,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: CASIColors.textPrimary, size: 13),
            const SizedBox(width: 4),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: textAlignment,
                child: Text(
                  label,
                  style: const TextStyle(color: CASIColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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