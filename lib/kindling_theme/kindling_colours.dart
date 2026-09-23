import 'package:flutter/material.dart';

import 'kindling_theme_config.dart';

/// Kindling Tools colour palette.
///
/// Use [KindlingColours.fromConfig] to generate a palette from a
/// [KindlingThemeConfig], or use the static default colors directly.
class KindlingColours {
  const KindlingColours._(this.config);

  /// Create a colour palette from a theme configuration
  factory KindlingColours.fromConfig(KindlingThemeConfig config) {
    return KindlingColours._(config);
  }
  final KindlingThemeConfig config;

  // ============ SURFACES ============

  /// Page background
  static const Color background = Color(0xFFF8FAFC);

  /// Cards and modals
  static const Color surface = Color(0xFFFFFFFF);

  /// Soft brand panel background (derived from primary)
  Color get surfaceBrand => primary.withAlpha(25);

  /// Border color
  static const Color border = Color(0xFFE5E7EB);

  // ============ TEXT ============

  /// Primary text color
  static const Color textPrimary = Color(0xFF111827);

  /// Secondary text color
  static const Color textSecondary = Color(0xFF4B5563);

  /// Text on brand/primary buttons
  static const Color textOnBrand = Color(0xFFFFFFFF);

  /// Text on success backgrounds
  static const Color textOnSuccess = Color(0xFF5A3B00);

  /// Dark ink color
  static const Color ink = Color(0xFF241C34);

  // ============ BRAND / INTERACTIVE ============

  /// Primary brand color - used for CTAs and key actions
  Color get primary => config.primary;

  /// Primary pressed state
  Color get primaryPressed => _darken(config.primary, 0.1);

  /// Secondary brand color
  Color get secondary => config.secondary;

  /// Focus ring color
  Color get focusRing => config.primary.withAlpha(100);

  // ============ SEMANTIC COLORS ============

  /// Success color (positive feedback)
  Color get success => config.success;

  /// Success pressed state
  Color get successPressed => _darken(config.success, 0.1);

  /// Success background for chips/panels
  Color get successSurface => config.success.withAlpha(50);

  /// Warning color
  Color get warning => config.warning;

  /// Error color (negative feedback)
  Color get error => config.error;

  /// Error pressed state
  Color get errorPressed => _darken(config.error, 0.1);

  /// Error background for chips/panels
  Color get errorSurface => config.error.withAlpha(50);

  // ============ PROGRESS / UI ACCENTS ============

  /// Progress bar track
  static const Color progressTrack = Color(0xFFE5E7EB);

  /// Progress bar fill (uses primary)
  Color get progressFill => config.primary;

  /// Inactive dot
  static const Color dotInactive = Color(0xFFD1D5DB);

  /// Active dot (uses primary)
  Color get dotActive => config.primary;

  // ============ HELPERS ============

  /// Darken a color by a percentage (0.0 - 1.0)
  static Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Lighten a color by a percentage (0.0 - 1.0)
  static Color lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}
