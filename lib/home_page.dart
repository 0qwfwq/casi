import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Hardcoded grid dimensions
  final int _gridColumns = 4;
  final int _gridRows = 6;

  @override
  void initState() {
    super.initState();
    _fetchApps();
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

  // Opens the bottom sheet containing all installed apps.
  void _showAppDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      "All Apps",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 24,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: _apps.length,
                      itemBuilder: (context, index) {
                        return InkWell(
                          onTap: () => InstalledApps.startApp(_apps[index].packageName),
                          onLongPress: () => _addToHomeScreen(_apps[index]),
                          child: _buildAppIconVisual(_apps[index]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark theme background
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 60, 16, 16), // Top padding for Remove bar
                    // We hardcode the number of items to create a fixed grid layout.
                    itemCount: _gridColumns * _gridRows,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _gridColumns, // <--- Hardcoded grid width (columns)
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 24,
                      childAspectRatio: 0.8,
                    ),
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
                  // Remove Drop Zone
                  if (_isDragging)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 60,
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
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAppDrawer,
        backgroundColor: Colors.white.withValues(alpha: 0.1),
        child: const Icon(Icons.apps, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
            errorBuilder: (context, error, stackTrace) => 
              const Icon(Icons.android, color: Colors.white, size: 48),
          ),
        ),
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
    );
  }
}
