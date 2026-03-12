import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      backgroundColor: Colors.grey[900],
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
              Navigator.push(context, MaterialPageRoute(builder: (context) => const BackgroundSettingsPage()));
            },
          ),
          SwitchListTile(
            title: const Text("Immersive Mode", style: TextStyle(color: Colors.white)),
            subtitle: const Text("Hide status & navigation bars", style: TextStyle(color: Colors.white54, fontSize: 12)),
            secondary: const Icon(Icons.fullscreen, color: Colors.white),
            value: _immersiveMode,
            onChanged: _toggleImmersiveMode,
            activeThumbColor: Colors.blue,
          ),
          ListTile(
            title: const Text("Web Button Long Press", style: TextStyle(color: Colors.white)),
            leading: const Icon(Icons.touch_app, color: Colors.white),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const WebLongPressSettingsPage()));
            },
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

      final int colorValue = prefs.getInt('bg_color') ?? Colors.black.value;
      _backgroundColor = Color(colorValue);
      // Format hex string for display (remove alpha if it's 0xFF...)
      String hex = _backgroundColor.value.toRadixString(16).toUpperCase();
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
    await prefs.setInt('bg_color', _backgroundColor.value);
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
      backgroundColor: Colors.grey[900],
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
              color: Colors.white.withValues(alpha: 0.1),
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
                  activeColor: Colors.blue,
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
                  activeColor: Colors.blue,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Contextual Settings based on selection
          if (_backgroundType == 'color') ...[
            const Text("Hex Color", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _backgroundColor,
                    border: Border.all(color: Colors.white54),
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
                      prefixStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: '000000',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    onChanged: _updateColorFromHex,
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text("Selected Image", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
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
                            Icon(Icons.add_photo_alternate, color: Colors.white54, size: 40),
                            SizedBox(height: 8),
                            Text("Tap to pick image", style: TextStyle(color: Colors.white54)),
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
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    label: const Text("Change Image", style: TextStyle(color: Colors.blue)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class WebLongPressSettingsPage extends StatefulWidget {
  const WebLongPressSettingsPage({super.key});

  @override
  State<WebLongPressSettingsPage> createState() => _WebLongPressSettingsPageState();
}

class _WebLongPressSettingsPageState extends State<WebLongPressSettingsPage> {
  String _action = 'assistant';
  String? _customAppPackage;
  String? _customAppName;
  List<AppInfo> _installedApps = [];
  bool _loadingApps = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _action = prefs.getString('web_long_press_action') ?? 'assistant';
      _customAppPackage = prefs.getString('web_long_press_custom_app');
      _customAppName = prefs.getString('web_long_press_custom_app_name');
    });
  }

  Future<void> _saveAction(String action) async {
    setState(() {
      _action = action;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('web_long_press_action', action);
  }

  Future<void> _pickCustomApp() async {
    if (_installedApps.isEmpty && !_loadingApps) {
      setState(() => _loadingApps = true);
      final apps = await InstalledApps.getInstalledApps(excludeSystemApps: false, withIcon: true);
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _installedApps = apps;
          _loadingApps = false;
        });
      }
    }

    if (!mounted) return;

    final selected = await showDialog<AppInfo>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Choose App', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (_loadingApps)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                )
              else
                SizedBox(
                  height: 400,
                  child: ListView.builder(
                    itemCount: _installedApps.length,
                    itemBuilder: (context, index) {
                      final app = _installedApps[index];
                      final hasIcon = app.icon != null && app.icon!.isNotEmpty;
                      return ListTile(
                        leading: hasIcon
                            ? Image.memory(app.icon!, width: 36, height: 36, gaplessPlayback: true)
                            : const Icon(Icons.android, color: Colors.white),
                        title: Text(app.name, style: const TextStyle(color: Colors.white)),
                        onTap: () => Navigator.pop(context, app),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        _customAppPackage = selected.packageName;
        _customAppName = selected.name;
        _action = 'custom';
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_long_press_action', 'custom');
      await prefs.setString('web_long_press_custom_app', selected.packageName);
      await prefs.setString('web_long_press_custom_app_name', selected.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Web Button Long Press'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Long Press Action",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text("AI Assistant", style: TextStyle(color: Colors.white)),
                  subtitle: const Text("Opens Gemini, Google, Alexa, or Bixby", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: 'assistant',
                  groupValue: _action,
                  onChanged: (value) => _saveAction(value!),
                  activeColor: Colors.blue,
                ),
                RadioListTile<String>(
                  title: const Text("None", style: TextStyle(color: Colors.white)),
                  subtitle: const Text("Disable long press", style: TextStyle(color: Colors.white54, fontSize: 12)),
                  value: 'none',
                  groupValue: _action,
                  onChanged: (value) => _saveAction(value!),
                  activeColor: Colors.blue,
                ),
                RadioListTile<String>(
                  title: const Text("Custom App", style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _customAppName ?? "No app selected",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  value: 'custom',
                  groupValue: _action,
                  onChanged: (value) {
                    _saveAction(value!);
                    if (_customAppPackage == null) {
                      _pickCustomApp();
                    }
                  },
                  activeColor: Colors.blue,
                ),
              ],
            ),
          ),
          if (_action == 'custom') ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: _pickCustomApp,
                icon: const Icon(Icons.apps, color: Colors.blue),
                label: Text(
                  _customAppName != null ? "Change App" : "Pick App",
                  style: const TextStyle(color: Colors.blue),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
