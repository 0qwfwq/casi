import 'dart:math';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:casi/utils/app_launcher.dart';

// ─── App Category Definitions ───────────────────────────────────────────────

class AppCategory {
  final String label;
  final IconData icon;
  final List<String> keywords;

  const AppCategory({required this.label, required this.icon, required this.keywords});
}

const List<AppCategory> _categoryDefinitions = [
  AppCategory(
    label: 'Social & Comms',
    icon: Icons.chat_bubble_outline,
    keywords: [
      'whatsapp', 'messenger', 'telegram', 'signal', 'discord', 'slack',
      'instagram', 'facebook', 'twitter', 'snapchat', 'tiktok', 'reddit',
      'linkedin', 'wechat', 'viber', 'line', 'skype', 'zoom', 'teams',
      'duo', 'meet', 'hangouts', 'kik', 'tumblr', 'pinterest', 'threads',
      'mastodon', 'bluesky', 'social', 'chat', 'message', 'sms', 'mms',
      'dialer', 'phone', 'contacts', 'call', 'mail', 'email', 'gmail',
      'outlook', 'yahoo', 'proton',
    ],
  ),
  AppCategory(
    label: 'Work & Study',
    icon: Icons.work_outline,
    keywords: [
      'docs', 'sheets', 'slides', 'drive', 'office', 'word', 'excel',
      'powerpoint', 'onenote', 'notion', 'evernote', 'todoist', 'trello',
      'asana', 'jira', 'confluence', 'classroom', 'canvas', 'blackboard',
      'duolingo', 'coursera', 'udemy', 'khan', 'quizlet', 'anki',
      'calculator', 'wolfram', 'desmos', 'translate', 'dictionary',
      'pdf', 'scanner', 'camscanner', 'adobe', 'reader', 'editor',
      'calendar', 'schedule', 'planner', 'reminder',
    ],
  ),
  AppCategory(
    label: 'Creative & Photos',
    icon: Icons.palette_outlined,
    keywords: [
      'camera', 'photo', 'gallery', 'snapseed', 'lightroom', 'vsco',
      'canva', 'figma', 'sketch', 'procreate', 'ibispaint', 'medibang',
      'krita', 'pixlr', 'picsart', 'inshot', 'capcut', 'kinemaster',
      'davinci', 'premiere', 'imovie', 'filmorago', 'video editor',
      'recorder', 'bandlab', 'garageband', 'fl studio', 'soundcloud',
      'draw', 'paint', 'art', 'design', 'creative',
    ],
  ),
  AppCategory(
    label: 'Media & Fun',
    icon: Icons.play_circle_outline,
    keywords: [
      'youtube', 'netflix', 'hulu', 'disney', 'hbo', 'prime video',
      'spotify', 'apple music', 'deezer', 'tidal', 'pandora',
      'twitch', 'crunchyroll', 'funimation', 'plex', 'vlc', 'podcast',
      'audible', 'kindle', 'books', 'play books', 'comics', 'manga',
      'webtoon', 'music', 'player', 'radio', 'tv', 'stream', 'video',
      'movie', 'game', 'games', 'play games', 'steam', 'roblox',
      'minecraft', 'fortnite', 'pubg', 'among us', 'candy',
    ],
  ),
  AppCategory(
    label: 'Shopping',
    icon: Icons.shopping_bag_outlined,
    keywords: [
      'amazon', 'ebay', 'walmart', 'target', 'aliexpress', 'wish',
      'etsy', 'shopify', 'mercari', 'poshmark', 'depop', 'grailed',
      'instacart', 'doordash', 'uber eats', 'grubhub', 'postmates',
      'seamless', 'caviar', 'gopuff', 'shop', 'store', 'market',
      'deal', 'coupon', 'price', 'buy', 'order', 'delivery', 'food',
      'grocery', 'costco', 'ikea', 'nike', 'adidas', 'shein', 'temu',
    ],
  ),
  AppCategory(
    label: 'Health & Fitness',
    icon: Icons.favorite_outline,
    keywords: [
      'health', 'fitness', 'workout', 'exercise', 'gym', 'run',
      'strava', 'fitbit', 'myfitnesspal', 'nike run', 'peloton',
      'calm', 'headspace', 'meditation', 'sleep', 'flo', 'period',
      'step', 'pedometer', 'weight', 'diet', 'nutrition', 'water',
      'mental', 'therapy', 'betterhelp', 'doctor', 'medical',
    ],
  ),
  AppCategory(
    label: 'Travel & Maps',
    icon: Icons.explore_outlined,
    keywords: [
      'maps', 'waze', 'uber', 'lyft', 'bolt', 'grab', 'transit',
      'citymapper', 'moovit', 'google earth', 'booking', 'airbnb',
      'expedia', 'kayak', 'skyscanner', 'tripadvisor', 'yelp',
      'compass', 'gps', 'navigation', 'travel', 'flight', 'hotel',
      'airline', 'train', 'bus', 'metro',
    ],
  ),
  AppCategory(
    label: 'Finance',
    icon: Icons.account_balance_outlined,
    keywords: [
      'bank', 'pay', 'wallet', 'venmo', 'cashapp', 'zelle', 'paypal',
      'chase', 'wells fargo', 'citi', 'capital one', 'amex',
      'robinhood', 'coinbase', 'crypto', 'stock', 'invest', 'trading',
      'mint', 'ynab', 'budget', 'expense', 'finance', 'money',
      'insurance', 'tax', 'credit',
    ],
  ),
  AppCategory(
    label: 'Tools',
    icon: Icons.build_outlined,
    keywords: [
      'settings', 'files', 'file manager', 'clock', 'alarm', 'timer',
      'flashlight', 'torch', 'compass', 'measure', 'level', 'qr',
      'barcode', 'vpn', 'proxy', 'cleaner', 'booster', 'battery',
      'wifi', 'bluetooth', 'nfc', 'launcher', 'keyboard', 'gboard',
      'swiftkey', 'clipboard', 'manager', 'monitor', 'system',
      'update', 'backup', 'restore', 'security', 'antivirus',
      'authenticator', 'password', 'bitwarden', 'lastpass',
      'weather', 'news', 'browser', 'chrome', 'firefox', 'edge',
      'opera', 'brave', 'samsung', 'google', 'android', 'pixel',
    ],
  ),
];

