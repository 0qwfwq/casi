import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wallpaper source types.
enum WallpaperType { color, image, system }

/// Holds brightness analysis results for adaptive glass opacity.
class WallpaperBrightness {
  /// 0.0 = pure black, 1.0 = pure white
  final double luminance;

  const WallpaperBrightness({required this.luminance});

  /// Whether the wallpaper is predominantly dark (luminance < 0.4).
  bool get isDark => luminance < 0.4;

  /// Whether the wallpaper is predominantly light (luminance >= 0.4).
  bool get isLight => !isDark;

  /// Glass tint multiplier — brighter wallpapers need more opaque glass
  /// for readability; darker wallpapers can use lighter tints.
  /// Range: 0.6 (very dark wallpaper) to 1.6 (very bright wallpaper).
  double get glassTintMultiplier {
    if (luminance < 0.15) return 0.6;  // OLED / near-black
    if (luminance < 0.3) return 0.8;   // Dark wallpaper
    if (luminance < 0.5) return 1.0;   // Medium
    if (luminance < 0.7) return 1.2;   // Light
    return 1.5;                         // Very bright
  }

  /// Border alpha multiplier — brighter wallpapers need stronger borders.
  double get glassBorderMultiplier {
    if (luminance < 0.2) return 0.7;
    if (luminance < 0.5) return 1.0;
    return 1.4;
  }

  static const dark = WallpaperBrightness(luminance: 0.1);
  static const medium = WallpaperBrightness(luminance: 0.5);
}

/// Service that manages wallpaper state, provides the wallpaper widget,
/// analyzes brightness for adaptive glass, and handles OLED optimization.
class WallpaperService extends ChangeNotifier {
  static const _channel = MethodChannel('casi.launcher/wallpaper');

  WallpaperType _type = WallpaperType.color;
  Color _color = Colors.black;
  String? _imagePath;
  Uint8List? _systemWallpaperBytes;
  WallpaperBrightness _brightness = WallpaperBrightness.dark;
  bool _hasSystemWallpaper = false;

  // Cached image provider for performance
  ImageProvider? _cachedImageProvider;
  String? _cachedImagePath;

  WallpaperType get type => _type;
  Color get color => _color;
  String? get imagePath => _imagePath;
  Uint8List? get systemWallpaperBytes => _systemWallpaperBytes;
  WallpaperBrightness get brightness => _brightness;
  bool get hasSystemWallpaper => _hasSystemWallpaper;

  /// Whether the current wallpaper is effectively black (OLED optimization).
  bool get isOLEDBlack {
    if (_type == WallpaperType.color) {
      return (_color.r * 255).round() < 10 &&
             (_color.g * 255).round() < 10 &&
             (_color.b * 255).round() < 10;
    }
    return _brightness.luminance < 0.05;
  }

  /// Load all settings from SharedPreferences and optionally fetch system wallpaper.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final bgType = prefs.getString('bg_type') ?? 'color';
    final colorValue = prefs.getInt('bg_color') ?? 0xFF000000;

    _color = Color(colorValue);
    _imagePath = prefs.getString('bg_image_path');

    switch (bgType) {
      case 'image':
        _type = _imagePath != null ? WallpaperType.image : WallpaperType.color;
      case 'system':
        _type = WallpaperType.system;
      default:
        _type = WallpaperType.color;
    }

    // Analyze brightness based on current wallpaper type
    await _analyzeBrightness();

    // Try fetching system wallpaper in the background
    _fetchSystemWallpaper();

