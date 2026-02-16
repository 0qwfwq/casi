import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class AppDrawer extends StatelessWidget {
  final List<AppInfo> apps;
  final ValueNotifier<double> progressNotifier;
  final Function(AppInfo) onAppTap;
  final Function(AppInfo) onAppLongPress;
  final VoidCallback onOpenSettings;
  final DraggableScrollableController? controller;

  const AppDrawer({
    super.key,
    required this.apps,
    required this.progressNotifier,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onOpenSettings,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final double progress = notification.extent / notification.maxExtent;
        progressNotifier.value = progress.clamp(0.0, 1.0);
        return false;
      },
      child: DraggableScrollableSheet(
        controller: controller,
        initialChildSize: 0.0,
        minChildSize: 0.0,
        maxChildSize: 0.9,
        snap: true,
        builder: (context, scrollController) {
          return _AppDrawerSheet(
            apps: apps,
            scrollController: scrollController,
            onAppTap: onAppTap,
            onAppLongPress: onAppLongPress,
            onOpenSettings: onOpenSettings,
            progressNotifier: progressNotifier,
          );
        },
      ),
    );
  }
}

class _AppDrawerSheet extends StatefulWidget {
  final List<AppInfo> apps;
  final ScrollController scrollController;
  final Function(AppInfo) onAppTap;
  final Function(AppInfo) onAppLongPress;
  final VoidCallback onOpenSettings;
  final ValueNotifier<double> progressNotifier;

  const _AppDrawerSheet({
    required this.apps,
    required this.scrollController,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onOpenSettings,
    required this.progressNotifier,
  });

  @override
  State<_AppDrawerSheet> createState() => _AppDrawerSheetState();
}

class _AppDrawerSheetState extends State<_AppDrawerSheet> {
  String _searchQuery = '';
  List<AppInfo> _filteredApps = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredApps = widget.apps;
  }

  void _updateSearch(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredApps = widget.apps;
      } else {
        _filteredApps = widget.apps
            .where((app) => app.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.progressNotifier,
      builder: (context, progress, _) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double width = screenWidth;
        const double borderRadius = 30.0;
        final double contentOpacity = (progress * 2).clamp(0.0, 1.0);

        return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: screenWidth,
              child: Stack(
                children: [
                  // Liquid Glass Background
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: width,
                      height: double.infinity,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(borderRadius)),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                child: Container(color: Colors.transparent),
                              ),
                            ),
                            Positioned.fill(
                              child: OCLiquidGlass(
                                color: Colors.white.withValues(alpha: 0.5),
                                child: const SizedBox(),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(borderRadius)),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Content
                  CustomScrollView(
                    controller: widget.scrollController,
                    slivers: [
                      // Handle / Dots Section
                      SliverToBoxAdapter(
                        child: Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),

                      // App Grid (Only visible when expanded)
                      // Search Bar (Moved to top)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverToBoxAdapter(
                          child: Opacity(
                            opacity: contentOpacity,
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: _updateSearch,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: 'Search apps...',
                                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                      prefixIcon: const Icon(Icons.search, color: Colors.white),
                                      filled: true,
                                      fillColor: Colors.white.withValues(alpha: 0.1),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.settings, color: Colors.white70),
                                  onPressed: widget.onOpenSettings,
                                  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.1)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SliverOpacity(
                        opacity: contentOpacity,
                        sliver: SliverPadding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 24,
                              childAspectRatio: 0.8,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final app = _filteredApps[index];
                                return InkWell(
                                  onTap: () => widget.onAppTap(app),
                                  onLongPress: () => widget.onAppLongPress(app),
                                  child: Column(
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
                                  ),
                                );
                              },
                              childCount: _filteredApps.length,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
      },
    );
  }
}