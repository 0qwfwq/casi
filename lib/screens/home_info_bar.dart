import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_page.dart';
import '../widgets/glass_header.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_dock.dart';
import '../widgets/song_player.dart'; // <--- Brought in the standalone SongPlayer!

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /// Static cache to survive Flutter Activity recreation when OS memory is low.
  /// This ensures returning home is instant, like a native launcher.
  static List<AppInfo>? _cachedFullApps;

  /// Stores the list of installed applications fetched from the device.
  List<AppInfo> _apps = [];
  /// Stores the apps pinned to the home screen, mapped by their grid index.
  final Map<int, AppInfo> _homeApps = {};
  
  /// Tracks whether the app data is currently being loaded.
  bool _isLoading = true;
  /// Tracks if the user is currently dragging an icon.
  bool _isDragging = false;

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
    
    // If the Dart engine is still alive, pull instantly from cache
    if (_cachedFullApps != null) {
      _apps = _cachedFullApps!;
      _isLoading = false;
      _loadSavedLayout(_apps).then((_) {
        if (mounted) setState(() {});
        // Silently check for newly installed/uninstalled apps in the background
        _checkAppChangesOnResume();
      });
    } else {
      _initApps();
    }
    
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Instead of doing a heavy fetch, just check if packages changed
      _checkAppChangesOnResume();
    }
  }

  /// Asynchronously retrieves the list of installed apps on cold start.
  Future<void> _initApps() async {
    // 1. Fast load (no icons) to show UI immediately on cold start
    final fastApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: false);
    fastApps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _loadSavedLayout(fastApps);
    if (mounted) {
      setState(() {
        _apps = fastApps;
        _isLoading = false;
      });
    }

    // 2. Full load (with icons) to update UI with graphics
    final fullApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);
    fullApps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _loadSavedLayout(fullApps);

    // Cache the heavy data globally for the lifecycle of the process
    _cachedFullApps = fullApps;

    if (mounted) {
      setState(() {
        _apps = fullApps;
      });
    }
  }

  /// Performs a lightning-fast check on resume to see if the user installed/uninstalled apps.
  Future<void> _checkAppChangesOnResume() async {
    if (_cachedFullApps == null) return; // Don't interrupt a cold start load

    try {
      // Fast check to see what packages are currently installed
      final currentFastApps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: false);
      
      final currentPackages = currentFastApps.map((e) => e.packageName).toSet();
      final loadedPackages = _apps.map((e) => e.packageName).toSet();

      // If the packages are exactly the same, do nothing! This keeps the launcher buttery smooth.
      if (currentPackages.length == loadedPackages.length && currentPackages.containsAll(loadedPackages)) {
        return;
      }

      // If there's a difference (app installed or uninstalled), load the full data again silently.
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

  /// Loads the home screen layout from SharedPreferences.
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
        } catch (_) {
          // App not found (uninstalled), skip it.
        }
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

  /// Adds an app to the first available slot on the home screen.
  void _addToHomeScreen(AppInfo app) {
    if (_homeApps.values.any((element) => element.packageName == app.packageName)) {
      return;
    }

    // Find the first empty slot
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

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    // Calculate header height (28% for clock + ~60px for status row + padding)
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
              // Swipe up from bottom to open drawer
              if (_dragStartY < screenHeight - 60 && details.primaryVelocity! < -500) {
                _drawerController.animateTo(
                  0.9,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
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
                                // SongPlayer and ScreenDock stacked vertically above the bottom edge
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SongPlayer(),
                                      const SizedBox(height: 16),
                                      ScreenDock(
                                        isDragging: _isDragging,
                                        onRemove: (app) {
                                          setState(() {
                                            _homeApps.removeWhere((key, value) => value.packageName == app.packageName);
                                          });
                                          _saveLayout();
                                        },
                                        onUninstall: (app) {
                                          setState(() {
                                            _homeApps.removeWhere((key, value) => value.packageName == app.packageName);
                                          });
                                          _saveLayout();
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
    return GridView.builder(
      // Padding adjusted to 220 to accommodate the independent SongPlayer + ScreenDock layout
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 220), 
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
      // Remove from old position if it exists
      final int? oldIndex = _homeApps.keys.cast<int?>().firstWhere(
            (k) => _homeApps[k]?.packageName == data.packageName,
            orElse: () => null,
          );
      if (oldIndex != null) {
        _homeApps.remove(oldIndex);
      }
      // Place in new position
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          child: Image.memory(
            app.icon ?? Uint8List(0),
            width: 48,
            height: 48,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => 
              const Icon(Icons.android, color: Colors.white, size: 48),
          ),
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