// ─── Categorize apps ────────────────────────────────────────────────────────

class _CategorizedApps {
  final String label;
  final IconData icon;
  final List<AppInfo> apps;

  _CategorizedApps({required this.label, required this.icon, required this.apps});
}

List<_CategorizedApps> _categorizeApps(List<AppInfo> apps) {
  final Map<int, List<AppInfo>> buckets = {};
  final Set<String> assigned = {};

  for (int i = 0; i < _categoryDefinitions.length; i++) {
    buckets[i] = [];
  }

  for (final app in apps) {
    final nameLower = app.name.toLowerCase();
    final pkgLower = app.packageName.toLowerCase();
    bool found = false;

    for (int i = 0; i < _categoryDefinitions.length; i++) {
      for (final kw in _categoryDefinitions[i].keywords) {
        if (nameLower.contains(kw) || pkgLower.contains(kw)) {
          buckets[i]!.add(app);
          assigned.add(app.packageName);
          found = true;
          break;
        }
      }
      if (found) break;
    }
  }

  // Unassigned apps go to "Other"
  final unassigned = apps.where((a) => !assigned.contains(a.packageName)).toList();

  final result = <_CategorizedApps>[];
  for (int i = 0; i < _categoryDefinitions.length; i++) {
    if (buckets[i]!.isNotEmpty) {
      result.add(_CategorizedApps(
        label: _categoryDefinitions[i].label,
        icon: _categoryDefinitions[i].icon,
        apps: buckets[i]!,
      ));
    }
  }
  if (unassigned.isNotEmpty) {
    result.add(_CategorizedApps(
      label: 'Other',
      icon: Icons.apps,
      apps: unassigned,
    ));
  }

  return result;
}

// ─── Main AppDrawer Widget ──────────────────────────────────────────────────

class AppDrawer extends StatelessWidget {
  final List<AppInfo> apps;
  final ValueNotifier<double> progressNotifier;
  final Function(AppInfo) onAppTap;
  final Function(AppInfo, Offset) onAppLongPress;
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
        maxChildSize: 1.0,
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

// ─── Drawer Sheet ───────────────────────────────────────────────────────────

class _AppDrawerSheet extends StatefulWidget {
  final List<AppInfo> apps;
  final ScrollController scrollController;
  final Function(AppInfo) onAppTap;
  final Function(AppInfo, Offset) onAppLongPress;
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
  final TextEditingController _searchController = TextEditingController();