    notifyListeners();
  }

  /// Reload settings (call after settings page changes).
  Future<void> reload() async {
    await initialize();
  }

  /// Fetch the system/live wallpaper from Android.
  Future<void> _fetchSystemWallpaper() async {
    try {
      final result = await _channel.invokeMethod('getSystemWallpaper');
      if (result != null && result is Uint8List && result.isNotEmpty) {
        _systemWallpaperBytes = result;
        _hasSystemWallpaper = true;

        if (_type == WallpaperType.system) {
          await _analyzeImageBrightness(result);
          notifyListeners();
        }
      }
    } on PlatformException {
      _hasSystemWallpaper = false;
    } on MissingPluginException {
      _hasSystemWallpaper = false;
    }
  }

  /// Analyze the brightness of the current wallpaper for adaptive glass.
  Future<void> _analyzeBrightness() async {
    switch (_type) {
      case WallpaperType.color:
        _brightness = WallpaperBrightness(
          luminance: _color.computeLuminance(),
        );
      case WallpaperType.image:
        if (_imagePath != null) {
          try {
            final file = File(_imagePath!);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              await _analyzeImageBrightness(bytes);
            }
          } catch (_) {
            _brightness = WallpaperBrightness.dark;
          }
        }
      case WallpaperType.system:
        if (_systemWallpaperBytes != null) {
          await _analyzeImageBrightness(_systemWallpaperBytes!);
        } else {
          _brightness = WallpaperBrightness.dark;
        }
    }
  }

  /// Sample an image's pixels to compute average luminance.
  /// Uses a small decoded image for performance.
  Future<void> _analyzeImageBrightness(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 64,  // Tiny sample for speed
        targetHeight: 64,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) {
        _brightness = WallpaperBrightness.dark;
        return;
      }

      final pixels = byteData.buffer.asUint8List();
      double totalLuminance = 0;
      int pixelCount = 0;

      // Sample every 4th pixel for speed
      for (int i = 0; i < pixels.length; i += 16) {
        final r = pixels[i] / 255.0;
        final g = pixels[i + 1] / 255.0;
        final b = pixels[i + 2] / 255.0;
        // Relative luminance (ITU-R BT.709)
        totalLuminance += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        pixelCount++;
      }

      final avgLuminance = pixelCount > 0 ? totalLuminance / pixelCount : 0.1;
      _brightness = WallpaperBrightness(luminance: avgLuminance);

      image.dispose();
      codec.dispose();
    } catch (_) {
      _brightness = WallpaperBrightness.dark;
    }
  }

  /// Get the cached image provider for the current wallpaper image.
  ImageProvider? getImageProvider() {
    if (_type == WallpaperType.image && _imagePath != null) {
      if (_cachedImagePath != _imagePath) {
        _cachedImageProvider = FileImage(File(_imagePath!));
        _cachedImagePath = _imagePath;
      }
      return _cachedImageProvider;
    }
    if (_type == WallpaperType.system && _systemWallpaperBytes != null) {
      return MemoryImage(_systemWallpaperBytes!);
    }
    return null;
  }

  /// Build the wallpaper background widget.
  /// Uses RepaintBoundary for performance — wallpaper rarely changes.
  Widget buildBackground() {
    return RepaintBoundary(
      child: _WallpaperLayer(
        type: _type,
        color: _color,
        imageProvider: getImageProvider(),
        isOLED: isOLEDBlack,
      ),
    );
  }

  /// Compute adaptive glass color based on wallpaper brightness.
  /// Returns white tint with adjusted alpha for the given elevation alpha.
  Color adaptiveGlassTint(double baseAlpha) {
    final adjusted = (baseAlpha * _brightness.glassTintMultiplier).clamp(0.0, 0.6);
    return Colors.white.withValues(alpha: adjusted);
  }

  /// Compute adaptive glass border color.
  Color adaptiveGlassBorder(double baseAlpha) {
    final adjusted = (baseAlpha * _brightness.glassBorderMultiplier).clamp(0.0, 0.5);
    return Colors.white.withValues(alpha: adjusted);
  }
}

/// Internal stateless widget that renders the wallpaper layer.
/// Wrapped in RepaintBoundary by the service for 60fps performance.
class _WallpaperLayer extends StatelessWidget {
  final WallpaperType type;
  final Color color;
  final ImageProvider? imageProvider;
  final bool isOLED;

  const _WallpaperLayer({
    required this.type,
    required this.color,
    this.imageProvider,
    this.isOLED = false,
  });

  @override
  Widget build(BuildContext context) {
    // OLED base: true black for power efficiency
    if (type == WallpaperType.color) {
      return SizedBox.expand(
        child: ColoredBox(color: color),
      );
    }

    if (imageProvider == null) {
      return SizedBox.expand(
        child: ColoredBox(
          color: type == WallpaperType.system 
              ? Colors.transparent 
              : (isOLED ? Colors.black : color),
        ),
      );
    }

    return SizedBox.expand(
      child: Image(
        image: imageProvider!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => ColoredBox(
          color: type == WallpaperType.system
              ? Colors.transparent
              : (isOLED ? Colors.black : const Color(0xFF0F1B2D)),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
