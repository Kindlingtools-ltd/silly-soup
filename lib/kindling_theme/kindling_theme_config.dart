import 'package:flutter/material.dart';

/// Kindling Tools theme configuration.
///
/// Apps can customize the theme by providing their own brand colors
/// and typography preferences.
///
/// Example:
/// ```dart
/// final config = KindlingThemeConfig(
///   primary: Color(0xFFFF66C4),
///   secondary: Color(0xFFCEA8F0),
///   fontFamily: 'Poppins',
/// );
/// ```
class KindlingThemeConfig {
  const KindlingThemeConfig({
    required this.primary,
    required this.secondary,
    this.success = const Color(0xFFFFC84A),
    this.warning = const Color(0xFFFF7A45),
    this.error = const Color(0xFFFF66C4),
    this.fontFamily = 'Poppins',
  });

  /// Create a theme config from a single seed color.
  ///
  /// Automatically generates complementary colors for secondary,
  /// success, warning, and error states.
  factory KindlingThemeConfig.fromSeed(
    Color seedColor, {
    String fontFamily = 'Poppins',
  }) {
    final hsl = HSLColor.fromColor(seedColor);

    // Generate complementary colors by rotating hue
    final secondary = HSLColor.fromAHSL(
      1.0,
      (hsl.hue + 60) % 360,
      hsl.saturation * 0.8,
      hsl.lightness,
    ).toColor();

    // success and warning keep their constructor defaults — warm gold and
    // orange read the same against any seed.
    final error = HSLColor.fromAHSL(
      1.0,
      (hsl.hue + 180) % 360,
      hsl.saturation,
      hsl.lightness,
    ).toColor();

    return KindlingThemeConfig(
      primary: seedColor,
      secondary: secondary,
      error: error,
      fontFamily: fontFamily,
    );
  }

  /// Primary brand color - used for CTAs and key interactive elements
  final Color primary;

  /// Secondary brand color - used for accents and supporting elements
  final Color secondary;

  /// Success color - used for positive feedback (e.g., correct answers)
  final Color success;

  /// Warning color - used for cautionary states
  final Color warning;

  /// Error color - used for negative feedback (e.g., incorrect answers)
  final Color error;

  /// Font family name for typography (e.g., 'Poppins', 'Roboto')
  final String fontFamily;

  /// Copy this config with some values replaced
  KindlingThemeConfig copyWith({
    Color? primary,
    Color? secondary,
    Color? success,
    Color? warning,
    Color? error,
    String? fontFamily,
  }) {
    return KindlingThemeConfig(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      fontFamily: fontFamily ?? this.fontFamily,
    );
  }
}
