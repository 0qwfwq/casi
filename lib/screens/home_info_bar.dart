import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart'; 
import 'settings_page.dart';
import '../widgets/glass_header.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_dock.dart';
import '../widgets/song_player.dart';
import '../widgets/clock_capsule.dart'; 
import '../pills/dynamic_pill.dart';
import '../pills/d_clock_pill.dart';

// --- NEW: AppTimer Class for Multi-Timer Support ---
class AppTimer {
  int totalSeconds;
  int remainingSeconds;
  bool isRunning;
  DateTime? endTime;

  AppTimer({required this.totalSeconds}) 
    : remainingSeconds = totalSeconds, 
      isRunning = false;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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
  bool _isViewingAlarms = false; 
  bool _isAlarmRinging = false; 
  int? _selectedAlarmIndex; 
  Timer? _alarmTimer;
  String? _lastRungAlarmTime; 

  // --- Audio States ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _soundTimer;

  // --- Time Scroller States ---
  int _scrolledHour = 1; 
  int _scrolledMinute = 0;
  String _scrolledAmPm = 'AM';
  String _scrolledDay = 'Mon'; 

  // --- Stopwatch States ---
  bool _isStopwatchMode = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _stopwatchTimer;
  String _stopwatchTime = "00:00.00";
  List<String> _stopwatchLaps = [];

  // --- Advanced Timer States ---
  bool _isTimerMode = false;
  bool _isViewingTimers = false;
  bool _isCreatingTimer = false;
  
  List<AppTimer> _appTimers = []; 
  int? _selectedTimerIndex;
  Timer? _countdownTimer;

  int _scrolledTimerHour = 0;
  int _scrolledTimerMinute = 5;
  int _scrolledTimerSecond = 0;

  // --- Settings ---
  String _bgType = 'color';
  Color _bgColor = Colors.black;
  String? _bgImagePath;
  bool _showAppNames = true;

