import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/design_system.dart';
import '../services/wallpaper_service.dart';
import '../services/notification_pill_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _immersiveMode = false;
  String _temperatureUnit = 'C'; // 'C' or 'F'
  final WallpaperService _wallpaperService = WallpaperService();
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _wallpaperService.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await _wallpaperService.initialize();
    setState(() {
      _immersiveMode = prefs.getBool('immersive_mode') ?? false;
      _temperatureUnit = prefs.getString('temperature_unit') ?? 'C';
      _nameController.text = prefs.getString('user_name') ?? '';
    });
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name.trim());
  }

  Future<void> _toggleImmersiveMode(bool value) async {
    setState(() {
      _immersiveMode = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('immersive_mode', value);

    if (value) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Wallpaper background
          Positioned.fill(child: _wallpaperService.buildBackground()),
          // Glass-tinted overlay for readability
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
          // Content
          SafeArea(
            child: ListView(
              children: [
                // Your Name
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, color: Colors.white),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Your Name',
                            labelStyle: TextStyle(color: CASIColors.textSecondary),
                            hintText: 'Enter your name',
                            hintStyle: TextStyle(color: CASIColors.textTertiary, fontSize: 13),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: CASIColors.textTertiary),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: CASIColors.accentPrimary),
                            ),
                          ),
                          onChanged: _saveName,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  title: const Text("Background", style: TextStyle(color: Colors.white)),
                  leading: const Icon(Icons.wallpaper, color: Colors.white),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  onTap: () {
                    Navigator.push(context, PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => const BackgroundSettingsPage(),
                      transitionDuration: const Duration(milliseconds: 80),
                      reverseTransitionDuration: const Duration(milliseconds: 60),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ));
                  },
                ),
                SwitchListTile(
                  title: const Text("Immersive Mode", style: TextStyle(color: Colors.white)),
                  subtitle: const Text("Hide status & navigation bars", style: TextStyle(color: CASIColors.textSecondary, fontSize: 12)),
                  secondary: const Icon(Icons.fullscreen, color: Colors.white),
                  value: _immersiveMode,
                  onChanged: _toggleImmersiveMode,
                  activeThumbColor: CASIColors.accentPrimary,
                ),
                ListTile(
                  title: const Text("Temperature Unit", style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _temperatureUnit == 'C' ? 'Celsius (°C)' : 'Fahrenheit (°F)',
                    style: const TextStyle(color: CASIColors.textSecondary, fontSize: 12),
                  ),
                  leading: const Icon(Icons.thermostat, color: Colors.white),
                  trailing: ToggleButtons(
                    isSelected: [_temperatureUnit == 'C', _temperatureUnit == 'F'],
                    onPressed: (index) async {
                      final unit = index == 0 ? 'C' : 'F';
                      setState(() => _temperatureUnit = unit);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('temperature_unit', unit);
                    },
                    borderRadius: BorderRadius.circular(8),
                    selectedColor: Colors.white,
                    fillColor: CASIColors.accentPrimary.withValues(alpha: 0.3),
                    color: CASIColors.textSecondary,
                    borderColor: CASIColors.textTertiary,
                    selectedBorderColor: CASIColors.accentPrimary,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
                    children: const [
                      Text('°C', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('°F', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                ListTile(
                  title: const Text("Notification Tiers", style: TextStyle(color: Colors.white)),
                  subtitle: const Text("Customize app priority for notification pills", style: TextStyle(color: CASIColors.textSecondary, fontSize: 12)),
                  leading: const Icon(Icons.notifications_active_outlined, color: Colors.white),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  onTap: () {
                    Navigator.push(context, PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => const NotificationTierSettingsPage(),
                      transitionDuration: const Duration(milliseconds: 80),
                      reverseTransitionDuration: const Duration(milliseconds: 60),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BackgroundSettingsPage extends StatefulWidget {
  const BackgroundSettingsPage({super.key});

  @override
  State<BackgroundSettingsPage> createState() => _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState extends State<BackgroundSettingsPage> {
  // 'color', 'image', or 'system'
  String _backgroundType = 'color';
  Color _backgroundColor = Colors.black;
  String? _backgroundImagePath;
  final WallpaperService _wallpaperService = WallpaperService();

  final TextEditingController _hexController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _wallpaperService.dispose();
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await _wallpaperService.initialize();
    setState(() {
      _backgroundType = prefs.getString('bg_type') ?? 'color';

      final int colorValue = prefs.getInt('bg_color') ?? 0xFF000000;
      _backgroundColor = Color(colorValue);
      String hex = colorValue.toRadixString(16).toUpperCase();
      if (hex.length == 8 && hex.startsWith('FF')) {
        hex = hex.substring(2);
      }
      _hexController.text = hex;

      _backgroundImagePath = prefs.getString('bg_image_path');
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_type', _backgroundType);
    await prefs.setInt('bg_color', _backgroundColor.toARGB32());
    if (_backgroundImagePath != null) {
      await prefs.setString('bg_image_path', _backgroundImagePath!);
    }
  }

  void _updateColorFromHex(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    try {
      final int val = int.parse(hex, radix: 16);
      setState(() {
        _backgroundColor = Color(val);
      });
      _saveSettings();
    } catch (e) {
      // Invalid hex, ignore
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null && mounted) {
      // Navigate to the crop/adjust screen
      final croppedPath = await Navigator.push<String>(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              WallpaperAdjustPage(imagePath: image.path),
          transitionDuration: const Duration(milliseconds: 80),
          reverseTransitionDuration: const Duration(milliseconds: 60),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );

      if (croppedPath != null) {
        setState(() {
          _backgroundImagePath = croppedPath;
          _backgroundType = 'image';
        });
        _saveSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Background Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Wallpaper background
          Positioned.fill(child: _wallpaperService.buildBackground()),
          // Glass-tinted overlay
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),
          // Content
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  "Background",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Background Type Selector — glass card
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: CASIGlass.blurLight, sigmaY: CASIGlass.blurLight),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha),
                        ),
                      ),
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            title: const Text("Solid Color", style: TextStyle(color: Colors.white)),
                            value: 'color',
                            groupValue: _backgroundType,
                            onChanged: (value) {
                              setState(() => _backgroundType = value!);
                              _saveSettings();
                            },
                            activeColor: CASIColors.accentPrimary,
                          ),
                          RadioListTile<String>(
                            title: const Text("Image", style: TextStyle(color: Colors.white)),
                            value: 'image',
                            groupValue: _backgroundType,
                            onChanged: (value) {
                              setState(() => _backgroundType = value!);
                              _saveSettings();
                            },
                            activeColor: CASIColors.accentPrimary,
                          ),
                          RadioListTile<String>(
                            title: const Text("System Wallpaper", style: TextStyle(color: Colors.white)),
                            subtitle: Text(
                              _wallpaperService.hasSystemWallpaper
                                  ? "Uses your device wallpaper"
                                  : "Live wallpaper pass-through",
                              style: const TextStyle(color: CASIColors.textSecondary, fontSize: 12),
                            ),
                            value: 'system',
                            groupValue: _backgroundType,
                            onChanged: (value) {
                              setState(() => _backgroundType = value!);
                              _saveSettings();
                            },
                            activeColor: CASIColors.accentPrimary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Contextual Settings based on selection
                if (_backgroundType == 'color') ...[
                  const Text("Hex Color", style: TextStyle(color: CASIColors.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _backgroundColor,
                          border: Border.all(color: CASIColors.textSecondary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: CASIGlass.blurLight, sigmaY: CASIGlass.blurLight),
                            child: TextField(
                              controller: _hexController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                prefixText: '# ',
                                prefixStyle: const TextStyle(color: CASIColors.textSecondary),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                hintText: '000000',
                                hintStyle: TextStyle(color: CASIColors.textTertiary),
                              ),
                              onChanged: _updateColorFromHex,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (_backgroundType == 'image') ...[
                  const Text("Selected Image", style: TextStyle(color: CASIColors.textSecondary)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickImage,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: CASIGlass.blurLight, sigmaY: CASIGlass.blurLight),
                        child: Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha)),
                            image: _backgroundImagePath != null
                                ? DecorationImage(
                                    image: FileImage(File(_backgroundImagePath!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _backgroundImagePath == null
                              ? const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_photo_alternate, color: CASIColors.textSecondary, size: 40),
                                      SizedBox(height: 8),
                                      Text("Tap to pick image", style: TextStyle(color: CASIColors.textSecondary)),
                                    ],
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  if (_backgroundImagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.edit, color: CASIColors.accentPrimary),
                          label: const Text("Change Image", style: TextStyle(color: CASIColors.accentPrimary)),
                        ),
                      ),
                    ),
                ] else if (_backgroundType == 'system') ...[
                  // System wallpaper info
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: CASIGlass.blurLight, sigmaY: CASIGlass.blurLight),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: CASIElevation.card.bgAlpha),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: CASIElevation.card.borderAlpha)),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.wallpaper_rounded,
                              color: CASIColors.accentPrimary,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _wallpaperService.hasSystemWallpaper
                                  ? "Your device wallpaper will show through all glass surfaces"
                                  : "The Android window is transparent — your system wallpaper (including live wallpapers) shows directly behind the launcher",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: CASIColors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notification Tier Settings Page
// ---------------------------------------------------------------------------

class NotificationTierSettingsPage extends StatefulWidget {
  const NotificationTierSettingsPage({super.key});

  @override
  State<NotificationTierSettingsPage> createState() =>
      _NotificationTierSettingsPageState();
}

class _NotificationTierSettingsPageState
    extends State<NotificationTierSettingsPage> {
  final WallpaperService _wallpaperService = WallpaperService();
  Map<String, int> _overrides = {};

  static const _tierLabels = {
    0: 'Ignored',
    1: 'T1 Critical',
    2: 'T2 Personal',
    3: 'T3 Professional',
    4: 'T4 Social',
    5: 'T5 Reminders',
    6: 'T6 Utility',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _wallpaperService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _wallpaperService.initialize();
    await NotificationPillService.loadUserOverrides();
    if (mounted) {
      setState(() {
        _overrides = Map.from(NotificationPillService.userOverrides);
      });
    }
  }

  Future<void> _addOverride() async {
    final controller = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        int selectedTier = 1;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: CASIColors.void_,
            title: const Text('Add Tier Override',
                style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Package name',
                    labelStyle: TextStyle(color: CASIColors.textSecondary),
                    hintText: 'com.example.app',
                    hintStyle: TextStyle(color: CASIColors.textTertiary),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: CASIColors.textTertiary),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: CASIColors.accentPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButton<int>(
                  value: selectedTier,
                  dropdownColor: CASIColors.void_,
                  isExpanded: true,
                  items: _tierLabels.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          style: const TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedTier = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: CASIColors.textSecondary)),
              ),
              TextButton(
                onPressed: () {
                  final pkg = controller.text.trim();
                  if (pkg.isNotEmpty) {
                    Navigator.pop(
                        ctx, {'package': pkg, 'tier': selectedTier});
                  }
                },
                child: const Text('Save',
                    style: TextStyle(color: CASIColors.accentPrimary)),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();

    if (result != null) {
      final pkg = result['package'] as String;
      final tier = result['tier'] as int;
      await NotificationPillService.setTierOverride(pkg, tier);
      if (mounted) {
        setState(() => _overrides[pkg] = tier);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Notification Tiers'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addOverride,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _wallpaperService.buildBackground()),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
          ),
          SafeArea(
            child: _overrides.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune,
                              color: CASIColors.textTertiary, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'No custom overrides yet.\n'
                            'Tap + to promote or demote an app\'s notification tier.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: CASIColors.textSecondary, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Default tiers are assigned automatically based on app type.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: CASIColors.textTertiary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _overrides.length,
                    itemBuilder: (context, index) {
                      final pkg = _overrides.keys.elementAt(index);
                      final tier = _overrides[pkg]!;
                      return ListTile(
                        title: Text(pkg,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        subtitle: Text(_tierLabels[tier] ?? 'Unknown',
                            style: const TextStyle(
                                color: CASIColors.textSecondary, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: CASIColors.textTertiary, size: 20),
                          onPressed: () async {
                            await NotificationPillService.removeTierOverride(
                                pkg);
                            if (mounted) {
                              setState(() => _overrides.remove(pkg));
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wallpaper Adjust Page — crop, resize, and reposition
// ---------------------------------------------------------------------------

class WallpaperAdjustPage extends StatefulWidget {
  final String imagePath;

  const WallpaperAdjustPage({super.key, required this.imagePath});

  @override
  State<WallpaperAdjustPage> createState() => _WallpaperAdjustPageState();
}

class _WallpaperAdjustPageState extends State<WallpaperAdjustPage> {
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;
  Offset _focalStart = Offset.zero;
  bool _saving = false;

  final GlobalKey _repaintKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CASIColors.void_,
      appBar: AppBar(
        title: const Text('Adjust Wallpaper'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveAndReturn,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: CASIColors.accentPrimary,
                    ),
                  )
                : const Text(
                    'Done',
                    style: TextStyle(
                      color: CASIColors.accentPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Pinch to resize · Drag to reposition',
              style: TextStyle(
                color: CASIColors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          // Interactive image area — fills remaining space
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRect(
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (details) {
                        _previousScale = _scale;
                        _previousOffset = _offset;
                        _focalStart = details.focalPoint;
                      },
                      onScaleUpdate: (details) {
                        setState(() {
                          _scale = (_previousScale * details.scale)
                              .clamp(0.3, 5.0);
                          _offset = _previousOffset +
                              (details.focalPoint - _focalStart);
                        });
                      },
                      child: Container(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        color: Colors.black,
                        child: Transform(
                          transform: Matrix4.identity()
                            ..translate(_offset.dx, _offset.dy)
                            ..scale(_scale),
                          alignment: Alignment.center,
                          child: Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (context, error, stack) {
                              debugPrint('[WallpaperAdjust] Image load error: $error');
                              return Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image,
                                        color: CASIColors.textTertiary, size: 48),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Could not load image',
                                      style: TextStyle(
                                          color: CASIColors.textSecondary,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Reset button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _scale = 1.0;
                  _offset = Offset.zero;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: CASIColors.glassCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CASIColors.glassDivider),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt,
                        color: CASIColors.textSecondary, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Reset',
                      style: TextStyle(
                        color: CASIColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndReturn() async {
    setState(() => _saving = true);

    try {
      // Persistent storage directory (survives cache clears)
      final appDir = await getApplicationSupportDirectory();
      final wallpaperDir = Directory('${appDir.path}/wallpapers');
      if (!wallpaperDir.existsSync()) wallpaperDir.createSync(recursive: true);

      // If no adjustments were made, copy the original to persistent storage
      if (_scale == 1.0 && _offset == Offset.zero) {
        final ext = widget.imagePath.split('.').last;
        final destPath =
            '${wallpaperDir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(widget.imagePath).copy(destPath);
        if (mounted) Navigator.pop(context, destPath);
        return;
      }

      // Capture the adjusted image from the RepaintBoundary
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        // Fallback: copy original
        final ext = widget.imagePath.split('.').last;
        final destPath =
            '${wallpaperDir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(widget.imagePath).copy(destPath);
        if (mounted) Navigator.pop(context, destPath);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        final ext = widget.imagePath.split('.').last;
        final destPath =
            '${wallpaperDir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(widget.imagePath).copy(destPath);
        if (mounted) Navigator.pop(context, destPath);
        return;
      }

      final destPath =
          '${wallpaperDir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(destPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      if (mounted) Navigator.pop(context, destPath);
    } catch (e) {
      debugPrint('[WallpaperAdjust] Save error: $e');
      if (mounted) Navigator.pop(context, widget.imagePath);
    }
  }
}
