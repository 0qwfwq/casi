import 'dart:math' show min;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

// =============================================================================
// CASI Design System — Flutter Implementation
// Translated from the CASI Design System v1.0 Living Document
// =============================================================================
//
// THIRD-PARTY ATTRIBUTION
// -----------------------------------------------------------------------------
// CASI's liquid-glass material is built on top of the [liquid_glass_easy]
// package by Ahmed Gamil, used under the MIT License:
//
//   MIT License
//   Copyright (c) 2025 Ahmed Gamil
//
//   Permission is hereby granted, free of charge, to any person obtaining a
//   copy of this software and associated documentation files (the "Software"),
//   to deal in the Software without restriction, including without limitation
//   the rights to use, copy, modify, merge, publish, distribute, sublicense,
//   and/or sell copies of the Software, and to permit persons to whom the
//   Software is furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in
//   all copies or substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//   DEALINGS IN THE SOFTWARE.
//
// The full LICENSE file ships inside the package (`pub.dev/packages/
// liquid_glass_easy`) and is automatically picked up by Flutter's
// [LicenseRegistry], so it is also surfaced to end-users through the
// standard `showLicensePage` flow whenever CASI exposes one.
// =============================================================================
//
// Material direction (in progress):
//   The frosted-glass material is being replaced with a true *liquid glass*
//   material driven by the [liquid_glass_easy] package — real refraction,
//   distortion, and chromatic aberration over a captured background, instead
//   of a flat blur. New surfaces are built with [LiquidGlassSurface] and the
//   tokens in [CASILiquidGlass]. Older surfaces still use [GlassSurface] /
//   [BackdropFilter]; they are migrated one feature at a time. The Weather
//   widget is the first surface on the new material — every other glass
//   surface in the app (dock, drawer, foresight pills, modals, etc.) will
//   follow.
//
//   When adding NEW glass UI: use [LiquidGlassSurface]. Pick a [GlassRole]
//   so the per-surface tint opacity stays consistent with the rest of the
//   app, and pass the wallpaper widget so the lens has something to refract.
//   Do not reach into the [liquid_glass_easy] APIs directly from feature
//   code — every liquid-glass surface in CASI flows through this file so a
//   single change here re-tunes the whole app.

// ─── 2. Color System ─────────────────────────────────────────────────────────

/// Primary Palette
class CASIColors {
  CASIColors._();

  // 2.1 Primary Palette
  static const Color void_ = Color(0xFF0F1B2D);        // Primary background
  static const Color deepVoid = Color(0xFF0A1220);      // Deepest background layer
  static const Color pulseBlue = Color(0xFF4F8EF7);     // Primary accent / interactive
  static const Color pulsePurple = Color(0xFF7C5CF7);   // Secondary accent / AI surfaces
  static const Color glassWhite = Color(0xFFFFFFFF);    // Text on dark / frosted base

  // 2.2 Semantic Palette
  static const Color confirm = Color(0xFF4FD17A);       // Success states / positive AI
  static const Color caution = Color(0xFFF7874F);       // Warnings / important notices
  static const Color alert = Color(0xFFF75F5F);         // Errors / destructive actions
  static const Color teal = Color(0xFF3DD6C8);          // Informational / secondary AI

  // 2.4 Color Roles
  static const Color bgPrimary = void_;
  static const Color bgDeep = deepVoid;
  static const Color accentPrimary = pulseBlue;
  static const Color accentSecondary = pulsePurple;
  static const Color accentTertiary = teal;

  // Text colors (always on dark)
  static const Color textPrimary = Color(0xFFFFFFFF);           // 100% white
  static const Color textSecondary = Color(0xB3FFFFFF);         // 70% white
  static const Color textTertiary = Color(0x66FFFFFF);          // 40% white

  // Flat (non-glass) surface overlays — white with alpha. Use these for
  // small decorative containers that sit on top of a glass surface (album
  // art placeholders, section dividers, etc.). For frosted glass itself
  // always use [GlassSurface].
  static const Color glassCard = Color(0x1FFFFFFF);             // 12% white
  static const Color glassElevated = Color(0x2EFFFFFF);         // 18% white
  static const Color glassDivider = Color(0x0DFFFFFF);          // 5% white
  static const Color glassHover = Color(0x08FFFFFF);            // 3% white
  static const Color glassLight = Color(0x14FFFFFF);            // 8% white

