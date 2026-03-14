import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/utils/app_launcher.dart';

// ─── Main AppDrawer Widget ──────────────────────────────────────────────────

class AppDrawer extends StatelessWidget {
  final List<AppInfo> apps;
  final ValueNotifier<double> progressNotifier;
  final Function(AppInfo) onAppTap;
  final Function(AppInfo) onAddToHome;
  final Function(AppInfo) onUninstall;
  final VoidCallback onOpenSettings;
  final DraggableScrollableController? controller;

  const AppDrawer({
    super.key,
    required this.apps,
    required this.progressNotifier,
    required this.onAppTap,
    required this.onAddToHome,
    required this.onUninstall,
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
        maxChildSize: 0.75,
        snap: true,
        snapSizes: const [0.0, 0.75],
        snapAnimationDuration: const Duration(milliseconds: 120),
        builder: (context, scrollController) {
          return _AppDrawerSheet(
            apps: apps,
            scrollController: scrollController,
            onAppTap: onAppTap,
            onAddToHome: onAddToHome,
            onUninstall: onUninstall,
            onOpenSettings: onOpenSettings,
            progressNotifier: progressNotifier,
          );
        },
      ),
    );
  }
}

// ─── Drawer Sheet ───────────────────────────────────────────────────────────

class _AppDrawerSheet extends StatefulWidget {
  final List<AppInfo> apps;
  final ScrollController scrollController;
  final Function(AppInfo) onAppTap;
  final Function(AppInfo) onAddToHome;
  final Function(AppInfo) onUninstall;
  final VoidCallback onOpenSettings;
  final ValueNotifier<double> progressNotifier;

  const _AppDrawerSheet({
    required this.apps,
    required this.scrollController,
    required this.onAppTap,
    required this.onAddToHome,
    required this.onUninstall,
    required this.onOpenSettings,
    required this.progressNotifier,
  });

  @override
  State<_AppDrawerSheet> createState() => _AppDrawerSheetState();
}

