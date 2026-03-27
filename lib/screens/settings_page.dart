import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/design_system.dart';
import '../services/wallpaper_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _immersiveMode = false;
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
                            hintText: 'How should ARIA greet you?',
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

    if (image != null) {
      setState(() {
        _backgroundImagePath = image.path;
        _backgroundType = 'image';
      });
      _saveSettings();
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