  // Semantic (full opacity for icons/indicators)
  static const Color success = confirm;
  static const Color warn = caution;
  static const Color error = alert;
}

// ─── 3. Typography ───────────────────────────────────────────────────────────

/// CASI uses Inter as its sole typeface.
/// For Flutter, we reference 'Inter' font family (must be bundled or via google_fonts).
class CASITypography {
  CASITypography._();

  static const String fontFamily = 'Inter';
  static const String codeFontFamily = 'JetBrains Mono';

  // type.display — 34sp Bold, line height 40sp
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 40 / 34,
    letterSpacing: -0.5,
    color: CASIColors.textPrimary,
  );

  // type.headline1 — 28sp Bold, line height 34sp
  static const TextStyle headline1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 34 / 28,
    letterSpacing: -0.25,
    color: CASIColors.textPrimary,
  );

  // type.headline2 — 22sp SemiBold, line height 28sp
  static const TextStyle headline2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 28 / 22,
    letterSpacing: 0,
    color: CASIColors.textPrimary,
  );

  // type.headline3 — 18sp SemiBold, line height 24sp
  static const TextStyle headline3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 24 / 18,
    letterSpacing: 0,
    color: CASIColors.textPrimary,
  );

  // type.body1 — 16sp Regular, line height 24sp
  static const TextStyle body1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    letterSpacing: 0.15,
    color: CASIColors.textPrimary,
  );

  // type.body2 — 14sp Regular, line height 20sp
  static const TextStyle body2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: 0.15,
    color: CASIColors.textPrimary,
  );

  // type.caption — 12sp Regular, line height 16sp
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    letterSpacing: 0.4,
    color: CASIColors.textPrimary,
  );

  // type.code — 13sp Regular, line height 20sp (JetBrains Mono)
  static const TextStyle code = TextStyle(
    fontFamily: codeFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 20 / 13,
    color: CASIColors.textPrimary,
  );

  // App name label in drawer — type.body1 SemiBold (per design system 4.4)
  static const TextStyle appLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 24 / 16,
    letterSpacing: 0.15,
    color: CASIColors.textPrimary,
  );
}

// ─── 4. Spacing & Layout Grid ────────────────────────────────────────────────

/// 8dp base grid. 4dp is the smallest allowed unit.
class CASISpacing {
  CASISpacing._();

  static const double xs = 4;    // Minimum internal padding
  static const double sm = 8;    // Internal card padding
  static const double md = 16;   // Standard component padding
  static const double lg = 24;   // Section spacing
  static const double xl = 32;   // Large section gaps
  static const double xxl = 48;  // Between major screen sections
  static const double hero = 64; // Top-of-screen hero spacing

  // Layout grid
  static const double marginHorizontal = 16; // Screen edge margin
  static const double gutterWidth = 16;      // Column gutters
  static const double minTouchTarget = 48;   // Minimum 48dp touch target
}

// ─── 5. Flat-overlay opacity tokens ──────────────────────────────────────────
//
// These are NOT glass — they're for small decorative containers that sit on
// top of an existing glass surface (e.g. album art placeholders, section
// dividers). Frosted glass goes through [GlassSurface].
enum CASIElevation {
  ground(bgAlpha: 0.0, borderAlpha: 0.0),
  base(bgAlpha: 0.05, borderAlpha: 0.0),
  card(bgAlpha: 0.12, borderAlpha: 0.06),
  raised(bgAlpha: 0.18, borderAlpha: 0.12),
  float_(bgAlpha: 0.24, borderAlpha: 0.20),
  peak(bgAlpha: 0.30, borderAlpha: 0.25);

  final double bgAlpha;
  final double borderAlpha;
  const CASIElevation({required this.bgAlpha, required this.borderAlpha});
}

