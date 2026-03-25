import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/utils/app_launcher.dart';
import 'package:casi/design_system.dart';

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
        maxChildSize: 1.0,
        snap: true,
        snapSizes: const [0.0, 0.50],
        snapAnimationDuration: CASIMotion.micro,
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
  final FocusNode _searchFocusNode = FocusNode();

  List<String> _pinnedPackages = [];

  String? _activeLetter;
  bool _isAlphabetDragging = false;
  double _alphabetDragLocalY = 0.0;

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
      setState(() => _pinnedPackages = List<String>.from(pinned));
    }
  }

  Future<void> _savePinnedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pinned_drawer_apps', _pinnedPackages);
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
    final appMap = {for (final app in widget.apps) app.packageName: app};
    return _pinnedPackages
        .where((pkg) => appMap.containsKey(pkg))
        .map((pkg) => appMap[pkg]!)
        .toList();
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
    if (_activeLetter == letter) return;
    _activeLetter = letter;
    HapticFeedback.selectionClick();

    final key = _sectionKeys[letter];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: Duration.zero,
        alignment: 0.4,
      );
    }
  }

  @override
  void dispose() {
    widget.progressNotifier.removeListener(_onDrawerProgressChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.progressNotifier,
      builder: (context, progress, _) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double contentOpacity = (progress * 2).clamp(0.0, 1.0);

        for (final letter in _availableLetters) {
          _sectionKeys.putIfAbsent(letter, () => GlobalKey());
        }
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
                      SliverOpacity(
                        opacity: contentOpacity,
                        sliver: SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: CASISpacing.md,
                              right: progress > 0.85 ? 36 : CASISpacing.md,
                            ),
                            child: _searchQuery.isNotEmpty
                                ? _buildSearchResults()
                                : _buildAppList(),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.of(context).viewInsets.bottom + 80,
                        ),
                      ),
                    ],
                  ),
                ),
                // Alphabet sidebar — only visible at full screen
                if (progress > 0.85)
                  Positioned(
                    right: 20,
                    top: 0,
                    bottom: 10,
                    child: Offstage(
                      offstage: _searchQuery.isNotEmpty,
                      child: AnimatedOpacity(
                        opacity: ((progress - 0.85) / 0.15).clamp(0.0, 1.0),
                        duration: CASIMotion.micro,
                        child: _buildAlphabetSidebar(),
                      ),
                    ),
                  ),
                // Search bar — glass.heavy spec (section 8.2)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.of(context).viewInsets.bottom + CASISpacing.md,
                  child: Opacity(
                    opacity: contentOpacity,
                    child: Center(
                      child: SizedBox(
                        width: screenWidth * 0.6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(CASISearchBarSpec.cornerRadius),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: CASISearchBarSpec.blurRadius,
                              sigmaY: CASISearchBarSpec.blurRadius,
                            ),
                            child: Container(
                              height: CASISearchBarSpec.height,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: CASISearchBarSpec.tintAlpha),
                                borderRadius: BorderRadius.circular(CASISearchBarSpec.cornerRadius),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha),
                                  width: CASISearchBarSpec.focusBorderWidth,
                                ),
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: _updateSearch,
                                style: CASITypography.body1.copyWith(
                                  color: CASIColors.textPrimary,
                                ),
                                cursorColor: CASIColors.accentPrimary,
                                decoration: InputDecoration(
                                  hintText: 'Search or ask',
                                  hintStyle: CASITypography.body1.copyWith(
                                    color: CASIColors.textTertiary,
                                  ),
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.only(right: 14.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(CASIGlass.cornerPill),
                                            onTap: () {
                                              AppLauncher.launchApp('com.google.ar.lens');
                                            },
                                            child: Icon(
                                              Icons.center_focus_strong_outlined,
                                              color: CASIColors.textSecondary,
                                              size: CASISearchBarSpec.iconSize,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: CASISpacing.sm),
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(CASIGlass.cornerPill),
                                            onTap: widget.onOpenSettings,
                                            onLongPress: () {
                                              AppLauncher.launchApp('com.android.settings');
                                            },
                                            child: Icon(
                                              Icons.settings_outlined,
                                              color: CASIColors.textSecondary,
                                              size: CASISearchBarSpec.iconSize,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  filled: false,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: CASISearchBarSpec.horizontalPadding,
                                    vertical: 12,
                                  ),
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
        // Pinned section — 6-column grid
        if (pinned.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: CASISpacing.md,
              top: CASISpacing.sm,
              bottom: CASISpacing.xs,
            ),
            child: Text(
              'PINNED',
              style: CASITypography.caption.copyWith(
                color: CASIColors.textTertiary,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              childAspectRatio: 0.75,
              mainAxisSpacing: CASISpacing.xs,
              crossAxisSpacing: CASISpacing.xs,
            ),
            itemCount: pinned.length,
            itemBuilder: (context, index) {
              return _buildPinnedGridCell(pinned[index]);
            },
          ),
          // Separator — color.surface.divider (5% white hairline)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CASISpacing.md,
              vertical: CASISpacing.sm,
            ),
            child: Container(
              height: 0.5,
              color: CASIColors.glassDivider,
            ),
          ),
        ],
        // Alphabetical sections
        for (final entry in grouped.entries) ...[
          Container(
            key: _sectionKeys[entry.key],
            padding: const EdgeInsets.only(
              left: CASISpacing.md,
              top: CASISpacing.md,
              bottom: CASISpacing.xs,
            ),
            child: Text(
              entry.key,
              style: CASITypography.caption.copyWith(
                color: CASIColors.textTertiary,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.0,
              ),
            ),
          ),
          for (final app in entry.value)
            _buildAppRow(app, isPinned: false),
        ],
      ],
    );
  }

  // ── Single App Row (section 4.4 Single Column Spec) ────────────────────

  Widget _buildAppRow(AppInfo app, {required bool isPinned}) {
    final hasIcon = app.icon != null && app.icon!.isNotEmpty;

    return GestureDetector(
      onTap: () => widget.onAppTap(app),
      onLongPressStart: (details) {
        _showContextMenu(app, details.globalPosition);
      },
      child: Padding(
        // Row horizontal padding: 16dp each side (space.md)
        padding: const EdgeInsets.symmetric(
          horizontal: CASISpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
            // App icon — 48dp x 48dp (section 4.4)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: CASIAppIconSpec.iconStandard,
                height: CASIAppIconSpec.iconStandard,
                child: hasIcon
                    ? Image.memory(
                        app.icon!,
                        width: CASIAppIconSpec.iconStandard,
                        height: CASIAppIconSpec.iconStandard,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.android, color: CASIColors.textSecondary, size: 40),
                      )
                    : Icon(Icons.android, color: CASIColors.textSecondary, size: 40),
              ),
            ),
            // Icon-to-label padding: 16dp (space.md)
            const SizedBox(width: CASIAppIconSpec.iconToLabelPadding),
            // App name — type.body1 SemiBold (section 4.4)
            Expanded(
              child: Text(
                app.name,
                style: CASITypography.appLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Pin indicator
            if (isPinned)
              Padding(
                padding: const EdgeInsets.only(left: CASISpacing.sm),
                child: Icon(
                  Icons.push_pin,
                  size: CASIIcons.micro,
                  color: CASIColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Pinned App Grid Cell ─────────────────────────────────────────────

  Widget _buildPinnedGridCell(AppInfo app) {
    final hasIcon = app.icon != null && app.icon!.isNotEmpty;

    return GestureDetector(
      onTap: () => widget.onAppTap(app),
      onLongPressStart: (details) {
        _showContextMenu(app, details.globalPosition);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: hasIcon
                  ? Image.memory(
                      app.icon!,
                      width: 40,
                      height: 40,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.android, color: CASIColors.textSecondary, size: 36),
                    )
                  : Icon(Icons.android, color: CASIColors.textSecondary, size: 36),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            app.name,
            style: CASITypography.caption.copyWith(
              color: CASIColors.textPrimary,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Context Menu (Long Press) — glass.float level ─────────────────────

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
                  borderRadius: BorderRadius.circular(CASIGlass.cornerStandard),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: CASIGlass.blurHeavy,
                      sigmaY: CASIGlass.blurHeavy,
                    ),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pin / Unpin
                          InkWell(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(CASIGlass.cornerStandard),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              _togglePin(app);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CASISpacing.md,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    pinned ? Icons.push_pin_outlined : Icons.push_pin,
                                    color: CASIColors.textPrimary,
                                    size: CASIIcons.standard,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    pinned ? 'Unpin' : 'Pin to Top',
                                    style: CASITypography.body2.copyWith(
                                      color: CASIColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            height: 0.5,
                            color: CASIColors.glassDivider,
                          ),
                          // Add to Home
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onAddToHome(app);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CASISpacing.md,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.add_to_home_screen_outlined,
                                    color: CASIColors.textPrimary,
                                    size: CASIIcons.standard,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Add to Home',
                                    style: CASITypography.body2.copyWith(
                                      color: CASIColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            height: 0.5,
                            color: CASIColors.glassDivider,
                          ),
                          // App Info
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              InstalledApps.openSettings(app.packageName);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CASISpacing.md,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: CASIColors.textPrimary,
                                    size: CASIIcons.standard,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'App Info',
                                    style: CASITypography.body2.copyWith(
                                      color: CASIColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            height: 0.5,
                            color: CASIColors.glassDivider,
                          ),
                          // Uninstall
                          InkWell(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(CASIGlass.cornerStandard),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              widget.onUninstall(app);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: CASISpacing.md,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    color: CASIColors.alert,
                                    size: CASIIcons.standard,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Uninstall',
                                    style: CASITypography.body2.copyWith(
                                      color: CASIColors.alert,
                                    ),
                                  ),
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
        padding: const EdgeInsets.only(top: CASISpacing.hero),
        child: Center(
          child: Text(
            'No apps match that',
            style: CASITypography.body1.copyWith(
              color: CASIColors.textSecondary,
            ),
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
          const double baseLetterSize = 10.0;
          const double maxLetterSize = 22.0;
          const double morphRadius = 3.5;
          const double sidebarWidth = 28.0;

          final double availableHeight = constraints.maxHeight;
          final double letterSpacing = (availableHeight * 0.5) / letters.length;
          final double topOffset = availableHeight * 0.42;

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
                setState(() {});
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
                  if (_pinnedPackages.isNotEmpty)
                    Positioned(
                      top: topOffset - CASISpacing.md,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          widget.scrollController.animateTo(
                            0,
                            duration: CASIMotion.micro,
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
                                size: CASIIcons.micro,
                                color: CASIColors.textSecondary,
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

                      double fontSize = baseLetterSize;
                      double xOffset = 0.0;

                      if (_isAlphabetDragging) {
                        final double distFromFinger =
                            (centerY - _alphabetDragLocalY).abs() / letterSpacing;
                        if (distFromFinger < morphRadius) {
                          final double t = 1.0 - (distFromFinger / morphRadius);
                          final double curve = sin(t * pi / 2);
                          fontSize = baseLetterSize + (maxLetterSize - baseLetterSize) * curve;
                          xOffset = -28.0 * curve;
                        }
                      } else if (isActive) {
                        fontSize = 13.0;
                      }

                      return Positioned(
                        top: centerY - fontSize / 2,
                        right: -xOffset,
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
                                    style: CASITypography.caption.copyWith(
                                      color: isActive
                                          ? CASIColors.textPrimary
                                          : CASIColors.textTertiary,
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
          top: Radius.circular(CASIGlass.cornerSheet),
        ),
        child: Stack(
          children: [
            // Full blur layer (frosted glass effect)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: CASIGlass.blurBackground,
                  sigmaY: CASIGlass.blurBackground,
                ),
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
                    Colors.white.withValues(alpha: CASIElevation.base.bgAlpha),
                    Colors.white.withValues(alpha: CASIGlass.tintLight),
                    Colors.white.withValues(alpha: CASIGlass.tintStandard),
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