  // Folder expansion state: index of expanded folder, or -1 for none
  int _expandedFolder = -1;

  // Gallery thumbnails
  List<Uint8List> _galleryThumbs = [];
  bool _galleryPermissionDenied = false;

  @override
  void initState() {
    super.initState();
    widget.progressNotifier.addListener(_onDrawerProgressChanged);
    _loadGalleryThumbs();
  }

  void _onDrawerProgressChanged() {
    if (widget.progressNotifier.value <= 0.01) {
      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
        _updateSearch('');
      }
      FocusManager.instance.primaryFocus?.unfocus();
      // Collapse folders when drawer closes
      if (_expandedFolder != -1) {
        setState(() => _expandedFolder = -1);
      }
    }
  }

  @override
  void didUpdateWidget(_AppDrawerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Force rebuild when app list changes
    if (widget.apps != oldWidget.apps) {
      setState(() {});
    }
  }

  void _updateSearch(String query) {
    setState(() {
      _searchQuery = query;
      _expandedFolder = -1; // collapse folders during search
    });
  }

  Future<void> _loadGalleryThumbs() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        setState(() => _galleryPermissionDenied = true);
        return;
      }

      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          imageOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true),
          ),
          orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );

      if (albums.isEmpty) return;

      // Get recent images from the first album (camera roll)
      final List<AssetEntity> recentImages = await albums.first.getAssetListRange(start: 0, end: 50);
      if (recentImages.isEmpty) return;

      // Pick 4 random ones
      final random = Random();
      final picked = <AssetEntity>[];
      final indices = List.generate(recentImages.length, (i) => i)..shuffle(random);
      for (int i = 0; i < min(4, indices.length); i++) {
        picked.add(recentImages[indices[i]]);
      }

      final thumbs = <Uint8List>[];
      for (final asset in picked) {
        final data = await asset.thumbnailDataWithSize(const ThumbnailSize(200, 200));
        if (data != null) thumbs.add(data);
      }

      if (mounted) {
        setState(() => _galleryThumbs = thumbs);
      }
    } catch (e) {
      debugPrint('Gallery thumbnail error: $e');
    }
  }

  void _openGalleryApp() {
    // Try common gallery package names
    const galleryPackages = [
      'com.google.android.apps.photos',      // Google Photos
      'com.sec.android.gallery3d',            // Samsung Gallery
      'com.miui.gallery',                     // Xiaomi Gallery
      'com.oneplus.gallery',                  // OnePlus Gallery
      'com.oppo.gallery3d',                   // Oppo Gallery
      'com.android.gallery3d',                // AOSP Gallery
    ];

    // Try launching the first available one
    for (final pkg in galleryPackages) {
      // We'll just try the first few most common ones
      if (widget.apps.any((a) => a.packageName == pkg)) {
        AppLauncher.launchApp(pkg);
        return;
      }
    }
    // Fallback: try Google Photos (most common)
    AppLauncher.launchApp('com.google.android.apps.photos');
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

        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: screenWidth,
            child: Stack(
              children: [
                // Gradient opacity background
                _GradientBackground(progress: progress),
                // Main scrollable content
                CustomScrollView(
                  controller: widget.scrollController,
                  slivers: [
                    // Drag handle
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
                    // Content
                    SliverOpacity(
                      opacity: contentOpacity,
                      sliver: SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              // Gallery widget
                              _buildGalleryWidget(),
                              const SizedBox(height: 20),
                              // Folders or search results
                              _searchQuery.isNotEmpty
                                  ? _buildSearchResults()
                                  : _buildFolders(),
                              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 80),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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

  // ── Gallery Widget ──────────────────────────────────────────────────────

  Widget _buildGalleryWidget() {
    return GestureDetector(
      onTap: _openGalleryApp,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.2,
              ),
            ),
            child: _galleryPermissionDenied
                ? Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, color: Colors.white.withValues(alpha: 0.5), size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'Tap to open Gallery',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : _galleryThumbs.isEmpty
                    ? Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined, color: Colors.white.withValues(alpha: 0.5), size: 24),
                            const SizedBox(width: 10),
                            Text(
                              'Gallery',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            for (int i = 0; i < _galleryThumbs.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.memory(
                                    _galleryThumbs[i],
                                    fit: BoxFit.cover,
                                    height: 70,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  // ── Search Results (flat grid like before) ────────────────────────────

  Widget _buildSearchResults() {
    final filtered = widget.apps
        .where((app) => app.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            'No apps found',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 16,
        mainAxisSpacing: 24,
        childAspectRatio: 0.8,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) => _buildAppTile(filtered[index]),
    );
  }

  // ── Folder Grid ───────────────────────────────────────────────────────

  Widget _buildFolders() {
    final categories = _categorizeApps(widget.apps);

    // Build a list of widgets: 2-column rows of folders, with expanded folder inline
    final List<Widget> children = [];

    int i = 0;
    while (i < categories.length) {
      if (_expandedFolder == i) {
        // This folder is expanded — show it full width
        children.add(_buildExpandedFolder(categories[i], i));
        i++;
      } else if (_expandedFolder == i + 1 && i + 1 < categories.length) {
        // The next folder is expanded: show this one alone, then expanded next
        children.add(Row(
          children: [
            Expanded(child: _buildFolderCard(categories[i], i)),
            const Expanded(child: SizedBox()),
          ],
        ));
        i++;
      } else if (i + 1 < categories.length) {
        // Normal: two folders side by side
        if (_expandedFolder != i + 1) {
          children.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildFolderCard(categories[i], i)),
              const SizedBox(width: 12),
              Expanded(child: _buildFolderCard(categories[i + 1], i + 1)),
            ],
          ));
          i += 2;
        } else {
          children.add(Row(
            children: [
              Expanded(child: _buildFolderCard(categories[i], i)),
              const Expanded(child: SizedBox()),
            ],
          ));
          i++;
        }
      } else {
        // Odd folder at end
        children.add(Row(
          children: [
            Expanded(child: _buildFolderCard(categories[i], i)),
            const Expanded(child: SizedBox()),
          ],
        ));
        i++;
      }
    }

    return Column(children: children);
  }

  // ── Collapsed Folder Card ─────────────────────────────────────────────

  Widget _buildFolderCard(_CategorizedApps category, int index) {
    // Show up to 4 app icons as preview
    final previewApps = category.apps.take(4).toList();

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedFolder = _expandedFolder == index ? -1 : index;
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Folder label
                  Row(
                    children: [
                      Icon(category.icon, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          category.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${category.apps.length}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // App icon previews (2x2 grid)
                  SizedBox(
                    height: 72,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: previewApps.length,
                      itemBuilder: (context, i) {
                        final app = previewApps[i];
                        final hasIcon = app.icon != null && app.icon!.isNotEmpty;
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: hasIcon
                              ? Image.memory(
                                  app.icon!,
                                  width: 32,
                                  height: 32,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.android, color: Colors.white54, size: 28),
                                )
                              : const Icon(Icons.android, color: Colors.white54, size: 28),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Expanded Folder ───────────────────────────────────────────────────

  Widget _buildExpandedFolder(_CategorizedApps category, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Folder header with close
                GestureDetector(
                  onTap: () => setState(() => _expandedFolder = -1),
                  child: Row(
                    children: [
                      Icon(category.icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          category.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_up, color: Colors.white.withValues(alpha: 0.6), size: 24),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // App grid inside expanded folder
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 20,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: category.apps.length,
                  itemBuilder: (context, i) => _buildAppTile(category.apps[i]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Single App Tile ───────────────────────────────────────────────────

  Widget _buildAppTile(AppInfo app) {
    final hasIcon = app.icon != null && app.icon!.isNotEmpty;

    return GestureDetector(
      onTap: () => widget.onAppTap(app),
      onLongPressStart: (details) => widget.onAppLongPress(app, details.globalPosition),
      child: Column(
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
  }
}

// ─── Gradient Background ────────────────────────────────────────────────────

class _GradientBackground extends StatelessWidget {
  final double progress;

  const _GradientBackground({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(36.0 * (1.0 - progress)), // loses radius as it goes full screen
        ),
        child: Stack(
          children: [
            // Blur layer
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(color: Colors.transparent),
              ),
            ),
            // Gradient opacity overlay: transparent at top → opaque at bottom
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.7),
                    Colors.black.withValues(alpha: 1.0),
                  ],
                  stops: const [0.0, 0.3, 0.6, 1.0],
                ),
              ),
            ),
            // Subtle white glass border overlay at top
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(36.0 * (1.0 - progress)),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