// ─── 6. The visionOS Glass System ────────────────────────────────────────────
//
// One material, applied consistently across every frosted surface in the
// app. The only thing that varies per surface is the tint opacity (see
// [GlassRole]) and the corner radius — blur, border, shadow, and accent
// behavior are identical everywhere.
//
// Spec:
//   blur:    sigmaX = sigmaY = 22 (visionOS range 20–24)
//   border:  0.5 px, white @ 8% opacity — nearly invisible
//   tint:    mostly white, faintly biased toward the wallpaper accent
//            (see [GlassPalette]) at [accentMix]
//   shadow:  none
//
class CASIGlass {
  CASIGlass._();

  /// visionOS blur sigma — the single blur value used by every glass surface.
  static const double blur = 22;

  /// Hairline border thickness.
  static const double borderWidth = 0.5;

  /// Border tint (white @ 8% opacity).
  static const double borderAlpha = 0.08;

  /// How much of the wallpaper accent bleeds into the otherwise-white tint.
  /// 0.0 = pure white, 1.0 = pure accent. Spec calls for a "nearly white or
  /// very faint sky-blue" look, so this stays low.
  static const double accentMix = 0.15;

  // ── Corner radii (shape only — the material itself is uniform) ──────────
  static const double cornerStandard = 16; // Standard cards
  static const double cornerChip = 8;      // Small chips/tags
  static const double cornerPill = 50;     // Pill shape (search bar)
  static const double cornerSheet = 24;    // Bottom sheets (top corners)
  static const double cornerModal = 24;    // Modals
}

/// Per-surface tint opacity. This is the only knob that varies between
/// glass surfaces — everything else (blur, border, accent) is fixed.
///
/// Values come directly from the product spec:
///   dock       — home dock row
///   drawer     — app drawer background
///   foresight  — Foresight dock + notification stack
///   pill       — notification/status pills
///   modal      — context menus, dialogs, bottom sheets, media cards
enum GlassRole {
  dock(0.12),
  drawer(0.18),
  foresight(0.15),
  pill(0.10),
  modal(0.15);

  final double opacity;
  const GlassRole(this.opacity);
}

/// Holds the single live accent color used by every glass surface.
///
/// Updated once per wallpaper change by [WallpaperService] (via its palette
/// extraction pass). [GlassSurface] listens to [accent] directly, so a new
/// wallpaper re-tints the whole UI without any plumbing through widget trees.
class GlassPalette {
  GlassPalette._();

  /// Faint sky-blue fallback — used before the first extraction completes,
  /// and whenever extraction fails or produces an unusably low-saturation
  /// color.
  static const Color fallbackAccent = Color(0xFFCFE4FF);

  /// The live wallpaper accent. Always a visible color — never transparent.
  static final ValueNotifier<Color> accent =
      ValueNotifier<Color>(fallbackAccent);

  /// Replace the current accent with [color]. Falls back to [fallbackAccent]
  /// when [color] is too desaturated or too dark to read well against white.
  static void update(Color color) {
    final hsl = HSLColor.fromColor(color);
    // Guard against wallpapers that produce muddy / near-grey accents —
    // those read worse than the fallback.
    if (hsl.saturation < 0.08 || hsl.lightness < 0.15) {
      accent.value = fallbackAccent;
      return;
    }
    // Normalize the accent to a consistently light pastel so the tint
    // stays subtle no matter how saturated the wallpaper is.
    accent.value = hsl
        .withSaturation((hsl.saturation * 0.6).clamp(0.15, 0.7))
        .withLightness(0.82)
        .toColor();
  }
}

