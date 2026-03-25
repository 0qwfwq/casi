import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/design_system.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _immersiveMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _immersiveMode = prefs.getBool('immersive_mode') ?? false;
    });
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
      backgroundColor: CASIColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        children: [
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
    );
  }
}

class BackgroundSettingsPage extends StatefulWidget {
  const BackgroundSettingsPage({super.key});

  @override
  State<BackgroundSettingsPage> createState() => _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState extends State<BackgroundSettingsPage> {
  // 'color' or 'image'
  String _backgroundType = 'color';
  // Default to black
  Color _backgroundColor = Colors.black;
  String? _backgroundImagePath;

  final TextEditingController _hexController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backgroundType = prefs.getString('bg_type') ?? 'color';

      final int colorValue = prefs.getInt('bg_color') ?? 0xFF000000;
      _backgroundColor = Color(colorValue);
      // Format hex string for display (remove alpha if it's 0xFF...)
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
      hex = 'FF$hex'; // Add full opacity if only RGB provided
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
      backgroundColor: CASIColors.bgPrimary,
      appBar: AppBar(
        title: const Text('Background Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Background",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Background Type Selector
          Container(
            decoration: BoxDecoration(
              color: CASIColors.glassCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text("Solid Color", style: TextStyle(color: Colors.white)),
                  value: 'color',
                  groupValue: _backgroundType,
                  onChanged: (value) {
                    setState(() {
                      _backgroundType = value!;
                    });
                    _saveSettings();
                  },
                  activeColor: CASIColors.accentPrimary,
                ),
                RadioListTile<String>(
                  title: const Text("Image", style: TextStyle(color: Colors.white)),
                  value: 'image',
                  groupValue: _backgroundType,
                  onChanged: (value) {
                    setState(() {
                      _backgroundType = value!;
                    });
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
                  child: TextField(
                    controller: _hexController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      prefixText: '# ',
                      prefixStyle: const TextStyle(color: CASIColors.textSecondary),
                      filled: true,
                      fillColor: CASIColors.glassCard,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: '000000',
                      hintStyle: TextStyle(color: CASIColors.textTertiary),
                    ),
                    onChanged: _updateColorFromHex,
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text("Selected Image", style: TextStyle(color: CASIColors.textSecondary)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: CASIColors.glassCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: CASIColors.glassDivider),
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
          ],
        ],
      ),
    );
  }
}
