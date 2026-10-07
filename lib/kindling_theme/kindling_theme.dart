// Kindling Tools Flutter Theme
//
// A reusable, configurable theme system for Kindling Tools apps.
//
// Quick Start:
//
// ```dart
// import 'package:your_app/kindling_theme/kindling_theme.dart';
//
// final config = KindlingThemeConfig(
//   primary: Color(0xFFFF66C4),
//   secondary: Color(0xFFCEA8F0),
//   fontFamily: 'Poppins',
// );
//
// MaterialApp(
//   theme: KindlingTheme.fromConfig(config).lightTheme,
//   // ...
// );
// ```

import 'package:flutter/material.dart';

import 'kindling_colours.dart';
import 'kindling_theme_config.dart';
import 'kindling_typography.dart';

// Export all theme components
export 'kindling_breakpoints.dart';
export 'kindling_colours.dart';
export 'kindling_theme_config.dart';
export 'kindling_typography.dart';

/// Kindling Tools theme generator.
///
/// Create a [KindlingTheme] from a [KindlingThemeConfig] and access the
/// generated [ThemeData] via [lightTheme]. A dark theme may follow.
class KindlingTheme {
  KindlingTheme._({
    required this.config,
    required this.colours,
    required this.typography,
  });

  /// Create a KindlingTheme from a configuration
  factory KindlingTheme.fromConfig(KindlingThemeConfig config) {
    return KindlingTheme._(
      config: config,
      colours: KindlingColours.fromConfig(config),
      typography: KindlingTypography.fromConfig(config),
    );
  }
  final KindlingThemeConfig config;
  final KindlingColours colours;
  final KindlingTypography typography;

  /// Generate a Material 3 light theme from the configuration
  ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      // Without this, any text the app does not style explicitly falls to
      // Material's default family and the engine fetches Roboto — 62KB from
      // fonts.gstatic.com, on a page that promises no third-party requests.
      fontFamily: config.fontFamily,
      scaffoldBackgroundColor: KindlingColours.background,
      colorScheme: ColorScheme.light(
        primary: colours.primary,
        secondary: colours.secondary,
        error: colours.error,
      ),
      textTheme: typography.textTheme,
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: KindlingColours.surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: TextStyle(
            fontFamily: config.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: TextStyle(
            fontFamily: config.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: KindlingColours.background,
        foregroundColor: KindlingColours.textPrimary,
        titleTextStyle: TextStyle(
          fontFamily: config.fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: KindlingColours.textPrimary,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colours.progressFill,
        linearTrackColor: KindlingColours.progressTrack,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colours.primary;
          }
          return Colors.grey.shade400;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colours.primary.withAlpha(128);
          }
          return Colors.grey.shade300;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KindlingColours.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KindlingColours.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colours.primary, width: 2),
        ),
        filled: true,
        fillColor: KindlingColours.surface,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: KindlingColours.surface,
        selectedColor: colours.primary.withAlpha(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: KindlingColours.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: KindlingColours.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // Future: Add darkTheme getter
  // ThemeData get darkTheme => ...
}
