import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
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

  /// Wallpaper widget the drawer's liquid-glass surfaces (search bar, app
  /// long-press context menu) refract. Pass
  /// [WallpaperService.buildBackground].
  final Widget backgroundWidget;

  const AppDrawer({
    super.key,
    required this.apps,
    required this.progressNotifier,
    required this.onAppTap,
    required this.onAddToHome,
    required this.onUninstall,
    required this.onOpenSettings,
    required this.backgroundWidget,
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
        snapSizes: const <double>[0.0, 1.0],
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
            backgroundWidget: backgroundWidget,
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
  final Widget backgroundWidget;

  const _AppDrawerSheet({
    required this.apps,
    required this.scrollController,
    required this.onAppTap,
    required this.onAddToHome,
    required this.onUninstall,
    required this.onOpenSettings,
    required this.progressNotifier,
    required this.backgroundWidget,
  });

  @override
  State<_AppDrawerSheet> createState() => _AppDrawerSheetState();
}

class _AppDrawerSheetState extends State<_AppDrawerSheet> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String? _activeLetter;
  bool _isAlphabetDragging = false;
  double _alphabetDragLocalY = 0.0;

  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    widget.progressNotifier.addListener(_onDrawerProgressChanged);
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
      // Reset scroll to top (letter A) when drawer closes
      if (widget.scrollController.hasClients && widget.scrollController.offset > 0) {
        widget.scrollController.jumpTo(0);
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

  // ── App Lists ─────────────────────────────────────────────────────────

  List<AppInfo> get _sortedApps {
    return widget.apps.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Map<String, List<AppInfo>> get _groupedApps {
    final Map<String, List<AppInfo>> groups = {};
    for (final app in _sortedApps) {
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
        final double contentOpacity =
            (progress / 0.5).clamp(0.0, 1.0);

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
                // Transparent hit-test backdrop — no glass tint. The home
                // wallpaper shows through at 100% opacity (OneUI-style).
                // The GestureDetector absorbs stray taps on empty drawer
                // space so they don't fall through to the homescreen below.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
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
                            child: (_searchQuery.isNotEmpty && _isFullyExpanded)
                                ? _buildSearchResults()
                                : _buildAppList(context, progress),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          // Reserve room for the floating search bar while
                          // fully expanded (bottom gap 50 + height 54 + buffer).
                          height: _isFullyExpanded
                              ? MediaQuery.of(context).viewInsets.bottom + 120
                              : 0,
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
                // Search bar — only visible when fully expanded
                if (_isFullyExpanded)
                Positioned(
                  left: 0,
                  right: 0,
                  // Match the foresight dock's distance from the bottom of the
                  // screen when no apps are on the homescreen:
                  //   ScreenDock outer bottom padding (xl + sm = 40)
                  // + home-row inner bottom padding (10)
                  bottom: MediaQuery.of(context).viewInsets.bottom +
                      CASISpacing.xl + CASISpacing.sm + 10,
                  child: AnimatedOpacity(
                    opacity: _isFullyExpanded ? contentOpacity : 0.0,
                    duration: CASIMotion.fast,
                    child: Center(
                      child: SizedBox(
                        width: screenWidth * 0.6,
                        child: LiquidGlassSurface.drawer(
                          backgroundWidget: widget.backgroundWidget,
                          cornerRadius: CASISearchBarSpec.cornerRadius,
                          // Match foresight dock height (icon 34 + vertical padding 10 × 2).
                          height: 54,
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
              ],
            ),
          ),
        );
      },
    );
  }

  // ── App List (Pinned + Alphabetical) ──────────────────────────────────

  bool get _isFullyExpanded {
    return widget.progressNotifier.value > 0.05;
  }

  Widget _buildAppList(BuildContext context, double progress) {
    final grouped = _groupedApps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            _buildAppRow(app),
        ],
      ],
    );
  }

  // ── Single App Row (section 4.4 Single Column Spec) ────────────────────

  Widget _buildAppRow(AppInfo app) {
    final hasIcon = app.icon != null && app.icon!.isNotEmpty;

    return GestureDetector(
      onTap: () => widget.onAppTap(app),
      onLongPressStart: (details) {
        _showContextMenu(app, details.globalPosition);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CASISpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
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
            const SizedBox(width: CASIAppIconSpec.iconToLabelPadding),
            Expanded(
              child: Text(
                app.name,
                style: CASITypography.appLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Context Menu (Long Press) — glass.float level ─────────────────────

  void _showContextMenu(AppInfo app, Offset position) {
    HapticFeedback.mediumImpact();
    final screenSize = MediaQuery.of(context).size;

    const double menuWidth = 200;
    const double menuHeight = 170;

    double left = (position.dx - menuWidth / 2).clamp(16.0, screenSize.width - menuWidth - 16.0);
    double top = (position.dy - 40).clamp(16.0, screenSize.height - menuHeight - 16.0);

    final double alignX = ((position.dx - left) / menuWidth * 2 - 1).clamp(-1.0, 1.0);
    final double alignY = ((position.dy - top) / menuHeight * 2 - 1).clamp(-1.0, 1.0);

    // The menu lens refracts the wallpaper *with* the route's 15% black
    // scrim composited on top, so the refracted view matches what the
    // user actually sees behind the menu (dimmed wallpaper) rather than
    // a brighter raw-wallpaper slice that would clash with the scrim.
    final Widget menuBackdrop = Stack(
      fit: StackFit.expand,
      children: [
        widget.backgroundWidget,
        ColoredBox(color: Colors.black.withValues(alpha: 0.15)),
      ],
    );

    Navigator.of(context).push(
      _ContextMenuRoute(
        left: left,
        top: top,
        scaleAlignment: Alignment(alignX, alignY),
        child: _ContextMenuContent(
          backgroundWidget: menuBackdrop,
          onAddToHome: () {
            Navigator.of(context).pop();
            widget.onAddToHome(app);
          },
          onAppInfo: () {
            Navigator.of(context).pop();
            InstalledApps.openSettings(app.packageName);
          },
          onUninstall: () {
            Navigator.of(context).pop();
            widget.onUninstall(app);
          },
        ),
      ),
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
          _buildAppRow(app),
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

// ─── Animated Context Menu Route ──────────────────────────────────────────
//
// A custom [PopupRoute] that scales + fades the context menu in from the
// user's finger position. The animation uses an easeOutCubic curve for a
// smooth, organic feel that matches the CASI design language.

class _ContextMenuRoute extends PopupRoute<void> {
  final double left;
  final double top;
  final Alignment scaleAlignment;
  final Widget child;

  _ContextMenuRoute({
    required this.left,
    required this.top,
    required this.scaleAlignment,
    required this.child,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => CASIMotion.expressive;

  @override
  Duration get reverseTransitionDuration => CASIMotion.fast;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return child;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Stack(
      children: [
        // Tap-to-dismiss scrim
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: FadeTransition(
              opacity: curved,
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
        // Animated menu
        Positioned(
          left: left,
          top: top,
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
              alignment: scaleAlignment,
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Context Menu Content ─────────────────────────────────────────────────

class _ContextMenuContent extends StatelessWidget {
  final VoidCallback onAddToHome;
  final VoidCallback onAppInfo;
  final VoidCallback onUninstall;
  final Widget backgroundWidget;

  const _ContextMenuContent({
    required this.onAddToHome,
    required this.onAppInfo,
    required this.onUninstall,
    required this.backgroundWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LiquidGlassSurface.modal(
        backgroundWidget: backgroundWidget,
        cornerRadius: CASILiquidGlass.cornerStandard,
        width: 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ContextMenuItem(
              icon: Icons.add_to_home_screen_outlined,
              label: 'Add to Home',
              onTap: onAddToHome,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CASILiquidGlass.cornerStandard),
              ),
            ),
            _divider(),
            _ContextMenuItem(
              icon: Icons.info_outline,
              label: 'App Info',
              onTap: onAppInfo,
            ),
            _divider(),
            _ContextMenuItem(
              icon: Icons.delete_outline,
              label: 'Uninstall',
              onTap: onUninstall,
              color: CASIColors.alert,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(CASILiquidGlass.cornerStandard),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(height: 0.5, color: CASIColors.glassDivider);
  }
}

class _ContextMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final BorderRadius? borderRadius;

  const _ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = CASIColors.textPrimary,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: borderRadius,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CASISpacing.md,
          vertical: 14,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: CASIIcons.standard),
            const SizedBox(width: 12),
            Text(
              label,
              style: CASITypography.body2.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
