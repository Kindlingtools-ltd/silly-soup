import 'package:flutter/material.dart';

/// Kindling Tools responsive breakpoints.
///
/// Provides consistent breakpoint values and helper methods for
/// building responsive layouts across different screen sizes.
class KindlingBreakpoints {
  /// Phone portrait width
  static const double compactWidth = 500;

  /// Phone landscape / small tablet width
  static const double mediumWidth = 700;

  /// Tablet landscape / desktop width
  static const double expandedWidth = 900;

  /// Minimum comfortable height for full layouts (below this, content should scroll)
  static const double minComfortableHeight = 450;

  /// Returns true if we should use a wide (side-by-side) layout.
  /// Only true if screen is BOTH landscape AND wide enough.
  static bool shouldUseWideLayout(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    return isLandscape && size.width >= mediumWidth;
  }

  /// Returns true if orientation is landscape (regardless of width)
  static bool isLandscape(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height;
  }

  /// Returns true for tablet-sized screens
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.width >= mediumWidth;
  }

  /// Returns true for tablet in landscape
  static bool isTabletLandscape(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width >= expandedWidth && size.width > size.height;
  }

  /// Returns true for small/phone screens
  static bool isCompact(BuildContext context) {
    return MediaQuery.of(context).size.width < compactWidth;
  }

  /// Get responsive padding based on screen width
  static double getHorizontalPadding(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < compactWidth) return 16;
    if (width < mediumWidth) return 24;
    return 32;
  }

  /// Get responsive content max width
  static double getMaxContentWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < compactWidth) return double.infinity;
    if (width < mediumWidth) return 600;
    if (width < expandedWidth) return 800;
    return 1000;
  }

  /// Get responsive card spacing
  static double getCardSpacing(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < compactWidth) return 12;
    if (width < mediumWidth) return 16;
    return 24;
  }

  /// Returns true if viewport height is constrained (e.g., landscape mobile web with browser chrome)
  static bool isHeightConstrained(BuildContext context) {
    return MediaQuery.of(context).size.height < minComfortableHeight;
  }

  /// Get responsive vertical spacing based on available height.
  /// Returns [compact] spacing when height is constrained, [normal] otherwise.
  static double getVerticalSpacing(
    BuildContext context, {
    double normal = 24,
    double compact = 12,
  }) {
    return isHeightConstrained(context) ? compact : normal;
  }
}