class _AppDrawerSheetState extends State<_AppDrawerSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Pinned favorites
  Set<String> _pinnedPackages = {};

  // Alphabet index state
  String? _activeLetter;
  bool _isAlphabetDragging = false;
  double _alphabetDragLocalY = 0.0; // Track finger position for morph effect

  // Section keys for scroll jumping
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    widget.progressNotifier.addListener(_onDrawerProgressChanged);
    _loadPinnedApps();
  }

  void _onDrawerProgressChanged() {
    if (widget.progressNotifier.value <= 0.01) {
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        _updateSearch('');
      }
      FocusManager.instance.primaryFocus?.unfocus();
      if (_activeLetter != null) {
        setState(() => _activeLetter = null);
      }
    }
  }

  @override
  void didUpdateWidget(_AppDrawerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.apps != oldWidget.apps) {
      setState(() {});
    }
  }

  void _updateSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  // ── Pinned Apps Persistence ────────────────────────────────────────────

  Future<void> _loadPinnedApps() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? pinned = prefs.getStringList('pinned_drawer_apps');
    if (pinned != null && mounted) {
      setState(() => _pinnedPackages = pinned.toSet());
    }
  }

  Future<void> _savePinnedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_drawer_apps', _pinnedPackages.toList());
  }

  void _togglePin(AppInfo app) {
    setState(() {
      if (_pinnedPackages.contains(app.packageName)) {
        _pinnedPackages.remove(app.packageName);
      } else {
        _pinnedPackages.add(app.packageName);
      }
    });
    _savePinnedApps();
  }

  bool _isPinned(AppInfo app) => _pinnedPackages.contains(app.packageName);

  // ── App Lists ─────────────────────────────────────────────────────────

  List<AppInfo> get _pinnedApps {
    return widget.apps
        .where((app) => _pinnedPackages.contains(app.packageName))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<AppInfo> get _unpinnedApps {
    return widget.apps
        .where((app) => !_pinnedPackages.contains(app.packageName))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Map<String, List<AppInfo>> get _groupedApps {
    final Map<String, List<AppInfo>> groups = {};
    for (final app in _unpinnedApps) {
      final firstChar = app.name.trim().isNotEmpty
          ? app.name.trim()[0].toUpperCase()
          : '#';
      final key = RegExp(r'[A-Z]').hasMatch(firstChar) ? firstChar : '#';
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(app);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });
    return Map.fromEntries(sortedKeys.map((k) => MapEntry(k, groups[k]!)));
  }

  List<String> get _availableLetters {
    final groups = _groupedApps;
    return groups.keys.toList();
  }

  // ── Alphabet Navigation ───────────────────────────────────────────────

  void _jumpToLetter(String letter) {
    if (_activeLetter == letter) return; // Skip redundant jumps
    _activeLetter = letter;
    HapticFeedback.selectionClick();

    final key = _sectionKeys[letter];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: Duration.zero, // Instant jump — no animation lag
        alignment: 0.4,
      );
    }
  }

  @override
  void dispose() {
    widget.progressNotifier.removeListener(_onDrawerProgressChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.progressNotifier,
      builder: (context, progress, _) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double contentOpacity = (progress * 2).clamp(0.0, 1.0);

        // Ensure section keys exist for all available letters
        for (final letter in _availableLetters) {
          _sectionKeys.putIfAbsent(letter, () => GlobalKey());
        }
        // Remove stale keys
        _sectionKeys.removeWhere((k, _) => !_availableLetters.contains(k));

        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: screenWidth,
            child: Stack(
              children: [
                // Background - frosted glass with gradient opacity
                _GradientBackground(progress: progress),
                // Main scrollable content
                Positioned.fill(
                  top: 0,
                  child: CustomScrollView(
                    controller: widget.scrollController,
                    physics: const ClampingScrollPhysics(),
                    slivers: [
                      // Content
                      SliverOpacity(
                        opacity: contentOpacity,
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16, right: 36),
                            child: _searchQuery.isNotEmpty
                                ? _buildSearchResults()
                                : _buildAppList(),
                          ),
                        ),
                      ),
                      // Bottom padding for search bar
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.of(context).viewInsets.bottom + 80,
                        ),
                      ),
                    ],
                  ),
                ),
                // Alphabet sidebar - positioned on right edge
                // Always in tree (Offstage) so search bar TextField keeps its index & focus
                Positioned(
                  right: 20,
                  top: 0,
                  bottom: 10,
                  child: Offstage(
                    offstage: _searchQuery.isNotEmpty,
                    child: Opacity(
                      opacity: contentOpacity,
                      child: _buildAlphabetSidebar(),
                    ),
                  ),
                ),
                // Search bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  child: Opacity(
                    opacity: contentOpacity,
                    child: Center(
                      child: SizedBox(
                        width: screenWidth * 0.6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  width: 1.2,
                                ),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: _updateSearch,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Search apps',
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.only(right: 14.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(30),
                                            onTap: () {
                                              AppLauncher.launchApp('com.google.ar.lens');
                                            },
                                            child: const Icon(Icons.center_focus_strong, color: Colors.white70),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(30),
                                            onTap: widget.onOpenSettings,
                                            onLongPress: () {
                                              AppLauncher.launchApp('com.android.settings');
                                            },
                                            child: const Icon(Icons.settings, color: Colors.white70),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  filled: false,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── App List (Pinned + Alphabetical) ──────────────────────────────────

  Widget _buildAppList() {
    final pinned = _pinnedApps;
    final grouped = _groupedApps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pinned section
        if (pinned.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text(
              'PINNED',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
              ),
            ),
          ),
          for (final app in pinned)
            _buildAppRow(app, isPinned: true),
          // Separator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 0.5,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
        // Alphabetical sections
        for (final entry in grouped.entries) ...[
          // Section header
          Container(
            key: _sectionKeys[entry.key],
            padding: const EdgeInsets.only(left: 16, top: 16, bottom: 6),
            child: Text(
              entry.key,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.0,
              ),
            ),
          ),
          // Apps in this section
          for (final app in entry.value)
            _buildAppRow(app, isPinned: false),
        ],
      ],
    );
  }

  // ── Single App Row ────────────────────────────────────────────────────

  Widget _buildAppRow(AppInfo app, {required bool isPinned}) {
    final hasIcon = app.icon != null && app.icon!.isNotEmpty;

    return GestureDetector(
      onTap: () => widget.onAppTap(app),
      onLongPressStart: (details) {
        _showContextMenu(app, details.globalPosition);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // App icon
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: hasIcon
                    ? Image.memory(
                        app.icon!,
                        width: 48,
                        height: 48,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.android, color: Colors.white54, size: 40),
                      )
                    : const Icon(Icons.android, color: Colors.white54, size: 40),
              ),
            ),
            const SizedBox(width: 16),
            // App name
            Expanded(
              child: Text(
                app.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Pin indicator
            if (isPinned)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.push_pin,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Context Menu (Long Press) ─────────────────────────────────────────

  void _showContextMenu(AppInfo app, Offset position) {
    final screenSize = MediaQuery.of(context).size;
    final pinned = _isPinned(app);
    double left = (position.dx - 100).clamp(16.0, screenSize.width - 216.0);
    double top = (position.dy - 80).clamp(16.0, screenSize.height - 220.0);

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                    child: Container(
                      width: 200,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pin / Unpin
                          InkWell(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            onTap: () {
                              Navigator.of(context).pop();
                              _togglePin(app);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(
                                    pinned ? Icons.push_pin_outlined : Icons.push_pin,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    pinned ? 'Unpin' : 'Pin to Top',
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.2)),
                          // Add to Home
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onAddToHome(app);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(Icons.add_to_home_screen, color: Colors.white, size: 20),
                                  SizedBox(width: 12),
                                  Text('Add to Home', style: TextStyle(color: Colors.white, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                          Container(height: 0.5, color: Colors.white.withValues(alpha: 0.2)),
                          // Uninstall
                          InkWell(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onUninstall(app);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  SizedBox(width: 12),
                                  Text('Uninstall', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ],
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

  // ── Search Results ────────────────────────────────────────────────────

  Widget _buildSearchResults() {
    final filtered = widget.apps
        .where((app) => app.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Text(
            'No apps found',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final app in filtered)
          _buildAppRow(app, isPinned: _isPinned(app)),
      ],
    );
  }

  // ── Alphabet Sidebar with Fisheye Morph ────────────────────────────────

  Widget _buildAlphabetSidebar() {
    final letters = _availableLetters;
    if (letters.isEmpty) return const SizedBox(width: 28);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Sidebar starts near vertical center and extends down
          // Each letter gets a base height, the whole column aligns from center-down
          const double baseLetterSize = 10.0;
          const double maxLetterSize = 22.0;
          const double morphRadius = 3.5; // How many letters away the effect reaches
          const double sidebarWidth = 28.0;

          final double availableHeight = constraints.maxHeight;
          final double letterSpacing = (availableHeight * 0.5) / letters.length;
          final double topOffset = availableHeight * 0.42; // Start below center, easier to reach

          return SizedBox(
            width: sidebarWidth,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (details) {
                setState(() {
                  _isAlphabetDragging = true;
                  _alphabetDragLocalY = details.localPosition.dy;
                });
                final idx = ((details.localPosition.dy - topOffset) / letterSpacing)
                    .floor()
                    .clamp(0, letters.length - 1);
                if (letters[idx] != _activeLetter) {
                  _jumpToLetter(letters[idx]);
                }
              },
              onVerticalDragUpdate: (details) {
                _alphabetDragLocalY = details.localPosition.dy;
                final idx = ((details.localPosition.dy - topOffset) / letterSpacing)
                    .floor()
                    .clamp(0, letters.length - 1);
                if (letters[idx] != _activeLetter) {
                  _jumpToLetter(letters[idx]);
                }
                setState(() {}); // Rebuild for morph effect only
              },
              onVerticalDragEnd: (_) {
                setState(() => _isAlphabetDragging = false);
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (mounted && !_isAlphabetDragging) {
                    setState(() => _activeLetter = null);
                  }
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Star icon for pinned apps
                  if (_pinnedPackages.isNotEmpty)
                    Positioned(
                      top: topOffset - 16,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          widget.scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 100),
                            curve: Curves.easeOutCubic,
                          );
                        },
                        child: SizedBox(
                          width: sidebarWidth,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  for (int i = 0; i < letters.length; i++)
                    Builder(builder: (context) {
                      final letter = letters[i];
                      final isActive = _activeLetter == letter;
                      final double centerY = topOffset + (i * letterSpacing) + letterSpacing / 2;

                      // Fisheye morph: letters near finger bulge outward
                      double fontSize = baseLetterSize;
                      double xOffset = 0.0;

                      if (_isAlphabetDragging) {
                        final double distFromFinger =
                            (centerY - _alphabetDragLocalY).abs() / letterSpacing;
                        if (distFromFinger < morphRadius) {
                          final double t = 1.0 - (distFromFinger / morphRadius);
                          // Smooth curve for the bulge
                          final double curve = sin(t * pi / 2);
                          fontSize = baseLetterSize + (maxLetterSize - baseLetterSize) * curve;
                          // Push letters to the left so user's finger doesn't cover them
                          xOffset = -28.0 * curve;
                        }
                      } else if (isActive) {
                        fontSize = 13.0;
                      }

                      return Positioned(
                        top: centerY - fontSize / 2,
                        right: -xOffset, // Move left = increase right offset? No: left of sidebar
                        child: GestureDetector(
                          onTap: () => _jumpToLetter(letter),
                          child: Transform.translate(
                            offset: Offset(xOffset, 0),
                            child: SizedBox(
                              width: sidebarWidth + (-xOffset).abs(),
                              height: max(fontSize + 8, 20),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text(
                                    letter,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.45),
                                      fontSize: fontSize,
                                      fontWeight: isActive || (_isAlphabetDragging && fontSize > 14)
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Gradient Background ────────────────────────────────────────────────────
// Frosted glass: high opacity at bottom → transparent at top

class _GradientBackground extends StatelessWidget {
  final double progress;

  const _GradientBackground({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(36.0),
        ),
        child: Stack(
          children: [
            // Full blur layer (frosted glass effect)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(color: Colors.transparent),
              ),
            ),
            // Frosted tint: transparent at top → visible frost at bottom
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.0),
                    Colors.white.withValues(alpha: 0.03),
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.15),
                  ],
                  stops: const [0.0, 0.3, 0.6, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
