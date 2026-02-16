import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_page.dart';
import 'glass_status_bar.dart';
import 'AppDrawer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Stores the list of installed applications fetched from the device.
  List<AppInfo> _apps = [];
  // Stores the apps pinned to the home screen, mapped by their grid index.
  final Map<int, AppInfo> _homeApps = {};
  // Tracks whether the app data is currently being loaded.
  bool _isLoading = true;
  // Tracks if the user is currently dragging an icon.
  bool _isDragging = false;

  // Background Settings
  String _bgType = 'color';
  Color _bgColor = Colors.black;
  String? _bgImagePath;
  bool _showAppNames = true;

  // Hardcoded grid dimensions
  final int _gridColumns = 4;
  final int _gridRows = 6;

  final ValueNotifier<double> _drawerProgress = ValueNotifier(0.0);
  final DraggableScrollableController _drawerController = DraggableScrollableController();
  double _dragStartY = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchApps();
    _loadSettings();
  }

  // Asynchronously retrieves the list of installed apps.
  Future<void> _fetchApps() async {
    // getInstalledApps({bool withIcon, bool excludeSystemApps, String packageNamePrefix})
    // We request icons to display them in the grid.
    List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);

    // Sort the apps alphabetically by their name for easier navigation.
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Load saved layout from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final List<String> savedLayout = prefs.getStringList('home_layout') ?? [];
    
    for (String item in savedLayout) {
      final parts = item.split(':');
      if (parts.length == 2) {
        final int index = int.tryParse(parts[0]) ?? -1;
        final String packageName = parts[1];
        
        if (index >= 0 && index < _gridColumns * _gridRows) {
          try {
            // Find the installed app that matches the saved package name
            final app = apps.firstWhere((a) => a.packageName == packageName);
            _homeApps[index] = app;
          } catch (e) {
            // App might have been uninstalled since last save; ignore it.
          }
        }
      }
    }

    // Check if the widget is still in the tree before calling setState to avoid errors.
    if (mounted) {
      setState(() {
        _apps = apps;
        _isLoading = false;
      });
    }
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
    // Save format: "index:packageName"
    final List<String> layout = _homeApps.entries
        .map((e) => '${e.key}:${e.value.packageName}')
        .toList();
    await prefs.setStringList('home_layout', layout);
  }

  // Adds an app to the home screen list if it isn't already there.
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

  // Removes an app from the home screen list.
  void _removeFromHomeScreen(int index) {
    setState(() {
      _homeApps.remove(index);
    });
    _saveLayout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.black, 
        body: Stack(
        children: [
          // Background Layer
          Positioned.fill(
            child: _bgType == 'image' && _bgImagePath != null
                ? Image.file(
                    File(_bgImagePath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                  )
                : Container(color: _bgColor),
          ),
          
          // Content Layer
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
                                child: GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 100, 16, 16), // Top padding for Status Bar
                                  // We hardcode the number of items to create a fixed grid layout.
                                  itemCount: _gridColumns * _gridRows,
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _gridColumns, // <--- Hardcoded grid width (columns)
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 24,
                                    childAspectRatio: 0.8,
                                  ),
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemBuilder: (context, index) {
                                    return DragTarget<AppInfo>(
                                      onAccept: (data) {
                                        setState(() {
                                          // If the app is already on the home screen, remove it from its old position.
                                          final int? oldIndex = _homeApps.keys.cast<int?>().firstWhere(
                                                (k) => _homeApps[k]?.packageName == data.packageName,
                                                orElse: () => null,
                                              );
                                          if (oldIndex != null) {
                                            _homeApps.remove(oldIndex);
                                          }
                                          // Place it in the new position
                                          _homeApps[index] = data;
                                        });
                                        _saveLayout();
                                      },
                                      builder: (context, candidateData, rejectedData) {
                                        final app = _homeApps[index];
                                        if (app == null) {
                                          return Container(
                                            decoration: BoxDecoration(
                                              border: candidateData.isNotEmpty
                                                  ? Border.all(color: Colors.white24)
                                                  : null,
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
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                            // Glass Status Bar
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: GlassStatusBar(
                                isImageBackground: _bgType == 'image',
                                backgroundColor: _bgColor,
                                opacity: 1.0,
                              ),
                            ),
                            // Remove Drop Zone
                            if (_isDragging)
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                height: 60,
                                child: Opacity(
                                  opacity: opacity,
                                  child: DragTarget<AppInfo>(
                                    onAccept: (data) {
                                      setState(() {
                                        _homeApps.removeWhere((key, value) => value.packageName == data.packageName);
                                      });
                                      _saveLayout();
                                    },
                                    builder: (context, candidateData, rejectedData) {
                                      return Container(
                                        color: candidateData.isNotEmpty
                                            ? Colors.red.withValues(alpha: 0.5)
                                            : Colors.red.withValues(alpha: 0.2),
                                        child: const Center(
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.delete, color: Colors.white),
                                              SizedBox(width: 8),
                                              Text(
                                                "Remove",
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    
                    // App Drawer (Draggable Sheet)
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
    );
  }

  // Helper method to build the individual app icon and name widget.
  Widget _buildAppIconVisual(AppInfo app) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
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
          // Name
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
