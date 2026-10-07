import 'package:flutter/material.dart';

import 'kindling_colours.dart';
import 'kindling_theme_config.dart';

/// Kindling Tools typography configuration.
///
/// Provides a consistent type scale that can be customized with different
/// font families. The family is bundled and declared in pubspec.yaml, so
/// nothing is fetched at runtime.
class KindlingTypography {
  const KindlingTypography._(this.config);

  /// Create typography from a theme configuration
  factory KindlingTypography.fromConfig(KindlingThemeConfig config) {
    return KindlingTypography._(config);
  }
  final KindlingThemeConfig config;

  /// A TextStyle in the configured (bundled) family.
  TextStyle _font({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: config.fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? KindlingColours.textPrimary,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // ============ DISPLAY STYLES ============

  /// Large display text (48-72pt for prominent content)
  TextStyle get displayLarge =>
      _font(fontSize: 56, fontWeight: FontWeight.w500, letterSpacing: 2);

  /// Medium display text
  TextStyle get displayMedium =>
      _font(fontSize: 36, fontWeight: FontWeight.w500, letterSpacing: 1.5);

  /// Small display text
  TextStyle get displaySmall =>
      _font(fontSize: 28, fontWeight: FontWeight.w500, letterSpacing: 1);

  // ============ HEADLINE STYLES ============

  /// Large headline (page titles)
  TextStyle get headlineLarge =>
      _font(fontSize: 28, fontWeight: FontWeight.w600);

  /// Medium headline (section titles)
  TextStyle get headlineMedium =>
      _font(fontSize: 24, fontWeight: FontWeight.w600);

  /// Small headline (card titles)
  TextStyle get headlineSmall =>
      _font(fontSize: 20, fontWeight: FontWeight.w600);

  // ============ TITLE STYLES ============

  /// Large title
  TextStyle get titleLarge => _font(fontSize: 18, fontWeight: FontWeight.w500);

  /// Medium title
  TextStyle get titleMedium => _font(fontWeight: FontWeight.w500);

  /// Small title
  TextStyle get titleSmall => _font(fontSize: 14, fontWeight: FontWeight.w500);

  // ============ BODY STYLES ============

  /// Large body text
  TextStyle get bodyLarge => _font(fontSize: 18);

  /// Medium body text (default)
  TextStyle get bodyMedium => _font();

  /// Small body text
  TextStyle get bodySmall => _font(fontSize: 14);

  // ============ LABEL STYLES ============

  /// Large label (buttons)
  TextStyle get labelLarge => _font(fontSize: 18, fontWeight: FontWeight.w500);

  /// Medium label
  TextStyle get labelMedium => _font(fontSize: 14, fontWeight: FontWeight.w500);

  /// Small label
  TextStyle get labelSmall => _font(fontSize: 12, fontWeight: FontWeight.w500);

  // ============ SPECIAL STYLES ============

  /// Score/stat display text
  TextStyle get scoreDisplay =>
      _font(fontSize: 48, fontWeight: FontWeight.w600);

  /// Percentage display text
  TextStyle get percentage => _font(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    color: KindlingColours.textSecondary,
  );

  /// Secondary/muted text style
  TextStyle get secondary => _font(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: KindlingColours.textSecondary,
  );

  // ============ BUTTON TEXT ============

  /// Button text (white for primary buttons)
  TextStyle get button =>
      _font(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white);

  // ============ TEXT THEME ============

  /// Generate a Flutter TextTheme from this typography
  TextTheme get textTheme => TextTheme(
    displayLarge: displayLarge,
    displayMedium: displayMedium,
    displaySmall: displaySmall,
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );
}