// ─── 6c. Liquid Glass System ────────────────────────────────────────────────
//
// True-physics glass material, powered by [liquid_glass_easy]. Where the
// older [CASIGlass]/[GlassSurface] system uses a flat [BackdropFilter] blur
// + tint, this one captures the wallpaper as a texture and refracts it
// through a shader-driven lens with optional distortion, magnification,
// chromatic aberration, and edge blur.
//
// Every liquid-glass surface in CASI is built on top of [LiquidGlassSurface]
// using these tokens so the whole app reads as one consistent material.
// Tweaking [distortion], [distortionWidth], or any token here re-tunes the
// look of every liquid-glass surface project-wide.
//
// Token spec:
//   distortion             — 0.47  (strong shape-refraction bend along edges)
//   distortionWidth        — 62    (edge band width matching the package demo)
//   magnification          — 1.00  (no zoom — flat glass, wallpaper behind)
//   chromaticAberration    — 0.003 (whisper of color fringing on the edge)
//   edgeBlurSigma          — 0.0   (perfectly clear glass — no frosted blur)
//   pixelRatio             — 0.8   (capture resolution; perf vs. detail trade-off)
//   realTimeCapture        — true  (live wallpaper / video refracts in real time)
class CASILiquidGlass {
  CASILiquidGlass._();

  /// How much the lens warps the captured background near its edges.
  /// 0 = no bend (clear glass), 0.47 = strong physically-accurate refraction.
  static const double distortion = 0.47;

  /// Width (in px) of the edge band that carries the distortion, matching
  /// the package README demo value (62 px).
  static const double distortionWidth = 62;

  /// Optical zoom through the lens. Glass is intentionally flat — the
  /// wallpaper should feel right *behind* the card, not magnified.
  static const double magnification = 1.0;

  /// Color-fringing intensity at the lens edge. Package default is 0.003.
  static const double chromaticAberration = 0.003;

  /// Sigma for edge blur on top of refraction. 0 = perfectly clear glass
  /// (no frosted softening — the refraction alone carries the material).
  static const double edgeBlurSigma = 0.0;

  /// Capture pixel ratio for [LiquidGlassView]. 1.0 captures at full device
  /// resolution, eliminating the pixelation visible through the lens.
  static const double pixelRatio = 1.0;

  /// Hairline border thickness applied on top of the lens — kept for
  /// continuity with [CASIGlass.borderWidth] so liquid-glass and frosted-
  /// glass surfaces have the same edge treatment during the migration.
  static const double borderWidth = CASIGlass.borderWidth;

  /// Border alpha — same value as the frosted system.
  static const double borderAlpha = CASIGlass.borderAlpha;

  /// Wallpaper-accent bleed into the white tint. Same as the frosted
  /// system so a partially-migrated screen reads as one material.
  static const double accentMix = CASIGlass.accentMix;

  // ── Corner radii — shared with [CASIGlass]. ─────────────────────────────
  static const double cornerStandard = CASIGlass.cornerStandard;
  static const double cornerChip = CASIGlass.cornerChip;
  static const double cornerPill = CASIGlass.cornerPill;
  static const double cornerSheet = CASIGlass.cornerSheet;
  static const double cornerModal = CASIGlass.cornerModal;
}

/// Liquid-glass version of [GlassSurface]. Wraps [child] in a
/// [LiquidGlassView] and places a single [LiquidGlass] lens behind it,
/// sized to whatever the child lays out as. The lens reads pixels from
/// [backgroundWidget] (almost always the wallpaper) and refracts them
/// through the CASI tokens in [CASILiquidGlass].
///
/// Usage:
///   LiquidGlassSurface.modal(
///     backgroundWidget: wallpaperService.buildBackground(),
///     child: ...,
///   );
///
/// Per-surface knob is the tint *opacity* via [GlassRole] — every other
/// parameter (distortion, magnification, blur, border, accent mix) is
/// fixed by [CASILiquidGlass] so the whole app stays on one material.
///
/// Layout model:
///   The widget renders [child] at its natural size (Stack-driven), and
///   places the lens behind it via [Positioned.fill]. This means the
///   surface participates in normal column/row layout — no manual width
///   or height needed in the typical case.
///
/// Background alignment:
///   [backgroundWidget] is the source the lens refracts. The package
///   sizes the background to the [LiquidGlassView]'s own bounds, which
///   would squish a full-screen wallpaper into the card. To keep the
///   refraction visually aligned with what's behind the card on screen,
///   this widget tracks its screen-space offset and renders the
///   wallpaper at the screen's full size *inside* the view, translated
///   by [-screenOffset]. The slice the lens captures matches the slice
///   of wallpaper actually behind the card.
class LiquidGlassSurface extends StatefulWidget {
  /// Child placed in front of the lens. Drives the surface's intrinsic
  /// size — the lens fills whatever the child lays out as.
  final Widget child;

