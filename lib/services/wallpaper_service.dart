import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:casi/design_system.dart';

/// Wallpaper source types.
enum WallpaperType { color, image, system }

/// Holds brightness analysis results — used only for OLED-black detection
/// now that the glass material is driven by the accent palette instead of
/// a brightness-based opacity multiplier.
class WallpaperBrightness {
  /// 0.0 = pure black, 1.0 = pure white
  final double luminance;

  const WallpaperBrightness({required this.luminance});

  bool get isDark => luminance < 0.4;
  bool get isLight => !isDark;

  static const dark = WallpaperBrightness(luminance: 0.1);
  static const medium = WallpaperBrightness(luminance: 0.5);
}

/// Service that manages wallpaper state, provides the wallpaper widget,
/// handles OLED optimization, and — on every wallpaper change — extracts
/// a single accent color from the wallpaper and pushes it to
/// [GlassPalette.accent] so every frosted surface re-tints to match.
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

    await _analyzeBrightness();
    await _extractAccent();

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
          await _extractAccent();
          notifyListeners();
        }
      }
    } on PlatformException {
      _hasSystemWallpaper = false;
    } on MissingPluginException {
      _hasSystemWallpaper = false;
    }
  }

  /// Analyze the brightness of the current wallpaper (OLED-black gating).
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
  Future<void> _analyzeImageBrightness(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 64,
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

      for (int i = 0; i < pixels.length; i += 16) {
        final r = pixels[i] / 255.0;
        final g = pixels[i + 1] / 255.0;
        final b = pixels[i + 2] / 255.0;
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

  /// Extract a single dominant color from the current wallpaper and push
  /// it to [GlassPalette]. Called once per wallpaper change — the palette
  /// notifier fans the result out to every [GlassSurface] in the tree.
  Future<void> _extractAccent() async {
    try {
      switch (_type) {
        case WallpaperType.color:
          // Solid-color wallpapers are their own accent.
          GlassPalette.update(_color);
        case WallpaperType.image:
          if (_imagePath != null && await File(_imagePath!).exists()) {
            final provider = FileImage(File(_imagePath!));
            await _extractFromProvider(provider);
          } else {
            GlassPalette.update(GlassPalette.fallbackAccent);
          }
        case WallpaperType.system:
          if (_systemWallpaperBytes != null) {
            await _extractFromProvider(MemoryImage(_systemWallpaperBytes!));
          } else {
            GlassPalette.update(GlassPalette.fallbackAccent);
          }
      }
    } catch (_) {
      GlassPalette.update(GlassPalette.fallbackAccent);
    }
  }

  Future<void> _extractFromProvider(ImageProvider provider) async {
    final palette = await PaletteGenerator.fromImageProvider(
      provider,
      size: const Size(100, 100),
      maximumColorCount: 8,
    );
    final picked = palette.lightMutedColor?.color ??
        palette.mutedColor?.color ??
        palette.lightVibrantColor?.color ??
        palette.dominantColor?.color;
    GlassPalette.update(picked ?? GlassPalette.fallbackAccent);
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
}

/// Internal stateless widget that renders the wallpaper layer.
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
