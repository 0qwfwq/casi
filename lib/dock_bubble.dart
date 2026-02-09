import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

class DockBubble extends StatelessWidget {
  final List<AppInfo> apps;
  final ValueNotifier<double> progressNotifier;
  final Function(AppInfo) onAppTap;
  final Function(AppInfo) onAppLongPress;
  final VoidCallback onOpenSettings;

  const DockBubble({
    super.key,
    required this.apps,
    required this.progressNotifier,
    required this.onAppTap,
    required this.onAppLongPress,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final double progress = (notification.extent - 0.05) / (0.5 - 0.05);
        progressNotifier.value = progress.clamp(0.0, 1.0);
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.05,
        minChildSize: 0.05,
        maxChildSize: 0.5,
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
        final double width = lerpDouble(120, screenWidth, progress)!;
        final double borderRadius = lerpDouble(30, 20, progress)!;
        // Fade content in as it expands
        final double contentOpacity = (progress - 0.6).clamp(0.0, 1.0) / 0.4;
        // Only show app names when fully expanded to prevent overflow during animation
        final bool showAppNames = progress > 0.99;

        return OCLiquidGlassGroup(
          settings: const OCLiquidGlassSettings(
            blurRadiusPx: 5.0,
            distortExponent: 1.0,
            distortFalloffPx: 20.0,
            specStrength: 5.0,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: screenWidth,
              child: Stack(
                children: [
                  // Liquid Glass Background
                  Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: width,
                      height: double.infinity,
                      child: OCLiquidGlass(
                        borderRadius: borderRadius,
                        color: Colors.grey[900]!.withValues(alpha: 0.4),
                        child: const SizedBox(),
                      ),
                    ),
                  ),
                  
                  // Content
                  CustomScrollView(
                    controller: widget.scrollController,
                    slivers: [
                      // Handle / Dots Section
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 20,
                        ),
                      ),

                      // App Grid (Only visible when expanded)
                      if (contentOpacity > 0) ...[
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
                                        if (showAppNames) ...[
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
                                    ),
                                  );
                                },
                                childCount: _filteredApps.length,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}