  /// What the lens refracts. In CASI this is the wallpaper widget from
  /// [WallpaperService.buildBackground]. The package captures this into
  /// a texture; it is not directly composited.
  final Widget backgroundWidget;

  /// Tint opacity. Use [GlassRole] values where possible; this parameter
  /// lets ad-hoc surfaces opt into a specific spec opacity without
  /// inventing a role.
  final double opacity;

  /// Corner radius. Shape is NOT part of the material (dock is pill,
  /// drawer is rounded-top sheet, cards are 16, etc.), so each call site
  /// picks the right radius for its context.
  final double cornerRadius;

  /// Padding inside the surface, applied to [child].
  final EdgeInsetsGeometry? padding;

  /// Margin outside the surface.
  final EdgeInsetsGeometry? margin;

  /// Optional fixed width.
  final double? width;

  /// Optional fixed height.
  final double? height;

  /// Replaces the standard tint color (e.g. for hover or active states
  /// that need a semantic color through the glass).
  final Color? tintOverride;

  /// Replaces the standard border color.
  final Color? borderOverride;

  /// Override for the lens's distortion intensity. Defaults to
  /// [CASILiquidGlass.distortion]; raise it for hero surfaces that want a
  /// stronger refraction read.
  final double? distortionOverride;

  const LiquidGlassSurface({
    super.key,
    required this.child,
    required this.backgroundWidget,
    this.opacity = 0.12,
    this.cornerRadius = CASILiquidGlass.cornerStandard,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.tintOverride,
    this.borderOverride,
    this.distortionOverride,
  });

  // ── Role factories — mirror the [GlassSurface] roles 1:1. ───────────────

