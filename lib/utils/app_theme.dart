import 'package:flutter/material.dart';

import '../kindling_theme/kindling_theme.dart';

// Re-export the Kindling theme so screens only ever import this file.
export '../kindling_theme/kindling_theme.dart';

/// Silly Soup's slice of the Kindling palette.
///
/// Bright but calm: warm kitchen colours, nothing that flashes or shouts.
const sillySoupThemeConfig = KindlingThemeConfig(
  primary: Color(0xFFFF7A45), // Carrot orange
  secondary: Color(0xFF7FC8A9), // Herb green
  warning: Color(0xFFFFB03A), // Amber
);

final sillySoupKindlingTheme = KindlingTheme.fromConfig(sillySoupThemeConfig);

/// Silly Soup colours.
class SoupColours {
  // ============ SURFACES ============
  static const Color background = Color(0xFFFFF7EE);
  static const Color surface = KindlingColours.surface;
  static const Color border = KindlingColours.border;

  // ============ TEXT ============
  static const Color textPrimary = KindlingColours.textPrimary;
  static const Color textSecondary = KindlingColours.textSecondary;
  static const Color textOnBrand = KindlingColours.textOnBrand;

  // ============ BRAND ============
  static const Color primary = Color(0xFFFF7A45);
  static const Color primaryPressed = Color(0xFFE8672F);
  static const Color secondary = Color(0xFF7FC8A9);
  static const Color gold = Color(0xFFFFC84A);

  // ============ KITCHEN ============
  /// The soup itself.
  static const Color broth = Color(0xFFF7A93B);
  static const Color brothLight = Color(0xFFFFC66B);

  /// The pan.
  static const Color pot = Color(0xFF4F5D75);
  static const Color potDark = Color(0xFF3C4759);
  static const Color potRim = Color(0xFF6B7A99);

  /// The pantry shelf.
  static const Color shelf = Color(0xFFE3C9A5);
  static const Color shelfDark = Color(0xFFC9A87C);

  /// The sound card the chef holds up.
  static const Color soundCard = Color(0xFFFFF0D9);

  /// Mouth close-up.
  static const Color skin = Color(0xFFF6D3B5);
  static const Color mouthInside = Color(0xFF8C4A52);
  static const Color lips = Color(0xFFD97A7A);
  static const Color teeth = Color(0xFFFFFDF7);
  static const Color tongue = Color(0xFFE38A94);
}

/// Sizes that matter for small hands and big rooms.
class SoupMetrics {
  /// Minimum tap target. Well above the 48dp Material floor because the
  /// people using this are three.
  static const double minTapTarget = 72;

  /// Ingredient tile size in a normal session.
  static const double ingredientSize = 104;

  /// Ingredient tile size on a whiteboard.
  static const double ingredientSizeWhiteboard = 156;

  static const double cardRadius = 24;

  /// Scale everything up for an adult-led session on a big screen.
  static double scale(bool whiteboardMode) => whiteboardMode ? 1.45 : 1.0;

  static double ingredient(bool whiteboardMode) =>
      whiteboardMode ? ingredientSizeWhiteboard : ingredientSize;
}

/// Silly Soup typography, on top of the Kindling scale.
class SoupTypography {
  static final _typography = sillySoupKindlingTheme.typography;

  /// The sound on the chef's card: "sss".
  static TextStyle soundDisplay(BuildContext context) =>
      _typography.displayLarge;

  /// The chef's speech bubble.
  static TextStyle chefSpeech(BuildContext context) => _typography.bodyLarge;

  static TextStyle heading(BuildContext context) => _typography.headlineLarge;

  static TextStyle subheading(BuildContext context) => _typography.secondary;

  static TextStyle body(BuildContext context) => _typography.bodyMedium;

  static TextStyle button(BuildContext context) => _typography.button;

  static TextStyle label(BuildContext context) => _typography.labelMedium;
}

/// The app theme.
class AppTheme {
  static ThemeData get lightTheme => sillySoupKindlingTheme.lightTheme.copyWith(
    scaffoldBackgroundColor: SoupColours.background,
  );
}

/// Responsive breakpoints — alias for [KindlingBreakpoints].
typedef Breakpoints = KindlingBreakpoints;