  // --- Layout Constants ---
  final int _gridColumns = 4;
  final int _gridRows = 6;

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

    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    _scrolledDay = days[DateTime.now().weekday - 1];

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAppChangesOnResume();
      _syncTimersOnResume(); // Catches up math for timers ticking in the background
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
    _playSound(); 
    _soundTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAlarmRinging) {
        _playSound(); 
      } else {
        _stopAlarmSound();
      }
    });
  }

  void _stopAlarmSound() {
    _soundTimer?.cancel();
    _soundTimer = null;
    _audioPlayer.stop();
  }

  // --- Alarm Background Logic ---
  void _checkAlarms() {
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

    if (_activeAlarms.contains(currentTimeStr) && _lastRungAlarmTime != currentTimeStr) {
      setState(() {
        _isAlarmRinging = true;
        _showPill = true;
        _isAlarmMode = false; 
        _isViewingAlarms = false;
        _isStopwatchMode = false; 
        _isTimerMode = false;
        _selectedAlarmIndex = null;
        _lastRungAlarmTime = currentTimeStr; 
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
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Snoozed for 5 minutes ($snoozeTime)')),
    );
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
          t.remainingSeconds = 0;
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
    }

    if (mounted) setState(() {});

    if (!anyRunning) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  void _syncTimersOnResume() {
    // Fast-forwards the math on all active timers in case the app went to sleep
    _tickTimers();
    if (_appTimers.any((t) => t.isRunning) && (_countdownTimer == null || !_countdownTimer!.isActive)) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
    }
  }

  void _toggleTimer() {
    if (_selectedTimerIndex == null || _appTimers.isEmpty) return;
    
    var t = _appTimers[_selectedTimerIndex!];
    setState(() {
      if (t.isRunning) {
        t.isRunning = false;
        t.endTime = null; // Pauses
      } else {
        if (t.remainingSeconds <= 0) t.remainingSeconds = t.totalSeconds;
        t.isRunning = true;
        t.endTime = DateTime.now().add(Duration(seconds: t.remainingSeconds));
        
        if (_countdownTimer == null || !_countdownTimer!.isActive) {
          _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
        }
      }
    });
  }

  void _stopTimer() {
    if (_selectedTimerIndex == null || _appTimers.isEmpty) return;
    
    setState(() {
      var t = _appTimers[_selectedTimerIndex!];
      t.isRunning = false;
      t.endTime = null;
      t.remainingSeconds = t.totalSeconds; // Fully Resets 
      _isViewingTimers = true; // Naturally falls back to list view
    });
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

      if (index >= 0 && index < _gridColumns * _gridRows) {
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
      final int colorValue = prefs.getInt('bg_color') ?? Colors.black.value;
      _bgColor = Color(colorValue);
      _bgImagePath = prefs.getString('bg_image_path');
      _showAppNames = prefs.getBool('show_app_names') ?? true;
    });
  }

  Future<void> _saveLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> layout = _homeApps.entries
        .map((e) => '${e.key}:${e.value.packageName}')
        .toList();
    await prefs.setStringList('home_layout', layout);
  }

  void _addToHomeScreen(AppInfo app) {
    if (_homeApps.values.any((element) => element.packageName == app.packageName)) {
      return;
    }

    for (int i = 0; i < _gridColumns * _gridRows; i++) {
      if (!_homeApps.containsKey(i)) {
        setState(() {
          _homeApps[i] = app;
        });
        _saveLayout();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${app.name} added to Home Screen'),
            duration: const Duration(seconds: 1),
          ),
        );
        return;
      }
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Home Screen is full!')),
    );
  }

  void _dismissPill() {
    setState(() {
      _showPill = false;
      _isAlarmMode = false;
      _isViewingAlarms = false;
      _selectedAlarmIndex = null; 

      // STOPWATCH CLEANUP
      _isStopwatchMode = false;
      _stopwatch.stop();
      _stopwatch.reset();
      _stopwatchTimer?.cancel();
      _stopwatchTime = "00:00.00";
      _stopwatchLaps.clear();

      // TIMER UI CLEANUP (But keeps running in background!)
      _isTimerMode = false;
      _isViewingTimers = false;
      _isCreatingTimer = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double headerHeight = (screenHeight * 0.28) + 80;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_drawerController.isAttached && _drawerController.size > 0.1) {
          _drawerController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildBackground(),
          GestureDetector(
            onVerticalDragStart: (details) {
              _dragStartY = details.globalPosition.dy;
            },
            onVerticalDragEnd: (details) {
              final double screenHeight = MediaQuery.of(context).size.height;
              if (_dragStartY < screenHeight - 60 && details.primaryVelocity! < -500) {
                _drawerController.animateTo(
                  0.9,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            },
            child: NotificationListener<ClockTapNotification>(
              onNotification: (notification) {
                if (_showPill) {
                  _dismissPill();
                } else {
                  setState(() {
                    _showPill = true;
                    _isAlarmMode = false; 
                    _isViewingAlarms = false;
                    _isStopwatchMode = false;
                    _isTimerMode = false;
                    _selectedAlarmIndex = null;
                    _scrolledHour = 1; 
                    _scrolledMinute = 0;
                    _scrolledAmPm = 'AM';
                    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                    _scrolledDay = days[DateTime.now().weekday - 1]; 
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
                              final double opacity = (1.0 - progress).clamp(0.0, 1.0);
                              return Stack(
                                children: [
                                  Opacity(
                                    opacity: opacity,
                                    child: RepaintBoundary(
                                      child: _buildHomeGrid(headerHeight),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: GlassStatusBar(
                                      opacity: 1.0,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: TapRegion(
                                      groupId: 'dock_region',
                                      onTapOutside: (event) {
                                        if (_isAlarmRinging) {
                                          return; 
                                        } else if (_isStopwatchMode || _isTimerMode) {
                                          _dismissPill();
                                        } else if (_isAlarmMode || _isViewingAlarms) {
                                          setState(() {
                                            _isAlarmMode = false;
                                            _isViewingAlarms = false;
                                            _selectedAlarmIndex = null;
                                          });
                                        } else if (_showPill) {
                                          _dismissPill();
                                        }
                                      },
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Offstage(
                                            offstage: !_isPlayerVisible || _isAlarmRinging, 
                                            child: Padding(
                                              padding: const EdgeInsets.only(bottom: 16),
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
                                          
                                          ScreenDock(
                                            isDragging: _isDragging,
                                            isAlarmMode: _isAlarmMode, 
                                            isAlarmRinging: _isAlarmRinging, 
                                            isViewingAlarms: _isViewingAlarms, 
                                            hasSelectedAlarm: _selectedAlarmIndex != null, 
                                            isStopwatchMode: _isStopwatchMode,
                                            isStopwatchRunning: _stopwatch.isRunning,
                                            isTimerMode: _isTimerMode,
                                            isTimerRunning: _selectedTimerIndex != null && _appTimers.isNotEmpty 
                                                ? _appTimers[_selectedTimerIndex!].isRunning 
                                                : false,
                                            isCreatingTimer: _isCreatingTimer,
                                            hasSelectedTimer: _selectedTimerIndex != null,
                                            initialAmPm: _scrolledAmPm, 
                                            initialDay: _scrolledDay, 
                                            onSnooze: _snoozeAlarm,          
                                            onCancel: _stopAlarm,            
                                            onEditAlarm: () {
                                              if (_selectedAlarmIndex != null) {
                                                final alarm = _activeAlarms[_selectedAlarmIndex!];
                                                final parts = alarm.split(' ');
                                                
                                                setState(() {
                                                  if (parts.length == 3) {
                                                    _scrolledDay = parts[0];
                                                    final timeParts = parts[1].split(':');
                                                    _scrolledHour = int.parse(timeParts[0]);
                                                    _scrolledMinute = int.parse(timeParts[1]);
                                                    _scrolledAmPm = parts[2];
                                                  } else {
                                                    _scrolledDay = 'Mon';
                                                    final timeParts = parts[0].split(':');
                                                    _scrolledHour = int.parse(timeParts[0]);
                                                    _scrolledMinute = int.parse(timeParts[1]);
                                                    _scrolledAmPm = parts[1];
                                                  }
                                                  
                                                  _activeAlarms.removeAt(_selectedAlarmIndex!);
                                                  _selectedAlarmIndex = null;
                                                  _isViewingAlarms = false;
                                                  _isAlarmMode = true; 
                                                });
                                              }
                                            },
                                            onDeleteAlarm: () {
                                              if (_selectedAlarmIndex != null) {
                                                setState(() {
                                                  _activeAlarms.removeAt(_selectedAlarmIndex!);
                                                  _selectedAlarmIndex = null;
                                                });
                                              }
                                            },
                                            onAmPmChanged: (val) => _scrolledAmPm = val, 
                                            onDayChanged: (val) => _scrolledDay = val,
                                            onStopwatchToggle: _toggleStopwatch,
                                            onStopwatchLap: _lapStopwatch,
                                            onTimerToggle: _toggleTimer,
                                            onTimerStop: _stopTimer,
                                            activePill: _showPill
                                                ? DynamicPill(
                                                    key: const ValueKey('main_dynamic_pill'),
                                                    child: DClockPill(
                                                      isAlarmMode: _isAlarmMode,
                                                      isViewingAlarms: _isViewingAlarms,
                                                      isAlarmRinging: _isAlarmRinging,
                                                      isStopwatchMode: _isStopwatchMode,
                                                      isTimerMode: _isTimerMode,
                                                      isViewingTimers: _isViewingTimers,
                                                      isCreatingTimer: _isCreatingTimer,
                                                      stopwatchTime: _stopwatchTime,
                                                      stopwatchLaps: _stopwatchLaps,
                                                      timerTime: _selectedTimerIndex != null && _appTimers.isNotEmpty 
                                                          ? _formatTimerTime(_appTimers[_selectedTimerIndex!].remainingSeconds) 
                                                          : "00:00",
                                                      savedTimersTimes: _appTimers.map((t) => _formatTimerTime(t.remainingSeconds)).toList(),
                                                      savedTimersRunning: _appTimers.map((t) => t.isRunning).toList(),
                                                      selectedTimerIndex: _selectedTimerIndex,
                                                      activeAlarms: _activeAlarms,
                                                      selectedIndex: _selectedAlarmIndex, 
                                                      initialHour: _scrolledHour, 
                                                      initialMinute: _scrolledMinute, 
                                                      initialTimerHour: _scrolledTimerHour,
                                                      initialTimerMinute: _scrolledTimerMinute,
                                                      initialTimerSecond: _scrolledTimerSecond,
                                                      
                                                      // --- New Integrated Actions ---
                                                      onViewAlarmsTapped: () => setState(() => _isViewingAlarms = true),
                                                      onAddNewAlarmTapped: () => setState(() {
                                                        _isViewingAlarms = false;
                                                        _selectedAlarmIndex = null;
                                                      }),
                                                      onSaveAlarmTapped: () {
                                                        setState(() {
                                                          String minStr = _scrolledMinute.toString().padLeft(2, '0');
                                                          String newAlarm = "$_scrolledDay $_scrolledHour:$minStr $_scrolledAmPm";
                                                          if (!_activeAlarms.contains(newAlarm)) {
                                                            _activeAlarms.add(newAlarm);
                                                          }
                                                          _isAlarmMode = false;
                                                          _isViewingAlarms = false;
                                                          _selectedAlarmIndex = null;
                                                          _showPill = false;
                                                        });
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
                                                      },
                                                      onViewTimersTapped: () => setState(() {
                                                        _isViewingTimers = true;
                                                        _isCreatingTimer = false;
                                                      }),
                                                      onAddNewTimerTapped: () => setState(() {
                                                        _isCreatingTimer = true;
                                                        _isViewingTimers = false;
                                                      }),
                                                      onCancelTimerTapped: () => setState(() {
                                                        if (_appTimers.isEmpty) {
                                                          _isTimerMode = false;
                                                          _showPill = false;
                                                        } else {
                                                          _isCreatingTimer = false;
                                                          _isViewingTimers = true;
                                                        }
                                                      }),
                                                      onSaveTimerTapped: () {
                                                        setState(() {
                                                          int totalSecs = _scrolledTimerHour * 3600 + _scrolledTimerMinute * 60 + _scrolledTimerSecond;
                                                          if (totalSecs > 0) {
                                                            var newT = AppTimer(totalSeconds: totalSecs);
                                                            newT.isRunning = true;
                                                            newT.endTime = DateTime.now().add(Duration(seconds: totalSecs));
                                                            
                                                            _appTimers.add(newT);
                                                            _selectedTimerIndex = _appTimers.length - 1;
                                                            
                                                            _isCreatingTimer = false;
                                                            _isViewingTimers = false;
                                                            
                                                            if (_countdownTimer == null || !_countdownTimer!.isActive) {
                                                              _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickTimers());
                                                            }
                                                          } else {
                                                            _isCreatingTimer = false;
                                                            _isViewingTimers = true;
                                                          }
                                                        });
                                                      },
                                                      onDeleteTimer: (index) {
                                                        setState(() {
                                                          _appTimers.removeAt(index);
                                                          if (_selectedTimerIndex == index) {
                                                            _selectedTimerIndex = _appTimers.isNotEmpty ? 0 : null;
                                                            if (_appTimers.isEmpty) {
                                                              _isViewingTimers = true;
                                                              _isCreatingTimer = false;
                                                            }
                                                          } else if (_selectedTimerIndex != null && _selectedTimerIndex! > index) {
                                                            _selectedTimerIndex = _selectedTimerIndex! - 1;
                                                          }
                                                        });
                                                      },

                                                      onSelectAlarm: (index) {
                                                        setState(() {
                                                          if (_selectedAlarmIndex == index) {
                                                            _selectedAlarmIndex = null;
                                                          } else {
                                                            _selectedAlarmIndex = index;
                                                          }
                                                        });
                                                      },
                                                      onSelectTimer: (index) {
                                                        setState(() {
                                                          _selectedTimerIndex = index;
                                                          _isViewingTimers = false; // Jump to big view immediately
                                                        });
                                                      },
                                                      onAlarmTapped: () => setState(() {
                                                        _isAlarmMode = true;
                                                        _isViewingAlarms = false;
                                                        _isStopwatchMode = false;
                                                        _isTimerMode = false;
                                                        _selectedAlarmIndex = null;
                                                        _scrolledHour = 1;
                                                        _scrolledMinute = 0;
                                                        _scrolledAmPm = 'AM';
                                                        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                                        _scrolledDay = days[DateTime.now().weekday - 1];
                                                      }),
                                                      onStopwatchTapped: () => setState(() {
                                                        _isStopwatchMode = true;
                                                        _isAlarmMode = false;
                                                        _isViewingAlarms = false;
                                                        _isTimerMode = false;
                                                        _selectedAlarmIndex = null;
                                                      }),
                                                      onTimerTapped: () => setState(() {
                                                        _isTimerMode = true;
                                                        _isStopwatchMode = false;
                                                        _isAlarmMode = false;
                                                        _isViewingAlarms = false;
                                                        _isViewingTimers = true; 
                                                        _isCreatingTimer = false;
                                                        _selectedAlarmIndex = null;
                                                        if (_appTimers.isNotEmpty && _selectedTimerIndex == null) {
                                                          _selectedTimerIndex = 0;
                                                        }
                                                      }),
                                                      onHourChanged: (val) => _scrolledHour = val,
                                                      onMinuteChanged: (val) => _scrolledMinute = val,
                                                      onTimerHourChanged: (val) => _scrolledTimerHour = val,
                                                      onTimerMinuteChanged: (val) => _scrolledTimerMinute = val,
                                                      onTimerSecondChanged: (val) => _scrolledTimerSecond = val,
                                                    ),
                                                  )
                                                : null,
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
                            onAppTap: (app) => InstalledApps.startApp(app.packageName),
                            onAppLongPress: (app) => _addToHomeScreen(app),
                            onOpenSettings: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()))
                                  .then((_) => _loadSettings());
                            },
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
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: _bgType == 'image' && _bgImagePath != null
          ? Image.file(
              File(_bgImagePath!),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
            )
          : Container(color: _bgColor),
    );
  }

  Widget _buildHomeGrid(double topPadding) {
    final double bottomPadding = _isPlayerVisible ? 220.0 : 130.0;
    
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, bottomPadding), 
      itemCount: _gridColumns * _gridRows,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns,
        crossAxisSpacing: 16,
        mainAxisSpacing: 24,
        childAspectRatio: 0.8,
      ),
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return DragTarget<AppInfo>(
          onAcceptWithDetails: (details) => _onAppDropped(index, details.data),
          builder: (context, candidateData, rejectedData) {
            return _buildGridItem(index, candidateData.isNotEmpty);
          },
        );
      },
    );
  }

  void _onAppDropped(int newIndex, AppInfo data) {
    setState(() {
      final int? oldIndex = _homeApps.keys.cast<int?>().firstWhere(
            (k) => _homeApps[k]?.packageName == data.packageName,
            orElse: () => null,
          );
      if (oldIndex != null) {
        _homeApps.remove(oldIndex);
      }
      _homeApps[newIndex] = data;
    });
    _saveLayout();
  }

  Widget _buildGridItem(int index, bool isCandidate) {
    final app = _homeApps[index];
    if (app == null) {
      return Container(
        decoration: BoxDecoration(
          border: isCandidate ? Border.all(color: Colors.white24) : null,
          borderRadius: BorderRadius.circular(12),
        ),
      );
    }
    return LongPressDraggable<AppInfo>(
      data: app,
      onDragStarted: () => setState(() => _isDragging = true),
      onDragEnd: (_) => setState(() => _isDragging = false),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 60,
          child: _buildAppIconVisual(app),
        ),
      ),
      childWhenDragging: Container(color: Colors.transparent),
      child: InkWell(
        onTap: () => InstalledApps.startApp(app.packageName),
        borderRadius: BorderRadius.circular(12),
        child: _buildAppIconVisual(app),
      ),
    );
  }

  Widget _buildAppIconVisual(AppInfo app) {
    final hasIcon = app.icon != null && app.icon!.isNotEmpty;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          child: hasIcon 
            ? Image.memory(
                app.icon!,
                width: 48,
                height: 48,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => 
                  const Icon(Icons.android, color: Colors.white, size: 48),
              )
            : const Icon(Icons.android, color: Colors.white, size: 48),
        ),
        if (_showAppNames) ...[
          const SizedBox(height: 8),
          Text(
            app.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}