  factory LiquidGlassSurface.dock({
    Key? key,
    required Widget child,
    required Widget backgroundWidget,
    double cornerRadius = CASILiquidGlass.cornerStandard,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      LiquidGlassSurface(
        key: key,
        backgroundWidget: backgroundWidget,
        opacity: GlassRole.dock.opacity,
        cornerRadius: cornerRadius,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory LiquidGlassSurface.drawer({
    Key? key,
    required Widget child,
    required Widget backgroundWidget,
    double cornerRadius = CASILiquidGlass.cornerSheet,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      LiquidGlassSurface(
        key: key,
        backgroundWidget: backgroundWidget,
        opacity: GlassRole.drawer.opacity,
        cornerRadius: cornerRadius,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory LiquidGlassSurface.foresight({
    Key? key,
    required Widget child,
    required Widget backgroundWidget,
    double cornerRadius = CASILiquidGlass.cornerPill,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      LiquidGlassSurface(
        key: key,
        backgroundWidget: backgroundWidget,
        opacity: GlassRole.foresight.opacity,
        cornerRadius: cornerRadius,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory LiquidGlassSurface.pill({
    Key? key,
    required Widget child,
    required Widget backgroundWidget,
    double cornerRadius = CASILiquidGlass.cornerPill,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      LiquidGlassSurface(
        key: key,
        backgroundWidget: backgroundWidget,
        opacity: GlassRole.pill.opacity,
        cornerRadius: cornerRadius,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory LiquidGlassSurface.modal({
    Key? key,
    required Widget child,
    required Widget backgroundWidget,
    double cornerRadius = CASILiquidGlass.cornerModal,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      LiquidGlassSurface(
        key: key,
        backgroundWidget: backgroundWidget,
        opacity: GlassRole.modal.opacity,
        cornerRadius: cornerRadius,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  /// Top-left of the surface in screen coordinates. Used to translate the
  /// wallpaper inside the [LiquidGlassView] so the slice that sits behind
  /// the surface visually aligns with the slice the lens captures. Updated
  /// after every frame; only triggers a rebuild when it actually changes.
  Offset _screenOffset = Offset.zero;

  /// Surface size in logical pixels. Tracked alongside [_screenOffset] so
  /// the lens dimensions stay in sync with the rendered Stack.
  Size _surfaceSize = Size.zero;

  final GlobalKey _surfaceKey = GlobalKey();

  void _syncScreenGeometry() {
    final ctx = _surfaceKey.currentContext;
    if (ctx == null) return;
    final RenderObject? ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return;
    final Offset offset = ro.localToGlobal(Offset.zero);
    final Size size = ro.size;
    if (offset != _screenOffset || size != _surfaceSize) {
      setState(() {
        _screenOffset = offset;
        _surfaceSize = size;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncScreenGeometry();
    });

    final MediaQueryData mq = MediaQuery.of(context);
    final Size screenSize = mq.size;

    // Pure liquid glass: no white tint by default. The refraction and
    // distortion ARE the material — adding a white overlay on top would
    // fight the physics effect. tintOverride is still honoured for
    // semantic states (e.g. red alarm tint, pause-blue swipe tint).
    final Color tint = widget.tintOverride ?? Colors.transparent;
    final Color border = widget.borderOverride ??
        Colors.white.withValues(alpha: CASILiquidGlass.borderAlpha);

    final BorderRadius radius = BorderRadius.circular(widget.cornerRadius);

    Widget surface = Stack(
      key: _surfaceKey,
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: radius,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double w = constraints.maxWidth;
                final double h = constraints.maxHeight;
                if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
                  return const SizedBox.shrink();
                }
                // Cap the distortion band so it never exceeds half the
                // shorter dimension. On small pills (h≈70 px) the global
                // 62 px value would span almost the entire surface, making
                // the refraction sample outside the captured texture and
                // producing a black bar at the top edge.
                final double effectiveDistortionWidth = min(
                  CASILiquidGlass.distortionWidth,
                  min(w, h) / 2 - 4.0,
                );
                return LiquidGlassView(
                  pixelRatio: CASILiquidGlass.pixelRatio,
                  realTimeCapture: true,
                  backgroundWidget: _AlignedWallpaperBackdrop(
                    wallpaper: widget.backgroundWidget,
                    screenSize: screenSize,
                    screenOffset: _screenOffset,
                  ),
                  children: [
                    LiquidGlass(
                      width: w,
                      height: h,
                      magnification: CASILiquidGlass.magnification,
                      distortion: widget.distortionOverride ??
                          CASILiquidGlass.distortion,
                      distortionWidth: effectiveDistortionWidth,
                      chromaticAberration:
                          CASILiquidGlass.chromaticAberration,
                      blur: LiquidGlassBlur(
                        sigmaX: CASILiquidGlass.edgeBlurSigma,
                        sigmaY: CASILiquidGlass.edgeBlurSigma,
                      ),
                      color: tint,
                      shape: RoundedRectangleShape(
                        cornerRadius: widget.cornerRadius,
                      ),
                      position: LiquidGlassAlignPosition(
                        alignment: Alignment.center,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        // Hairline specular border — defines the glass edge without
        // adding a flat tint on top of the refraction.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: border,
                  width: CASILiquidGlass.borderWidth,
                ),
              ),
            ),
          ),
        ),
        // Content drives the Stack's intrinsic size.
        Padding(
          padding: widget.padding ?? EdgeInsets.zero,
          child: widget.child,
        ),
      ],
    );

    if (widget.width != null || widget.height != null) {
      surface = SizedBox(
        width: widget.width,
        height: widget.height,
        child: surface,
      );
    }
    if (widget.margin != null) {
      surface = Padding(padding: widget.margin!, child: surface);
    }
    return RepaintBoundary(child: surface);
  }
}

/// Renders [wallpaper] at full screen size inside a parent that's sized to
/// the surface's bounds, translated by [-screenOffset] so the visible slice
/// matches what's actually behind the surface on screen. Without this, the
/// package would scale the wallpaper to fit the surface — refraction would
/// pick up a squished copy of the whole image instead of the slice behind
/// it.
class _AlignedWallpaperBackdrop extends StatelessWidget {
  final Widget wallpaper;
  final Size screenSize;
  final Offset screenOffset;

  const _AlignedWallpaperBackdrop({
    required this.wallpaper,
    required this.screenSize,
    required this.screenOffset,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: screenSize.width,
        maxWidth: screenSize.width,
        minHeight: screenSize.height,
        maxHeight: screenSize.height,
        child: Transform.translate(
          offset: -screenOffset,
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: wallpaper,
          ),
        ),
      ),
    );
  }
}

// ─── 7. Motion & Animation ──────────────────────────────────────────────────

/// Animation duration tokens.
class CASIMotion {
  CASIMotion._();

  static const Duration instant = Duration.zero;
  static const Duration micro = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration expressive = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration crawl = Duration(milliseconds: 600);

  // Easing curves (Flutter equivalents of the cubic beziers)
  static const Curve easeEnter = Curves.decelerate;          // Elements entering
  static const Curve easeExit = Curves.easeIn;               // Elements leaving
  static const Curve easeStandard = Curves.fastOutSlowIn;    // Moving within screen
}

// ─── 10. Iconography ─────────────────────────────────────────────────────────

/// Icon size scale.
class CASIIcons {
  CASIIcons._();

  static const double micro = 14;    // Inline status indicators
  static const double small = 18;    // Secondary actions, chip icons
  static const double standard = 22; // Navigation, toolbar, list leading
  static const double large = 28;    // Primary feature icons
  static const double xl = 40;       // Onboarding, hero moments
}

// ─── 8. Core Component Specs ────────────────────────────────────────────────

/// Search bar dimensions (section 8.2). Blur/tint come from the unified
/// glass material — this spec only owns geometry.
class CASISearchBarSpec {
  CASISearchBarSpec._();

  static const double height = 52;
  static const double cornerRadius = 28;   // Pill shape
  static const double horizontalPadding = 20;
  static const double iconSize = 20;
}

/// App icon / drawer row specs (section 4.4, 8.3).
class CASIAppIconSpec {
  CASIAppIconSpec._();

  static const double iconStandard = 48;    // Standard icon size
  static const double iconCompact = 40;     // Compact list
  static const double iconFeatured = 56;    // Featured
  static const double touchTarget = 64;     // Minimum touch target
  static const double labelToIconGap = 6;   // Gap below icon to label
  static const double rowHeight = 72;       // Preferred row height (64 min)
  static const double iconToLabelPadding = 16; // space.md
}

// ─── 6b. GlassSurface Widget ────────────────────────────────────────────────

/// The single visionOS-style frosted-glass surface used everywhere in the
/// app. Every frosted widget in CASI should be built on top of this — no
/// raw [BackdropFilter] + [ImageFilter.blur] in feature code.
///
/// The material is uniform (blur 22, 0.5 px @ 8% white border, no shadow,
/// tint biased faintly toward the wallpaper accent). The only per-surface
/// knob is the tint *opacity*, which comes from [GlassRole] or an explicit
/// [opacity] override.
///
/// Wraps its subtree in a [RepaintBoundary] to isolate the blur's repaint
/// cost from the rest of the widget tree.
class GlassSurface extends StatelessWidget {
  /// Child widget placed inside the glass container.
  final Widget child;

  /// Tint opacity — the fraction of the (white + accent) tint shown. Use
  /// [GlassRole] values where possible; this parameter lets ad-hoc
  /// surfaces opt into a specific spec opacity without inventing a role.
  final double opacity;

  /// Corner radius. Shape is NOT part of the glass material (dock is pill,
  /// drawer is rounded-top sheet, cards are 16, etc.), so each call site
  /// picks the right radius for its context.
  final double cornerRadius;

  /// Optional directional corner radii (e.g. rounded-top bottom sheets).
  /// When non-null, takes precedence over [cornerRadius].
  final BorderRadiusGeometry? borderRadiusOverride;

  /// Padding inside the glass container (applied to [child]).
  final EdgeInsetsGeometry? padding;

  /// Margin outside the glass container.
  final EdgeInsetsGeometry? margin;

  /// Optional fixed width.
  final double? width;

  /// Optional fixed height.
  final double? height;

  /// Replaces the standard tint color with an arbitrary color (e.g. for
  /// hover or active states that need to flash a semantic color through
  /// the glass). The provided color should already include its alpha.
  final Color? tintOverride;

  /// Replaces the standard border color. Pass a semantic color when a
  /// surface needs to highlight (drag-target hover, destructive action,
  /// etc.). Defaults to white @ 8% opacity.
  final Color? borderOverride;

  const GlassSurface({
    super.key,
    required this.child,
    this.opacity = 0.12,
    this.cornerRadius = CASIGlass.cornerStandard,
    this.borderRadiusOverride,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.tintOverride,
    this.borderOverride,
  });

  // ── Role factories ────────────────────────────────────────────────────

  factory GlassSurface.dock({
    Key? key,
    required Widget child,
    double cornerRadius = CASIGlass.cornerStandard,
    BorderRadiusGeometry? borderRadiusOverride,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      GlassSurface(
        key: key,
        opacity: GlassRole.dock.opacity,
        cornerRadius: cornerRadius,
        borderRadiusOverride: borderRadiusOverride,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory GlassSurface.drawer({
    Key? key,
    required Widget child,
    double cornerRadius = CASIGlass.cornerSheet,
    BorderRadiusGeometry? borderRadiusOverride,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      GlassSurface(
        key: key,
        opacity: GlassRole.drawer.opacity,
        cornerRadius: cornerRadius,
        borderRadiusOverride: borderRadiusOverride,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory GlassSurface.foresight({
    Key? key,
    required Widget child,
    double cornerRadius = CASIGlass.cornerPill,
    BorderRadiusGeometry? borderRadiusOverride,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      GlassSurface(
        key: key,
        opacity: GlassRole.foresight.opacity,
        cornerRadius: cornerRadius,
        borderRadiusOverride: borderRadiusOverride,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory GlassSurface.pill({
    Key? key,
    required Widget child,
    double cornerRadius = CASIGlass.cornerPill,
    BorderRadiusGeometry? borderRadiusOverride,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      GlassSurface(
        key: key,
        opacity: GlassRole.pill.opacity,
        cornerRadius: cornerRadius,
        borderRadiusOverride: borderRadiusOverride,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  factory GlassSurface.modal({
    Key? key,
    required Widget child,
    double cornerRadius = CASIGlass.cornerModal,
    BorderRadiusGeometry? borderRadiusOverride,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double? width,
    double? height,
    Color? tintOverride,
    Color? borderOverride,
  }) =>
      GlassSurface(
        key: key,
        opacity: GlassRole.modal.opacity,
        cornerRadius: cornerRadius,
        borderRadiusOverride: borderRadiusOverride,
        padding: padding,
        margin: margin,
        width: width,
        height: height,
        tintOverride: tintOverride,
        borderOverride: borderOverride,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: GlassPalette.accent,
      builder: (context, accent, _) {
        final BorderRadiusGeometry radius =
            borderRadiusOverride ?? BorderRadius.circular(cornerRadius);

        // Unified tint: mostly white with a faint accent bleed, then
        // scaled to the requested per-surface opacity.
        final Color baseTint =
            Color.lerp(Colors.white, accent, CASIGlass.accentMix) ??
                Colors.white;
        final Color tint = tintOverride ?? baseTint.withValues(alpha: opacity);
        final Color border = borderOverride ??
            Colors.white.withValues(alpha: CASIGlass.borderAlpha);

        Widget surface = ClipRRect(
          borderRadius: radius is BorderRadius
              ? radius
              : BorderRadius.circular(cornerRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: CASIGlass.blur,
              sigmaY: CASIGlass.blur,
            ),
            child: Container(
              width: width,
              height: height,
              padding: padding,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: radius is BorderRadius
                    ? radius
                    : BorderRadius.circular(cornerRadius),
                border: Border.all(
                  color: border,
                  width: CASIGlass.borderWidth,
                ),
              ),
              child: child,
            ),
          ),
        );

        if (margin != null) {
          surface = Padding(padding: margin!, child: surface);
        }

        return RepaintBoundary(child: surface);
      },
    );
  }
}
