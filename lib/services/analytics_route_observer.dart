import 'package:flutter/widgets.dart';

import 'analytics_service.dart';

/// Reports a screen view whenever the navigator settles on a new screen.
///
/// Doing this from the navigator rather than from each screen's `initState`
/// means going *back* counts too: a child who leaves a soup returns to the
/// sound picker, and that is a screen view the picker itself never hears
/// about.
///
/// Only named routes are reported. Anything pushed without a name — a
/// dialog, a sheet — is deliberately invisible here.
class AnalyticsRouteObserver extends NavigatorObserver {
  AnalyticsRouteObserver(this._analytics);

  /// The name the app's first route arrives with. Reported as `home`.
  static const String homeRoute = '/';

  final AnalyticsService _analytics;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _report(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _report(newRoute);

  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    _analytics.logScreenView(name == homeRoute ? 'home' : name);
  }
}
