import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:volume_controller/volume_controller.dart';
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
import '../morning_brief/health_brief_service.dart';
import '../notification_history/notification_history_screen.dart';

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
  bool _isPlayerVisible = false;

  // --- Pill & Alarm State ---
  bool _showPill = false;
  bool _isAlarmMode = false;

  // --- Advanced Alarm States ---
  List<String> _activeAlarms = [];
  bool _isAlarmRinging = false;
  int? _selectedAlarmIndex;
  Timer? _alarmTimer;
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
  WeatherBriefData? _weatherBriefData;
  CalendarBriefData? _calendarBriefData;
  HealthBriefData? _healthBriefData;
  bool _isForecastVisible = false;
  final GlobalKey _weatherPillKey = GlobalKey();

  // --- Settings ---
  String _bgType = 'color';
  Color _bgColor = Colors.black;
  String? _bgImagePath;
  bool _immersiveMode = false;

  int _lastCheckedDay = DateTime.now().day;

  // --- Layout Constants ---
  static const int _maxHomeApps = 7;

  // --- Drawer Control ---
  final ValueNotifier<double> _drawerProgress = ValueNotifier(0.0);
  final DraggableScrollableController _drawerController = DraggableScrollableController();
  double _dragStartY = 0.0;

  // --- Notification History Slide ---
  late final AnimationController _notifSlideController;
  bool _isNotifHistoryOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _notifSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 80),
    );

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
    _refreshWeatherBrief();
    _refreshCalendarBrief();
    _refreshHealthBrief();

    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkAlarms();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmTimer?.cancel();
    _stopwatchTimer?.cancel();
    _countdownTimer?.cancel();
    _stopAlarmSound();
    _audioPlayer.dispose();
    _notifSlideController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersiveMode();
      _checkAppChangesOnResume();
      _syncTimersOnResume();
      _refreshWeatherBrief();
      _refreshCalendarBrief();
      _refreshHealthBrief();
      // Instantly close the drawer when returning to the launcher
      if (_drawerController.isAttached && _drawerController.size > 0.0) {
        _drawerController.jumpTo(0.0);
      }
    } else if (state == AppLifecycleState.paused) {
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
        _refreshHealthBrief();
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
      _bgType = prefs.getString('bg_type') ?? 'color';
      final int colorValue = prefs.getInt('bg_color') ?? 0xFF000000;
      _bgColor = Color(colorValue);
      _bgImagePath = prefs.getString('bg_image_path');
      _immersiveMode = prefs.getBool('immersive_mode') ?? false;
    });
    _applyImmersiveMode();
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
    setState(() {
      _morningBriefDismissDay = dismissDay;
      _showMorningBrief = !dismissed;
    });
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

  Future<void> _showMorningBriefAgain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('morning_brief_dismiss_day');
    setState(() {
      _morningBriefDismissDay = -1;
      _showMorningBrief = true;
    });
    _refreshWeatherBrief();
    _refreshCalendarBrief();
    _refreshHealthBrief();
  }

  Future<void> _refreshWeatherBrief() async {
    final data = await WeatherBriefService.generateBrief();
    if (mounted && data != null) {
      setState(() {
        _weatherBriefData = data;
      });
    }
  }

  void _openNotificationHistory() {
    setState(() => _isNotifHistoryOpen = true);
    _notifSlideController.forward();
  }

  void _closeNotificationHistory() {
    _notifSlideController.reverse().then((_) {
      if (mounted) setState(() => _isNotifHistoryOpen = false);
    });
  }

  Future<void> _refreshCalendarBrief() async {
    final data = await CalendarBriefService.getTodayEvents();
    if (mounted) {
      setState(() {
        _calendarBriefData = data;
      });
    }
  }

  Future<void> _refreshHealthBrief() async {
    final data = await HealthBriefService.getTodayData();
    if (mounted) {
      setState(() {
        _healthBriefData = data;
      });
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
  void _showAddEventDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: CASISpacing.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CASIGlass.cornerSheet),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: CASIGlass.blurHeavy, sigmaY: CASIGlass.blurHeavy),
              child: Container(
                padding: const EdgeInsets.all(CASISpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                  borderRadius: BorderRadius.circular(CASIGlass.cornerSheet),
                  border: Border.all(color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha), width: 1.0),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)
                  ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'New Event',
                      style: TextStyle(color: CASIColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)
                    ),
                    const SizedBox(height: CASISpacing.lg),
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: CASIColors.textPrimary, fontSize: 16),
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Event Title',
                        hintStyle: const TextStyle(color: CASIColors.textTertiary),
                        filled: true,
                        fillColor: CASIColors.bgPrimary.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      style: const TextStyle(color: CASIColors.textPrimary, fontSize: 16),
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Description (Optional)',
                        hintStyle: const TextStyle(color: CASIColors.textTertiary),
                        filled: true,
                        fillColor: CASIColors.bgPrimary.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            child: const Text('Cancel', style: TextStyle(color: CASIColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (titleController.text.trim().isNotEmpty) {
                                setState(() {
                                  final date = DateTime(_calendarFocusedDay.year, _calendarFocusedDay.month, _calendarFocusedDay.day);
                                  final eventsList = _calendarEvents[date] ?? [];
                                  eventsList.add(CalendarEvent(
                                    title: titleController.text.trim(),
                                    description: descController.text.trim(),
                                  ));
                                  _calendarEvents[date] = eventsList;
                                });
                                _saveCalendarEvents();
                                Navigator.pop(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CASIColors.accentPrimary.withValues(alpha: 0.8),
                              foregroundColor: CASIColors.textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              elevation: 0,
                            ),
                            child: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
      backgroundColor: CASIColors.bgPrimary,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildBackground(),
          // Main content — slides right when notification history opens
          SlideTransition(
            position: Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(1.0, 0.0),
            ).animate(CurvedAnimation(
              parent: _notifSlideController,
              curve: Curves.easeOutCubic,
            )),
            child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              if (_drawerProgress.value > 0.05 || _showPill || _isAlarmRinging ||
                  _isForecastVisible || _isNotifHistoryOpen) {
                return;
              }
              const MethodChannel('casi.launcher/apps').invokeMethod('lockScreen');
            },
            onLongPressStart: (details) {
              _showHomescreenContextMenu(details.globalPosition);
            },
            onVerticalDragStart: (details) {
              _dragStartY = details.globalPosition.dy;
            },
            onVerticalDragEnd: (details) {
              final double screenHeight = MediaQuery.of(context).size.height;
              if (_dragStartY < screenHeight - 60 && details.primaryVelocity! < -500) {
                _drawerController.animateTo(
                  0.75,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                _openNotificationHistory();
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
                                          AnimatedCrossFade(
                                            duration: const Duration(milliseconds: 120),
                                            sizeCurve: Curves.easeOutCubic,
                                            firstCurve: Curves.easeOutCubic,
                                            secondCurve: Curves.easeInCubic,
                                            crossFadeState: (_showMorningBrief && !_showPill && !_isAlarmRinging)
                                                ? CrossFadeState.showFirst
                                                : CrossFadeState.showSecond,
                                            firstChild: Padding(
                                              padding: const EdgeInsets.only(top: 12),
                                              child: MorningBriefPanel(
                                                weatherData: _weatherBriefData,
                                                calendarData: _calendarBriefData,
                                                healthData: _healthBriefData,
                                                launcherEvents: _calendarEvents,
                                                onDismiss: _dismissMorningBrief,
                                                onRefreshHealth: _refreshHealthBrief,
                                              ),
                                            ),
                                            secondChild: const SizedBox(width: double.infinity),
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
                                            ScreenDock(
                                              isDragging: _isDragging,
                                              showApps: !_showPill && !_isAlarmRinging,
                                              onRemove: (app) {
                                                setState(() {
                                                  _homeApps.removeWhere((key, value) => value.packageName == app.packageName);
                                                });
                                                _saveLayout();
                                              },
                                              onUninstall: (app) {
                                                try {
                                                  InstalledApps.uninstallApp(app.packageName);
                                                } catch (e) {
                                                  debugPrint("Uninstall error: $e");
                                                }
                                              },
                                              homeApps: _homeApps,
                                              maxHomeApps: _maxHomeApps,
                                              onAppDropped: (index, app) => _onAppDropped(index, app),
                                              onAppTap: (app) => AppLauncher.launchApp(app.packageName),
                                              onDragStarted: () => setState(() => _isDragging = true),
                                              onDragEnded: () => setState(() => _isDragging = false),
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
                                                            onAddEvent: _showAddEventDialog,
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
                                  ],
                                );
                              },
                            ),
                            AppDrawer(
                              apps: _apps,
                              progressNotifier: _drawerProgress,
                              controller: _drawerController,
                              onAppTap: (app) => AppLauncher.launchApp(app.packageName),
                              onAddToHome: (app) => _addToHomeScreen(app),
                              onUninstall: (app) {
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
          ), // SlideTransition (main content)
          // Notification history — slides in from the left
          if (_isNotifHistoryOpen)
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1.0, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: _notifSlideController,
                curve: Curves.easeOutCubic,
              )),
              child: NotificationHistoryPanel(
                onDismiss: _closeNotificationHistory,
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

    // Hide status pills during active pill, alarm, or expanded weather
    final bool showStatusPills = !_showPill && !_isAlarmRinging && !_isForecastVisible;

    // GlobalKey preserves WeatherPill state (including _isExpanded) across layout changes
    final weatherPill = WeatherPill(
      key: _weatherPillKey,
      onExpandedChanged: (expanded) {
        setState(() => _isForecastVisible = expanded);
      },
    );

    final alarmPill = SizedBox(
      width: _statusPillWidth,
      child: _buildStatusPill(
        icon: Icons.alarm,
        label: nearestAlarm ?? '',
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
    );

    final timerPill = SizedBox(
      width: _statusPillWidth,
      child: _buildStatusPill(
        icon: Icons.timer,
        label: hasTimer ? _formatTimerTime(_appTimers[nearestTimer].remainingSeconds) : '',
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
    );

    final bool showAlarm = showStatusPills && hasAlarm;
    final bool showTimer = showStatusPills && hasTimer;

    if (showAlarm && showTimer) {
      // 3 pills: Expanded(alarm right-aligned) | Weather | Expanded(timer left-aligned)
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [alarmPill],
              ),
            ),
            const SizedBox(width: 4),
            weatherPill,
            const SizedBox(width: 4),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [timerPill],
              ),
            ),
          ],
        ),
      );
    } else if (showAlarm) {
      // 2 pills: center the alarm+weather pair together
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            alarmPill,
            const SizedBox(width: 4),
            weatherPill,
          ],
        ),
      );
    } else if (showTimer) {
      // 2 pills: center the weather+timer pair together
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            weatherPill,
            const SizedBox(width: 4),
            timerPill,
          ],
        ),
      );
    } else {
      // Weather only (or expanded forecast) — no Row so expanded width: double.infinity works
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: _isForecastVisible ? 40 : 20),
        child: weatherPill,
      );
    }
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(CASIGlass.cornerPill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: CASIGlass.blurStandard, sigmaY: CASIGlass.blurStandard),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
              borderRadius: BorderRadius.circular(CASIGlass.cornerPill),
              border: Border.all(color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha)),
            ),
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
        ),
      ),
    );
  }

  void _showHomescreenContextMenu(Offset position) {
    // Only show on bare wallpaper — not when drawer, pill, forecast, etc. are active
    if (_showMorningBrief || _showPill || _isAlarmRinging ||
        _isForecastVisible || _isNotifHistoryOpen ||
        _drawerProgress.value > 0.05) {
      return;
    }

    final screenSize = MediaQuery.of(context).size;
    double left = (position.dx - 100).clamp(16.0, screenSize.width - 216.0);
    double top = (position.dy - 40).clamp(16.0, screenSize.height - 100.0);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: CASIGlass.blurHeavy, sigmaY: CASIGlass.blurHeavy),
                    child: Container(
                      width: 200,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: CASIElevation.float_.bgAlpha),
                        borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: CASIElevation.float_.borderAlpha),
                          width: 1.0,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showMorningBriefAgain();
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Icon(Icons.wb_sunny_outlined, color: CASIColors.textPrimary, size: 20),
                              SizedBox(width: 12),
                              Text('Show Brief', style: TextStyle(color: CASIColors.textPrimary, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: _bgType == 'image' && _bgImagePath != null
          ? Image.file(
              File(_bgImagePath!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: CASIColors.bgPrimary),
            )
          : Container(color: _bgColor),
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
    });
    _saveLayout();
  }

}