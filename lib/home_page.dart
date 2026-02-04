import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<AppInfo> _apps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchApps();
  }

  Future<void> _fetchApps() async {
    // getInstalledApps({bool withIcon, bool excludeSystemApps, String packageNamePrefix})
    List<AppInfo> apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);

    // Sort alphabetically
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (mounted) {
      setState(() {
        _apps = apps;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark theme background
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  // 1. Placeholder for "Widgets"
                  SliverToBoxAdapter(
                    child: Container(
                      height: 200,
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.widgets, color: Colors.white54, size: 48),
                            SizedBox(height: 8),
                            Text(
                              "Widget Area",
                              style: TextStyle(color: Colors.white54, fontSize: 18),
                            ),
                            Text(
                              "(Customizable)",
                              style: TextStyle(color: Colors.white30, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // 2. Section Title
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text(
                        "All Apps",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // 3. App Grid
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, // 4 columns
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 24,
                        childAspectRatio: 0.8, // Adjust for icon + text height
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          AppInfo app = _apps[index];
                          return _buildAppIcon(app);
                        },
                        childCount: _apps.length,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAppIcon(AppInfo app) {
    return InkWell(
      onTap: () {
        InstalledApps.startApp(app.packageName);
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(8),
            // decoration: BoxDecoration(
            //   color: Colors.white.withValues(alpha: 0.05),
            //   shape: BoxShape.circle,
            // ),
            child: Image.memory(
              app.icon ?? Uint8List(0), // Just in case, though analyzer says non-null
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
      ),
    );
  }
}
