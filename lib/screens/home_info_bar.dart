import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart'; // --- NEW: Audio package ---
import 'settings_page.dart';
import '../widgets/glass_header.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_dock.dart';
import '../widgets/song_player.dart';
import '../widgets/clock_capsule.dart'; 
import '../pills/dynamic_pill.dart';
import '../pills/d_clock_pill.dart';

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

  // --- NEW: Advanced Alarm States ---
  List<String> _activeAlarms = []; 
  bool _isViewingAlarms = false; 
  bool _isAlarmRinging = false; 
  Timer? _alarmTimer;
  String? _lastRungAlarmTime; // Prevents infinite ringing within the same minute

  // --- NEW: Audio States ---
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _soundTimer;

  // --- NEW: Time Scroller States ---
  int _scrolledHour = 1; // Default to match the visual wheel state
  int _scrolledMinute = 0;
  String _scrolledAmPm = 'AM';

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

    // --- NEW: Start background alarm checker ---
    _alarmTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkAlarms();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmTimer?.cancel();
    _stopAlarmSound(); // Ensure sound stops if widget is disposed
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAppChangesOnResume();
    }
  }

  // --- NEW: Alarm Audio Logic ---
  Future<void> _playSound() async {
    try {
      // audioplayers automatically prefixes with 'assets/', so this maps to 'assets/sounds/alarm_sound.wav'
      await _audioPlayer.play(AssetSource('sounds/alarm_sound.wav'));
    } catch (e) {
      debugPrint("Error playing alarm sound: $e");
    }
  }

  void _startAlarmSound() {
    _playSound(); // Play immediately
    _soundTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAlarmRinging) {
        _playSound(); // Loop every 5 seconds
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

  // --- NEW: Alarm Background Logic ---
  void _checkAlarms() {
    if (_isAlarmRinging) return; // Don't trigger if already ringing
    
    final now = DateTime.now();
    // Format current time to match our simple "hh:mm AM" mock format
    int hour = now.hour;
    int minute = now.minute;
    String ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minuteStr = minute.toString().padLeft(2, '0');
    String currentTimeStr = "$hour:$minuteStr $ampm";

    // Check if the time matches AND we haven't already rung for this exact minute
    if (_activeAlarms.contains(currentTimeStr) && _lastRungAlarmTime != currentTimeStr) {
      setState(() {
        _isAlarmRinging = true;
        _showPill = true;
        _isAlarmMode = false; // Close creation mode if it was open
        _isViewingAlarms = false;
        _lastRungAlarmTime = currentTimeStr; // Mark as rung
      });
      _startAlarmSound(); // Trigger the repeating sound
    }
  }

  void _snoozeAlarm() {
    _stopAlarmSound(); // Stop the audio immediately

    // Generate a temporary alarm 5 minutes from now!
    final now = DateTime.now().add(const Duration(minutes: 5));
    int hour = now.hour;
    int minute = now.minute;
    String ampm = hour >= 12 ? "PM" : "AM";
    hour = hour % 12;
    if (hour == 0) hour = 12;
    String minuteStr = minute.toString().padLeft(2, '0');
    String snoozeTime = "$hour:$minuteStr $ampm";

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
    _stopAlarmSound(); // Stop the audio immediately
    setState(() {
      _isAlarmRinging = false;
      _showPill = false;
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
    });
  }

  // --- NEW: View Alarms & Checkmark Action Row ---
  Widget _buildAlarmTopActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // View Active Alarms Button
        GestureDetector(
          onTap: () {
            setState(() {
              _isViewingAlarms = !_isViewingAlarms;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isViewingAlarms ? Colors.white : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
              ],
            ),
            child: Icon(
              Icons.format_list_bulleted, 
              color: _isViewingAlarms ? Colors.black : Colors.white, 
              size: 24
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Confirm/Save Alarm Button
        GestureDetector(
          onTap: () {
            setState(() {
              // Now dynamically reads the real values from the Hub state!
              String minStr = _scrolledMinute.toString().padLeft(2, '0');
              String newAlarm = "$_scrolledHour:$minStr $_scrolledAmPm";
              
              if (!_activeAlarms.contains(newAlarm)) {
                _activeAlarms.add(newAlarm);
              }
              _isAlarmMode = false;
              _isViewingAlarms = false;
              _showPill = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Alarm Set!'), 
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.greenAccent.shade400,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
              ],
            ),
            child: const Icon(Icons.check, color: Colors.black, size: 24),
          ),
        ),
      ],
    );
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
                    _isAlarmMode = false; // Fresh start when opening
                    _isViewingAlarms = false;
                    // Reset scroll tracker to match the visual default state of the wheels!
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
                                        if (_isAlarmMode || _isViewingAlarms || _isAlarmRinging) {
                                          setState(() {
                                            _isAlarmMode = false;
                                            _isViewingAlarms = false;
                                            // Don't kill ringing alarm if tapped outside, user must hit cancel/snooze
                                          });
                                        } else if (_showPill) {
                                          _dismissPill();
                                        }
                                      },
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Offstage(
                                            offstage: !_isPlayerVisible,
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
                                          
                                          // --- INJECTED: Safely positioned above the Dock bounds so it is clickable! ---
                                          AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 300),
                                            child: _isAlarmMode 
                                                ? Padding(
                                                    key: const ValueKey('alarm_actions'),
                                                    padding: const EdgeInsets.only(bottom: 16),
                                                    child: _buildAlarmTopActionButtons(),
                                                  )
                                                : const SizedBox.shrink(key: ValueKey('empty_actions')),
                                          ),

                                          ScreenDock(
                                            isDragging: _isDragging,
                                            isAlarmMode: _isAlarmMode, 
                                            isAlarmRinging: _isAlarmRinging, // Passes ringing state
                                            onSnooze: _snoozeAlarm,          // Pass snooze action
                                            onCancel: _stopAlarm,            // Pass cancel action
                                            onAmPmChanged: (val) => _scrolledAmPm = val, // Track Dock Am/Pm
                                            activePill: _showPill
                                                ? DynamicPill(
                                                    key: const ValueKey('main_dynamic_pill'),
                                                    onDismissed: _dismissPill,
                                                    // Removed topWidget here to prevent the clipping issue!
                                                    child: DClockPill(
                                                      isAlarmMode: _isAlarmMode,
                                                      isViewingAlarms: _isViewingAlarms,
                                                      isAlarmRinging: _isAlarmRinging,
                                                      activeAlarms: _activeAlarms,
                                                      onAlarmTapped: () => setState(() {
                                                        _isAlarmMode = true;
                                                        _isViewingAlarms = false;
                                                      }),
                                                      onDeleteAlarm: (index) => setState(() {
                                                        _activeAlarms.removeAt(index);
                                                      }),
                                                      onHourChanged: (val) => _scrolledHour = val,
                                                      onMinuteChanged: (val) => _scrolledMinute = val,
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