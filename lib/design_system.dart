import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

// =============================================================================
// CASI Design System — Flutter Implementation
// Translated from the CASI Design System v1.0 Living Document
// =============================================================================

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

  // Glass surface colors (white with alpha)
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

// ─── 5. Elevation & Depth ────────────────────────────────────────────────────

/// Glass elevation levels — opacity increases with elevation.
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

// ─── 6. The Frosted Glass System ─────────────────────────────────────────────

/// Glass variant definitions.
class CASIGlass {
  CASIGlass._();

  // Blur radii (sigmaX/sigmaY for Flutter's ImageFilter.blur)
  static const double blurStandard = 20;   // Home screen cards, app drawer
  static const double blurHeavy = 32;      // Search bar, AI card, active states
  static const double blurLight = 12;      // Subtle groupings, hover
  static const double blurSheet = 40;      // Bottom sheets, drawers, modals
  static const double blurFrosted = 48;    // Critical modals, confirmation dialogs
  static const double blurBackground = 30; // App drawer background

  // Tint alpha values
  static const double tintStandard = 0.12; // Standard glass cards
  static const double tintHeavy = 0.18;    // Search bar, AI card
  static const double tintLight = 0.08;    // Subtle groupings
  static const double tintSheet = 0.20;    // Bottom sheets
  static const double tintFrosted = 0.24;  // Critical modals

  // Corner radii
  static const double cornerStandard = 16; // Standard cards
  static const double cornerChip = 8;      // Small chips/tags
  static const double cornerPill = 50;     // Pill shape (search bar)
  static const double cornerSheet = 24;    // Bottom sheets (top corners)
  static const double cornerModal = 24;    // Modals
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

/// Search bar dimensions (section 8.2).
class CASISearchBarSpec {
  CASISearchBarSpec._();

  static const double height = 52;
  static const double cornerRadius = 28;   // Pill shape
  static const double horizontalPadding = 20;
  static const double iconSize = 20;
  static const double focusBorderWidth = 1.5;
  static const double blurRadius = 24;     // Heavier than standard
  static const double tintAlpha = 0.18;    // glass.heavy
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

// ─── 6b. Glass Surface Widget ───────────────────────────────────────────────

/// Reusable frosted glass container that encapsulates the
/// ClipRRect → BackdropFilter → Container pattern from the design system.
///
/// Supports adaptive opacity via [tintMultiplier] and [borderMultiplier]
/// which are driven by wallpaper brightness analysis.
///
/// Wrapped in [RepaintBoundary] to isolate blur repaint cost from
/// surrounding widget tree, helping maintain 60fps on all devices.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final double tintAlpha;
  final double borderAlpha;
  final double cornerRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Multiplier from wallpaper brightness (1.0 = no adjustment).
  final double tintMultiplier;
  final double borderMultiplier;

  /// Optional explicit background color override (e.g. for hover states).
  final Color? colorOverride;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = CASIGlass.blurStandard,
    this.tintAlpha = CASIGlass.tintStandard,
    this.borderAlpha = 0.06,
    this.cornerRadius = CASIGlass.cornerStandard,
    this.padding,
    this.margin,
    this.tintMultiplier = 1.0,
    this.borderMultiplier = 1.0,
    this.colorOverride,
  });

  /// Convenience: card elevation glass surface.
  factory GlassSurface.card({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    double tintMultiplier = 1.0,
    double borderMultiplier = 1.0,
  }) {
    return GlassSurface(
      key: key,
      blur: CASIGlass.blurStandard,
      tintAlpha: CASIElevation.card.bgAlpha,
      borderAlpha: CASIElevation.card.borderAlpha,
      padding: padding,
      margin: margin,
      tintMultiplier: tintMultiplier,
      borderMultiplier: borderMultiplier,
      child: child,
    );
  }

  /// Convenience: sheet / modal elevation glass surface.
  factory GlassSurface.sheet({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry? padding,
    double tintMultiplier = 1.0,
    double borderMultiplier = 1.0,
  }) {
    return GlassSurface(
      key: key,
      blur: CASIGlass.blurSheet,
      tintAlpha: CASIGlass.tintSheet,
      borderAlpha: CASIElevation.float_.borderAlpha,
      cornerRadius: CASIGlass.cornerSheet,
      padding: padding,
      tintMultiplier: tintMultiplier,
      borderMultiplier: borderMultiplier,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTint = colorOverride ??
        Colors.white.withValues(
          alpha: (tintAlpha * tintMultiplier).clamp(0.0, 0.6),
        );
    final effectiveBorder = Colors.white.withValues(
      alpha: (borderAlpha * borderMultiplier).clamp(0.0, 0.5),
    );

    Widget surface = ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: effectiveTint,
            borderRadius: BorderRadius.circular(cornerRadius),
            border: Border.all(color: effectiveBorder, width: 1.0),
          ),
          child: child,
        ),
      ),
    );

    if (margin != null) {
      surface = Padding(padding: margin!, child: surface);
    }

    return RepaintBoundary(child: surface);
  }
}
