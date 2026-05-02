import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/design_system.dart';
import '../services/wallpaper_service.dart';
import '../services/foresight_user_rules.dart';
import '../services/foresight_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _immersiveMode = false;
  String _temperatureUnit = 'C'; // 'C' or 'F'
  bool _showForesight = true;
  bool _briefDismissedToday = false;
  String _foresightLongPressPackage = '';
  String _foresightLongPressLabel = 'Default Browser';
  bool _showClock = true;
  bool _showDate = true;
  bool _weatherWidgetActive = false;
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
    final today = DateTime.now().day;
    final longPressPkg = prefs.getString('foresight_longpress_package') ?? '';
    setState(() {
      _immersiveMode = prefs.getBool('immersive_mode') ?? false;
      _temperatureUnit = prefs.getString('temperature_unit') ?? 'C';
      _nameController.text = prefs.getString('user_name') ?? '';
      _showForesight = !(prefs.getBool('foresight_hidden') ?? false);
      _briefDismissedToday =
          (prefs.getInt('morning_brief_dismiss_day') ?? -1) == today;
      _foresightLongPressPackage = longPressPkg;
      _showClock = prefs.getBool('show_clock') ?? true;
      _showDate = prefs.getBool('show_date') ?? true;
      _weatherWidgetActive = prefs.getBool('weather_widget_active') ?? false;
    });
    // Resolve a human-readable label for the long-press target.
    if (longPressPkg.isNotEmpty) {
      try {
        final info = await InstalledApps.getAppInfo(longPressPkg);
        if (mounted && info != null) {
          setState(() => _foresightLongPressLabel = info.name);
        }
      } catch (_) {
        // Fall back to the raw package name if we can't resolve.
        if (mounted) {
          setState(() => _foresightLongPressLabel = longPressPkg);
        }
      }
    } else if (mounted) {
      setState(() => _foresightLongPressLabel = 'Default Browser');
    }
  }

  Future<void> _toggleForesight(bool value) async {
    setState(() => _showForesight = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('foresight_hidden', !value);
  }

  Future<void> _toggleShowClock(bool value) async {
    setState(() => _showClock = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_clock', value);
  }

  Future<void> _toggleShowDate(bool value) async {
    setState(() => _showDate = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_date', value);
  }

  Future<void> _toggleWeatherWidget(bool value) async {
    setState(() => _weatherWidgetActive = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('weather_widget_active', value);
  }

  /// "Show Brief again" — clears today's dismiss flag so the morning
  /// brief reappears once. The user can still dismiss it again; the
  /// next automatic re-show happens the following morning.
  Future<void> _showBriefAgain() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('morning_brief_dismiss_day');
    if (mounted) {
      setState(() => _briefDismissedToday = false);
    }
  }

  Future<void> _pickForesightLongPressApp() async {
    final selected = await showDialog<_AppPickResult>(
      context: context,
      builder: (_) => const _AppPickerDialog(),
    );
    if (selected == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'foresight_longpress_package', selected.packageName);
    setState(() {
      _foresightLongPressPackage = selected.packageName;
      _foresightLongPressLabel = selected.label;
    });
  }

  Future<void> _resetForesightLongPress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('foresight_longpress_package', '');
    setState(() {
      _foresightLongPressPackage = '';
      _foresightLongPressLabel = 'Default Browser';
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

  // ── Section header builder ────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: CASITypography.caption.copyWith(
          color: CASIColors.textTertiary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _sectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 0.5,
        color: CASIColors.glassDivider,
      ),
    );
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
                // ─── General ───────────────────────────────────────
                _sectionHeader('General'),
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
                const SizedBox(height: 4),
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
                // ─── Clock ─────────────────────────────────────────
                _sectionDivider(),
                _sectionHeader('Clock'),
                SwitchListTile(
                  title: const Text("Show Clock",
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      "Show the time digits at the top of the home screen",
                      style: TextStyle(
                          color: CASIColors.textSecondary, fontSize: 12)),
                  secondary: const Icon(Icons.schedule_outlined,
                      color: Colors.white),
                  value: _showClock,
                  onChanged: _toggleShowClock,
                  activeThumbColor: CASIColors.accentPrimary,
                ),
                SwitchListTile(
                  title: const Text("Show Date",
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      "Show the day and date above the clock",
                      style: TextStyle(
                          color: CASIColors.textSecondary, fontSize: 12)),
                  secondary: const Icon(Icons.calendar_today_outlined,
                      color: Colors.white),
                  value: _showDate,
                  onChanged: _toggleShowDate,
                  activeThumbColor: CASIColors.accentPrimary,
                ),

                // ─── Weather ───────────────────────────────────────
                _sectionDivider(),
                _sectionHeader('Weather'),
                SwitchListTile(
                  title: const Text("Show Weather",
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      "Show the weather forecast widget on the home screen",
                      style: TextStyle(
                          color: CASIColors.textSecondary, fontSize: 12)),
                  secondary: const Icon(Icons.cloud_outlined,
                      color: Colors.white),
                  value: _weatherWidgetActive,
                  onChanged: _toggleWeatherWidget,
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

                // ─── Foresight ─────────────────────────────────────
                _sectionDivider(),
                _sectionHeader('Foresight'),
                SwitchListTile(
                  title: const Text("Show Foresight",
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                      "Show predicted app suggestions above the dock",
                      style: TextStyle(
                          color: CASIColors.textSecondary, fontSize: 12)),
                  secondary: const Icon(Icons.auto_awesome_outlined,
                      color: Colors.white),
                  value: _showForesight,
                  onChanged: _toggleForesight,
                  activeThumbColor: CASIColors.accentPrimary,
                ),
                // Schedule rules
                ListTile(
                  leading: const Icon(Icons.schedule_outlined, color: Colors.white),
                  title: const Text("Schedule Rules",
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    "Pin apps by time and day of week",
                    style: TextStyle(color: CASIColors.textSecondary, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  onTap: () {
                    Navigator.push(context, PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const ForesightScheduleRulesPage(),
                      transitionDuration: const Duration(milliseconds: 80),
                      reverseTransitionDuration: const Duration(milliseconds: 60),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ));
                  },
                ),
                // Scenario rules
                ListTile(
                  leading: const Icon(Icons.device_hub_outlined, color: Colors.white),
                  title: const Text("Scenario Rules",
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    "Pin apps by Bluetooth, charging, Wi-Fi, and more",
                    style: TextStyle(color: CASIColors.textSecondary, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  onTap: () {
                    Navigator.push(context, PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const ForesightScenarioRulesPage(),
                      transitionDuration: const Duration(milliseconds: 80),
                      reverseTransitionDuration: const Duration(milliseconds: 60),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ));
                  },
                ),
                // Foresight long-press app picker
                ListTile(
                  title: const Text("Long-Press App",
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _foresightLongPressLabel,
                    style: const TextStyle(
                        color: CASIColors.textSecondary, fontSize: 12),
                  ),
                  leading: const Icon(Icons.touch_app_outlined,
                      color: Colors.white),
                  trailing: _foresightLongPressPackage.isEmpty
                      ? const Icon(Icons.arrow_forward_ios,
                          color: Colors.white, size: 16)
                      : IconButton(
                          icon: const Icon(Icons.close,
                              color: CASIColors.textSecondary, size: 18),
                          tooltip: 'Reset to Default Browser',
                          onPressed: _resetForesightLongPress,
                        ),
                  onTap: _pickForesightLongPressApp,
                ),

                // ─── Morning Brief ─────────────────────────────────
                _sectionDivider(),
                _sectionHeader('Morning Brief'),
                ListTile(
                  title: const Text("Show Brief Again",
                      style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _briefDismissedToday
                        ? "You dismissed today's Brief — tap to bring it back"
                        : "Brief is currently visible",
                    style: const TextStyle(
                        color: CASIColors.textSecondary, fontSize: 12),
                  ),
                  leading: const Icon(Icons.wb_sunny_outlined,
                      color: Colors.white),
                  trailing: const Icon(Icons.refresh,
                      color: Colors.white, size: 18),
                  enabled: _briefDismissedToday,
                  onTap: _briefDismissedToday ? _showBriefAgain : null,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── App Picker Dialog ──────────────────────────────────────────────────────
// Presents a searchable list of installed apps and returns the picked
// one. Used to choose which app is launched when the user long-presses
// the Foresight dock.

class _AppPickResult {
  final String packageName;
  final String label;

  const _AppPickResult({required this.packageName, required this.label});
}

class _AppPickerDialog extends StatefulWidget {
  const _AppPickerDialog();

  @override
  State<_AppPickerDialog> createState() => _AppPickerDialogState();
}

class _AppPickerDialogState extends State<_AppPickerDialog> {
  List<AppInfo> _apps = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: false,
      withIcon: false,
    );
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (mounted) {
      setState(() {
        _apps = apps;
        _loading = false;
      });
    }
  }

  List<AppInfo> get _filtered {
    if (_query.isEmpty) return _apps;
    final q = _query.toLowerCase();
    return _apps
        .where((a) =>
            a.name.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassSurface.modal(
        cornerRadius: CASIGlass.cornerStandard,
        width: 320,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: CASIColors.accentPrimary,
                    decoration: const InputDecoration(
                      hintText: 'Search apps',
                      hintStyle: TextStyle(color: CASIColors.textTertiary),
                      prefixIcon:
                          Icon(Icons.search, color: CASIColors.textSecondary),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Flexible(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final app = _filtered[i];
                            return ListTile(
                              title: Text(
                                app.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                app.packageName,
                                style: const TextStyle(
                                    color: CASIColors.textTertiary,
                                    fontSize: 11),
                              ),
                              onTap: () => Navigator.of(context).pop(
                                _AppPickResult(
                                  packageName: app.packageName,
                                  label: app.name,
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                GlassSurface.modal(
                  cornerRadius: 12,
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
                        child: GlassSurface.modal(
                          cornerRadius: 8,
                          child: TextField(
                            controller: _hexController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              prefixText: '# ',
                              prefixStyle: TextStyle(color: CASIColors.textSecondary),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              hintText: '000000',
                              hintStyle: TextStyle(color: CASIColors.textTertiary),
                            ),
                            onChanged: _updateColorFromHex,
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
                    child: _backgroundImagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_backgroundImagePath!),
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          )
                        : GlassSurface.modal(
                            cornerRadius: 12,
                            height: 200,
                            width: double.infinity,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_photo_alternate, color: CASIColors.textSecondary, size: 40),
                                  SizedBox(height: 8),
                                  Text("Tap to pick image", style: TextStyle(color: CASIColors.textSecondary)),
                                ],
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
                  GlassSurface.modal(
                    cornerRadius: 12,
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
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

// ---------------------------------------------------------------------------
// Foresight Schedule Rules Page
// ---------------------------------------------------------------------------

class ForesightScheduleRulesPage extends StatefulWidget {
  const ForesightScheduleRulesPage({super.key});

  @override
  State<ForesightScheduleRulesPage> createState() =>
      _ForesightScheduleRulesPageState();
}

class _ForesightScheduleRulesPageState
    extends State<ForesightScheduleRulesPage> {
  final WallpaperService _wallpaperService = WallpaperService();
  List<ForesightScheduleRule> _rules = [];

  @override
  void initState() {
    super.initState();
    _wallpaperService.initialize();
    _reload();
  }

  @override
  void dispose() {
    _wallpaperService.dispose();
    super.dispose();
  }

  void _reload() => setState(
      () => _rules = ForesightUserRulesService.instance.scheduleRules.toList());

  Future<void> _addRule() async {
    final pageCtx = context;

    String? packageName;
    String? appName;
    int startHour = 8;
    int endHour = 9;
    // Default Mon–Fri
    List<int> weekdays = [1, 2, 3, 4, 5];

    final saved = await showDialog<bool>(
      context: pageCtx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          backgroundColor: CASIColors.void_,
          title: const Text('Add Schedule Rule',
              style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App picker
                const Text('App',
                    style: TextStyle(
                        color: CASIColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDialog<_AppPickResult>(
                      context: pageCtx,
                      builder: (_) => const _AppPickerDialog(),
                    );
                    if (picked != null) {
                      setS(() {
                        packageName = picked.packageName;
                        appName = picked.label;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            appName ?? 'Tap to choose an app',
                            style: TextStyle(
                              color: appName != null
                                  ? Colors.white
                                  : CASIColors.textTertiary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: CASIColors.textTertiary, size: 18),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Time window
                const Text('Time Window',
                    style: TextStyle(
                        color: CASIColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('From',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: startHour,
                      dropdownColor: CASIColors.void_,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      items: [
                        for (int h = 0; h < 24; h++)
                          DropdownMenuItem(
                              value: h, child: Text(fmtHour(h)))
                      ],
                      onChanged: (v) {
                        if (v != null) setS(() => startHour = v);
                      },
                    ),
                    const SizedBox(width: 12),
                    const Text('to',
                        style: TextStyle(color: Colors.white, fontSize: 13)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: endHour,
                      dropdownColor: CASIColors.void_,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                      items: [
                        for (int h = 0; h < 24; h++)
                          DropdownMenuItem(
                              value: h, child: Text(fmtHour(h)))
                      ],
                      onChanged: (v) {
                        if (v != null) setS(() => endHour = v);
                      },
                    ),
                  ],
                ),
                if (startHour == endHour)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Start and end cannot be the same hour.',
                      style: TextStyle(
                          color: Colors.redAccent, fontSize: 11),
                    ),
                  ),

                const SizedBox(height: 18),

                // Day selector
                const Text('Days',
                    style: TextStyle(
                        color: CASIColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (int d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(dayAbbr(d),
                            style: const TextStyle(fontSize: 12)),
                        selected: weekdays.contains(d),
                        onSelected: (on) => setS(() {
                          if (on) {
                            weekdays.add(d);
                          } else {
                            weekdays.remove(d);
                          }
                          weekdays.sort();
                        }),
                        selectedColor:
                            CASIColors.accentPrimary.withValues(alpha: 0.35),
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: weekdays.contains(d)
                              ? Colors.white
                              : CASIColors.textSecondary,
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                      ),
                  ],
                ),
                if (weekdays.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Empty = every day',
                        style: TextStyle(
                            color: CASIColors.textTertiary, fontSize: 11)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel',
                  style: TextStyle(color: CASIColors.textSecondary)),
            ),
            TextButton(
              onPressed: (packageName == null || startHour == endHour)
                  ? null
                  : () => Navigator.pop(dlgCtx, true),
              child: const Text('Save',
                  style: TextStyle(color: CASIColors.accentPrimary)),
            ),
          ],
        ),
      ),
    );

    if (saved == true && packageName != null) {
      final rule = ForesightScheduleRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        packageName: packageName!,
        appName: appName!,
        startHour: startHour,
        endHour: endHour,
        weekdays: weekdays,
      );
      await ForesightUserRulesService.instance.addScheduleRule(rule);
      ForesightService.instance.invalidateCache();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Schedule Rules'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addRule),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _wallpaperService.buildBackground()),
          Positioned.fill(
              child:
                  ColoredBox(color: Colors.black.withValues(alpha: 0.3))),
          SafeArea(
            child: _rules.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_outlined,
                              color: CASIColors.textTertiary, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'No schedule rules yet.\n'
                            'Tap + to pin an app at a specific time and day.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: CASIColors.textSecondary,
                                height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Example: show Gmail from 6–8 AM on Mon, Tue, Fri.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: CASIColors.textTertiary,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    itemCount: _rules.length,
                    itemBuilder: (_, i) {
                      final r = _rules[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              CASIColors.accentPrimary.withValues(alpha: 0.2),
                          child: Text(
                            r.appName.isNotEmpty
                                ? r.appName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        title: Text(r.appName,
                            style:
                                const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '${r.timeRangeLabel} · ${r.daysLabel}',
                          style: const TextStyle(
                              color: CASIColors.textSecondary,
                              fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: CASIColors.textTertiary, size: 20),
                          onPressed: () async {
                            await ForesightUserRulesService.instance
                                .removeScheduleRule(r.id);
                            ForesightService.instance.invalidateCache();
                            _reload();
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
// Foresight Scenario Rules Page
// ---------------------------------------------------------------------------

class ForesightScenarioRulesPage extends StatefulWidget {
  const ForesightScenarioRulesPage({super.key});

  @override
  State<ForesightScenarioRulesPage> createState() =>
      _ForesightScenarioRulesPageState();
}

class _ForesightScenarioRulesPageState
    extends State<ForesightScenarioRulesPage> {
  final WallpaperService _wallpaperService = WallpaperService();
  List<ForesightScenarioRule> _rules = [];

  @override
  void initState() {
    super.initState();
    _wallpaperService.initialize();
    _reload();
  }

  @override
  void dispose() {
    _wallpaperService.dispose();
    super.dispose();
  }

  void _reload() => setState(
      () => _rules = ForesightUserRulesService.instance.scenarioRules.toList());

  Future<void> _addRule() async {
    final pageCtx = context;

    String? packageName;
    String? appName;
    ScenarioTrigger trigger = ScenarioTrigger.anyBluetooth;
    String ssidFilter = '';

    final saved = await showDialog<bool>(
      context: pageCtx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (_, setS) => AlertDialog(
          backgroundColor: CASIColors.void_,
          title: const Text('Add Scenario Rule',
              style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // App picker
                const Text('App',
                    style: TextStyle(
                        color: CASIColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDialog<_AppPickResult>(
                      context: pageCtx,
                      builder: (_) => const _AppPickerDialog(),
                    );
                    if (picked != null) {
                      setS(() {
                        packageName = picked.packageName;
                        appName = picked.label;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            appName ?? 'Tap to choose an app',
                            style: TextStyle(
                              color: appName != null
                                  ? Colors.white
                                  : CASIColors.textTertiary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: CASIColors.textTertiary, size: 18),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Trigger
                const Text('When this happens',
                    style: TextStyle(
                        color: CASIColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButton<ScenarioTrigger>(
                  value: trigger,
                  isExpanded: true,
                  dropdownColor: CASIColors.void_,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13),
                  items: ScenarioTrigger.values
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.label),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setS(() => trigger = v);
                  },
                ),

                // Wi-Fi filter (only for specificWifi)
                if (trigger == ScenarioTrigger.specificWifi) ...[
                  const SizedBox(height: 14),
                  const Text('Wi-Fi name contains',
                      style: TextStyle(
                          color: CASIColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Home, Tesla Model 3, Office',
                      hintStyle:
                          TextStyle(color: CASIColors.textTertiary),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: CASIColors.textTertiary)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: CASIColors.accentPrimary)),
                    ),
                    onChanged: (v) => ssidFilter = v,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: const Text('Cancel',
                  style: TextStyle(color: CASIColors.textSecondary)),
            ),
            TextButton(
              onPressed: packageName == null
                  ? null
                  : () => Navigator.pop(dlgCtx, true),
              child: const Text('Save',
                  style: TextStyle(color: CASIColors.accentPrimary)),
            ),
          ],
        ),
      ),
    );

    if (saved == true && packageName != null) {
      final rule = ForesightScenarioRule(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        packageName: packageName!,
        appName: appName!,
        trigger: trigger,
        ssidFilter: (trigger == ScenarioTrigger.specificWifi &&
                ssidFilter.trim().isNotEmpty)
            ? ssidFilter.trim()
            : null,
      );
      await ForesightUserRulesService.instance.addScenarioRule(rule);
      ForesightService.instance.invalidateCache();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Scenario Rules'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _addRule),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: _wallpaperService.buildBackground()),
          Positioned.fill(
              child:
                  ColoredBox(color: Colors.black.withValues(alpha: 0.3))),
          SafeArea(
            child: _rules.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.device_hub_outlined,
                              color: CASIColors.textTertiary, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            'No scenario rules yet.\n'
                            'Tap + to pin an app for a specific situation.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: CASIColors.textSecondary,
                                height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Examples: show Maps when connected to your car, '
                            'or Spotify when headphones are plugged in.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: CASIColors.textTertiary,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    itemCount: _rules.length,
                    itemBuilder: (_, i) {
                      final r = _rules[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              CASIColors.accentPrimary.withValues(alpha: 0.2),
                          child: Text(
                            r.appName.isNotEmpty
                                ? r.appName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        title: Text(r.appName,
                            style:
                                const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          r.ssidFilter != null
                              ? '${r.triggerLabel} · "${r.ssidFilter}"'
                              : r.triggerLabel,
                          style: const TextStyle(
                              color: CASIColors.textSecondary,
                              fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: CASIColors.textTertiary, size: 20),
                          onPressed: () async {
                            await ForesightUserRulesService.instance
                                .removeScenarioRule(r.id);
                            ForesightService.instance.invalidateCache();
                            _reload();
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
